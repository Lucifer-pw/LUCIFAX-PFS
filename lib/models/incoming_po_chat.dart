import 'package:cloud_firestore/cloud_firestore.dart';

class IncomingPoChat {
  final String id;
  final String senderJid;
  final String senderPhone;
  final String senderName;
  final String messageText;
  final DateTime receivedAt;
  final String status; // 'pending', 'processed', 'dismissed'
  final DateTime? processedAt;
  final bool isOrderDetected;
  final String? createdInvoiceNo;
  final String? createdTransactionId;
  final String? dismissReason;

  IncomingPoChat({
    required this.id,
    required this.senderJid,
    required this.senderPhone,
    required this.senderName,
    required this.messageText,
    required this.receivedAt,
    this.status = 'pending',
    this.processedAt,
    this.isOrderDetected = false,
    this.createdInvoiceNo,
    this.createdTransactionId,
    this.dismissReason,
  });

  factory IncomingPoChat.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        try {
          return DateTime.parse(val);
        } catch (_) {}
      }
      return DateTime.now();
    }

    return IncomingPoChat(
      id: id,
      senderJid: (map['senderJid'] ?? map['sender'] ?? '').toString(),
      senderPhone: (map['senderPhone'] ?? map['phone'] ?? '').toString(),
      senderName: (map['senderName'] ?? map['pushName'] ?? 'Tanpa Nama').toString(),
      messageText: (map['messageText'] ?? map['text'] ?? map['rawText'] ?? '').toString(),
      receivedAt: parseDate(map['receivedAt'] ?? map['timestamp'] ?? map['createdAt']),
      status: (map['status'] ?? 'pending').toString(),
      processedAt: map['processedAt'] != null ? parseDate(map['processedAt']) : null,
      isOrderDetected: map['isOrderDetected'] == true,
      createdInvoiceNo: map['createdInvoiceNo'] as String?,
      createdTransactionId: map['createdTransactionId'] as String?,
      dismissReason: map['dismissReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderJid': senderJid,
      'senderPhone': senderPhone,
      'senderName': senderName,
      'messageText': messageText,
      'receivedAt': Timestamp.fromDate(receivedAt),
      'status': status,
      'processedAt': processedAt != null ? Timestamp.fromDate(processedAt!) : null,
      'isOrderDetected': isOrderDetected,
      'createdInvoiceNo': createdInvoiceNo,
      'createdTransactionId': createdTransactionId,
      'dismissReason': dismissReason,
    };
  }

  IncomingPoChat copyWith({
    String? status,
    DateTime? processedAt,
    String? createdInvoiceNo,
    String? createdTransactionId,
    String? dismissReason,
  }) {
    return IncomingPoChat(
      id: id,
      senderJid: senderJid,
      senderPhone: senderPhone,
      senderName: senderName,
      messageText: messageText,
      receivedAt: receivedAt,
      status: status ?? this.status,
      processedAt: processedAt ?? this.processedAt,
      isOrderDetected: isOrderDetected,
      createdInvoiceNo: createdInvoiceNo ?? this.createdInvoiceNo,
      createdTransactionId: createdTransactionId ?? this.createdTransactionId,
      dismissReason: dismissReason ?? this.dismissReason,
    );
  }
}
