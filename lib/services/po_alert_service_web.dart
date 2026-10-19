// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

void showWebDesktopNotification(String title, String body) {
  try {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body, icon: 'icons/Icon-192.png');
    } else if (html.Notification.permission != 'denied') {
      html.Notification.requestPermission().then((permission) {
        if (permission == 'granted') {
          html.Notification(title, body: body, icon: 'icons/Icon-192.png');
        }
      });
    }
  } catch (e) {
    debugPrint('Web desktop notification error: $e');
  }
}

void playPlatformAudioFallback() {
  try {
    final audio = html.AudioElement('assets/notifications/cihuy.mp3');
    audio.play().catchError((e) {
      debugPrint('HTML5 audio play error: $e');
    });
  } catch (e) {
    debugPrint('HTML5 fallback error: $e');
  }
}
