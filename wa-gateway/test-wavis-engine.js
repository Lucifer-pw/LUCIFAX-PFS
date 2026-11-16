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
const intentTests = [
  { text: 'piutang AFM', expected: 'QUERY_RECEIVABLES' },
  { text: 'utang e afm piro mas?', expected: 'QUERY_RECEIVABLES' },
  { text: 'cek bon maju market', expected: 'QUERY_RECEIVABLES' },
  { text: 'sisa tagihan griya ff', expected: 'QUERY_RECEIVABLES' },
  { text: 'stok bratwurst ori ready ga?', expected: 'QUERY_STOCK' },
  { text: 'stock rolade sapi sisa berapa', expected: 'QUERY_STOCK' },
  { text: 'ready beres merah 24', expected: 'QUERY_STOCK' },
  { text: 'halo mas', expected: 'GREETING_MENU' },
  { text: 'pagi admin', expected: 'GREETING_MENU' },
  { text: 'assalamualaikum wavis', expected: 'GREETING_MENU' },
  { text: 'tadi saya lihat ada kucing di gudang', expected: 'UNKNOWN' }
];

intentTests.forEach(({ text, expected }) => {
  const actual = engine.classifyIntent(text);
  assert.strictEqual(actual, expected, `Intent untuk "${text}" harus "${expected}", tapi didapat "${actual}"`);
  console.log(`  ✓ "${text}" → [${actual}]`);
});
console.log('✅ Test 2 PASSED: Klasifikasi Intent 100% Akurat!');

// 3. UJI CUSTOMER & PRODUCT MATCHER
console.log('\n--- Test 3: Customer & Product Matcher ---');
const mockCustomers = [
  { id: 'c1', customerName: 'AHYAR', aliasName: 'AFM' },
  { id: 'c2', customerName: 'MAJU MARKET MANDIRI', aliasName: 'MMM' },
  { id: 'c3', customerName: 'GRIYA FROZEN FOOD', aliasName: 'GRIYA FF' },
  { id: 'H002', customerName: 'AW FROZEN FOOD', aliasName: 'AW FF' }
];

const mockProducts = [
  { id: 'p1', productName: 'BRS COKLAT 24S 500 G', price: 30688, isiKarton: 15, stock: 675 },
  { id: 'p2', productName: 'BRATWURST SAPI MINI 500 G', price: 45838, isiKarton: 15, stock: 1200 },
  { id: 'p3', productName: 'ROLLADE SAPI 215 G', price: 17500, isiKarton: 30, stock: 900 }
];

const custMatch = engine.matchCustomerFromQuery('tolong cek sisa utang afm mas', mockCustomers);
assert(custMatch && custMatch.aliasName === 'AFM', 'Harus cocok dengan AFM');
console.log(`  ✓ Cocok Pelanggan: "${custMatch.aliasName} (${custMatch.customerName})"`);

const custMatchAw = engine.matchCustomerFromQuery('saya ingin cek kartu piutang nya AW', mockCustomers);
assert(custMatchAw && custMatchAw.aliasName === 'AW FF', 'Harus cocok dengan AW FF');
console.log(`  ✓ Cocok Pelanggan: "${custMatchAw.aliasName} (${custMatchAw.customerName})"`);

const custMatchAw2 = engine.matchCustomerFromQuery('piutang AW FF', mockCustomers);
assert(custMatchAw2 && custMatchAw2.aliasName === 'AW FF', 'Harus cocok dengan AW FF');
console.log(`  ✓ Cocok Pelanggan: "${custMatchAw2.aliasName} (${custMatchAw2.customerName})"`);

const prodMatch = engine.matchProductFromQuery('stok bratwurst mini sisa berapa', mockProducts);
assert(prodMatch && prodMatch.productName.includes('BRATWURST SAPI MINI'), 'Harus cocok dengan Bratwurst Mini');
console.log(`  ✓ Cocok Produk: "${prodMatch.productName}"`);
console.log('✅ Test 3 PASSED: Matching Pelanggan & Produk Sempurna!');

// 4. UJI GREETING MENU
console.log('\n--- Test 4: Menu Bantuan L-W.A.V.I.S ---');
const greeting = engine.handleGreetingMenu('Pak Joko');
assert(greeting.includes('Halo Pak Joko!'), 'Harus menyapa Pak Joko');
assert(greeting.includes('1. Buat Pesanan Baru (PO)'), 'Menu 1 PO harus ada');
assert(greeting.includes('2. Cek Piutang Toko'), 'Menu 2 Piutang harus ada');
assert(greeting.includes('3. Cek Stok Barang Gudang'), 'Menu 3 Stok harus ada');
console.log(greeting);
console.log('✅ Test 4 PASSED: Menu Bantuan L-W.A.V.I.S Sempurna!');

console.log('\n🎉 SEMUA PENGUJIAN UNIT WavisInteractiveEngine LULUS 100%! 🚀');
