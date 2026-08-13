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
  StreamSubscription? _viewerSubscription;
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
  // KACAB / PRESENTER: START SCREEN SHARE (ON-DEMAND RECONNECT)
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
      onStatusUpdate?.call('Layar aktif, menyiapkan sinyal...');

      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.onEnded.listen((_) {
        stopBroadcasting(sessionId: sessionId);
        if (onStoppedByUser != null) onStoppedByUser();
      });

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);

      // Function to generate a fresh offer for a viewer
      Future<void> createAndSendOffer() async {
        if (!_isBroadcasting || _localStream == null) return;
        try {
          _peerConnection?.close();
          _peerConnection = html.RtcPeerConnection(_rtcConfig);

          final currentTracks = _localStream!.getVideoTracks();
          if (currentTracks.isNotEmpty) {
            _peerConnection!.addTrack(currentTracks.first, _localStream!);
          }

          final offer = await _peerConnection!.createOffer();
          await _peerConnection!.setLocalDescription({
            'sdp': offer.sdp,
            'type': offer.type,
          });

          await Future.delayed(const Duration(milliseconds: 800));
          final localDesc = _peerConnection!.localDescription;

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
          }, SetOptions(merge: true));

          onStatusUpdate?.call('Siaran aktif, menunggu Developer...');
        } catch (e) {
          debugPrint("Error generating offer: $e");
        }
      }

      // Initial offer
      await createAndSendOffer();

      // Listen for Answer or Reconnect Request from Developer
      String? lastAnswerSdp;
      dynamic lastRequestOfferAt;

      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data == null || !_isBroadcasting) return;

        // 1. Developer requests a fresh offer (e.g. Developer refreshed / opened Tab)
        final reqOfferAt = data['requestOfferAt'];
        if (reqOfferAt != null && reqOfferAt != lastRequestOfferAt) {
          lastRequestOfferAt = reqOfferAt;
          await createAndSendOffer();
          return;
        }

        // 2. Developer submitted an Answer
        if (data['answer'] != null && _peerConnection != null) {
          final answer = data['answer'] as Map<String, dynamic>;
          final sdp = answer['sdp'] as String?;
          if (sdp != null && sdp != lastAnswerSdp) {
            lastAnswerSdp = sdp;
            try {
              if (_peerConnection!.signalingState == 'have-local-offer') {
                await _peerConnection!.setRemoteDescription({
                  'sdp': sdp,
                  'type': answer['type'] ?? 'answer',
                });
                onStatusUpdate?.call('Terhubung ke Developer!');
              }
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
  // DEVELOPER / VIEWER: CONNECT (ON-DEMAND FRESH HANDSHAKE)
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
        throw Exception("Sesi siaran belum dimulai oleh Kacab.");
      }

      final data = sessionSnap.data()!;
      if (data['status'] != 'active') {
        throw Exception("Sesi siaran sedang tidak aktif.");
      }

      _viewerSubscription?.cancel();
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

      // Internal function to process an offer from Firestore
      Future<void> processOffer(Map<String, dynamic> offer) async {
        if (!_isViewing || _peerConnection == null) return;
        try {
          // 1. Set Remote Offer
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

          // 3. Wait 800ms for ICE candidates bundling
          await Future.delayed(const Duration(milliseconds: 800));

          // 4. Save Answer document to Firestore
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
          debugPrint("Error processing offer on viewer: $e");
        }
      }

      // Check if offer exists or if we should request fresh offer
      if (data['offer'] != null && data['answer'] == null) {
        await processOffer(data['offer'] as Map<String, dynamic>);
      } else {
        // Request fresh offer from Kacab
        onStatusUpdate?.call('Meminta sinyal siaran baru dari Kacab...');
        await sessionRef.update({
          'requestOfferAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      }

      // Listen for fresh offer from Kacab
      String? lastProcessedOfferSdp;
      _viewerSubscription = sessionRef.snapshots().listen((snapshot) async {
        final d = snapshot.data();
        if (d == null || !_isViewing || _peerConnection == null) return;

        if (d['offer'] != null) {
          final offer = d['offer'] as Map<String, dynamic>;
          final sdp = offer['sdp'] as String?;
          if (sdp != null && sdp != lastProcessedOfferSdp && _peerConnection!.signalingState != 'stable') {
            lastProcessedOfferSdp = sdp;
            await processOffer(offer);
          }
        }
      });
    } catch (e) {
      debugPrint("Error connecting as viewer: $e");
      _isViewing = false;
      onStatusUpdate?.call('Gagal: $e');
    }
  }

  void disconnectViewer() {
    _isViewing = false;
    _viewerSubscription?.cancel();
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession({String sessionId = 'kacab_live'}) {
    return _db.collection('webrtc_screen_sessions').doc(sessionId).snapshots();
  }
}
