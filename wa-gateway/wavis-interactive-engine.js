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
  formatPoConfirmation(invoiceData, senderName = 'Pak') {
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
   */
  classifyIntent(text) {
    const clean = normalizeText(text);
    if (!clean) return 'UNKNOWN';

    // 1. Cek Pola Tanya Piutang
    const piutangPattern = /\b(piutang|utang|bon|tagihan|sisa tagihan|sisa piutang|belum bayar)\b/i;
    if (piutangPattern.test(clean)) {
      return 'QUERY_RECEIVABLES';
    }

    // 2. Cek Pola Tanya Stok
    const stockPattern = /\b(stok|stock|ready|sisa berapa|ada ga|ada gak|masih ada)\b/i;
    if (stockPattern.test(clean)) {
      return 'QUERY_STOCK';
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

    // Buang kata kunci tanya piutang agar fokus ke nama toko
    const queryWithoutKw = clean
      .replace(/\b(piutang|utang|bon|tagihan|sisa|berapa|belum|bayar|toko|cek|tolong|dong|mas|pak|ya)\b/g, '')
      .replace(/\s+/g, ' ')
      .trim();

    if (!queryWithoutKw) return null;

    const words = queryWithoutKw.split(/\s+/).filter(w => w.length >= 2);

    // 1. Cek Exact Alias (minimal 3 huruf, misal "AFM", "MMM")
    for (const c of customers) {
      const alias = normalizeText(c.aliasName || '');
      if (alias.length >= 3 && words.includes(alias)) {
        return c;
      }
    }

    // 2. Cek Inisial Nama (minimal 3 huruf)
    for (const c of customers) {
      const name = normalizeText(c.customerName || '');
      const nameWords = name.split(/\s+/).filter(Boolean);
      const initials = nameWords.map(w => w[0]).join('');
      if (initials.length >= 3 && words.includes(initials)) {
        return c;
      }
    }

    // 3. Cek Substring Nama
    for (const c of customers) {
      const name = normalizeText(c.customerName || '');
      if (name.length >= 3 && queryWithoutKw.includes(name)) {
        return c;
      }
    }

    // 4. Word overlap score
    let best = null;
    let maxScore = 0;
    for (const c of customers) {
      const name = normalizeText(c.customerName || '');
      const alias = normalizeText(c.aliasName || '');
      const cWords = (name + ' ' + alias).split(/\s+/);
      let score = 0;
      for (const qw of words) {
        if (qw.length >= 3 && cWords.includes(qw)) score += 5;
      }
      if (score > maxScore && score >= 5) {
        maxScore = score;
        best = c;
      }
    }

    // Fallback untuk alias 2 huruf jika benar-benar ada di kata
    if (!best) {
      for (const c of customers) {
        const alias = normalizeText(c.aliasName || '');
        if (alias.length === 2 && words.includes(alias)) {
          return c;
        }
      }
    }

    return best;
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
  async handleReceivablesQuery(text, senderName = 'Pak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const customers = this.autoPoProcessor.cachedCustomers || [];
    const matchedCustomer = this.matchCustomerFromQuery(text, customers);

    if (!matchedCustomer) {
      return `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk mengecek kartu piutang, mohon sebutkan nama toko / pelanggannya ya Pak.\n\n` +
        `💡 *Contoh:* ketik \`piutang AFM\` atau \`tagihan Maju Market\`.`;
    }

    const custName = matchedCustomer.customerName || 'PELANGGAN';
    const alias = matchedCustomer.aliasName ? ` (${matchedCustomer.aliasName})` : '';

    try {
      // Ambil transaksi belum lunas untuk customer ini
      const db = this.firebaseAdapter.db || this.firebaseAdapter.clientDb;
      let unpaidInvoices = [];

      if (this.firebaseAdapter.mode === 'admin' && db) {
        const snap = await db.collection('invoices')
          .where('customerName', '==', custName)
          .get();
        unpaidInvoices = snap.docs
          .map(d => ({ id: d.id, ...d.data() }))
          .filter(inv => (inv.statusTransfer || '').toUpperCase() !== 'PAID');
      } else if (this.firebaseAdapter.clientSdk && db) {
        const { collection, query, where, getDocs } = this.firebaseAdapter.clientSdk;
        const snap = await getDocs(query(collection(db, 'invoices'), where('customerName', '==', custName)));
        unpaidInvoices = snap.docs
          .map(d => ({ id: d.id, ...d.data() }))
          .filter(inv => (inv.statusTransfer || '').toUpperCase() !== 'PAID');
      }

      let totalRemaining = 0;
      let lastPaymentInfo = null;

      unpaidInvoices.forEach(inv => {
        const grand = Number(inv.grandTotal) || 0;
        const paid = Number(inv.paidAmount) || 0;
        const remaining = grand - paid;
        if (remaining > 0) totalRemaining += remaining;

        if (paid > 0) {
          lastPaymentInfo = {
            amount: paid,
            date: inv.transferDate || inv.date || null
          };
        }
      });

      let lastPayStr = '-';
      if (lastPaymentInfo && lastPaymentInfo.amount > 0) {
        let tgl = '';
        try {
          const d = lastPaymentInfo.date ? (lastPaymentInfo.date.toDate ? lastPaymentInfo.date.toDate() : new Date(lastPaymentInfo.date)) : null;
          if (d) tgl = ` (Tgl: ${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()})`;
        } catch (_) {}
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
      resText += `ℹ️ _Ketik \`order\` atau kirimkan list pesanan jika toko ini mau ambil barang lagi ya Pak!_`;

      return resText;
    } catch (e) {
      console.error('[WAVIS RECEIVABLES ERROR]', e.message);
      return `🤖 *[L-W.A.V.I.S]*\nMaaf ${senderName}, terjadi kendala saat membaca database piutang. Silakan ulangi sesaat lagi ya Pak.`;
    }
  }

  /**
   * Menjawab Pertanyaan Stok
   */
  async handleStockQuery(text, senderName = 'Pak') {
    await this.autoPoProcessor.refreshCacheIfNeeded();
    const products = this.autoPoProcessor.cachedProducts || [];
    const matchedProduct = this.matchProductFromQuery(text, products);

    if (!matchedProduct) {
      return `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
        `Halo ${senderName}! Untuk mengecek stok gudang, mohon sebutkan nama produknya ya Pak.\n\n` +
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
    resText += `ℹ️ _Langsung kirim format PO jika ingin langsung dibuatkan draft faktur ya Pak!_`;

    return resText;
  }

  /**
   * Menjawab Sapaan & Menampilkan Menu Edukasi
   */
  handleGreetingMenu(senderName = 'Pak') {
    let resText = `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
    resText += `Halo ${senderName}! 👋\n\n`;
    resText += `Admin / Developer saat ini sedang tidak standby di tempat. \n`;
    resText += `Namun jangan khawatir, selagi menunggu beliau online, apa yang bisa *L-W.A.V.I.S* bantu untuk operasional Bapak?\n\n`;
    resText += `Saya bisa langsung melayani:\n`;
    resText += `📝 *1. Buat Pesanan Baru (PO)*\n`;
    resText += `   Langsung kirim list order toko di sini, faktur akan langsung saya buatkan otomatis.\n\n`;
    resText += `💳 *2. Cek Piutang Toko*\n`;
    resText += `   Ketik: \`piutang [nama toko]\` (contoh: *piutang AFM*)\n\n`;
    resText += `📦 *3. Cek Stok Barang Gudang*\n`;
    resText += `   Ketik: \`stok [nama barang]\` (contoh: *stok bratwurst*)\n\n`;
    resText += `────────────────────────────\n`;
    resText += `Silakan ketik apa yang Bapak perlukan. Untuk pesan pribadi atau urusan di luar sistem, akan tetap dibalas langsung oleh Admin setelah aktif kembali ya Pak! 😊`;

    return resText;
  }

  /**
   * Kirim Pesan Balasan WhatsApp via Baileys Socket
   */
  async sendReply(remoteJid, text, quotedMsg = null) {
    if (!remoteJid || !text) return false;
    const sock = this.sockGetter ? this.sockGetter() : null;
    if (!sock) {
      console.warn('[L-W.A.V.I.S] ⚠️ Socket WhatsApp tidak terhubung. Balasan dibatalkan.');
      return false;
    }

    try {
      // 1. Simulasi status mengetik ("composing presence")
      try {
        await sock.sendPresenceUpdate('composing', remoteJid);
        await new Promise(r => setTimeout(r, 1200)); // jeda 1.2 detik agar natural
        await sock.sendPresenceUpdate('paused', remoteJid);
      } catch (_) {}

      // 2. Kirim pesan balasan
      const options = {};
      if (quotedMsg) {
        options.quoted = quotedMsg;
      }

      await sock.sendMessage(remoteJid, { text }, options);
      console.log(`[L-W.A.V.I.S SUCCESS] 🤖 Pesan interaktif berhasil dikirim ke ${remoteJid}!`);
      return true;
    } catch (err) {
      console.error('[L-W.A.V.I.S SEND ERROR]', err.message);
      return false;
    }
  }
}

module.exports = WavisInteractiveEngine;
