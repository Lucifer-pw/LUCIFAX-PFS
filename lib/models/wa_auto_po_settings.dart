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
        final enabled = (it['enabled'] ?? 'true').toString();
        final isEnabled = enabled != 'false';
        final interactive = (it['interactive'] ?? 'true').toString();
        final isInteractive = interactive != 'false';
        final rawRole = (it['role'] ?? 'OFFICE').toString().toUpperCase();
        final role = (rawRole == 'GENERAL' || rawRole == 'UMUM') ? 'GENERAL' : 'OFFICE';
        if (phone.isNotEmpty) {
          final clean = phone.replaceAll(RegExp(r'\D'), '');
          contacts.add({
            'phone': phone,
            'name': name.isNotEmpty ? name : 'Kontak WA',
            'enabled': isEnabled ? 'true' : 'false',
            'interactive': isInteractive ? 'true' : 'false',
            'role': role,
          });
          if (isEnabled && clean.isNotEmpty && !numbers.contains(clean)) {
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
        ? newContacts
            .where((c) => c['enabled'] != 'false')
            .map((c) => (c['phone'] ?? '').replaceAll(RegExp(r'\D'), ''))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
        : this.whitelistNumbers);

    return WaAutoPoSettings(
      autoPoEnabled: autoPoEnabled ?? this.autoPoEnabled,
      strictWhitelistOnly: strictWhitelistOnly ?? this.strictWhitelistOnly,
      autoSettleTransferSlips: autoSettleTransferSlips ?? this.autoSettleTransferSlips,
      whitelistNumbers: newNumbers,
      whitelistContacts: newContacts,
    );
  }

  static String normalizePhoneDigits(String p) {
    var s = p.replaceAll(RegExp(r'\D'), '');
    if (s.startsWith('08')) s = '628${s.substring(2)}';
    return s;
  }

  /// Mengecek apakah suatu nomor memiliki status Interactive (I) aktif
  bool isInteractiveForPhone(String phone) {
    final clean = normalizePhoneDigits(phone);
    if (clean.isEmpty) return false;
    for (final c in whitelistContacts) {
      final cp = normalizePhoneDigits(c['phone'] ?? '');
      if (cp.isNotEmpty && (clean.endsWith(cp) || cp.endsWith(clean) || clean == cp)) {
        return c['interactive'] != 'false';
      }
    }
    return false;
  }

  /// Mengecek peran kontak: 'OFFICE' (Kantor), 'GENERAL' (Umum), atau 'NONE'
  String getContactRole(String phone) {
    final clean = normalizePhoneDigits(phone);
    if (clean.isEmpty) return 'NONE';
    for (final c in whitelistContacts) {
      final cp = normalizePhoneDigits(c['phone'] ?? '');
      if (cp.isNotEmpty && (clean.endsWith(cp) || cp.endsWith(clean) || clean == cp)) {
        final role = (c['role'] ?? 'OFFICE').toUpperCase();
        return (role == 'GENERAL' || role == 'UMUM') ? 'GENERAL' : 'OFFICE';
      }
    }
    return 'NONE';
  }

  /// Mengecek apakah suatu kontak berstatus Tim Kantor / Internal PFS
  bool isOfficeForPhone(String phone) {
    return getContactRole(phone) == 'OFFICE';
  }
}
