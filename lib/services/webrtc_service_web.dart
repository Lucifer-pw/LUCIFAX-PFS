import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

class WebRtcScreenService {
  static final WebRtcScreenService _instance = WebRtcScreenService._internal();
  factory WebRtcScreenService() => _instance;
  WebRtcScreenService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  html.RtcPeerConnection? _peerConnection;
  html.MediaStream? _localStream;
  StreamSubscription? _sessionSubscription;
  bool _isBroadcasting = false;
  bool _isViewing = false;

  bool get isBroadcasting => _isBroadcasting;
  bool get isViewing => _isViewing;

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  // ══════════════════════════════════════════════════════════
  // KACAB / PRESENTER: START SCREEN SHARE (PROVEN VANILLA ICE)
  // ══════════════════════════════════════════════════════════

  Future<bool> startBroadcasting({
    required String userId,
    required String userName,
    String sessionId = 'kacab_live',
    VoidCallback? onStoppedByUser,
    Function(String)? onStatusUpdate,
  }) async {
    if (!kIsWeb) return false;

    try {
      onStatusUpdate?.call('Meminta izin tangkapan layar...');

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception("Browser tidak mendukung MediaDevices.");
      }

      final displayMediaOptions = {
        'video': {
          'cursor': 'always',
          'frameRate': {'ideal': 30, 'max': 60},
        },
        'audio': false,
        'preferCurrentTab': true,
        'selfBrowserSurface': 'include',
      };

      final jsPromise = js_util.callMethod(
        mediaDevices,
        'getDisplayMedia',
        [js_util.jsify(displayMediaOptions)],
      );

      _localStream = await js_util.promiseToFuture<html.MediaStream>(jsPromise);
      if (_localStream == null || _localStream!.getVideoTracks().isEmpty) {
        throw Exception("Gagal menangkap layar.");
      }

      _isBroadcasting = true;
      onStatusUpdate?.call('Layar aktif, menyiapkan sinyal video...');

      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.onEnded.listen((_) {
        stopBroadcasting(sessionId: sessionId);
        if (onStoppedByUser != null) onStoppedByUser();
      });

      // Close previous connection if any
      _peerConnection?.close();
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      // Add track to peer connection
      _peerConnection!.addTrack(videoTrack, _localStream!);

      // Create Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      // Wait 1.2s for ICE Gathering to bundle all candidates inside SDP
      await Future.delayed(const Duration(milliseconds: 1200));

      // Get localDescription with embedded ICE candidates
      final localDesc = _peerConnection!.localDescription;
      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);

      // Save SINGLE document write with full SDP offer
      await sessionRef.set({
        'sessionId': sessionId,
        'broadcasterId': userId,
        'broadcasterName': userName,
        'status': 'active',
        'offer': {
          'sdp': localDesc?.sdp ?? offer.sdp,
          'type': localDesc?.type ?? offer.type,
        },
        'answer': null,
        'startedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      onStatusUpdate?.call('Siaran aktif, menunggu Developer...');

      // Listen for Answer from Developer
      String? lastAnswerSdp;
      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data != null && data['answer'] != null && _peerConnection != null) {
          final answer = data['answer'] as Map<String, dynamic>;
          final sdp = answer['sdp'] as String?;
          if (sdp != null && sdp != lastAnswerSdp) {
            lastAnswerSdp = sdp;
            try {
              await _peerConnection!.setRemoteDescription({
                'sdp': sdp,
                'type': answer['type'] ?? 'answer',
              });
              onStatusUpdate?.call('Terhubung ke Developer!');
            } catch (e) {
              debugPrint("Error setting remote answer on broadcaster: $e");
            }
          }
        }
      });

      return true;
    } catch (e) {
      debugPrint("Error starting screen broadcast: $e");
      await stopBroadcasting(sessionId: sessionId);
      return false;
    }
  }

  Future<void> stopBroadcasting({String sessionId = 'kacab_live'}) async {
    _isBroadcasting = false;
    _sessionSubscription?.cancel();

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream = null;
    }

    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }

    try {
      await _db.collection('webrtc_screen_sessions').doc(sessionId).set({
        'status': 'ended',
        'endedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════
  // DEVELOPER / VIEWER: CONNECT (VANILLA ICE - 1 WRITE ONLY)
  // ══════════════════════════════════════════════════════════

  Future<void> connectToBroadcast({
    String sessionId = 'kacab_live',
    required Function(dynamic) onRemoteStreamReceived,
    Function(String)? onStatusUpdate,
  }) async {
    if (!kIsWeb) return;

    try {
      _isViewing = true;
      onStatusUpdate?.call('Mengambil data siaran...');

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);
      final sessionSnap = await sessionRef.get();

      if (!sessionSnap.exists) {
        throw Exception("Sesi siaran belum dimulai.");
      }

      final data = sessionSnap.data()!;
      if (data['status'] != 'active' || data['offer'] == null) {
        throw Exception("Sesi siaran sedang tidak aktif.");
      }

      _peerConnection?.close();
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      // Listen for remote tracks
      _peerConnection!.onTrack.listen((event) {
        debugPrint("Viewer onTrack event received: ${event.streams}");
        if (event.streams != null && event.streams!.isNotEmpty) {
          onRemoteStreamReceived(event.streams!.first);
          onStatusUpdate?.call('Siaran Langsung Terhubung (60 FPS)');
        } else if (event.track != null) {
          final stream = html.MediaStream([event.track!]);
          onRemoteStreamReceived(stream);
          onStatusUpdate?.call('Siaran Langsung Terhubung (60 FPS)');
        }
      });

      _peerConnection!.onIceConnectionStateChange.listen((_) {
        final state = _peerConnection?.iceConnectionState ?? '';
        debugPrint("Viewer ICE State: $state");
        if (state == 'connected' || state == 'completed') {
          onStatusUpdate?.call('Terhubung Lancar (60 FPS)');
        } else if (state == 'checking') {
          onStatusUpdate?.call('Menyambungkan (Checking)...');
        }
      });

      // 1. Set Remote Description (Offer from Broadcaster)
      final offer = data['offer'] as Map<String, dynamic>;
      await _peerConnection!.setRemoteDescription({
        'sdp': offer['sdp'],
        'type': offer['type'],
      });

      // 2. Create SDP Answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription({
        'sdp': answer.sdp,
        'type': answer.type,
      });

      // 3. Wait 1.2s for ICE gathering to bundle all candidates inside SDP
      await Future.delayed(const Duration(milliseconds: 1200));

      // 4. Save SINGLE Answer document to Firestore (Only 1 Write!)
      final localDesc = _peerConnection!.localDescription;
      await sessionRef.update({
        'answer': {
          'sdp': localDesc?.sdp ?? answer.sdp,
          'type': localDesc?.type ?? answer.type,
        },
        'connectedAt': Timestamp.now(),
      });

      onStatusUpdate?.call('Sinyal terkirim, memutar video...');
    } catch (e) {
      debugPrint("Error connecting as viewer: $e");
      _isViewing = false;
      onStatusUpdate?.call('Gagal: $e');
    }
  }

  void disconnectViewer() {
    _isViewing = false;
    _sessionSubscription?.cancel();
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession({String sessionId = 'kacab_live'}) {
    return _db.collection('webrtc_screen_sessions').doc(sessionId).snapshots();
  }
}
