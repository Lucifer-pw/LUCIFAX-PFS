import 'package:cloud_firestore/cloud_firestore.dart';

class RemotePrintCommand {
  final String id;
  final int invoiceNo;
  final String customerName;
  final DateTime? deliveryDate;
  final DateTime printedDeliveryDate;
  final String optionType; // 'TANGGAL_BARU' | 'TANGGAL_AWAL'
  final String status; // 'PENDING' | 'PROCESSING' | 'COMPLETED' | 'FAILED'
  final String requestedByUserId;
  final String requestedByUserName;
  final String? targetUserId;
  final String targetUserRole; // 'kacab' | 'all'
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? errorMessage;
  final String? printerStationName;
  final double grandTotal;

  RemotePrintCommand({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    this.deliveryDate,
    required this.printedDeliveryDate,
    required this.optionType,
    required this.status,
    required this.requestedByUserId,
    required this.requestedByUserName,
    this.targetUserId,
    this.targetUserRole = 'kacab',
    required this.createdAt,
    this.processedAt,
    this.errorMessage,
    this.printerStationName,
    this.grandTotal = 0.0,
  });

  factory RemotePrintCommand.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        try {
          return DateTime.parse(val);
        } catch (_) {}
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        try {
          return DateTime.parse(val);
        } catch (_) {}
      }
      return null;
    }

    return RemotePrintCommand(
      id: doc.id,
      invoiceNo: data['invoiceNo'] is int
          ? data['invoiceNo']
          : int.tryParse(data['invoiceNo']?.toString() ?? '0') ?? 0,
      customerName: data['customerName']?.toString() ?? '',
      deliveryDate: parseNullableDate(data['deliveryDate']),
      printedDeliveryDate: parseDate(data['printedDeliveryDate']),
      optionType: data['optionType']?.toString() ?? 'TANGGAL_AWAL',
      status: data['status']?.toString() ?? 'PENDING',
      requestedByUserId: data['requestedByUserId']?.toString() ?? '',
      requestedByUserName: data['requestedByUserName']?.toString() ?? 'Developer',
      targetUserId: data['targetUserId']?.toString(),
      targetUserRole: data['targetUserRole']?.toString() ?? 'kacab',
      createdAt: parseDate(data['createdAt']),
      processedAt: parseNullableDate(data['processedAt']),
      errorMessage: data['errorMessage']?.toString(),
      printerStationName: data['printerStationName']?.toString(),
      grandTotal: (data['grandTotal'] is num) ? (data['grandTotal'] as num).toDouble() : 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoiceNo': invoiceNo,
      'customerName': customerName,
      'deliveryDate': deliveryDate != null ? Timestamp.fromDate(deliveryDate!) : null,
      'printedDeliveryDate': Timestamp.fromDate(printedDeliveryDate),
      'optionType': optionType,
      'status': status,
      'requestedByUserId': requestedByUserId,
      'requestedByUserName': requestedByUserName,
      'targetUserId': targetUserId,
      'targetUserRole': targetUserRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'processedAt': processedAt != null ? Timestamp.fromDate(processedAt!) : null,
      'errorMessage': errorMessage,
      'printerStationName': printerStationName,
      'grandTotal': grandTotal,
    };
  }

  bool get isPending => status == 'PENDING';
  bool get isProcessing => status == 'PROCESSING';
  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
}
