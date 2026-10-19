import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'po_alert_service.dart';

class NotificationSoundService extends ChangeNotifier {
  static final NotificationSoundService _instance = NotificationSoundService._internal();
  factory NotificationSoundService() => _instance;
  NotificationSoundService._internal() {
    _loadMutePreference();
  }

  static const String _prefMuteKey = 'pref_po_notification_muted';
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  Future<void> _loadMutePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = prefs.getBool(_prefMuteKey) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMuteKey, _isMuted);
    } catch (_) {}
  }

  Future<void> setMuted(bool val) async {
    if (_isMuted == val) return;
    _isMuted = val;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMuteKey, _isMuted);
    } catch (_) {}
  }

  /// Play the "cihuy.mp3" sound alert across all platforms (Web and Android native)
  Future<void> playCihuyAlert() async {
    if (_isMuted) {
      debugPrint('[NotificationSoundService] Sound is muted, skipping chime.');
      return;
    }
    try {
      await playPlatformAudio();
      debugPrint('[NotificationSoundService] 🔊 Cihuy sound played successfully!');
    } catch (e) {
      debugPrint('[NotificationSoundService] playPlatformAudio failed: $e');
    }
  }

  /// Trigger desktop notification if on Web
  void triggerDesktopNotification({required String title, required String body}) {
    showWebDesktopNotification(title, body);
  }
}
