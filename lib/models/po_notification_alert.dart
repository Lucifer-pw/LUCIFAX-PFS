class PoNotificationAlert {
  final String chatId;
  final String senderName;
  final String senderPhone;
  final List<String> invoiceNos;
  final DateTime timestamp;
  final String rawText;

  PoNotificationAlert({
    required this.chatId,
    required this.senderName,
    required this.senderPhone,
    required this.invoiceNos,
    required this.timestamp,
    required this.rawText,
  });

  bool get isMultiInvoice => invoiceNos.length > 1;
}
