class CustomerProductHistory {
  final String productId;
  final String productName;
  final double price;
  final double discountPercent;
  final double discountAmount;
  final String invoiceNo;
  final DateTime? date;
  final int purchaseCount;

  CustomerProductHistory({
    required this.productId,
    required this.productName,
    required this.price,
    required this.discountPercent,
    required this.discountAmount,
    required this.invoiceNo,
    this.date,
    this.purchaseCount = 1,
  });
}
