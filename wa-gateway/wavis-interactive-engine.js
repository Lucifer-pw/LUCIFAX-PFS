/**
 * WAVIS INTERACTIVE ENGINE (Tahap 3)
 * L-W.A.V.I.S: Lucifax-Whatsapp Assistant Vision Interactive System
 * 
 * Modul cerdas interaktif lokal dua arah untuk membalas konfirmasi pesanan (PO),
 * melayani cek piutang, cek stok, dan memberikan bantuan saat admin sedang tidak standby.
 * 100% Native / Lokal tanpa ketergantungan API pihak ketiga.
 */

function normalizeText(str) {
  return (str || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

class WavisInteractiveEngine {
  constructor(firebaseAdapter, autoPoProcessor) {
    this.firebaseAdapter = firebaseAdapter;
    this.autoPoProcessor = autoPoProcessor;
    this.sockGetter = null;
    this.rawMessageStore = null;
    this.lastAdminActivityTime = 0;
  }

  setSocketGetter(fn) {
    this.sockGetter = fn;
  }

  setRawMessageStore(fn) {
    this.rawMessageStore = fn;
  }

  recordAdminActivity() {
    this.lastAdminActivityTime = Date.now();
  }

  isAdminStandby(thresholdMs = 3 * 60 * 1000) {
    return (Date.now() - this.lastAdminActivityTime) < thresholdMs;
  }

  /**
   * Generator Kalimat Penutup Interaktif Cerdas & Proaktif (AI Persona Assistant)
   * Menyediakan variasi pesan luwes, ramah, dan kontekstual agar tidak terkesan kaku seperti robot biasa.
   */
  generateSmartFooter(context, options = {}) {
    const { senderName = 'Kak', hasDebt = false, isReady = true, customerName = '', productName = '' } = options;

    let footers = [];

    switch (context) {
      case 'RECEIVABLES_WITH_DEBT':
        footers = [
          `💡 *Selagi Admin / Developer belum standby di tempat:*\nL-W.A.V.I.S siap bantu cek rincian faktur lain, cek ketersediaan stok barang, atau langsung proses draft PO baru. Ada yang ingin dicek lagi ${senderName}? 😊`,
          `💬 *Butuh rincian faktur tertentu atau mau titip konfirmasi pembayaran?*\nSilakan ketik nomor faktur atau kirim foto bukti transfer ke sini, nanti saya sinkronkan langsung ke sistem ya ${senderName}. 📝`,
          `📦 *Toko ini ada rencana ambil barang lagi?*\nL-W.A.V.I.S siap bantu cek stok barang yang sering diorder atau langsung siapkan draft pesanannya! ✨`,
          `🤝 *Ada yang bisa saya bantu lagi untuk operasional hari ini ${senderName}?*\nKetik saja nama barang untuk cek stok, atau nama toko lain untuk cek kartu piutangnya.`
        ];
        break;

      case 'RECEIVABLES_LUNAS':
        footers = [
          `🎉 *Toko ini berstatus bersih tanpa tunggakan!*\nSiap ambil barang lagi hari ini ${senderName}? Kirimkan list pesanannya atau ketik nama barang untuk cek stok, L-W.A.V.I.S buatkan fakturnya selagi Admin belum standby. ✨`,
          `✨ *Mau restok produk favorit untuk toko ini?*\nCukup ketik \`stok [nama barang]\` atau kirim format orderan di sini, sistem siap proses otomatis! 📦`,
          `🤝 *Senang melihat transaksi toko ini lancar!* 😊\nAda toko lain atau stok gudang yang ingin dicek lagi selagi Admin sedang tidak di tempat? Silakan ketik langsung ya ${senderName}.`
        ];
        break;

      case 'STOCK_SPECIFIC_READY':
        footers = [
          `📦 *Stok aman dan siap kirim!*\nMau langsung dibuatkan draft faktur penjualannya ${senderName}? Cukup kirim list ordernya di sini ya. Selagi Admin offline, L-W.A.V.I.S siap bantu! 😊`,
          `✨ Butuh cek ketersediaan produk lainnya atau mau sekalian cek kartu piutang toko tujuan pengiriman? Silakan ketik langsung ya ${senderName}. 💡`,
          `🤝 Ada produk lain yang ingin dicek juga selagi menunggu Admin online? Ketik saja nama produknya ya ${senderName}.`
        ];
        break;

      case 'STOCK_SPECIFIC_EMPTY':
        footers = [
          `⚠️ *Stok produk ini sedang kosong di gudang.*\nMau saya bantu cek produk alternatif yang serupa atau cek varian ukuran lain ${senderName}? Ketik nama produk alternatifnya ya. 🔍`,
          `📝 Ingin titip catatan kebutuhan restok produk ini untuk Admin / Developer? Ketik saja pesannya di sini, akan saya pastikan terbaca saat beliau aktif kembali ya! ✨`,
          `💡 Butuh cek stok barang lain yang saat ini ready di gudang? Ketik \`stok keseluruhan\` untuk melihat rangkuman produk siap kirim.`
        ];
        break;

      case 'STOCK_OVERALL':
        footers = [
          `📦 Ingin cek stok detail untuk produk tertentu atau mau langsung input orderan toko ${senderName}? Ketik \`stok [nama barang]\` atau kirimkan list ordernya ya! ✨`,
          `🤝 Selagi Admin / Developer sedang tidak standby, L-W.A.V.I.S siap melayani cek piutang toko atau pembuatan draft faktur. Ada hal operasional lain yang bisa saya bantu ${senderName}? 😊`,
          `💡 Butuh buat draft PO untuk toko tertentu? Langsung kirim format pesanannya di sini, sistem akan langsung memprosesnya otomatis!`
        ];
        break;

      case 'PO_CONFIRMATION':
        footers = [
          `ℹ️ *Layanan Operasional L-W.A.V.I.S:*\n• Faktur sudah aman masuk antrean kasir.\n• Selagi Admin belum standby, L-W.A.V.I.S siap bantu cek stok barang atau proses pesanan toko lainnya. Ada lagi yang ingin diproses ${senderName}? 😊`,
          `ℹ️ *Layanan Operasional L-W.A.V.I.S:*\n• Draft pesanan sudah tersimpan rapi di sistem.\n• Jika ada pesan personal atau catatan khusus untuk Admin, silakan ketik langsung ya, beliau akan membalas segera setelah aktif kembali! ✨`
        ];
        break;

      default:
        footers = [
          `🤝 *L-W.A.V.I.S siap siaga!* Selagi Admin belum standby di tempat, silakan manfaatkan layanan cek piutang, cek stok fisik, atau input PO kapan saja. Ada hal lain yang ingin dicek ${senderName}? 😊`,
          `💡 Ketik apa yang ${senderName} butuhkan: cek piutang toko, stok barang gudang, atau kirimkan list orderan. Saya siap bantu kelancaran operasional Anda!`
        ];
        break;
    }

    const selected = footers[Math.floor(Math.random() * footers.length)];
    return selected;
  }

  /**
   * Format Konfirmasi Faktur PO (Format 2-Baris Padat + Status Paid + GrandTotal)
   */
  formatPoConfirmation(invoiceData, senderName = 'Kak') {
    const {
      invoiceNo,
      customerName,
      aliasName,
      city,
      province,
      date,
      status,
      statusTransfer,
      items = [],
      grandTotal = 0,
      note
    } = invoiceData;

    const displayCust = aliasName ? `${aliasName} (${customerName})` : customerName;
    const cleanCity = city || 'SEMARANG';
    const cleanProv = province || 'JAWA TENGAH';
    
    // Format tanggal
    let tglStr = 'Hari ini';
    try {
      const d = date ? (date.toDate ? date.toDate() : new Date(date)) : new Date();
      const dd = String(d.getDate()).padStart(2, '0');
      const mm = String(d.getMonth() + 1).padStart(2, '0');
      const yyyy = d.getFullYear();
      tglStr = `${dd}-${mm}-${yyyy}`;
    } catch (_) {}

    // Hitung total karton
    let totalCarton = 0;
    for (const it of items) {
      if (typeof it.cartonCount === 'number' && it.cartonCount > 0) {
        totalCarton += it.cartonCount;
      } else {
        const pcsPerKtn = it.isiKarton || 15;
        totalCarton += (it.qty || 0) / pcsPerKtn;
      }
    }

    const numberEmojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟'];

    let text = `🤖 *[PESAN OTOMATIS: L-W.A.V.I.S]*\n`;
    text += `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n`;
    text += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    text += `Halo ${senderName}! Draft pesanan berhasil diproses ke sistem:\n\n`;
    text += `🏢 *Pelanggan:* ${displayCust}\n`;
    text += `📍 *Kota:* ${cleanCity}, ${cleanProv}\n`;
    text += `📄 *No. Invoice:* #${invoiceNo}\n`;
    text += `📅 *Tgl Invoice:* ${tglStr}\n`;
    text += `🚚 *Status Kirim:* ${status || 'PENDING'}\n`;
    text += `💳 *Status Paid:* ${statusTransfer || 'UNPAID'}\n\n`;
    text += `*DAFTAR BARANG (${items.length} Item):*\n`;
    text += `────────────────────\n`;

    items.forEach((it, idx) => {
      const num = idx < 10 ? numberEmojis[idx] : `${idx + 1}.`;
      const pName = it.productName || 'PRODUK';
      const weightStr = it.weightKg ? ` (${Number(it.weightKg).toFixed(2)} kg)` : '';
      
      const ktnVal = it.cartonCount || (it.isiKarton ? Math.round(it.qty / it.isiKarton * 10) / 10 : null);
      const ktnStr = ktnVal ? `${ktnVal} Ktn` : `${it.qty} pcs`;
      const priceStr = (it.price || 0).toLocaleString('id-ID');
      
      let discStr = ' | Disc: -';
      if ((it.discountPercent && it.discountPercent > 0) || (it.discountAmount && it.discountAmount > 0)) {
        const pct = it.discountPercent ? `${it.discountPercent}%` : '';
        const amt = it.discountAmount ? `(-${it.discountAmount.toLocaleString('id-ID')})` : '';
        discStr = ` | Disc ${pct} ${amt}`.trim();
      }

      const subtotalStr = (it.subtotal || 0).toLocaleString('id-ID');

      text += `${num} *${pName}*${weightStr}\n`;
      text += `   ${ktnStr} (${it.qty} pcs) @${priceStr}${discStr} = *Rp ${subtotalStr}*\n\n`;
    });

    text += `────────────────────\n`;
    text += `📦 *GrandTotal Karton:* ${Math.round(totalCarton * 10) / 10} Ktn\n`;
    text += `💰 *GRAND TOTAL:* *Rp ${grandTotal.toLocaleString('id-ID')}*\n`;
    if (note && note.trim().length > 0) {
      text += `📝 *Catatan:* ${note.trim()}\n`;
    }
    text += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    text += this.generateSmartFooter('PO_CONFIRMATION', { senderName });

    return text;
  }

  /**
   * Klasifikasi Maksud Chat (Intent Recognition Lokal)
   * Mendukung validasi produk lokal agar kata "ready" tidak bentrok dengan percakapan santai.
   */
  classifyIntent(text, products = []) {
    const clean = normalizeText(text);
    if (!clean) return 'UNKNOWN';

    // 1. Cek Pola Tanya Piutang
    const piutangPattern = /\b(piutang|utang|bon|tagihan|sisa tagihan|sisa piutang|belum bayar)\b/i;
    if (piutangPattern.test(clean)) {
      return 'QUERY_RECEIVABLES';
    }

    // 2. Cek Pola Tanya Stok:
    // Pastikan tidak false-positive pada bahasa percakapan santai seperti "Are you ready?", "Aku ready", dll.
    const stockExplicitPattern = /\b(stok|stock|sisa berapa|sisa stok|info stok|cek stok)\b|\b(ada|masih ada)\s+(ga|gak|nggak|kah|blm|belum|ndak|ora)\b/i;
    const readyWithContextPattern = /\bready\s+(stok|stock|ga|gak|nggak|kah|ta|po|dong|blm|belum)\b|\b(stok|stock|masih|apakah|apa)\s+ready\b/i;

    if (stockExplicitPattern.test(clean) || readyWithContextPattern.test(clean)) {
      return 'QUERY_STOCK';
    }

    // Jika pesan mengandung kata 'ready' standalone, cek apakah diikuti produk nyata dari katalog
    if (/\bready\b/i.test(clean) && Array.isArray(products) && products.length > 0) {
      const prod = this.matchProductFromQuery(clean, products);
      if (prod) {
        return 'QUERY_STOCK';
      }
    }

    // 3. Cek Pola Sapaan / Menu Bantuan / Pertanyaan Kemampuan AI
    const greetingPattern = /\b(halo|hello|pagi|siang|sore|malam|assalamualaikum|bantuan|menu|wavis|hai|bisa apa|bisa bantu apa|tugasmu|fungsi wavis|siapa kamu|fitur|cara pakai|standby)\b/i;
    if (greetingPattern.test(clean)) {
      return 'GREETING_MENU';
    }

    return 'UNKNOWN';
  }

  /**
   * Cari Pelanggan yang Cocok dari Teks Query
   * Cerdas & memahami akronim/singkatan (SJJ, MMM, AFM), aturan AI Knowledge,
   * nama toko alias, nama legal, dan membersihkan stop-words percakapan.
   */
  matchCustomerFromQuery(text, customers) {
    const clean = normalizeText(text);
    if (!clean || !Array.isArray(customers) || customers.length === 0) return null;

    // 0. Cek Engine Self-Learning (ESL) rules dari ai_knowledge_rules (misal 'SJJ' -> 'SURYANTO WIBISONO WIBOWO' / 'AD008')
    const rules = this.autoPoProcessor?.cachedRules || [];
    for (const rule of rules) {
      if (rule.type === 'customer_alias') {
        const kw = normalizeText(rule.keyword || '');
        if (kw.length >= 2) {
          const kwPattern = new RegExp('(^|\\s)' + kw.replace(/\s+/g, '\\s+') + '(\\s|$)', 'i');
          if (kwPattern.test(clean)) {
            const found = customers.find(c =>
              (rule.targetId && c.id === rule.targetId) ||
              (rule.mappedValue && (c.customerName === rule.mappedValue || c.aliasName === rule.mappedValue)) ||
              (rule.mappedValue && normalizeText(c.customerName).includes(normalizeText(rule.mappedValue))) ||
              (rule.mappedValue && normalizeText(c.aliasName).includes(normalizeText(rule.mappedValue)))
            );
            if (found) return found;
          }
        }
      }
    }

    // 1. Cek Initials / Singkatan / Akronim Nama Toko (misal "SUMBER JADI JAYA" -> "SJJ", "MAJU MARKET MANDIRI" -> "MMM")
    for (const c of customers) {
      const alias = normalizeText(c.aliasName || c.alias || '');
      const name = normalizeText(c.customerName || c.name || '');

      const getInitials = (s) => s.split(/\s+/).filter(w => w.length > 0 && !['ff', 'frozen', 'food', 'cv', 'pt', 'toko', 'ud'].includes(w)).map(w => w[0]).join('');
      const aliasInitials = getInitials(alias);
      const nameInitials = getInitials(name);

      if (aliasInitials.length >= 2) {
        const initPat = new RegExp('(^|\\s)' + aliasInitials + '(\\s|$)', 'i');
        if (initPat.test(clean)) return c;
      }
      if (nameInitials.length >= 2) {
        const initPat = new RegExp('(^|\\s)' + nameInitials + '(\\s|$)', 'i');
        if (initPat.test(clean)) return c;
      }

      // Cek odooNamePtSo / odooDeliveryAddressCvSo jika ada
      const odoo = normalizeText(c.odooNamePtSo || c.odooDeliveryAddressCvSo || '');
      if (odoo.length >= 3) {
        const odooParts = odoo.split(/\s+/);
        for (const op of odooParts) {
          if (op.length >= 3 && !['jateng', 'cv', 'pt', 'so'].includes(op)) {
            const opPat = new RegExp('(^|\\s)' + op + '(\\s|$)', 'i');
            if (opPat.test(clean)) return c;
          }
        }
      }
    }

    // 2. Cek Exact Alias (e.g. 'aw ff', 'griya ff', 'afm', 'sumber jadi jaya')
    for (const c of customers) {
      const alias = normalizeText(c.aliasName || c.alias || '');
      if (alias.length >= 2) {
        const aliasPattern = new RegExp('(^|\\s)' + alias.replace(/\s+/g, '\\s+') + '(\\s|$)', 'i');
        if (aliasPattern.test(clean)) return c;

        // Root alias tanpa 'ff' / 'frozen food'
        const rootAlias = alias.replace(/\b(ff|frozen|food)\b/g, '').trim();
        if (rootAlias.length >= 2) {
          const rootPattern = new RegExp('(^|\\s)' + rootAlias + '(\\s|$)', 'i');
          if (rootPattern.test(clean)) return c;
        }
      }
    }

    // 3. Cek Nama Pelanggan (e.g. 'aw frozen food', 'suryanto wibisono')
    for (const c of customers) {
      const name = normalizeText(c.customerName || c.name || '');
      if (name.length >= 3 && clean.includes(name)) return c;
      const rootName = name.replace(/\b(ff|frozen|food|toko|cv|pt)\b/g, '').trim();
      if (rootName.length >= 2) {
        const rootPattern = new RegExp('(^|\\s)' + rootName + '(\\s|$)', 'i');
        if (rootPattern.test(clean)) return c;
      }
    }

    // 4. Word overlap fallback (abaikan kata umum & stop words percakapan)
    const stopWords = [
      'wavis', 'kirimkan', 'kirim', 'kartu', 'piutang', 'utang', 'bon', 'tagihan',
      'dari', 'untuk', 'toko', 'pelanggan', 'cek', 'lihat', 'tampilkan', 'buka',
      'minta', 'tolong', 'dong', 'saya', 'ingin', 'mau', 'mas', 'pak', 'kak',
      'nya', 'ya', 'info', 'siang', 'pagi', 'sore', 'malam', 'halo', 'assalamualaikum'
    ];
    const words = clean.split(/\s+/).filter(w => !stopWords.includes(w) && w.length >= 2);
    for (const c of customers) {
      const name = normalizeText(c.customerName || c.name || '');
      const alias = normalizeText(c.aliasName || c.alias || '');
      const cWords = (name + ' ' + alias).split(/\s+/);
      for (const qw of words) {
        if (cWords.includes(qw)) return c;
      }
    }

    return null;
  }

  /**
   * Cari Produk yang Cocok dari Teks Query
   */
  matchProductFromQuery(text, products) {
    const clean = normalizeText(text);
    if (!clean || !Array.isArray(products) || products.length === 0) return null;

    // Buang stop words stok
    const cleanWords = clean
      .replace(/\b(stok|stock|ready|sisa|berapa|ada|ga|gak|masih|ya|mas|pak|dong)\b/g, '')
      .replace(/\s+/g, ' ')
      .trim()
      .split(/\s+/)
      .filter(w => w.length >= 2);

    if (cleanWords.length === 0) return null;

    let best = null;
    let maxScore = 0;
    for (const p of products) {
      const pName = normalizeText(p.productName || p.name || '');
      const pWords = pName.split(/\s+/);
      let score = 0;
      for (const qw of cleanWords) {
        if (pWords.includes(qw)) {
          score += 5;
        } else if (pName.includes(qw)) {
          score += 2;
        }
      }
      if (score > maxScore && score >= 5) {
        maxScore = score;
        best = p;
      }
    }

    return best;
  }

  /**
   * Menjawab Pertanyaan Piutang
   */
  async handleReceivablesQuery(text, senderName = 'Kak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const customers = this.autoPoProcessor.cachedCustomers || [];
    const matchedCustomer = this.matchCustomerFromQuery(text, customers);

    if (!matchedCustomer) {
      return `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk mengecek kartu piutang, mohon sebutkan nama toko / pelanggannya ya.\n\n` +
        `💡 *Contoh:* ketik \`piutang AFM\` atau \`tagihan Maju Market\`.`;
    }

    const custName = matchedCustomer.customerName || 'PELANGGAN';
    const alias = matchedCustomer.aliasName ? ` (${matchedCustomer.aliasName})` : '';

    try {
      // Ambil transaksi untuk customer ini dari koleksi transactions
      const db = this.firebaseAdapter.db || this.firebaseAdapter.clientDb;
      let allCustomerTransactions = [];

      const queryCol = async (field, val) => {
        if (!val) return [];
        if (this.firebaseAdapter.mode === 'admin' && db) {
          const snap = await db.collection('transactions').where(field, '==', val).get();
          return snap.docs.map(d => ({ id: d.id, ...d.data() }));
        } else if (this.firebaseAdapter.clientSdk && db) {
          const { collection, query, where, getDocs } = this.firebaseAdapter.clientSdk;
          const snap = await getDocs(query(collection(db, 'transactions'), where(field, '==', val)));
          return snap.docs.map(d => ({ id: d.id, ...d.data() }));
        }
        return [];
      };

      if (matchedCustomer.id) {
        allCustomerTransactions = await queryCol('customerId', matchedCustomer.id);
      }
      if (allCustomerTransactions.length === 0 && matchedCustomer.customerName) {
        allCustomerTransactions = await queryCol('customerName', matchedCustomer.customerName);
      }
      if (allCustomerTransactions.length === 0 && matchedCustomer.aliasName) {
        allCustomerTransactions = await queryCol('aliasName', matchedCustomer.aliasName);
      }

      // Urutkan transaksi dari yang terbaru ke terlama
      allCustomerTransactions.sort((a, b) => {
        const getSec = (x) => {
          if (!x) return 0;
          if (x.date?._seconds) return x.date._seconds;
          if (x.date?.toDate) return x.date.toDate().getTime() / 1000;
          if (x.createdAt?._seconds) return x.createdAt._seconds;
          return new Date(x.date || x.createdAt || 0).getTime() / 1000;
        };
        return getSec(b) - getSec(a);
      });

      // Filter invoice yang belum lunas
      const unpaidInvoices = allCustomerTransactions.filter(inv => {
        const st = (inv.statusTransfer || '').toUpperCase();
        return st !== 'PAID' && (Number(inv.grandTotal) || 0) > 0;
      });

      let totalRemaining = 0;
      unpaidInvoices.forEach(inv => {
        const grand = Number(inv.grandTotal) || 0;
        const paid = Number(inv.transferBankDetails?.totalPaid || inv.transferBankDetails?.amount || inv.paidAmount || 0);
        const remaining = Math.max(0, grand - paid);
        totalRemaining += remaining;
      });

      // Cari info cicilan / pembayaran terakhir dari transaksi customer
      let lastPaymentInfo = null;
      for (const inv of allCustomerTransactions) {
        const paid = Number(inv.transferBankDetails?.totalPaid || inv.transferBankDetails?.amount || inv.paidAmount || 0);
        if (paid > 0) {
          const rawDate = inv.transferBankDetails?.rawDate || inv.transferBankDetails?.transferDate || inv.transferDate || inv.date;
          lastPaymentInfo = {
            amount: paid,
            date: rawDate,
            bank: inv.transferBankDetails?.bank || ''
          };
          break;
        }
      }

      let lastPayStr = '-';
      if (lastPaymentInfo && lastPaymentInfo.amount > 0) {
        let tgl = '';
        if (typeof lastPaymentInfo.date === 'string' && lastPaymentInfo.date.length >= 8) {
          if (lastPaymentInfo.date.includes('/')) {
            tgl = ` (Tgl: ${lastPaymentInfo.date})`;
          } else {
            try {
              const d = new Date(lastPaymentInfo.date);
              tgl = ` (Tgl: ${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()})`;
            } catch (_) {}
          }
        } else if (lastPaymentInfo.date?._seconds) {
          const d = new Date(lastPaymentInfo.date._seconds * 1000);
          tgl = ` (Tgl: ${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()})`;
        }
        const bName = lastPaymentInfo.bank ? ` via ${lastPaymentInfo.bank}` : '';
        lastPayStr = `Rp ${lastPaymentInfo.amount.toLocaleString('id-ID')}${tgl}${bName}`;
      }

      let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += `Halo ${senderName}! Berikut ringkasan kartu piutang untuk *${custName}${alias}*:\n\n`;
      resText += `💳 *Total Sisa Piutang:* *Rp ${totalRemaining.toLocaleString('id-ID')}*\n`;
      resText += `📑 *Jumlah Faktur Belum Lunas:* ${unpaidInvoices.length} Invoice\n`;
      resText += `🗓️ *Cicilan / Pembayaran Terakhir:* ${lastPayStr}\n\n`;

      if (unpaidInvoices.length > 0) {
        resText += `*Daftar Faktur Belum Lunas:*\n`;
        unpaidInvoices.slice(0, 5).forEach((inv, i) => {
          const rem = (Number(inv.grandTotal) || 0) - (Number(inv.paidAmount) || 0);
          resText += `• #${inv.invoiceNo || inv.id}: Sisa Rp ${rem.toLocaleString('id-ID')}\n`;
        });
        if (unpaidInvoices.length > 5) {
          resText += `• ...dan ${unpaidInvoices.length - 5} faktur lainnya.\n`;
        }
      } else {
        resText += `🎉 *STATUS: SEMUA FAKTUR SUDAH LUNAS!* ✅\n`;
        resText += `Alhamdulillah, toko ini tidak memiliki sisa tunggakan tagihan saat ini.\n`;
      }

      resText += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      const footerCtx = unpaidInvoices.length > 0 ? 'RECEIVABLES_WITH_DEBT' : 'RECEIVABLES_LUNAS';
      resText += this.generateSmartFooter(footerCtx, { senderName, hasDebt: unpaidInvoices.length > 0, customerName: custName });

      return resText;
    } catch (e) {
      console.error('[WAVIS RECEIVABLES ERROR]', e.message);
      return `🤖 *[L-W.A.V.I.S]*\nMaaf ${senderName}, terjadi kendala saat membaca database piutang. Silakan ulangi sesaat lagi ya.`;
    }
  }

  /**
   * Menjawab Pertanyaan Stok
   * Cerdas: mendukung pertanyaan stok produk spesifik maupun stok keseluruhan gudang.
   */
  async handleStockQuery(text, senderName = 'Kak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const products = this.autoPoProcessor.cachedProducts || [];
    const clean = normalizeText(text);

    // 1. Cek Pertanyaan STOK KESELURUHAN / TOTAL GUDANG
    const isOverall = /\b(keseluruhan|seluruh|semua|total|rekap|global|gudang fisik|fisik gudang|semuanya)\b/i.test(clean);
    if (isOverall && products.length > 0) {
      let totalPcs = 0;
      let totalKtn = 0;
      const readyList = [];
      const emptyList = [];

      for (const p of products) {
        const stock = Number(p.stock) || 0;
        const isi = Number(p.isiKarton) || 15;
        const ktn = isi > 0 ? (stock / isi) : 0;
        totalPcs += stock;
        totalKtn += ktn;
        if (stock > 0) {
          readyList.push({ name: p.productName || p.name, stock, ktn, price: Number(p.price) || 0 });
        } else {
          emptyList.push({ name: p.productName || p.name });
        }
      }

      readyList.sort((a, b) => b.stock - a.stock);

      let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += `Halo ${senderName}! Berikut rekap ketersediaan stok fisik gudang saat ini:\n\n`;
      resText += `📊 *RINGKASAN TOTAL GUDANG:*\n`;
      resText += `• Total Produk Terdaftar: ${products.length} SKU\n`;
      resText += `• Total Fisik Gudang: *~${Math.round(totalKtn)} Karton* (${totalPcs.toLocaleString('id-ID')} pcs)\n`;
      resText += `• Produk Ready (Siap Kirim): *${readyList.length} Item*\n`;
      resText += `• Produk Kosong / Habis: *${emptyList.length} Item*\n\n`;

      if (readyList.length > 0) {
        resText += `📦 *Top ${Math.min(5, readyList.length)} Produk Paling Ready:*\n`;
        const numEmojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣'];
        readyList.slice(0, 5).forEach((p, idx) => {
          const emoji = numEmojis[idx] || `${idx + 1}.`;
          resText += `${emoji} *${p.name}*\n   ↳ ${Math.round(p.ktn * 10) / 10} Ktn (${p.stock.toLocaleString('id-ID')} pcs) @Rp ${p.price.toLocaleString('id-ID')}\n`;
        });
      }

      resText += `\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += this.generateSmartFooter('STOCK_OVERALL', { senderName });
      return resText;
    }

    // 2. Cek Produk Spesifik
    const matchedProduct = this.matchProductFromQuery(text, products);

    if (!matchedProduct) {
      return `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk mengecek stok gudang, mohon sebutkan nama produknya ya.\n\n` +
        `💡 *Contoh:* ketik \`stok bratwurst mini\` atau \`ready beres merah 24\`.\n` +
        `ℹ️ Atau ketik \`stok keseluruhan\` untuk melihat rekap total gudang.`;
    }

    const pName = matchedProduct.productName || matchedProduct.name || 'PRODUK';
    const isiKtn = Number(matchedProduct.isiKarton) || 15;
    const stockPcs = Number(matchedProduct.stock) || 0;
    const stockKtn = isiKtn > 0 ? (stockPcs / isiKtn) : 0;
    const roundedKtn = Math.round(stockKtn * 10) / 10;
    const price = Number(matchedProduct.price) || 0;

    let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    resText += `Halo ${senderName}! Informasi stok gudang untuk *${pName}*:\n\n`;
    resText += `📦 *Sisa Stok Gudang:* *${roundedKtn} Karton* (${stockPcs.toLocaleString('id-ID')} pcs)\n`;
    resText += `💰 *Harga Standar:* Rp ${price.toLocaleString('id-ID')} / pcs\n`;
    resText += `🏷️ *Status:* ${stockPcs > 0 ? '✅ Ready / Siap Kirim' : '⚠️ Stok Kosong / Habis'}\n\n`;
    resText += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    const stockFooterCtx = stockPcs > 0 ? 'STOCK_SPECIFIC_READY' : 'STOCK_SPECIFIC_EMPTY';
    resText += this.generateSmartFooter(stockFooterCtx, { senderName, isReady: stockPcs > 0, productName: pName });

    return resText;
  }

  /**
   * Menjawab Sapaan & Menampilkan Menu Edukasi
   */
  handleGreetingMenu(senderName = 'Kak') {
    let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    resText += `Halo ${senderName}! 👋\n\n`;
    resText += `Admin / Developer saat ini sedang tidak standby di tempat.\n`;
    resText += `Namun jangan khawatir! Selagi menunggu beliau online, *L-W.A.V.I.S* siap membantu memastikan seluruh urusan operasional Anda tetap berjalan lancar dan cepat.\n\n`;
    resText += `*LAYANAN YANG BISA SAYA PROSES OTOMATIS:*\n`;
    resText += `📝 *1. Buat Pesanan Baru (PO)*\n`;
    resText += `   ↳ Langsung kirim list order toko di sini, draft faktur akan langsung dibuatkan otomatis & masuk antrean kasir.\n\n`;
    resText += `💳 *2. Cek Kartu Piutang Toko*\n`;
    resText += `   ↳ Ketik: \`piutang [nama toko]\` (contoh: *piutang AFM* atau *piutang SJJ*).\n\n`;
    resText += `📦 *3. Cek Stok Barang Gudang*\n`;
    resText += `   ↳ Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst mini*)\n`;
    resText += `   ↳ Atau ketik: \`stok keseluruhan\` untuk melihat rekap total gudang.\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Ada hal operasional yang ingin dicek hari ini ${senderName}? Silakan ketik langsung ya! Untuk pesan pribadi, Admin akan tetap membalas segera setelah aktif kembali. 😊`;

    return resText;
  }

  /**
   * Kirim Pesan Balasan WhatsApp via Baileys Socket
   */
  async sendReply(remoteJid, text, quotedMsg = null, senderPhone = null) {
    if (!remoteJid || !text) return false;
    const sock = this.sockGetter ? this.sockGetter() : null;
    if (!sock) {
      console.warn('[L-W.A.V.I.S] ⚠️ Socket WhatsApp tidak terhubung. Balasan dibatalkan.');
      return false;
    }

    // STRICT: JANGAN PERNAH mengirim balasan interaktif bot ke grup WhatsApp (@g.us)!
    if (remoteJid.endsWith('@g.us')) {
      console.log(`[L-W.A.V.I.S SKIP] 🛑 Membatalkan pengiriman balasan interaktif ke grup WhatsApp (${remoteJid}).`);
      return false;
    }

    // Resolusi Target JID:
    // Jika target adalah WhatsApp LID (@lid) tapi nomor telepon (@s.whatsapp.net) diketahui,
    // prioritaskan kirim ke nomor HP (@s.whatsapp.net) agar tidak terkena delay enkripsi WhatsApp
    // "Menunggu pesan ini. Ini mungkin membutuhkan waktu beberapa saat."
    let targetJid = remoteJid;
    let cleanP = senderPhone ? String(senderPhone).replace(/\D/g, '') : '';
    if (cleanP.startsWith('08')) cleanP = '628' + cleanP.slice(2);

    if (cleanP && cleanP.length >= 8 && targetJid.endsWith('@lid')) {
      targetJid = `${cleanP}@s.whatsapp.net`;
      console.log(`[L-W.A.V.I.S JID RESOLVED] 🔄 Mengalihkan target dari LID ${remoteJid} ke nomor WhatsApp ${targetJid} untuk mencegah delay enkripsi.`);
    }

    try {
      // 1. Simulasi status mengetik ("composing presence")
      try {
        await sock.sendPresenceUpdate('composing', targetJid);
        await new Promise(r => setTimeout(r, 1200)); // jeda 1.2 detik agar natural
        await sock.sendPresenceUpdate('paused', targetJid);
      } catch (_) {}

      // 2. Kirim pesan balasan
      const options = {};
      if (quotedMsg) {
        options.quoted = quotedMsg;
      }

      const sentMsg = await sock.sendMessage(targetJid, { text }, options);
      console.log(`[L-W.A.V.I.S SUCCESS] 🤖 Pesan interaktif berhasil dikirim ke ${targetJid}!`);

      // Simpan pesan keluar ke dalam cache getMessage untuk antisipasi retry E2EE ("Menunggu pesan ini...")
      if (sentMsg && sentMsg.key && sentMsg.message && typeof this.rawMessageStore === 'function') {
        const msgId = sentMsg.key.id;
        this.rawMessageStore(targetJid, msgId, sentMsg.message);
        if (remoteJid && remoteJid !== targetJid) {
          this.rawMessageStore(remoteJid, msgId, sentMsg.message);
        }
        if (sentMsg.key.remoteJid && sentMsg.key.remoteJid !== targetJid) {
          this.rawMessageStore(sentMsg.key.remoteJid, msgId, sentMsg.message);
        }
      }

      return true;
    } catch (err) {
      console.error('[L-W.A.V.I.S SEND ERROR]', err.message);
      return false;
    }
  }
}

module.exports = WavisInteractiveEngine;
