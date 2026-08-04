import 'package:cloud_firestore/cloud_firestore.dart';

class StockMutation {
  final String id;
  final String kodeInduk;
  final String productName;
  final String type; // 'KELUAR', 'MASUK', 'RETUR_STATUS', 'EDIT_MANUAL', 'INPUT_STOK'
  final double qty; // negative = out, positive = in
  final double stockBefore;
  final double stockAfter;
  final String reference; // e.g. 'Invoice #632', 'Input Stok', 'Edit Manual'
  final String customerName; // customer name if from invoice
  final DateTime timestamp;

  StockMutation({
    required this.id,
    required this.kodeInduk,
    required this.productName,
    required this.type,
    required this.qty,
    required this.stockBefore,
    required this.stockAfter,
    required this.reference,
    this.customerName = '',
    required this.timestamp,
  });

  factory StockMutation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parsedTimestamp = DateTime.now();
    if (data['timestamp'] != null && data['timestamp'] is Timestamp) {
      parsedTimestamp = (data['timestamp'] as Timestamp).toDate();
    }

    return StockMutation(
      id: doc.id,
      kodeInduk: data['kodeInduk'] ?? '',
      productName: data['productName'] ?? '',
      type: data['type'] ?? '',
      qty: (data['qty'] is num) ? (data['qty'] as num).toDouble() : 0.0,
      stockBefore: (data['stockBefore'] is num) ? (data['stockBefore'] as num).toDouble() : 0.0,
      stockAfter: (data['stockAfter'] is num) ? (data['stockAfter'] as num).toDouble() : 0.0,
      reference: data['reference'] ?? '',
      customerName: data['customerName'] ?? '',
      timestamp: parsedTimestamp,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'kodeInduk': kodeInduk,
      'productName': productName,
      'type': type,
      'qty': qty,
      'stockBefore': stockBefore,
      'stockAfter': stockAfter,
      'reference': reference,
      'customerName': customerName,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
