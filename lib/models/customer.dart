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
  final String ktpImageUrl;
  final double depositBalance;
  final String odooNamePtSo; // Nama Customer di Odoo PT SO (e.g. MISTER SOSIS (SUSILO HARYAWAN))
  final String odooDeliveryAddressCvSo; // Nama Delivery Address di Odoo CV SO (e.g. MISTER SOSIS)
  final String mapsUrl; // Link Google Maps lokasi toko / titik pengiriman
  final double? latitude;
  final double? longitude;

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
    this.ktpImageUrl = '',
    this.depositBalance = 0.0,
    this.odooNamePtSo = '',
    this.odooDeliveryAddressCvSo = '',
    this.mapsUrl = '',
    this.latitude,
    this.longitude,
  });

  String get displayName {
    final name = customerName.trim();
    final alias = aliasName.trim();
    if (name.isNotEmpty && alias.isNotEmpty && name.toLowerCase() != alias.toLowerCase()) {
      return '$alias ($name)';
    }
    return alias.isNotEmpty ? alias : name;
  }

  // Fallbacks: if explicit Odoo mapping is empty, use displayName for PT SO and alias/name for CV SO
  String get effectiveOdooPtSo => odooNamePtSo.trim().isNotEmpty ? odooNamePtSo.trim() : displayName;
  String get effectiveOdooCvSo => odooDeliveryAddressCvSo.trim().isNotEmpty
      ? odooDeliveryAddressCvSo.trim()
      : (aliasName.trim().isNotEmpty ? aliasName.trim() : customerName.trim());

  bool get hasValidMapsLocation => mapsUrl.trim().isNotEmpty || (latitude != null && longitude != null);

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
      ktpImageUrl: map['ktpImageUrl'] ?? '',
      depositBalance: (map['depositBalance'] is num) ? (map['depositBalance'] as num).toDouble() : 0.0,
      odooNamePtSo: map['odooNamePtSo']?.toString() ?? '',
      odooDeliveryAddressCvSo: map['odooDeliveryAddressCvSo']?.toString() ?? '',
      mapsUrl: map['mapsUrl']?.toString() ?? '',
      latitude: (map['latitude'] is num) ? (map['latitude'] as num).toDouble() : null,
      longitude: (map['longitude'] is num) ? (map['longitude'] as num).toDouble() : null,
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
      'ktpImageUrl': ktpImageUrl,
      'depositBalance': depositBalance,
      'odooNamePtSo': odooNamePtSo,
      'odooDeliveryAddressCvSo': odooDeliveryAddressCvSo,
      'mapsUrl': mapsUrl,
      'latitude': latitude,
      'longitude': longitude,
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
    String? ktpImageUrl,
    double? depositBalance,
    String? odooNamePtSo,
    String? odooDeliveryAddressCvSo,
    String? mapsUrl,
    double? latitude,
    double? longitude,
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
      ktpImageUrl: ktpImageUrl ?? this.ktpImageUrl,
      depositBalance: depositBalance ?? this.depositBalance,
      odooNamePtSo: odooNamePtSo ?? this.odooNamePtSo,
      odooDeliveryAddressCvSo: odooDeliveryAddressCvSo ?? this.odooDeliveryAddressCvSo,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
