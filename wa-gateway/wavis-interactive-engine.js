/**
 * WAVIS INTERACTIVE ENGINE (Tahap 3)
 * L-W.A.V.I.S: Lucifax-Whatsapp Assistant Vision Interactive System
 * 
 * Modul cerdas interaktif lokal dua arah untuk membalas konfirmasi pesanan (PO),
 * melayani cek piutang, cek stok, dan memberikan bantuan saat admin sedang tidak standby.
 * 100% Native / Lokal tanpa ketergantungan API pihak ketiga.
 */

const WavisPdfGenerator = require('./wavis-pdf-generator');

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

    // Hitung total karton (selaras dengan it.qty dan isiKarton)
    let totalCarton = 0;
    for (const it of items) {
      const pcsPerKtn = getIsiKtn(it);
      const safeQty = (typeof it.qty === 'number' && !isNaN(it.qty)) ? it.qty : 0;
      const ktn = (pcsPerKtn > 0 && safeQty > 0)
        ? (safeQty / pcsPerKtn)
        : ((typeof it.cartonCount === 'number' && !isNaN(it.cartonCount) && it.cartonCount > 0) ? it.cartonCount : 0);
      totalCarton += ktn;
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
      const revisedTag = it._isAdded ? ' ➕ *(DITAMBAHKAN)*' : (it._isSwapped ? ' 🔄 *(DIGANTI)*' : (it._isRevised ? ' 🔄 *(DIREVISI)*' : ''));
      
      const pcsPerKtn = getIsiKtn(it);
      const safeQty = (typeof it.qty === 'number' && !isNaN(it.qty)) ? it.qty : 0;
      const ktnVal = (pcsPerKtn > 0 && safeQty > 0)
        ? Math.round(safeQty / pcsPerKtn * 10) / 10
        : ((typeof it.cartonCount === 'number' && !isNaN(it.cartonCount) && it.cartonCount > 0) ? it.cartonCount : null);
      const ktnStr = ktnVal ? `${ktnVal} Ktn` : `${safeQty} pcs`;
      const priceStr = Math.round(it.price || 0).toLocaleString('id-ID');
      
      let discStr = ' | Disc: -';
      if ((it.discountPercent && it.discountPercent > 0) || (it.discountAmount && it.discountAmount > 0)) {
        const pct = it.discountPercent ? `${it.discountPercent}%` : '';
        const amt = it.discountAmount ? `(-${Math.round(it.discountAmount).toLocaleString('id-ID')})` : '';
        discStr = ` | Disc ${pct} ${amt}`.trim();
      }

      const subtotalStr = Math.round(it.subtotal || 0).toLocaleString('id-ID');

      text += `${num} *${pName}*${weightStr}${revisedTag}\n`;
      text += `   ${ktnStr} (${safeQty} pcs) @${priceStr}${discStr} = *Rp ${subtotalStr}*\n\n`;
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
   * Mendukung query piutang, stok, faktur/invoice, revisi PO, kirim file PDF, sapaan/menu, dan fallback cerdas.
   */
  classifyIntent(text, products = []) {
    const clean = normalizeText(text);
    if (!clean) return 'UNKNOWN';

    const isPdfRequest = /\b(?:file\s*pdf|format\s*pdf|dokumen\s*pdf|cetak\s*pdf|unduh\s*pdf|download\s*pdf|pdf)\b/i.test(clean);

    // 1. Cek Pola Tanya Piutang / Minta File Dokumen PDF Piutang
    const piutangPattern = /\b(piutang|utang|bon|tagihan|sisa tagihan|sisa piutang|belum bayar)\b/i;
    if (piutangPattern.test(clean)) {
      if (isPdfRequest) {
        return 'SEND_PDF_RECEIVABLES';
      }
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

    // 3. Cek Pola Revisi PO / Tukar Barang / Hapus Barang / Tambah Barang
    const revisionPattern = /\b(revisi|ubah|ganti|tambah|tambahkan|tambahan|kurang|batal|edit|tukar|hapus|buang|hilangkan|cancel|coret)\b[\s\S]*?\b(po|order|pesanan|karton|ktn|krton|krtn|krt|dus|box|jadi|pcs|pack|pak|bal|ball|roll|rol|dengan|ke|saja|aja)\b|\b(revisi|ubah|ganti|tukar|hapus|batalkan|tambah|tambahkan|tambahan)\s+(?:po|item|barang|orderan|tambahan)?\b|^(?:tolong\s+|mohon\s+)?(?:tambah|tambahkan|tambahan)\b|\b(?:di\s*ganti|di\s*tukar|di\s*hapus|hapus\s*saja|dihapus\s*saja|di\s*buang|buang\s*saja|dibuang\s*saja|di\s*tambah(?:kan)?)\b/i;
    if (revisionPattern.test(clean)) {
      return 'REVISE_PO';
    }

    // 4. Cek Pola Query Faktur / Invoice atau Permintaan File Dokumen PDF Faktur
    const invoicePattern = /\b(faktur|invoice|nota)\b|\b(?:data|cek|tampilkan|lihat|info|kirimkan)\s+po\b|\bpo\s*(?:no|nomor|nomer|#)?\s*\d{2,6}\b/i;
    if (invoicePattern.test(clean) || (isPdfRequest && /\b\d{2,6}\b/.test(clean))) {
      if (/\b(revisi|ubah|ganti|tambah|tambahkan|kurang|batal|edit|tukar|hapus|dihapus|di\s*hapus|buang|dibuang|cancel|coret)\b/i.test(clean)) {
        return 'REVISE_PO';
      }
      if (isPdfRequest) {
        return 'SEND_PDF_INVOICE';
      }
      return 'QUERY_INVOICE';
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

    // 0. Cek Engine Self-Learning (ESL) rules dari ai_knowledge_rules (misal 'SJJ' -> 'SURYANTO WIBISONO WIBOWO' / 'AD008', 'Pak Nardi' -> 'NARDI FF (NARDI)')
    const rules = this.autoPoProcessor?.cachedRules || [];
    for (const rule of rules) {
      if (rule.type === 'customer_alias') {
        const kw = normalizeText(rule.keyword || '');
        if (kw.length >= 2) {
          const kwPattern = new RegExp('(^|\\s)' + kw.replace(/\s+/g, '\\s+') + '(\\s|$)', 'i');
          if (kwPattern.test(clean)) {
            const normMapped = normalizeText(rule.mappedValue || '');
            const mappedParts = (rule.mappedValue || '')
              .replace(/[()]/g, ' ')
              .split(/\s+/)
              .map(p => normalizeText(p))
              .filter(p => p.length >= 2 && !['ff', 'frozen', 'food', 'toko', 'cv', 'pt', 'ud'].includes(p));

            const found = customers.find(c => {
              if (rule.targetId && c.id === rule.targetId) return true;
              const cName = normalizeText(c.customerName || c.name || '');
              const cAlias = normalizeText(c.aliasName || c.alias || '');

              // Exact match
              if (cName === normMapped || cAlias === normMapped) return true;
              // Bidirectional inclusion
              if (cName.length >= 2 && (normMapped.includes(cName) || cName.includes(normMapped))) return true;
              if (cAlias.length >= 2 && (normMapped.includes(cAlias) || cAlias.includes(normMapped))) return true;

              // Mapped parts match (misal 'NARDI FF (NARDI)' -> mp 'nardi' cocok dengan cName / cAlias 'nardi')
              for (const mp of mappedParts) {
                if (cName.includes(mp) || cAlias.includes(mp)) return true;
              }
              return false;
            });
            if (found) return found;
          }
        }
      }
    }

    // Blacklist inisial yang bertabrakan dengan kata umum / sapaan / partikel bahasa Indonesia
    const initialsBlacklist = ['pak', 'mas', 'kak', 'bu', 'ibu', 'om', 'dan', 'ke', 'di', 'ada', 'ff', 'pt', 'cv', 'ud'];

    // 1. Cek Initials / Singkatan / Akronim Nama Toko (misal "SUMBER JADI JAYA" -> "SJJ", "MAJU MARKET MANDIRI" -> "MMM")
    for (const c of customers) {
      const alias = normalizeText(c.aliasName || c.alias || '');
      const name = normalizeText(c.customerName || c.name || '');

      const getInitials = (s) => s.split(/\s+/).filter(w => w.length > 0 && !['ff', 'frozen', 'food', 'cv', 'pt', 'toko', 'ud'].includes(w)).map(w => w[0]).join('');
      const aliasInitials = getInitials(alias);
      const nameInitials = getInitials(name);

      if (aliasInitials.length >= 2 && !initialsBlacklist.includes(aliasInitials)) {
        const initPat = new RegExp('(^|\\s)' + aliasInitials + '(\\s|$)', 'i');
        if (initPat.test(clean)) return c;
      }
      if (nameInitials.length >= 2 && !initialsBlacklist.includes(nameInitials)) {
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
      .filter(w => w.length >= 2 || /^\d+$/.test(w));

    if (cleanWords.length === 0) return null;

    const qHasMerah = cleanWords.includes('merah');
    const qHasCoklat = cleanWords.includes('coklat') || cleanWords.includes('cklt');
    const qHasAyam = cleanWords.includes('ayam') || cleanWords.includes('ay');
    const qHasSapi = cleanWords.includes('sapi') || cleanWords.includes('sp');

    const qHas7 = cleanWords.includes('7') || cleanWords.includes('7s');
    const qHas13 = cleanWords.includes('13') || cleanWords.includes('13s');
    const qHas24 = cleanWords.includes('24') || cleanWords.includes('24s');

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

      // Domain contrast penalty & bonus
      if (qHasMerah) {
        if (pWords.includes('merah') || pName.includes('merah')) score += 10;
        else if (pWords.includes('coklat') || pName.includes('coklat')) score -= 15;
      }
      if (qHasCoklat) {
        if (pWords.includes('coklat') || pName.includes('coklat')) score += 10;
        else if (pWords.includes('merah') || pName.includes('merah')) score -= 15;
      }
      if (qHasAyam) {
        if (pWords.includes('ayam') || pName.includes('ayam')) score += 10;
        else if (pWords.includes('sapi') || pName.includes('sapi')) score -= 15;
      }
      if (qHasSapi) {
        if (pWords.includes('sapi') || pName.includes('sapi')) score += 10;
        else if (pWords.includes('ayam') || pName.includes('ayam')) score -= 15;
      }

      // Size number contrast penalty & bonus (7 vs 13 vs 24)
      if (qHas7) {
        if (pWords.includes('7') || pWords.includes('7s') || pName.includes('7s') || /\b7s\b/i.test(pName)) score += 20;
        if (pWords.includes('13') || pWords.includes('13s') || pWords.includes('24') || pWords.includes('24s') || pName.includes('13s') || pName.includes('24s')) score -= 30;
      }
      if (qHas13) {
        if (pWords.includes('13') || pWords.includes('13s') || pName.includes('13s') || /\b13s\b/i.test(pName)) score += 20;
        if (pWords.includes('7') || pWords.includes('7s') || pWords.includes('24') || pWords.includes('24s') || pName.includes('7s') || pName.includes('24s')) score -= 30;
      }
      if (qHas24) {
        if (pWords.includes('24') || pWords.includes('24s') || pName.includes('24s') || /\b24s\b/i.test(pName)) score += 20;
        if (pWords.includes('7') || pWords.includes('7s') || pWords.includes('13') || pWords.includes('13s') || pName.includes('7s') || pName.includes('13s')) score -= 30;
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
    resText += `💳 *2. Cek Kartu Piutang / Unduh PDF Piutang*\n`;
    resText += `   ↳ Ketik: \`piutang [nama toko]\` atau \`kirimkan file pdf piutang [nama toko]\`.\n\n`;
    resText += `📦 *3. Cek Stok Barang Gudang*\n`;
    resText += `   ↳ Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst mini*)\n`;
    resText += `   ↳ Atau ketik: \`stok keseluruhan\` untuk melihat rekap total gudang.\n\n`;
    resText += `🔄 *4. Revisi PO (Khusus Status PENDING)*\n`;
    resText += `   ↳ Quote/balas pesanan dengan: \`revisi PO [nama barang] jadi [jumlah] karton\`\n`;
    resText += `   ↳ Atau tukar barang: \`revisi [nama barang] di ganti [barang baru] [jumlah] karton\`.\n\n`;
    resText += `📄 *5. Cek Rincian Faktur / Invoice (Unduh Dokumen PDF)*\n`;
    resText += `   ↳ Ketik: \`faktur [nomor]\` atau \`kirimkan file pdf PO nomor [nomor]\`.\n\n`;
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
    let items = Array.isArray(invData.items) ? [...invData.items] : [];
    const actions = this.parseAllRevisionActions(text, items);
    if (!actions || actions.length === 0) {
      const currentItemList = items.length > 0
        ? items.map((it, idx) => `${idx + 1}. ${it.productName}`).join('\n')
        : '(Faktur belum memiliki daftar barang)';
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Perintah revisi belum terdeteksi dengan jelas pada Faktur *#${targetInvNo}*.\n\n` +
        `*Barang yang ada di Faktur #${targetInvNo}:*\n${currentItemList}\n\n` +
        `💡 *Contoh format yang bisa Anda gunakan:*\n` +
        `• Tambah Item: \`tambah brs 24 10 karton\` atau \`tambahkan sosis cocktail 5 karton\`\n` +
        `• Hapus: \`hapus brs 13 dan brs 7\` atau \`sosis cocktail dihapus\`\n` +
        `• Ubah Qty: \`revisi brs 24 jadi 15 karton\` atau \`brs 24 jadi 15 ktn dan brs 13 jadi 20 ktn\`\n` +
        `• Ganti Barang: \`ganti brs 13 jadi sosis cocktail 10 ktn\``;
    }

    const hasAddAction = actions.some(a => a.action === 'ADD');
    if (items.length === 0 && !hasAddAction) {
      return `⚠️ Faktur #${targetInvNo} tidak memiliki daftar barang yang dapat direvisi.`;
    }

    const deleteIndices = [];
    const deletedItemNames = [];
    const revisionLogs = [];
    const notFoundQueries = [];

    for (const act of actions) {
      if (act.action === 'DELETE') {
        const idx = this.matchItemFromList(act.targetQuery, items);
        if (idx !== -1) {
          if (!deleteIndices.includes(idx)) {
            deleteIndices.push(idx);
            deletedItemNames.push(items[idx].productName || 'PRODUK');
          }
        } else {
          notFoundQueries.push(act.targetQuery);
        }
      } else if (act.action === 'SWAP') {
        const idx = this.matchItemFromList(act.oldQuery, items);
        if (idx === -1) {
          notFoundQueries.push(act.oldQuery);
          continue;
        }

        const targetOldItem = items[idx];
        const oldItemName = targetOldItem.productName || 'PRODUK LAMA';

        // Cari produk pengganti di history customer & katalog master
        let customerHistory = [];
        if (invData.customerId && this.firebaseAdapter?.getCustomerProductMemory) {
          try {
            customerHistory = await this.firebaseAdapter.getCustomerProductMemory(invData.customerId);
          } catch (_) {}
        }

        let newPricing = null;
        let targetNewProduct = null;
        if (customerHistory.length > 0 && this.autoPoProcessor?.matchProductFromHistory) {
          const histMatch = this.autoPoProcessor.matchProductFromHistory(act.newQuery, customerHistory);
          if (histMatch) {
            newPricing = histMatch;
            targetNewProduct = products.find(p =>
              (histMatch.productId && p.id === histMatch.productId) ||
              (histMatch.productName && (p.productName === histMatch.productName || p.name === histMatch.productName))
            );
          }
        }

        if (!targetNewProduct) {
          targetNewProduct = this.matchProductFromQuery(act.newQuery, products);
        }

        if (!targetNewProduct && products.length > 0) {
          const cleanNew = normalizeText(act.newQuery);
          targetNewProduct = products.find(p => {
            const pName = normalizeText(p.productName || p.name || '');
            return pName.includes(cleanNew) || cleanNew.split(/\s+/).every(w => pName.includes(w));
          });
        }

        if (!targetNewProduct) {
          return `🤖 *[L-W.A.V.I.S]*\n` +
            `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
            `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
            `Halo ${senderName}! Produk pengganti (*${act.newQuery}*) tidak ditemukan dalam katalog master produk.\n\n` +
            `Mohon periksa kembali penulisan nama produk penggantinya ya. 😊`;
        }

        const oldPcsPerKtn = Number(targetOldItem.isiKarton) || 15;
        const oldCarton = (typeof targetOldItem.cartonCount === 'number' && targetOldItem.cartonCount > 0)
          ? targetOldItem.cartonCount
          : (targetOldItem.qty && oldPcsPerKtn > 0 ? Math.round(targetOldItem.qty / oldPcsPerKtn) : 1);
        const pcsPerKtn = Number(targetNewProduct.isiKarton) || 15;
        const rawQty = (act.qty && act.qty > 0 && !isNaN(act.qty)) ? act.qty : oldCarton;
        const unit = (act.unit || 'karton').toLowerCase();

        let newCartonQty = 0;
        let newQtyPcs = 0;

        if (['roll', 'rol', 'pcs', 'pack', 'pak', 'pc', 'batang'].includes(unit)) {
          newQtyPcs = Math.round(rawQty);
          newCartonQty = pcsPerKtn > 0 ? (newQtyPcs / pcsPerKtn) : 1;
        } else if (['bal', 'ball'].includes(unit)) {
          newQtyPcs = Math.round(rawQty * 25);
          newCartonQty = pcsPerKtn > 0 ? (newQtyPcs / pcsPerKtn) : rawQty;
        } else {
          newCartonQty = rawQty;
          newQtyPcs = Math.round(newCartonQty * pcsPerKtn);
        }

        let unitPrice = Number(targetNewProduct.price) || 0;
        let discPct = 0;
        let discAmt = 0;

        if (newPricing && newPricing.price > 0) {
          unitPrice = newPricing.price;
          discPct = newPricing.discountPercent || 0;
          discAmt = newPricing.discountAmount || 0;
        } else if (invData.customerId && this.firebaseAdapter?.getLastCustomerProductPricing) {
          try {
            const lastPrc = await this.firebaseAdapter.getLastCustomerProductPricing(
              invData.customerId,
              targetNewProduct.id,
              targetNewProduct.productName || targetNewProduct.name
            );
            if (lastPrc && lastPrc.price > 0) {
              unitPrice = lastPrc.price;
              discPct = lastPrc.discountPercent || 0;
              discAmt = lastPrc.discountAmount || 0;
            }
          } catch (_) {}
        }

        const grossTotal = newQtyPcs * unitPrice;
        const calcDiscAmt = discPct > 0 ? (grossTotal * discPct / 100) : (discAmt > 0 ? discAmt : 0);
        const newSubtotal = Math.round(grossTotal - calcDiscAmt);

        const newProductName = targetNewProduct.productName || targetNewProduct.name || 'PRODUK';
        const sizeGrams = Number(targetNewProduct.sizeGrams) || 500;
        const weightKg = Math.round(newQtyPcs * sizeGrams / 1000 * 100) / 100;

        const swappedItem = {
          productId: targetNewProduct.id || '',
          productName: newProductName,
          price: unitPrice,
          qty: newQtyPcs,
          isiKarton: pcsPerKtn,
          cartonCount: newCartonQty,
          discountPercent: discPct,
          discountAmount: discAmt,
          subtotal: newSubtotal,
          sizeGrams: sizeGrams,
          weightKg: weightKg,
          isBonus: false,
          _isRevised: true,
          _isSwapped: true,
          _oldProductName: oldItemName
        };

        items[idx] = swappedItem;
        revisionLogs.push(`Ganti ${oldItemName} -> ${newProductName} (${newCartonQty} ktn)`);
      } else if (act.action === 'QTY') {
        const idx = this.matchItemFromList(act.targetQuery, items);
        if (idx === -1) {
          notFoundQueries.push(act.targetQuery);
          continue;
        }

        const rawQty = Number(act.qty);
        if (isNaN(rawQty) || rawQty <= 0) {
          continue;
        }

        const targetItem = { ...items[idx] };

        const getIsiKtn = (it) => {
          if (typeof it.isiKarton === 'number' && it.isiKarton > 0) return it.isiKarton;
          const found = products.find(p => (it.productId && p.id === it.productId) || (it.productName && (p.productName === it.productName || p.name === it.productName)));
          if (found && found.isiKarton) return Number(found.isiKarton);
          if (it.cartonCount > 0 && it.qty > 0) return Math.round(it.qty / it.cartonCount);
          return 15;
        };

        const isiKtn = getIsiKtn(targetItem);
        const unit = (act.unit || 'karton').toLowerCase();

        let newCartonQty = 0;
        let newQtyPcs = 0;

        if (['roll', 'rol', 'pcs', 'pack', 'pak', 'pc', 'batang'].includes(unit)) {
          newQtyPcs = Math.round(rawQty);
          newCartonQty = isiKtn > 0 ? (newQtyPcs / isiKtn) : 1;
        } else if (['bal', 'ball'].includes(unit)) {
          newQtyPcs = Math.round(rawQty * 25);
          newCartonQty = isiKtn > 0 ? (newQtyPcs / isiKtn) : rawQty;
        } else {
          newCartonQty = rawQty;
          newQtyPcs = Math.round(newCartonQty * isiKtn);
        }

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
          targetItem.weightKg = Math.round((newQtyPcs * Number(targetItem.sizeGrams)) / 1000 * 100) / 100;
        }
        targetItem._isRevised = true;

        items[idx] = targetItem;
        const unitDisplay = (newCartonQty % 1 === 0) ? `${newCartonQty} ktn` : `${newQtyPcs} ${unit}`;
        revisionLogs.push(`${targetItem.productName} -> ${unitDisplay}`);
      } else if (act.action === 'ADD') {
        let customerHistory = [];
        if (invData.customerId && this.firebaseAdapter?.getCustomerProductMemory) {
          try {
            customerHistory = await this.firebaseAdapter.getCustomerProductMemory(invData.customerId);
          } catch (_) {}
        }

        let matchedProduct = null;
        let historyPricing = null;

        // PRIORITAS 0: Cek apakah item sudah ada di faktur saat ini (Prioritas Utama Konteks Percakapan Revisi)
        const existingInvoiceIdx = this.matchItemFromList(act.productQuery, items);
        if (existingInvoiceIdx !== -1) {
          matchedProduct = items[existingInvoiceIdx];
        }

        // PRIORITAS 1: Cek Customer History (AI belajar dari kebiasaan customer AW FF)
        if (!matchedProduct && customerHistory.length > 0 && this.autoPoProcessor?.matchProductFromHistory) {
          const histMatch = this.autoPoProcessor.matchProductFromHistory(act.productQuery, customerHistory);
          if (histMatch) {
            historyPricing = histMatch;
            matchedProduct = products.find(p =>
              (histMatch.productId && p.id === histMatch.productId) ||
              (histMatch.productName && (p.productName === histMatch.productName || p.name === histMatch.productName))
            );
            if (!matchedProduct) {
              matchedProduct = products.find(p =>
                (p.productName || p.name || '').toLowerCase().includes((histMatch.productName || '').toLowerCase())
              );
            }
            if (!matchedProduct) {
              matchedProduct = {
                id: histMatch.productId || '',
                productName: histMatch.productName,
                name: histMatch.productName,
                price: histMatch.price,
                isiKarton: 15,
                sizeGrams: 500
              };
            }
          }
        }

        // PRIORITAS 2: Cek AI Knowledge Rules (product_alias)
        if (!matchedProduct) {
          const rules = this.autoPoProcessor?.cachedRules || [];
          const prodRules = rules.filter(r => r.type === 'product_alias');
          const cleanQ = normalizeText(act.productQuery);
          for (const r of prodRules) {
            let from = normalizeText(r.keyword || r.from || '');
            if (from && (cleanQ === from || cleanQ.includes(from) || from.includes(cleanQ))) {
              if (r.targetId) {
                const p = products.find(prod => prod.id === r.targetId);
                if (p) { matchedProduct = p; break; }
              }
              const toNorm = normalizeText(r.mappedValue || r.to || '');
              const p = products.find(prod => {
                const pn = normalizeText(prod.productName || prod.name || '');
                return pn === toNorm || pn.includes(toNorm) || toNorm.includes(pn);
              });
              if (p) { matchedProduct = p; break; }
            }
          }
        }

        // PRIORITAS 3: Match via matchProductFromQuery atau fuzzy search ke master products
        if (!matchedProduct) {
          matchedProduct = this.matchProductFromQuery(act.productQuery, products);
        }
        if (!matchedProduct && products.length > 0) {
          const cleanQ = normalizeText(act.productQuery);
          matchedProduct = products.find(p => {
            const pName = normalizeText(p.productName || p.name || '');
            return pName.includes(cleanQ) || cleanQ.split(/\s+/).every(w => pName.includes(w));
          });
        }

        if (!matchedProduct) {
          notFoundQueries.push(act.productQuery);
          continue;
        }

        // Tentukan Harga & Diskon Pelanggan
        let unitPrice = Number(matchedProduct.price) || 0;
        let discPct = 0;
        let discAmt = 0;

        if (historyPricing && historyPricing.price > 0) {
          unitPrice = historyPricing.price;
          discPct = historyPricing.discountPercent || 0;
          discAmt = historyPricing.discountAmount || 0;
        } else if (invData.customerId && this.firebaseAdapter?.getLastCustomerProductPricing) {
          try {
            const lastPrc = await this.firebaseAdapter.getLastCustomerProductPricing(
              invData.customerId,
              matchedProduct.id,
              matchedProduct.productName || matchedProduct.name
            );
            if (lastPrc && lastPrc.price > 0) {
              unitPrice = lastPrc.price;
              discPct = lastPrc.discountPercent || 0;
              discAmt = lastPrc.discountAmount || 0;
            }
          } catch (_) {}
        }

        // Konversi Kemasan & Qty (Mendukung karton, pcs, roll, bal)
        const pcsPerKtn = Number(matchedProduct.isiKarton) || 15;
        const rawQty = (act.qty && act.qty > 0 && !isNaN(act.qty)) ? act.qty : 1;
        const unit = (act.unit || 'karton').toLowerCase();

        let addCartonQty = 0;
        let addQtyPcs = 0;

        if (['roll', 'rol', 'pcs', 'pack', 'pak', 'pc', 'batang'].includes(unit)) {
          addQtyPcs = Math.round(rawQty);
          addCartonQty = pcsPerKtn > 0 ? (addQtyPcs / pcsPerKtn) : 1;
        } else if (['bal', 'ball'].includes(unit)) {
          addQtyPcs = Math.round(rawQty * 25);
          addCartonQty = pcsPerKtn > 0 ? (addQtyPcs / pcsPerKtn) : rawQty;
        } else {
          addCartonQty = rawQty;
          addQtyPcs = Math.round(addCartonQty * pcsPerKtn);
        }

        const sizeGrams = Number(matchedProduct.sizeGrams) || 500;
        const addWeightKg = Math.round(addQtyPcs * sizeGrams / 1000 * 100) / 100;

        const grossTotal = addQtyPcs * unitPrice;
        const calcDiscAmt = discPct > 0 ? (grossTotal * discPct / 100) : (discAmt > 0 ? discAmt : 0);
        const addSubtotal = Math.round(grossTotal - calcDiscAmt);
        const prodName = matchedProduct.productName || matchedProduct.name || 'PRODUK';

        const unitDisplay = (addCartonQty % 1 === 0) ? `${addCartonQty} ktn` : `${addQtyPcs} ${unit}`;

        // Periksa apakah barang sudah ada di faktur
        const existingIdx = items.findIndex(it =>
          (matchedProduct.id && it.productId && it.productId === matchedProduct.id) ||
          ((it.productName || '').toLowerCase().trim() === prodName.toLowerCase().trim())
        );

        if (existingIdx !== -1) {
          // Barang sudah ada di faktur: akumulasikan kuantitas
          const it = items[existingIdx];
          const existingCarton = (typeof it.cartonCount === 'number' && it.cartonCount > 0)
            ? it.cartonCount
            : (pcsPerKtn > 0 ? (it.qty / pcsPerKtn) : 0);
          it.cartonCount = existingCarton + addCartonQty;
          it.qty = (it.qty || 0) + addQtyPcs;
          it.subtotal = (it.subtotal || 0) + addSubtotal;
          if (it.sizeGrams) {
            it.weightKg = Math.round(it.qty * Number(it.sizeGrams) / 1000 * 100) / 100;
          }
          it._isRevised = true;
          items[existingIdx] = it;
          const totalUnitDisplay = (it.cartonCount % 1 === 0) ? `${it.cartonCount} ktn` : `${it.qty} pcs`;
          revisionLogs.push(`Tambah ${prodName} +${unitDisplay} (Total: ${totalUnitDisplay})`);
        } else {
          // Barang baru: sisipkan ke faktur
          const newItem = {
            productId: matchedProduct.id || '',
            productName: prodName,
            price: unitPrice,
            qty: addQtyPcs,
            isiKarton: pcsPerKtn,
            cartonCount: addCartonQty,
            discountPercent: discPct,
            discountAmount: discAmt,
            subtotal: addSubtotal,
            sizeGrams: sizeGrams,
            weightKg: addWeightKg,
            isBonus: false,
            _isRevised: true,
            _isAdded: true
          };
          items.push(newItem);
          revisionLogs.push(`Tambah ${prodName} (${unitDisplay})`);
        }
      }
    }

    // Eksekusi penghapusan jika ada item yang ditandai hapus
    if (deleteIndices.length > 0) {
      if (items.length - deleteIndices.length <= 0) {
        return `⚠️ *[PENGHAPUSAN ITEM DITOLAK]*\n` +
          `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
          `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
          `Halo ${senderName}!\n\n` +
          `Semua barang di Faktur #${targetInvNo} tidak boleh dihapus seluruhnya hingga kosong.\n` +
          `Faktur tidak boleh berstatus kosong. Jika ingin membatalkan seluruh pesanan Faktur #${targetInvNo}, silakan konfirmasi langsung ke Admin / Kasir ya! 🙏`;
      }

      deleteIndices.sort((a, b) => b - a);
      for (const idx of deleteIndices) {
        items.splice(idx, 1);
      }
      revisionLogs.push(`Hapus ${deletedItemNames.join(', ')}`);
    }

    if (revisionLogs.length === 0 && notFoundQueries.length > 0) {
      const currentItemList = items.map((it, idx) => `${idx + 1}. ${it.productName}`).join('\n');
      return `🤖 *[L-W.A.V.I.S]*\n` +
        `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
        `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Barang yang ingin direvisi/ditambahkan (*${notFoundQueries.join(', ')}*) tidak ditemukan di Faktur *#${targetInvNo}* maupun katalog produk.\n\n` +
        `*Barang yang ada di Faktur #${targetInvNo}:*\n${currentItemList}\n\n` +
        `💡 *Contoh format:* \`tambah brs 24 10 karton\` atau \`revisi ${items[0]?.productName || 'nama barang'} jadi 10 karton\``;
    }

    // Hitung ulang grand total invoice
    let newGrandTotal = 0;
    for (const it of items) {
      newGrandTotal += (it.isBonus ? 0 : Number(it.subtotal || 0));
    }
    invData.items = items;
    invData.grandTotal = Math.round(newGrandTotal);

    const revisionNote = `Revisi WA L-W.A.V.I.S: ${revisionLogs.join(' | ')}`;

    // Simpan pembaruan ke Firestore jika terhubung
    const cleanItemsForDb = items.map(it => {
      const c = { ...it };
      delete c._isRevised;
      delete c._isSwapped;
      delete c._isAdded;
      delete c._oldProductName;
      return c;
    });

    const cleanTransactionNote = (invData.note && !invData.note.toLowerCase().includes('revisi wa l-w.a.v.i.s'))
      ? invData.note.trim()
      : '';

    try {
      if (invDocRef) {
        const updatePayload = {
          items: cleanItemsForDb,
          grandTotal: invData.grandTotal,
          note: cleanTransactionNote,
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
          isReplySent: true,
          revisionLog: revisionNote,
          note: revisionNote
        });
      }

      let confSubtitle = '';
      if (deleteIndices.length > 0 && revisionLogs.length === 1) {
        confSubtitle = `Barang *${deletedItemNames.join(' dan ')}* berhasil dihapus dari Faktur #${targetInvNo}:`;
      } else if (revisionLogs.length === 1 && revisionLogs[0].startsWith('Tambah ')) {
        confSubtitle = `Barang *${revisionLogs[0].replace(/^Tambah\s+/, '')}* berhasil ditambahkan ke Faktur #${targetInvNo}:`;
      } else {
        confSubtitle = `Revisi pesanan Faktur #${targetInvNo} berhasil diperbarui di sistem:`;
      }

      // Format balasan konfirmasi resmi revisi
      return this.formatPoConfirmation(invData, senderName, {
        title: 'REVISI PO BERHASIL DIPROSES: L-W.A.V.I.S',
        subtitle: confSubtitle,
        isRevised: true
      });
    } catch (err) {
      console.error('[L-W.A.V.I.S UPDATE TRANSACTION ERROR]', err.message);
      return `⚠️ Gagal memperbarui transaksi #${targetInvNo}: ${err.message}`;
    }
  }

  /**
   * Helper pencocokan item dari daftar produk di faktur
   */
  matchItemFromList(targetQuery, items) {
    const cleanQ = normalizeText(targetQuery).replace(/\b(item|barang|produk|yang|pesanan|order|po|faktur|invoice)\b/gi, ' ').replace(/\s+/g, ' ').trim();
    if (!cleanQ) return -1;
    const words = cleanQ.split(/\s+/).filter(w => w.length >= 1);
    const numTokens = words.filter(w => /^\d+$/.test(w));
    let bestIdx = -1;
    let bestScore = 0;

    for (let i = 0; i < items.length; i++) {
      const itName = normalizeText(items[i].productName || items[i].name || '');
      let score = 0;
      let numMatched = 0;
      let wordsMatched = 0;

      for (const w of words) {
        const wNorm = (w === 'beres' || w === 'beras') ? 'brs' : (w === 'brs' ? 'beres' : w);
        if (/^\d+$/.test(w)) {
          const numRegex = new RegExp('\\b' + w + '[a-z]*\\b|\\b' + w + '\\b', 'i');
          if (numRegex.test(itName)) {
            score += 20;
            numMatched++;
            wordsMatched++;
          } else {
            score -= 15;
          }
        } else if (itName.includes(w) || itName.includes(wNorm)) {
          score += 5;
          wordsMatched++;
        } else {
          score -= 10;
        }
      }

      // Jika query menyebutkan nomor spesifik (misal 24, 13, 7), tapi nomor tersebut tidak ada pada item ini, abaikan
      if (numTokens.length > 0 && numMatched === 0) {
        continue;
      }

      // Jika query terdiri dari beberapa kata dan tidak ada angka (misal 'brs merah'), minimal sebagian kata harus cocok
      if (words.length > 1 && numTokens.length === 0 && wordsMatched < Math.ceil(words.length / 2)) {
        continue;
      }

      if (score > bestScore && score >= 5) {
        bestScore = score;
        bestIdx = i;
      }
    }

    if (bestIdx === -1 && cleanQ.length >= 2 && numTokens.length === 0) {
      for (let i = 0; i < items.length; i++) {
        const itName = normalizeText(items[i].productName || items[i].name || '');
        if (itName.includes(cleanQ) || cleanQ.includes(itName)) {
          return i;
        }
      }
    }

    return bestIdx;
  }

  /**
   * Helper parsing 1 item dan kuantitas untuk penambahan item (mendukung format angka di depan/belakang)
   */
  parseSingleItemAndQty(raw) {
    let s = String(raw || '').trim();
    // Bersihkan kata-kata percakapan / partikel di akhir (saja, aja, ya, dong, min, pak, dll)
    const trailingStopWordsRegex = /[\s,]+(?:saja|aja|aj|sj|ya|yaa|yah|dong|dunk|dng|deh|nih|lah|lh|mas|masnya|pak|pakbos|kak|kakak|min|mimin|admin|bos|boss|bosque|om|gan|tolong|mohon)$/i;
    while (trailingStopWordsRegex.test(s)) {
      s = s.replace(trailingStopWordsRegex, '').trim();
    }
    // Bersihkan prefix perintah revisi/tambah jika terbawa
    s = s.replace(/^(?:tolong\s+|mohon\s+|revisi\s+|ubah\s+|tambah\s+|tambahkan\s+)+/i, '').trim();

    // 1. Qty di depan dengan satuan: '10 karton brs 24'
    const m1 = s.match(/^(\d+(?:[.,]\d+)?)\s*(karton|ktn|krton|krtn|krt|dus|box|pack|pak|pcs|pc|bal|ball|roll|rol|batang)\s+(.+)$/i);
    if (m1) {
      return {
        product: m1[3].trim(),
        qty: parseFloat(m1[1].replace(',', '.')),
        unit: m1[2].toLowerCase()
      };
    }
    // 2. Qty di belakang dengan satuan: 'brs 24 10 karton'
    const m2 = s.match(/^(.+?)\s+(\d+(?:[.,]\d+)?)\s*(karton|ktn|krton|krtn|krt|dus|box|pack|pak|pcs|pc|bal|ball|roll|rol|batang)$/i);
    if (m2) {
      return {
        product: m2[1].trim(),
        qty: parseFloat(m2[2].replace(',', '.')),
        unit: m2[3].toLowerCase()
      };
    }
    // 3. Qty di belakang TANPA satuan, tapi ada 2 angka terpisah: misal 'brs 24 10'
    const m3 = s.match(/^(.+?\b\d+s?)\s+(\d+)$/i);
    if (m3) {
      return {
        product: m3[1].trim(),
        qty: parseFloat(m3[2]),
        unit: 'karton'
      };
    }
    // 4. Qty di belakang tanpa satuan pada nama tanpa angka: misal 'sosis cocktail 10'
    const m4 = s.match(/^([a-zA-Z\s]+?)\s+(\d+)$/);
    if (m4) {
      const num = parseInt(m4[2], 10);
      const isSize = [7, 8, 13, 24, 215, 250, 400, 500, 1000].includes(num) || /^(brs|beres|beras)/i.test(m4[1].trim());
      if (!isSize) {
        return {
          product: m4[1].trim(),
          qty: num,
          unit: 'karton'
        };
      }
    }
    // 5. Default: seluruh teks adalah nama produk, qty = 1
    return {
      product: s,
      qty: 1,
      unit: 'karton'
    };
  }

  /**
   * Helper parsing seluruh instruksi revisi (mendukung revisi multi-item / batch, multi-line, block header, dan unit-aware)
   */
  parseAllRevisionActions(rawText, currentInvoiceItems = []) {
    let text = String(rawText || '').trim();

    // Strip prefix nomor faktur/invoice (misal: "revisi PO 700: " atau "ubah faktur #696")
    text = text.replace(/(?:revisi|ubah)\s*(?:po|faktur|invoice|nota|#)?\s*[:#.]?\s*\d{2,6}\s*[:,-]?/i, ' ');
    text = text.replace(/(?:po|faktur|invoice|nota|#)\s*[:#.]?\s*\d{2,6}/gi, ' ');

    // Normalisasi baris
    const rawLines = text.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0);

    const trailingStopWordsRegex = /[\s,]+(?:saja|aja|aj|sj|ya|yaa|yah|dong|dunk|dng|deh|nih|lah|lh|mas|masnya|pak|pakbos|kak|kakak|min|mimin|admin|bos|boss|bosque|om|gan|tolong|mohon)$/i;

    const actions = [];
    let currentBlockMode = null; // 'ADD', 'DELETE', 'SWAP', null

    for (let line of rawLines) {
      let cleanLine = line.replace(/^[0-9]+[.)\-*+]\s*/, '').replace(/^[-*+]\s*/, '').trim();
      if (!cleanLine) continue;

      while (trailingStopWordsRegex.test(cleanLine)) {
        cleanLine = cleanLine.replace(trailingStopWordsRegex, '').trim();
      }
      if (!cleanLine) continue;

      // Header blok baris (misal 'revisi tambahan', 'tambahan:', 'tambah:', 'hapus:', 'revisi qty:')
      if (/^(?:revisi\s+)?(?:tambahan|tambah|tambahkan|orderan\s+tambahan|order\s+tambahan)\s*[:]?$/i.test(cleanLine)) {
        currentBlockMode = 'ADD';
        continue;
      }
      if (/^(?:revisi\s+)?(?:hapus|penghapusan|dihapus|batal|dibatalkan)\s*[:]?$/i.test(cleanLine)) {
        currentBlockMode = 'DELETE';
        continue;
      }
      if (/^(?:revisi\s+)?(?:ganti|tukar|penggantian|penukaran)\s*[:]?$/i.test(cleanLine)) {
        currentBlockMode = 'SWAP';
        continue;
      }
      if (/^(?:revisi\s+)?(?:ubah\s+qty|ganti\s+qty|revisi)\s*[:]?$/i.test(cleanLine)) {
        currentBlockMode = null;
        continue;
      }

      // Inline header (misal 'tambahan: brs merah 15 ktn' atau 'order tambahan: ...')
      const inlineHeaderMatch = cleanLine.match(/^(?:revisi\s+)?(?:tambahan|tambah|tambahkan|orderan\s+tambahan|order\s+tambahan)\s*[:]\s*(.+)$/i);
      if (inlineHeaderMatch) {
        currentBlockMode = 'ADD';
        cleanLine = inlineHeaderMatch[1].trim();
      }

      const inlineDelHeaderMatch = cleanLine.match(/^(?:revisi\s+)?(?:hapus|penghapusan|dihapus|batal|dibatalkan)\s*[:]\s*(.+)$/i);
      if (inlineDelHeaderMatch) {
        currentBlockMode = 'DELETE';
        cleanLine = inlineDelHeaderMatch[1].trim();
      }

      const inlineSwapHeaderMatch = cleanLine.match(/^(?:revisi\s+)?(?:ganti|tukar|penggantian|penukaran)\s*[:]\s*(.+)$/i);
      if (inlineSwapHeaderMatch) {
        currentBlockMode = 'SWAP';
        cleanLine = inlineSwapHeaderMatch[1].trim();
      }

      // Deteksi baris perintah hapus multi-item murni (misal: 'hapus item barang brs 13 dan brs 7')
      const delLineMatch = cleanLine.match(/^(?:tolong\s+|mohon\s+|revisi\s+)?(?:di\s*hapus|hapus|di\s*buang|buang|di\s*hilangkan|hilangkan|di\s*batalkan|batalkan|di\s*cancel|cancel|di\s*coret|coret)\s+(?:item\s+|barang\s+|produk\s+)?(.+)$/i);
      if (delLineMatch && !/\b(?:jadi|menjadi|ganti|tukar|tambah|tambahkan|tambahan)\b/i.test(delLineMatch[1])) {
        const raw = delLineMatch[1]
          .replace(/\b(?:saja|aja|dong|ya|tolong|mohon)\b/gi, '')
          .replace(/\b(?:item|barang|produk)\b/gi, '')
          .trim();
        const targets = raw.split(/\s*(?:,|;|\bdan\b|\bserta\b)\s*/i).map(t => t.trim()).filter(t => t.length > 0);
        for (const t of targets) actions.push({ action: 'DELETE', targetQuery: t });
        continue;
      }

      // Deteksi baris perintah hapus suffix murni (misal: 'brs 13 dan brs 7 dihapus saja')
      const suffixDelMatch = cleanLine.match(/^(.+?)\s+(?:di\s*hapus|hapus|di\s*buang|buang|di\s*hilangkan|hilangkan|di\s*batalkan|batalkan|di\s*cancel|cancel|di\s*coret|coret|ga\s*jadi|nggak\s*jadi)(?:\s+saja|\s+aja|\s+dong|\s+ya)?$/i);
      if (suffixDelMatch && !/\b(?:jadi|menjadi|ganti|tukar|tambah|tambahkan|tambahan)\b/i.test(suffixDelMatch[1])) {
        const raw = suffixDelMatch[1]
          .replace(/\b(?:revisi|ubah|tolong|mohon|item|barang|produk)\b/gi, '')
          .trim();
        const targets = raw.split(/\s*(?:,|;|\bdan\b|\bserta\b)\s*/i).map(t => t.trim()).filter(t => t.length > 0);
        for (const t of targets) actions.push({ action: 'DELETE', targetQuery: t });
        continue;
      }

      // Deteksi baris perintah tambah multi-item murni (misal: 'tambah brs 24 10 karton dan sosis cocktail 5 karton')
      const addLineMatch = cleanLine.match(/^(?:tolong\s+|mohon\s+|revisi\s+)?(?:tambah|tambahkan|tambahan)\s+(?:item\s+|barang\s+|produk\s+|orderan\s+|pesanan\s+)?(.+)$/i);
      if (addLineMatch && !/\b(?:jadi|menjadi|ganti|tukar|hapus|dihapus|buang|dibuang|cancel|coret)\b/i.test(addLineMatch[1])) {
        const raw = addLineMatch[1].replace(/\b(?:saja|aja|dong|ya|tolong|mohon)\b/gi, '').trim();
        const parts = raw.split(/\s*(?:;|\bdan\b|\bserta\b|,(?!\d))\s*/i).map(t => t.trim()).filter(t => t.length > 0);
        for (const p of parts) {
          const itemParsed = this.parseSingleItemAndQty(p);
          actions.push({
            action: 'ADD',
            productQuery: itemParsed.product,
            qty: itemParsed.qty,
            unit: itemParsed.unit
          });
        }
        continue;
      }

      // Pisahkan item berdasarkan koma (yang bukan koma desimal), titik koma, atau kata 'dan' / 'serta'
      const subParts = cleanLine.split(/\s*(?:;|\bdan\b|\bserta\b|,(?!\d))\s*/i);

      for (let part of subParts) {
        part = part.trim();
        while (trailingStopWordsRegex.test(part)) {
          part = part.replace(trailingStopWordsRegex, '').trim();
        }
        if (!part) continue;

        // A. SWAP (Ganti / Tukar)
        let swapMatch = null;
        const mSwap1 = part.match(/^(?:revisi\s+|tolong\s+)?(?:ganti|tukar)\s+(.+?)\s+(?:dengan|jadi|ke|menjadi)\s+(.+)$/i);
        const mSwap2 = part.match(/(.+?)\s+(?:di\s*ganti|ganti|di\s*tukar|tukar)\s+(?:dengan|jadi|ke|menjadi)?\s*(.+)$/i);
        const mSwap3 = part.match(/^(?:revisi\s+|tolong\s+)?(?:ganti\s+|tukar\s+)?(.+?)\s+(?:menjadi|jadi|ke|dengan)\s+(.+)$/i);

        if (mSwap1) {
          swapMatch = { oldT: mSwap1[1], newT: mSwap1[2] };
        } else if (mSwap2) {
          swapMatch = { oldT: mSwap2[1], newT: mSwap2[2] };
        } else if (mSwap3) {
          const checkNewT = mSwap3[2].trim();
          const nonQty = checkNewT
            .replace(/\d+(?:[.,]\d+)?/g, '')
            .replace(/\b(karton|ktn|krton|krtn|krt|dus|box|bal|ball|pcs|pack|pak|roll|rol|pc|batang)\b/gi, '')
            .replace(/\b(saja|aja|aj|sj|ya|yaa|yah|dong|dunk|dng|deh|nih|lah|lh|mas|masnya|pak|pakbos|kak|kakak|min|mimin|admin|bos|boss|bosque|om|gan|tolong|mohon)\b/gi, '')
            .trim();
          if (nonQty.length > 0 || currentBlockMode === 'SWAP') {
            swapMatch = { oldT: mSwap3[1], newT: mSwap3[2] };
          }
        }

        if (swapMatch) {
          let oldT = swapMatch.oldT.replace(/^(?:ganti|tukar|revisi|ubah|tolong|mohon|item|barang|produk)\s+/gi, '').trim();
          let newT = swapMatch.newT.trim();
          while (trailingStopWordsRegex.test(newT)) {
            newT = newT.replace(trailingStopWordsRegex, '').trim();
          }
          let qty = null;
          let unit = 'karton';
          const qm = newT.match(/(\d+(?:[.,]\d+)?)\s*(karton|ktn|krton|krtn|krt|dus|box|bal|ball|pcs|pack|pak|roll|rol|pc|batang)\b/i);
          if (qm) {
            qty = parseFloat(qm[1].replace(',', '.'));
            unit = qm[2].toLowerCase();
          } else {
            const qm2 = newT.match(/(.*?)\s+(\d+)$/);
            if (qm2) qty = parseFloat(qm2[2]);
          }
          let newProd = newT
            .replace(/(\d+(?:[.,]\d+)?)\s*(karton|ktn|krton|krtn|krt|dus|box|bal|ball|pcs|pack|pak|roll|rol|pc|batang)\b/gi, '')
            .replace(/\s+\d+$/, '')
            .trim();
          actions.push({ action: 'SWAP', oldQuery: oldT, newQuery: newProd, qty, unit });
          continue;
        }

        // B. DELETE (Hapus)
        const isDel = /\b(?:di\s*hapus|hapus|di\s*buang|buang|di\s*hilangkan|hilangkan|di\s*batalkan|batalkan|di\s*cancel|cancel|di\s*coret|coret|ga\s*jadi|nggak\s*jadi)\b/i.test(part) || currentBlockMode === 'DELETE';
        if (isDel && !/\b(?:jadi|menjadi|ganti|tukar|tambah|tambahkan|tambahan)\b/i.test(part)) {
          const targetQ = part
            .replace(/\b(?:di\s*hapus|hapus|di\s*buang|buang|di\s*hilangkan|hilangkan|di\s*batalkan|batalkan|di\s*cancel|cancel|di\s*coret|coret|ga\s*jadi|nggak\s*jadi|saja|aja|dong|ya|tolong|mohon|revisi|ubah|item|barang|produk)\b/gi, ' ')
            .replace(/\s+/g, ' ')
            .trim();
          if (targetQ.length > 0) {
            actions.push({ action: 'DELETE', targetQuery: targetQ });
          }
          continue;
        }

        // C. ADD (Tambah / Tambahkan)
        const isExplicitAdd = /^(?:tolong\s+|mohon\s+|revisi\s+)?(?:tambahkan|tambahan|tambah|order\s+lagi|pesan\s+lagi|\+)\s+/i.test(part) ||
          /\b(?:di\s*tambah(?:kan)?|tambah(?:kan)?)\b/i.test(part);

        if (isExplicitAdd || currentBlockMode === 'ADD') {
          const cleanAdd = part.replace(/^(?:tolong\s+|mohon\s+|revisi\s+)?(?:tambahkan|tambahan|tambah|order\s+lagi|pesan\s+lagi|\+)\s*/i, '')
            .replace(/\b(?:item|barang|produk|orderan|pesanan)\b/gi, '')
            .trim();
          const itemParsed = this.parseSingleItemAndQty(cleanAdd);
          actions.push({
            action: 'ADD',
            productQuery: itemParsed.product,
            qty: itemParsed.qty,
            unit: itemParsed.unit
          });
          continue;
        }

        // D. QTY dengan kata 'jadi / menjadi'
        const mQty1 = part.match(/(?:revisi\s+|ubah\s+)?(.+?)\s+(?:jadi|menjadi)\s+(\d+(?:[.,]\d+)?)\s*(?:karton|ktn|krton|krtn|krt|dus|box|bal|ball|pcs|pack|pak|roll|rol|pc|batang)?(?:\s+(?:saja|aja|ya|dong|deh|nih|lah|mas|pak|kak|min|admin|bos))?$/i);
        if (mQty1) {
          const prod = mQty1[1].replace(/\b(revisi|ubah|tolong|mohon|item|barang|produk|po|faktur|invoice)\b/gi, '').trim();
          const unitM = part.match(/(karton|ktn|krton|krtn|krt|dus|box|bal|ball|pcs|pack|pak|roll|rol|pc|batang)(?:\s+(?:saja|aja|ya|dong|deh|nih|lah|mas|pak|kak|min|admin|bos))?$/i);
          actions.push({
            action: 'QTY',
            targetQuery: prod,
            qty: parseFloat(mQty1[2].replace(',', '.')),
            unit: unitM ? unitM[1].toLowerCase() : 'karton'
          });
          continue;
        }

        // E. Pola nama barang diikuti jumlah (misal 'brs merah 15 karton' atau 'rolade ayam roll 250 roll')
        const itemCandidate = this.parseSingleItemAndQty(part);
        if (itemCandidate && itemCandidate.product && itemCandidate.qty > 0) {
          const matchedIdx = this.matchItemFromList(itemCandidate.product, currentInvoiceItems);
          if (matchedIdx !== -1) {
            actions.push({ action: 'QTY', targetQuery: itemCandidate.product, qty: itemCandidate.qty, unit: itemCandidate.unit });
          } else {
            actions.push({ action: 'ADD', productQuery: itemCandidate.product, qty: itemCandidate.qty, unit: itemCandidate.unit });
          }
          continue;
        }
      }
    }

    return actions;
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
    resText += `   ↳ Quote/balas pesanan dengan: \`revisi PO [nama barang] jadi [jumlah] karton\` atau tukar barang: \`revisi [nama lama] di ganti [nama baru] [jumlah] karton\`.\n\n`;
    resText += `💳 *3. Cek Kartu Piutang & Dokumen PDF Piutang*\n`;
    resText += `   ↳ Ketik: \`piutang [nama toko]\` atau \`kirimkan file pdf piutang [nama toko]\`.\n\n`;
    resText += `📦 *4. Cek Stok Fisik Gudang*\n`;
    resText += `   ↳ Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst*) atau \`stok keseluruhan\`.\n\n`;
    resText += `📄 *5. Cek Rincian Faktur / Invoice (Unduh Dokumen PDF)*\n`;
    resText += `   ↳ Ketik: \`faktur [nomor]\` atau \`kirimkan file pdf PO nomor [nomor]\`.\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Untuk hal-hal di luar 5 layanan otomatis di atas atau pesan personal untuk Admin, beliau akan membalas segera setelah aktif kembali ya! 😊`;

    return resText;
  }

  /**
   * Membuat dan Mengirimkan File PDF Faktur Penjualan Resmi
   */
  async handleSendPdfInvoice(text, senderName = 'Kak', payload = null) {
    const clean = normalizeText(text);
    const regexPrefix = /(?:faktur|invoice|nota|po|nomor|nomer|#)\s*[:#.]?\s*([a-zA-Z]{1,3}\d{1,6})\b/i;
    const regexDistance = /(?:faktur|invoice|nota|po).*?\b(\d{2,8})\b/i;
    const regexAnyNumber = /\b(\d{2,8})\b/;
    const match = clean.match(regexPrefix) || clean.match(regexDistance) || clean.match(regexAnyNumber);

    let invNo = match && match[1] ? match[1].replace(/^[#]/, '').trim() : null;

    if (!invNo && payload && payload.quotedMessageText) {
      const qMatch = payload.quotedMessageText.match(/(?:invoice|faktur|nota|po|#)\s*[:#.]?\s*(\d{2,6})/i);
      if (qMatch) invNo = qMatch[1];
    }

    if (!invNo) {
      return {
        reply: `🤖 *[L-W.A.V.I.S]*\n` +
          `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
          `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
          `Halo ${senderName}! Untuk mengirimkan file dokumen PDF faktur, mohon sebutkan nomor fakturnya ya. 😊\n\n` +
          `💡 *Contoh:* ketik \`kirimkan file pdf PO nomor 700\` atau \`pdf faktur 697\`.`
      };
    }

    try {
      const db = this.firebaseAdapter?.db || this.firebaseAdapter?.clientDb;
      let invData = null;

      if (!db && this.mockInvoices) {
        invData = this.mockInvoices[invNo] || null;
      }

      if (!invData && db && this.firebaseAdapter?.mode === 'admin') {
        const snap = await db.collection('transactions').doc(invNo).get();
        if (snap.exists) {
          invData = snap.data();
        } else {
          const qSnap = await db.collection('transactions').where('invoiceNo', '==', invNo).limit(1).get();
          if (!qSnap.empty) invData = qSnap.docs[0].data();
        }
      } else if (!invData && db && this.firebaseAdapter?.clientSdk) {
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
        return {
          reply: `🤖 *[L-W.A.V.I.S]*\n` +
            `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
            `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
            `Halo ${senderName}! Data Faktur / Invoice *#${invNo}* tidak ditemukan di dalam sistem database. ❌\n\n` +
            `Mohon periksa kembali nomor fakturnya ya! Jika butuh bantuan lebih lanjut, Admin akan siap membantu setelah aktif kembali. 😊`
        };
      }

      if (!invData.invoiceNo) invData.invoiceNo = invNo;
      if (invData.note && invData.note.toLowerCase().includes('revisi wa l-w.a.v.i.s')) {
        invData.note = '';
      }

      const pdfBuffer = WavisPdfGenerator.generateInvoicePdf(invData);
      const custDisplay = invData.aliasName ? `${invData.aliasName} (${invData.customerName})` : (invData.customerName || 'Pelanggan');

      const caption = `📄 *[DOKUMEN RESMI FAKTUR PENJUALAN]*\n` +
        `No. Invoice: #${invNo}\n` +
        `Pelanggan: ${custDisplay}\n` +
        `Grand Total: Rp ${Math.round(invData.grandTotal || 0).toLocaleString('id-ID')}\n` +
        `Dibuat otomatis oleh L-W.A.V.I.S ✨`;

      return {
        reply: caption,
        document: {
          buffer: pdfBuffer,
          mimetype: 'application/pdf',
          fileName: WavisPdfGenerator.generateInvoiceFilename(invData),
          caption: caption
        }
      };
    } catch (err) {
      console.error('[L-W.A.V.I.S SEND PDF INVOICE ERROR]', err.message);
      return {
        reply: `⚠️ Maaf ${senderName}, terjadi kendala saat membuat file dokumen PDF faktur #${invNo}: ${err.message}`
      };
    }
  }

  /**
   * Membuat dan Mengirimkan File PDF Kartu Piutang Resmi
   */
  async handleSendPdfReceivables(text, senderName = 'Kak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const customers = this.autoPoProcessor.cachedCustomers || [];
    const matchedCustomer = this.matchCustomerFromQuery(text, customers);

    if (!matchedCustomer) {
      return {
        reply: `🤖 *[L-W.A.V.I.S]*\n` +
          `_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n` +
          `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
          `Halo ${senderName}! Untuk mengirimkan file dokumen PDF kartu piutang, mohon sebutkan nama toko / pelanggannya ya. 😊\n\n` +
          `💡 *Contoh:* ketik \`kirimkan file pdf piutang AFM\` atau \`pdf piutang SJJ\`.`
      };
    }

    const custName = matchedCustomer.customerName || 'PELANGGAN';
    const alias = matchedCustomer.aliasName ? ` (${matchedCustomer.aliasName})` : '';

    try {
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

      const unpaidInvoices = allCustomerTransactions.filter(inv => {
        const st = (inv.statusTransfer || '').toUpperCase();
        return st !== 'PAID' && (Number(inv.grandTotal) || 0) > 0;
      });

      let totalDebt = 0;
      unpaidInvoices.forEach(inv => {
        const grand = Number(inv.grandTotal) || 0;
        const paid = Number(inv.transferBankDetails?.totalPaid || inv.transferBankDetails?.amount || inv.paidAmount || 0);
        totalDebt += Math.max(0, grand - paid);
      });

      let lastPayment = null;
      for (const inv of allCustomerTransactions) {
        const paid = Number(inv.transferBankDetails?.totalPaid || inv.transferBankDetails?.amount || inv.paidAmount || 0);
        if (paid > 0) {
          lastPayment = {
            amount: paid,
            date: inv.transferBankDetails?.rawDate || inv.transferBankDetails?.transferDate || inv.transferDate || inv.date,
            bank: inv.transferBankDetails?.bank || ''
          };
          break;
        }
      }

      const pdfData = {
        customer: matchedCustomer,
        unpaidInvoices,
        allTransactions: allCustomerTransactions,
        totalDebt,
        lastPayment
      };

      const pdfBuffer = WavisPdfGenerator.generateReceivablesPdf(pdfData);
      const safeAlias = (matchedCustomer.aliasName || matchedCustomer.customerName || 'Customer').replace(/[^a-zA-Z0-9]/g, '_');

      const caption = `📊 *[DOKUMEN RESMI KARTU PIUTANG]*\n` +
        `Pelanggan: ${custName}${alias}\n` +
        `Total Sisa Piutang: Rp ${Math.round(totalDebt).toLocaleString('id-ID')}\n` +
        `Faktur Belum Lunas: ${unpaidInvoices.length} Invoice\n` +
        `Dibuat otomatis oleh L-W.A.V.I.S ✨`;

      return {
        reply: caption,
        document: {
          buffer: pdfBuffer,
          mimetype: 'application/pdf',
          fileName: `Kartu_Piutang_${safeAlias}.pdf`,
          caption: caption
        }
      };
    } catch (err) {
      console.error('[L-W.A.V.I.S SEND PDF RECEIVABLES ERROR]', err.message);
      return {
        reply: `⚠️ Maaf ${senderName}, gagal membuat file PDF kartu piutang: ${err.message}`
      };
    }
  }

  /**
   * Kirim File Dokumen (PDF) WhatsApp via Baileys Socket
   */
  async sendDocumentReply(remoteJid, documentObj, caption = '', quotedMsg = null, senderPhone = null) {
    if (!remoteJid || !documentObj || !documentObj.buffer) return false;
    const sock = this.sockGetter ? this.sockGetter() : null;
    if (!sock) {
      console.warn('[L-W.A.V.I.S] ⚠️ Socket WhatsApp tidak terhubung. Kirim PDF dibatalkan.');
      return false;
    }

    // STRICT: JANGAN PERNAH mengirim balasan interaktif bot ke grup WhatsApp (@g.us)!
    if (remoteJid.endsWith('@g.us')) {
      console.log(`[L-W.A.V.I.S SKIP] 🛑 Membatalkan pengiriman dokumen PDF ke grup WhatsApp (${remoteJid}).`);
      return false;
    }

    const targetJid = remoteJid;

    try {
      try {
        await sock.sendPresenceUpdate('composing', targetJid);
        await new Promise(r => setTimeout(r, 1200));
        await sock.sendPresenceUpdate('paused', targetJid);
      } catch (_) {}

      const options = {};
      if (quotedMsg && typeof quotedMsg === 'object' && quotedMsg.key) {
        options.quoted = quotedMsg;
      }

      const docPayload = {
        document: documentObj.buffer,
        mimetype: documentObj.mimetype || 'application/pdf',
        fileName: documentObj.fileName || 'dokumen.pdf',
        caption: caption || documentObj.caption || ''
      };

      const sentMsg = await sock.sendMessage(targetJid, docPayload, options);
      console.log(`[L-W.A.V.I.S SUCCESS] 📄 File PDF "${docPayload.fileName}" berhasil dikirim ke ${targetJid}!`);

      if (sentMsg && sentMsg.key && sentMsg.message && typeof this.rawMessageStore === 'function') {
        const msgId = sentMsg.key.id;
        this.rawMessageStore(targetJid, msgId, sentMsg.message);
        if (remoteJid && remoteJid !== targetJid) {
          this.rawMessageStore(remoteJid, msgId, sentMsg.message);
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
      console.error('[L-W.A.V.I.S SEND PDF ERROR]', err.message);
      return false;
    }
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
