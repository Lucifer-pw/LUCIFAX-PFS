import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

const MethodChannel _soundChannel = MethodChannel('com.lucifax.pfs/sound');

void showWebDesktopNotification(String title, String body) {
  // No-op on mobile/desktop native platforms
}

Future<void> playPlatformAudio() async {
  try {
    await _soundChannel.invokeMethod('playCihuy');
  } catch (e) {
    debugPrint('Native audio play error: $e');
  }
}
