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
          projectId: serviceAccount.project_id || 'aplikasi-transaksi-fiva-frozen',
          storageBucket: 'aplikasi-transaksi-fiva-frozen.firebasestorage.app'
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

  async uploadReceiptImage(buffer, filename = `receipt_${Date.now()}.jpg`) {
    if (!buffer) return null;
    const destPath = `payment_receipts/${filename}`;
    const token = `receipt_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

    if (this.mode === 'admin' && this.admin) {
      try {
        const bucket = this.admin.storage().bucket();
        const file = bucket.file(destPath);
        await file.save(buffer, {
          metadata: {
            contentType: 'image/jpeg',
            metadata: {
              firebaseStorageDownloadTokens: token
            }
          }
        });
        const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destPath)}?alt=media&token=${token}`;
        console.log(`[FIREBASE STORAGE] 📸 Struk transfer berhasil diunggah: ${downloadUrl}`);
        return downloadUrl;
      } catch (err) {
        console.warn('[FIREBASE STORAGE ERROR] Gagal upload struk ke Firebase Storage:', err.message);
      }
    }
    return null;
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

  async findMatchingReceivable(customerHint, amount) {
    if (!amount || amount <= 0) return null;
    const cleanHint = (customerHint || '').toUpperCase().trim();

    try {
      let snap;
      if (this.mode === 'admin') {
        snap = await this.db.collection('receivables').get();
      } else if (this.mode === 'client') {
        const { collection, getDocs } = this.clientSdk;
        snap = await getDocs(collection(this.clientDb, 'receivables'));
      } else {
        return null;
      }

      const getInitials = (str) => {
        return str
          .replace(/[^A-Za-z0-9\s]/g, ' ')
          .split(/\s+/)
          .filter(Boolean)
          .map(w => w[0])
          .join('')
          .toUpperCase();
      };

      const candidates = [];
      snap.forEach(doc => {
        const d = doc.data();
        const toko = (d.toko || d.customerName || '').toUpperCase();
        const nominal = Number(d.nominal || d.totalTagihan || d.total || 0);
        const noInvoice = String(d.noInvoice || d.invoiceNo || '');
        const isLunas = !!d.isLunas;

        const amountDiff = Math.abs(nominal - amount);
        const isAmountMatch = amountDiff <= 100;

        if (!isAmountMatch) return;

        let nameMatch = false;
        if (cleanHint && toko) {
          const tokoInitials = getInitials(toko);
          const hintInitials = getInitials(cleanHint);

          if (cleanHint.includes(toko) || toko.includes(cleanHint)) {
            nameMatch = true;
          } else if (cleanHint === tokoInitials || hintInitials === cleanHint || tokoInitials === hintInitials) {
            nameMatch = true;
          } else {
            const hintWords = cleanHint.split(/\s+/).filter(w => w.length >= 4 && !['CV', 'PT', 'TOKO'].includes(w));
            if (hintWords.some(w => toko.includes(w))) {
              nameMatch = true;
            }
          }
        }

        if (nameMatch) {
          candidates.push({ noInvoice, toko, nominal, isLunas, docId: doc.id });
        }
      });

      const unpaid = candidates.find(c => !c.isLunas);
      if (unpaid) return unpaid;
      if (candidates.length > 0) return candidates[0];
      return null;
    } catch (err) {
      console.warn('[FIREBASE RECEIVABLE MATCH ERROR]:', err.message);
      return null;
    }
  }

  async settleInvoicePayment(invoiceNo, paymentData = {}) {
    const invClean = String(invoiceNo || '').replace(/\D/g, '').trim();
    if (!invClean) return { success: false };

    try {
      console.log(`[AUTO-SETTLE] Memproses pembayaran otomatis Faktur #${invClean}...`);
      const payAmount = Number(paymentData.amount) || 0;
      let effectiveNominal = 0;
      let newPaidAmount = payAmount;
      let willBeLunas = true;
      let remainingAfter = 0;
      let matchedReceivable = false;

      // 1. Process receivables update
      if (this.mode === 'admin') {
        const snap = await this.db.collection('receivables').where('noInvoice', '==', invClean).get();
        if (!snap.empty) {
          matchedReceivable = true;
          for (const d of snap.docs) {
            const existing = d.data();
            effectiveNominal = Number(existing.nominal || existing.totalTagihan || existing.total || 0);
            const currentPaid = Number(existing.paidAmount || (Array.isArray(existing.payments) ? existing.payments.reduce((sum, p) => sum + (Number(p.amount) || 0), 0) : 0));
            newPaidAmount = currentPaid + (payAmount > 0 ? payAmount : (effectiveNominal - currentPaid));
            willBeLunas = newPaidAmount >= (effectiveNominal - 1.0);
            remainingAfter = willBeLunas ? 0 : Math.max(0, effectiveNominal - newPaidAmount);

            const payments = Array.isArray(existing.payments) ? [...existing.payments] : [];
            payments.push({
              id: `pay_${Date.now()}`,
              amount: payAmount > 0 ? payAmount : effectiveNominal,
              date: new Date(),
              method: paymentData.bank ? `Transfer ${paymentData.bank}` : 'TRANSFER',
              notes: willBeLunas
                ? `Pelunasan otomatis via WhatsApp Gateway (${paymentData.bank || 'Transfer'})`
                : `Pembayaran Cicilan via WhatsApp Gateway (${paymentData.bank || 'Transfer'}) - Sisa Rp ${remainingAfter.toLocaleString('id-ID')}`,
              receiptUrl: paymentData.imageUrl || '',
              createdAt: new Date()
            });

            await d.ref.update({
              isLunas: willBeLunas,
              paidAmount: newPaidAmount,
              payments,
              updatedAt: new Date()
            });
          }
        }
      } else if (this.mode === 'client') {
        const { collection, query, where, getDocs, updateDoc } = this.clientSdk;
        const q = query(collection(this.clientDb, 'receivables'), where('noInvoice', '==', invClean));
        const snap = await getDocs(q);
        if (!snap.empty) {
          matchedReceivable = true;
          for (const d of snap.docs) {
            const existing = d.data();
            effectiveNominal = Number(existing.nominal || existing.totalTagihan || existing.total || 0);
            const currentPaid = Number(existing.paidAmount || (Array.isArray(existing.payments) ? existing.payments.reduce((sum, p) => sum + (Number(p.amount) || 0), 0) : 0));
            newPaidAmount = currentPaid + (payAmount > 0 ? payAmount : (effectiveNominal - currentPaid));
            willBeLunas = newPaidAmount >= (effectiveNominal - 1.0);
            remainingAfter = willBeLunas ? 0 : Math.max(0, effectiveNominal - newPaidAmount);

            const payments = Array.isArray(existing.payments) ? [...existing.payments] : [];
            payments.push({
              id: `pay_${Date.now()}`,
              amount: payAmount > 0 ? payAmount : effectiveNominal,
              date: new Date(),
              method: paymentData.bank ? `Transfer ${paymentData.bank}` : 'TRANSFER',
              notes: willBeLunas
                ? `Pelunasan otomatis via WhatsApp Gateway (${paymentData.bank || 'Transfer'})`
                : `Pembayaran Cicilan via WhatsApp Gateway (${paymentData.bank || 'Transfer'}) - Sisa Rp ${remainingAfter.toLocaleString('id-ID')}`,
              receiptUrl: paymentData.imageUrl || '',
              createdAt: new Date()
            });

            await updateDoc(d.ref, {
              isLunas: willBeLunas,
              paidAmount: newPaidAmount,
              payments,
              updatedAt: new Date()
            });
          }
        }
      }

      // If not in receivables yet, read transaction to check grandTotal
      if (!matchedReceivable) {
        let trSnap;
        if (this.mode === 'admin') {
          trSnap = await this.db.collection('transactions').doc(invClean).get();
        } else if (this.mode === 'client') {
          const { doc, getDoc } = this.clientSdk;
          trSnap = await getDoc(doc(this.clientDb, 'transactions', invClean));
        }
        if (trSnap && (trSnap.exists || (typeof trSnap.exists === 'function' && trSnap.exists()))) {
          const trData = trSnap.data();
          effectiveNominal = Number(trData.grandTotal || 0);
          if (effectiveNominal > 0 && payAmount > 0) {
            willBeLunas = payAmount >= (effectiveNominal - 1.0);
            remainingAfter = willBeLunas ? 0 : Math.max(0, effectiveNominal - payAmount);
          }
        }
      }

      // 2. Update transactions collection
      const updateData = {
        statusTransfer: willBeLunas ? 'PAID' : 'PARTIAL',
        transferDate: new Date(),
        transferReceiptUrl: paymentData.imageUrl || null,
        transferBankDetails: {
          bank: paymentData.bank || '',
          amount: payAmount,
          berita: paymentData.berita || '',
          refNo: paymentData.refNo || '',
          senderName: paymentData.senderName || '',
          settledAt: new Date().toISOString(),
          settleSource: 'WA_GATEWAY_AUTO_SETTLE',
          isPartial: !willBeLunas,
          remaining: remainingAfter,
          totalPaid: newPaidAmount,
          totalTagihan: effectiveNominal
        }
      };

      if (this.mode === 'admin') {
        await this.db.collection('transactions').doc(invClean).set(updateData, { merge: true });
      } else if (this.mode === 'client') {
        const { doc, setDoc } = this.clientSdk;
        await setDoc(doc(this.clientDb, 'transactions', invClean), updateData, { merge: true });
      }

      const statusLog = willBeLunas ? 'LUNAS PENUH' : `CICILAN (Sisa: Rp ${remainingAfter.toLocaleString('id-ID')})`;
      console.log(`[AUTO-SETTLE SUCCESS] 🎉 Faktur #${invClean} BERHASIL DIPROSES! Status: ${statusLog}`);
      return {
        success: true,
        isLunas: willBeLunas,
        remaining: remainingAfter,
        paidAmount: newPaidAmount,
        totalTagihan: effectiveNominal
      };
    } catch (err) {
      console.error(`[AUTO-SETTLE ERROR] Gagal memproses Faktur #${invClean}:`, err.message);
      return { success: false, error: err.message };
    }
  }
}

module.exports = new FirebaseAdapter();
