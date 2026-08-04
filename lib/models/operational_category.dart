import 'package:cloud_firestore/cloud_firestore.dart';

class OperationalCategory {
  final String id;
  final String name;
  final String description;
  final double defaultAmount;
  final DateTime createdAt;

  OperationalCategory({
    required this.id,
    required this.name,
    this.description = '',
    this.defaultAmount = 0.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory OperationalCategory.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return OperationalCategory(
      id: docId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      defaultAmount: (map['defaultAmount'] as num?)?.toDouble() ?? 0.0,
      createdAt: parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'defaultAmount': defaultAmount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
