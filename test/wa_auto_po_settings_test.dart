import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_app/models/wa_auto_po_settings.dart';

void main() {
  group('WaAutoPoSettings Interactive Tests', () {
    test('Default interactive is true for contacts without explicit interactive field', () {
      final map = {
        'autoPoEnabled': true,
        'strictWhitelistOnly': true,
        'whitelistContacts': [
          {'name': 'Pak Joko', 'phone': '08123456789', 'enabled': 'true'},
          {'name': 'Pak BC', 'phone': '08129876543', 'enabled': 'true', 'interactive': 'false'},
        ]
      };

      final settings = WaAutoPoSettings.fromMap(map);
      expect(settings.whitelistContacts.length, 2);
      expect(settings.whitelistContacts[0]['interactive'], 'true');
      expect(settings.whitelistContacts[1]['interactive'], 'false');

      expect(settings.isInteractiveForPhone('08123456789'), isTrue);
      expect(settings.isInteractiveForPhone('+628123456789'), isTrue);
      expect(settings.isInteractiveForPhone('08129876543'), isFalse);
      expect(settings.isInteractiveForPhone('08999999999'), isFalse);
    });

    test('copyWith updates interactive flag cleanly', () {
      final initial = WaAutoPoSettings(
        whitelistContacts: [
          {'name': 'Pak Joko', 'phone': '08123456789', 'enabled': 'true', 'interactive': 'true'},
        ],
      );

      expect(initial.isInteractiveForPhone('08123456789'), isTrue);

      final updated = initial.copyWith(
        whitelistContacts: [
          {'name': 'Pak Joko', 'phone': '08123456789', 'enabled': 'true', 'interactive': 'false'},
        ],
      );

      expect(updated.isInteractiveForPhone('08123456789'), isFalse);
    });
  });
}
