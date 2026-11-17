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
  formatPoConfirmation(invoiceData, senderName = 'Kak', options = {}) {
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

    const title = options.title || 'PESAN OTOMATIS: L-W.A.V.I.S';
    const subtitle = options.subtitle || `Draft pesanan berhasil diproses ke sistem:`;
    const isRevised = !!options.isRevised;
    const isQuery = !!options.isQuery;

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

    // Helper isiKarton fallback
    const cachedProds = this.autoPoProcessor?.cachedProducts || [];
    const getIsiKtn = (it) => {
      if (typeof it.isiKarton === 'number' && it.isiKarton > 0) return it.isiKarton;
      if (cachedProds.length > 0) {
        const found = cachedProds.find(p => (it.productId && p.id === it.productId) || (it.productName && (p.productName === it.productName || p.name === it.productName)));
        if (found && found.isiKarton) return Number(found.isiKarton);
      }
      return 15;
    };

    // Hitung total karton
    let totalCarton = 0;
    for (const it of items) {
      if (typeof it.cartonCount === 'number' && it.cartonCount > 0) {
        totalCarton += it.cartonCount;
      } else {
        const pcsPerKtn = getIsiKtn(it);
        totalCarton += (it.qty || 0) / pcsPerKtn;
      }
    }

    const numberEmojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟'];

    let text = `🤖 *[${title}]*\n`;
    text += `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n`;
    text += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    text += `Halo ${senderName}! ${subtitle}\n\n`;
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
      const revisedTag = it._isRevised ? ' 🔄 *(DIREVISI)*' : '';
      
      const pcsPerKtn = getIsiKtn(it);
      const ktnVal = it.cartonCount || (pcsPerKtn ? Math.round(it.qty / pcsPerKtn * 10) / 10 : null);
      const ktnStr = ktnVal ? `${ktnVal} Ktn` : `${it.qty} pcs`;
      const priceStr = Math.round(it.price || 0).toLocaleString('id-ID');
      
      let discStr = ' | Disc: -';
      if ((it.discountPercent && it.discountPercent > 0) || (it.discountAmount && it.discountAmount > 0)) {
        const pct = it.discountPercent ? `${it.discountPercent}%` : '';
        const amt = it.discountAmount ? `(-${Math.round(it.discountAmount).toLocaleString('id-ID')})` : '';
        discStr = ` | Disc ${pct} ${amt}`.trim();
      }

      const subtotalStr = Math.round(it.subtotal || 0).toLocaleString('id-ID');

      text += `${num} *${pName}*${weightStr}${revisedTag}\n`;
      text += `   ${ktnStr} (${it.qty} pcs) @${priceStr}${discStr} = *Rp ${subtotalStr}*\n\n`;
    });

    text += `────────────────────\n`;
    text += `📦 *GrandTotal Karton:* ${Math.round(totalCarton * 10) / 10} Ktn\n`;
    text += `💰 *GRAND TOTAL:* *Rp ${Math.round(grandTotal || 0).toLocaleString('id-ID')}*\n`;
    if (note && note.trim().length > 0) {
      text += `📝 *Catatan:* ${note.trim()}\n`;
    }
    text += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    text += `ℹ️ *Catatan Sistem:*\n`;
    if (isRevised) {
      text += `• Perubahan data barang dan total faktur telah tersinkronisasi otomatis.\n`;
      text += `• Status faktur tetap ${status || 'PENDING'} menunggu proses armada logistik.\n`;
      text += `• Jika ada pesan personal untuk Admin, beliau akan membalas segera setelah aktif kembali. 😊`;
    } else if (isQuery) {
      text += `• Data faktur diambil langsung dari Database Transaksi.\n`;
      text += `• Selagi Admin belum standby, L-W.A.V.I.S siap bantu cek stok barang atau proses pesanan lainnya. 😊`;
    } else {
      text += `• Faktur sudah aman masuk Database Transaksi.\n`;
      text += `• Jika ada pesan personal untuk Admin, beliau akan membalas segera setelah aktif kembali. 😊`;
    }

    return text;
  }

  /**
   * Klasifikasi Maksud Chat (Intent Recognition Lokal)
   * Mendukung query piutang, stok, faktur/invoice, revisi PO, sapaan/menu, dan fallback cerdas.
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

    // 3. Cek Pola Query Faktur / Invoice
    const invoicePattern = /\b(faktur|invoice|nota)\b|\b(?:data|cek|tampilkan|lihat|info|kirimkan)\s+po\b|\bpo\s*(?:no|nomor|nomer|#)?\s*\d{2,6}\b/i;
    if (invoicePattern.test(clean)) {
      if (/\b(revisi|ubah|ganti|tambah|kurang|batal|edit)\b/i.test(clean)) {
        return 'REVISE_PO';
      }
      return 'QUERY_INVOICE';
    }

    // 4. Cek Pola Revisi PO
    const revisionPattern = /\b(revisi|ubah|ganti|tambah|kurang|batal|edit)\b.*?\b(po|order|pesanan|karton|ktn|dus|box|jadi|pcs)\b|\b(revisi|ubah|ganti)\s+po\b/i;
    if (revisionPattern.test(clean)) {
      return 'REVISE_PO';
    }

    // 5. Cek Pola Sapaan / Menu Bantuan / Pertanyaan Kemampuan AI
    const greetingPattern = /\b(halo|hello|pagi|siang|sore|malam|assalamualaikum|bantuan|menu|wavis|hai|bisa apa|bisa bantu apa|tugasmu|fungsi wavis|siapa kamu|fitur|cara pakai|standby)\b/i;
    if (greetingPattern.test(clean)) {
      return 'GREETING_MENU';
    }

    // 6. Cek Pola Pertanyaan / Instruksi Operasional Umum (Smart Fallback agar bot TIDAK BISU)
    const inquiryPattern = /\b(apakah|bisa|bisakah|tolong|bagaimana|gimana|tampilkan|kirimkan|cek|info|tanya|minta|adakah)\b|\?/i;
    if (inquiryPattern.test(clean)) {
      return 'SMART_FALLBACK';
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
        lastPayStr = `Rp ${Math.round(lastPaymentInfo.amount || 0).toLocaleString('id-ID')}${tgl}${bName}`;
      }

      let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += `Halo ${senderName}! Berikut ringkasan kartu piutang untuk *${custName}${alias}*:\n\n`;
      resText += `💳 *Total Sisa Piutang:* *Rp ${Math.round(totalRemaining || 0).toLocaleString('id-ID')}*\n`;
      resText += `📑 *Jumlah Faktur Belum Lunas:* ${unpaidInvoices.length} Invoice\n`;
      resText += `🗓️ *Cicilan / Pembayaran Terakhir:* ${lastPayStr}\n\n`;

      if (unpaidInvoices.length > 0) {
        resText += `*Daftar Faktur Belum Lunas:*\n`;
        unpaidInvoices.slice(0, 5).forEach((inv, i) => {
          const rem = Math.round((Number(inv.grandTotal) || 0) - (Number(inv.paidAmount) || 0));
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
      // Kelompokkan produk berdasarkan kodeInduk agar produk fisik yang sama tidak dihitung dobel
      // (contoh: KAL-400 & KAL-400-2 memiliki fisik sama 480 pcs / 24 ktn, hanya beda tier harga)
      const parentGroups = new Map();
      for (const p of products) {
        const ki = (p.kodeInduk || p.kode_induk || p.id || '').trim().toUpperCase();
        if (!parentGroups.has(ki)) {
          parentGroups.set(ki, []);
        }
        parentGroups.get(ki).push(p);
      }

      let totalPcs = 0;
      let totalKtn = 0;
      const readyList = [];
      const emptyList = [];

      for (const [ki, variantList] of parentGroups.entries()) {
        const primaryProd = variantList.find(v => !v.id.endsWith('-2') && !v.id.endsWith('-3')) || variantList[0];
        const stock = Number(primaryProd.stock) || 0;
        const isi = Number(primaryProd.isiKarton) || 15;
        const ktn = isi > 0 ? (stock / isi) : 0;

        totalPcs += stock;
        totalKtn += ktn;

        let displayName = primaryProd.productName || primaryProd.name || ki;
        if (displayName.includes(' 2 400G')) displayName = displayName.replace(' 2 400G', ' 400 G');
        if (displayName.includes(' 2 500G')) displayName = displayName.replace(' 2 500G', ' 500 G');

        const prices = Array.from(new Set(variantList.map(v => Number(v.price) || 0).filter(pr => pr > 0))).sort((a, b) => a - b);
        let priceStr = '';
        if (prices.length === 1) {
          priceStr = `Rp ${Math.round(prices[0]).toLocaleString('id-ID')}`;
        } else if (prices.length > 1) {
          priceStr = `Rp ${Math.round(prices[0]).toLocaleString('id-ID')} - Rp ${Math.round(prices[prices.length - 1]).toLocaleString('id-ID')}`;
        }

        if (stock > 0) {
          readyList.push({
            name: displayName,
            stock,
            ktn,
            priceStr
          });
        } else {
          emptyList.push({ name: displayName });
        }
      }

      readyList.sort((a, b) => b.stock - a.stock);

      let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += `Halo ${senderName}! Berikut rekap ketersediaan stok fisik gudang saat ini:\n\n`;
      resText += `📊 *RINGKASAN TOTAL GUDANG:*\n`;
      resText += `• Total Produk Terdaftar: ${products.length} SKU (${parentGroups.size} Produk Induk Fisik)\n`;
      resText += `• Total Fisik Gudang: *~${Math.round(totalKtn)} Karton* (${totalPcs.toLocaleString('id-ID')} pcs)\n`;
      resText += `• Produk Fisik Ready: *${readyList.length} Item*\n`;
      resText += `• Produk Fisik Kosong: *${emptyList.length} Item*\n\n`;

      if (readyList.length > 0) {
        resText += `📦 *Top ${Math.min(5, readyList.length)} Produk Paling Ready:*\n`;
        const numEmojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣'];
        readyList.slice(0, 5).forEach((p, idx) => {
          const emoji = numEmojis[idx] || `${idx + 1}.`;
          const prc = p.priceStr ? ` @${p.priceStr}` : '';
          resText += `${emoji} *${p.name}*\n   ↳ ${Math.round(p.ktn * 10) / 10} Ktn (${p.stock.toLocaleString('id-ID')} pcs)${prc}\n`;
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
    resText += `💰 *Harga Standar:* Rp ${Math.round(price).toLocaleString('id-ID')} / pcs\n`;
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
    resText += `🔄 *4. Revisi PO (Khusus Status PENDING)*\n`;
    resText += `   ↳ Quote/balas pesanan dengan: \`revisi PO [nama barang] jadi [jumlah] karton\`.\n\n`;
    resText += `📄 *5. Cek Rincian Faktur / Invoice*\n`;
    resText += `   ↳ Ketik: \`faktur [nomor]\` (contoh: *faktur 697* atau *kirimkan data PO nomor invoice 697*).\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Ada hal operasional yang ingin dicek hari ini ${senderName}? Silakan ketik langsung ya! Untuk pesan pribadi, Admin akan tetap membalas segera setelah aktif kembali. 😊`;

    return resText;
  }

  /**
   * Menampilkan Data Faktur / Invoice Spesifik (#693, #697, #699, dll)
   */
  async handleInvoiceQuery(text, senderName = 'Kak') {
    const clean = normalizeText(text);
    // Regex presisi multi-tahap: Menangani 'kirimkan data PO nomor invoice 697', 'faktur 699', 'invoice #693', dll.
    const regexPrefix = /(?:faktur|invoice|nota|po|nomor|nomer|#)\s*[:#.]?\s*([a-zA-Z]{1,3}\d{1,6})\b/i;
    const regexDistance = /(?:faktur|invoice|nota|po).*?\b(\d{2,8})\b/i;
    const regexAnyNumber = /\b(\d{2,8})\b/;
    const match = clean.match(regexPrefix) || clean.match(regexDistance) || clean.match(regexAnyNumber);
    
    if (!match || !match[1]) {
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk menampilkan rincian data faktur atau invoice, mohon sebutkan nomor fakturnya ya. 😊\n\n` +
        `💡 *Contoh:* ketik \`faktur 697\` atau \`kirimkan data PO nomor invoice 697\`.`;
    }

    const rawInv = match[1].replace(/^[#]/, '').trim();
    const invNo = rawInv;

    try {
      const db = this.firebaseAdapter?.db || this.firebaseAdapter?.clientDb;
      let invData = null;

      if (!db && this.mockInvoices) {
        invData = this.mockInvoices[invNo] || null;
      } else if (!db) {
        return `⚠️ Maaf ${senderName}, koneksi database sedang tidak tersedia. Mohon coba beberapa saat lagi.`;
      }

      if (!invData && db && this.firebaseAdapter && this.firebaseAdapter.mode === 'admin') {
        const snap = await db.collection('transactions').doc(invNo).get();
        if (snap.exists) {
          invData = snap.data();
        } else {
          const qSnap = await db.collection('transactions').where('invoiceNo', '==', invNo).limit(1).get();
          if (!qSnap.empty) invData = qSnap.docs[0].data();
        }
      } else if (!invData && db && this.firebaseAdapter && this.firebaseAdapter.clientSdk) {
        const { doc, getDoc, collection, query, where, getDocs, limit } = this.firebaseAdapter.clientSdk;
        const snap = await getDoc(doc(db, 'transactions', invNo));
        if (snap.exists()) {
          invData = snap.data();
        } else {
          const qSnap = await getDocs(query(collection(db, 'transactions'), where('invoiceNo', '==', invNo), limit(1)));
          if (!qSnap.empty) invData = qSnap.docs[0].data();
        }
      }

      if (!invData) {
        return `🤖 *[L-W.A.V.I.S]*\n` +
          `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
          `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
          `Halo ${senderName}! Data Faktur / Invoice *#${invNo}* tidak ditemukan di dalam sistem database. ❌\n\n` +
          `Mohon periksa kembali nomor fakturnya ya! Jika butuh bantuan lebih lanjut, Admin akan siap membantu setelah aktif kembali. 😊`;
      }

      if (!invData.invoiceNo) invData.invoiceNo = invNo;

      return this.formatPoConfirmation(invData, senderName, {
        title: 'DETAIL FAKTUR: L-W.A.V.I.S',
        subtitle: `Berikut rincian data Faktur #${invNo} yang tercatat di sistem:`,
        isQuery: true
      });
    } catch (err) {
      console.error('[L-W.A.V.I.S QUERY INVOICE ERROR]', err.message);
      return `⚠️ Maaf ${senderName}, terjadi kendala saat mengambil data faktur: ${err.message}`;
    }
  }

  /**
   * Menangani Revisi Pesanan PO (SOP Bisnis: PENDING revisi otomatis, DIKIRIM wajib manual kasir/admin)
   */
  async handlePoRevision(payload, senderName = 'Kak') {
    const text = typeof payload === 'string' ? payload : (payload.messageText || '');
    const clean = normalizeText(text);

    if (this.autoPoProcessor && typeof this.autoPoProcessor.refreshCacheIfNeeded === 'function') {
      await this.autoPoProcessor.refreshCacheIfNeeded();
    }
    const customers = this.autoPoProcessor?.cachedCustomers || [];
    const products = this.autoPoProcessor?.cachedProducts || [];
    const db = this.firebaseAdapter?.db || this.firebaseAdapter?.clientDb;

    // 1. CARI NOMOR FAKTUR TARGET
    let targetInvNo = null;

    // A. Eksplisit dari teks (misal: "revisi PO 699", "ubah faktur #693")
    const explicitInvMatch = text.match(/(?:invoice|faktur|nota|po|#)\s*[:#.]?\s*(\d{2,6})/i);
    if (explicitInvMatch) {
      targetInvNo = explicitInvMatch[1];
    }

    // B. Dari Quoted Reply (quotedStanzaId dicari di incoming_po_chats)
    if (!targetInvNo && payload && payload.quotedStanzaId && db) {
      try {
        let chatSnap = null;
        if (this.firebaseAdapter.mode === 'admin') {
          const snap1 = await db.collection('incoming_po_chats').where('messageId', '==', payload.quotedStanzaId).limit(1).get();
          if (!snap1.empty) {
            chatSnap = snap1.docs[0].data();
          } else {
            const snap2 = await db.collection('incoming_po_chats').where('messageIds', 'array-contains', payload.quotedStanzaId).limit(1).get();
            if (!snap2.empty) chatSnap = snap2.docs[0].data();
          }
        } else if (this.firebaseAdapter.clientSdk) {
          const { collection, query, where, getDocs, limit } = this.firebaseAdapter.clientSdk;
          const snap1 = await getDocs(query(collection(db, 'incoming_po_chats'), where('messageId', '==', payload.quotedStanzaId), limit(1)));
          if (!snap1.empty) {
            chatSnap = snap1.docs[0].data();
          } else {
            const snap2 = await getDocs(query(collection(db, 'incoming_po_chats'), where('messageIds', 'array-contains', payload.quotedStanzaId), limit(1)));
            if (!snap2.empty) chatSnap = snap2.docs[0].data();
          }
        }

        if (chatSnap && (chatSnap.createdInvoiceNo || chatSnap.createdTransactionId)) {
          const rawInv = String(chatSnap.createdInvoiceNo || chatSnap.createdTransactionId);
          targetInvNo = rawInv.replace(/\D/g, '');
        }
      } catch (e) {
        console.warn('[REVISI QUOTE LOOKUP WARN]', e.message);
      }
    }

    // C. Cek apakah ada invoice number di quotedMessageText (misal: "No. Invoice: #699")
    if (!targetInvNo && payload && payload.quotedMessageText) {
      const qInvMatch = payload.quotedMessageText.match(/(?:invoice|faktur|nota|po|#)\s*[:#.]?\s*(\d{2,6})/i);
      if (qInvMatch) {
        targetInvNo = qInvMatch[1];
      }
    }

    // D. Jika belum dapat, cari customer dari quotedMessageText atau text
    let targetCustomer = null;
    if (payload && payload.quotedMessageText) {
      targetCustomer = this.matchCustomerFromQuery(payload.quotedMessageText, customers);
    }
    if (!targetCustomer) {
      targetCustomer = this.matchCustomerFromQuery(text, customers);
    }

    let invDocRef = null;
    let invData = null;

    if (targetInvNo && db) {
      if (this.firebaseAdapter.mode === 'admin') {
        const snap = await db.collection('transactions').doc(targetInvNo).get();
        if (snap.exists) {
          invDocRef = db.collection('transactions').doc(targetInvNo);
          invData = snap.data();
        } else {
          const qSnap = await db.collection('transactions').where('invoiceNo', '==', targetInvNo).limit(1).get();
          if (!qSnap.empty) {
            invDocRef = qSnap.docs[0].ref;
            invData = qSnap.docs[0].data();
          }
        }
      } else if (this.firebaseAdapter.clientSdk) {
        const { doc, getDoc, collection, query, where, getDocs, limit } = this.firebaseAdapter.clientSdk;
        const snap = await getDoc(doc(db, 'transactions', targetInvNo));
        if (snap.exists()) {
          invDocRef = doc(db, 'transactions', targetInvNo);
          invData = snap.data();
        } else {
          const qSnap = await getDocs(query(collection(db, 'transactions'), where('invoiceNo', '==', targetInvNo), limit(1)));
          if (!qSnap.empty) {
            invDocRef = qSnap.docs[0].ref;
            invData = qSnap.docs[0].data();
          }
        }
      }
    } else if (targetCustomer && db) {
      try {
        if (this.firebaseAdapter.mode === 'admin') {
          const qPending = await db.collection('transactions')
            .where('customerId', '==', targetCustomer.id)
            .where('status', '==', 'PENDING')
            .limit(5)
            .get();
          if (!qPending.empty) {
            invDocRef = qPending.docs[0].ref;
            invData = qPending.docs[0].data();
            targetInvNo = invData.invoiceNo || qPending.docs[0].id;
          } else {
            const qAny = await db.collection('transactions')
              .where('customerId', '==', targetCustomer.id)
              .limit(5)
              .get();
            if (!qAny.empty) {
              invDocRef = qAny.docs[0].ref;
              invData = qAny.docs[0].data();
              targetInvNo = invData.invoiceNo || qAny.docs[0].id;
            }
          }
        } else if (this.firebaseAdapter.clientSdk) {
          const { collection, query, where, getDocs, limit } = this.firebaseAdapter.clientSdk;
          const qPending = await getDocs(query(collection(db, 'transactions'), where('customerId', '==', targetCustomer.id), where('status', '==', 'PENDING'), limit(5)));
          if (!qPending.empty) {
            invDocRef = qPending.docs[0].ref;
            invData = qPending.docs[0].data();
            targetInvNo = invData.invoiceNo || qPending.docs[0].id;
          } else {
            const qAny = await getDocs(query(collection(db, 'transactions'), where('customerId', '==', targetCustomer.id), limit(5)));
            if (!qAny.empty) {
              invDocRef = qAny.docs[0].ref;
              invData = qAny.docs[0].data();
              targetInvNo = invData.invoiceNo || qAny.docs[0].id;
            }
          }
        }
      } catch (e) {
        console.warn('[REVISI CUSTOMER LOOKUP WARN]', e.message);
      }
    }

    // Fallback untuk unit testing tanpa live db: dukung payload.mockInvoice
    if (!invData && payload && payload.mockInvoice) {
      invData = payload.mockInvoice;
      targetInvNo = invData.invoiceNo || 'MOCK';
    }

    if (!invData || !targetInvNo) {
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk merevisi pesanan, mohon sebutkan nomor fakturnya atau quote (balas) pesan PO yang ingin direvisi ya. 😊\n\n` +
        `💡 *Contoh:* \`revisi PO 699 brs merah jadi 35 karton\`\n` +
        `Atau quote chat rincian order sebelumnya dengan ketik \`revisi brs merah jadi 35 karton\`.`;
    }

    // 2. SOP BISNIS MUTLAK: CEK STATUS FAKTUR (DIKIRIM VS PENDING)
    const statusFaktur = String(invData.status || 'PENDING').toUpperCase();
    const customerDisplay = invData.aliasName ? `${invData.aliasName} (${invData.customerName})` : (invData.customerName || 'Toko Pelanggan');

    if (statusFaktur === 'DIKIRIM') {
      return `⚠️ *[REVISI PO DITOLAK: SUDAH DIKIRIM]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}!\n\n` +
        `Mohon maaf, Faktur *#${targetInvNo}* untuk *${customerDisplay}* saat ini sudah berstatus *DIKIRIM* 🚚 (barang sudah diserahkan ke armada pengiriman / logistik).\n\n` +
        `⛔ Sesuai SOP operasional, pesanan yang sudah *DIKIRIM* tidak dapat direvisi secara otomatis oleh L-W.A.V.I.S.\n\n` +
        `📞 *Tindakan Selanjutnya:*\n` +
        `Silakan hubungi Admin / Kasir secara langsung untuk penyesuaian manual (surat jalan susulan atau retur ya). 🙏\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        this.generateSmartFooter('PO_REVISION_REJECTED', { senderName });
    }

    // 3. JIKA STATUS PENDING -> LAKUKAN PARSING & REVISI
    const items = Array.isArray(invData.items) ? [...invData.items] : [];
    if (items.length === 0) {
      return `⚠️ Faktur #${targetInvNo} tidak memiliki daftar barang yang dapat direvisi.`;
    }

    // Ekstrak kuantiti karton baru
    let newCartonQty = null;
    const m1 = text.match(/(?:jadi|menjadi|ganti|ubah|revisi)\s*(\d+)/i);
    if (m1) {
      newCartonQty = parseInt(m1[1], 10);
    } else {
      const m2 = text.match(/(\d+)\s*(?:karton|ktn|dus|box|bal|ball)\b/i);
      if (m2) newCartonQty = parseInt(m2[1], 10);
    }

    if (!newCartonQty || newCartonQty <= 0) {
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Jumlah karton baru belum terdeteksi dengan jelas pada Faktur #${targetInvNo}.\n\n` +
        `💡 *Contoh format:* \`revisi PO brs merah jadi 35 karton\``;
    }

    // Cocokkan produk yang ingin diubah di dalam items
    const queryProdText = clean
      .replace(/\b(revisi|ubah|ganti|tambah|kurang|edit|batal|po|faktur|invoice|jadi|menjadi|karton|ktn|dus|box|pcs|pack|pak|\d+)\b/g, '')
      .replace(/\s+/g, ' ')
      .trim();

    let matchedItemIndex = -1;
    let maxItemScore = 0;
    const prodWords = queryProdText.split(/\s+/).filter(w => w.length >= 2);

    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const itName = normalizeText(it.productName || '');
      let score = 0;
      for (const pw of prodWords) {
        const pwNorm = pw.replace(/^beres$/, 'brs').replace(/^brs$/, 'beres');
        if (itName.includes(pw) || itName.includes(pwNorm)) {
          score += 5;
        }
      }
      if (score > maxItemScore && score >= 5) {
        maxItemScore = score;
        matchedItemIndex = i;
      }
    }

    if (matchedItemIndex === -1) {
      const currentItemList = items.map((it, idx) => `${idx + 1}. ${it.productName}`).join('\n');
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Barang yang ingin direvisi pada Faktur *#${targetInvNo}* tidak cocok dengan daftar faktur saat ini.\n\n` +
        `*Barang yang ada di Faktur #${targetInvNo}:*\n${currentItemList}\n\n` +
        `💡 *Contoh:* \`revisi PO brs merah jadi ${newCartonQty} karton\``;
    }

    // Update item yang cocok
    const targetItem = { ...items[matchedItemIndex] };
    const getIsiKtn = (it) => {
      if (typeof it.isiKarton === 'number' && it.isiKarton > 0) return it.isiKarton;
      const found = products.find(p => (it.productId && p.id === it.productId) || (it.productName && (p.productName === it.productName || p.name === it.productName)));
      if (found && found.isiKarton) return Number(found.isiKarton);
      if (it.cartonCount > 0 && it.qty > 0) return Math.round(it.qty / it.cartonCount);
      return 15;
    };

    const isiKtn = getIsiKtn(targetItem);
    const newQtyPcs = newCartonQty * isiKtn;
    const unitPrice = Number(targetItem.price) || 0;
    const discPct = Number(targetItem.discountPercent) || 0;
    const discAmt = Number(targetItem.discountAmount) || 0;
    const grossTotal = newQtyPcs * unitPrice;
    const calcDiscAmt = discPct > 0 ? (grossTotal * discPct / 100) : (discAmt > 0 ? discAmt : 0);
    const newSubtotal = Math.round(grossTotal - calcDiscAmt);

    targetItem.cartonCount = newCartonQty;
    targetItem.qty = newQtyPcs;
    targetItem.subtotal = newSubtotal;
    if (targetItem.sizeGrams) {
      targetItem.weightKg = (newQtyPcs * Number(targetItem.sizeGrams)) / 1000;
    }
    targetItem._isRevised = true;

    items[matchedItemIndex] = targetItem;

    // Hitung ulang grand total invoice
    let newGrandTotal = 0;
    for (const it of items) {
      newGrandTotal += (it.isBonus ? 0 : Number(it.subtotal || 0));
    }
    invData.items = items;
    invData.grandTotal = Math.round(newGrandTotal);

    // Simpan pembaruan ke Firestore jika terhubung
    const cleanItemsForDb = items.map(it => {
      const c = { ...it };
      delete c._isRevised;
      return c;
    });

    const revisionNote = `Revisi WA L-W.A.V.I.S: ${targetItem.productName} -> ${newCartonQty} ktn`;
    const existingNote = invData.note ? invData.note.trim() : '';
    const updatedNote = existingNote ? `${existingNote} | ${revisionNote}` : revisionNote;

    try {
      if (invDocRef) {
        const updatePayload = {
          items: cleanItemsForDb,
          grandTotal: invData.grandTotal,
          note: updatedNote,
          updatedAt: new Date()
        };
        if (this.firebaseAdapter?.mode === 'admin') {
          await invDocRef.update(updatePayload);
        } else if (this.firebaseAdapter?.clientSdk) {
          const { updateDoc } = this.firebaseAdapter.clientSdk;
          await updateDoc(invDocRef, updatePayload);
        }
      }

      if (payload && payload.chatDocId && this.firebaseAdapter?.updateChatDocument) {
        await this.firebaseAdapter.updateChatDocument(payload.chatDocId, {
          status: 'processed',
          createdInvoiceNo: `${targetInvNo} (UPDATED)`,
          createdTransactionId: targetInvNo,
          isReplySent: true
        });
      }

      // Format balasan konfirmasi resmi revisi
      return this.formatPoConfirmation(invData, senderName, {
        title: 'REVISI PO BERHASIL DIPROSES: L-W.A.V.I.S',
        subtitle: `Revisi pesanan Faktur #${targetInvNo} berhasil diperbarui di sistem:`,
        isRevised: true
      });
    } catch (err) {
      console.error('[L-W.A.V.I.S UPDATE TRANSACTION ERROR]', err.message);
      return `⚠️ Gagal memperbarui transaksi #${targetInvNo}: ${err.message}`;
    }
  }

  /**
   * Menjawab Pertanyaan / Instruksi Umum Edukatif (Anti Bot Diam / Bisu)
   */
  handleSmartFallback(text, senderName = 'Kak') {
    let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    resText += `Halo ${senderName}! 👋\n\n`;
    resText += `Saya memahami pesan Anda, namun saat ini perintah tersebut belum terhubung ke sistem otomatis saya.\n\n`;
    resText += `*5 LAYANAN UTAMA YANG DAPAT SAYA PROSES OTOMATIS:*\n`;
    resText += `📝 *1. Buat Pesanan Baru (PO)*\n`;
    resText += `   ↳ Kirimkan rincian order toko di sini untuk langsung dibuatkan draft faktur.\n\n`;
    resText += `🔄 *2. Revisi PO (Khusus Status PENDING)*\n`;
    resText += `   ↳ Quote/balas pesanan dengan: \`revisi PO [nama barang] jadi [jumlah] karton\`.\n\n`;
    resText += `💳 *3. Cek Kartu Piutang Toko*\n`;
    resText += `   ↳ Ketik: \`piutang [nama toko]\` (contoh: *piutang AFM* atau *piutang SJJ*).\n\n`;
    resText += `📦 *4. Cek Stok Fisik Gudang*\n`;
    resText += `   ↳ Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst*) atau \`stok keseluruhan\`.\n\n`;
    resText += `📄 *5. Cek Rincian Faktur / Invoice*\n`;
    resText += `   ↳ Ketik: \`faktur [nomor]\` (contoh: *faktur 699* atau *invoice #693*).\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Untuk hal-hal di luar 5 layanan otomatis di atas atau pesan personal untuk Admin, beliau akan membalas segera setelah aktif kembali ya! 😊`;

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

    // Target JID: Balas langsung ke remoteJid tempat pesan masuk
    // (Bila pesan masuk dari @lid, balas langsung ke @lid agar tetap di thread yang sama pada WA pengirim & penerima)
    const targetJid = remoteJid;

    try {
      // 1. Simulasi status mengetik ("composing presence")
      try {
        await sock.sendPresenceUpdate('composing', targetJid);
        await new Promise(r => setTimeout(r, 1200)); // jeda 1.2 detik agar natural
        await sock.sendPresenceUpdate('paused', targetJid);
      } catch (_) {}

      // 2. Kirim pesan balasan
      const options = {};
      if (quotedMsg && typeof quotedMsg === 'object' && quotedMsg.key) {
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
        if (senderPhone) {
          let cleanP = String(senderPhone).replace(/\D/g, '');
          if (cleanP.startsWith('08')) cleanP = '628' + cleanP.slice(2);
          if (cleanP) {
            this.rawMessageStore(`${cleanP}@s.whatsapp.net`, msgId, sentMsg.message);
          }
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
