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
    this.lastAdminActivityTime = 0;
  }

  setSocketGetter(fn) {
    this.sockGetter = fn;
  }

  recordAdminActivity() {
    this.lastAdminActivityTime = Date.now();
  }

  isAdminStandby(thresholdMs = 3 * 60 * 1000) {
    return (Date.now() - this.lastAdminActivityTime) < thresholdMs;
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
    text += `ℹ️ *Catatan Sistem:*\n`;
    text += `• Faktur sudah aman masuk antrean kasir.\n`;
    text += `• Jika ada pesan personal untuk Admin, beliau akan membalas segera setelah aktif kembali. 😊`;

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

    // 3. Cek Pola Sapaan / Menu Bantuan
    const greetingPattern = /\b(halo|hello|pagi|siang|sore|malam|assalamualaikum|bantuan|menu|wavis|hai)\b/i;
    if (greetingPattern.test(clean)) {
      return 'GREETING_MENU';
    }

    return 'UNKNOWN';
  }

  /**
   * Cari Pelanggan yang Cocok dari Teks Query
   */
  matchCustomerFromQuery(text, customers) {
    const clean = normalizeText(text);
    if (!clean || !Array.isArray(customers) || customers.length === 0) return null;

    // 1. Cek Exact Alias (e.g. 'aw ff', 'griya ff', 'afm')
    for (const c of customers) {
      const alias = normalizeText(c.aliasName || c.alias || '');
      if (alias.length >= 2) {
        const aliasPattern = new RegExp('(^|\\s)' + alias.replace(/\s+/g, '\\s+') + '(\\s|$)', 'i');
        if (aliasPattern.test(clean)) return c;

        // Root alias tanpa 'ff' / 'frozen food' (e.g. 'aw' dari 'aw ff', 'griya' dari 'griya ff')
        const rootAlias = alias.replace(/\b(ff|frozen|food)\b/g, '').trim();
        if (rootAlias.length >= 2) {
          const rootPattern = new RegExp('(^|\\s)' + rootAlias + '(\\s|$)', 'i');
          if (rootPattern.test(clean)) return c;
        }
      }
    }

    // 2. Cek Nama Pelanggan (e.g. 'aw frozen food' -> 'aw')
    for (const c of customers) {
      const name = normalizeText(c.customerName || c.name || '');
      if (name.length >= 3 && clean.includes(name)) return c;
      const rootName = name.replace(/\b(ff|frozen|food|toko|cv|pt)\b/g, '').trim();
      if (rootName.length >= 2) {
        const rootPattern = new RegExp('(^|\\s)' + rootName + '(\\s|$)', 'i');
        if (rootPattern.test(clean)) return c;
      }
    }

    // 3. Word overlap fallback (abaikan kata umum piutang & stop words)
    const stopWords = ['piutang', 'utang', 'bon', 'tagihan', 'cek', 'kartu', 'saya', 'ingin', 'mau', 'nya', 'mas', 'pak', 'dong', 'tolong', 'info'];
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
            date: rawDate
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
        lastPayStr = `Rp ${lastPaymentInfo.amount.toLocaleString('id-ID')}${tgl}`;
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
        resText += `✅ *Alhamdulillah, semua faktur tercatat sudah lunas!*\n`;
      }

      resText += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
      resText += `ℹ️ _Ketik \`order\` atau kirimkan list pesanan jika toko ini mau ambil barang lagi ya!_`;

      return resText;
    } catch (e) {
      console.error('[WAVIS RECEIVABLES ERROR]', e.message);
      return `🤖 *[L-W.A.V.I.S]*\nMaaf ${senderName}, terjadi kendala saat membaca database piutang. Silakan ulangi sesaat lagi ya.`;
    }
  }

  /**
   * Menjawab Pertanyaan Stok
   */
  async handleStockQuery(text, senderName = 'Kak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const products = this.autoPoProcessor.cachedProducts || [];
    const matchedProduct = this.matchProductFromQuery(text, products);

    if (!matchedProduct) {
      return `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk mengecek stok gudang, mohon sebutkan nama produknya ya.\n\n` +
        `💡 *Contoh:* ketik \`stok bratwurst mini\` atau \`ready beres merah 24\`.`;
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
    resText += `ℹ️ _Langsung kirim format PO jika ingin langsung dibuatkan draft faktur ya!_`;

    return resText;
  }

  /**
   * Menjawab Sapaan & Menampilkan Menu Edukasi
   */
  handleGreetingMenu(senderName = 'Kak') {
    let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    resText += `Halo ${senderName}! 👋\n\n`;
    resText += `Admin / Developer saat ini sedang tidak standby di tempat. \n`;
    resText += `Namun jangan khawatir, selagi menunggu beliau online, apa yang bisa *L-W.A.V.I.S* bantu untuk kelancaran operasional Anda hari ini?\n\n`;
    resText += `Saya bisa langsung melayani:\n`;
    resText += `📝 *1. Buat Pesanan Baru (PO)*\n`;
    resText += `   Langsung kirim list order toko di sini, faktur akan langsung saya buatkan otomatis.\n\n`;
    resText += `💳 *2. Cek Piutang Toko*\n`;
    resText += `   Ketik: \`piutang [nama toko]\` (contoh: *piutang AFM*)\n\n`;
    resText += `📦 *3. Cek Stok Barang Gudang*\n`;
    resText += `   Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst*)\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Silakan ketik apa yang diperlukan. Untuk pesan pribadi atau urusan di luar sistem, akan tetap dibalas langsung oleh Admin setelah aktif kembali ya! 😊`;

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

      await sock.sendMessage(targetJid, { text }, options);
      console.log(`[L-W.A.V.I.S SUCCESS] 🤖 Pesan interaktif berhasil dikirim ke ${targetJid}!`);
      return true;
    } catch (err) {
      console.error('[L-W.A.V.I.S SEND ERROR]', err.message);
      return false;
    }
  }
}

module.exports = WavisInteractiveEngine;
