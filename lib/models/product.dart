class Product {
  final String id; // unique doc ID
  final String kodeInduk; // parent group code (e.g. BRSM-500)
  final String name; // maps to NAMA_BARANG
  final double price;
  final double stock;
  final int isiKarton;
  final double sizeGrams;

  Product({
    required this.id,
    String? kodeInduk,
    required this.name,
    required this.price,
    required this.stock,
    required this.isiKarton,
    required this.sizeGrams,
  }) : kodeInduk = (kodeInduk != null && kodeInduk.isNotEmpty) ? kodeInduk : id;

  factory Product.fromMap(Map<String, dynamic> map, String docId) {
    final rawKodeInduk = map['kodeInduk']?.toString();
    return Product(
      id: docId,
      kodeInduk: (rawKodeInduk != null && rawKodeInduk.isNotEmpty) ? rawKodeInduk : docId,
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      stock: (map['stock'] ?? 0.0).toDouble(),
      isiKarton: map['isiKarton'] ?? 0,
      sizeGrams: (map['sizeGrams'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'kodeInduk': kodeInduk,
      'name': name,
      'price': price,
      'stock': stock,
      'isiKarton': isiKarton,
      'sizeGrams': sizeGrams,
    };
  }

  // Parse size from product name, e.g. "BAKSO AYAM 250 G" -> 250
  static double parseSizeFromName(String name) {
    name = name.toUpperCase();
    final regex = RegExp(r'(\d+)\s*G');
    final match = regex.firstMatch(name);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '0') ?? 0.0;
    }
    return 0.0;
  }

  Product copyWith({
    String? id,
    String? kodeInduk,
    String? name,
    double? price,
    double? stock,
    int? isiKarton,
    double? sizeGrams,
  }) {
    return Product(
      id: id ?? this.id,
      kodeInduk: kodeInduk ?? this.kodeInduk,
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      isiKarton: isiKarton ?? this.isiKarton,
      sizeGrams: sizeGrams ?? this.sizeGrams,
    );
  }
}
