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
  final double depositBalance;

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
    this.depositBalance = 0.0,
  });

  String get displayName {
    final name = customerName.trim();
    final alias = aliasName.trim();
    if (name.isNotEmpty && alias.isNotEmpty && name.toLowerCase() != alias.toLowerCase()) {
      return '$alias ($name)';
    }
    return alias.isNotEmpty ? alias : name;
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
      depositBalance: (map['depositBalance'] is num) ? (map['depositBalance'] as num).toDouble() : 0.0,
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
      'depositBalance': depositBalance,
    };
  }

  Customer copyWith({
    String? id,
    String? customerName,
    String? aliasName,
    String? address,
    String? city,
    String? province,
    String? country,
    String? phone,
    String? ktpNumber,
    double? depositBalance,
  }) {
    return Customer(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      aliasName: aliasName ?? this.aliasName,
      address: address ?? this.address,
      city: city ?? this.city,
      province: province ?? this.province,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      ktpNumber: ktpNumber ?? this.ktpNumber,
      depositBalance: depositBalance ?? this.depositBalance,
    );
  }
}
