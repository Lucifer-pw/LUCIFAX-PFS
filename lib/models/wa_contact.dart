import 'package:cloud_firestore/cloud_firestore.dart';

class WaContact {
  final String id;
  final String name;
  final String phone;
  final String role;
  final String template;

  WaContact({
    required this.id,
    required this.name,
    required this.phone,
    this.role = '',
    this.template = '',
  });

  factory WaContact.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WaContact(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? '',
      template: data['template'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'role': role,
      'template': template,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
