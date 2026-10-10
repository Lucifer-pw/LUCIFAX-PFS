class ChatOrderItemDraft {
  String productId;
  String productName;
  String rawText;
  String qtyUnit; // 'karton', 'pack', 'roll'
  double qtyInput; // e.g. 35.0 (karton) or 121.0 (pack)
  double qtyPcs; // Total pack / pcs used in TransactionItem
  double price; // Unit price from customer history or master product
  double discountPercent;
  double discountAmount;
  double sizeGrams;
  bool isNewItemForCustomer; // true if customer never bought this before

  ChatOrderItemDraft({
    required this.productId,
    required this.productName,
    required this.rawText,
    required this.qtyUnit,
    required this.qtyInput,
    required this.qtyPcs,
    required this.price,
    this.discountPercent = 0.0,
    this.discountAmount = 0.0,
    this.sizeGrams = 500.0,
    this.isNewItemForCustomer = false,
  });

  double get subtotal {
    final rawTotal = qtyPcs * price;
    if (discountPercent > 0) {
      return (rawTotal * (1 - discountPercent / 100)).clamp(0.0, double.infinity);
    } else if (discountAmount > 0) {
      return (rawTotal - (discountAmount * qtyPcs)).clamp(0.0, double.infinity);
    }
    return rawTotal;
  }
}

class ChatOrderDraft {
  String customerRawName;
  String customerId;
  String customerName;
  String aliasName;
  String city;
  String province;
  List<ChatOrderItemDraft> items;
  String rawChatBlock;
  String note;

  ChatOrderDraft({
    required this.customerRawName,
    this.customerId = '',
    required this.customerName,
    this.aliasName = '',
    this.city = 'SEMARANG',
    this.province = 'JAWA TENGAH',
    required this.items,
    required this.rawChatBlock,
    this.note = '',
  });

  double get grandTotal => items.fold(0.0, (sum, item) => sum + item.subtotal);
  double get totalKarton {
    // If unit is karton, sum qtyInput. Otherwise estimate from qtyPcs
    double total = 0.0;
    for (var item in items) {
      if (item.qtyUnit.toLowerCase() == 'karton') {
        total += item.qtyInput;
      }
    }
    return total;
  }
}
