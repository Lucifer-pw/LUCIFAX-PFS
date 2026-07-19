import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/receivable.dart';

class ReceivableProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Receivable> _receivables = [];
  bool _isLoading = false;
  String? _error;

  List<Receivable> get receivables => _receivables;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get totalUnpaid {
    return _receivables
        .where((r) => !r.isLunas)
        .fold(0.0, (acc, r) => acc + r.nominal);
  }

  double get totalPaid {
    return _receivables
        .where((r) => r.isLunas)
        .fold(0.0, (acc, r) => acc + r.nominal);
  }

  Future<void> fetchReceivables() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _db
          .collection('receivables')
          .orderBy('tglKirim', descending: true)
          .get();

      _receivables = snapshot.docs
          .map((doc) => Receivable.fromFirestore(doc))
          .toList();
    } catch (e) {
      _error = e.toString();
      debugPrint("Error fetching receivables: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addReceivable(Receivable item) async {
    try {
      final docRef = await _db.collection('receivables').add(item.toFirestore());
      final newItem = item.copyWith(id: docRef.id);
      _receivables.insert(0, newItem);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error adding receivable: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleLunas(String id, bool currentStatus) async {
    try {
      final newStatus = !currentStatus;
      await _db.collection('receivables').doc(id).update({
        'isLunas': newStatus,
      });

      final index = _receivables.indexWhere((r) => r.id == id);
      if (index != -1) {
        _receivables[index] = _receivables[index].copyWith(isLunas: newStatus);
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error toggling receivable lunas status: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteReceivable(String id) async {
    try {
      await _db.collection('receivables').doc(id).delete();
      _receivables.removeWhere((r) => r.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error deleting receivable: $e");
      notifyListeners();
      return false;
    }
  }
}
