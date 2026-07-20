import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceRecord {
  final String id; // format: "${monthYear}_${staffId}"
  final String monthYear; // e.g. "05-2026"
  final String staffId;
  final String staffName;
  final String location;
  final double hk; // Hari Kerja (1-20)
  final double off; // Off
  final double sakit; // Sakit
  final double ijin; // Ijin
  final double estimasi; // Estimasi masuk (21-akhir)
  final double totalHk; // HK + Estimasi
  final DateTime updatedAt;

  AttendanceRecord({
    required this.id,
    required this.monthYear,
    required this.staffId,
    required this.staffName,
    required this.location,
    required this.hk,
    required this.off,
    required this.sakit,
    required this.ijin,
    required this.estimasi,
    required this.totalHk,
    required this.updatedAt,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> map, String docId) {
    final hkVal = ((map['hk'] ?? 0.0) as num).toDouble();
    final offVal = ((map['off'] ?? 0.0) as num).toDouble();
    final sakitVal = ((map['sakit'] ?? 0.0) as num).toDouble();
    final ijinVal = ((map['ijin'] ?? 0.0) as num).toDouble();
    final estimasiVal = ((map['estimasi'] ?? 0.0) as num).toDouble();
    final totalHkVal = map['totalHk'] != null
        ? ((map['totalHk'] ?? 0.0) as num).toDouble()
        : (hkVal + estimasiVal);

    return AttendanceRecord(
      id: docId,
      monthYear: map['monthYear'] ?? '',
      staffId: map['staffId'] ?? '',
      staffName: map['staffName'] ?? '',
      location: map['location'] ?? '',
      hk: hkVal,
      off: offVal,
      sakit: sakitVal,
      ijin: ijinVal,
      estimasi: estimasiVal,
      totalHk: totalHkVal,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'monthYear': monthYear,
      'staffId': staffId,
      'staffName': staffName,
      'location': location,
      'hk': hk,
      'off': off,
      'sakit': sakit,
      'ijin': ijin,
      'estimasi': estimasi,
      'totalHk': totalHk,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
