import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_sound_service.dart';

/// Handler background pesan FCM (wajib top-level & anotasi pragma)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[WAVIS FCM BG] 📬 Pesan FCM masuk saat aplikasi tertutup: ${message.messageId}');
  if (message.notification != null) {
    debugPrint('[WAVIS FCM BG] Judul: ${message.notification?.title}, Isi: ${message.notification?.body}');
  }
}

class WavisFcmService {
  static final WavisFcmService _instance = WavisFcmService._internal();
  static WavisFcmService get instance => _instance;
  WavisFcmService._internal();

  static const String topicName = 'wavis_alerts';
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Registrasi background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Web handling: Web push butuh VAPID key / service worker.
      // Jika di web, jangan sampai crash jika service worker belum terdaftar.
      if (kIsWeb) {
        debugPrint('[WAVIS FCM] Berjalan di Web. Melewati subscribe native Android.');
        return;
      }

      final messaging = FirebaseMessaging.instance;

      // 1. Minta izin notifikasi (Android 13+ / iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('[WAVIS FCM] 🛡️ Status Izin Notifikasi: ${settings.authorizationStatus}');

      // 2. Berlangganan topik notifikasi 'wavis_alerts'
      await messaging.subscribeToTopic(topicName);
      debugPrint('[WAVIS FCM] 📡 Berhasil berlangganan ke topik: $topicName');

      // 3. Listener saat aplikasi sedang DIBUKA (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[WAVIS FCM FG] 🔔 Notifikasi diterima saat aplikasi dibuka:');
        final notif = message.notification;
        if (notif != null) {
          debugPrint('   👉 ${notif.title}: ${notif.body}');
          // Putar suara notifikasi cihuy jika ada alert baru
          try {
            NotificationSoundService().playCihuyAlert();
          } catch (_) {}
        }
      });

      // 4. Listener saat notifikasi DIKLIK oleh user
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[WAVIS FCM] 👆 Notifikasi diklik! Data: ${message.data}');
      });

      // Ambil token perangkat (opsional untuk debug)
      final token = await messaging.getToken();
      debugPrint('[WAVIS FCM] 🔑 FCM Device Token: ${token != null ? token.substring(0, 15) : "null"}...');

    } catch (e) {
      debugPrint('[WAVIS FCM ERROR] Gagal inisialisasi FCM: $e');
    }
  }
}
