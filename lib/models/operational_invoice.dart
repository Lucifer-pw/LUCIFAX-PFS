import 'package:cloud_firestore/cloud_firestore.dart';

class OperationalInvoiceItem {
  final String title;
  final String category;
  final double amount;
  final String note;

  OperationalInvoiceItem({
    required this.title,
    required this.category,
    required this.amount,
    this.note = '',
  });

  factory OperationalInvoiceItem.fromMap(Map<String, dynamic> map) {
    return OperationalInvoiceItem(
      title: map['title'] ?? map['name'] ?? '',
      category: map['category'] ?? 'Biaya Operasional',
      amount: (map['amount'] ?? map['price'] ?? 0.0).toDouble(),
      note: map['note'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'amount': amount,
      'note': note,
    };
  }
}

class OperationalInvoice {
  final String id;
  final String invoiceNo;
  final List<OperationalInvoiceItem> items;
  final DateTime date;
  final String status; // 'LUNAS', 'PENDING', 'DIKLAIM'
  final String paymentMethod; // 'DANA / E-Wallet', 'Transfer Bank', 'Cash'
  final String createdBy;
  final DateTime createdAt;

  OperationalInvoice({
    required this.id,
    required this.invoiceNo,
    required this.items,
    required this.date,
    required this.status,
    required this.paymentMethod,
    required this.createdBy,
    required this.createdAt,
  });

  double get amount => items.fold(0.0, (acc, item) => acc + item.amount);
  String get title => items.isNotEmpty ? items.first.title : 'Tagihan Biaya Operasional';
  String get category => items.isNotEmpty ? items.first.category : 'Biaya Operasional';
  String get note => items.map((i) => i.note).where((n) => n.isNotEmpty).join(' | ');

  factory OperationalInvoice.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<OperationalInvoiceItem> parsedItems = [];
    if (map['items'] != null && map['items'] is List) {
      parsedItems = (map['items'] as List)
          .map((i) => OperationalInvoiceItem.fromMap(Map<String, dynamic>.from(i)))
          .toList();
    }

    // Fallback backward compatibility for legacy single-item documents
    if (parsedItems.isEmpty) {
      parsedItems = [
        OperationalInvoiceItem(
          title: map['title'] ?? 'Tagihan Biaya Operasional',
          category: map['category'] ?? 'Biaya Operasional',
          amount: (map['amount'] ?? 0.0).toDouble(),
          note: map['note'] ?? '',
        )
      ];
    }

    return OperationalInvoice(
      id: docId,
      invoiceNo: map['invoiceNo'] ?? '',
      items: parsedItems,
      date: parseDate(map['date']),
      status: map['status'] ?? 'LUNAS',
      paymentMethod: map['paymentMethod'] ?? 'DANA / E-Wallet',
      createdBy: map['createdBy'] ?? '',
      createdAt: parseDate(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
      'title': title,
      'category': category,
      'amount': amount,
      'note': note,
      'items': items.map((i) => i.toMap()).toList(),
      'date': Timestamp.fromDate(date),
      'status': status,
      'paymentMethod': paymentMethod,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
