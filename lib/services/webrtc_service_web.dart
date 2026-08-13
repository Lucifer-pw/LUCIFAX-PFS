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
      {'urls': 'stun:stun.services.mozilla.com'},
    ],
  };

  /// Helper to reliably wait until all ICE candidates are bundled into SDP
  Future<void> _waitForIceGathering(html.RtcPeerConnection pc) async {
    if (pc.iceGatheringState == 'complete') return;

    final completer = Completer<void>();
    StreamSubscription? sub;

    sub = pc.onIceCandidate.listen((event) {
      if (event.candidate == null) {
        sub?.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    // Fallback safety timeout 1200ms
    Future.delayed(const Duration(milliseconds: 1200), () {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
  }

  // ══════════════════════════════════════════════════════════
  // KACAB / PRESENTER: START SCREEN SHARE (BULLETPROOF P2P)
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
      onStatusUpdate?.call('Layar aktif, menyiapkan sinyal P2P...');

      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.onEnded.listen((_) {
        stopBroadcasting(sessionId: sessionId);
        if (onStoppedByUser != null) onStoppedByUser();
      });

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);

      // Method to create a fresh offer with complete ICE candidates
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

          // Wait until STUN candidates are gathered
          await _waitForIceGathering(_peerConnection!);

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

      // 1. Initial Offer
      await createAndSendOffer();

      // 2. Listen for Answer or Fresh Offer Requests
      String? lastAnswerSdp;
      dynamic lastRequestOfferAt;

      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data == null || !_isBroadcasting) return;

        // Developer requested fresh connection handshake
        final reqOfferAt = data['requestOfferAt'];
        if (reqOfferAt != null && reqOfferAt != lastRequestOfferAt) {
          lastRequestOfferAt = reqOfferAt;
          await createAndSendOffer();
          return;
        }

        // Developer submitted Answer
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
  // DEVELOPER / VIEWER: CONNECT (AUTO ICE GATHERING + DIRECT)
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

      // Listen for incoming remote tracks
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

      // Internal handler to process Offer and return Answer
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

          // 3. Wait for all ICE candidates in Answer
          await _waitForIceGathering(_peerConnection!);

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

      // Check if current offer is fresh
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
