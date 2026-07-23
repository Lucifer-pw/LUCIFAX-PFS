import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stock_entry.dart';

class StockProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<StockEntry> _stockEntries = [];
  bool _isLoading = false;
  String? _error;

  List<StockEntry> get stockEntries => _stockEntries;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Returns weekly stock map: { productId: { 1: qty, 2: qty, 3: qty, 4: qty, 5: qty } }
  Map<String, Map<int, double>> getWeeklySummary(String monthYear) {
    final Map<String, Map<int, double>> result = {};

    final monthlyEntries = _stockEntries.where((e) => e.monthYear == monthYear).toList();

    for (var entry in monthlyEntries) {
      result.putIfAbsent(entry.productId, () => {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0});
      final currentQty = result[entry.productId]![entry.weekNumber] ?? 0.0;
      result[entry.productId]![entry.weekNumber] = currentQty + entry.qty;
    }

    return result;
  }

  Future<void> fetchStockEntries() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _db
          .collection('stock_entries')
          .orderBy('date', descending: true)
          .get();

      _stockEntries = snapshot.docs
          .map((doc) => StockEntry.fromFirestore(doc))
          .toList();

      // Auto-sync unsynced entries to products collection
      _syncUnsyncedEntries(snapshot.docs);
    } catch (e) {
      _error = e.toString();
      debugPrint("Error fetching stock entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateStockForProductAndSiblings(String productId, double deltaQty) async {
    if (productId.isEmpty || deltaQty == 0) return;
    try {
      final targetDoc = await _db.collection('products').doc(productId).get();
      if (targetDoc.exists) {
        final data = targetDoc.data();
        final String kodeInduk = (data?['kodeInduk'] ?? '').toString().trim();

        if (kodeInduk.isNotEmpty) {
          final query = await _db.collection('products').where('kodeInduk', isEqualTo: kodeInduk).get();
          if (query.docs.isNotEmpty) {
            final batch = _db.batch();
            for (var doc in query.docs) {
              batch.update(doc.reference, {'stock': FieldValue.increment(deltaQty)});
            }
            await batch.commit();
            return;
          }
        }
      }
      await _db.collection('products').doc(productId).update({'stock': FieldValue.increment(deltaQty)});
    } catch (e) {
      debugPrint("Error updating sibling stock: $e");
    }
  }

  Future<void> _syncUnsyncedEntries(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    for (var doc in docs) {
      final data = doc.data();
      final bool isSynced = data['isSynced'] ?? false;
      if (!isSynced) {
        final String productId = data['productId'] ?? '';
        final double qty = (data['qty'] ?? 0.0).toDouble();

        if (productId.isNotEmpty && qty > 0) {
          await _updateStockForProductAndSiblings(productId, qty);
          await doc.reference.update({'isSynced': true}).catchError((err) {
            debugPrint("Sync flag error: $err");
          });
        }
      }
    }
  }

  Future<bool> saveStockEntry(StockEntry entry) async {
    try {
      final data = entry.toFirestore();
      data['isSynced'] = true;

      final docRef = await _db.collection('stock_entries').add(data);
      final newEntry = entry.copyWith(id: docRef.id);
      _stockEntries.insert(0, newEntry);

      // Increment stock across all variants with matching kodeInduk
      if (entry.productId.isNotEmpty && entry.qty > 0) {
        await _updateStockForProductAndSiblings(entry.productId, entry.qty);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error saving stock entry: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteStockEntry(String id) async {
    try {
      final existingIndex = _stockEntries.indexWhere((e) => e.id == id);
      if (existingIndex != -1) {
        final existingEntry = _stockEntries[existingIndex];
        // Decrement stock across all variants with matching kodeInduk
        if (existingEntry.productId.isNotEmpty && existingEntry.qty > 0) {
          await _updateStockForProductAndSiblings(existingEntry.productId, -existingEntry.qty);
        }
      }

      await _db.collection('stock_entries').doc(id).delete();
      _stockEntries.removeWhere((e) => e.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error deleting stock entry: $e");
      notifyListeners();
      return false;
    }
  }

  // Fetch initial stock for a month
  Future<Map<String, double>> fetchInitialStocks(String monthYear) async {
    final Map<String, double> result = {};
    try {
      final snap = await _db
          .collection('monthly_stock_initial')
          .where('monthYear', isEqualTo: monthYear)
          .get();
      for (var doc in snap.docs) {
        final data = doc.data();
        final String prodId = data['productId'] ?? '';
        final double initialStock = (data['initialStock'] ?? 0.0).toDouble();
        if (prodId.isNotEmpty) {
          result[prodId] = initialStock;
        }
      }
    } catch (e) {
      debugPrint("Error fetching initial stocks: $e");
    }
    return result;
  }

  // Save initial stocks for a month
  Future<void> saveInitialStocks(String monthYear, Map<String, double> stocks) async {
    final batch = _db.batch();
    for (var entry in stocks.entries) {
      final docRef = _db.collection('monthly_stock_initial').doc("${monthYear}_${entry.key}");
      batch.set(docRef, {
        'monthYear': monthYear,
        'productId': entry.key,
        'initialStock': entry.value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    notifyListeners();
  }
}
