import 'package:cloud_firestore/cloud_firestore.dart';

class Staff {
  final String id;
  final String name;
  final String location; // e.g. "Solo-Jateng", "Semarang-Jateng"
  final String position; // e.g. "Pegawai", "Kacab"
  final bool isActive;
  final DateTime createdAt;

  Staff({
    required this.id,
    required this.name,
    required this.location,
    this.position = 'Pegawai',
    this.isActive = true,
    required this.createdAt,
  });

  factory Staff.fromMap(Map<String, dynamic> map, String docId) {
    return Staff(
      id: docId,
      name: map['name'] ?? '',
      location: map['location'] ?? '',
      position: map['position'] ?? 'Pegawai',
      isActive: map['isActive'] ?? true,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': location,
      'position': position,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
