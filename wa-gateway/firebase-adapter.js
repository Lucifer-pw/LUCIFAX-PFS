const fs = require('fs');
const path = require('path');

class FirebaseAdapter {
  constructor() {
    this.mode = 'uninitialized';
    this.db = null;
    this.init();
  }

  init() {
    const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS 
      || path.join(__dirname, 'serviceAccountKey.json');

    if (fs.existsSync(serviceAccountPath)) {
      try {
        const admin = require('firebase-admin');
        const serviceAccount = require(serviceAccountPath);
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: serviceAccount.project_id || 'aplikasi-transaksi-fiva-frozen'
        });
        this.db = admin.firestore();
        this.admin = admin;
        this.mode = 'admin';
        console.log('[FIREBASE] Berhasil terhubung via Firebase Admin SDK (serviceAccountKey.json)');
        return;
      } catch (err) {
        console.warn('[FIREBASE] Gagal inisialisasi serviceAccountKey.json, beralih ke Client SDK:', err.message);
      }
    }

    // Fallback: Client SDK
    try {
      const { initializeApp } = require('firebase/app');
      const { 
        getFirestore, 
        doc, 
        setDoc, 
        collection, 
        addDoc, 
        onSnapshot, 
        serverTimestamp,
        updateDoc 
      } = require('firebase/firestore');
      const { getAuth, signInWithEmailAndPassword, signInAnonymously } = require('firebase/auth');

      const firebaseConfig = {
        apiKey: process.env.FIREBASE_API_KEY || "AIzaSyDLz_JIz7I7inIziST57QSkOoBjp42Tv40",
        authDomain: process.env.FIREBASE_AUTH_DOMAIN || "aplikasi-transaksi-fiva-frozen.firebaseapp.com",
        projectId: process.env.FIREBASE_PROJECT_ID || "aplikasi-transaksi-fiva-frozen",
        storageBucket: process.env.FIREBASE_STORAGE_BUCKET || "aplikasi-transaksi-fiva-frozen.firebasestorage.app",
        messagingSenderId: process.env.FIREBASE_MESSAGING_SENDER_ID || "388227024926",
        appId: process.env.FIREBASE_APP_ID || "1:388227024926:web:d9595a3ec0882e1814860f"
      };

      const app = initializeApp(firebaseConfig);
      this.clientDb = getFirestore(app);
      this.clientAuth = getAuth(app);
      this.clientSdk = { doc, setDoc, collection, addDoc, onSnapshot, serverTimestamp, updateDoc };
      this.mode = 'client';

      const email = process.env.FIREBASE_USER_EMAIL;
      const password = process.env.FIREBASE_USER_PASSWORD;

      if (email && password) {
        signInWithEmailAndPassword(this.clientAuth, email, password)
          .then(userCred => {
            console.log('[FIREBASE] Client SDK berhasil login sebagai:', userCred.user.email);
          })
          .catch(err => {
            console.warn('[FIREBASE] Gagal login email, mencoba anonymous/direct:', err.message);
          });
      } else {
        console.log('[FIREBASE] Berjalan via Firebase Client SDK (Web Config)');
      }
    } catch (err) {
      console.error('[FIREBASE ERROR] Gagal menginisialisasi Firebase:', err.message);
    }
  }

  async updateGatewayStatus(data) {
    const payload = {
      ...data,
      updatedAt: new Date(),
      lastHeartbeat: new Date()
    };

    if (this.mode === 'admin') {
      try {
        await this.db.collection('wa_bot_session').doc('gateway').set(payload, { merge: true });
        // Dual-write to wa_gateway_session for backward compatibility
        await this.db.collection('wa_gateway_session').doc('gateway').set(payload, { merge: true });
        if (payload.instanceId) {
          await this.db.collection('wa_gateway_nodes').doc(payload.instanceId).set({
            ...payload,
            updatedAt: new Date(),
            lastHeartbeat: new Date()
          }, { merge: true });
        }
      } catch (e) {
        console.error('[FIREBASE] Error updating status (Admin):', e.message);
      }
    } else if (this.mode === 'client') {
      try {
        const { doc, setDoc, serverTimestamp } = this.clientSdk;
        const cPayload = { ...payload, updatedAt: serverTimestamp(), lastHeartbeat: serverTimestamp() };
        await setDoc(doc(this.clientDb, 'wa_bot_session', 'gateway'), cPayload, { merge: true });
        await setDoc(doc(this.clientDb, 'wa_gateway_session', 'gateway'), cPayload, { merge: true });
        if (payload.instanceId) {
          await setDoc(doc(this.clientDb, 'wa_gateway_nodes', payload.instanceId), cPayload, { merge: true });
        }
      } catch (e) {
        console.error('[FIREBASE] Error updating status (Client):', e.message);
      }
    }
  }

  async claimMaster(instanceId, deviceName, devicePlatform) {
    const payload = {
      activeInstanceId: instanceId,
      activeDeviceName: deviceName,
      activeDevicePlatform: devicePlatform,
      claimedAt: new Date(),
      lastHeartbeat: new Date()
    };
    if (this.mode === 'admin') {
      try {
        await this.db.collection('wa_bot_session').doc('gateway_master').set(payload, { merge: true });
        await this.db.collection('wa_gateway_nodes').doc(instanceId).set({
          status: 'CONNECTED',
          updatedAt: new Date(),
          lastHeartbeat: new Date()
        }, { merge: true });
      } catch (e) {
        console.error('[FIREBASE] Error claiming master (Admin):', e.message);
      }
    } else if (this.mode === 'client') {
      try {
        const { doc, setDoc, serverTimestamp } = this.clientSdk;
        await setDoc(doc(this.clientDb, 'wa_bot_session', 'gateway_master'), {
          ...payload,
          claimedAt: serverTimestamp(),
          lastHeartbeat: serverTimestamp()
        }, { merge: true });
        await setDoc(doc(this.clientDb, 'wa_gateway_nodes', instanceId), {
          status: 'CONNECTED',
          updatedAt: serverTimestamp(),
          lastHeartbeat: serverTimestamp()
        }, { merge: true });
      } catch (e) {
        console.error('[FIREBASE] Error claiming master (Client):', e.message);
      }
    }
  }

  async sendHeartbeat(instanceId, deviceName, devicePlatform, deviceDetails = null, status = 'ONLINE') {
    const payload = {
      deviceName,
      devicePlatform,
      instanceId,
      status,
      lastHeartbeat: new Date()
    };
    if (deviceDetails) {
      payload.deviceDetails = deviceDetails;
    }
    if (this.mode === 'admin') {
      try {
        if (status === 'CONNECTED') {
          await this.db.collection('wa_bot_session').doc('gateway').set(payload, { merge: true });
          await this.db.collection('wa_bot_session').doc('gateway_master').set(payload, { merge: true });
          await this.db.collection('wa_gateway_session').doc('gateway').set(payload, { merge: true });
        }
        // Always record node in cluster list
        await this.db.collection('wa_gateway_nodes').doc(instanceId).set({
          ...payload,
          updatedAt: new Date()
        }, { merge: true });
      } catch (_) {}
    } else if (this.mode === 'client') {
      try {
        const { doc, setDoc, serverTimestamp } = this.clientSdk;
        const cPayload = { ...payload, lastHeartbeat: serverTimestamp(), updatedAt: serverTimestamp() };
        if (status === 'CONNECTED') {
          await setDoc(doc(this.clientDb, 'wa_bot_session', 'gateway'), cPayload, { merge: true });
          await setDoc(doc(this.clientDb, 'wa_bot_session', 'gateway_master'), cPayload, { merge: true });
        }
        await setDoc(doc(this.clientDb, 'wa_gateway_nodes', instanceId), cPayload, { merge: true });
      } catch (_) {}
    }
  }

  listenToMaster(currentInstanceId, onPreempted) {
    const checkDoc = (data) => {
      if (!data) return;
      const targetId = data.activeInstanceId || data.instanceId;
      if (targetId && targetId !== currentInstanceId) {
        onPreempted({
          activeInstanceId: targetId,
          activeDeviceName: data.activeDeviceName || data.deviceName || 'Perangkat Lain',
          claimedAt: data.claimedAt || data.lastConnectedAt || data.updatedAt,
          lastHeartbeat: data.lastHeartbeat || data.updatedAt
        });
      }
    };

    if (this.mode === 'admin') {
      this.db.collection('wa_bot_session').doc('gateway_master').onSnapshot(doc => {
        if (doc && doc.exists) checkDoc(doc.data());
      });
      this.db.collection('wa_bot_session').doc('gateway').onSnapshot(doc => {
        if (doc && doc.exists) {
          const d = doc.data();
          if (d && d.status === 'CONNECTED') checkDoc(d);
        }
      });
    } else if (this.mode === 'client') {
      const { doc, onSnapshot } = this.clientSdk;
      onSnapshot(doc(this.clientDb, 'wa_bot_session', 'gateway_master'), snap => {
        if (snap && snap.exists()) checkDoc(snap.data());
      });
      onSnapshot(doc(this.clientDb, 'wa_bot_session', 'gateway'), snap => {
        if (snap && snap.exists()) {
          const d = snap.data();
          if (d && d.status === 'CONNECTED') checkDoc(d);
        }
      });
    }
  }

  async saveIncomingChat(chatData) {
    const payload = {
      ...chatData,
      receivedAt: chatData.receivedAt || new Date(),
      status: 'pending',
      processedAt: null
    };

    if (this.mode === 'admin') {
      try {
        const res = await this.db.collection('incoming_po_chats').add(payload);
        // Dual-write to incoming_wa_orders for backward compatibility
        await this.db.collection('incoming_wa_orders').doc(res.id).set(payload);
        return res.id;
      } catch (e) {
        console.error('[FIREBASE] Error saving incoming chat (Admin):', e.message);
      }
    } else if (this.mode === 'client') {
      try {
        const { collection, addDoc, doc, setDoc, serverTimestamp } = this.clientSdk;
        const cPayload = { ...payload, receivedAt: chatData.receivedAt || serverTimestamp() };
        const res = await addDoc(collection(this.clientDb, 'incoming_po_chats'), cPayload);
        await setDoc(doc(this.clientDb, 'incoming_wa_orders', res.id), cPayload);
        return res.id;
      } catch (e) {
        console.error('[FIREBASE] Error saving incoming chat (Client):', e.message);
      }
    }
  }

  async loadRecentMessageIds() {
    const ids = new Set();
    try {
      if (this.mode === 'admin' && this.db) {
        const snap = await this.db.collection('incoming_po_chats')
          .orderBy('receivedAt', 'desc')
          .limit(100)
          .get();
        snap.forEach(doc => {
          const d = doc.data();
          if (d.messageId) ids.add(d.messageId);
          if (Array.isArray(d.messageIds)) {
            d.messageIds.forEach(id => ids.add(id));
          }
        });
      }
    } catch (_) {}
    return ids;
  }

  listenToCommands(onCommand) {
    let isExecuting = false;
    if (this.mode === 'admin') {
      this.db.collection('wa_bot_session').doc('gateway_command').onSnapshot(async doc => {
        if (doc.exists) {
          const data = doc.data();
          if (data && data.command && !data.executed && !isExecuting) {
            isExecuting = true;
            try {
              await doc.ref.update({ executed: true, executedAt: new Date() });
              onCommand(data.command, data);
            } finally {
              setTimeout(() => { isExecuting = false; }, 2000);
            }
          }
        }
      });
    } else if (this.mode === 'client') {
      const { doc, onSnapshot, updateDoc, serverTimestamp } = this.clientSdk;
      onSnapshot(doc(this.clientDb, 'wa_bot_session', 'gateway_command'), async snap => {
        if (snap.exists()) {
          const data = snap.data();
          if (data && data.command && !data.executed && !isExecuting) {
            isExecuting = true;
            try {
              await updateDoc(doc(this.clientDb, 'wa_bot_session', 'gateway_command'), {
                executed: true,
                executedAt: serverTimestamp()
              });
              onCommand(data.command, data);
            } finally {
              setTimeout(() => { isExecuting = false; }, 2000);
            }
          }
        }
      });
    }
  }

  listenToSettings(onSettings) {
    if (this.mode === 'admin') {
      this.db.collection('app_settings').doc('wa_auto_po_settings').onSnapshot(doc => {
        if (doc && doc.exists) {
          onSettings(doc.data());
        }
      });
      this.db.collection('wa_contacts').onSnapshot(snap => {
        const numbers = [];
        snap.forEach(d => {
          const p = (d.data().phone || '').replace(/\D/g, '');
          if (p) numbers.push(p);
        });
        onSettings({ additionalWhitelist: numbers });
      });
    } else if (this.mode === 'client') {
      const { doc, collection, onSnapshot } = this.clientSdk;
      onSnapshot(doc(this.clientDb, 'app_settings', 'wa_auto_po_settings'), snap => {
        if (snap && snap.exists()) {
          onSettings(snap.data());
        }
      });
      onSnapshot(collection(this.clientDb, 'wa_contacts'), snap => {
        const numbers = [];
        snap.forEach(d => {
          const p = (d.data().phone || '').replace(/\D/g, '');
          if (p) numbers.push(p);
        });
        onSettings({ additionalWhitelist: numbers });
      });
    }
  }
}

module.exports = new FirebaseAdapter();
