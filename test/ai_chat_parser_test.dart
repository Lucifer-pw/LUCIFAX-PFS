import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_app/services/ai_chat_parser_service.dart';
import 'package:cashier_app/models/product.dart';
import 'package:cashier_app/models/customer.dart';
import 'package:cashier_app/models/customer_product_history.dart';
import 'package:cashier_app/models/ai_knowledge_rule.dart';
import 'package:cashier_app/models/transaction.dart';

void main() {
  test('AI Parser matches Fiva beres sapi 24 to BRS COKLAT 24S 500 G', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS MERAH 24S 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'BRS COKLAT 24S 500 G', price: 37000, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P04', name: 'BRS COKLAT 13S 500 G', price: 37000, stock: 100, isiKarton: 13, sizeGrams: 500),
      Product(id: 'P05', name: 'BRS COKLAT 7S 500 G', price: 37000, stock: 100, isiKarton: 7, sizeGrams: 500),
    ];

    final customers = [
      Customer(
        id: '0002',
        customerName: 'MAJU MARKET MANDIRI',
        aliasName: 'MMM',
        address: 'Pekalongan',
        city: 'PEKALONGAN',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08123456789',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'MMM', mappedValue: 'MAJU MARKET MANDIRI', targetId: '0002', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'Beres sapi 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Beres sapi 13', mappedValue: 'BRS COKLAT 13S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
    ];

    final chatText = '''
MMM
1. Fiva beres sosis merah 500gr 5k
5. Fiva beres sapi 500gr isi 13 10k
6. Fiva beres sapi 500gr isi 24 3k
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, '0002');
    expect(draft.customerName, 'MAJU MARKET MANDIRI');
    expect(draft.items.length, 3);

    // Item 1: BRS MERAH 24 500G
    expect(draft.items[0].productName, 'BRS MERAH 24 500G');
    expect(draft.items[0].qtyInput, 5.0);

    // Item 2: BRS COKLAT 13S 500 G
    expect(draft.items[1].productName, 'BRS COKLAT 13S 500 G');
    expect(draft.items[1].qtyInput, 10.0);

    // Item 3: BRS COKLAT 24S 500 G (MUST BE COKLAT 24S, NOT MERAH 24)
    expect(draft.items[2].productName, 'BRS COKLAT 24S 500 G');
    expect(draft.items[2].qtyInput, 3.0);
  });

  test('Customer history matches Beres Sapi to BRS COKLAT 24S even when customer history has BRS MERAH 24', () {
    final parser = AiChatParserService();
    // Test the internal matching method directly with history list
    final history = <CustomerProductHistory>[
      CustomerProductHistory(
        productId: 'P01',
        productName: 'BRS MERAH 24 500G',
        price: 36691,
        discountPercent: 0.0,
        discountAmount: 0.0,
        purchaseCount: 10,
        invoiceNo: 'INV-001',
      ),
      CustomerProductHistory(
        productId: 'P03',
        productName: 'BRS COKLAT 24S 500 G',
        price: 37000,
        discountPercent: 0.0,
        discountAmount: 0.0,
        purchaseCount: 5,
        invoiceNo: 'INV-002',
      ),
    ];

    // beres sosis merah 500gr -> BRS MERAH 24 500G
    final matchMerah = parser.testMatchCustomerHistory('beres sosis merah 500gr', history);
    expect(matchMerah?.productName, 'BRS MERAH 24 500G');

    // beres sapi 500gr isi 24 -> BRS COKLAT 24S 500 G
    final matchSapi = parser.testMatchCustomerHistory('beres sapi 500gr isi 24', history);
    expect(matchSapi?.productName, 'BRS COKLAT 24S 500 G');
  });

  test('Customer history prefers most recent invoice (#673 with 15%) over older high-frequency invoice (#516 with 12.5%)', () {
    final parser = AiChatParserService();
    final now = DateTime.now();

    final history = <CustomerProductHistory>[
      // Newer invoice (#673) with 15% discount, but lower purchase count (3)
      CustomerProductHistory(
        productId: 'KAL-400',
        productName: 'KORNET AYAM LOYANG 400 G',
        price: 19363,
        discountPercent: 15.0,
        discountAmount: 0.0,
        purchaseCount: 3,
        invoiceNo: '673',
        date: now.subtract(const Duration(days: 6)),
      ),
      // Older invoice (#516) with 12.5% discount, but high historical purchase count (21)
      CustomerProductHistory(
        productId: 'KORNET AYAM LOYANG 400 G',
        productName: 'KORNET AYAM LOYANG 400 G',
        price: 19363,
        discountPercent: 12.5,
        discountAmount: 0.0,
        purchaseCount: 21,
        invoiceNo: '516',
        date: now.subtract(const Duration(days: 120)),
      ),
    ];

    final matched = parser.testMatchCustomerHistory('Kornet ayam loyang', history);
    expect(matched, isNotNull);
    expect(matched!.invoiceNo, '673');
    expect(matched.discountPercent, 15.0);
  });

  test('Debug user chat with ANIZA FF KENDAL', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS MERAH 24S 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'BRS COKLAT 24S 500 G', price: 37000, stock: 100, isiKarton: 24, sizeGrams: 500),
    ];

    final customers = [
      Customer(id: 'AA001', customerName: 'BAMBANG EKO RATIYATNO', aliasName: 'KK FF', address: '', city: 'WONOSOBO', province: '', country: '', phone: '', ktpNumber: ''),
      Customer(id: 'AA002', customerName: 'WIMBO WIEK KUSTANTO', aliasName: 'LG FF', address: '', city: 'WONOSOBO', province: '', country: '', phone: '', ktpNumber: ''),
      Customer(id: 'H003', customerName: 'ANNISA UL HAKIM', aliasName: 'NIZA', address: '', city: 'KENDAL', province: '', country: '', phone: '', ktpNumber: ''),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'LG FF', mappedValue: 'LG FF (WIMBO WIEK KUSTANTO)', targetId: 'AA002', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'customer_alias', keyword: 'KK FF', mappedValue: 'KK FF WONOSOBO', targetId: 'AA001', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'customer_alias', keyword: 'ANIZA FF KENDAL', mappedValue: 'ANNISA UL HAKIM', targetId: 'H003', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r5', type: 'product_alias', keyword: 'Beres coklat 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
    ];

    final chatText = '''
Waalaikumsalam
Po ANIZA FF KENDAL
Beres merah 24 : 1
Beres coklat 24 : 2
KRM HR KAMIS
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'H003');
    expect(draft.customerName, 'ANNISA UL HAKIM');
    expect(draft.items.length, 2);
    expect(draft.items[0].productName, 'BRS MERAH 24 500G');
    expect(draft.items[0].qtyInput, 1.0);
    expect(draft.items[1].productName, 'BRS COKLAT 24S 500 G');
    expect(draft.items[1].qtyInput, 2.0);
  });

  test('LG FF bonus rule auto-appends 1 karton Kornet Ayam Loyang 400 G when ordering 40 karton', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P10', name: 'KORNET AYAM LOYANG 400 G', price: 19363, stock: 100, isiKarton: 20, sizeGrams: 400),
      Product(id: 'P11', name: 'ROLADE SAPI ROLL 325 G', price: 15000, stock: 100, isiKarton: 20, sizeGrams: 325),
    ];

    final customers = [
      Customer(
        id: 'AA002',
        customerName: 'WIMBO WIEK KUSTANTO',
        aliasName: 'LG FF',
        address: 'Wonosobo',
        city: 'WONOSOBO',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08123456789',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(
        id: 'c1',
        type: 'customer_alias',
        keyword: 'LG FF',
        mappedValue: 'LG FF (WIMBO WIEK KUSTANTO)',
        targetId: 'AA002',
        createdAt: DateTime.now(),
      ),
      AiKnowledgeRule(
        id: 'b1',
        type: 'bonus_rule',
        keyword: 'LG FF|KORNET AYAM LOYANG 400 G|40',
        mappedValue: 'KORNET AYAM LOYANG 400 G|1|karton',
        createdAt: DateTime.now(),
      ),
    ];

    final chatText = '''
LG FF WONOSOBO
KORNET AYAM LOYANG 40 K....
ROLADE SAPI ROLL 325 ROLL...
KRM BSK HR KAMIS
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'AA002');
    expect(draft.customerName, 'WIMBO WIEK KUSTANTO');
    expect(draft.aliasName, 'LG FF');

    // Should have 3 items: Kornet 40k, Rolade, and the Auto Bonus
    expect(draft.items.length, 3);

    // Regular item
    expect(draft.items[0].productName, 'KORNET AYAM LOYANG 400 G');
    expect(draft.items[0].qtyInput, 40.0);
    expect(draft.items[0].qtyUnit, 'karton');
    expect(draft.items[0].isBonus, isFalse);

    // Bonus item
    final bonusItem = draft.items.firstWhere((it) => it.isBonus);
    expect(bonusItem.productName, contains('KORNET AYAM LOYANG 400 G'));
    expect(bonusItem.qtyInput, 1.0);
    expect(bonusItem.qtyUnit, 'karton');
    expect(bonusItem.price, 0.0);

    // Note
    expect(draft.note, 'NOTE : BONUS 1 KARTON KORNET AYAM @400 G');
  });

  test('LG FF bonus rule scales note for multiples (80 karton -> NOTE : BONUS 2 KARTON...)', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'KORNET AYAM LOYANG 400 G', price: 20000, stock: 100, isiKarton: 20, sizeGrams: 400),
    ];
    final customers = [
      Customer(id: 'AA002', customerName: 'WIMBO WIEK KUSTANTO', aliasName: 'LG FF', address: '', city: 'SEMARANG', province: 'JAWA TENGAH', country: 'INDONESIA', phone: '', ktpNumber: ''),
    ];
    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'bonus_rule', keyword: 'LG FF|KORNET AYAM LOYANG 400 G|40', mappedValue: 'KORNET AYAM LOYANG 400 G|1|karton', createdAt: DateTime.now()),
    ];

    final chatText = '''
LG FF
1. Kornet ayam loyang : 80 k
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.note, 'NOTE : BONUS 2 KARTON KORNET AYAM @400 G');
  });

  test('Normal order (e.g. Berkah tempura with instruction "Krm hr kamis") keeps note strictly empty', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
    ];
    final customers = [
      Customer(id: 'C001', customerName: 'ANDI SUSANTO', aliasName: 'BERKAH TEMPURA', address: '', city: 'KARANGANYAR', province: 'JAWA TENGAH', country: 'INDONESIA', phone: '', ktpNumber: ''),
    ];

    final chatText = '''
Berkah tempura
Beres merah 5 k
Krm hr kamis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: [],
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerName, 'ANDI SUSANTO');
    expect(draft.items.length, 1);
    expect(draft.note, isEmpty);
  });

  test('Unregistered new store LUCIFAX FF Surakarta parses correctly with city Surakarta and empty customerId', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS COKLAT 24S 500 G', price: 37000, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'ROLADE SAPI 1000 G', price: 42000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P04', name: 'ROLADE AYAM ROLL 325 G', price: 14000, stock: 100, isiKarton: 25, sizeGrams: 325),
      Product(id: 'P05', name: 'ROLADE SAPI ROLL 325 G', price: 15000, stock: 100, isiKarton: 25, sizeGrams: 325),
    ];

    final customers = <Customer>[];
    final rules = <AiKnowledgeRule>[];

    final chatText = '''
LUCIFAX FF Surakarta
Fiva beres merah isi 24 = 30 karton
Fiva rolade 1 kg =35 karton
Fiva beres coklat isi 24 = 5 karton
Fiva rolade roll ayam = 2 ball....50 ROLL
Fiva rolade roll sapi = 2 ball....50 ROLL
Krm bsk pg
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, '');
    expect(draft.customerName, 'LUCIFAX FF Surakarta');
    expect(draft.city, 'SURAKARTA');
    expect(draft.items.length, 5);

    expect(draft.items[0].productName, 'BRS MERAH 24 500G');
    expect(draft.items[0].qtyInput, 30.0);
    expect(draft.items[0].qtyUnit, 'karton');

    expect(draft.items[1].productName, 'ROLADE SAPI 1000 G');
    expect(draft.items[1].qtyInput, 35.0);
    expect(draft.items[1].qtyUnit, 'karton');

    expect(draft.items[2].productName, 'BRS COKLAT 24S 500 G');
    expect(draft.items[2].qtyInput, 5.0);
    expect(draft.items[2].qtyUnit, 'karton');

    expect(draft.items[3].productName, 'ROLADE AYAM ROLL 325 G');
    expect(draft.items[3].qtyInput, 50.0);
    expect(draft.items[3].qtyUnit, 'roll');

    expect(draft.items[4].productName, 'ROLADE SAPI ROLL 325 G');
    expect(draft.items[4].qtyInput, 50.0);
    expect(draft.items[4].qtyUnit, 'roll');

    // Unregistered new store must have 0% discount, 0 discountAmount, and empty invoiceNo
    for (var item in draft.items) {
      expect(item.discountPercent, 0.0);
      expect(item.discountAmount, 0.0);
      expect(item.invoiceNo, '');
      expect(item.isNewItemForCustomer, true);
    }
  });

  test('New store LUCIFAX FF BLORA accurately detects city BLORA', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
    ];

    final chatText = '''
LUCIFAX FF BLORA
Fiva beres merah isi 24 = 30 karton
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: [],
      rules: [],
    );

    expect(drafts.length, 1);
    expect(drafts.first.customerRawName, 'LUCIFAX FF BLORA');
    expect(drafts.first.city, 'BLORA');
  });

  test('Customer MISTER SOSIS with alias matches SUSILO HARYAWAN [K001] and respects Kamus AI rules over ROLL 400 G', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 45000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P02', name: 'ROLLADE SAPI 1000 G ( MBG )', price: 46000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P03', name: 'ROLLADE SAPI ROLL 400 G', price: 26194, stock: 100, isiKarton: 50, sizeGrams: 400),
    ];

    final customers = [
      Customer(
        id: 'K001',
        customerName: 'SUSILO HARYAWAN',
        aliasName: 'MISTER SOSIS',
        address: 'Blora',
        city: 'BLORA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'product_alias', keyword: 'ROLADE SAPI ROLL', mappedValue: 'ROLLADE SAPI ROLL 400 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'Rolade polos 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Rolade sapi polos 1 kg', mappedValue: 'ROLLADE SAPI 1000 G ( MBG )', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Rolade Ayam polos 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
    ];

    final chatText = '''
MISTER SOSIS
Rolade ayam polos 1 kg...25 k
Rolade sapi polos 1 kg....15 k
Krm hr kamis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'K001');
    expect(draft.customerName, 'SUSILO HARYAWAN');
    expect(draft.aliasName, 'MISTER SOSIS');
    expect(draft.city, 'BLORA');
    expect(draft.items.length, 2);
    expect(draft.items[0].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draft.items[0].qtyInput, 25.0);
    expect(draft.items[1].productName, 'ROLLADE SAPI 1000 G ( MBG )');
    expect(draft.items[1].qtyInput, 15.0);
  });

  test('Customer history matches Fiva rolade roll ayam to ROLLADE AYAM ROLL 400 G, NOT ROLLADE AYAM 1000 G (even with 22x purchase history)', () {
    final parser = AiChatParserService();
    final history = <CustomerProductHistory>[
      CustomerProductHistory(
        productId: 'RA-1000',
        productName: 'ROLLADE AYAM 1000 G ( MBG )',
        price: 47000,
        discountPercent: 0.0,
        discountAmount: 0.0,
        purchaseCount: 22,
        invoiceNo: '670',
        date: DateTime.now().subtract(const Duration(days: 5)),
      ),
      CustomerProductHistory(
        productId: 'RAR-400',
        productName: 'ROLLADE AYAM ROLL 400 G',
        price: 24797,
        discountPercent: 0.0,
        discountAmount: 0.0,
        purchaseCount: 1,
        invoiceNo: '650',
        date: DateTime.now().subtract(const Duration(days: 40)),
      ),
    ];

    final matched = parser.testMatchCustomerHistory('Fiva rolade roll ayam', history);
    expect(matched?.productName, 'ROLLADE AYAM ROLL 400 G');
  });

  test('Full SJJ WhatsApp Chat parses all 5 items correctly with true ROLL variants', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500 G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS COKLAT 24S 500 G', price: 37000, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P04', name: 'ROLLADE AYAM ROLL 400 G', price: 24797, stock: 100, isiKarton: 50, sizeGrams: 400),
      Product(id: 'P05', name: 'ROLLADE SAPI ROLL 400 G', price: 26194, stock: 100, isiKarton: 50, sizeGrams: 400),
    ];

    final customers = [
      Customer(
        id: 'AD008',
        customerName: 'SURYANTO WIBISONO WIBOWO',
        aliasName: 'SUMBER JADI JAYA',
        address: 'Solo',
        city: 'SURAKARTA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'SJJ', mappedValue: 'SUMBER JADI JAYA', targetId: 'AD008', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'ROLADE SAPI ROLL', mappedValue: 'ROLLADE SAPI ROLL 400 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Beres coklat 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r5', type: 'product_alias', keyword: 'Rolade 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
    ];

    final chatText = '''
Pak order SJJ
Fiva beres merah isi 24 = 30 karton
Fiva rolade 1 kg =35 karton
Fiva beres coklat isi 24 = 5 karton
Fiva rolade roll ayam = 2 ball....50 ROLL
Fiva rolade roll sapi = 2 ball....50 ROLL
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'AD008');
    expect(draft.customerName, 'SURYANTO WIBISONO WIBOWO');
    expect(draft.items.length, 5);

    expect(draft.items[0].productName, 'BRS MERAH 24 500 G');
    expect(draft.items[0].qtyInput, 30.0);
    expect(draft.items[0].qtyUnit, 'karton');

    expect(draft.items[1].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draft.items[1].qtyInput, 35.0);
    expect(draft.items[1].qtyUnit, 'karton');

    expect(draft.items[2].productName, 'BRS COKLAT 24S 500 G');
    expect(draft.items[2].qtyInput, 5.0);
    expect(draft.items[2].qtyUnit, 'karton');

    // Item 4 MUST be ROLLADE AYAM ROLL 400 G with 50 roll, NOT 1000g!
    expect(draft.items[3].productName, 'ROLLADE AYAM ROLL 400 G');
    expect(draft.items[3].qtyInput, 50.0);
    expect(draft.items[3].qtyUnit, 'roll');

    // Item 5 MUST be ROLLADE SAPI ROLL 400 G with 50 roll
    expect(draft.items[4].productName, 'ROLLADE SAPI ROLL 400 G');
    expect(draft.items[4].qtyInput, 50.0);
    expect(draft.items[4].qtyUnit, 'roll');
  });

  test('Tahap 1: Chat with store name at BOTTOM (Mister sosis) parses customer and all items correctly', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 45000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P02', name: 'ROLLADE SAPI 1000 G ( MBG )', price: 46000, stock: 100, isiKarton: 10, sizeGrams: 1000),
    ];

    final customers = [
      Customer(
        id: 'K001',
        customerName: 'SUSILO HARYAWAN',
        aliasName: 'MISTER SOSIS',
        address: 'Blora',
        city: 'BLORA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '081234567890',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'MISTER SOSIS', mappedValue: 'SUSILO HARYAWAN', targetId: 'K001', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'Rolade polos 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Rolade sapi polos 1 kg', mappedValue: 'ROLLADE SAPI 1000 G ( MBG )', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Rolade Ayam polos 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
    ];

    final chatText = '''
Rolade ayam polos 1 kg...25 k
Rolade sapi polos 1 kg....15 k
Krm hr kamis
Mister sosis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'K001');
    expect(draft.customerName, 'SUSILO HARYAWAN');
    expect(draft.items.length, 2);
    expect(draft.items[0].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draft.items[0].qtyInput, 25.0);
    expect(draft.items[1].productName, 'ROLLADE SAPI 1000 G ( MBG )');
    expect(draft.items[1].qtyInput, 15.0);
  });

  test('Tahap 2: Chat without any store name in text resolves customer via senderPhone', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 45000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P02', name: 'ROLLADE SAPI 1000 G ( MBG )', price: 46000, stock: 100, isiKarton: 10, sizeGrams: 1000),
    ];

    final customers = [
      Customer(
        id: 'K001',
        customerName: 'SUSILO HARYAWAN',
        aliasName: 'MISTER SOSIS',
        address: 'Blora',
        city: 'BLORA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '081234567890',
        ktpNumber: '',
      ),
    ];

    final chatText = '''
Rolade ayam polos 1 kg...25 k
Rolade sapi polos 1 kg....15 k
Krm hr kamis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: [],
      senderPhone: '6281234567890',
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'K001');
    expect(draft.customerName, 'SUSILO HARYAWAN');
    expect(draft.items.length, 2);
    expect(draft.items[0].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draft.items[0].qtyInput, 25.0);
  });

  test('Bug fix: Administrative chat "Masuk erp bsk pagi 1. Sjj 2. Berkah tempura" produces 0 drafts (no PO created)', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P02', name: 'TEMPURA AYAM 500 G', price: 25000, stock: 100, isiKarton: 20, sizeGrams: 500),
    ];
    final customers = [
      Customer(id: 'AD008', customerName: 'SURYANTO WIBISONO WIBOWO', aliasName: 'SJJ', address: '', city: 'SURAKARTA', province: '', country: '', phone: '', ktpNumber: ''),
      Customer(id: 'BT001', customerName: 'BERKAH TEMPURA', aliasName: 'BERKAH TEMPURA', address: '', city: 'SEMARANG', province: '', country: '', phone: '', ktpNumber: ''),
    ];

    final chatText = '''
Masuk erp bsk pagi
1. Sjj
2. Berkah tempura
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: [],
    );

    expect(drafts.isEmpty, isTrue);
  });

  test('Order chat with items and "Masuk erp bsk pagi" captures note in draft.note', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
    ];
    final customers = [
      Customer(id: 'AD008', customerName: 'SURYANTO WIBISONO WIBOWO', aliasName: 'SJJ', address: '', city: 'SURAKARTA', province: '', country: '', phone: '', ktpNumber: ''),
    ];

    final chatText = '''
Masuk erp bsk pagi
SJJ
Rolade ayam 1000g 10k
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: [],
    );

    expect(drafts.length, 1);
    expect(drafts.first.items.length, 1);
    expect(drafts.first.note, isEmpty);
  });

  test('Pak BC Multi-store chat splits into 2 separate drafts: SJJ and Mister Sosis', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500 G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS COKLAT 24S 500 G', price: 37000, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P04', name: 'ROLLADE AYAM ROLL 400 G', price: 24797, stock: 100, isiKarton: 50, sizeGrams: 400),
      Product(id: 'P05', name: 'ROLLADE SAPI ROLL 400 G', price: 26194, stock: 100, isiKarton: 50, sizeGrams: 400),
    ];

    final customers = [
      Customer(
        id: 'AD008',
        customerName: 'SURYANTO WIBISONO WIBOWO',
        aliasName: 'SJJ',
        address: 'Solo',
        city: 'SURAKARTA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08122589564',
        ktpNumber: '',
      ),
      Customer(
        id: 'K001',
        customerName: 'SUSILO HARYAWAN',
        aliasName: 'MISTER SOSIS',
        address: 'Blora',
        city: 'BLORA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'SJJ', mappedValue: 'SJJ', targetId: 'AD008', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'customer_alias', keyword: 'Mister sosis', mappedValue: 'SUSILO HARYAWAN', targetId: 'K001', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Rolade 1 kg', mappedValue: 'ROLLADE AYAM 1000 G ( MBG )', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r4', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r5', type: 'product_alias', keyword: 'Beres coklat 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r6', type: 'product_alias', keyword: 'Rolade roll ayam', mappedValue: 'ROLLADE AYAM ROLL 400 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r7', type: 'product_alias', keyword: 'Rolade roll sapi', mappedValue: 'ROLLADE SAPI ROLL 400 G', createdAt: DateTime.now()),
    ];

    final chatText = '''
Fiva beres merah isi 24 = 30 karton
Fiva rolade 1 kg =35 karton
Fiva beres coklat isi 24 = 5 karton
Fiva rolade roll ayam = 2 ball....50 ROLL
Fiva rolade roll sapi = 2 ball....50 ROLL
Krm bsk pg
SJJ
Fiva beres merah isi 24 = 30 karton
Fiva rolade 1 kg =35 karton
Fiva beres coklat isi 24 = 5 karton
Fiva rolade roll ayam = 2 ball....50 ROLL
Fiva rolade roll sapi = 2 ball....50 ROLL
Krm bsk pg
Mister sosis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 2);

    // Draft 1: SJJ
    final draft1 = drafts[0];
    expect(draft1.customerId, 'AD008');
    expect(draft1.items.length, 5);
    expect(draft1.note, isEmpty);

    // Draft 2: Mister sosis
    final draft2 = drafts[1];
    expect(draft2.customerId, 'K001');
    expect(draft2.customerName, 'SUSILO HARYAWAN');
    expect(draft2.items.length, 5);
    expect(draft2.note, isEmpty);
  });

  test('Chat with store at top (Griya ff Pekalongan) parses correctly', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500 G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
    ];
    final customers = [
      Customer(id: 'G01', customerName: 'GRIYA FROZEN FOOD', aliasName: 'GRIYA FF', address: '', city: 'PEKALONGAN', province: 'JAWA TENGAH', country: 'INDONESIA', phone: '', ktpNumber: ''),
    ];
    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'Griya ff', mappedValue: 'GRIYA FROZEN FOOD', targetId: 'G01', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'Beres merah', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
    ];

    final chatText = '''
Griya ff Pekalongan
Beres merah 20 k
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    expect(drafts.length, 1);
    expect(drafts.first.customerId, 'G01');
    expect(drafts.first.items.length, 1);
    expect(drafts.first.items.first.qtyInput, 20.0);
    expect(drafts.first.items.first.qtyUnit, 'karton');
  });

  test('MISTER SOSIS adapts to historical variants (BRS MERAH 24S 500G @ 34549, BRS COKLAT 24S 2 500G @ 28234) and discounts (17.5%)', () async {
    final parser = AiChatParserService();
    final products = [
      Product(id: 'P01', name: 'BRS MERAH 24 500 G', price: 36691, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P02', name: 'BRS MERAH 24S 500G', price: 34549, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P03', name: 'BRS COKLAT 24S 500 G', price: 30688, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P04', name: 'BRS COKLAT 24S 2 500G', price: 28234, stock: 100, isiKarton: 24, sizeGrams: 500),
      Product(id: 'P05', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P06', name: 'ROLLADE AYAM ROLL 400 G', price: 24797, stock: 100, isiKarton: 50, sizeGrams: 400),
      Product(id: 'P07', name: 'ROLLADE SAPI ROLL 400 G', price: 26194, stock: 100, isiKarton: 50, sizeGrams: 400),
    ];

    final customers = [
      Customer(
        id: 'K001',
        customerName: 'SUSILO HARYAWAN',
        aliasName: 'MISTER SOSIS',
        address: 'Blora',
        city: 'BLORA',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '081234567890',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'MISTER SOSIS', mappedValue: 'SUSILO HARYAWAN', targetId: 'K001', createdAt: DateTime.now()),
      // Global product rules (map to standard/master)
      AiKnowledgeRule(id: 'r2', type: 'product_alias', keyword: 'Beres merah 24', mappedValue: 'BRS MERAH 24 500 G', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'product_alias', keyword: 'Beres coklat 24', mappedValue: 'BRS COKLAT 24S 500 G', createdAt: DateTime.now()),
    ];

    // Historical purchases of Mister Sosis (from Invoice #632 and earlier)
    final misterSosisHistory = [
      CustomerProductHistory(
        productId: 'P02',
        productName: 'BRS MERAH 24S 500G',
        price: 34549,
        discountPercent: 0.0,
        discountAmount: 0.0,
        invoiceNo: '632',
        purchaseCount: 5,
        date: DateTime.now().subtract(const Duration(days: 60)),
      ),
      CustomerProductHistory(
        productId: 'P04',
        productName: 'BRS COKLAT 24S 2 500G',
        price: 28234,
        discountPercent: 0.0,
        discountAmount: 0.0,
        invoiceNo: '632',
        purchaseCount: 8,
        date: DateTime.now().subtract(const Duration(days: 60)),
      ),
      CustomerProductHistory(
        productId: 'P05',
        productName: 'ROLLADE AYAM 1000 G ( MBG )',
        price: 45000,
        discountPercent: 0.0,
        discountAmount: 0.0,
        invoiceNo: '632',
        purchaseCount: 15,
        date: DateTime.now().subtract(const Duration(days: 60)),
      ),
      CustomerProductHistory(
        productId: 'P06',
        productName: 'ROLLADE AYAM ROLL 400 G',
        price: 24797,
        discountPercent: 17.5,
        discountAmount: 0.0,
        invoiceNo: '620',
        purchaseCount: 3,
        date: DateTime.now().subtract(const Duration(days: 90)),
      ),
      CustomerProductHistory(
        productId: 'P07',
        productName: 'ROLLADE SAPI ROLL 400 G',
        price: 26194,
        discountPercent: 17.5,
        discountAmount: 0.0,
        invoiceNo: '620',
        purchaseCount: 3,
        date: DateTime.now().subtract(const Duration(days: 90)),
      ),
    ];

    final chatText = '''
Fiva beres merah isi 24 = 30 karton
Fiva rolade 1 kg =35 karton
Fiva beres coklat isi 24 = 5 karton
Fiva rolade roll ayam = 2 ball....50 ROLL
Fiva rolade roll sapi = 2 ball....50 ROLL
Krm bsk pg
Mister sosis
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
      mockCustomerHistory: {'K001': misterSosisHistory},
    );

    expect(drafts.length, 1);
    final draft = drafts.first;
    expect(draft.customerId, 'K001');
    expect(draft.customerName, 'SUSILO HARYAWAN');
    expect(draft.aliasName, 'MISTER SOSIS');
    expect(draft.items.length, 5);

    // Item 1: BRS MERAH 24S 500G @ 34.549 (adapted to customer's historical variant, NOT master 36.691!)
    expect(draft.items[0].productName, 'BRS MERAH 24S 500G');
    expect(draft.items[0].qtyInput, 30.0);
    expect(draft.items[0].price, 34549.0);

    // Item 2: ROLLADE AYAM 1000 G ( MBG ) @ 45.000 (from customer history, NOT standard 47.000!)
    expect(draft.items[1].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draft.items[1].qtyInput, 35.0);
    expect(draft.items[1].price, 45000.0);

    // Item 3: BRS COKLAT 24S 2 500G @ 28.234 (adapted to customer's historical Tier 2 variant, NOT master 30.688!)
    expect(draft.items[2].productName, 'BRS COKLAT 24S 2 500G');
    expect(draft.items[2].qtyInput, 5.0);
    expect(draft.items[2].price, 28234.0);

    // Item 4: ROLLADE AYAM ROLL 400 G with 17.5% discount
    expect(draft.items[3].productName, 'ROLLADE AYAM ROLL 400 G');
    expect(draft.items[3].qtyInput, 50.0);
    expect(draft.items[3].qtyUnit, 'roll');
    expect(draft.items[3].discountPercent, 17.5);

    // Item 5: ROLLADE SAPI ROLL 400 G with 17.5% discount
    expect(draft.items[4].productName, 'ROLLADE SAPI ROLL 400 G');
    expect(draft.items[4].qtyInput, 50.0);
    expect(draft.items[4].qtyUnit, 'roll');
    expect(draft.items[4].discountPercent, 17.5);
  });

  test('Multi-store chat with mixed header (SJJ) and footer (Hana makmur) splits into 2 POs without phantom PO for Griya ff pekalongan', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P01', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 47000, stock: 100, isiKarton: 10, sizeGrams: 1000),
      Product(id: 'P02', name: 'ROLLADE AYAM 250 G', price: 15000, stock: 100, isiKarton: 20, sizeGrams: 250),
      Product(id: 'P03', name: 'KORNET AYAM LOYANG 400 G', price: 19363, stock: 100, isiKarton: 20, sizeGrams: 400),
      Product(id: 'P04', name: 'ROLLADE AYAM ROLL 400 G', price: 24797, stock: 100, isiKarton: 50, sizeGrams: 400),
      Product(id: 'P05', name: 'ROLLADE SAPI ROLL 400 G', price: 26194, stock: 100, isiKarton: 50, sizeGrams: 400),
    ];

    final customers = [
      Customer(
        id: 'C001',
        customerName: 'GRIYA FROZEN FOOD',
        aliasName: 'GRIYA FF PEKALONGAN',
        address: 'Pekalongan',
        city: 'PEKALONGAN',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08111111111',
        ktpNumber: '',
      ),
      Customer(
        id: 'C002',
        customerName: 'SUMBER JADI JAYA',
        aliasName: 'SJJ',
        address: 'Semarang',
        city: 'SEMARANG',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08222222222',
        ktpNumber: '',
      ),
      Customer(
        id: 'C003',
        customerName: 'HANA MAKMUR',
        aliasName: 'HANA MAKMUR',
        address: 'Kudus',
        city: 'KUDUS',
        province: 'JAWA TENGAH',
        country: 'INDONESIA',
        phone: '08333333333',
        ktpNumber: '',
      ),
    ];

    final rules = [
      AiKnowledgeRule(id: 'r1', type: 'customer_alias', keyword: 'SJJ', mappedValue: 'SUMBER JADI JAYA', targetId: 'C002', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r2', type: 'customer_alias', keyword: 'Griya ff pekalongan', mappedValue: 'GRIYA FROZEN FOOD', targetId: 'C001', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r3', type: 'customer_alias', keyword: 'Hana makmur', mappedValue: 'HANA MAKMUR', targetId: 'C003', createdAt: DateTime.now()),
    ];

    final chatText = '''
Msk erp hari ini....
1. Griya ff pekalongan
SJJ
Kirim hr selasa
Rolade ayam polos 1 kg ...15 k
Fv Kornet loyang 15 k.....300 pack
Fv Rolade ayam roll 100 ball.....2.500 roll
Fv Rolade sapi roll 35 ball...875 roll
Krm hari kamis minggu depan
Hana makmur
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
    );

    // Must be exactly 2 drafts: SJJ and HANA MAKMUR (Griya ff pekalongan has 0 items, so no phantom PO)
    expect(drafts.length, 2);

    // Draft 1: SJJ
    final draftSjj = drafts[0];
    expect(draftSjj.customerId, 'C002');
    expect(draftSjj.customerName, 'SUMBER JADI JAYA');
    expect(draftSjj.note, isEmpty);
    expect(draftSjj.items.length, 1);
    expect(draftSjj.items[0].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(draftSjj.items[0].qtyInput, 15.0);
    expect(draftSjj.items[0].qtyUnit, 'karton');

    // Draft 2: HANA MAKMUR
    final draftHana = drafts[1];
    expect(draftHana.customerId, 'C003');
    expect(draftHana.customerName, 'HANA MAKMUR');
    expect(draftHana.note, isEmpty);
    expect(draftHana.items.length, 3);

    // Item 1: Kornet loyang 15 k / 300 pack
    expect(draftHana.items[0].productName, 'KORNET AYAM LOYANG 400 G');
    expect(draftHana.items[0].qtyInput, 15.0);
    expect(draftHana.items[0].qtyUnit, 'karton');

    // Item 2: Rolade ayam roll 2.500 roll
    expect(draftHana.items[1].productName, 'ROLLADE AYAM ROLL 400 G');
    expect(draftHana.items[1].qtyInput, 2500.0);
    expect(draftHana.items[1].qtyUnit, 'roll');

    // Item 3: Rolade sapi roll 875 roll
    expect(draftHana.items[2].productName, 'ROLLADE SAPI ROLL 400 G');
    expect(draftHana.items[2].qtyInput, 875.0);
    expect(draftHana.items[2].qtyUnit, 'roll');
  });
  test('Reproduction: Multi-store chat with senderPhone for ELA FF should still resolve SJJ not ELA FF', () async {
    final parser = AiChatParserService();

    final products = [
      Product(id: 'P001', name: 'ROLLADE AYAM 1000 G ( MBG )', price: 150000.0, stock: 100.0, isiKarton: 10, sizeGrams: 1000.0),
      Product(id: 'P002', name: 'KORNET AYAM LOYANG 400 G', price: 150000.0, stock: 100.0, isiKarton: 20, sizeGrams: 400.0),
      Product(id: 'P003', name: 'ROLLADE AYAM ROLL 400 G', price: 25000.0, stock: 5000.0, isiKarton: 1, sizeGrams: 400.0),
      Product(id: 'P004', name: 'ROLLADE SAPI ROLL 400 G', price: 25000.0, stock: 5000.0, isiKarton: 1, sizeGrams: 400.0),
    ];

    // Customer database matching production:
    // ELA FF has phone +6287789733632
    // SJJ has customerName 'SUMBER JADI JAYA' (or aliasName 'SUMBER JADI JAYA')
    // No explicit AiKnowledgeRule for SJJ in rules!
    final customers = [
      Customer(id: 'C_ELA', customerName: 'ANDI SUSANTO', aliasName: 'ELA FF', address: '', city: 'JEPARA', province: '', country: '', phone: '+6287789733632', ktpNumber: ''),
      Customer(id: 'C_SJJ', customerName: 'SUMBER JADI JAYA', aliasName: '', address: '', city: 'PEKALONGAN', province: '', country: '', phone: '', ktpNumber: ''),
      Customer(id: 'C_HANA', customerName: 'HANA MAKMUR', aliasName: 'Hana makmur', address: '', city: 'PURBALINGGA', province: '', country: '', phone: '', ktpNumber: ''),
    ];

    // Production rules - Notice NO SJJ rule here!
    final rules = [
      AiKnowledgeRule(id: 'r_unit1', type: 'unit', keyword: 'k', mappedValue: '1 Karton', createdAt: DateTime.now()),
      AiKnowledgeRule(id: 'r_unit2', type: 'unit', keyword: 'roll', mappedValue: '1 Pack', createdAt: DateTime.now()),
    ];

    final chatText = '''
Msk erp hari ini....
1. Griya ff pekalongan
SJJ
Kirim hr selasa
Rolade ayam polos 1 kg ...15 k
Fv Kornet loyang 15 k.....300 pack
Fv Rolade ayam roll 100 ball.....2.500 roll
Fv Rolade sapi roll 35 ball...875 roll
Krm hari kamis minggu depan
Hana makmur
''';

    final drafts = await parser.parseChatOrders(
      rawChat: chatText,
      products: products,
      customers: customers,
      rules: rules,
      senderPhone: '+6287789733632',
    );

    expect(drafts.length, 2);
    // SJJ should be resolved for Draft 0 despite senderPhone matching ELA FF
    expect(drafts[0].customerId, 'C_SJJ');
    expect(drafts[0].customerName, 'SUMBER JADI JAYA');
    expect(drafts[0].items.length, 1);
    expect(drafts[0].items[0].productName, 'ROLLADE AYAM 1000 G ( MBG )');
    expect(drafts[0].items[0].qtyInput, 15.0);

    // Hana Makmur should be resolved for Draft 1
    expect(drafts[1].customerId, 'C_HANA');
    expect(drafts[1].customerName, 'HANA MAKMUR');
    expect(drafts[1].items.length, 3);
  });

  test('TransactionItem displayNameWithBonus never produces duplicate (BONUS) (BONUS)', () {
    // Normal item: isBonus = false
    final itemNormal = TransactionItem(
      productId: 'P1',
      productName: 'KORNET AYAM LOYANG 400 G',
      price: 19000,
      qty: 800,
      discountPercent: 0,
      subtotal: 15200000,
      sizeGrams: 400,
      isBonus: false,
    );
    expect(itemNormal.displayNameWithBonus, 'KORNET AYAM LOYANG 400 G');

    // Clean bonus item: isBonus = true, clean name
    final itemBonusClean = TransactionItem(
      productId: 'P1',
      productName: 'KORNET AYAM LOYANG 400 G',
      price: 0,
      qty: 20,
      discountPercent: 0,
      subtotal: 0,
      sizeGrams: 400,
      isBonus: true,
    );
    expect(itemBonusClean.displayNameWithBonus, 'KORNET AYAM LOYANG 400 G (BONUS)');

    // Legacy bonus item where productName already had (BONUS): isBonus = true
    final itemBonusLegacy = TransactionItem(
      productId: 'P1',
      productName: 'KORNET AYAM LOYANG 400 G (BONUS)',
      price: 0,
      qty: 20,
      discountPercent: 0,
      subtotal: 0,
      sizeGrams: 400,
      isBonus: true,
    );
    // Must be single (BONUS), NOT (BONUS) (BONUS)
    expect(itemBonusLegacy.displayNameWithBonus, 'KORNET AYAM LOYANG 400 G (BONUS)');
  });
}



