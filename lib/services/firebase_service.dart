import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/staff.dart';
import '../models/attendance_record.dart';
import '../models/transaction.dart' as model_tr;
import '../models/transaction_return.dart';
import '../models/operational_invoice.dart';
import '../models/operational_category.dart';
import '../models/operational_payment_method.dart';
import '../models/stock_mutation.dart';
import '../models/wa_contact.dart';
import '../models/invoice_print_log.dart';
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ==========================================
  // INVOICE PRINT & DATE SELECTION AUDIT LOGS
  // ==========================================

  Future<void> logInvoicePrint({
    required dynamic invoiceNo,
    required String customerName,
    required DateTime originalDate,
    DateTime? originalDeliveryDate,
    required DateTime printedDeliveryDate,
    required String optionType, // 'TANGGAL_AWAL' | 'TANGGAL_BARU'
    required String actionType, // 'PRINT' | 'DOWNLOAD'
    required String userId,
    required String userName,
    required String userUsername,
    required String userRole,
    required bool isDeveloper,
    required double grandTotal,
  }) async {
    try {
      await _db.collection('invoice_print_logs').add({
        'invoiceNo': invoiceNo,
        'customerName': customerName,
        'originalDate': Timestamp.fromDate(originalDate),
        if (originalDeliveryDate != null) 'originalDeliveryDate': Timestamp.fromDate(originalDeliveryDate),
        'printedDeliveryDate': Timestamp.fromDate(printedDeliveryDate),
        'optionType': optionType,
        'actionType': actionType,
        'userId': userId,
        'userName': userName,
        'userUsername': userUsername,
        'userRole': userRole,
        'isDeveloper': isDeveloper,
        'timestamp': Timestamp.now(),
        'grandTotal': grandTotal,
      });
    } catch (e) {
      debugPrint('Error logging invoice print: $e');
    }
  }

  Stream<List<InvoicePrintLog>> streamInvoicePrintLogs({int limit = 150}) {
    return _db.collection('invoice_print_logs').snapshots().map((snapshot) {
      var list = snapshot.docs.map((doc) => InvoicePrintLog.fromFirestore(doc)).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (list.length > limit) {
        list = list.sublist(0, limit);
      }
      return list;
    });
  }

  Future<void> deleteInvoicePrintLog(String logId) async {
    try {
      await _db.collection('invoice_print_logs').doc(logId).delete();
    } catch (e) {
      debugPrint('Error deleting print log: $e');
    }
  }

  Future<void> clearAllInvoicePrintLogs() async {
    try {
      final snap = await _db.collection('invoice_print_logs').get();
      final batch = _db.batch();
      for (var doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error clearing all print logs: $e');
    }
  }

  // ==========================================
  // PRODUCTS CRUD
  // ==========================================

  Stream<List<Product>> streamProducts() {
    return _db.collection('products').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Product.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> saveProduct(Product product, {bool logMutation = false, double? oldStock}) async {
    await _db.collection('products').doc(product.id).set(product.toMap());

    if (product.kodeInduk.isNotEmpty) {
      final query = await _db
          .collection('products')
          .where('kodeInduk', isEqualTo: product.kodeInduk)
          .get();

      if (query.docs.isNotEmpty) {
        final batch = _db.batch();
        for (var doc in query.docs) {
          batch.update(doc.reference, {'stock': product.stock});
        }
        await batch.commit();
      }
    }

    // Log stock mutation for manual edits
    if (logMutation && oldStock != null && oldStock != product.stock) {
      final delta = product.stock - oldStock;
      await _logStockMutations([
        StockMutation(
          id: '',
          kodeInduk: product.kodeInduk,
          productName: product.name,
          type: 'EDIT_MANUAL',
          qty: delta,
          stockBefore: oldStock,
          stockAfter: product.stock,
          reference: 'Edit Manual Master Barang',
          timestamp: DateTime.now(),
        ),
      ]);
    }
  }

  // ==========================================
  // STOCK MUTATION LOGGING
  // ==========================================

  Future<void> _logStockMutations(List<StockMutation> mutations) async {
    try {
      final batch = _db.batch();
      for (var m in mutations) {
        final docRef = _db.collection('stock_mutations').doc();
        batch.set(docRef, m.toFirestore());
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error logging stock mutations: $e');
    }
  }

  Stream<List<StockMutation>> streamStockMutations(
    String kodeInduk, {
    DateTime? startDate,
    DateTime? endDate,
    DateTime? date,
    int limit = 500,
  }) {
    DateTime? start = startDate;
    DateTime? end = endDate;
    if (date != null && start == null && end == null) {
      start = DateTime(date.year, date.month, date.day, 0, 0, 0);
      end = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    }

    // Query by kodeInduk only (no composite index required in Firestore)
    return _db
        .collection('stock_mutations')
        .where('kodeInduk', isEqualTo: kodeInduk)
        .snapshots()
        .map((snapshot) {
      var list = snapshot.docs.map((doc) => StockMutation.fromFirestore(doc)).toList();

      if (start != null) {
        final s = start;
        list = list.where((m) => m.timestamp.isAfter(s.subtract(const Duration(seconds: 1)))).toList();
      }
      if (end != null) {
        final e = end;
        list = list.where((m) => m.timestamp.isBefore(e.add(const Duration(seconds: 1)))).toList();
      }

      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (list.length > limit) {
        list = list.sublist(0, limit);
      }
      return list;
    });
  }

  Stream<List<StockMutation>> streamAllStockMutations({
    DateTime? startDate,
    DateTime? endDate,
    DateTime? date,
    int limit = 500,
  }) {
    DateTime? start = startDate;
    DateTime? end = endDate;
    if (date != null && start == null && end == null) {
      start = DateTime(date.year, date.month, date.day, 0, 0, 0);
      end = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    }

    Query query = _db.collection('stock_mutations');
    if (start != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    }
    if (end != null) {
      query = query.where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end));
    }

    return query.snapshots().map((snapshot) {
      var list = snapshot.docs.map((doc) => StockMutation.fromFirestore(doc)).toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (list.length > limit) {
        list = list.sublist(0, limit);
      }
      return list;
    });
  }

  Future<void> deleteProduct(String id) async {
    await _db.collection('products').doc(id).delete();
  }

  Future<void> syncAllKodeIndukStocksToFirestore(Map<String, double> kodeIndukStockMap) async {
    try {
      final batch = _db.batch();
      bool needsCommit = false;

      for (var entry in kodeIndukStockMap.entries) {
        if (entry.key.isNotEmpty && entry.value > 0) {
          final query = await _db
              .collection('products')
              .where('kodeInduk', isEqualTo: entry.key)
              .get();

          for (var doc in query.docs) {
            final double currentDocStock = (doc.data()['stock'] ?? 0.0).toDouble();
            if (currentDocStock != entry.value) {
              batch.update(doc.reference, {'stock': entry.value});
              needsCommit = true;
            }
          }
        }
      }

      if (needsCommit) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Error syncing kodeInduk stocks to Firestore: $e");
    }
  }

  // ==========================================
  // CUSTOMERS CRUD & ID GENERATION
  // ==========================================

  Stream<List<Customer>> streamCustomers() {
    return _db.collection('customers').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Customer.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> saveCustomer(Customer customer) async {
    await _db.collection('customers').doc(customer.id).set(customer.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _db.collection('customers').doc(id).delete();
  }

  // VBA GetPlatKode port
  String getPlatKode(String city) {
    final cityName = city.trim().toUpperCase();
    switch (cityName) {
      // ===== G =====
      case "PEKALONGAN":
      case "TEGAL":
      case "BREBES":
      case "BATANG":
      case "PEMALANG":
        return "G";

      // ===== H =====
      case "SEMARANG":
      case "DEMAK":
      case "GROBOGAN":
      case "SALATIGA":
      case "GUBUG":
      case "PURWODADI":
      case "KENDAL":
        return "H";

      // ===== AA =====
      case "WONOSOBO":
      case "MAGELANG":
      case "PURWOREJO":
      case "TEMANGGUNG":
      case "KEBUMEN":
        return "AA";

      // ===== R =====
      case "BANJARNEGARA":
      case "PURBALINGGA":
      case "BANYUMAS":
      case "CILACAP":
        return "R";

      // ===== K =====
      case "KUDUS":
      case "JEPARA":
      case "PATI":
      case "REMBANG":
      case "BLORA":
        return "K";

      // ===== AD =====
      case "SOLO":
      case "SURAKARTA":
      case "SRAGEN":
      case "KARANGANYAR":
      case "KLATEN":
      case "BOYOLALI":
      case "COLOMADU":
      case "BANJARSARI":
        return "AD";

      // ===== AB (DIY) =====
      case "YOGYAKARTA":
      case "SLEMAN":
      case "BANTUL":
      case "KULONPROGO":
      case "GUNUNGKIDUL":
      case "WATES":
        return "AB";

      default:
        return "X";
    }
  }

  // VBA GenerateCustomerIDByCity port
  Future<String> generateCustomerID(String city) async {
    final plat = getPlatKode(city);
    if (plat == "X") {
      throw Exception("Kota belum terdaftar dalam kode plat wilayah!");
    }

    final query = await _db.collection('customers').get();
    int maxNumber = 0;

    for (var doc in query.docs) {
      final id = doc.id;
      if (id.startsWith(plat)) {
        final numberPart = id.substring(plat.length);
        final numVal = int.tryParse(numberPart) ?? 0;
        if (numVal > maxNumber) {
          maxNumber = numVal;
        }
      }
    }

    final nextNumber = maxNumber + 1;
    final paddedNumber = nextNumber.toString().padLeft(3, '0');
    return "$plat$paddedNumber";
  }

  // ==========================================
  // TRANSACTIONS & ERP SYNC
  // ==========================================

  Stream<List<model_tr.Transaction>> streamTransactions() {
    return _db
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => model_tr.Transaction.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<String> peekNextInvoiceNo({String type = 'PO'}) async {
    try {
      if (type == 'SA') {
        final counterRef = _db.collection('counters').doc('sample_transactions');
        final snap = await counterRef.get();
        int current = 54;
        if (snap.exists) {
          current = snap.data()?['lastSaNo'] ?? 54;
        }
        return 'SA${current + 1}';
      } else {
        final counterRef = _db.collection('counters').doc('transactions');
        final snap = await counterRef.get();
        int current = 180;
        if (snap.exists) {
          current = snap.data()?['lastInvoiceNo'] ?? current;
        }
        return '${current + 1}';
      }
    } catch (e) {
      debugPrint("peekNextInvoiceNo fallback due to: $e");
      try {
        final snap = await _db.collection('transactions').orderBy('date', descending: true).limit(20).get();
        int maxNo = (type == 'SA' ? 54 : 180);
        for (var doc in snap.docs) {
          final id = doc.id;
          if (type == 'SA') {
            if (id.startsWith('SA')) {
              final numPart = int.tryParse(id.replaceAll('SA', '')) ?? 0;
              if (numPart > maxNo) maxNo = numPart;
            }
          } else {
            final numPart = int.tryParse(id) ?? 0;
            if (numPart > maxNo) maxNo = numPart;
          }
        }
        final next = maxNo + 1;
        return type == 'SA' ? 'SA$next' : '$next';
      } catch (_) {
        final nowTs = DateTime.now().millisecondsSinceEpoch % 10000;
        return type == 'SA' ? 'SA$nowTs' : '$nowTs';
      }
    }
  }

  // Save transaction with Auto-Increment Invoice Number (PO or SA) & ERP update inside a Firestore Transaction
  Future<model_tr.Transaction> createTransaction({
    required String customerId,
    required String customerName,
    required String aliasName,
    required DateTime deliveryDate,
    required String city,
    required String province,
    required String country,
    required List<model_tr.TransactionItem> items,
    required double grandTotal,
    required String note,
    required String createdBy,
    String invoiceType = 'PO', // 'PO' or 'SA'
    String? customSaNo,
    String? idempotencyKey,
  }) async {
    // Idempotency check: if this key was already used, return existing transaction
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      try {
        final idempotencyRef = _db.collection('idempotency_keys').doc(idempotencyKey);
        final idempotencySnap = await idempotencyRef.get();
        if (idempotencySnap.exists) {
          final existingInvoiceNo = idempotencySnap.data()?['invoiceNo']?.toString() ?? '';
          if (existingInvoiceNo.isNotEmpty) {
            final existingDoc = await _db.collection('transactions').doc(existingInvoiceNo).get();
            if (existingDoc.exists) {
              debugPrint('Idempotency hit: returning existing invoice #$existingInvoiceNo');
              return model_tr.Transaction.fromMap(existingDoc.data()!, existingDoc.id);
            }
          }
        }
      } catch (e) {
        debugPrint("Idempotency check bypass/error: $e");
      }
    }

    final now = DateTime.now();
    String docId = '';

    if (invoiceType == 'SA') {
      if (customSaNo != null && customSaNo.trim().isNotEmpty) {
        String clean = customSaNo.trim().toUpperCase();
        if (!clean.startsWith('SA')) {
          clean = 'SA$clean';
        }
        docId = clean;
      } else {
        try {
          final saCounterRef = _db.collection('counters').doc('sample_transactions');
          int nextSa = await _db.runTransaction<int>((transaction) async {
            final snap = await transaction.get(saCounterRef);
            int current = 54;
            if (snap.exists) {
              current = snap.data()?['lastSaNo'] ?? 54;
            }
            final next = current + 1;
            transaction.set(saCounterRef, {'lastSaNo': next});
            return next;
          });
          docId = 'SA$nextSa';
        } catch (e) {
          debugPrint("SA counter transaction error: $e, using fallback");
          docId = await peekNextInvoiceNo(type: 'SA');
        }
      }
    } else {
      try {
        final counterRef = _db.collection('counters').doc('transactions');
        int nextNo = await _db.runTransaction<int>((transaction) async {
          final counterSnapshot = await transaction.get(counterRef);
          int currentNo = 180;
          if (counterSnapshot.exists) {
            currentNo = counterSnapshot.data()?['lastInvoiceNo'] ?? currentNo;
          }
          final next = currentNo + 1;
          transaction.set(counterRef, {'lastInvoiceNo': next});
          return next;
        });
        docId = nextNo.toString();
      } catch (e) {
        debugPrint("PO counter transaction error: $e, using fallback");
        docId = await peekNextInvoiceNo(type: 'PO');
      }
    }

    final trDoc = model_tr.Transaction(
      invoiceNo: docId,
      customerId: customerId,
      customerName: customerName,
      aliasName: aliasName,
      date: now,
      deliveryDate: null,
      city: city,
      province: province,
      country: country,
      items: items,
      grandTotal: grandTotal,
      note: note,
      status: 'PENDING',
      statusTransfer: 'UNPAID',
      createdBy: createdBy,
      createdAt: now,
    );

    // Save transaction (status PENDING = no stock deduction, no ERP sync)
    await _db.collection('transactions').doc(docId).set(trDoc.toMap());

    // Save idempotency key to prevent duplicate creation
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      try {
        await _db.collection('idempotency_keys').doc(idempotencyKey).set({
          'invoiceNo': docId,
          'createdAt': Timestamp.fromDate(now),
        });
      } catch (e) {
        debugPrint("Idempotency key save bypass/error: $e");
      }
    }

    return trDoc;
  }

  Future<void> updateTransactionTransferStatus(dynamic invoiceNo, String status, DateTime? transferDate) async {
    await _db.collection('transactions').doc(invoiceNo.toString()).update({
      'statusTransfer': status,
      'transferDate': transferDate != null ? Timestamp.fromDate(transferDate) : null,
    });
  }

  Future<void> updateTransactionDeliveryDate(dynamic invoiceNo, DateTime deliveryDate) async {
    await _db.collection('transactions').doc(invoiceNo.toString()).update({
      'deliveryDate': Timestamp.fromDate(deliveryDate),
    });
  }

  // Helper to apply items to ERP summary in a transaction
  void _addToErpSummary(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> erpRef,
    DocumentSnapshot<Map<String, dynamic>>? erpSnap,
    model_tr.Transaction tr,
    String monthYear,
  ) {
    Map<String, dynamic> erpData = (erpSnap != null && erpSnap.exists)
        ? Map<String, dynamic>.from(erpSnap.data()!)
        : {
            'monthYear': monthYear,
            'customerId': tr.customerId,
            'customerName': tr.aliasName,
            'products': {},
            'totalIncome': 0.0,
            'invoices': [],
          };

    double currentIncome = (erpData['totalIncome'] ?? 0.0).toDouble();
    erpData['totalIncome'] = currentIncome + tr.grandTotal;

    Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});
    for (var item in tr.items) {
      Map<String, dynamic> prodRecord = productsMap[item.productId] != null
          ? Map<String, dynamic>.from(productsMap[item.productId])
          : {'pcs': 0.0, 'kg': 0.0};
      double currentPcs = (prodRecord['pcs'] ?? 0.0).toDouble();
      double currentKg = (prodRecord['kg'] ?? 0.0).toDouble();
      prodRecord['pcs'] = currentPcs + item.qty;
      prodRecord['kg'] = currentKg + item.weightKg;
      productsMap[item.productId] = prodRecord;
    }
    erpData['products'] = productsMap;

    // Track invoices list
    List<dynamic> invoices = List<dynamic>.from(erpData['invoices'] ?? []);
    // Remove existing entry for this invoice (if re-adding)
    invoices.removeWhere((inv) => inv['invoiceNo'] == tr.invoiceNo);
    // Add invoice with items breakdown
    invoices.add({
      'invoiceNo': tr.invoiceNo,
      'grandTotal': tr.grandTotal,
      'date': Timestamp.fromDate(tr.date),
      'items': tr.items.map((item) => {
        'productId': item.productId,
        'productName': item.productName,
        'qty': item.qty,
        'weightKg': item.weightKg,
        'subtotal': item.subtotal,
        'isBonus': item.isBonus,
      }).toList(),
    });
    erpData['invoices'] = invoices;

    transaction.set(erpRef, erpData);
  }

  // Helper to remove items from ERP summary in a transaction
  void _removeFromErpSummary(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> erpRef,
    DocumentSnapshot<Map<String, dynamic>> erpSnap,
    model_tr.Transaction tr,
  ) {
    if (!erpSnap.exists) return;
    Map<String, dynamic> erpData = Map<String, dynamic>.from(erpSnap.data()!);
    double income = (erpData['totalIncome'] ?? 0.0).toDouble();
    erpData['totalIncome'] = (income - tr.grandTotal).clamp(0.0, double.infinity);

    Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});
    for (var item in tr.items) {
      if (productsMap.containsKey(item.productId)) {
        Map<String, dynamic> prodRecord = Map<String, dynamic>.from(productsMap[item.productId]);
        double currentPcs = (prodRecord['pcs'] ?? 0.0).toDouble();
        double currentKg = (prodRecord['kg'] ?? 0.0).toDouble();
        prodRecord['pcs'] = currentPcs - item.qty;
        prodRecord['kg'] = currentKg - item.weightKg;
        if (prodRecord['pcs'] <= 0 && prodRecord['kg'] <= 0) {
          productsMap.remove(item.productId);
        } else {
          productsMap[item.productId] = prodRecord;
        }
      }
    }
    erpData['products'] = productsMap;

    // Remove invoice from invoices list
    List<dynamic> invoices = List<dynamic>.from(erpData['invoices'] ?? []);
    invoices.removeWhere((inv) => inv['invoiceNo'] == tr.invoiceNo);
    erpData['invoices'] = invoices;

    transaction.set(erpRef, erpData);
  }

  Future<void> updateTransactionErpStatus(dynamic invoiceNo, DateTime? newErpSyncDate) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);
      if (oldTr.status == 'DIPINDAH' || oldTr.items.isEmpty || oldTr.note.startsWith('DIPINDAH')) {
        throw Exception("Invoice berstatus DIPINDAH tidak dapat di-update ke ERP. Hanya Invoice Tujuan yang disinkronkan ke ERP.");
      }
      final oldSyncDate = oldTr.erpSyncDate;

      final String? oldMonthYear = oldSyncDate != null ? DateFormat('MM-yyyy').format(oldSyncDate) : null;
      final String? newMonthYear = newErpSyncDate != null ? DateFormat('MM-yyyy').format(newErpSyncDate) : null;

      DocumentReference<Map<String, dynamic>>? oldErpRef;
      DocumentSnapshot<Map<String, dynamic>>? oldErpSnap;
      if (oldSyncDate != null && oldMonthYear != null) {
        oldErpRef = _db.collection('erp_summary').doc("${oldMonthYear}_${oldTr.customerId}");
        oldErpSnap = await transaction.get(oldErpRef);
      }

      DocumentReference<Map<String, dynamic>>? newErpRef;
      DocumentSnapshot<Map<String, dynamic>>? newErpSnap;
      if (newErpSyncDate != null && newMonthYear != null) {
        newErpRef = _db.collection('erp_summary').doc("${newMonthYear}_${oldTr.customerId}");
        if (oldErpRef != null && oldErpRef.path == newErpRef.path) {
          newErpSnap = oldErpSnap;
        } else {
          newErpSnap = await transaction.get(newErpRef);
        }
      }

      if (oldErpRef != null && oldErpSnap != null && (newErpRef == null || oldErpRef.path != newErpRef.path)) {
        _removeFromErpSummary(transaction, oldErpRef, oldErpSnap, oldTr);
      }

      if (newErpRef != null && (oldErpRef == null || oldErpRef.path != newErpRef.path)) {
        _addToErpSummary(transaction, newErpRef, newErpSnap, oldTr, newMonthYear!);
      }

      transaction.update(docRef, {
        'erpSyncDate': newErpSyncDate != null ? Timestamp.fromDate(newErpSyncDate) : null,
      });
    });
  }

  Future<List<DocumentReference<Map<String, dynamic>>>> _resolveProductRefs(
    String productId,
    String productName,
  ) async {
    final resolver = await _KodeIndukResolver.create(_db);
    final kInduk = resolver.resolveKodeInduk(productId, productName);
    return resolver.getRefsForKodeInduk(kInduk);
  }

  // Update delivery status (DIKIRIM / PENDING) and deliveryDate with automatic stock deduction/restoration
  Future<void> updateTransactionDeliveryStatus(
    dynamic invoiceNo,
    String newStatus,
    DateTime? newDeliveryDate,
  ) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    // Read initial transaction doc to determine items and old status BEFORE transaction
    final initSnap = await docRef.get();
    if (!initSnap.exists) {
      throw Exception("Transaksi tidak ditemukan!");
    }
    final initTr = model_tr.Transaction.fromMap(initSnap.data()!, initSnap.id);
    final String oldStatus = initTr.status;

    bool stockShouldDecrease = (oldStatus != 'DIKIRIM' && newStatus == 'DIKIRIM');
    bool stockShouldIncrease = (oldStatus == 'DIKIRIM' && newStatus != 'DIKIRIM');

    final resolver = await _KodeIndukResolver.create(_db);

    // Aggregate delta per kodeInduk
    final Map<String, double> deltaPerKodeInduk = {};
    if (stockShouldDecrease) {
      for (var item in initTr.items) {
        final kInduk = resolver.resolveKodeInduk(item.productId, item.productName);
        deltaPerKodeInduk[kInduk] = (deltaPerKodeInduk[kInduk] ?? 0.0) - item.qty;
      }
    } else if (stockShouldIncrease) {
      for (var item in initTr.items) {
        final kInduk = resolver.resolveKodeInduk(item.productId, item.productName);
        deltaPerKodeInduk[kInduk] = (deltaPerKodeInduk[kInduk] ?? 0.0) + item.qty;
      }
    }

    // PRE-CHECK PHYSICAL STOCK SUFFICIENCY BEFORE TRANSACTION
    if (stockShouldDecrease) {
      final List<String> insufficientStockProducts = [];

      for (var entry in deltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final delta = entry.value;
        if (delta < 0) {
          final requiredQty = delta.abs();
          final refs = resolver.getRefsForKodeInduk(kInduk);
          for (var ref in refs) {
            final pSnap = await ref.get();
            if (pSnap.exists) {
              final currentStock = (pSnap.data()?['stock'] ?? 0.0).toDouble();
              if (currentStock < requiredQty) {
                final pName = pSnap.data()?['name'] ?? kInduk;
                insufficientStockProducts.add("• $pName (Stok Ada: ${currentStock.toInt()} pcs, Dibutuhkan: ${requiredQty.toInt()} pcs)");
              }
            }
          }
        }
      }

      if (insufficientStockProducts.isNotEmpty) {
        throw Exception("STOK_TIDAK_CUKUP:\n${insufficientStockProducts.join('\n')}");
      }
    }

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }

      final Map<String, DocumentSnapshot> pSnapshots = {};
      for (var entry in deltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        for (var ref in refs) {
          final pSnap = await transaction.get(ref);
          if (pSnap.exists) pSnapshots[ref.path] = pSnap;
        }
      }

      for (var entry in deltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final delta = entry.value;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        for (var ref in refs) {
          final pSnap = pSnapshots[ref.path];
          if (pSnap != null && pSnap.exists) {
            final data = pSnap.data() as Map<String, dynamic>?;
            final currentStock = (data?['stock'] ?? 0.0).toDouble();
            transaction.update(ref, {'stock': currentStock + delta});
          }
        }
      }

      transaction.update(docRef, {
        'status': newStatus,
        'deliveryDate': newStatus == 'PENDING' ? null : (newDeliveryDate != null ? Timestamp.fromDate(newDeliveryDate) : null),
      });
    });

    // Log stock mutations AFTER transaction succeeds
    if (deltaPerKodeInduk.isNotEmpty) {
      final String mutationType = stockShouldDecrease ? 'KELUAR' : 'RETUR_STATUS';
      final List<StockMutation> mutations = [];

      for (var entry in deltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final delta = entry.value;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        // Get representative product name from first ref
        String pName = kInduk;
        if (refs.isNotEmpty) {
          final pSnap = await refs.first.get();
          if (pSnap.exists) {
            pName = (pSnap.data() as Map<String, dynamic>?)?['name'] ?? kInduk;
          }
        }
        // Get current stock (after mutation) to compute before
        double currentStockAfter = 0;
        if (refs.isNotEmpty) {
          final pSnap = await refs.first.get();
          if (pSnap.exists) {
            currentStockAfter = ((pSnap.data() as Map<String, dynamic>?)?['stock'] ?? 0.0).toDouble();
          }
        }
        final stockBefore = currentStockAfter - delta; // reverse to get before

        mutations.add(StockMutation(
          id: '',
          kodeInduk: kInduk,
          productName: pName,
          type: mutationType,
          qty: delta,
          stockBefore: stockBefore,
          stockAfter: currentStockAfter,
          reference: 'Invoice #${invoiceNo.toString()}',
          customerName: initTr.customerName,
          timestamp: DateTime.now(),
        ));
      }

      await _logStockMutations(mutations);
    }
  }

  // Get ERP summaries for a specific month - reads directly from transactions for 100% accuracy (0 Reads when cached)
  Future<List<Map<String, dynamic>>> getErpSummaries(String monthYear, {List<model_tr.Transaction>? cachedTransactions}) async {
    final Map<String, Map<String, dynamic>> customerErpMap = {};

    List<Map<String, dynamic>> rawTrDataList = [];

    if (cachedTransactions != null && cachedTransactions.isNotEmpty) {
      for (var tr in cachedTransactions) {
        if (tr.erpSyncDate == null) continue;
        final trMonthYear = DateFormat('MM-yyyy').format(tr.erpSyncDate!);
        if (trMonthYear != monthYear) continue;

        rawTrDataList.add({
          'id': tr.invoiceNo,
          'customerId': tr.customerId,
          'customerName': tr.customerName,
          'aliasName': tr.aliasName,
          'erpSyncDate': Timestamp.fromDate(tr.erpSyncDate!),
          'date': Timestamp.fromDate(tr.date),
          'grandTotal': tr.grandTotal,
          'items': tr.items.map((i) => {
            'productId': i.productId,
            'productName': i.productName,
            'qty': i.qty,
            'weightKg': i.weightKg,
            'subtotal': i.subtotal,
            'isBonus': i.isBonus,
          }).toList(),
        });
      }
    } else {
      try {
        final trSnap = await _db.collection('transactions').get(const GetOptions(source: Source.cache));
        if (trSnap.docs.isNotEmpty) {
          for (var doc in trSnap.docs) {
            final data = doc.data();
            final Timestamp? erpTs = data['erpSyncDate'] as Timestamp?;
            if (erpTs == null) continue;
            final erpDate = erpTs.toDate();
            final trMonthYear = DateFormat('MM-yyyy').format(erpDate);
            if (trMonthYear != monthYear) continue;
            data['id'] = doc.id;
            rawTrDataList.add(data);
          }
        }
      } catch (_) {}

      if (rawTrDataList.isEmpty) {
        final trSnap = await _db.collection('transactions').get();
        for (var doc in trSnap.docs) {
          final data = doc.data();
          final Timestamp? erpTs = data['erpSyncDate'] as Timestamp?;
          if (erpTs == null) continue;
          final erpDate = erpTs.toDate();
          final trMonthYear = DateFormat('MM-yyyy').format(erpDate);
          if (trMonthYear != monthYear) continue;
          data['id'] = doc.id;
          rawTrDataList.add(data);
        }
      }
    }

    for (var trData in rawTrDataList) {
      final Timestamp erpTs = trData['erpSyncDate'] as Timestamp;
      final erpDate = erpTs.toDate();

      final customerId = (trData['customerId'] ?? '').toString();
      final customerName = (trData['aliasName'] ?? trData['customerName'] ?? '').toString();
      final invoiceNo = trData['id'] ?? (trData['invoiceNo'] ?? 0);
      final trDate = (trData['date'] as Timestamp?)?.toDate() ?? erpDate;

      final items = (trData['items'] as List<dynamic>?) ?? [];

      if (!customerErpMap.containsKey(customerId)) {
        customerErpMap[customerId] = {
          'monthYear': monthYear,
          'customerId': customerId,
          'customerName': customerName,
          'totalIncome': 0.0,
          'products': <String, Map<String, double>>{},
          'invoices': <Map<String, dynamic>>[],
        };
      }

      final cRecord = customerErpMap[customerId]!;
      final productsMap = cRecord['products'] as Map<String, Map<String, double>>;
      final invoicesList = cRecord['invoices'] as List<Map<String, dynamic>>;

      double calculatedGrandTotal = 0.0;
      final List<Map<String, dynamic>> formattedItems = [];
      for (var item in items) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        final productId = (itemMap['productId'] ?? '').toString();
        final productName = (itemMap['productName'] ?? '').toString();
        final qty = (itemMap['qty'] ?? 0.0).toDouble();
        final weightKg = (itemMap['weightKg'] ?? 0.0).toDouble();
        final subtotal = ((itemMap['subtotal'] ?? 0.0) as num).toDouble().roundToDouble();
        final isBonus = itemMap['isBonus'] == true;

        if (!productsMap.containsKey(productId)) {
          productsMap[productId] = {'pcs': 0.0, 'kg': 0.0};
        }
        productsMap[productId]!['pcs'] = productsMap[productId]!['pcs']! + qty;
        productsMap[productId]!['kg'] = productsMap[productId]!['kg']! + weightKg;

        if (!isBonus) {
          calculatedGrandTotal += subtotal;
        }

        formattedItems.add({
          'productId': productId,
          'productName': productName,
          'qty': qty,
          'weightKg': weightKg,
          'subtotal': subtotal,
          'isBonus': isBonus,
        });
      }

      cRecord['totalIncome'] = (cRecord['totalIncome'] as double) + calculatedGrandTotal;

      invoicesList.add({
        'invoiceNo': invoiceNo,
        'grandTotal': calculatedGrandTotal,
        'date': Timestamp.fromDate(trDate),
        'erpSyncDate': Timestamp.fromDate(erpDate),
        'items': formattedItems,
      });
    }

    try {
      final erpSnap = await _db.collection('erp_summary').where('monthYear', isEqualTo: monthYear).get();
      for (var doc in erpSnap.docs) {
        final data = doc.data();
        final cId = (data['customerId'] ?? '').toString();
        if (cId.isNotEmpty && !customerErpMap.containsKey(cId)) {
          customerErpMap[cId] = data;
        }
      }
    } catch (e) {
      debugPrint("Error fetching erp_summary: $e");
    }

    return customerErpMap.values.toList();
  }

  // Import transaction (with specific invoice number, e.g. "625", "SA1", "SA34")
  Future<void> importTransaction({
    required dynamic invoiceNo,
    required String customerId,
    required String customerName,
    required String aliasName,
    DateTime? date,
    required DateTime deliveryDate,
    required String city,
    required String province,
    required String country,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    required String note,
    required String createdBy,
    String status = 'PENDING',
    String statusTransfer = 'UNPAID',
    DateTime? transferDate,
    DateTime? erpSyncDate,
  }) async {
    final now = DateTime.now();
    final listItems = items.map((e) => model_tr.TransactionItem.fromMap(e)).toList();
    final String docId = invoiceNo.toString();

    final trDoc = model_tr.Transaction(
      invoiceNo: docId,
      customerId: customerId,
      customerName: customerName,
      aliasName: aliasName,
      date: date ?? now,
      deliveryDate: deliveryDate,
      city: city,
      province: province,
      country: country,
      items: listItems,
      grandTotal: grandTotal,
      note: note,
      status: status,
      statusTransfer: statusTransfer,
      transferDate: transferDate,
      erpSyncDate: erpSyncDate,
      createdBy: createdBy,
      createdAt: now,
    );

    // Update lastInvoiceNo counter if imported numeric invoice number is larger
    final int? numericInv = int.tryParse(docId);
    if (numericInv != null) {
      final counterRef = _db.collection('counters').doc('transactions');
      await _db.runTransaction((transaction) async {
        final counterSnapshot = await transaction.get(counterRef);
        int currentNo = 180;
        if (counterSnapshot.exists) {
          currentNo = counterSnapshot.data()?['lastInvoiceNo'] ?? currentNo;
        }
        if (numericInv > currentNo) {
          transaction.set(counterRef, {'lastInvoiceNo': numericInv});
        }
      });
    }

    // Save transaction doc
    await _db.collection('transactions').doc(docId).set(trDoc.toMap());

    // If imported transaction has erpSyncDate set, sync to erp_summary collection
    if (erpSyncDate != null) {
      final String monthYear = DateFormat('MM-yyyy').format(erpSyncDate);
      final erpRef = _db.collection('erp_summary').doc("${monthYear}_${trDoc.customerId}");
      await _db.runTransaction((transaction) async {
        final erpSnap = await transaction.get(erpRef);
        _addToErpSummary(transaction, erpRef, erpSnap, trDoc, monthYear);
      });
    }
  }

  // Move items between two invoices without affecting stock (status DIKIRIM)
  Future<void> moveInvoiceItems({
    required model_tr.Transaction sourceTr,
    required model_tr.Transaction targetTr,
  }) async {
    final sourceRef = _db.collection('transactions').doc(sourceTr.invoiceNo.toString());
    final targetRef = _db.collection('transactions').doc(targetTr.invoiceNo.toString());

    await sourceRef.set(sourceTr.toMap(), SetOptions(merge: true));
    await targetRef.set(targetTr.toMap(), SetOptions(merge: true));
  }

  // Update existing transaction with stock and ERP summary updates
  Future<void> updateTransaction(model_tr.Transaction updatedTr) async {
    final docRef = _db.collection('transactions').doc(updatedTr.invoiceNo.toString());

    // 1. READ OLD TRANSACTION FIRST
    final oldSnapInit = await docRef.get();
    if (!oldSnapInit.exists) {
      throw Exception("Transaksi tidak ditemukan!");
    }
    final oldTr = model_tr.Transaction.fromMap(oldSnapInit.data()!, oldSnapInit.id);

    final bool oldWasDelivered = (oldTr.status == 'DIKIRIM');
    final bool newIsDelivered = (updatedTr.status == 'DIKIRIM');

    // 2. RESOLVE KODE INDUK & CALCULATE NET STOCK DELTA PER KODE INDUK
    final resolver = await _KodeIndukResolver.create(_db);
    final Map<String, double> netStockDeltaPerKodeInduk = {};

    if (oldWasDelivered) {
      for (var item in oldTr.items) {
        final kInduk = resolver.resolveKodeInduk(item.productId, item.productName);
        netStockDeltaPerKodeInduk[kInduk] = (netStockDeltaPerKodeInduk[kInduk] ?? 0.0) + item.qty;
      }
    }

    if (newIsDelivered) {
      for (var item in updatedTr.items) {
        final kInduk = resolver.resolveKodeInduk(item.productId, item.productName);
        netStockDeltaPerKodeInduk[kInduk] = (netStockDeltaPerKodeInduk[kInduk] ?? 0.0) - item.qty;
      }
    }

    // Filter out zero net stock changes
    netStockDeltaPerKodeInduk.removeWhere((key, value) => value == 0.0);

    // PRE-CHECK PHYSICAL STOCK SUFFICIENCY if netStockDelta requires stock deduction (-)
    final List<String> insufficientStockProducts = [];
    for (var entry in netStockDeltaPerKodeInduk.entries) {
      final kInduk = entry.key;
      final delta = entry.value;
      if (delta < 0) {
        final requiredQty = delta.abs();
        final refs = resolver.getRefsForKodeInduk(kInduk);
        for (var ref in refs) {
          final pSnap = await ref.get();
          if (pSnap.exists) {
            final data = pSnap.data() as Map<String, dynamic>?;
            final currentStock = (data?['stock'] ?? 0.0).toDouble();
            if (currentStock < requiredQty) {
              final pName = pSnap.data()?['name'] ?? kInduk;
              insufficientStockProducts.add("• $pName (Stok Ada: ${currentStock.toInt()} pcs, Dibutuhkan: ${requiredQty.toInt()} pcs)");
            }
          }
        }
      }
    }
    if (insufficientStockProducts.isNotEmpty) {
      throw Exception("STOK_TIDAK_CUKUP:\n${insufficientStockProducts.join('\n')}");
    }

    // 3. RUN FIRESTORE TRANSACTION
    await _db.runTransaction((transaction) async {
      // Step A: READ ALL DOCUMENTS FIRST
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }

      // Read product snapshots transactionally
      final Map<String, DocumentSnapshot> pSnapshots = {};
      for (var entry in netStockDeltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        for (var ref in refs) {
          final pSnap = await transaction.get(ref);
          if (pSnap.exists) pSnapshots[ref.path] = pSnap;
        }
      }

      // Read old ERP snap if erpSyncDate was set
      final String? oldMonthYear = oldTr.erpSyncDate != null ? DateFormat('MM-yyyy').format(oldTr.erpSyncDate!) : null;
      DocumentReference<Map<String, dynamic>>? oldErpRef;
      DocumentSnapshot<Map<String, dynamic>>? oldErpSnap;
      if (oldTr.erpSyncDate != null && oldMonthYear != null) {
        oldErpRef = _db.collection('erp_summary').doc("${oldMonthYear}_${oldTr.customerId}");
        oldErpSnap = await transaction.get(oldErpRef);
      }

      // Read new ERP snap if updated erpSyncDate is set
      final String? newMonthYear = updatedTr.erpSyncDate != null ? DateFormat('MM-yyyy').format(updatedTr.erpSyncDate!) : null;
      DocumentReference<Map<String, dynamic>>? newErpRef;
      DocumentSnapshot<Map<String, dynamic>>? newErpSnap;
      if (updatedTr.erpSyncDate != null && newMonthYear != null) {
        newErpRef = _db.collection('erp_summary').doc("${newMonthYear}_${updatedTr.customerId}");
        if (oldErpRef != null && oldErpRef.path == newErpRef.path) {
          newErpSnap = oldErpSnap;
        } else {
          newErpSnap = await transaction.get(newErpRef);
        }
      }

      // Step B: PERFORM ALL WRITES
      // 1) Update stock per kodeInduk
      for (var entry in netStockDeltaPerKodeInduk.entries) {
        final kInduk = entry.key;
        final delta = entry.value;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        for (var ref in refs) {
          final pSnap = pSnapshots[ref.path];
          if (pSnap != null && pSnap.exists) {
            final data = pSnap.data() as Map<String, dynamic>?;
            final currentStock = (data?['stock'] ?? 0.0).toDouble();
            final newStock = currentStock + delta;
            transaction.update(ref, {'stock': newStock});
          }
        }
      }

      // 2) Update ERP Summaries
      if (oldErpRef != null && oldErpSnap != null && (newErpRef == null || oldErpRef.path != newErpRef.path)) {
        _removeFromErpSummary(transaction, oldErpRef, oldErpSnap, oldTr);
      }

      if (newErpRef != null && (oldErpRef == null || oldErpRef.path != newErpRef.path)) {
        _addToErpSummary(transaction, newErpRef, newErpSnap, updatedTr, newMonthYear!);
      }

      // 3) Write updated transaction doc
      final Map<String, dynamic> data = updatedTr.toMap();
      data['erpSyncDate'] = updatedTr.erpSyncDate != null 
          ? Timestamp.fromDate(updatedTr.erpSyncDate!) 
          : null;
      transaction.set(docRef, data);
    });
  }


  // Delete transaction (with stock restoration if DIKIRIM)
  Future<void> deleteTransaction(dynamic invoiceNo) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    final initSnap = await docRef.get();
    if (!initSnap.exists) {
      throw Exception("Transaksi tidak ditemukan!");
    }
    final initTr = model_tr.Transaction.fromMap(initSnap.data()!, initSnap.id);
    final bool wasDelivered = (initTr.status == 'DIKIRIM');

    final resolver = await _KodeIndukResolver.create(_db);

    // Aggregate qty per kodeInduk for stock restoration
    final Map<String, double> totalQtyPerKodeInduk = {};
    if (wasDelivered) {
      for (var item in initTr.items) {
        final kInduk = resolver.resolveKodeInduk(item.productId, item.productName);
        totalQtyPerKodeInduk[kInduk] = (totalQtyPerKodeInduk[kInduk] ?? 0.0) + item.qty;
      }
    }

    await _db.runTransaction((transaction) async {
      // 1. READ ALL DOCUMENTS FIRST
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);

      // Read product snapshots transactionally
      final Map<String, DocumentSnapshot> pSnapshots = {};
      if (wasDelivered) {
        for (var entry in totalQtyPerKodeInduk.entries) {
          final kInduk = entry.key;
          final refs = resolver.getRefsForKodeInduk(kInduk);
          for (var ref in refs) {
            final pSnap = await transaction.get(ref);
            if (pSnap.exists) pSnapshots[ref.path] = pSnap;
          }
        }
      }

      // Read ERP snap if erpSyncDate was set
      final String? monthYear = oldTr.erpSyncDate != null ? DateFormat('MM-yyyy').format(oldTr.erpSyncDate!) : null;
      DocumentReference<Map<String, dynamic>>? erpRef;
      DocumentSnapshot<Map<String, dynamic>>? erpSnap;
      if (oldTr.erpSyncDate != null && monthYear != null) {
        erpRef = _db.collection('erp_summary').doc("${monthYear}_${oldTr.customerId}");
        erpSnap = await transaction.get(erpRef);
      }

      // 2. EXECUTE WRITES
      // Restore stock per kodeInduk
      if (wasDelivered) {
        for (var entry in totalQtyPerKodeInduk.entries) {
          final kInduk = entry.key;
          final totalQty = entry.value;
          final refs = resolver.getRefsForKodeInduk(kInduk);
          for (var ref in refs) {
            final pSnap = pSnapshots[ref.path];
            if (pSnap != null && pSnap.exists) {
              final data = pSnap.data() as Map<String, dynamic>?;
            final currentStock = (data?['stock'] ?? 0.0).toDouble();
              transaction.update(ref, {'stock': currentStock + totalQty});
            }
          }
        }
      }

      // Remove from ERP summary
      if (erpRef != null && erpSnap != null && erpSnap.exists) {
        _removeFromErpSummary(transaction, erpRef, erpSnap, oldTr);
      }

      // Delete the transaction document
      transaction.delete(docRef);
    });

    // Log stock mutations AFTER transaction succeeds (for deleted DIKIRIM invoices)
    if (wasDelivered && totalQtyPerKodeInduk.isNotEmpty) {
      final List<StockMutation> mutations = [];

      for (var entry in totalQtyPerKodeInduk.entries) {
        final kInduk = entry.key;
        final totalQty = entry.value;
        final refs = resolver.getRefsForKodeInduk(kInduk);
        String pName = kInduk;
        double currentStockAfter = 0;
        if (refs.isNotEmpty) {
          final pSnap = await refs.first.get();
          if (pSnap.exists) {
            final data = pSnap.data() as Map<String, dynamic>?;
            pName = data?['name'] ?? kInduk;
            currentStockAfter = (data?['stock'] ?? 0.0).toDouble();
          }
        }
        final stockBefore = currentStockAfter - totalQty;

        mutations.add(StockMutation(
          id: '',
          kodeInduk: kInduk,
          productName: pName,
          type: 'HAPUS_INVOICE',
          qty: totalQty,
          stockBefore: stockBefore,
          stockAfter: currentStockAfter,
          reference: 'Hapus Invoice #${invoiceNo.toString()}',
          customerName: initTr.customerName,
          timestamp: DateTime.now(),
        ));
      }

      await _logStockMutations(mutations);
    }
  }

  // ==========================================
  // STAFF & ATTENDANCE MANAGEMENT
  // ==========================================

  Stream<List<Staff>> streamStaff() {
    return _db.collection('staff').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Staff.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> saveStaff(Staff staff) async {
    final docRef = staff.id.isNotEmpty
        ? _db.collection('staff').doc(staff.id)
        : _db.collection('staff').doc();
    await docRef.set(staff.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteStaff(String staffId) async {
    await _db.collection('staff').doc(staffId).delete();
  }

  Stream<List<AttendanceRecord>> streamAttendanceByMonthYear(String monthYear) {
    return _db
        .collection('attendance')
        .where('monthYear', isEqualTo: monthYear)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AttendanceRecord.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> saveAttendanceRecord(AttendanceRecord record) async {
    await _db.collection('attendance').doc(record.id).set(record.toMap());
  }

  Future<void> deleteAttendanceRecord(String id) async {
    await _db.collection('attendance').doc(id).delete();
  }

  Future<String?> getHrdPhone() async {
    try {
      final doc = await _db.collection('settings').doc('attendance').get();
      if (doc.exists && doc.data()?['hrdPhone'] != null) {
        return doc.data()!['hrdPhone'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveHrdPhone(String phone) async {
    try {
      await _db.collection('settings').doc('attendance').set(
        {'hrdPhone': phone},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  // ==========================================
  // TRANSACTION RETURNS CRUD
  // ==========================================

  Future<void> saveTransactionReturn(TransactionReturn retData) async {
    final batch = _db.batch();

    final retRef = _db.collection('returns').doc();
    batch.set(retRef, retData.toMap());

    final trRef = _db.collection('transactions').doc(retData.invoiceNo);
    batch.update(trRef, {
      'returnAmount': FieldValue.increment(retData.totalReturnAmount),
      'hasReturn': true,
    });

    for (final item in retData.items) {
      if (item.condition == 'BAGUS' && item.qtyReturned > 0) {
        final prodRef = _db.collection('products').doc(item.productId);
        batch.update(prodRef, {
          'stock': FieldValue.increment(item.qtyReturned),
        });
      }
    }

    await batch.commit();
  }

  Stream<List<TransactionReturn>> streamReturns() {
    return _db.collection('returns').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TransactionReturn.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // ==========================================
  // OPERATIONAL INVOICES (DEVELOPER ONLY)
  // ==========================================

  Stream<List<OperationalInvoice>> streamOperationalInvoices() {
    return _db
        .collection('operational_invoices')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => OperationalInvoice.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> saveOperationalInvoice(OperationalInvoice invoice) async {
    final docRef = invoice.id.isNotEmpty
        ? _db.collection('operational_invoices').doc(invoice.id)
        : _db.collection('operational_invoices').doc();
    await docRef.set(invoice.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteOperationalInvoice(String id) async {
    await _db.collection('operational_invoices').doc(id).delete();
  }

  // ==========================================
  // OPERATIONAL CATEGORIES CRUD (DYNAMIC)
  // ==========================================

  Stream<List<OperationalCategory>> streamOperationalCategories() {
    return _db.collection('operational_categories').snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => OperationalCategory.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> saveOperationalCategory(OperationalCategory category) async {
    final docRef = category.id.isNotEmpty
        ? _db.collection('operational_categories').doc(category.id)
        : _db.collection('operational_categories').doc();
    await docRef.set(category.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteOperationalCategory(String id) async {
    await _db.collection('operational_categories').doc(id).delete();
  }

  // ==========================================
  // OPERATIONAL PAYMENT METHODS CRUD (DYNAMIC)
  // ==========================================

  Stream<List<OperationalPaymentMethod>> streamOperationalPaymentMethods() {
    return _db.collection('operational_payment_methods').snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => OperationalPaymentMethod.fromMap(doc.data(), doc.id))
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> saveOperationalPaymentMethod(OperationalPaymentMethod method) async {
    final docRef = method.id.isNotEmpty
        ? _db.collection('operational_payment_methods').doc(method.id)
        : _db.collection('operational_payment_methods').doc();
    await docRef.set(method.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteOperationalPaymentMethod(String id) async {
    await _db.collection('operational_payment_methods').doc(id).delete();
  }

  Future<void> seedDefaultOperationalCategoriesIfEmpty() async {
    final snap = await _db.collection('operational_categories').get();
    if (snap.docs.isEmpty) {
      final defaults = [
        'Maintenance & Upgrade Server (Firebase / Cloud)',
        'Pengembangan & Biaya Program (App Dev)',
        'Domain & Cloud Infrastructure',
        'Biaya Operasional Maintenance Rutin',
        'Lainnya',
      ];
      final batch = _db.batch();
      for (var name in defaults) {
        final ref = _db.collection('operational_categories').doc();
        batch.set(ref, {
          'name': name,
          'description': 'Kategori bawaan sistem',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> seedDefaultOperationalPaymentMethodsIfEmpty() async {
    final snap = await _db.collection('operational_payment_methods').get();
    if (snap.docs.isEmpty) {
      final defaults = [
        'DANA / E-Wallet',
        'Transfer Bank (BCA/Mandiri)',
        'Kas / Cash',
        'Lainnya',
      ];
      final batch = _db.batch();
      for (var name in defaults) {
        final ref = _db.collection('operational_payment_methods').doc();
        batch.set(ref, {
          'name': name,
          'description': 'Metode pembayaran bawaan sistem',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  // ==========================================
  // WA CONTACTS (PERSISTENT CONTACT LIST FOR WHATSAPP SHARE)
  // ==========================================
  Stream<List<WaContact>> streamWaContacts() {
    return _db.collection('wa_contacts').orderBy('name').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => WaContact.fromFirestore(doc)).toList();
    });
  }

  Future<void> saveWaContact(WaContact contact) async {
    final ref = contact.id.isNotEmpty
        ? _db.collection('wa_contacts').doc(contact.id)
        : _db.collection('wa_contacts').doc();
    await ref.set(contact.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteWaContact(String id) async {
    await _db.collection('wa_contacts').doc(id).delete();
  }

  Future<void> seedDefaultWaContactsIfEmpty() async {
    final snap = await _db.collection('wa_contacts').get();
    if (snap.docs.isEmpty) {
      final defaults = [
        {'name': 'Bu Silvi', 'phone': '08123456789', 'role': 'Admin ERP', 'template': 'siang Bu Silvi'},
      ];
      final batch = _db.batch();
      for (var c in defaults) {
        final ref = _db.collection('wa_contacts').doc();
        batch.set(ref, {
          'name': c['name'],
          'phone': c['phone'],
          'role': c['role'],
          'template': c['template'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  // ==========================================
  // MONTHLY TARGETS (TARGET BULANAN PER-AREA/PERIODE)
  // ==========================================

  Stream<double> streamMonthlyTarget(String monthYear, {double defaultTarget = 310947810.0}) {
    final cleanMonth = monthYear.trim();
    if (cleanMonth.isEmpty || cleanMonth == 'SEMUA') {
      return Stream.value(defaultTarget);
    }
    return _db.collection('monthly_targets').doc(cleanMonth).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final val = snapshot.data()!['targetAmount'];
        if (val is num) return val.toDouble();
      }
      return defaultTarget;
    });
  }

  Future<double> getMonthlyTarget(String monthYear, {double defaultTarget = 310947810.0}) async {
    final cleanMonth = monthYear.trim();
    if (cleanMonth.isEmpty || cleanMonth == 'SEMUA') return defaultTarget;
    try {
      final doc = await _db.collection('monthly_targets').doc(cleanMonth).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['targetAmount'];
        if (val is num) return val.toDouble();
      }
    } catch (_) {}
    return defaultTarget;
  }

  Stream<Map<String, double>> streamAllMonthlyTargets({double defaultTarget = 310947810.0}) {
    return _db.collection('monthly_targets').snapshots().map((snapshot) {
      final Map<String, double> result = {};
      for (var doc in snapshot.docs) {
        final val = doc.data()['targetAmount'];
        if (val is num) {
          result[doc.id] = val.toDouble();
        }
      }
      return result;
    });
  }

  Future<Map<String, double>> getAllMonthlyTargets() async {
    try {
      final snapshot = await _db.collection('monthly_targets').get();
      final Map<String, double> result = {};
      for (var doc in snapshot.docs) {
        final val = doc.data()['targetAmount'];
        if (val is num) {
          result[doc.id] = val.toDouble();
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> setMonthlyTarget(String monthYear, double targetAmount, {String updatedBy = 'LUCIFAX (DEV)'}) async {
    final cleanMonth = monthYear.trim();
    if (cleanMonth.isEmpty || cleanMonth == 'SEMUA') return;
    await _db.collection('monthly_targets').doc(cleanMonth).set({
      'monthYear': cleanMonth,
      'targetAmount': targetAmount,
      'area': 'JAWA TENGAH',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    }, SetOptions(merge: true));
  }
}

class _KodeIndukResolver {
  final Map<String, List<DocumentReference<Map<String, dynamic>>>> kodeIndukToRefs = {};
  final Map<String, String> productIdToKodeInduk = {};
  final Map<String, String> productNameToKodeInduk = {};

  static Future<_KodeIndukResolver> create(FirebaseFirestore db) async {
    final resolver = _KodeIndukResolver();
    final allProdsQuery = await db.collection('products').get();

    for (var d in allProdsQuery.docs) {
      final docId = d.id.trim();
      final data = d.data();
      final name = (data['name'] ?? '').toString().trim();
      final rawKodeInduk = (data['kodeInduk'] ?? '').toString().trim();
      final kodeInduk = rawKodeInduk.isNotEmpty ? rawKodeInduk : docId;

      if (docId.isNotEmpty) {
        resolver.productIdToKodeInduk[docId.toLowerCase()] = kodeInduk;
      }
      if (name.isNotEmpty) {
        resolver.productNameToKodeInduk[name.toLowerCase()] = kodeInduk;
      }

      resolver.kodeIndukToRefs.putIfAbsent(kodeInduk, () => []).add(d.reference);
    }
    return resolver;
  }

  String resolveKodeInduk(String productId, String productName) {
    final cleanId = productId.trim().toLowerCase();
    final cleanName = productName.trim().toLowerCase();

    if (cleanId.isNotEmpty && productIdToKodeInduk.containsKey(cleanId)) {
      return productIdToKodeInduk[cleanId]!;
    }
    if (cleanName.isNotEmpty && productNameToKodeInduk.containsKey(cleanName)) {
      return productNameToKodeInduk[cleanName]!;
    }
    return productId.trim().isNotEmpty ? productId.trim() : productName.trim();
  }

  List<DocumentReference<Map<String, dynamic>>> getRefsForKodeInduk(String kodeInduk) {
    return kodeIndukToRefs[kodeInduk] ?? [];
  }
}
