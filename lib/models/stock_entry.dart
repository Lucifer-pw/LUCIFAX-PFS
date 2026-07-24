import 'package:cloud_firestore/cloud_firestore.dart';

class StockEntry {
  final String id;
  final String productId;
  final String productName;
  final double price;
  final DateTime date;
  final String monthYear; // Format: "MM-yyyy"
  final int weekNumber; // 1, 2, 3, 4, 5
  final double qty;
  final double? stockBefore;
  final double? stockAfter;
  final DateTime? createdAt;

  StockEntry({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    required this.date,
    required this.monthYear,
    required this.weekNumber,
    required this.qty,
    this.stockBefore,
    this.stockAfter,
    this.createdAt,
  });

  factory StockEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parsedDate = DateTime.now();
    if (data['date'] != null) {
      if (data['date'] is Timestamp) {
        parsedDate = (data['date'] as Timestamp).toDate();
      } else if (data['date'] is String) {
        parsedDate = DateTime.tryParse(data['date']) ?? DateTime.now();
      }
    }

    DateTime? parsedCreatedAt;
    if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    }

    return StockEntry(
      id: doc.id,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      price: (data['price'] is num) ? (data['price'] as num).toDouble() : 0.0,
      date: parsedDate,
      monthYear: data['monthYear'] ?? '',
      weekNumber: (data['weekNumber'] is num) ? (data['weekNumber'] as num).toInt() : 1,
      qty: (data['qty'] is num) ? (data['qty'] as num).toDouble() : 0.0,
      stockBefore: (data['stockBefore'] is num) ? (data['stockBefore'] as num).toDouble() : null,
      stockAfter: (data['stockAfter'] is num) ? (data['stockAfter'] as num).toDouble() : null,
      createdAt: parsedCreatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'date': Timestamp.fromDate(date),
      'monthYear': monthYear,
      'weekNumber': weekNumber,
      'qty': qty,
      if (stockBefore != null) 'stockBefore': stockBefore,
      if (stockAfter != null) 'stockAfter': stockAfter,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  StockEntry copyWith({
    String? id,
    String? productId,
    String? productName,
    double? price,
    DateTime? date,
    String? monthYear,
    int? weekNumber,
    double? qty,
    double? stockBefore,
    double? stockAfter,
    DateTime? createdAt,
  }) {
    return StockEntry(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      price: price ?? this.price,
      date: date ?? this.date,
      monthYear: monthYear ?? this.monthYear,
      weekNumber: weekNumber ?? this.weekNumber,
      qty: qty ?? this.qty,
      stockBefore: stockBefore ?? this.stockBefore,
      stockAfter: stockAfter ?? this.stockAfter,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
