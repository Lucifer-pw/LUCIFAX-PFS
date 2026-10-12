import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_app/services/ai_chat_parser_service.dart';
import 'package:cashier_app/models/product.dart';
import 'package:cashier_app/models/customer.dart';
import 'package:cashier_app/models/customer_product_history.dart';
import 'package:cashier_app/models/ai_knowledge_rule.dart';

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
}

