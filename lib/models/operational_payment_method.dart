import 'package:cloud_firestore/cloud_firestore.dart';

class OperationalPaymentMethod {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;

  OperationalPaymentMethod({
    required this.id,
    required this.name,
    this.description = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory OperationalPaymentMethod.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return OperationalPaymentMethod(
      id: docId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      createdAt: parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
