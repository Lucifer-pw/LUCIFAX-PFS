class Product {
  final String id; // maps to KODE_INDUK
  final String name; // maps to NAMA_BARANG
  final double price;
  final double stock;
  final int isiKarton;
  final double sizeGrams;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.isiKarton,
    required this.sizeGrams,
  });

  factory Product.fromMap(Map<String, dynamic> map, String docId) {
    return Product(
      id: docId,
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      stock: (map['stock'] ?? 0.0).toDouble(),
      isiKarton: map['isiKarton'] ?? 0,
      sizeGrams: (map['sizeGrams'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
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
}
