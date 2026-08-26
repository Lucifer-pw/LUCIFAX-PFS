import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

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
    );
  }
}
