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
  final String invoiceNo; // auto-incrementing or custom ID (e.g. "625", "SA1", "SA34")
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
  final double returnAmount;
  final bool hasReturn;
  final List<TransactionItem> movedItems; // History of items moved to another invoice
  final String movedToInvoice; // Target invoice number for moved items
  final bool isLocked;

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
    this.returnAmount = 0.0,
    this.hasReturn = false,
    this.movedItems = const [],
    this.movedToInvoice = '',
    this.isLocked = false,
  });

  double get netGrandTotal => (grandTotal - returnAmount).clamp(0.0, double.infinity);

  factory Transaction.fromMap(Map<String, dynamic> map, String docId) {
    final itemsList = (map['items'] as List<dynamic>?)
            ?.map((item) => TransactionItem.fromMap(item as Map<String, dynamic>))
            .toList() ??
        [];

    final calculatedTotal = itemsList.fold(0.0, (sum, item) => sum + (item.isBonus ? 0.0 : item.subtotal)).roundToDouble();
    final finalGrandTotal = calculatedTotal > 0 ? calculatedTotal : ((map['grandTotal'] ?? 0.0) as num).toDouble().roundToDouble();

    final status = map['status'] ?? 'PENDING';
    final rawDeliveryDate = map['deliveryDate'] != null ? (map['deliveryDate'] as Timestamp).toDate() : null;
    final deliveryDate = status == 'DIKIRIM' ? rawDeliveryDate : null;

    final String finalInvoiceNo = map['invoiceNo']?.toString().isNotEmpty == true 
        ? map['invoiceNo'].toString() 
        : docId;

    final retAmt = (map['returnAmount'] ?? 0.0).toDouble();
    final hasRet = (map['hasReturn'] ?? false) || retAmt > 0;

    final movedItemsList = (map['movedItems'] as List<dynamic>?)
            ?.map((item) => TransactionItem.fromMap(item as Map<String, dynamic>))
            .toList() ??
        [];

    return Transaction(
      invoiceNo: finalInvoiceNo,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      aliasName: map['aliasName'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      deliveryDate: deliveryDate,
      city: map['city'] ?? '',
      province: map['province'] ?? '',
      country: map['country'] ?? 'INDONESIA',
      items: itemsList,
      grandTotal: finalGrandTotal,
      note: map['note'] ?? '',
      status: status,
      statusTransfer: map['statusTransfer'] ?? 'UNPAID',
      transferDate: (map['transferDate'] as Timestamp?)?.toDate(),
      erpSyncDate: (map['erpSyncDate'] as Timestamp?)?.toDate(),
      createdBy: map['createdBy'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      returnAmount: retAmt,
      hasReturn: hasRet,
      movedItems: movedItemsList,
      movedToInvoice: map['movedToInvoice'] ?? '',
      isLocked: map['isLocked'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
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
      'returnAmount': returnAmount,
      'hasReturn': hasReturn,
      'movedItems': movedItems.map((item) => item.toMap()).toList(),
      'movedToInvoice': movedToInvoice,
      'isLocked': isLocked,
    };
  }
}
