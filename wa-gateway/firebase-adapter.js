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
        if (!admin.apps.length) {
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
            projectId: serviceAccount.project_id || 'aplikasi-transaksi-fiva-frozen',
            storageBucket: 'aplikasi-transaksi-fiva-frozen.firebasestorage.app'
          });
        }
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
        getDoc,
        getDocs,
        setDoc, 
        collection, 
        query,
        where,
        limit,
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
      this.clientSdk = { 
        doc, 
        getDoc, 
        getDocs, 
        setDoc, 
        collection, 
        query, 
        where, 
        limit, 
        addDoc, 
        onSnapshot, 
        serverTimestamp, 
        updateDoc 
      };
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
            cacheControl: 'public, max-age=31536000',
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

  async findChatByMessageId(messageId) {
    if (!messageId) return null;
    try {
      if (this.mode === 'admin' && this.db) {
        let snap = await this.db.collection('incoming_po_chats')
          .where('messageId', '==', messageId)
          .limit(1)
          .get();
        if (!snap.empty) return { id: snap.docs[0].id, ...snap.docs[0].data() };

        snap = await this.db.collection('incoming_po_chats')
          .where('messageIds', 'array-contains', messageId)
          .limit(1)
          .get();
        if (!snap.empty) return { id: snap.docs[0].id, ...snap.docs[0].data() };
      } else if (this.mode === 'client' && this.clientDb) {
        const { collection, query, where, limit, getDocs } = this.clientSdk;
        const q = query(collection(this.clientDb, 'incoming_po_chats'), where('messageId', '==', messageId), limit(1));
        const snap = await getDocs(q);
        if (!snap.empty) return { id: snap.docs[0].id, ...snap.docs[0].data() };
      }
    } catch (e) {
      console.warn('[FIREBASE] findChatByMessageId notice:', e.message);
    }
    return null;
  }

  async updateChatDocument(chatId, updateData) {
    if (!chatId || !updateData) return false;
    try {
      if (this.mode === 'admin' && this.db) {
        await this.db.collection('incoming_po_chats').doc(chatId).update(updateData);
        return true;
      } else if (this.mode === 'client' && this.clientDb) {
        const { doc, updateDoc } = this.clientSdk;
        await updateDoc(doc(this.clientDb, 'incoming_po_chats', chatId), updateData);
        return true;
      }
    } catch (e) {
      console.warn('[FIREBASE] updateChatDocument notice:', e.message);
    }
    return false;
  }

  async findRecentPendingTransferSlip(senderPhone, senderJid, amount = 0) {
    try {
      if (this.mode === 'admin' && this.db) {
        const snap = await this.db.collection('incoming_po_chats')
          .where('messageType', '==', 'TRANSFER_SLIP')
          .where('status', '==', 'pending')
          .limit(10)
          .get();
        if (!snap.empty) {
          const match = snap.docs.find(d => {
            const data = d.data();
            const phoneMatch = senderPhone && (data.senderPhone === senderPhone);
            const jidMatch = senderJid && (data.senderJid === senderJid);
            const amountMatch = (!amount || amount <= 0) || (data.transferInfo && Math.abs(Number(data.transferInfo.amount || 0) - amount) <= 100);
            return (phoneMatch || jidMatch) && amountMatch;
          });
          if (match) return { id: match.id, ...match.data() };
        }
      } else if (this.mode === 'client' && this.clientDb) {
        const { collection, query, where, limit, getDocs } = this.clientSdk;
        const q = query(collection(this.clientDb, 'incoming_po_chats'), where('messageType', '==', 'TRANSFER_SLIP'), where('status', '==', 'pending'), limit(10));
        const snap = await getDocs(q);
        if (!snap.empty) {
          const match = snap.docs.find(d => {
            const data = d.data();
            const phoneMatch = senderPhone && (data.senderPhone === senderPhone);
            const jidMatch = senderJid && (data.senderJid === senderJid);
            const amountMatch = (!amount || amount <= 0) || (data.transferInfo && Math.abs(Number(data.transferInfo.amount || 0) - amount) <= 100);
            return (phoneMatch || jidMatch) && amountMatch;
          });
          if (match) return { id: match.id, ...match.data() };
        }
      }
    } catch (e) {
      console.warn('[FIREBASE] findRecentPendingTransferSlip notice:', e.message);
    }
    return null;
  }

  async saveAiKnowledgeRule(rule) {
    if (!rule || !rule.keyword || !rule.mappedValue) return false;
    try {
      const payload = {
        type: rule.type || 'customer_alias',
        keyword: String(rule.keyword).trim().toUpperCase(),
        mappedValue: String(rule.mappedValue).trim().toUpperCase(),
        source: rule.source || 'WA_GATEWAY_ESL',
        createdAt: new Date()
      };
      if (this.mode === 'admin' && this.db) {
        const existing = await this.db.collection('ai_knowledge_rules')
          .where('keyword', '==', payload.keyword)
          .where('mappedValue', '==', payload.mappedValue)
          .limit(1)
          .get();
        if (existing.empty) {
          await this.db.collection('ai_knowledge_rules').add(payload);
          console.log(`[ESL LEARN] 🧠 Aturan baru dipelajari: "${payload.keyword}" -> "${payload.mappedValue}"`);
        }
        return true;
      } else if (this.mode === 'client' && this.clientDb) {
        const { collection, query, where, limit, getDocs, addDoc } = this.clientSdk;
        const q = query(
          collection(this.clientDb, 'ai_knowledge_rules'),
          where('keyword', '==', payload.keyword),
          where('mappedValue', '==', payload.mappedValue),
          limit(1)
        );
        const existing = await getDocs(q);
        if (existing.empty) {
          await addDoc(collection(this.clientDb, 'ai_knowledge_rules'), payload);
          console.log(`[ESL LEARN] 🧠 Aturan baru dipelajari: "${payload.keyword}" -> "${payload.mappedValue}"`);
        }
        return true;
      }
    } catch (e) {
      console.warn('[ESL LEARN NOTICE]:', e.message);
    }
    return false;
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
    } else if (this.mode === 'client') {
      const { doc, onSnapshot } = this.clientSdk;
      onSnapshot(doc(this.clientDb, 'app_settings', 'wa_auto_po_settings'), snap => {
        if (snap && snap.exists()) {
          onSettings(snap.data());
        }
      });
    }
  }

  async findMatchingReceivable(customerHint, amount, rawOcrText = '') {
    if (!amount || amount <= 0) return null;
    const cleanHint = (customerHint || '').toUpperCase().trim();
    const upperOcr = (rawOcrText || '').toUpperCase();

    try {
      // 0. ENGINE SELF-LEARNING (ESL): Ambil memori aturan yang pernah dipelajari
      let learnedRules = [];
      try {
        if (this.mode === 'admin' && this.db) {
          const rulesSnap = await this.db.collection('ai_knowledge_rules').where('type', '==', 'customer_alias').get();
          learnedRules = rulesSnap.docs.map(d => d.data());
        } else if (this.mode === 'client' && this.clientDb) {
          const { collection, query, where, getDocs } = this.clientSdk;
          const rulesSnap = await getDocs(query(collection(this.clientDb, 'ai_knowledge_rules'), where('type', '==', 'customer_alias')));
          learnedRules = rulesSnap.docs.map(d => d.data());
        }
      } catch (_) {}

      const getInitials = (str) => {
        return str
          .replace(/[^A-Za-z0-9\s]/g, ' ')
          .split(/\s+/)
          .filter(Boolean)
          .map(w => w[0])
          .join('')
          .toUpperCase();
      };

      const isNameMatched = (toko, hint) => {
        if (!toko) return false;
        const cleanToko = toko.toUpperCase().trim();

        // 0. Cek Engine Self-Learning (ESL) memory rules
        for (const rule of learnedRules) {
          const kw = (rule.keyword || '').toUpperCase().trim();
          const target = (rule.mappedValue || '').toUpperCase().trim();
          if (kw.length >= 3 && target.length >= 3) {
            if (upperOcr.includes(kw) || cleanHint.includes(kw)) {
              if (cleanToko.includes(target) || target.includes(cleanToko)) {
                console.log(`[ESL RULE HIT] 🧠 Pola terpelajar cocok: "${kw}" -> "${target}" pada Toko "${cleanToko}"`);
                return true;
              }
            }
          }
        }

        // 1. Cek langsung teks OCR struk apakah mengandung nama toko atau alias/pemilik (misal: "Wimbo Wiek Kustanto" / "LG FF")
        if (upperOcr) {
          if (cleanToko.includes('(')) {
            const parts = cleanToko.split('(');
            const outside = parts[0].trim();
            const inside = parts[1].replace(')', '').trim();
            if (inside.length >= 3 && upperOcr.includes(inside)) return true;
            if (outside.length >= 3 && upperOcr.includes(outside)) return true;
          } else if (cleanToko.length >= 3 && upperOcr.includes(cleanToko)) {
            return true;
          }
        }

        if (!hint) return false;
        const filteredHint = hint
          .replace(/\b(DARI|KE|PENGIRIM|SEABANK|BCA|MANDIRI|BRI|BNI|BANK|TRANSFER|BI-FAST|REALTIME|SUKSES|BERHASIL)\b/gi, ' ')
          .replace(/[^A-Za-z0-9\s]/g, ' ')
          .trim();

        if (!filteredHint) return false;

        const tokoInitials = getInitials(cleanToko);
        const hintInitials = getInitials(filteredHint);

        if (filteredHint.includes(cleanToko) || cleanToko.includes(filteredHint)) return true;
        if (filteredHint === tokoInitials || hintInitials === filteredHint || tokoInitials === hintInitials) return true;
        const hintWords = filteredHint.split(/\s+/).filter(w => w.length >= 3 && !['CV', 'PT', 'TOKO', 'WARUNG', 'MARKET', 'DAN'].includes(w));
        if (hintWords.some(w => cleanToko.includes(w))) return true;

        return false;
      };

      const candidates = [];
      const exactAmountUnpaidList = [];

      // 1. PRIORITAS UTAMA: Periksa langsung koleksi transactions (sumber kebenaran nominal riil setelah revisi nota)
      try {
        let trDocs = [];
        if (this.mode === 'admin' && this.db) {
          const trSnap = await this.db.collection('transactions').get();
          trDocs = trSnap.docs.map(doc => ({ id: doc.id, data: doc.data() }));
        } else if (this.mode === 'client' && this.clientDb) {
          const { collection, getDocs } = this.clientSdk;
          const trSnap = await getDocs(collection(this.clientDb, 'transactions'));
          trDocs = trSnap.docs.map(doc => ({ id: doc.id, data: doc.data() }));
        }

        trDocs.forEach(({ id, data: d }) => {
          const statusTransfer = (d.statusTransfer || '').toUpperCase();
          if (statusTransfer === 'PAID') return; // Lewati yang sudah lunas

          const noInvoice = String(d.invoiceNo || id || '').replace(/\D/g, '');
          const toko = (d.aliasName || d.customerName || '').toUpperCase();
          const fullCust = (d.customerName || '').toUpperCase();
          const fullAlias = (d.aliasName || '').toUpperCase();
          const total = Number(d.grandTotal || 0) - Number(d.returnAmount || 0);

          const amountDiff = Math.abs(total - amount);
          const isAmountMatch = amountDiff <= 100;

          if (isAmountMatch) {
            const item = { noInvoice, toko, nominal: total, isLunas: false, docId: id, fromTransaction: true };
            exactAmountUnpaidList.push(item);

            if (isNameMatched(toko, cleanHint) || isNameMatched(fullCust, cleanHint) || isNameMatched(fullAlias, cleanHint)) {
              candidates.push(item);
            }
          }
        });
      } catch (trErr) {
        console.warn('[MATCH TRANSACTIONS ERROR]:', trErr.message);
      }

      // Fallback: Jika ada tepat 1 invoice belum lunas dengan nominal persis sama, gunakan sebagai match!
      if (candidates.length === 0 && exactAmountUnpaidList.length > 0) {
        const unpaidExact = exactAmountUnpaidList.filter(c => !c.isLunas);
        if (unpaidExact.length === 1) {
          console.log(`[AUTO-MATCH UNIQUE AMOUNT] 🎯 Hanya ada 1 faktur tertunggak (#${unpaidExact[0].noInvoice} - ${unpaidExact[0].toko}) dengan nominal Rp ${amount.toLocaleString('id-ID')}!`);
          candidates.push(unpaidExact[0]);
        }
      }

      // Jika berhasil dicocokkan via transactions, lakukan sinkronisasi otomatis ke receivables agar sinkron permanen
      if (candidates.length > 0) {
        const bestMatch = candidates[0];
        try {
          if (this.mode === 'admin') {
            const recSnap = await this.db.collection('receivables').where('noInvoice', '==', bestMatch.noInvoice).get();
            recSnap.forEach(rDoc => {
              if (Math.abs(Number(rDoc.data().nominal || 0) - bestMatch.nominal) > 100) {
                rDoc.ref.update({ nominal: bestMatch.nominal });
                console.log(`[AUTO-RESYNC RECEIVABLE] Memperbarui nominal piutang Faktur #${bestMatch.noInvoice} dari ${rDoc.data().nominal} menjadi ${bestMatch.nominal}`);
              }
            });
          }
        } catch (_) {}
        return bestMatch;
      }

      // 2. PRIORITAS KEDUA: Periksa koleksi receivables (pencocokan piutang cadangan)
      let snap;
      if (this.mode === 'admin') {
        snap = await this.db.collection('receivables').get();
      } else if (this.mode === 'client') {
        const { collection, getDocs } = this.clientSdk;
        snap = await getDocs(collection(this.clientDb, 'receivables'));
      } else {
        return null;
      }

      snap.forEach(doc => {
        const d = doc.data();
        const toko = (d.toko || d.customerName || '').toUpperCase();
        const nominal = Number(d.nominal || d.totalTagihan || d.total || 0);
        const noInvoice = String(d.noInvoice || d.invoiceNo || '');
        const isLunas = !!d.isLunas;

        const amountDiff = Math.abs(nominal - amount);
        const isAmountMatch = amountDiff <= 100;

        if (!isAmountMatch) return;

        if (isNameMatched(toko, cleanHint)) {
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

  parseSlipDateTime(rawDate, rawOcr, fallbackDate) {
    const text = ((rawDate || '') + '\n' + (rawOcr || '')).trim();

    const months = {
      'jan': 0, 'januari': 0, 'january': 0,
      'feb': 1, 'februari': 1, 'february': 1,
      'mar': 2, 'maret': 2, 'march': 2,
      'apr': 3, 'april': 3,
      'mei': 4, 'may': 4,
      'jun': 5, 'juni': 5, 'june': 5,
      'jul': 6, 'juli': 6, 'july': 6,
      'agu': 7, 'agust': 7, 'agustus': 7, 'aug': 7, 'august': 7,
      'sep': 8, 'september': 8,
      'okt': 9, 'oktober': 9, 'oct': 9, 'october': 9,
      'nop': 10, 'nov': 10, 'november': 10,
      'des': 11, 'desember': 11, 'dec': 11, 'december': 11
    };

    let hr = 12, min = 0, sec = 0;
    const timeMatch = text.match(/(?:Jam|Pukul|Waktu|Time)?\s*[:=]?\s*([0-2]?[0-9])[:.]([0-5][0-9])(?:[:.]([0-5][0-9]))?/i);
    if (timeMatch) {
      hr = parseInt(timeMatch[1], 10);
      min = parseInt(timeMatch[2], 10);
      if (timeMatch[3]) sec = parseInt(timeMatch[3], 10);
    }

    const dmyMatch = text.match(/(?:Tanggal|Tgl|Date)?\s*[:=]?\s*([0-3]?[0-9])[\/\-\.]([0-1]?[0-9])[\/\-\.]([0-9]{2,4})/i);
    if (dmyMatch) {
      const d = parseInt(dmyMatch[1], 10);
      const m = parseInt(dmyMatch[2], 10) - 1;
      let y = parseInt(dmyMatch[3], 10);
      if (y < 100) y += 2000;
      return new Date(y, m, d, hr, min, sec);
    }

    const textMonthMatch = text.match(/([0-3]?[0-9])\s+([A-Za-z]{3,9})\s+([0-9]{2,4})/i);
    if (textMonthMatch) {
      const d = parseInt(textMonthMatch[1], 10);
      const mStr = textMonthMatch[2].toLowerCase();
      const m = months[mStr] !== undefined ? months[mStr] : (months[mStr.substring(0, 3)] !== undefined ? months[mStr.substring(0, 3)] : 0);
      let y = parseInt(textMonthMatch[3], 10);
      if (y < 100) y += 2000;
      return new Date(y, m, d, hr, min, sec);
    }

    return fallbackDate || new Date();
  }

  async settleInvoicePayment(invoiceNo, paymentData = {}) {
    const invClean = String(invoiceNo || '').replace(/\D/g, '').trim();
    if (!invClean) return { success: false };

    try {
      console.log(`[AUTO-SETTLE] Memproses pembayaran otomatis Faktur #${invClean}...`);
      const transferDate = this.parseSlipDateTime(paymentData.rawDate, paymentData.rawOcrText, paymentData.receivedAt);
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
              date: transferDate,
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
              date: transferDate,
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
        transferDate: transferDate,
        transferReceiptUrl: paymentData.imageUrl || null,
        transferBankDetails: {
          bank: paymentData.bank || '',
          amount: payAmount,
          berita: paymentData.berita || '',
          refNo: paymentData.refNo || '',
          senderName: paymentData.senderName || '',
          transferDate: transferDate.toISOString(),
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

  async getNextInvoiceNo() {
    try {
      if (this.mode === 'admin') {
        const counterRef = this.db.collection('counters').doc('transactions');
        return await this.db.runTransaction(async (transaction) => {
          const snap = await transaction.get(counterRef);
          let currentNo = 180;
          if (snap.exists) {
            currentNo = snap.data().lastInvoiceNo || currentNo;
          }
          const nextNo = currentNo + 1;
          transaction.set(counterRef, { lastInvoiceNo: nextNo }, { merge: true });
          return String(nextNo);
        });
      } else if (this.mode === 'client') {
        const { doc, getDoc, setDoc } = this.clientSdk;
        const counterRef = doc(this.clientDb, 'counters', 'transactions');
        const snap = await getDoc(counterRef);
        let currentNo = 180;
        if (snap.exists && (typeof snap.exists === 'function' ? snap.exists() : true)) {
          currentNo = snap.data()?.lastInvoiceNo || currentNo;
        }
        const nextNo = currentNo + 1;
        await setDoc(counterRef, { lastInvoiceNo: nextNo }, { merge: true });
        return String(nextNo);
      }
    } catch (e) {
      console.error('[FIREBASE GET NEXT INVOICE ERROR]', e.message);
      return String(Date.now() % 1000000);
    }
  }

  async saveTransaction(invoiceNo, transactionData) {
    const invStr = String(invoiceNo);
    if (this.mode === 'admin') {
      await this.db.collection('transactions').doc(invStr).set(transactionData);
    } else if (this.mode === 'client') {
      const { doc, setDoc } = this.clientSdk;
      await setDoc(doc(this.clientDb, 'transactions', invStr), transactionData);
    }
  }

  async markChatAsProcessed(chatDocId, invoiceNo) {
    if (!chatDocId) return;
    const invStr = String(invoiceNo);
    const updatePayload = {
      status: 'processed',
      createdInvoiceNo: invStr,
      createdTransactionId: invStr,
      processedAt: new Date()
    };
    try {
      if (this.mode === 'admin') {
        await this.db.collection('incoming_po_chats').doc(chatDocId).update(updatePayload);
        await this.db.collection('incoming_wa_orders').doc(chatDocId).set(updatePayload, { merge: true }).catch(() => {});
      } else if (this.mode === 'client') {
        const { doc, updateDoc, setDoc } = this.clientSdk;
        await updateDoc(doc(this.clientDb, 'incoming_po_chats', chatDocId), updatePayload);
        await setDoc(doc(this.clientDb, 'incoming_wa_orders', chatDocId), updatePayload, { merge: true }).catch(() => {});
      }
    } catch (e) {
      console.warn('[MARK CHAT PROCESSED ERROR]', e.message);
    }
  }
}

module.exports = new FirebaseAdapter();
