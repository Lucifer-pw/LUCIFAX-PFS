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
      status: 'DIKIRIM',
      statusTransfer: 'UNPAID',
      createdBy: createdBy,
      createdAt: now,
    );

    // Save transaction
    await _db.collection('transactions').doc(docId).set(trDoc.toMap());

    // Update Stock in Products and monthly ERP summaries
    final batch = _db.batch();

    // 1. Update Product Stock
    for (var item in items) {
      final productRef = _db.collection('products').doc(item.productId);
      batch.update(productRef, {
        'stock': FieldValue.increment(-item.qty),
      });
    }

    // 2. Sync to ERP Monthly summary
    final monthYear = DateFormat('MM-yyyy').format(deliveryDate);
    final erpRef = _db.collection('erp_summary').doc("${monthYear}_$customerId");

    final erpSnap = await erpRef.get();
    Map<String, dynamic> erpData = erpSnap.exists
        ? erpSnap.data()!
        : {
            'monthYear': monthYear,
            'customerId': customerId,
            'customerName': aliasName, // or customerName
            'products': {},
            'totalIncome': 0.0,
          };

    double currentIncome = (erpData['totalIncome'] ?? 0.0).toDouble();
    erpData['totalIncome'] = currentIncome + grandTotal;

    Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});

    for (var item in items) {
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
    await erpRef.set(erpData);
    await batch.commit();

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
      status: 'DIKIRIM',
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

    await _db.collection('transactions').doc(invoiceNo.toString()).set(trDoc.toMap());

    // Update stocks and ERP
    final batch = _db.batch();
    for (var item in listItems) {
      final productRef = _db.collection('products').doc(item.productId);
      batch.update(productRef, {
        'stock': FieldValue.increment(-item.qty),
      });
    }

    final monthYear = DateFormat('MM-yyyy').format(deliveryDate);
    final erpRef = _db.collection('erp_summary').doc("${monthYear}_$customerId");

    final erpSnap = await erpRef.get();
    Map<String, dynamic> erpData = erpSnap.exists
        ? erpSnap.data()!
        : {
            'monthYear': monthYear,
            'customerId': customerId,
            'customerName': aliasName,
            'products': {},
            'totalIncome': 0.0,
          };

    double currentIncome = (erpData['totalIncome'] ?? 0.0).toDouble();
    erpData['totalIncome'] = currentIncome + grandTotal;

    Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});

    for (var item in listItems) {
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
    await erpRef.set(erpData);
    await batch.commit();
  }

  // Update existing transaction with stock and ERP summary updates
  Future<void> updateTransaction(model_tr.Transaction updatedTr) async {
    final docRef = _db.collection('transactions').doc(updatedTr.invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. Get old transaction
      final oldSnap = await transaction.get(docRef);
      if (!oldSnap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(oldSnap.data()!, oldSnap.id);

      // 2. Revert old stocks (increment product stocks by old qty)
      for (var item in oldTr.items) {
        final prodRef = _db.collection('products').doc(item.productId);
        final prodSnap = await transaction.get(prodRef);
        if (prodSnap.exists) {
          final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
          transaction.update(prodRef, {'stock': currentStock + item.qty});
        }
      }

      // 3. Revert from old ERP summary
      final oldMonthYear = DateFormat('MM-yyyy').format(oldTr.deliveryDate);
      final oldErpRef = _db.collection('erp_summary').doc("${oldMonthYear}_${oldTr.customerId}");
      final oldErpSnap = await transaction.get(oldErpRef);
      if (oldErpSnap.exists) {
        Map<String, dynamic> erpData = Map<String, dynamic>.from(oldErpSnap.data()!);
        double income = (erpData['totalIncome'] ?? 0.0).toDouble();
        erpData['totalIncome'] = income - oldTr.grandTotal;

        Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});
        for (var item in oldTr.items) {
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
        transaction.set(oldErpRef, erpData);
      }

      // 4. Apply new stocks (decrement product stocks by new qty)
      for (var item in updatedTr.items) {
        final prodRef = _db.collection('products').doc(item.productId);
        final prodSnap = await transaction.get(prodRef);
        if (prodSnap.exists) {
          final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
          transaction.update(prodRef, {'stock': currentStock - item.qty});
        }
      }

      // 5. Apply to new ERP summary
      final newMonthYear = DateFormat('MM-yyyy').format(updatedTr.deliveryDate);
      final newErpRef = _db.collection('erp_summary').doc("${newMonthYear}_${updatedTr.customerId}");
      final newErpSnap = await transaction.get(newErpRef);

      Map<String, dynamic> newErpData = newErpSnap.exists
          ? Map<String, dynamic>.from(newErpSnap.data()!)
          : {
              'monthYear': newMonthYear,
              'customerId': updatedTr.customerId,
              'customerName': updatedTr.aliasName,
              'products': {},
              'totalIncome': 0.0,
            };

      double newIncome = (newErpData['totalIncome'] ?? 0.0).toDouble();
      newErpData['totalIncome'] = newIncome + updatedTr.grandTotal;

      Map<String, dynamic> newProductsMap = Map<String, dynamic>.from(newErpData['products'] ?? {});
      for (var item in updatedTr.items) {
        Map<String, dynamic> prodRecord = newProductsMap[item.productId] != null
            ? Map<String, dynamic>.from(newProductsMap[item.productId])
            : {'pcs': 0.0, 'kg': 0.0};

        double currentPcs = (prodRecord['pcs'] ?? 0.0).toDouble();
        double currentKg = (prodRecord['kg'] ?? 0.0).toDouble();

        prodRecord['pcs'] = currentPcs + item.qty;
        prodRecord['kg'] = currentKg + item.weightKg;

        newProductsMap[item.productId] = prodRecord;
      }
      newErpData['products'] = newProductsMap;
      transaction.set(newErpRef, newErpData);

      // 6. Write updated transaction doc
      transaction.set(docRef, updatedTr.toMap());
    });
  }

  // Delete transaction with stock and ERP summary reversion
  Future<void> deleteTransaction(int invoiceNo) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. Get old transaction
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);

      // 2. Revert stocks
      for (var item in oldTr.items) {
        final prodRef = _db.collection('products').doc(item.productId);
        final prodSnap = await transaction.get(prodRef);
        if (prodSnap.exists) {
          final currentStock = (prodSnap.data()?['stock'] ?? 0.0).toDouble();
          transaction.update(prodRef, {'stock': currentStock + item.qty});
        }
      }

      // 3. Revert from ERP summary
      final monthYear = DateFormat('MM-yyyy').format(oldTr.deliveryDate);
      final erpRef = _db.collection('erp_summary').doc("${monthYear}_${oldTr.customerId}");
      final erpSnap = await transaction.get(erpRef);
      if (erpSnap.exists) {
        Map<String, dynamic> erpData = Map<String, dynamic>.from(erpSnap.data()!);
        double income = (erpData['totalIncome'] ?? 0.0).toDouble();
        erpData['totalIncome'] = income - oldTr.grandTotal;

        Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});
        for (var item in oldTr.items) {
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

      // 4. Delete the transaction document
      transaction.delete(docRef);
    });
  }
}
