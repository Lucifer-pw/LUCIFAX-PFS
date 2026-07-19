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
      final DateTime oldDeliveryDate = oldTr.deliveryDate;

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

      // Read old ERP snap
      final oldMonthYear = DateFormat('MM-yyyy').format(oldDeliveryDate);
      final oldErpRef = _db.collection('erp_summary').doc("${oldMonthYear}_${oldTr.customerId}");
      final oldErpSnap = (stockShouldIncrease || (oldStatus == 'DIKIRIM' && newStatus == 'DIKIRIM' && oldDeliveryDate != newDeliveryDate))
          ? await transaction.get(oldErpRef)
          : null;

      // Read new ERP snap
      final newMonthYear = DateFormat('MM-yyyy').format(newDeliveryDate);
      final newErpRef = _db.collection('erp_summary').doc("${newMonthYear}_${oldTr.customerId}");
      final newErpSnap = (stockShouldDecrease || (oldStatus == 'DIKIRIM' && newStatus == 'DIKIRIM' && oldDeliveryDate != newDeliveryDate))
          ? await transaction.get(newErpRef)
          : null;

      // 2. EXECUTE ALL WRITES (NO READS AFTER THIS LINE)
      if (stockShouldDecrease) {
        // Deduct product stocks
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

        // Apply to new ERP summary
        Map<String, dynamic> erpData = (newErpSnap != null && newErpSnap.exists)
            ? Map<String, dynamic>.from(newErpSnap.data()!)
            : {
                'monthYear': newMonthYear,
                'customerId': oldTr.customerId,
                'customerName': oldTr.aliasName,
                'products': {},
                'totalIncome': 0.0,
              };

        double currentIncome = (erpData['totalIncome'] ?? 0.0).toDouble();
        erpData['totalIncome'] = currentIncome + oldTr.grandTotal;

        Map<String, dynamic> productsMap = Map<String, dynamic>.from(erpData['products'] ?? {});
        for (var item in oldTr.items) {
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
        transaction.set(newErpRef, erpData);
      } else if (stockShouldIncrease) {
        // Revert product stocks (add back)
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

        // Revert from old ERP summary
        if (oldErpSnap != null && oldErpSnap.exists) {
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
      } else if (oldStatus == 'DIKIRIM' && newStatus == 'DIKIRIM' && oldDeliveryDate != newDeliveryDate) {
        if (oldMonthYear != newMonthYear) {
          if (oldErpSnap != null && oldErpSnap.exists) {
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

          Map<String, dynamic> newErpData = (newErpSnap != null && newErpSnap.exists)
              ? Map<String, dynamic>.from(newErpSnap.data()!)
              : {
                  'monthYear': newMonthYear,
                  'customerId': oldTr.customerId,
                  'customerName': oldTr.aliasName,
                  'products': {},
                  'totalIncome': 0.0,
                };

          double newIncome = (newErpData['totalIncome'] ?? 0.0).toDouble();
          newErpData['totalIncome'] = newIncome + oldTr.grandTotal;

          Map<String, dynamic> newProductsMap = Map<String, dynamic>.from(newErpData['products'] ?? {});
          for (var item in oldTr.items) {
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
        }
      }

      transaction.update(docRef, {
        'status': newStatus,
        'deliveryDate': Timestamp.fromDate(newDeliveryDate),
        'erpSyncDate': newStatus == 'DIKIRIM' ? Timestamp.fromDate(DateTime.now()) : null,
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

      // Read old ERP snap if old status was DIKIRIM
      final oldMonthYear = DateFormat('MM-yyyy').format(oldTr.deliveryDate);
      final oldErpRef = _db.collection('erp_summary').doc("${oldMonthYear}_${oldTr.customerId}");
      final oldErpSnap = oldWasDelivered ? await transaction.get(oldErpRef) : null;

      // Read new ERP snap if new status is DIKIRIM
      final newMonthYear = DateFormat('MM-yyyy').format(updatedTr.deliveryDate);
      final newErpRef = _db.collection('erp_summary').doc("${newMonthYear}_${updatedTr.customerId}");
      final newErpSnap = newIsDelivered ? await transaction.get(newErpRef) : null;

      // 2. NOW PERFORM ALL WRITES (NO READS AFTER THIS LINE)
      // Revert old stocks if old status was DIKIRIM
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

        // Revert old ERP summary
        if (oldErpSnap != null && oldErpSnap.exists) {
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
      }

      // Apply new stocks if new status is DIKIRIM
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

        // Apply to new ERP summary
        Map<String, dynamic> newErpData = (newErpSnap != null && newErpSnap.exists)
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
      }

      // Write updated transaction doc
      final Map<String, dynamic> data = updatedTr.toMap();
      if (newIsDelivered) {
        data['erpSyncDate'] = updatedTr.erpSyncDate != null 
            ? Timestamp.fromDate(updatedTr.erpSyncDate!) 
            : Timestamp.fromDate(DateTime.now());
      } else {
        data['erpSyncDate'] = null;
      }
      transaction.set(docRef, data);
    });
  }

  // Delete transaction without reverting stock (as explicitly requested)
  Future<void> deleteTransaction(int invoiceNo) async {
    final docRef = _db.collection('transactions').doc(invoiceNo.toString());

    await _db.runTransaction((transaction) async {
      // 1. READ ALL DOCUMENTS FIRST
      final snap = await transaction.get(docRef);
      if (!snap.exists) {
        throw Exception("Transaksi tidak ditemukan!");
      }
      final oldTr = model_tr.Transaction.fromMap(snap.data()!, snap.id);
      final bool wasDelivered = (oldTr.status == 'DIKIRIM');

      // Read ERP snap only if wasDelivered
      final monthYear = DateFormat('MM-yyyy').format(oldTr.deliveryDate);
      final erpRef = _db.collection('erp_summary').doc("${monthYear}_${oldTr.customerId}");
      final erpSnap = wasDelivered ? await transaction.get(erpRef) : null;

      // 2. EXECUTE WRITES (NO STOCK REVERSION)
      // Revert from ERP summary if it was delivered
      if (wasDelivered && erpSnap != null && erpSnap.exists) {
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

      // Delete the transaction document
      transaction.delete(docRef);
    });
  }
}
