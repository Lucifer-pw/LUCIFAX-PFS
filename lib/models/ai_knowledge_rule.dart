import 'package:cloud_firestore/cloud_firestore.dart';

class AiKnowledgeRule {
  final String id;
  /// Types: 'unit', 'customer_alias', 'product_alias', 'general_instruction', 'bonus_rule', 'bank_transfer_profile'
  final String type;
  /// Keyword or abbreviation in chat (e.g. 'k', 'MMM', 'Beres merah 24', 'roll', 'CV ALFA FROZEN MART')
  final String keyword;
  /// Target system mapping (e.g. '1 Karton', 'TOKO MAJU MAKMUR MANDIRI', 'BRS MERAH 24S 500 G', 'AFM')
  final String mappedValue;
  /// Optional target product ID or customer ID
  final String? targetId;
  /// Optional bank name for bank transfer profile (e.g. 'BRI', 'BCA')
  final String? bankName;
  /// Optional account number / digits for bank transfer profile (e.g. '3302')
  final String? accountNumber;
  /// Verification status: 'approved', 'pending_review'
  final String status;
  final DateTime createdAt;
  final String updatedBy;

  AiKnowledgeRule({
    required this.id,
    required this.type,
    required this.keyword,
    required this.mappedValue,
    this.targetId,
    this.bankName,
    this.accountNumber,
    this.status = 'approved',
    required this.createdAt,
    this.updatedBy = 'developer',
  });

  factory AiKnowledgeRule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AiKnowledgeRule.fromMap(data, doc.id);
  }

  factory AiKnowledgeRule.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedCreatedAt = DateTime.now();
    if (map['createdAt'] != null) {
      if (map['createdAt'] is Timestamp) {
        parsedCreatedAt = (map['createdAt'] as Timestamp).toDate();
      } else if (map['createdAt'] is String) {
        parsedCreatedAt = DateTime.tryParse(map['createdAt']) ?? DateTime.now();
      }
    }

    return AiKnowledgeRule(
      id: docId,
      type: map['type'] ?? 'product_alias',
      keyword: map['keyword'] ?? '',
      mappedValue: map['mappedValue'] ?? '',
      targetId: map['targetId'],
      bankName: map['bankName']?.toString(),
      accountNumber: map['accountNumber']?.toString(),
      status: map['status'] ?? 'approved',
      createdAt: parsedCreatedAt,
      updatedBy: map['updatedBy'] ?? 'developer',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'keyword': keyword,
      'mappedValue': mappedValue,
      if (targetId != null) 'targetId': targetId,
      if (bankName != null) 'bankName': bankName,
      if (accountNumber != null) 'accountNumber': accountNumber,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedBy': updatedBy,
    };
  }

  AiKnowledgeRule copyWith({
    String? id,
    String? type,
    String? keyword,
    String? mappedValue,
    String? targetId,
    String? bankName,
    String? accountNumber,
    String? status,
    DateTime? createdAt,
    String? updatedBy,
  }) {
    return AiKnowledgeRule(
      id: id ?? this.id,
      type: type ?? this.type,
      keyword: keyword ?? this.keyword,
      mappedValue: mappedValue ?? this.mappedValue,
      targetId: targetId ?? this.targetId,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
