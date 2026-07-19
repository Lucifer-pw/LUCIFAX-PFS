import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/customer.dart';
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

    // Sync stock across all variants sharing the same kodeInduk
    final query = await _db
        .collection('products')
        .where('kodeInduk', isEqualTo: product.kodeInduk)
        .get();

    if (query.docs.length > 1) {
      final batch = _db.batch();
      for (var doc in query.docs) {
        if (doc.id != product.id) {
          batch.update(doc.reference, {'stock': product.stock});
        }
      }
      await batch.commit();
    }
  }

  Future<void> deleteProduct(String id) async {
    await _db.collection('products').doc(id).delete();
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

  // Save transaction with Auto-Increment Invoice Number & ERP update inside a Firestore Transaction
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
  }) async {
    final counterRef = _db.collection('counters').doc('transactions');
    final now = DateTime.now();

    // Use a transaction to ensure atomic invoice increments
    int newInvoiceNo = await _db.runTransaction<int>((transaction) async {
      final counterSnapshot = await transaction.get(counterRef);
      int currentNo = 180; // Starting invoice offset from VBA data
      if (counterSnapshot.exists) {
        currentNo = counterSnapshot.data()?['lastInvoiceNo'] ?? currentNo;
      }
      final nextNo = currentNo + 1;
      transaction.set(counterRef, {'lastInvoiceNo': nextNo});
      return nextNo;
    });

    final docId = newInvoiceNo.toString();
    final trDoc = model_tr.Transaction(
      invoiceNo: newInvoiceNo,
      customerId: customerId,
      customerName: customerName,
      aliasName: aliasName,
      date: now,
      deliveryDate: deliveryDate,
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

  Future<void> updateTransactionTransferStatus(int invoiceNo, String status, DateTime? transferDate) async {
    await _db.collection('transactions').doc(invoiceNo.toString()).update({
      'statusTransfer': status,
      'transferDate': transferDate != null ? Timestamp.fromDate(transferDate) : null,
    });
  }

  Future<void> updateTransactionDeliveryDate(int invoiceNo, DateTime deliveryDate) async {
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
    transaction.set(erpRef, erpData);
  }

  Future<void> updateTransactionErpStatus(int invoiceNo, DateTime? newErpSyncDate) async {
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
    int invoiceNo,
    String newStatus,
    DateTime newDeliveryDate,
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

      // 2. EXECUTE ALL WRITES (Physical Stock Deduction / Restoration)
      if (stockShouldDecrease) {
        for (var item in oldTr.items) {
          final vars = variantSnaps[item.productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock - item.qty});
              }
            }
          } else {
            final prodSnap = productSnaps[item.productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock - item.qty});
            }
          }
        }
      } else if (stockShouldIncrease) {
        for (var item in oldTr.items) {
          final vars = variantSnaps[item.productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock + item.qty});
              }
            }
          } else {
            final prodSnap = productSnaps[item.productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock + item.qty});
            }
          }
        }
      }

      transaction.update(docRef, {
        'status': newStatus,
        'deliveryDate': Timestamp.fromDate(newDeliveryDate),
      });
    });
  }

  // Get ERP summaries for a specific month
  Future<List<Map<String, dynamic>>> getErpSummaries(String monthYear) async {
    final snap = await _db
        .collection('erp_summary')
        .where('monthYear', isEqualTo: monthYear)
        .get();
    return snap.docs.map((doc) => doc.data()).toList();
  }

  // Import transaction (with specific invoice number)
  Future<void> importTransaction({
    required int invoiceNo,
    required String customerId,
    required String customerName,
    required String aliasName,
    required DateTime deliveryDate,
    required String city,
    required String province,
    required String country,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    required String note,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final listItems = items.map((e) => model_tr.TransactionItem.fromMap(e)).toList();

    final trDoc = model_tr.Transaction(
      invoiceNo: invoiceNo,
      customerId: customerId,
      customerName: customerName,
      aliasName: aliasName,
      date: now,
      deliveryDate: deliveryDate,
      city: city,
      province: province,
      country: country,
      items: listItems,
      grandTotal: grandTotal,
      note: note,
      status: 'PENDING',
      statusTransfer: 'UNPAID',
      createdBy: createdBy,
      createdAt: now,
    );

    // Update lastInvoiceNo counter if imported invoice number is larger
    final counterRef = _db.collection('counters').doc('transactions');
    await _db.runTransaction((transaction) async {
      final counterSnapshot = await transaction.get(counterRef);
      int currentNo = 180;
      if (counterSnapshot.exists) {
        currentNo = counterSnapshot.data()?['lastInvoiceNo'] ?? currentNo;
      }
      if (invoiceNo > currentNo) {
        transaction.set(counterRef, {'lastInvoiceNo': invoiceNo});
      }
    });

    // Save transaction (status PENDING = no stock deduction, no ERP sync)
    await _db.collection('transactions').doc(invoiceNo.toString()).set(trDoc.toMap());
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
      if (oldWasDelivered) {
        for (var item in oldTr.items) {
          final vars = oldVariantSnaps[item.productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock + item.qty});
              }
            }
          } else {
            final prodSnap = oldProductSnaps[item.productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock + item.qty});
            }
          }
        }
      }

      if (oldErpRef != null && oldErpSnap != null && (newErpRef == null || oldErpRef.path != newErpRef.path)) {
        _removeFromErpSummary(transaction, oldErpRef, oldErpSnap, oldTr);
      }

      if (newIsDelivered) {
        for (var item in updatedTr.items) {
          final vars = newVariantSnaps[item.productId];
          if (vars != null) {
            for (var vSnap in vars) {
              if (vSnap.exists) {
                final currentStock = (vSnap.data()?['stock'] ?? 0.0).toDouble();
                transaction.update(vSnap.reference, {'stock': currentStock - item.qty});
              }
            }
          } else {
            final prodSnap = newProductSnaps[item.productId];
            if (prodSnap != null && prodSnap.exists) {
              final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
              transaction.update(prodSnap.reference, {'stock': currentStock - item.qty});
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
  Future<void> deleteTransaction(int invoiceNo) async {
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
}
