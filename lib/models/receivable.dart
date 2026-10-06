import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentRecord {
  final String id;
  final double amount;
  final DateTime date;
  final String note;
  final String paymentMethod;
  final DateTime? createdAt;

  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
    this.paymentMethod = 'Transfer',
    this.createdAt,
  });

  factory PaymentRecord.fromMap(Map<String, dynamic> map, [String? id]) {
    DateTime parsedDate = DateTime.now();
    if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        parsedDate = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        parsedDate = DateTime.tryParse(map['date']) ?? DateTime.now();
      }
    }
    DateTime? parsedCreatedAt;
    if (map['createdAt'] != null && map['createdAt'] is Timestamp) {
      parsedCreatedAt = (map['createdAt'] as Timestamp).toDate();
    }

    return PaymentRecord(
      id: id ?? map['id'] ?? '',
      amount: (map['amount'] is num) ? (map['amount'] as num).toDouble() : 0.0,
      date: parsedDate,
      note: map['note'] ?? '',
      paymentMethod: map['paymentMethod'] ?? 'Transfer',
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'note': note,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}

class Receivable {
  final String id;
  final String toko;
  final String kota;
  final String noInvoice;
  final DateTime? tglKirim;
  final double nominal;
  final String keterangan;
  final bool isLunas;
  final DateTime? createdAt;
  final DateTime? erpSyncDate;
  final bool isLocked;
  final double returnAmount;
  final double paidAmount;
  final List<PaymentRecord> payments;

  Receivable({
    required this.id,
    required this.toko,
    this.kota = '',
    required this.noInvoice,
    this.tglKirim,
    required this.nominal,
    this.keterangan = '',
    this.isLunas = false,
    this.createdAt,
    this.erpSyncDate,
    this.isLocked = false,
    this.returnAmount = 0.0,
    this.paidAmount = 0.0,
    this.payments = const [],
  });

  double get effectiveNominal => (nominal - returnAmount).clamp(0.0, double.infinity);
  double get effectivePaidAmount => isLunas && paidAmount <= 0 ? effectiveNominal : paidAmount;
  double get remainingAmount {
    if (isLunas) return 0.0;
    return (effectiveNominal - effectivePaidAmount).clamp(0.0, double.infinity);
  }
  bool get isPartiallyPaid => !isLunas && effectivePaidAmount > 0 && remainingAmount > 0;

  factory Receivable.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime? parsedTglKirim;
    if (data['tglKirim'] != null) {
      if (data['tglKirim'] is Timestamp) {
        parsedTglKirim = (data['tglKirim'] as Timestamp).toDate();
      } else if (data['tglKirim'] is String) {
        parsedTglKirim = DateTime.tryParse(data['tglKirim']);
      }
    }

    DateTime? parsedCreatedAt;
    if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    }

    DateTime? parsedErpSyncDate;
    if (data['erpSyncDate'] != null && data['erpSyncDate'] is Timestamp) {
      parsedErpSyncDate = (data['erpSyncDate'] as Timestamp).toDate();
    } else if (data['erpSyncDate'] is String) {
      parsedErpSyncDate = DateTime.tryParse(data['erpSyncDate']);
    }

    final rawPayments = data['payments'] as List<dynamic>? ?? [];
    final paymentsList = rawPayments.map((p) {
      if (p is Map<String, dynamic>) {
        return PaymentRecord.fromMap(p);
      } else if (p is Map) {
        return PaymentRecord.fromMap(Map<String, dynamic>.from(p));
      }
      return null;
    }).whereType<PaymentRecord>().toList();

    double parsedPaidAmount = (data['paidAmount'] is num) ? (data['paidAmount'] as num).toDouble() : 0.0;
    if (parsedPaidAmount <= 0 && paymentsList.isNotEmpty) {
      parsedPaidAmount = paymentsList.fold(0.0, (acc, p) => acc + p.amount);
    }

    return Receivable(
      id: doc.id,
      toko: data['toko'] ?? '',
      kota: data['kota'] ?? '',
      noInvoice: data['noInvoice'] ?? '',
      tglKirim: parsedTglKirim,
      nominal: (data['nominal'] is num) ? (data['nominal'] as num).toDouble() : 0.0,
      keterangan: data['keterangan'] ?? '',
      isLunas: data['isLunas'] ?? false,
      createdAt: parsedCreatedAt,
      erpSyncDate: parsedErpSyncDate,
      isLocked: data['isLocked'] ?? false,
      returnAmount: (data['returnAmount'] is num) ? (data['returnAmount'] as num).toDouble() : 0.0,
      paidAmount: parsedPaidAmount,
      payments: paymentsList,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'toko': toko,
      'kota': kota,
      'noInvoice': noInvoice,
      'tglKirim': tglKirim != null ? Timestamp.fromDate(tglKirim!) : null,
      'nominal': nominal,
      'keterangan': keterangan,
      'isLunas': isLunas,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'erpSyncDate': erpSyncDate != null ? Timestamp.fromDate(erpSyncDate!) : null,
      'isLocked': isLocked,
      'returnAmount': returnAmount,
      'paidAmount': paidAmount,
      'payments': payments.map((p) => p.toMap()).toList(),
    };
  }

  Receivable copyWith({
    String? id,
    String? toko,
    String? kota,
    String? noInvoice,
    DateTime? tglKirim,
    double? nominal,
    String? keterangan,
    bool? isLunas,
    DateTime? createdAt,
    DateTime? erpSyncDate,
    bool? isLocked,
    double? returnAmount,
    double? paidAmount,
    List<PaymentRecord>? payments,
  }) {
    return Receivable(
      id: id ?? this.id,
      toko: toko ?? this.toko,
      kota: kota ?? this.kota,
      noInvoice: noInvoice ?? this.noInvoice,
      tglKirim: tglKirim ?? this.tglKirim,
      nominal: nominal ?? this.nominal,
      keterangan: keterangan ?? this.keterangan,
      isLunas: isLunas ?? this.isLunas,
      createdAt: createdAt ?? this.createdAt,
      erpSyncDate: erpSyncDate ?? this.erpSyncDate,
      isLocked: isLocked ?? this.isLocked,
      returnAmount: returnAmount ?? this.returnAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      payments: payments ?? this.payments,
    );
  }
}
