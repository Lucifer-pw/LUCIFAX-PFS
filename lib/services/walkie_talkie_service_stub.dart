import 'dart:async';
import 'package:flutter/foundation.dart';

class WalkieTalkieService extends ChangeNotifier {
  static final WalkieTalkieService _instance = WalkieTalkieService._internal();
  factory WalkieTalkieService() => _instance;
  WalkieTalkieService._internal();

  bool get isInitialized => false;
  bool get isTransmitting => false;
  bool get isReceiving => false;
  bool get isSpeakerMuted => false;
  bool get hasMicPermission => false;
  bool get isChannelBusy => false;
  double get speakerVolume => 1.0;
  int get connectedPeerCount => 0;
  Set<String> get connectedPeerIds => const {};

  String? get currentSpeakerId => null;
  String? get currentSpeakerName => null;
  String? get currentTargetId => null;
  String get currentTargetName => 'Semua Staff (Broadcast)';
  String get statusMessage => 'WebRTC Walkie-Talkie hanya didukung di Web.';

  bool isPeerConnected(String uid) => false;

  Future<bool> initialize({
    required String userId,
    required String userName,
    required String role,
  }) async {
    debugPrint("WalkieTalkieService: Platform non-web tidak didukung.");
    return false;
  }

  Future<void> startTransmitting() async {}
  Future<void> stopTransmitting() async {}
  Future<void> toggleTransmitting() async {}
  void setTarget({String? targetId, String? targetName}) {}
  void toggleSpeakerMute() {}
  void setVolume(double volume) {}
  Future<void> unlockAudio() async {}
  void refreshPeers() {}
}
