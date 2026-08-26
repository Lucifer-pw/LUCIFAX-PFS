import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/receivable.dart';
import '../services/firebase_service.dart';

class ReceivableProvider with ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Receivable> _receivables = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription? _subscription;
  StreamSubscription? _authSubscription;

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

  ReceivableProvider() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        _isLoading = true;
        notifyListeners();
        _subscription = _dbService.streamReceivables().listen((list) {
          _receivables = list;
          _isLoading = false;
          notifyListeners();
        }, onError: (error) {
          debugPrint("Receivable stream error: $error");
          _error = error.toString();
          _isLoading = false;
          notifyListeners();
        });
      } else {
        _receivables = [];
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> fetchReceivables() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _db
          .collection('receivables')
          .get();

      final list = snapshot.docs
          .map((doc) => Receivable.fromFirestore(doc))
          .toList();
      list.sort((a, b) {
        if (a.tglKirim == null && b.tglKirim == null) return 0;
        if (a.tglKirim == null) return 1;
        if (b.tglKirim == null) return -1;
        return a.tglKirim!.compareTo(b.tglKirim!);
      });
      _receivables = list;
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

  Future<bool> markLunasWithDate(String id, String noInvoice, bool isLunas, DateTime? transferDate) async {
    try {
      // 1. Update receivables in Firestore
      await _db.collection('receivables').doc(id).update({
        'isLunas': isLunas,
      });

      // 2. Update local state
      final index = _receivables.indexWhere((r) => r.id == id);
      if (index != -1) {
        _receivables[index] = _receivables[index].copyWith(isLunas: isLunas);
        notifyListeners();
      }

      // 3. Sync to transactions collection in Firestore
      final invClean = noInvoice.replaceAll('#', '').trim();
      final trStatus = isLunas ? 'PAID' : 'UNPAID';
      final trDoc = await _db.collection('transactions').doc(invClean).get();
      if (trDoc.exists) {
        await trDoc.reference.update({
          'statusTransfer': trStatus,
          'transferDate': isLunas ? Timestamp.fromDate(transferDate ?? DateTime.now()) : null,
        });
      } else {
        final trSnap = await _db.collection('transactions').where('invoiceNo', isEqualTo: invClean).limit(1).get();
        if (trSnap.docs.isNotEmpty) {
          await trSnap.docs.first.reference.update({
            'statusTransfer': trStatus,
            'transferDate': isLunas ? Timestamp.fromDate(transferDate ?? DateTime.now()) : null,
          });
        }
      }

      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error markLunasWithDate: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleLunas(String id, bool currentStatus, {DateTime? transferDate}) async {
    final index = _receivables.indexWhere((r) => r.id == id);
    final noInvoice = (index != -1) ? _receivables[index].noInvoice : '';
    return await markLunasWithDate(id, noInvoice, !currentStatus, transferDate);
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

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
