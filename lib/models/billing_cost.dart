import 'package:cloud_firestore/cloud_firestore.dart';

class BillingCost {
  final String id;
  final DateTime date;
  final double amount;
  final String? note;

  BillingCost({
    required this.id,
    required this.date,
    required this.amount,
    this.note,
  });

  factory BillingCost.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BillingCost(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      amount: (data['amount'] as num).toDouble(),
      note: data['note'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'date': Timestamp.fromDate(date),
      'amount': amount,
      if (note != null) 'note': note,
    };
  }

  BillingCost copyWith({
    String? id,
    DateTime? date,
    double? amount,
    String? note,
  }) {
    return BillingCost(
      id: id ?? this.id,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      note: note ?? this.note,
    );
  }
}
