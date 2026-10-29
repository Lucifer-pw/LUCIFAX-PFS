class WaAutoPoSettings {
  final bool autoPoEnabled;
  final bool strictWhitelistOnly;
  final bool autoSettleTransferSlips; // Opsi B (true: Otomatis Penuh / Zero-Click), Opsi A (false: Konfirmasi Kasir)
  final List<String> whitelistNumbers;
  final List<Map<String, String>> whitelistContacts; // [{ 'phone': '08123...', 'name': 'Pak BC' }]

  WaAutoPoSettings({
    this.autoPoEnabled = false,
    this.strictWhitelistOnly = true,
    this.autoSettleTransferSlips = true,
    this.whitelistNumbers = const [],
    this.whitelistContacts = const [],
  });

  factory WaAutoPoSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return WaAutoPoSettings();
    }

    final rawList = map['whitelistContacts'] as List<dynamic>? ?? [];
    final contacts = <Map<String, String>>[];
    final numbers = <String>[];

    for (var it in rawList) {
      if (it is Map) {
        final phone = (it['phone'] ?? '').toString().trim();
        final name = (it['name'] ?? '').toString().trim();
        if (phone.isNotEmpty) {
          final clean = phone.replaceAll(RegExp(r'\D'), '');
          contacts.add({'phone': phone, 'name': name.isNotEmpty ? name : 'Kontak WA'});
          if (clean.isNotEmpty && !numbers.contains(clean)) {
            numbers.add(clean);
          }
        }
      }
    }

    // Fallback to flat whitelistNumbers ONLY if whitelistContacts was completely empty
    if (contacts.isEmpty) {
      final rawNumbers = map['whitelistNumbers'] as List<dynamic>? ?? [];
      for (var n in rawNumbers) {
        final clean = n.toString().replaceAll(RegExp(r'\D'), '').trim();
        if (clean.isNotEmpty && !numbers.contains(clean)) {
          numbers.add(clean);
          contacts.add({'phone': clean, 'name': 'Kontak Whitelist'});
        }
      }
    }

    return WaAutoPoSettings(
      autoPoEnabled: map['autoPoEnabled'] == true,
      strictWhitelistOnly: map['strictWhitelistOnly'] ?? true,
      autoSettleTransferSlips: map['autoSettleTransferSlips'] ?? true,
      whitelistNumbers: numbers,
      whitelistContacts: contacts,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'autoPoEnabled': autoPoEnabled,
      'strictWhitelistOnly': strictWhitelistOnly,
      'autoSettleTransferSlips': autoSettleTransferSlips,
      'whitelistNumbers': whitelistNumbers,
      'whitelistContacts': whitelistContacts,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  WaAutoPoSettings copyWith({
    bool? autoPoEnabled,
    bool? strictWhitelistOnly,
    bool? autoSettleTransferSlips,
    List<String>? whitelistNumbers,
    List<Map<String, String>>? whitelistContacts,
  }) {
    final newContacts = whitelistContacts ?? this.whitelistContacts;
    final newNumbers = whitelistNumbers ?? (whitelistContacts != null
        ? newContacts.map((c) => (c['phone'] ?? '').replaceAll(RegExp(r'\D'), '')).where((s) => s.isNotEmpty).toSet().toList()
        : this.whitelistNumbers);

    return WaAutoPoSettings(
      autoPoEnabled: autoPoEnabled ?? this.autoPoEnabled,
      strictWhitelistOnly: strictWhitelistOnly ?? this.strictWhitelistOnly,
      autoSettleTransferSlips: autoSettleTransferSlips ?? this.autoSettleTransferSlips,
      whitelistNumbers: newNumbers,
      whitelistContacts: newContacts,
    );
  }
}
