/**
 * Autonomous PO Processor for WhatsApp Gateway (Termux / Background Node.js)
 * Memungkinkan pembuatan PO / Faktur Penjualan secara mandiri dari HP (Termux)
 * saat laptop kasir mati / aplikasi Flutter belum dibuka.
 */

class AutonomousPoProcessor {
  constructor(firebaseAdapter) {
    this.firebaseAdapter = firebaseAdapter;
    this.cachedCustomers = [];
    this.cachedProducts = [];
    this.cachedRules = [];
    this.lastCacheTime = 0;
    this.CACHE_TTL_MS = 10 * 60 * 1000; // 10 menit cache
  }

  cleanPhone(p) {
    if (!p) return '';
    let s = p.toString().replace(/\D/g, '');
    if (s.startsWith('08')) s = '628' + s.slice(2);
    return s;
  }

  async refreshCacheIfNeeded() {
    const now = Date.now();
    if (now - this.lastCacheTime < this.CACHE_TTL_MS && this.cachedCustomers.length > 0) {
      return;
    }

    try {
      console.log('[AUTONOMOUS PO] 🔄 Menyinkronkan cache Master Data (Customers, Products, Rules) dari Firestore...');
      const db = this.firebaseAdapter.db || this.firebaseAdapter.clientDb;
      const isClient = this.firebaseAdapter.mode === 'client';

      if (!isClient && this.firebaseAdapter.db) {
        // Mode Firebase Admin
        const custSnap = await db.collection('customers').get();
        this.cachedCustomers = custSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const prodSnap = await db.collection('products').get();
        this.cachedProducts = prodSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const rulesSnap = await db.collection('ai_knowledge_rules').get();
        this.cachedRules = rulesSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      } else if (isClient && this.firebaseAdapter.clientSdk) {
        // Mode Client SDK
        const { collection, getDocs } = require('firebase/firestore');
        const custSnap = await getDocs(collection(db, 'customers'));
        this.cachedCustomers = custSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const prodSnap = await getDocs(collection(db, 'products'));
        this.cachedProducts = prodSnap.docs.map(d => ({ id: d.id, ...d.data() }));

        const rulesSnap = await getDocs(collection(db, 'ai_knowledge_rules'));
        this.cachedRules = rulesSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      }

      this.lastCacheTime = now;
      console.log(`[AUTONOMOUS PO] ✅ Cache diperbarui: ${this.cachedCustomers.length} pelanggan, ${this.cachedProducts.length} produk, ${this.cachedRules.length} aturan.`);
    } catch (err) {
      console.warn('[AUTONOMOUS PO CACHE WARNING]', err.message);
    }
  }

  resolveCustomer(lines, senderPhone, pushName) {
    const cleanSender = this.cleanPhone(senderPhone);

    // 1. Cek dari nomor HP
    if (cleanSender) {
      const byPhone = this.cachedCustomers.find(c => {
        const cp = this.cleanPhone(c.phone);
        return cp && (cleanSender.endsWith(cp) || cp.endsWith(cleanSender) || cleanSender === cp);
      });
      if (byPhone) return byPhone;
    }

    // 2. Cek baris pertama / kedua apakah cocok dengan alias rule atau nama pelanggan
    const custRules = this.cachedRules.filter(r => r.type === 'customer_alias');
    for (let i = 0; i < Math.min(lines.length, 3); i++) {
      const lineClean = lines[i].replace(/[^a-zA-Z0-9\s]/g, ' ').trim().toLowerCase();
      if (!lineClean || lineClean.length < 2) continue;

      // Cek rule alias
      const ruleMatch = custRules.find(r => {
        const from = (r.from || '').toLowerCase().trim();
        return from && (lineClean === from || lineClean.startsWith(from + ' ') || lineClean.endsWith(' ' + from));
      });
      if (ruleMatch) {
        const targetName = (ruleMatch.to || '').toLowerCase().trim();
        const found = this.cachedCustomers.find(c =>
          (c.customerName || '').toLowerCase().includes(targetName) ||
          (c.aliasName || '').toLowerCase().includes(targetName)
        );
        if (found) return found;
      }

      // Cek nama customer / alias langsung
      const directMatch = this.cachedCustomers.find(c => {
        const cn = (c.customerName || '').toLowerCase().trim();
        const an = (c.aliasName || '').toLowerCase().trim();
        return (cn && (lineClean.includes(cn) || cn.includes(lineClean))) ||
               (an && (lineClean.includes(an) || an.includes(lineClean)));
      });
      if (directMatch) return directMatch;
    }

    // 3. Cek pushName WhatsApp
    if (pushName) {
      const pnClean = pushName.toLowerCase().trim();
      const byPush = this.cachedCustomers.find(c => {
        const cn = (c.customerName || '').toLowerCase().trim();
        const an = (c.aliasName || '').toLowerCase().trim();
        return (cn && (pnClean.includes(cn) || cn.includes(pnClean))) ||
               (an && (pnClean.includes(an) || an.includes(pnClean)));
      });
      if (byPush) return byPush;
    }

    return null;
  }

  resolveProduct(rawItemText) {
    const lower = rawItemText.toLowerCase();

    // 1. Ekstrak kuantiti & satuan
    const qtyMatch = lower.match(/(?:^|\s|\.\.\.)(\d+(?:[.,]\d+)?)\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/i);
    let qtyInput = 0;
    let qtyUnit = 'karton';
    if (qtyMatch) {
      qtyInput = parseFloat(qtyMatch[1].replace(',', '.'));
      const u = qtyMatch[2].toLowerCase();
      if (['k', 'ktn', 'karton', 'dus', 'box'].includes(u)) {
        qtyUnit = 'karton';
      } else if (['pack', 'pcs'].includes(u)) {
        qtyUnit = 'pcs';
      } else if (['bal', 'ball'].includes(u)) {
        qtyUnit = 'ball';
      } else if (['roll'].includes(u)) {
        qtyUnit = 'roll';
      }
    } else {
      // Fallback kuantiti di akhir baris: misal "...10"
      const endMatch = lower.match(/(?:\.\.\.|\s+)(\d+)\s*$/);
      if (endMatch) {
        qtyInput = parseFloat(endMatch[1]);
        qtyUnit = 'karton';
      }
    }

    if (qtyInput <= 0) return null;

    // Bersihkan teks barang dari kuantiti
    let cleanProd = lower
      .replace(/(?:^|\s|\.\.\.)\d+(?:[.,]\d+)?\s*(k|ktn|karton|dus|box|pack|pcs|bal|ball|roll)\b/gi, ' ')
      .replace(/^[0-9]+[.)]\s*/, '')
      .replace(/\.\.\..*$/, '')
      .replace(/[^a-zA-Z0-9\s]/g, ' ')
      .trim();

    // 2. Cocokkan dengan rules produk
    const prodRules = this.cachedRules.filter(r => r.type === 'product_alias');
    for (const r of prodRules) {
      const from = (r.from || '').toLowerCase().trim();
      if (from && cleanProd.includes(from)) {
        const to = (r.to || '').toLowerCase().trim();
        const p = this.cachedProducts.find(prod => (prod.productName || '').toLowerCase().includes(to));
        if (p) {
          return this.buildTransactionItem(p, qtyInput, qtyUnit);
        }
      }
    }

    // 3. Cocokkan dengan katalog produk langsung
    const words = cleanProd.split(/\s+/).filter(w => w.length >= 3);
    if (words.length > 0) {
      // Skor kecocokan kata
      let bestProduct = null;
      let maxScore = 0;

      for (const p of this.cachedProducts) {
        const pName = (p.productName || '').toLowerCase();
        let score = 0;
        for (const w of words) {
          if (pName.includes(w)) score++;
        }
        if (score > maxScore) {
          maxScore = score;
          bestProduct = p;
        }
      }

      if (bestProduct && maxScore >= Math.min(2, words.length)) {
        return this.buildTransactionItem(bestProduct, qtyInput, qtyUnit);
      }
    }

    return null;
  }

  buildTransactionItem(prod, qtyInput, qtyUnit) {
    const sizeGrams = Number(prod.sizeGrams) || 500;
    let pcsPerKtn = 15;
    if (sizeGrams >= 1000) {
      pcsPerKtn = 10;
    } else if (prod.productName && prod.productName.includes('24S')) {
      pcsPerKtn = 24;
    } else if (prod.productName && prod.productName.includes('13S')) {
      pcsPerKtn = 13;
    } else if (prod.productName && prod.productName.includes('7S')) {
      pcsPerKtn = 15;
    }

    let qtyPcs = qtyInput;
    if (qtyUnit === 'karton') {
      qtyPcs = qtyInput * pcsPerKtn;
    } else if (qtyUnit === 'ball') {
      qtyPcs = qtyInput * 25; // 1 ball = 25 pcs
    }

    const price = Number(prod.price) || 0;
    const subtotal = Math.round(qtyPcs * price);

    return {
      productId: prod.id || '',
      productName: prod.productName || 'PRODUK',
      price: price,
      qty: qtyPcs,
      discountPercent: 0,
      subtotal: subtotal,
      sizeGrams: sizeGrams,
      isBonus: false
    };
  }

  async parseOrderChat(rawChat, senderPhone, pushName) {
    await this.refreshCacheIfNeeded();

    const lines = rawChat.split('\n').map(l => l.trim()).filter(l => l.length > 0);
    if (lines.length === 0) return null;

    const customer = this.resolveCustomer(lines, senderPhone, pushName);
    if (!customer) {
      console.log(`[AUTONOMOUS PO] ⚠️ Customer belum dapat dipastikan dari pengirim (+${senderPhone}). Menunggu konfirmasi kasir.`);
      return null;
    }

    const items = [];
    for (const line of lines) {
      const lower = line.toLowerCase();
      // Skip instruksi / sapaan / header toko
      if (lower.startsWith('krm') || lower.startsWith('kirim') || lower.startsWith('salam') || lower.startsWith('pagi') || lower.startsWith('siang')) {
        continue;
      }
      if (customer.aliasName && lower.includes(customer.aliasName.toLowerCase())) continue;
      if (customer.customerName && lower.includes(customer.customerName.toLowerCase())) continue;

      const item = this.resolveProduct(line);
      if (item) {
        items.push(item);
      }
    }

    if (items.length === 0) {
      return null;
    }

    const grandTotal = items.reduce((sum, it) => sum + (it.subtotal || 0), 0);

    return {
      customer,
      items,
      grandTotal
    };
  }

  async processAutonomousPo(chatDocId, chatPayload) {
    try {
      // 1. Jangan proses jika quoted reply / revisi (harus melalui verifikasi kasir)
      if (chatPayload.isQuotedReply) {
        console.log(`[AUTONOMOUS PO] ℹ️ Chat adalah QUOTED_REPLY (Revisi/Balasan). Dibiarkan pending untuk review kasir.`);
        return null;
      }

      console.log(`[AUTONOMOUS PO] 🤖 Memulai analisis otonom pesanan dari ${chatPayload.senderName} (+${chatPayload.senderPhone})...`);
      const parsed = await this.parseOrderChat(
        chatPayload.messageText,
        chatPayload.senderPhone,
        chatPayload.senderName
      );

      if (!parsed || parsed.items.length === 0) {
        console.log(`[AUTONOMOUS PO] ⏳ Format pesanan belum lengkap atau butuh verifikasi manual. Chat disimpan sebagai pending.`);
        return null;
      }

      console.log(`[AUTONOMOUS PO] 🎯 Pelanggan: ${parsed.customer.customerName} (${parsed.customer.aliasName || '-'}), ${parsed.items.length} item barang, Grand Total: Rp ${parsed.grandTotal.toLocaleString('id-ID')}`);

      // 2. Generate Nomor Faktur resmi via transaction
      const invoiceNo = await this.firebaseAdapter.getNextInvoiceNo();
      if (!invoiceNo) {
        throw new Error('Gagal menghasilkan nomor faktur transaksi');
      }

      // 3. Simpan Transaksi baru ke Firestore (Status: PENDING)
      const now = new Date();
      const transactionDoc = {
        invoiceNo: String(invoiceNo),
        customerId: parsed.customer.id || '',
        customerName: parsed.customer.customerName || '',
        aliasName: parsed.customer.aliasName || '',
        date: now,
        deliveryDate: null,
        city: parsed.customer.city || 'SEMARANG',
        province: parsed.customer.province || 'JAWA TENGAH',
        country: 'INDONESIA',
        items: parsed.items,
        grandTotal: parsed.grandTotal,
        note: '',
        status: 'PENDING',
        statusTransfer: parsed.grandTotal <= 0 ? 'PAID' : 'UNPAID',
        transferDate: null,
        createdBy: 'AI Auto-PO Termux Gateway',
        createdAt: now,
        sourceInvoices: [],
        lampiranInvoiceNo: '',
        isLampiran: false
      };

      await this.firebaseAdapter.saveTransaction(invoiceNo, transactionDoc);

      // 4. Update dokumen incoming_po_chats menjadi processed
      if (chatDocId) {
        await this.firebaseAdapter.markChatAsProcessed(chatDocId, invoiceNo);
      }

      console.log(`[AUTONOMOUS PO SUCCESS] 🚀🎉 FAKTUR #${invoiceNo} (${parsed.customer.customerName}) BERHASIL DIBUAT DARI TERMUX! (Laptop kasir tidak perlu menyala)`);
      return {
        success: true,
        invoiceNo: String(invoiceNo),
        customerName: parsed.customer.customerName,
        grandTotal: parsed.grandTotal
      };
    } catch (err) {
      console.error('[AUTONOMOUS PO ERROR]', err.message);
      return null;
    }
  }
}

module.exports = AutonomousPoProcessor;
