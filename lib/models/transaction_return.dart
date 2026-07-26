import 'package:cloud_firestore/cloud_firestore.dart';

class ReturnItem {
  final String productId;
  final String productName;
  final double qtyReturned; // in pieces
  final double price; // Original unit price
  final double discountPercent; // Discount percent
  final double effectiveUnitPrice; // Price after discount
  final double subtotalReturn; // qtyReturned * effectiveUnitPrice
  final double sizeGrams;
  final bool isBonus;
  final String condition; // 'BAGUS' (Stok Kembali) or 'RUSAK_BS' (Barang Afkir)
  final String reason;

  ReturnItem({
    required this.productId,
    required this.productName,
    required this.qtyReturned,
    required this.price,
    required this.discountPercent,
    required this.effectiveUnitPrice,
    required this.subtotalReturn,
    required this.sizeGrams,
    this.isBonus = false,
    required this.condition,
    required this.reason,
  });

  factory ReturnItem.fromMap(Map<String, dynamic> map) {
    final price = (map['price'] ?? 0.0).toDouble();
    final disc = (map['discountPercent'] ?? 0.0).toDouble();
    final effPrice = isBonusHelper(map['isBonus']) ? 0.0 : (map['effectiveUnitPrice'] ?? (price * (1 - disc / 100))).toDouble();

    return ReturnItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      qtyReturned: (map['qtyReturned'] ?? 0.0).toDouble(),
      price: price,
      discountPercent: disc,
      effectiveUnitPrice: effPrice,
      subtotalReturn: (map['subtotalReturn'] ?? 0.0).toDouble(),
      sizeGrams: (map['sizeGrams'] ?? 0.0).toDouble(),
      isBonus: isBonusHelper(map['isBonus']),
      condition: map['condition'] ?? 'BAGUS',
      reason: map['reason'] ?? '',
    );
  }

  static bool isBonusHelper(dynamic val) {
    if (val is bool) return val;
    return false;
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'qtyReturned': qtyReturned,
      'price': price,
      'discountPercent': discountPercent,
      'effectiveUnitPrice': effectiveUnitPrice,
      'subtotalReturn': subtotalReturn,
      'sizeGrams': sizeGrams,
      'isBonus': isBonus,
      'condition': condition,
      'reason': reason,
    };
  }
}

class TransactionReturn {
  final String id;
  final String invoiceNo;
  final String customerId;
  final String customerName;
  final String aliasName;
  final DateTime returnDate;
  final List<ReturnItem> items;
  final double totalReturnAmount;
  final String createdBy;
  final DateTime createdAt;

  TransactionReturn({
    required this.id,
    required this.invoiceNo,
    required this.customerId,
    required this.customerName,
    required this.aliasName,
    required this.returnDate,
    required this.items,
    required this.totalReturnAmount,
    required this.createdBy,
    required this.createdAt,
  });

  factory TransactionReturn.fromMap(Map<String, dynamic> map, String docId) {
    final itemsList = (map['items'] as List<dynamic>?)
            ?.map((item) => ReturnItem.fromMap(item as Map<String, dynamic>))
            .toList() ??
        [];

    return TransactionReturn(
      id: docId,
      invoiceNo: map['invoiceNo']?.toString() ?? '',
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      aliasName: map['aliasName'] ?? '',
      returnDate: map['returnDate'] != null
          ? (map['returnDate'] as Timestamp).toDate()
          : DateTime.now(),
      items: itemsList,
      totalReturnAmount: (map['totalReturnAmount'] ?? 0.0).toDouble(),
      createdBy: map['createdBy'] ?? '',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNo': invoiceNo,
      'customerId': customerId,
      'customerName': customerName,
      'aliasName': aliasName,
      'returnDate': Timestamp.fromDate(returnDate),
      'items': items.map((item) => item.toMap()).toList(),
      'totalReturnAmount': totalReturnAmount,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
