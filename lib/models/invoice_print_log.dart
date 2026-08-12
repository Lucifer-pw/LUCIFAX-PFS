import 'package:cloud_firestore/cloud_firestore.dart';

class InvoicePrintLog {
  final String id;
  final dynamic invoiceNo;
  final String customerName;
  final DateTime originalDate;
  final DateTime? originalDeliveryDate;
  final DateTime printedDeliveryDate;
  final String optionType; // 'TANGGAL_AWAL' or 'TANGGAL_BARU'
  final String actionType; // 'PRINT' or 'DOWNLOAD'
  final String userId;
  final String userName;
  final String userUsername;
  final String userRole;
  final bool isDeveloper;
  final DateTime timestamp;
  final double grandTotal;

  InvoicePrintLog({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    required this.originalDate,
    this.originalDeliveryDate,
    required this.printedDeliveryDate,
    required this.optionType,
    required this.actionType,
    required this.userId,
    required this.userName,
    required this.userUsername,
    required this.userRole,
    required this.isDeveloper,
    required this.timestamp,
    required this.grandTotal,
  });

  factory InvoicePrintLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val, [DateTime? fallback]) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? (fallback ?? DateTime.now());
      return fallback ?? DateTime.now();
    }

    return InvoicePrintLog(
      id: doc.id,
      invoiceNo: data['invoiceNo'] ?? '',
      customerName: data['customerName'] ?? '',
      originalDate: parseDate(data['originalDate']),
      originalDeliveryDate: data['originalDeliveryDate'] != null ? parseDate(data['originalDeliveryDate']) : null,
      printedDeliveryDate: parseDate(data['printedDeliveryDate']),
      optionType: data['optionType'] ?? 'TANGGAL_AWAL',
      actionType: data['actionType'] ?? 'PRINT',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userUsername: data['userUsername'] ?? '',
      userRole: data['userRole'] ?? 'kacab',
      isDeveloper: data['isDeveloper'] == true,
      timestamp: parseDate(data['timestamp']),
      grandTotal: (data['grandTotal'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
      'customerName': customerName,
      'originalDate': Timestamp.fromDate(originalDate),
      if (originalDeliveryDate != null) 'originalDeliveryDate': Timestamp.fromDate(originalDeliveryDate!),
      'printedDeliveryDate': Timestamp.fromDate(printedDeliveryDate),
      'optionType': optionType,
      'actionType': actionType,
      'userId': userId,
      'userName': userName,
      'userUsername': userUsername,
      'userRole': userRole,
      'isDeveloper': isDeveloper,
      'timestamp': Timestamp.fromDate(timestamp),
      'grandTotal': grandTotal,
    };
  }

  bool get isDateModified => optionType == 'TANGGAL_BARU';
}
