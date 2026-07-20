import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionItem {
  final String productId;
  final String productName;
  final double price;
  final double qty; // in pieces
  final double discountPercent; // e.g. 17.5 for 17.5%
  final double subtotal;
  final double sizeGrams;
  final double weightKg; // Calculated as qty * sizeGrams / 1000
  final bool isBonus; // true if this item is a free bonus (price = 0)

  TransactionItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.qty,
    required this.discountPercent,
    required this.subtotal,
    required this.sizeGrams,
    this.isBonus = false,
  }) : weightKg = (qty * sizeGrams) / 1000.0;

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      qty: (map['qty'] ?? 0.0).toDouble(),
      discountPercent: (map['discountPercent'] ?? 0.0).toDouble(),
      subtotal: (map['subtotal'] ?? 0.0).toDouble(),
      sizeGrams: (map['sizeGrams'] ?? 0.0).toDouble(),
      isBonus: map['isBonus'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'qty': qty,
      'discountPercent': discountPercent,
      'subtotal': subtotal,
      'sizeGrams': sizeGrams,
      'weightKg': weightKg,
      'isBonus': isBonus,
    };
  }
}

class Transaction {
  final int invoiceNo; // auto-incrementing ID
  final String customerId;
  final String customerName;
  final String aliasName;
  final DateTime date;
  final DateTime? deliveryDate;
  final String city;
  final String province;
  final String country;
  final List<TransactionItem> items;
  final double grandTotal;
  final String note;
  final String status; // 'DIKIRIM', 'PENDING'
  final String statusTransfer; // 'PAID', 'UNPAID'
  final DateTime? transferDate;
  final DateTime? erpSyncDate;
  final String createdBy;
  final DateTime createdAt;

  Transaction({
    required this.invoiceNo,
    required this.customerId,
    required this.customerName,
    required this.aliasName,
    required this.date,
    this.deliveryDate,
    required this.city,
    required this.province,
    required this.country,
    required this.items,
    required this.grandTotal,
    required this.note,
    required this.status,
    required this.statusTransfer,
    this.transferDate,
    this.erpSyncDate,
    required this.createdBy,
    required this.createdAt,
  });

    final itemsList = (map['items'] as List<dynamic>?)
            ?.map((item) => TransactionItem.fromMap(item as Map<String, dynamic>))
            .toList() ??
        [];

    final calculatedTotal = itemsList.fold(0.0, (sum, item) => sum + (item.isBonus ? 0.0 : item.subtotal)).roundToDouble();
    final finalGrandTotal = calculatedTotal > 0 ? calculatedTotal : ((map['grandTotal'] ?? 0.0) as num).toDouble().roundToDouble();

    return Transaction(
      invoiceNo: int.tryParse(docId) ?? 0,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      aliasName: map['aliasName'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      deliveryDate: map['deliveryDate'] != null ? (map['deliveryDate'] as Timestamp).toDate() : null,
      city: map['city'] ?? '',
      province: map['province'] ?? '',
      country: map['country'] ?? 'INDONESIA',
      items: itemsList,
      grandTotal: finalGrandTotal,
      note: map['note'] ?? '',
      status: map['status'] ?? 'PENDING',
      statusTransfer: map['statusTransfer'] ?? 'UNPAID',
      transferDate: (map['transferDate'] as Timestamp?)?.toDate(),
      erpSyncDate: (map['erpSyncDate'] as Timestamp?)?.toDate(),
      createdBy: map['createdBy'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'aliasName': aliasName,
      'date': Timestamp.fromDate(date),
      'deliveryDate': deliveryDate != null ? Timestamp.fromDate(deliveryDate!) : null,
      'city': city,
      'province': province,
      'country': country,
      'items': items.map((item) => item.toMap()).toList(),
      'grandTotal': grandTotal,
      'note': note,
      'status': status,
      'statusTransfer': statusTransfer,
      'transferDate': transferDate != null ? Timestamp.fromDate(transferDate!) : null,
      'erpSyncDate': erpSyncDate != null ? Timestamp.fromDate(erpSyncDate!) : null,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
