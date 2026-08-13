import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WebRtcScreenService {
  static final WebRtcScreenService _instance = WebRtcScreenService._internal();
  factory WebRtcScreenService() => _instance;
  WebRtcScreenService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool get isBroadcasting => false;
  bool get isViewing => false;

  Future<bool> startBroadcasting({
    required String userId,
    required String userName,
    String sessionId = 'kacab_live',
    VoidCallback? onStoppedByUser,
    Function(String)? onStatusUpdate,
  }) async {
    debugPrint("WebRTC screen share only supported on Web.");
    return false;
  }

  Future<void> stopBroadcasting({String sessionId = 'kacab_live'}) async {}

  Future<void> connectToBroadcast({
    String sessionId = 'kacab_live',
    required Function(dynamic) onRemoteStreamReceived,
    Function(String)? onStatusUpdate,
  }) async {}

  void disconnectViewer() {}

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession({String sessionId = 'kacab_live'}) {
    return _db.collection('webrtc_screen_sessions').doc(sessionId).snapshots();
  }
}
