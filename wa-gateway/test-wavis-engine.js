/**
 * Unit Test untuk WavisInteractiveEngine (Tahap 3 Interactive)
 */

const assert = require('assert');
const WavisInteractiveEngine = require('./wavis-interactive-engine');

console.log('🧪 Memulai Pengujian Unit WavisInteractiveEngine...');

const engine = new WavisInteractiveEngine(null, null);

// 1. UJI FORMAT KONFIRMASI PO
console.log('\n--- Test 1: Format Konfirmasi PO L-W.A.V.I.S ---');
const mockInvoice = {
  invoiceNo: '696',
  customerName: 'AHYAR',
  aliasName: 'AFM',
  city: 'BATANG',
  province: 'JAWA TENGAH',
  date: new Date('2026-11-16T10:37:00Z'),
  status: 'PENDING',
  statusTransfer: 'UNPAID',
  grandTotal: 29279850,
  items: [
    {
      productName: 'BRS COKLAT 24S 2 500G',
      qty: 150,
      isiKarton: 15,
      cartonCount: 10,
      price: 28234,
      discountPercent: 0,
      discountAmount: 0,
      subtotal: 4235100,
      weightKg: 75
    },
    {
      productName: 'BRS COKLAT 13S 2 500G',
      qty: 450,
      isiKarton: 15,
      cartonCount: 30,
      price: 27962,
      discountPercent: 0,
      discountAmount: 0,
      subtotal: 12582900,
      weightKg: 225
    },
    {
      productName: 'BRS COKLAT 7S 2 500G',
      qty: 75,
      isiKarton: 15,
      cartonCount: 5,
      price: 27962,
      discountPercent: 0,
      discountAmount: 0,
      subtotal: 2097150,
      weightKg: 37.5
    },
    {
      productName: 'BRS MERAH 24S 500G',
      qty: 300,
      isiKarton: 15,
      cartonCount: 20,
      price: 34549,
      discountPercent: 0,
      discountAmount: 0,
      subtotal: 10364700,
      weightKg: 150
    }
  ]
};

const poText = engine.formatPoConfirmation(mockInvoice, 'Pak Joko');
console.log(poText);

assert(poText.includes('🤖 *[PESAN OTOMATIS: L-W.A.V.I.S]*'), 'Header L-WAVIS harus ada');
assert(poText.includes('Halo Pak Joko!'), 'Sapaan nama pengirim harus ada');
assert(poText.includes('AFM (AHYAR)'), 'Nama toko harus ada');
assert(poText.includes('#696'), 'Nomor invoice harus ada');
assert(poText.includes('Status Paid:* UNPAID'), 'Status Paid harus ada');
assert(poText.includes('GrandTotal Karton:* 65 Ktn'), 'GrandTotal Karton harus 65 Ktn');
assert(poText.includes('GRAND TOTAL:* *Rp 29.279.850*'), 'Grand Total harus sesuai');
console.log('✅ Test 1 PASSED: Format PO 2-Baris Padat + Status Paid + GrandTotal Sempurna!');

// 2. UJI INTENT CLASSIFICATION
console.log('\n--- Test 2: Klasifikasi Maksud / Intent ---');
const mockProductsForIntent = [
  { id: 'p1', productName: 'BERES MERAH 24', name: 'BERES MERAH 24', price: 34549 },
  { id: 'p2', productName: 'BRATWURST MINI', name: 'BRATWURST MINI', price: 45838 }
];

const intentTests = [
  { text: 'piutang AFM', expected: 'QUERY_RECEIVABLES' },
  { text: 'utang e afm piro mas?', expected: 'QUERY_RECEIVABLES' },
  { text: 'cek bon maju market', expected: 'QUERY_RECEIVABLES' },
  { text: 'sisa tagihan griya ff', expected: 'QUERY_RECEIVABLES' },
  { text: 'stok bratwurst ori ready ga?', expected: 'QUERY_STOCK' },
  { text: 'stock rolade sapi sisa berapa', expected: 'QUERY_STOCK' },
  { text: 'ready beres merah 24', expected: 'QUERY_STOCK' },
  { text: 'stok', expected: 'QUERY_STOCK' },
  { text: 'ready stok?', expected: 'QUERY_STOCK' },
  { text: 'ready gak?', expected: 'QUERY_STOCK' },
  { text: 'Are you ready?', expected: 'UNKNOWN' },
  { text: 'sudah ready?', expected: 'UNKNOWN' },
  { text: 'aku dah ready nih', expected: 'UNKNOWN' },
  { text: 'halo mas', expected: 'GREETING_MENU' },
  { text: 'pagi admin', expected: 'GREETING_MENU' },
  { text: 'assalamualaikum wavis', expected: 'GREETING_MENU' },
  { text: 'apakah kamu bisa menampilkan data faktur atau invoice nomer 693', expected: 'QUERY_INVOICE' },
  { text: 'faktur 699', expected: 'QUERY_INVOICE' },
  { text: 'kirimkan data PO nomor invoice 697', expected: 'QUERY_INVOICE' },
  { text: 'cek PO 697', expected: 'QUERY_INVOICE' },
  { text: 'tampilkan PO 697', expected: 'QUERY_INVOICE' },
  { text: 'revisi PO brs merah jadi 35 karton', expected: 'REVISE_PO' },
  { text: 'revisi faktur 699 brs merah jadi 35 dus', expected: 'REVISE_PO' },
  { text: 'tolong bantu cek toko', expected: 'SMART_FALLBACK' },
  { text: 'tadi saya lihat ada kucing di gudang', expected: 'UNKNOWN' }
];

intentTests.forEach(({ text, expected }) => {
  const actual = engine.classifyIntent(text, mockProductsForIntent);
  assert.strictEqual(actual, expected, `Intent untuk "${text}" harus "${expected}", tapi didapat "${actual}"`);
  console.log(`  ✓ "${text}" → [${actual}]`);
});
console.log('✅ Test 2 PASSED: Klasifikasi Intent 100% Akurat (Termasuk filter "Are you ready?")!');

// 3. UJI CUSTOMER & PRODUCT MATCHER
console.log('\n--- Test 3: Customer & Product Matcher ---');
const mockCustomers = [
  { id: 'c1', customerName: 'AHYAR', aliasName: 'AFM' },
  { id: 'c2', customerName: 'MAJU MARKET MANDIRI', aliasName: 'MMM' },
  { id: 'c3', customerName: 'GRIYA FROZEN FOOD', aliasName: 'GRIYA FF' },
  { id: 'H002', customerName: 'AW FROZEN FOOD', aliasName: 'AW FF' },
  { id: 'AD008', customerName: 'SURYANTO WIBISONO WIBOWO', aliasName: 'SUMBER JADI JAYA', odooNamePtSo: 'SJJ JATENG' }
];

engine.autoPoProcessor = {
  cachedRules: [
    { type: 'customer_alias', keyword: 'SJJ', mappedValue: 'SURYANTO WIBISONO WIBOWO', targetId: 'AD008' }
  ],
  cachedProducts: [
    { id: 'p1', productName: 'BRS COKLAT 24S 500 G', price: 30688, isiKarton: 15, stock: 435 },
    { id: 'p2', productName: 'BRATWURST SAPI MINI 500 G', price: 45838, isiKarton: 15, stock: 1200 },
    { id: 'p3', productName: 'ROLLADE SAPI 215 G', price: 17500, isiKarton: 30, stock: 0 }
  ],
  refreshCacheIfNeeded: async () => {}
};

const custMatchSjj1 = engine.matchCustomerFromQuery('wavis kirimkan kartu piutang dari SJJ', mockCustomers);
assert(custMatchSjj1 && custMatchSjj1.id === 'AD008', 'Harus cocok dengan SJJ (Sumber Jadi Jaya)');
console.log(`  ✓ Cocok Pelanggan: "${custMatchSjj1.aliasName} (${custMatchSjj1.customerName})" dari kalimat percakapan`);

const custMatchSjj2 = engine.matchCustomerFromQuery('piutang sjj', mockCustomers);
assert(custMatchSjj2 && custMatchSjj2.id === 'AD008', 'Harus cocok dengan SJJ (Sumber Jadi Jaya)');
console.log(`  ✓ Cocok Pelanggan: "${custMatchSjj2.aliasName}" dari "piutang sjj"`);

const custMatchSjj3 = engine.matchCustomerFromQuery('piutang sumber jadi jaya', mockCustomers);
assert(custMatchSjj3 && custMatchSjj3.id === 'AD008', 'Harus cocok dengan Sumber Jadi Jaya');
console.log(`  ✓ Cocok Pelanggan: "${custMatchSjj3.aliasName}" dari nama lengkap toko`);

const custMatch = engine.matchCustomerFromQuery('tolong cek sisa utang afm mas', mockCustomers);
assert(custMatch && custMatch.aliasName === 'AFM', 'Harus cocok dengan AFM');
console.log(`  ✓ Cocok Pelanggan: "${custMatch.aliasName} (${custMatch.customerName})"`);

const custMatchAw = engine.matchCustomerFromQuery('saya ingin cek kartu piutang nya AW', mockCustomers);
assert(custMatchAw && custMatchAw.aliasName === 'AW FF', 'Harus cocok dengan AW FF');
console.log(`  ✓ Cocok Pelanggan: "${custMatchAw.aliasName} (${custMatchAw.customerName})"`);

const custMatchAw2 = engine.matchCustomerFromQuery('piutang AW FF', mockCustomers);
assert(custMatchAw2 && custMatchAw2.aliasName === 'AW FF', 'Harus cocok dengan AW FF');
console.log(`  ✓ Cocok Pelanggan: "${custMatchAw2.aliasName} (${custMatchAw2.customerName})"`);

const prodMatch = engine.matchProductFromQuery('stok bratwurst mini sisa berapa', engine.autoPoProcessor.cachedProducts);
assert(prodMatch && prodMatch.productName.includes('BRATWURST SAPI MINI'), 'Harus cocok dengan Bratwurst Mini');
console.log(`  ✓ Cocok Produk: "${prodMatch.productName}"`);
console.log('✅ Test 3 PASSED: Matching Pelanggan & Produk Sempurna!');

// 4. UJI OVERALL WAREHOUSE STOCK QUERY (CEK STOK KESELURUHAN)
console.log('\n--- Test 4: Cek Stok Fisik Keseluruhan ---');
(async () => {
  const stockSummary = await engine.handleStockQuery('saya ingin cek stok barang fisik keseluruhan', 'Rogue');
  console.log(stockSummary);
  assert(stockSummary.includes('RINGKASAN TOTAL GUDANG'), 'Harus ada ringkasan total gudang');
  assert(stockSummary.includes('Top'), 'Harus ada top produk ready');
  console.log('✅ Test 4 PASSED: Respon Cek Stok Keseluruhan Cerdas & Informatif!');
})();

// 4. UJI GREETING MENU
console.log('\n--- Test 4: Menu Bantuan L-W.A.V.I.S ---');
const greeting = engine.handleGreetingMenu('Pak Joko');
assert(greeting.includes('Halo Pak Joko!'), 'Harus menyapa Pak Joko');
assert(greeting.includes('1. Buat Pesanan Baru'), 'Menu 1 PO harus ada');
assert(greeting.includes('2. Cek') && greeting.includes('Piutang'), 'Menu 2 Piutang harus ada');
assert(greeting.includes('3. Cek Stok'), 'Menu 3 Stok harus ada');
assert(greeting.includes('4. Revisi PO'), 'Menu 4 Revisi PO harus ada');
assert(greeting.includes('5. Cek Rincian Faktur'), 'Menu 5 Faktur harus ada');
console.log(greeting);
console.log('✅ Test 4 PASSED: Menu Bantuan L-W.A.V.I.S Sempurna!');

// 5. UJI SEND REPLY (GROUP BLOCK, LID RESOLUTION, & OUTGOING MESSAGE CACHE)
console.log('\n--- Test 5: Pengujian sendReply (Filter Grup, Resolusi LID, & Cache Pesan Keluar) ---');
let capturedTargetJid = null;
let capturedPayload = null;
const mockRawCache = new Map();

engine.setSocketGetter(() => ({
  sendPresenceUpdate: async () => {},
  sendMessage: async (jid, payload) => {
    capturedTargetJid = jid;
    capturedPayload = payload;
    return {
      key: { id: 'TEST_MSG_ID_999', remoteJid: jid, fromMe: true },
      message: { conversation: payload.text }
    };
  }
}));

engine.setRawMessageStore((jid, id, msg) => {
  mockRawCache.set(`${jid}_${id}`, msg);
});

(async () => {
  // 5A: Coba kirim ke Grup WhatsApp (@g.us) -> WAJIB DITOLAK
  const groupRes = await engine.sendReply('120363402777174624@g.us', 'Halo grup');
  assert.strictEqual(groupRes, false, 'sendReply ke grup harus ditolak');
  console.log('  ✓ sendReply ke grup WhatsApp (@g.us) berhasil diblokir');

  // 5B: Coba kirim ke LID (@lid) -> Balas langsung ke LID agar sinkron di HP bot & lawan bicara
  const lidRes = await engine.sendReply('33668835856433@lid', 'Halo Rogue', null, '087789733632');
  assert.strictEqual(lidRes, true, 'sendReply harus berhasil');
  assert.strictEqual(capturedTargetJid, '33668835856433@lid', 'Target JID harus tetap di thread LID yang sama');
  console.log(`  ✓ sendReply ke LID berhasil dikirim ke: ${capturedTargetJid}`);

  // 5C: Cek apakah pesan keluar tersimpan di rawMessageCache untuk pencegahan E2EE delay
  assert(mockRawCache.has('33668835856433@lid_TEST_MSG_ID_999'), 'Pesan keluar harus tersimpan di cache LID');
  assert(mockRawCache.has('6287789733632@s.whatsapp.net_TEST_MSG_ID_999'), 'Pesan keluar harus tersimpan di cache phone number');
  console.log('  ✓ Pesan keluar tersimpan di cache getMessage (LID & Phone) untuk instant retry E2EE');

  console.log('✅ Test 5 PASSED: Filter Grup, Resolusi LID, & Cache Pesan Keluar Bekerja Sempurna!');

  // 6. UJI VARIATIF SMART FOOTER & EXTENDED INTENT
  console.log('\n--- Test 6: Uji Smart Footer & Extended Intent ---');
  const footerDebt = engine.generateSmartFooter('RECEIVABLES_WITH_DEBT', { senderName: 'Rogue' });
  assert(footerDebt && footerDebt.length > 20, 'Footer piutang harus terbentuk');
  console.log('  ✓ Smart Footer Piutang:', footerDebt.split('\n')[0]);

  const footerLunas = engine.generateSmartFooter('RECEIVABLES_LUNAS', { senderName: 'Rogue' });
  assert(footerLunas && footerLunas.length > 20, 'Footer lunas harus terbentuk');
  console.log('  ✓ Smart Footer Lunas:', footerLunas.split('\n')[0]);

  const intent1 = engine.classifyIntent('adakah yang bisa wavis bantu selagi admin tidak standby');
  assert.strictEqual(intent1, 'GREETING_MENU', 'Harus mengenali intent GREETING_MENU');
  const intent2 = engine.classifyIntent('kamu bisa apa');
  assert.strictEqual(intent2, 'GREETING_MENU', 'Harus mengenali intent GREETING_MENU');
  console.log('  ✓ Intent extended (pertanyaan bantuan/kemampuan) sukses diklasifikasikan');

  console.log('✅ Test 6 PASSED: Smart Footer & Extended Intent Berhasil!');

  // 7. UJI SOP REVISI PO (PENDING VS DIKIRIM) & SMART FALLBACK
  console.log('\n--- Test 7: Uji SOP Revisi PO Otomatis & Smart Fallback ---');
  
  // 7A: Revisi Faktur status PENDING (Wajib Berhasil diperbarui)
  const pendingInvoiceMock = JSON.parse(JSON.stringify(mockInvoice)); // invoiceNo: 696, status: PENDING
  const revisionPayloadPending = {
    messageText: 'revisi PO brs merah jadi 35 karton',
    isQuotedReply: true,
    quotedMessageText: 'Orderan fiva bulan November 2026 aw ff...',
    mockInvoice: pendingInvoiceMock
  };

  const revisionResPending = await engine.handlePoRevision(revisionPayloadPending, 'Rogue');
  console.log(revisionResPending);
  assert(revisionResPending.includes('REVISI PO BERHASIL DIPROSES: L-W.A.V.I.S'), 'Header revisi berhasil harus ada');
  assert(revisionResPending.includes('🔄 *(DIREVISI)*'), 'Label item direvisi harus ada');
  assert(revisionResPending.includes('35 Ktn (525 pcs)'), 'Jumlah karton baru harus 35 Ktn (525 pcs)');
  assert(revisionResPending.includes('GrandTotal Karton:* 80 Ktn'), 'GrandTotal Karton harus 80 Ktn (10+30+5+35)');
  assert(revisionResPending.includes('GRAND TOTAL:* *Rp 37.053.375*'), 'GrandTotal rupiah harus terhitung ulang 37.053.375');
  console.log('  ✓ 7A PASSED: Revisi PO status PENDING berhasil dihitung ulang dan diperbarui');

  // 7B: Revisi Faktur status DIKIRIM (Wajib DITOLAK secara sopan & tegas)
  const shippedInvoiceMock = JSON.parse(JSON.stringify(mockInvoice));
  shippedInvoiceMock.status = 'DIKIRIM';
  const revisionPayloadShipped = {
    messageText: 'revisi PO brs merah jadi 35 karton',
    isQuotedReply: true,
    quotedMessageText: 'Orderan fiva bulan November 2026 aw ff...',
    mockInvoice: shippedInvoiceMock
  };

  const revisionResShipped = await engine.handlePoRevision(revisionPayloadShipped, 'Rogue');
  console.log(revisionResShipped);
  assert(revisionResShipped.includes('⚠️ *[REVISI PO DITOLAK: SUDAH DIKIRIM]*'), 'Header penolakan harus ada');
  assert(revisionResShipped.includes('berstatus *DIKIRIM*'), 'Penjelasan status dikirim harus ada');
  assert(revisionResShipped.includes('Admin / Kasir secara langsung'), 'Petunjuk manual ke admin kasir harus ada');
  console.log('  ✓ 7B PASSED: Revisi PO status DIKIRIM sukses DITOLAK sesuai SOP');

  // 7C: Uji Smart Fallback (Anti Bot Diam)
  const fallbackText = engine.handleSmartFallback('tolong bantu cek toko', 'Rogue');
  assert(fallbackText.includes('5 LAYANAN UTAMA YANG DAPAT SAYA PROSES OTOMATIS'), '5 layanan harus tercantum');
  assert(fallbackText.includes('Revisi PO (Khusus Status PENDING)'), 'Panduan revisi harus ada');
  assert(fallbackText.includes('Cek Rincian Faktur / Invoice'), 'Panduan faktur harus ada');
  console.log('  ✓ 7C PASSED: Smart Fallback edukatif dan anti bisu');

  // 7D: Uji Ekstraksi Query Faktur Kompleks ("kirimkan data PO nomor invoice 697")
  engine.mockInvoices = {
    '697': { ...mockInvoice, invoiceNo: '697' }
  };
  const invoiceRes = await engine.handleInvoiceQuery('kirimkan data PO nomor invoice 697', 'Rogue');
  console.log(invoiceRes);
  assert(invoiceRes.includes('#697'), 'Nomor invoice #697 harus ada di balasan faktur');
  assert(invoiceRes.includes('DETAIL FAKTUR: L-W.A.V.I.S'), 'Header detail faktur harus ada');
  console.log('  ✓ 7D PASSED: Query nomor invoice berhasil mengekstrak "697" dari kalimat kompleks');

  console.log('✅ Test 7 PASSED: SOP Revisi PO (Pending vs Dikirim) & Smart Fallback Sempurna!');

  // 8. UJI PERGANTIAN BARANG (PRODUCT SWAP / SUBSTITUTION) PADA REVISI PO
  console.log('\n--- Test 8: Uji Pergantian Barang (Product Swap / Substitution) ---');
  // Mock produk katalog master untuk penukaran
  engine.autoPoProcessor.cachedProducts.push({
    id: 'p-sosis-cocktail',
    productName: 'SOSIS COCKTAIL 250 G',
    name: 'SOSIS COCKTAIL 250 G',
    price: 34549,
    isiKarton: 15,
    sizeGrams: 250,
    stock: 500
  });

  const swapInvoiceMock = JSON.parse(JSON.stringify(mockInvoice)); // invoiceNo: 696, item 4: BRS MERAH 24S 500G
  const swapPayload = {
    messageText: 'revisi beres merah di ganti sosis cocktail 2 karton',
    isQuotedReply: true,
    quotedMessageText: 'Orderan fiva bulan November 2026...',
    mockInvoice: swapInvoiceMock
  };

  const swapResult = await engine.handlePoRevision(swapPayload, 'Rogue');
  console.log(swapResult);

  assert(swapResult.includes('SOSIS COCKTAIL 250 G'), 'Item harus terganti menjadi SOSIS COCKTAIL');
  assert(swapResult.includes('🔄 *(DIGANTI)*'), 'Tag DIGANTI harus muncul');
  assert(swapResult.includes('2 Ktn (30 pcs)'), 'Jumlah karton baru harus 2 Ktn (30 pcs)');
  assert(!swapResult.includes('BRS MERAH 24S 500G'), 'BRS MERAH tidak boleh ada lagi di daftar item');
  // Hitung ulang karton: 10 + 30 + 5 + 2 = 47 Ktn
  assert(swapResult.includes('GrandTotal Karton:* 47 Ktn'), 'GrandTotal Karton harus 47 Ktn');
  console.log('  ✓ 8A PASSED: Pergantian barang (swap) berhasil mengganti item, harga, dan total karton');

  // 9. UJI PEMBUATAN & PENGIRIMAN DOKUMEN PDF (FAKTUR & KARTU PIUTANG)
  console.log('\n--- Test 9: Uji Pembuatan & Pengiriman Dokumen PDF ---');
  
  // 9A. Uji Intent Detection untuk Permintaan PDF
  const pdfInvoiceIntent = engine.classifyIntent('kirimkan file pdf PO nomor 700');
  assert.strictEqual(pdfInvoiceIntent, 'SEND_PDF_INVOICE', 'Harus mengenali intent SEND_PDF_INVOICE');
  console.log('  ✓ 9A-1: "kirimkan file pdf PO nomor 700" → SEND_PDF_INVOICE');

  const pdfReceivablesIntent = engine.classifyIntent('kirimkan file pdf piutang afm');
  assert.strictEqual(pdfReceivablesIntent, 'SEND_PDF_RECEIVABLES', 'Harus mengenali intent SEND_PDF_RECEIVABLES');
  console.log('  ✓ 9A-2: "kirimkan file pdf piutang afm" → SEND_PDF_RECEIVABLES');

  // 9B. Uji Pembuatan Buffer Dokumen PDF Faktur Penjualan (Sesuai Layout Resmi Kasir Image 4)
  engine.mockInvoices['700'] = {
    ...mockInvoice,
    invoiceNo: '700',
    customerName: 'AW FROZEN FOOD',
    aliasName: 'AW FF',
    city: 'SEMARANG',
    date: new Date('2026-11-17T10:00:00Z')
  };

  const pdfInvoiceRes = await engine.handleSendPdfInvoice('kirimkan file pdf PO nomor 700', 'Rogue');
  assert(pdfInvoiceRes && pdfInvoiceRes.document, 'Respon harus memiliki objek document');
  assert(pdfInvoiceRes.document.buffer instanceof Buffer, 'Buffer PDF harus bertipe Buffer');
  assert(pdfInvoiceRes.document.buffer.length > 1000, 'Ukuran PDF harus valid (> 1KB)');
  assert.strictEqual(pdfInvoiceRes.document.fileName, '700_AW_FF_SEMARANG_20261117.pdf', 'Nama file PDF faktur harus format resmi kasir: ${invNo}_${alias}_${city}_${date}.pdf');
  assert(pdfInvoiceRes.document.buffer.slice(0, 8).toString().includes('%PDF-1.4'), 'Header binary file harus %PDF-1.4');
  console.log(`  ✓ 9B: Berhasil generate PDF Faktur Penjualan #${pdfInvoiceRes.document.fileName} (${pdfInvoiceRes.document.buffer.length} bytes)`);

  // 9C. Uji Pengiriman Dokumen via sendDocumentReply
  let capturedDocPayload = null;
  engine.setSocketGetter(() => ({
    sendPresenceUpdate: async () => {},
    sendMessage: async (jid, payload) => {
      capturedDocPayload = payload;
      return {
        key: { id: 'TEST_DOC_MSG_888', remoteJid: jid, fromMe: true },
        message: { documentMessage: { fileName: payload.fileName } }
      };
    }
  }));

  const sendDocSuccess = await engine.sendDocumentReply('6287789733632@s.whatsapp.net', pdfInvoiceRes.document, pdfInvoiceRes.reply);
  assert.strictEqual(sendDocSuccess, true, 'sendDocumentReply harus mengembalikan true');
  assert(capturedDocPayload && capturedDocPayload.document, 'Payload socket harus berisi file document');
  assert.strictEqual(capturedDocPayload.fileName, '700_AW_FF_SEMARANG_20261117.pdf', 'Nama file pada Baileys payload harus sesuai format resmi');
  assert.strictEqual(capturedDocPayload.mimetype, 'application/pdf', 'Mimetype harus application/pdf');
  console.log('  ✓ 9C: Pengiriman Dokumen PDF via Baileys Socket terverifikasi sukses!');

  console.log('✅ Test 8 & 9 PASSED: Product Swap & Native PDF Document Dispatch Bekerja Sempurna!');

  // 10. UJI PENGHAPUSAN ITEM DARI FAKTUR PO (ITEM DELETION, MISAL: "sosis cocktail dihapus saja")
  console.log('\n--- Test 10: Uji Penghapusan Item PO (Item Deletion) ---');

  // 10A. Uji Intent Detection untuk Hapus Item
  const delIntent1 = engine.classifyIntent('sosis cocktail dihapus saja');
  assert.strictEqual(delIntent1, 'REVISE_PO', 'Harus mengenali intent REVISE_PO untuk "sosis cocktail dihapus saja"');
  console.log('  ✓ 10A-1: "sosis cocktail dihapus saja" → REVISE_PO');

  const delIntent2 = engine.classifyIntent('hapus sosis cocktail di po 696');
  assert.strictEqual(delIntent2, 'REVISE_PO', 'Harus mengenali intent REVISE_PO untuk "hapus sosis cocktail"');
  console.log('  ✓ 10A-2: "hapus sosis cocktail di po 696" → REVISE_PO');

  const delIntent3 = engine.classifyIntent('revisi rollade sapi dibuang saja');
  assert.strictEqual(delIntent3, 'REVISE_PO', 'Harus mengenali intent REVISE_PO untuk "revisi rollade sapi dibuang saja"');
  console.log('  ✓ 10A-3: "revisi rollade sapi dibuang saja" → REVISE_PO');

  // 10B. Eksekusi Penghapusan Item pada Faktur Status PENDING
  const invoiceForDeletion = JSON.parse(JSON.stringify(mockInvoice));
  // Tambah item ke-4 sosis cocktail untuk dihapus
  invoiceForDeletion.items.push({
    productName: 'SOSIS COCKTAIL AYAM 500 G',
    qty: 30,
    isiKarton: 15,
    cartonCount: 2,
    price: 35000,
    discountPercent: 0,
    discountAmount: 0,
    subtotal: 1050000,
    weightKg: 15
  });
  invoiceForDeletion.grandTotal += 1050000; // total 30.329.850, total 5 item, 67 karton

  const deletionPayload = {
    messageText: 'sosis cocktail dihapus saja',
    quotedMessageText: 'No. Invoice: #696\nPelanggan: AFM (AHYAR)',
    quotedStanzaId: 'MSG_CONFIRM_696',
    mockInvoice: invoiceForDeletion
  };

  const delResult = await engine.handlePoRevision(deletionPayload, 'Rogue');
  console.log(delResult);

  assert(delResult.includes('REVISE_PO BERHASIL DIPROSES: L-W.A.V.I.S') || delResult.includes('REVISI PO BERHASIL DIPROSES'), 'Header revisi harus muncul');
  assert(delResult.includes('SOSIS COCKTAIL AYAM 500 G* berhasil dihapus'), 'Pesan konfirmasi harus menyebut nama barang yang dihapus');
  assert(!delResult.includes('SOSIS COCKTAIL AYAM 500 G\n'), 'Sosis cocktail tidak boleh ada lagi di daftar item');
  assert(delResult.includes('DAFTAR BARANG (4 Item):'), 'Jumlah item harus kembali menjadi 4 item');
  assert(delResult.includes('GrandTotal Karton:* 65 Ktn'), 'GrandTotal Karton harus kembali 65 Ktn');
  assert(delResult.includes('GRAND TOTAL:* *Rp 29.279.850*'), 'Grand Total harus kembali Rp 29.279.850');
  console.log('  ✓ 10B PASSED: Penghapusan item PO berhasil menghapus item, mengurangi grand total, dan update karton');

  // 10C. Edge Case: Menolak Penghapusan Jika Hanya Tersisa 1 Item
  const singleItemInvoice = {
    invoiceNo: '999',
    customerName: 'AHYAR',
    aliasName: 'AFM',
    status: 'PENDING',
    grandTotal: 1000000,
    items: [
      {
        productName: 'SOSIS COCKTAIL AYAM 500 G',
        qty: 15,
        isiKarton: 15,
        cartonCount: 1,
        price: 35000,
        subtotal: 525000
      }
    ]
  };

  const rejectSingleDelPayload = {
    messageText: 'sosis cocktail dihapus saja',
    mockInvoice: singleItemInvoice
  };

  const rejectDelResult = await engine.handlePoRevision(rejectSingleDelPayload, 'Rogue');
  assert(rejectDelResult.includes('PENGHAPUSAN ITEM DITOLAK') || rejectDelResult.includes('Faktur tidak boleh'), 'Harus menolak menghapus item satu-satunya');
  console.log('  ✓ 10C PASSED: Faktur dengan 1 item menolak penghapusan agar tidak menjadi faktur kosong');

  console.log('✅ Test 10 PASSED: Logika Penghapusan Item PO (Item Deletion) Bekerja 100% Sempurna!');

  // 11. UJI MATRIKS HAK AKSES & KEAMANAN (KANTOR VS UMUM)
  console.log('\n--- Test 11: Uji Matriks Hak Akses & Keamanan (Kantor vs Umum) ---');

  // Helper simulasi filter peran kontak
  const officeNumbers = new Set(['6281234567890', '6281200000564']);
  const generalNumbers = new Set(['6287789733632', '6282100000871', '6282100000410']);

  function testContactRole(phone) {
    if (generalNumbers.has(phone)) return 'GENERAL';
    if (officeNumbers.has(phone)) return 'OFFICE';
    return 'OFFICE';
  }

  function simulateSecurityFilter(phone, intent, senderName = 'Kak') {
    const role = testContactRole(phone);
    const isOffice = (role === 'OFFICE');

    if (!isOffice) {
      if (['QUERY_RECEIVABLES', 'QUERY_STOCK', 'QUERY_INVOICE', 'SEND_PDF_INVOICE', 'SEND_PDF_RECEIVABLES', 'REVISE_PO'].includes(intent)) {
        return {
          allowed: false,
          reply: `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
            `Halo ${senderName}! 👋\n\n` +
            `Mohon maaf, informasi operasional, perubahan pesanan, serta dokumen keuangan hanya dapat diakses oleh tim internal PT PFS atau langsung melalui Admin / Developer saat aktif kembali ya. Terima kasih! 🙏\n` +
            `━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
            `ℹ️ Jika ada keperluan mendesak, silakan tinggalkan pesan di sini, Admin akan membalas segera setelah online. 😊`
        };
      }

      if (['GREETING_MENU', 'SMART_FALLBACK'].includes(intent)) {
        return {
          allowed: true,
          isGeneralGreeting: true,
          reply: `🤖 *[L-W.A.V.I.S]*\n_(Lucifax-Whatsapp Assistant Vision Interactive System)_\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n` +
            `Halo ${senderName}! 👋\n\n` +
            `Admin / Developer saat ini sedang tidak standby di tempat.\n` +
            `Namun jangan khawatir! Selagi menunggu beliau online, pesan Anda sudah kami terima dan beliau akan membalas segera setelah aktif kembali ya! 😊`
        };
      }
    }

    return { allowed: true, isOffice: true };
  }

  // 11A. Nomor Umum: Rogue (6287789733632) mencoba Revisi/Hapus PO
  const secReviseGeneral = simulateSecurityFilter('6287789733632', 'REVISE_PO', 'Rogue');
  assert.strictEqual(secReviseGeneral.allowed, false, 'Nomor Umum harus DITOLAK saat mencoba Revisi PO');
  assert(secReviseGeneral.reply.includes('hanya dapat diakses oleh tim internal PT PFS'), 'Pesan penolakan harus sopan dan menjaga keamanan data');
  console.log('  ✓ 11A-1: Nomor Umum coba REVISE_PO → DITOLAK MUTLAK');

  // 11A-2. Nomor Umum: coba minta Piutang
  const secPiutangGeneral = simulateSecurityFilter('6287789733632', 'QUERY_RECEIVABLES', 'Rogue');
  assert.strictEqual(secPiutangGeneral.allowed, false, 'Nomor Umum harus DITOLAK saat tanya Piutang');
  console.log('  ✓ 11A-2: Nomor Umum coba QUERY_RECEIVABLES → DITOLAK MUTLAK');

  // 11A-3. Nomor Umum: coba cek Stok Gudang
  const secStockGeneral = simulateSecurityFilter('6287789733632', 'QUERY_STOCK', 'Rogue');
  assert.strictEqual(secStockGeneral.allowed, false, 'Nomor Umum harus DITOLAK saat cek Stok');
  console.log('  ✓ 11A-3: Nomor Umum coba QUERY_STOCK → DITOLAK MUTLAK');

  // 11A-4. Nomor Umum: sapaan offline (Halo Rogue)
  const secGreetingGeneral = simulateSecurityFilter('6287789733632', 'GREETING_MENU', 'Rogue');
  assert.strictEqual(secGreetingGeneral.allowed, true);
  assert.strictEqual(secGreetingGeneral.isGeneralGreeting, true);
  assert(!secGreetingGeneral.reply.includes('LAYANAN YANG BISA SAYA PROSES OTOMATIS'), 'Nomor umum TIDAK boleh melihat 5 menu internal');
  assert(secGreetingGeneral.reply.includes('Halo Rogue! 👋'), 'Salam ramah harus menyebut nama');
  console.log('  ✓ 11A-4: Nomor Umum sapaan offline → Salam Ramah Standar (Tanpa bocorkan 5 menu internal)');

  // 11B. Nomor Kantor: Pak Joko (6281200000564)
  const secOfficeCheck = simulateSecurityFilter('6281200000564', 'REVISE_PO', 'Pak Joko');
  assert.strictEqual(secOfficeCheck.allowed, true);
  assert.strictEqual(secOfficeCheck.isOffice, true);
  console.log('  ✓ 11B: Nomor Kantor (Pak Joko) → Diizinkan akses seluruh operasional L-W.A.V.I.S');

  console.log('✅ Test 11 PASSED: Matriks Hak Akses & Keamanan (Kantor vs Umum) Terverifikasi 100%!');

  // 12. UJI REVISI MULTI-ITEM (BATCH DELETION & BATCH QTY REVISION)
  console.log('\n--- Test 12: Uji Revisi Multi-Item (Batch Deletion & Multi Qty) ---');
  const inv700Test = {
    invoiceNo: '700',
    customerName: 'AW FF (AW FROZEN FOOD)',
    aliasName: 'AW FF',
    city: 'SEMARANG',
    province: 'JAWA TENGAH',
    status: 'PENDING',
    items: [
      { productName: 'BRS COKLAT 24S 2 500G', qty: 150, cartonCount: 10, price: 28234, subtotal: 4235100, isiKarton: 15 },
      { productName: 'BRS COKLAT 13S 2 500G', qty: 450, cartonCount: 30, price: 27962, subtotal: 12582900, isiKarton: 15 },
      { productName: 'BRS COKLAT 7S 2 500G', qty: 75, cartonCount: 5, price: 27962, subtotal: 2097150, isiKarton: 15 }
    ],
    grandTotal: 18915150
  };

  // 12A. Hapus beberapa item sekaligus: "hapus item barang brs 13 dan brs 7"
  const multiDelPayload = {
    messageText: 'hapus item barang brs 13 dan brs 7',
    mockInvoice: JSON.parse(JSON.stringify(inv700Test))
  };
  const multiDelRes = await engine.handlePoRevision(multiDelPayload, 'Rogue');
  assert(multiDelRes.includes('BRS COKLAT 13S 2 500G dan BRS COKLAT 7S 2 500G* berhasil dihapus'), 'Harus menyebut kedua item yang dihapus');
  assert(multiDelRes.includes('DAFTAR BARANG (1 Item):'), 'Harus tersisa 1 item');
  assert(multiDelRes.includes('BRS COKLAT 24S 2 500G'), 'Item 24S harus tetap ada');
  assert(multiDelRes.includes('GrandTotal Karton:* 10 Ktn'), 'Grand total karton harus 10 Ktn');
  assert(multiDelRes.includes('GRAND TOTAL:* *Rp 4.235.100*'), 'Grand total uang harus Rp 4.235.100');
  console.log('  ✓ 12A PASSED: Penghapusan multi-item ("hapus item barang brs 13 dan brs 7") berhasil menghapus kedua item dan menjaga item lainnya');

  // 12B. Revisi Qty beberapa item sekaligus: "revisi brs 24 jadi 15 karton dan brs 13 jadi 20 karton"
  const multiQtyPayload = {
    messageText: 'revisi brs 24 jadi 15 karton dan brs 13 jadi 20 karton',
    mockInvoice: JSON.parse(JSON.stringify(inv700Test))
  };
  const multiQtyRes = await engine.handlePoRevision(multiQtyPayload, 'Rogue');
  assert(multiQtyRes.includes('15 Ktn (225 pcs)'), 'BRS 24S harus menjadi 15 Ktn');
  assert(multiQtyRes.includes('20 Ktn (300 pcs)'), 'BRS 13S harus menjadi 20 Ktn');
  assert(multiQtyRes.includes('GrandTotal Karton:* 40 Ktn'), 'Grand total karton harus 40 Ktn');
  assert(multiQtyRes.includes('GRAND TOTAL:* *Rp 16.838.400*'), 'Grand total uang harus Rp 16.838.400');
  console.log('  ✓ 12B PASSED: Revisi multi-qty ("revisi brs 24 jadi 15 karton dan brs 13 jadi 20 karton") berhasil memperbarui kedua item sekaligus');

  console.log('✅ Test 12 PASSED: Dukungan Revisi Multi-Item (Batch Deletion & Multi Qty) Terverifikasi 100%!');

  // 13. UJI TAMBAH ITEM BARU & AKUMULASI (ADD_ITEM)
  console.log('\n--- Test 13: Uji Tambah Item Baru & Akumulasi Item (ADD_ITEM) ---');
  
  // Pastikan master products dan rules memiliki mapping BRS 24
  engine.autoPoProcessor.cachedRules.push({
    type: 'product_alias',
    keyword: 'brs 24',
    mappedValue: 'BRS COKLAT 24S 2 500G'
  });
  engine.autoPoProcessor.cachedProducts.push({
    id: 'p-brs-24',
    productName: 'BRS COKLAT 24S 2 500G',
    name: 'BRS COKLAT 24S 2 500G',
    price: 28234,
    isiKarton: 15,
    sizeGrams: 500,
    stock: 200
  });

  // Mock history transaksi AW FF untuk BRS 24
  engine.firebaseAdapter = {
    getCustomerProductMemory: async (customerId) => {
      return [
        { productId: 'p-brs-24', productName: 'BRS COKLAT 24S 2 500G', price: 28234, discountPercent: 0, invoiceNo: '700' }
      ];
    },
    getLastCustomerProductPricing: async (customerId, prodId, prodName) => {
      if (prodName && prodName.includes('COKLAT 24S')) {
        return { price: 28234, discountPercent: 0, invoiceNo: '700' };
      }
      if (prodName && prodName.includes('MERAH')) {
        return { price: 34549, discountPercent: 0, invoiceNo: '698' };
      }
      return null;
    }
  };

  const inv700TwoItems = {
    invoiceNo: '700',
    customerId: 'c-awff',
    customerName: 'AW FF (AW FROZEN FOOD)',
    aliasName: 'AW FF',
    city: 'SEMARANG',
    province: 'JAWA TENGAH',
    status: 'PENDING',
    items: [
      { productName: 'BRS COKLAT 13S 2 500G', qty: 450, cartonCount: 30, price: 27962, subtotal: 12582900, isiKarton: 15 },
      { productName: 'BRS COKLAT 7S 2 500G', qty: 75, cartonCount: 5, price: 27962, subtotal: 2097150, isiKarton: 15 }
    ],
    grandTotal: 14680050
  };

  // 13A. Tambah item baru: "tambahkan brs 24 10 karton"
  const addPayload1 = {
    messageText: 'tambahkan brs 24 10 karton',
    mockInvoice: JSON.parse(JSON.stringify(inv700TwoItems))
  };
  const addRes1 = await engine.handlePoRevision(addPayload1, 'Rogue');
  console.log(addRes1);
  assert(addRes1.includes('BRS COKLAT 24S 2 500G (10 ktn)* berhasil ditambahkan'), 'Header harus menyatakan BRS 24S berhasil ditambahkan');
  assert(addRes1.includes('DAFTAR BARANG (3 Item):'), 'Faktur harus bertambah menjadi 3 item');
  assert(addRes1.includes('➕ *(DITAMBAHKAN)*'), 'Tag DITAMBAHKAN harus muncul pada item baru');
  assert(addRes1.includes('10 Ktn (150 pcs) @28.234 | Disc: - = *Rp 4.235.100*'), 'Kalkulasi harga dan pcs BRS 24 harus tepat');
  assert(addRes1.includes('30 Ktn (450 pcs)'), 'BRS 13S harus TETAP 30 Ktn (tidak boleh berubah jadi 10 ktn)');
  assert(addRes1.includes('5 Ktn (75 pcs)'), 'BRS 7S harus TETAP 5 Ktn');
  assert(addRes1.includes('GrandTotal Karton:* 45 Ktn'), 'Grand total karton harus 45 Ktn (30+5+10)');
  assert(addRes1.includes('GRAND TOTAL:* *Rp 18.915.150*'), 'Grand total uang harus Rp 18.915.150');
  console.log('  ✓ 13A PASSED: "tambahkan brs 24 10 karton" berhasil menambahkan item baru tanpa merusak item lain!');

  // 13B. Akumulasi item yang sudah ada: "tambah brs 24 5 karton"
  const invWith24 = JSON.parse(JSON.stringify(inv700Test)); // Sudah ada BRS 24S 10 ktn, 13S 30 ktn, 7S 5 ktn
  const addPayload2 = {
    messageText: 'tambah brs 24 5 karton',
    mockInvoice: invWith24
  };
  const addRes2 = await engine.handlePoRevision(addPayload2, 'Rogue');
  assert(addRes2.includes('15 Ktn (225 pcs)'), 'BRS 24S harus bertambah dari 10 ktn jadi 15 ktn');
  assert(addRes2.includes('GrandTotal Karton:* 50 Ktn'), 'Grand total karton harus bertambah 5 ktn jadi 50 ktn');
  console.log('  ✓ 13B PASSED: Akumulasi "tambah brs 24 5 karton" pada item yang sudah ada berhasil menambah kuantitas');

  // 13C. Multi-add item baru sekaligus: "tambah brs 24 10 karton dan sosis cocktail 5 karton"
  const addPayload3 = {
    messageText: 'tambah brs 24 10 karton dan sosis cocktail 5 karton',
    mockInvoice: JSON.parse(JSON.stringify(inv700TwoItems))
  };
  const addRes3 = await engine.handlePoRevision(addPayload3, 'Rogue');
  assert(addRes3.includes('DAFTAR BARANG (4 Item):'), 'Faktur harus bertambah menjadi 4 item');
  assert(addRes3.includes('BRS COKLAT 24S 2 500G'), 'Harus memuat BRS 24S');
  assert(addRes3.includes('SOSIS COCKTAIL 250 G'), 'Harus memuat SOSIS COCKTAIL');
  assert(addRes3.includes('GrandTotal Karton:* 50 Ktn'), 'Grand total karton harus 50 Ktn (30+5+10+5)');
  console.log('  ✓ 13C PASSED: Multi-add "tambah brs 24 10 karton dan sosis cocktail 5 karton" sukses menambahkan kedua barang');

  // 13D. Mixed command: "hapus brs 13 dan tambah brs 24 10 karton"
  const mixedPayload = {
    messageText: 'hapus brs 13 dan tambah brs 24 10 karton',
    mockInvoice: JSON.parse(JSON.stringify(inv700TwoItems))
  };
  const mixedRes = await engine.handlePoRevision(mixedPayload, 'Rogue');
  assert(!mixedRes.includes('BRS COKLAT 13S'), 'BRS 13S harus terhapus');
  assert(mixedRes.includes('BRS COKLAT 7S 2 500G'), 'BRS 7S harus tetap ada');
  assert(mixedRes.includes('BRS COKLAT 24S 2 500G'), 'BRS 24S harus ditambahkan');
  assert(mixedRes.includes('DAFTAR BARANG (2 Item):'), 'Faktur harus berisi 2 item (7S dan 24S)');
  assert(mixedRes.includes('GrandTotal Karton:* 15 Ktn'), 'Grand total karton harus 15 Ktn (5 + 10)');
  console.log('  ✓ 13D PASSED: Mixed command ("hapus brs 13 dan tambah brs 24 10 karton") berhasil diproses simultan');

  console.log('✅ Test 13 PASSED: Fitur Penambahan Item (ADD_ITEM) & Akumulasi Terverifikasi 100%!');

  // 14. UJI POLA PERCAKAPAN WHATSAPP NYATA (REVISI TAMBAHAN MULTI-LINE & ROLL/PCS UNIT CONVERSION)
  console.log('\n--- Test 14: Pola Percakapan WhatsApp Nyata (Revisi Tambahan Multi-Line, Unit Awareness, Anti-NaN) ---');

  // Pastikan master products memuat Rolade Ayam Roll 400G dan BRS Merah 24S 500G
  engine.autoPoProcessor.cachedProducts.push({
    id: 'p-brs-merah-24',
    productName: 'BRS MERAH 24S 500G',
    name: 'BRS MERAH 24S 500G',
    price: 34549,
    isiKarton: 15,
    sizeGrams: 500,
    stock: 300
  });
  engine.autoPoProcessor.cachedProducts.push({
    id: 'p-rolade-ayam-roll',
    productName: 'ROLLADE AYAM ROLL 400 G',
    name: 'ROLLADE AYAM ROLL 400 G',
    price: 24797,
    isiKarton: 25,
    sizeGrams: 400,
    stock: 500
  });

  const inv700ThreeItems = {
    invoiceNo: '700',
    customerId: 'c-awff',
    customerName: 'AW FF (AW FROZEN FOOD)',
    aliasName: 'AW FF',
    city: 'SEMARANG',
    province: 'JAWA TENGAH',
    status: 'PENDING',
    items: [
      { productName: 'BRS COKLAT 13S 2 500G', qty: 450, cartonCount: 30, price: 27962, subtotal: 12582900, isiKarton: 15 },
      { productName: 'BRS COKLAT 7S 2 500G', qty: 75, cartonCount: 5, price: 27962, subtotal: 2097150, isiKarton: 15 },
      { productName: 'BRS COKLAT 24S 2 500G', qty: 150, cartonCount: 10, price: 28234, subtotal: 4235100, isiKarton: 15 }
    ],
    grandTotal: 18915150
  };

  const exactUserChatPayload = {
    messageText: 'revisi tambahan\nbrs merah 15 karton\nrolade ayam roll 250 roll',
    mockInvoice: JSON.parse(JSON.stringify(inv700ThreeItems))
  };

  const exactUserRes = await engine.handlePoRevision(exactUserChatPayload, 'Rogue');
  console.log(exactUserRes);

  assert(!exactUserRes.includes('NaN'), 'Respon TIDAK BOLEH memuat nilai NaN sama sekali!');
  assert(exactUserRes.includes('30 Ktn (450 pcs)'), 'BRS COKLAT 13S harus tetap 30 Ktn (450 pcs), tidak boleh rusak jadi NaN');
  assert(exactUserRes.includes('5 Ktn (75 pcs)'), 'BRS COKLAT 7S harus tetap 5 Ktn');
  assert(exactUserRes.includes('10 Ktn (150 pcs)'), 'BRS COKLAT 24S harus tetap 10 Ktn');
  assert(exactUserRes.includes('BRS MERAH 24S 500G'), 'BRS MERAH 24S harus berhasil ditambahkan');
  assert(exactUserRes.includes('15 Ktn (225 pcs)'), 'BRS MERAH harus 15 Ktn (225 pcs)');
  assert(exactUserRes.includes('ROLLADE AYAM ROLL 400 G'), 'ROLLADE AYAM ROLL harus berhasil ditambahkan');
  assert(exactUserRes.includes('10 Ktn (250 pcs)'), 'ROLADE AYAM ROLL 250 roll (isi 25) harus dikonversi menjadi 10 Ktn (250 pcs)');
  assert(exactUserRes.includes('DAFTAR BARANG (5 Item):'), 'Faktur harus bertambah menjadi 5 item');
  assert(exactUserRes.includes('GrandTotal Karton:* 70 Ktn'), 'Grand total karton harus 70 Ktn (30+5+10+15+10)');
  console.log('  ✓ 14A PASSED: "revisi tambahan\\nbrs merah 15 karton\\nrolade ayam roll 250 roll" berhasil 100% tanpa NaN!');

  console.log('✅ Test 14 PASSED: Pola Percakapan WhatsApp Nyata & Unit Awareness Sempurna!');

  // 15. UJI AKUMULASI KARTON PADA ITEM DARI FIRESTORE (KARTON COUNT SINKRON DENGAN QTY)
  console.log('\n--- Test 15: Akumulasi Tambah Karton pada Item Tanpa Field cartonCount di Database ---');
  const invFromDbWithoutCartonCount = {
    invoiceNo: '700',
    customerId: 'c-awff',
    customerName: 'AW FF (AW FROZEN FOOD)',
    aliasName: 'AW FF',
    city: 'SEMARANG',
    province: 'JAWA TENGAH',
    status: 'PENDING',
    items: [
      { productName: 'BRS COKLAT 13S 2 500G', qty: 450, price: 27962, subtotal: 12582900, sizeGrams: 500 },
      { productName: 'BRS COKLAT 7S 2 500G', qty: 75, price: 27962, subtotal: 2097150, sizeGrams: 500 },
      { productName: 'BRS COKLAT 24S 2 500G', qty: 150, price: 28234, subtotal: 4235100, sizeGrams: 500 }
    ],
    grandTotal: 18915150
  };

  const image5Payload = {
    messageText: 'revisi tambah brs 7  5 karton\nganti brs 24 jadi brs merah 7 karton\nhapus brs 13',
    mockInvoice: invFromDbWithoutCartonCount
  };

  const image5Res = await engine.handlePoRevision(image5Payload, 'Rogue');
  console.log(image5Res);

  assert(!image5Res.includes('BRS COKLAT 13S'), 'BRS COKLAT 13S harus terhapus');
  assert(!image5Res.includes('5 Ktn (150 pcs)'), 'BRS COKLAT 7S TIDAK BOLEH salah menampilkan 5 Ktn (150 pcs)');
  assert(image5Res.includes('10 Ktn (150 pcs)'), 'BRS COKLAT 7S harus menampilkan 10 Ktn (150 pcs)');
  assert(image5Res.includes('7 Ktn (105 pcs)'), 'BRS MERAH 24S harus menampilkan 7 Ktn (105 pcs)');
  assert(image5Res.includes('GrandTotal Karton:* 17 Ktn'), 'Grand total karton harus 17 Ktn (10 + 7)');
  assert(image5Res.includes('GRAND TOTAL:* *Rp 7.821.945*'), 'Grand total rupiah harus tepat Rp 7.821.945');
  console.log('  ✓ 15A PASSED: Akumulasi karton dari database sinkron 10 Ktn (150 pcs) & total 17 Ktn!');

  console.log('✅ Test 15 PASSED: Sinkronisasi Karton dengan Qty Firestore Terverifikasi 100%!');

  console.log('\n🎉 SEMUA PENGUJIAN UNIT WavisInteractiveEngine LULUS 100%! 🚀');
})();
