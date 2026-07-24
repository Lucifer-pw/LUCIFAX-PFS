import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/staff.dart';
import '../models/attendance_record.dart';
import '../models/transaction.dart' as model_tr;
import 'package:intl/intl.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  Future<void> saveProduct(Product product) async {
    await _db.collection('products').doc(product.id).set(product.toMap());

    if (product.kodeInduk.isNotEmpty) {
      final query = await _db
          .collection('products')
          .where('kodeInduk', isEqualTo: product.kodeInduk)
          .get();

      if (query.docs.length > 1) {
        double targetStock = product.stock;
        for (var doc in query.docs) {
          final sStock = (doc.data()['stock'] ?? 0.0).toDouble();
          if (sStock > targetStock) targetStock = sStock;
        }

        final batch = _db.batch();
        for (var doc in query.docs) {
          batch.update(doc.reference, {'stock': targetStock});
        }
        await batch.commit();
      }
    }
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
        final snap = await _db.collection('transactions').get();
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
  }) async {
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

  // Update delivery status (DIKIRIM / PENDING) and deliveryDate with automatic stock deduction/restoration
  Future<void> updateTransactionDeliveryStatus(
    dynamic invoiceNo,
    String newStatus,
    DateTime? newDeliveryDate,
  ) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. READ ALL DOCUMENTS FIRST (NO WRITES BEFORE ALL GETS ARE DONE)
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);
      final String oldStatus = oldTr.status;

      bool stockShouldDecrease = (oldStatus != 'DIKIRIM' && newStatus == 'DIKIRIM');
      bool stockShouldIncrease = (oldStatus == 'DIKIRIM' && newStatus != 'DIKIRIM');

      // Read product snapshots for all items and their variants
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> productSnaps = {};
      final Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> variantSnaps = {};

      if (stockShouldDecrease || stockShouldIncrease) {
        for (var item in oldTr.items) {
          final prodRef = _db.collection('products').doc(item.productId);
          final snap = await transaction.get(prodRef);
          productSnaps[item.productId] = snap;

          if (snap.exists) {
            final parentKodeInduk = snap.data()?['kodeInduk'] ?? item.productId;
            final query = await _db
                .collection('products')
                .where('kodeInduk', isEqualTo: parentKodeInduk)
                .get();
            final List<DocumentSnapshot<Map<String, dynamic>>> list = [];
            for (var doc in query.docs) {
              list.add(await transaction.get(doc.reference));
            }
            variantSnaps[item.productId] = list;
          }
        }
      }

      // 2. Aggregate qty per productId (handles duplicate productIds like normal + bonus items)
      final Map<String, double> totalQtyPerProduct = {};
      for (var item in oldTr.items) {
        totalQtyPerProduct[item.productId] = (totalQtyPerProduct[item.productId] ?? 0.0) + item.qty;
      }

      // 3. EXECUTE ALL WRITES (Physical Stock Deduction / Restoration)
      if (stockShouldDecrease) {
        for (var entry in totalQtyPerProduct.entries) {
          final productId = entry.key;
          final totalQty = entry.value;
          final vars = variantSnaps[productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock - totalQty});
              }
            }
          } else {
            final prodSnap = productSnaps[productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock - totalQty});
            }
          }
        }
      } else if (stockShouldIncrease) {
        for (var entry in totalQtyPerProduct.entries) {
          final productId = entry.key;
          final totalQty = entry.value;
          final vars = variantSnaps[productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock + totalQty});
              }
            }
          } else {
            final prodSnap = productSnaps[productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock + totalQty});
            }
          }
        }
      }

      transaction.update(docRef, {
        'status': newStatus,
        'deliveryDate': newStatus == 'PENDING' ? null : (newDeliveryDate != null ? Timestamp.fromDate(newDeliveryDate) : null),
      });
    });
  }

  // Get ERP summaries for a specific month - reads directly from transactions for 100% accuracy
  Future<List<Map<String, dynamic>>> getErpSummaries(String monthYear) async {
    final trSnap = await _db.collection('transactions').get();
    
    final Map<String, Map<String, dynamic>> customerErpMap = {};

    for (var doc in trSnap.docs) {
      final trData = doc.data();
      final Timestamp? erpTs = trData['erpSyncDate'] as Timestamp?;
      if (erpTs == null) continue; // EXCLUDE any transaction where status is BELUM ERP!

      final erpDate = erpTs.toDate();
      final trMonthYear = DateFormat('MM-yyyy').format(erpDate);
      if (trMonthYear != monthYear) continue;

      final customerId = (trData['customerId'] ?? '').toString();
      final customerName = (trData['aliasName'] ?? trData['customerName'] ?? '').toString();
      final invoiceNo = int.tryParse(doc.id) ?? (trData['invoiceNo'] ?? 0);
      final grandTotal = (trData['grandTotal'] ?? 0.0).toDouble();
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
        'items': formattedItems,
      });
    }

    try {
      final erpSnap = await _db.collection('erp_summary').get();
      for (var doc in erpSnap.docs) {
        final data = doc.data();
        final docMonthYear = data['monthYear']?.toString() ?? '';
        if (docMonthYear == monthYear || doc.id.startsWith('${monthYear}_')) {
          final cId = (data['customerId'] ?? '').toString();
          if (cId.isNotEmpty && !customerErpMap.containsKey(cId)) {
            customerErpMap[cId] = data;
          }
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

  // Update existing transaction with stock and ERP summary updates
  Future<void> updateTransaction(model_tr.Transaction updatedTr) async {
    final docRef = _db.collection('transactions').doc(updatedTr.invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. READ ALL DOCUMENTS FIRST
      final oldSnap = await transaction.get(docRef);
      if (!oldSnap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(oldSnap.data()!, oldSnap.id);

      final bool oldWasDelivered = (oldTr.status == 'DIKIRIM');
      final bool newIsDelivered = (updatedTr.status == 'DIKIRIM');

      // Read old product snaps and their variants if old status was DIKIRIM
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> oldProductSnaps = {};
      final Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> oldVariantSnaps = {};
      if (oldWasDelivered) {
        for (var item in oldTr.items) {
          final prodRef = _db.collection('products').doc(item.productId);
          final snap = await transaction.get(prodRef);
          oldProductSnaps[item.productId] = snap;
          if (snap.exists) {
            final parentKodeInduk = snap.data()?['kodeInduk'] ?? item.productId;
            final query = await _db.collection('products').where('kodeInduk', isEqualTo: parentKodeInduk).get();
            final List<DocumentSnapshot<Map<String, dynamic>>> list = [];
            for (var doc in query.docs) {
              list.add(await transaction.get(doc.reference));
            }
            oldVariantSnaps[item.productId] = list;
          }
        }
      }

      // Read new product snaps and their variants if new status is DIKIRIM
      final Map<String, DocumentSnapshot<Map<String, dynamic>>> newProductSnaps = {};
      final Map<String, List<DocumentSnapshot<Map<String, dynamic>>>> newVariantSnaps = {};
      if (newIsDelivered) {
        for (var item in updatedTr.items) {
          final prodRef = _db.collection('products').doc(item.productId);
          final snap = await transaction.get(prodRef);
          newProductSnaps[item.productId] = snap;
          if (snap.exists) {
            final parentKodeInduk = snap.data()?['kodeInduk'] ?? item.productId;
            final query = await _db.collection('products').where('kodeInduk', isEqualTo: parentKodeInduk).get();
            final List<DocumentSnapshot<Map<String, dynamic>>> list = [];
            for (var doc in query.docs) {
              list.add(await transaction.get(doc.reference));
            }
            newVariantSnaps[item.productId] = list;
          }
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

      // 2. NOW PERFORM ALL WRITES
      // Aggregate qty per productId for old items (handles duplicate productIds like normal + bonus)
      if (oldWasDelivered) {
        final Map<String, double> oldTotalQty = {};
        for (var item in oldTr.items) {
          oldTotalQty[item.productId] = (oldTotalQty[item.productId] ?? 0.0) + item.qty;
        }
        for (var entry in oldTotalQty.entries) {
          final productId = entry.key;
          final totalQty = entry.value;
          final vars = oldVariantSnaps[productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock + totalQty});
              }
            }
          } else {
            final prodSnap = oldProductSnaps[productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock + totalQty});
            }
          }
        }
      }

      if (oldErpRef != null && oldErpSnap != null && (newErpRef == null || oldErpRef.path != newErpRef.path)) {
        _removeFromErpSummary(transaction, oldErpRef, oldErpSnap, oldTr);
      }

      // Aggregate qty per productId for new items (handles duplicate productIds like normal + bonus)
      if (newIsDelivered) {
        final Map<String, double> newTotalQty = {};
        for (var item in updatedTr.items) {
          newTotalQty[item.productId] = (newTotalQty[item.productId] ?? 0.0) + item.qty;
        }
        for (var entry in newTotalQty.entries) {
          final productId = entry.key;
          final totalQty = entry.value;
          final vars = newVariantSnaps[productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock - totalQty});
              }
            }
          } else {
            final prodSnap = newProductSnaps[productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock - totalQty});
            }
          }
        }
      }

      if (newErpRef != null && (oldErpRef == null || oldErpRef.path != newErpRef.path)) {
        _addToErpSummary(transaction, newErpRef, newErpSnap, updatedTr, newMonthYear!);
      }

      // Write updated transaction doc
      final Map<String, dynamic> data = updatedTr.toMap();
      data['erpSyncDate'] = updatedTr.erpSyncDate != null 
          ? Timestamp.fromDate(updatedTr.erpSyncDate!) 
          : null;
      transaction.set(docRef, data);
    });
  }

  // Delete transaction
  Future<void> deleteTransaction(dynamic invoiceNo) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. READ ALL DOCUMENTS FIRST
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);

      // Read ERP snap if erpSyncDate was set
      final String? monthYear = oldTr.erpSyncDate != null ? DateFormat('MM-yyyy').format(oldTr.erpSyncDate!) : null;
      DocumentReference<Map<String, dynamic>>? erpRef;
      DocumentSnapshot<Map<String, dynamic>>? erpSnap;
      if (oldTr.erpSyncDate != null && monthYear != null) {
        erpRef = _db.collection('erp_summary').doc("${monthYear}_${oldTr.customerId}");
        erpSnap = await transaction.get(erpRef);
      }

      // 2. EXECUTE WRITES
      if (erpRef != null && erpSnap != null && erpSnap.exists) {
        _removeFromErpSummary(transaction, erpRef, erpSnap, oldTr);
      }

      // Delete the transaction document
      transaction.delete(docRef);
    });
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
}
