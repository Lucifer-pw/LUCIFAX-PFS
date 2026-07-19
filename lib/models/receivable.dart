import 'package:cloud_firestore/cloud_firestore.dart';

class Receivable {
  final String id;
  final String toko;
  final String noInvoice;
  final DateTime tglKirim;
  final double nominal;
  final String keterangan;
  final bool isLunas;
  final DateTime? createdAt;

  Receivable({
    required this.id,
    required this.toko,
    required this.noInvoice,
    required this.tglKirim,
    required this.nominal,
    this.keterangan = '',
    this.isLunas = false,
    this.createdAt,
  });

  factory Receivable.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime parsedTglKirim = DateTime.now();
    if (data['tglKirim'] != null) {
      if (data['tglKirim'] is Timestamp) {
        parsedTglKirim = (data['tglKirim'] as Timestamp).toDate();
      } else if (data['tglKirim'] is String) {
        parsedTglKirim = DateTime.tryParse(data['tglKirim']) ?? DateTime.now();
      }
    }

    DateTime? parsedCreatedAt;
    if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    }

    return Receivable(
      id: doc.id,
      toko: data['toko'] ?? '',
      noInvoice: data['noInvoice'] ?? '',
      tglKirim: parsedTglKirim,
      nominal: (data['nominal'] is num) ? (data['nominal'] as num).toDouble() : 0.0,
      keterangan: data['keterangan'] ?? '',
      isLunas: data['isLunas'] ?? false,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'toko': toko,
      'noInvoice': noInvoice,
      'tglKirim': Timestamp.fromDate(tglKirim),
      'nominal': nominal,
      'keterangan': keterangan,
      'isLunas': isLunas,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  Receivable copyWith({
    String? id,
    String? toko,
    String? noInvoice,
    DateTime? tglKirim,
    double? nominal,
    String? keterangan,
    bool? isLunas,
    DateTime? createdAt,
  }) {
    return Receivable(
      id: id ?? this.id,
      toko: toko ?? this.toko,
      noInvoice: noInvoice ?? this.noInvoice,
      tglKirim: tglKirim ?? this.tglKirim,
      nominal: nominal ?? this.nominal,
      keterangan: keterangan ?? this.keterangan,
      isLunas: isLunas ?? this.isLunas,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
