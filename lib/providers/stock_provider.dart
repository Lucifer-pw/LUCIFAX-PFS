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
    } catch (e) {
      _error = e.toString();
      debugPrint("Error fetching stock entries: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveStockEntry(StockEntry entry) async {
    try {
      final docRef = await _db.collection('stock_entries').add(entry.toFirestore());
      final newEntry = entry.copyWith(id: docRef.id);
      _stockEntries.insert(0, newEntry);

      // Also update master product stock in 'products' collection if document exists
      if (entry.productId.isNotEmpty) {
        final prodDoc = await _db.collection('products').doc(entry.productId).get();
        if (prodDoc.exists) {
          final data = prodDoc.data();
          final String parentKodeInduk = data?['kodeInduk'] ?? entry.productId;
          final double qtyToAdd = entry.qty;

          // Find all products sharing the same kodeInduk
          final query = await _db
              .collection('products')
              .where('kodeInduk', isEqualTo: parentKodeInduk)
              .get();

          final batch = _db.batch();
          for (var doc in query.docs) {
            final currentStock = (doc.data()['stock'] ?? 0.0).toDouble();
            batch.update(doc.reference, {'stock': currentStock + qtyToAdd});
          }
          if (!query.docs.any((doc) => doc.id == entry.productId)) {
            final currentStock = (data?['stock'] ?? 0.0).toDouble();
            batch.update(prodDoc.reference, {'stock': currentStock + qtyToAdd});
          }
          await batch.commit();
        }
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
      final entryDoc = await _db.collection('stock_entries').doc(id).get();
      if (entryDoc.exists) {
        final data = entryDoc.data();
        final String productId = data?['productId'] ?? '';
        final double qty = (data?['qty'] ?? 0.0).toDouble();

        if (productId.isNotEmpty) {
          final prodDoc = await _db.collection('products').doc(productId).get();
          if (prodDoc.exists) {
            final prodData = prodDoc.data();
            final String parentKodeInduk = prodData?['kodeInduk'] ?? productId;

            // Find all products sharing the same kodeInduk
            final query = await _db
                .collection('products')
                .where('kodeInduk', isEqualTo: parentKodeInduk)
                .get();

            final batch = _db.batch();
            for (var doc in query.docs) {
              final currentStock = (doc.data()['stock'] ?? 0.0).toDouble();
              batch.update(doc.reference, {'stock': currentStock - qty});
            }
            if (!query.docs.any((doc) => doc.id == productId)) {
              final currentStock = (prodData?['stock'] ?? 0.0).toDouble();
              batch.update(prodDoc.reference, {'stock': currentStock - qty});
            }
            await batch.commit();
          }
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
}
