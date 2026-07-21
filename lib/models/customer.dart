class Customer {
  final String id; // maps to ID CUST
  final String customerName; // maps to CUSTOMER
  final String aliasName; // maps to NAMA PELANGGAN
  final String address; // maps to ALAMAT
  final String city; // maps to KOTA/KABUPATEN
  final String province;
  final String country;
  final String phone;
  final String ktpNumber;

  Customer({
    required this.id,
    required this.customerName,
    required this.aliasName,
    required this.address,
    required this.city,
    required this.province,
    required this.country,
    required this.phone,
    required this.ktpNumber,
  });

  String get displayName {
    final name = customerName.trim();
    final alias = aliasName.trim();
    if (name.isNotEmpty && alias.isNotEmpty && name.toLowerCase() != alias.toLowerCase()) {
      return '$name ($alias)';
    }
    return name.isNotEmpty ? name : alias;
  }

  factory Customer.fromMap(Map<String, dynamic> map, String docId) {
    return Customer(
      id: docId,
      customerName: map['customerName'] ?? '',
      aliasName: map['aliasName'] ?? '',
      address: map['address'] ?? '',
      city: map['city'] ?? '',
      province: map['province'] ?? '',
      country: map['country'] ?? 'INDONESIA',
      phone: map['phone'] ?? '',
      ktpNumber: map['ktpNumber'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerName': customerName,
      'aliasName': aliasName,
      'address': address,
      'city': city,
      'province': province,
      'country': country,
      'phone': phone,
      'ktpNumber': ktpNumber,
    };
  }
}
