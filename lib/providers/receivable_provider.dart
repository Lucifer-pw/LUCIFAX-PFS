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
        .fold(0.0, (acc, r) => acc + r.remainingAmount);
  }

  double get totalPaid {
    return _receivables
        .fold(0.0, (acc, r) => acc + r.effectivePaidAmount);
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

  Future<bool> recordPayment({
    required String receivableId,
    required String noInvoice,
    required double paymentAmount,
    required DateTime paymentDate,
    String note = '',
    String paymentMethod = 'Transfer',
    double overpaymentToDeposit = 0.0,
    String? customerId,
  }) async {
    try {
      final index = _receivables.indexWhere((r) => r.id == receivableId);
      if (index == -1) return false;
      final current = _receivables[index];

      final newPayment = PaymentRecord(
        id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
        amount: paymentAmount,
        date: paymentDate,
        note: note,
        paymentMethod: paymentMethod,
        createdAt: DateTime.now(),
      );

      final updatedPayments = List<PaymentRecord>.from(current.payments)..add(newPayment);
      final newPaidAmount = current.effectivePaidAmount + paymentAmount;
      final bool willBeLunas = newPaidAmount >= (current.effectiveNominal - 1.0);

      // 1. Update receivables in Firestore
      await _db.collection('receivables').doc(receivableId).update({
        'paidAmount': newPaidAmount,
        'isLunas': willBeLunas,
        'payments': updatedPayments.map((p) => p.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. If overpayment to deposit, update customer's depositBalance
      if (overpaymentToDeposit > 0 && customerId != null && customerId.isNotEmpty) {
        await _db.collection('customers').doc(customerId).update({
          'depositBalance': FieldValue.increment(overpaymentToDeposit),
        });
      }

      // 3. Update local state
      _receivables[index] = current.copyWith(
        paidAmount: newPaidAmount,
        isLunas: willBeLunas,
        payments: updatedPayments,
      );
      notifyListeners();

      // 4. Sync to transactions collection in Firestore
      final invClean = noInvoice.replaceAll('#', '').trim();
      final trStatus = willBeLunas ? 'PAID' : 'UNPAID';
      final trDoc = await _db.collection('transactions').doc(invClean).get();
      if (trDoc.exists) {
        await trDoc.reference.update({
          'statusTransfer': trStatus,
          'transferDate': willBeLunas ? Timestamp.fromDate(paymentDate) : null,
        });
      } else {
        final trSnap = await _db.collection('transactions').where('invoiceNo', isEqualTo: invClean).limit(1).get();
        if (trSnap.docs.isNotEmpty) {
          await trSnap.docs.first.reference.update({
            'statusTransfer': trStatus,
            'transferDate': willBeLunas ? Timestamp.fromDate(paymentDate) : null,
          });
        }
      }

      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error recordPayment: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> deletePaymentRecord({
    required String receivableId,
    required String noInvoice,
    required String paymentId,
  }) async {
    try {
      final index = _receivables.indexWhere((r) => r.id == receivableId);
      if (index == -1) return false;
      final current = _receivables[index];

      final updatedPayments = current.payments.where((p) => p.id != paymentId).toList();
      final newPaidAmount = updatedPayments.fold(0.0, (acc, p) => acc + p.amount);
      final bool willBeLunas = newPaidAmount >= (current.effectiveNominal - 1.0) && newPaidAmount > 0;

      await _db.collection('receivables').doc(receivableId).update({
        'paidAmount': newPaidAmount,
        'isLunas': willBeLunas,
        'payments': updatedPayments.map((p) => p.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _receivables[index] = current.copyWith(
        paidAmount: newPaidAmount,
        isLunas: willBeLunas,
        payments: updatedPayments,
      );
      notifyListeners();

      final invClean = noInvoice.replaceAll('#', '').trim();
      final trStatus = willBeLunas ? 'PAID' : 'UNPAID';
      final trDoc = await _db.collection('transactions').doc(invClean).get();
      if (trDoc.exists) {
        await trDoc.reference.update({
          'statusTransfer': trStatus,
          'transferDate': willBeLunas ? Timestamp.fromDate(DateTime.now()) : null,
        });
      }

      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint("Error deletePaymentRecord: $e");
      notifyListeners();
      return false;
    }
  }

  Future<bool> markLunasWithDate(String id, String noInvoice, bool isLunas, DateTime? transferDate) async {
    try {
      final index = _receivables.indexWhere((r) => r.id == id);
      double newPaid = 0.0;
      List<PaymentRecord> newPayments = [];

      if (index != -1) {
        final current = _receivables[index];
        if (isLunas) {
          newPaid = current.effectiveNominal;
          newPayments = List<PaymentRecord>.from(current.payments);
          if (newPayments.isEmpty) {
            newPayments.add(PaymentRecord(
              id: 'pay_${DateTime.now().millisecondsSinceEpoch}',
              amount: newPaid,
              date: transferDate ?? DateTime.now(),
              note: 'Pelunasan Penuh',
              paymentMethod: 'Transfer',
              createdAt: DateTime.now(),
            ));
          }
        } else {
          newPaid = 0.0;
          newPayments = [];
        }
      }

      // 1. Update receivables in Firestore
      await _db.collection('receivables').doc(id).update({
        'isLunas': isLunas,
        'paidAmount': newPaid,
        'payments': newPayments.map((p) => p.toMap()).toList(),
      });

      // 2. Update local state
      if (index != -1) {
        _receivables[index] = _receivables[index].copyWith(
          isLunas: isLunas,
          paidAmount: newPaid,
          payments: newPayments,
        );
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
