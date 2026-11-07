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
  final String messageType; // 'ORDER_PO', 'TRANSFER_SLIP', 'CASUAL_CHAT'
  final bool hasImage;
  final String? imageUrl;
  final String? caption;
  final Map<String, dynamic>? transferInfo;
  final bool isPaymentApplied;
  final String? matchedInvoiceNo;
  final bool isPartialPayment;
  final double remainingAmount;
  final String? quotedInvoiceNo;
  final String? quotedOcrText;
  final String? quotedImageUrl;
  final String? quotedMessageText;
  final String? quotedStanzaId;
  final bool isForwarded;
  final bool isQuotedReply;
  final String? rawOcrText;

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
    this.messageType = 'ORDER_PO',
    this.hasImage = false,
    this.imageUrl,
    this.caption,
    this.transferInfo,
    this.isPaymentApplied = false,
    this.matchedInvoiceNo,
    this.isPartialPayment = false,
    this.remainingAmount = 0.0,
    this.quotedInvoiceNo,
    this.quotedOcrText,
    this.quotedImageUrl,
    this.quotedMessageText,
    this.quotedStanzaId,
    this.isForwarded = false,
    this.isQuotedReply = false,
    this.rawOcrText,
  });

  bool get isTransferSlip => messageType == 'TRANSFER_SLIP' || transferInfo != null;
  bool get isExpense => transferInfo?['isExpense'] == true;
  String? get expenseCategory => transferInfo?['expenseCategory']?.toString();
  String? get recipientName => transferInfo?['recipient']?.toString();

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

    final rawType = (map['messageType'] ?? '').toString();
    final Map<String, dynamic>? tInfo = map['transferInfo'] is Map ? Map<String, dynamic>.from(map['transferInfo']) : null;
    final String resolvedType = rawType.isNotEmpty
        ? rawType
        : (tInfo != null ? 'TRANSFER_SLIP' : (map['isOrderDetected'] == true ? 'ORDER_PO' : 'CASUAL_CHAT'));

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
      messageType: resolvedType,
      hasImage: map['hasImage'] == true || map['imageUrl'] != null,
      imageUrl: map['imageUrl'] as String?,
      caption: map['caption'] as String?,
      transferInfo: tInfo,
      isPaymentApplied: map['isPaymentApplied'] == true,
      matchedInvoiceNo: (map['matchedInvoiceNo'] ?? tInfo?['invoiceNo'])?.toString(),
      isPartialPayment: map['isPartialPayment'] == true || (tInfo?['isPartial'] == true),
      remainingAmount: ((map['remainingAmount'] ?? tInfo?['remainingAmount'] ?? 0) as num).toDouble(),
      quotedInvoiceNo: map['quotedInvoiceNo']?.toString(),
      quotedOcrText: map['quotedOcrText']?.toString(),
      quotedImageUrl: map['quotedImageUrl']?.toString(),
      quotedMessageText: map['quotedMessageText']?.toString(),
      quotedStanzaId: map['quotedStanzaId']?.toString(),
      isForwarded: map['isForwarded'] == true,
      isQuotedReply: map['isQuotedReply'] == true,
      rawOcrText: (map['rawOcrText'] ?? tInfo?['rawOcrText'] ?? map['quotedOcrText'])?.toString(),
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
      'messageType': messageType,
      'hasImage': hasImage,
      'imageUrl': imageUrl,
      'caption': caption,
      'transferInfo': transferInfo,
      'isPaymentApplied': isPaymentApplied,
      'matchedInvoiceNo': matchedInvoiceNo,
      'isPartialPayment': isPartialPayment,
      'remainingAmount': remainingAmount,
      'quotedInvoiceNo': quotedInvoiceNo,
      'quotedOcrText': quotedOcrText,
      'quotedImageUrl': quotedImageUrl,
      'quotedMessageText': quotedMessageText,
      'quotedStanzaId': quotedStanzaId,
      'isForwarded': isForwarded,
      'isQuotedReply': isQuotedReply,
      'rawOcrText': rawOcrText,
    };
  }

  IncomingPoChat copyWith({
    String? status,
    DateTime? processedAt,
    String? createdInvoiceNo,
    String? createdTransactionId,
    String? dismissReason,
    String? messageType,
    bool? hasImage,
    String? imageUrl,
    String? caption,
    Map<String, dynamic>? transferInfo,
    bool? isPaymentApplied,
    String? matchedInvoiceNo,
    bool? isPartialPayment,
    double? remainingAmount,
    String? quotedInvoiceNo,
    String? quotedOcrText,
    String? quotedImageUrl,
    String? quotedMessageText,
    String? quotedStanzaId,
    bool? isForwarded,
    bool? isQuotedReply,
    String? rawOcrText,
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
      messageType: messageType ?? this.messageType,
      hasImage: hasImage ?? this.hasImage,
      imageUrl: imageUrl ?? this.imageUrl,
      caption: caption ?? this.caption,
      transferInfo: transferInfo ?? this.transferInfo,
      isPaymentApplied: isPaymentApplied ?? this.isPaymentApplied,
      matchedInvoiceNo: matchedInvoiceNo ?? this.matchedInvoiceNo,
      isPartialPayment: isPartialPayment ?? this.isPartialPayment,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      quotedInvoiceNo: quotedInvoiceNo ?? this.quotedInvoiceNo,
      quotedOcrText: quotedOcrText ?? this.quotedOcrText,
      quotedImageUrl: quotedImageUrl ?? this.quotedImageUrl,
      quotedMessageText: quotedMessageText ?? this.quotedMessageText,
      quotedStanzaId: quotedStanzaId ?? this.quotedStanzaId,
      isForwarded: isForwarded ?? this.isForwarded,
      isQuotedReply: isQuotedReply ?? this.isQuotedReply,
      rawOcrText: rawOcrText ?? this.rawOcrText,
    );
  }
}
