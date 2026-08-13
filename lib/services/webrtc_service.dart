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
  StreamSubscription? _candidateSubscription;
  bool _isBroadcasting = false;
  bool _isViewing = false;

  bool get isBroadcasting => _isBroadcasting;
  bool get isViewing => _isViewing;

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'iceCandidatePoolSize': 10,
  };

  // ══════════════════════════════════════════════════════════
  // KACAB / PRESENTER: START SCREEN SHARE BROADCAST
  // ══════════════════════════════════════════════════════════

  Future<bool> startBroadcasting({
    required String userId,
    required String userName,
    String sessionId = 'kacab_live',
    VoidCallback? onStoppedByUser,
    Function(String)? onStatusUpdate,
  }) async {
    if (!kIsWeb) {
      debugPrint("WebRTC screen share only supported on Web.");
      return false;
    }

    try {
      onStatusUpdate?.call('Meminta izin layar...');

      // 1. Get Screen Media Stream from browser via JS Interop
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception("Browser tidak mendukung MediaDevices API.");
      }

      final displayMediaOptions = {
        'video': {
          'cursor': 'always',
          'frameRate': {'ideal': 30, 'max': 60},
        },
        'audio': false,
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
      onStatusUpdate?.call('Layar aktif, menyiapkan koneksi...');

      // Handle when user stops sharing via browser floating stop bar
      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.onEnded.listen((_) {
        stopBroadcasting(sessionId: sessionId);
        if (onStoppedByUser != null) onStoppedByUser();
      });

      // 2. Clean old candidate subcollections
      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);
      final oldBroadcasterCands = await sessionRef.collection('broadcaster_candidates').get();
      for (var doc in oldBroadcasterCands.docs) {
        await doc.reference.delete();
      }
      final oldViewerCands = await sessionRef.collection('viewer_candidates').get();
      for (var doc in oldViewerCands.docs) {
        await doc.reference.delete();
      }

      // 3. Create RTC Peer Connection
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      // Add local stream tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Listen for local ICE candidates and save to Firestore
      _peerConnection!.onIceCandidate.listen((event) {
        if (event.candidate != null && event.candidate!.candidate != null) {
          sessionRef.collection('broadcaster_candidates').add({
            'candidate': event.candidate!.candidate,
            'sdpMid': event.candidate!.sdpMid,
            'sdpMLineIndex': event.candidate!.sdpMLineIndex,
            'createdAt': Timestamp.now(),
          });
        }
      });

      _peerConnection!.onIceConnectionStateChange.listen((_) {
        debugPrint("Broadcaster ICE State: ${_peerConnection?.iceConnectionState}");
        onStatusUpdate?.call('Koneksi: ${_peerConnection?.iceConnectionState}');
      });

      // 4. Create SDP Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      // 5. Save Session to Firestore
      await sessionRef.set({
        'sessionId': sessionId,
        'broadcasterId': userId,
        'broadcasterName': userName,
        'status': 'active',
        'offer': {
          'sdp': offer.sdp,
          'type': offer.type,
        },
        'answer': null,
        'startedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      onStatusUpdate?.call('Siaran aktif, menunggu Developer...');

      // 6. Listen for SDP Answer from Developer
      bool hasSetRemote = false;
      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data != null && data['answer'] != null && _peerConnection != null && !hasSetRemote) {
          final answer = data['answer'] as Map<String, dynamic>;
          if (answer['sdp'] != null) {
            hasSetRemote = true;
            await _peerConnection!.setRemoteDescription({
              'sdp': answer['sdp'],
              'type': answer['type'],
            });
            onStatusUpdate?.call('Terhubung ke Developer!');
          }
        }
      });

      // 7. Listen for Viewer ICE Candidates
      _candidateSubscription?.cancel();
      _candidateSubscription = sessionRef
          .collection('viewer_candidates')
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data != null && data['candidate'] != null && _peerConnection != null) {
              final candidate = html.RtcIceCandidate({
                'candidate': data['candidate'],
                'sdpMid': data['sdpMid'],
                'sdpMLineIndex': data['sdpMLineIndex'],
              });
              _peerConnection!.addIceCandidate(candidate).catchError((e) {
                debugPrint("Broadcaster addIceCandidate error: $e");
              });
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
    _candidateSubscription?.cancel();

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
  // DEVELOPER / VIEWER: CONNECT & RECEIVE LIVE STREAM
  // ══════════════════════════════════════════════════════════

  Future<void> connectToBroadcast({
    String sessionId = 'kacab_live',
    required Function(html.MediaStream) onRemoteStreamReceived,
    Function(String)? onStatusUpdate,
  }) async {
    if (!kIsWeb) return;

    try {
      _isViewing = true;
      onStatusUpdate?.call('Mengambil data siaran...');

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);
      final sessionSnap = await sessionRef.get();

      if (!sessionSnap.exists) {
        throw Exception("Sesi siaran tidak ditemukan.");
      }

      final data = sessionSnap.data()!;
      if (data['status'] != 'active' || data['offer'] == null) {
        throw Exception("Sesi siaran sedang tidak aktif.");
      }

      _peerConnection?.close();
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      // Listen for remote tracks
      _peerConnection!.onTrack.listen((event) {
        debugPrint("Viewer onTrack event received with streams: ${event.streams}");
        if (event.streams != null && event.streams!.isNotEmpty) {
          onRemoteStreamReceived(event.streams!.first);
          onStatusUpdate?.call('Siaran Langsung Terhubung (60 FPS)');
        }
      });

      _peerConnection!.onIceConnectionStateChange.listen((_) {
        final state = _peerConnection?.iceConnectionState ?? '';
        debugPrint("Viewer ICE State: $state");
        if (state == 'connected' || state == 'completed') {
          onStatusUpdate?.call('Terhubung Lancar');
        } else if (state == 'checking') {
          onStatusUpdate?.call('Menyambungkan (Checking)...');
        } else if (state == 'failed' || state == 'disconnected') {
          onStatusUpdate?.call('Koneksi Terputus ($state)');
        }
      });

      // Send local ICE candidates (Viewer) to Firestore
      _peerConnection!.onIceCandidate.listen((event) {
        if (event.candidate != null && event.candidate!.candidate != null) {
          sessionRef.collection('viewer_candidates').add({
            'candidate': event.candidate!.candidate,
            'sdpMid': event.candidate!.sdpMid,
            'sdpMLineIndex': event.candidate!.sdpMLineIndex,
            'createdAt': Timestamp.now(),
          });
        }
      });

      // 1. Set Remote Offer Description
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

      // 3. Save Answer to Firestore
      await sessionRef.update({
        'answer': {
          'sdp': answer.sdp,
          'type': answer.type,
        },
        'connectedAt': Timestamp.now(),
      });

      // 4. Listen for Broadcaster ICE Candidates
      _candidateSubscription?.cancel();
      _candidateSubscription = sessionRef
          .collection('broadcaster_candidates')
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final candData = change.doc.data();
            if (candData != null && candData['candidate'] != null && _peerConnection != null) {
              final candidate = html.RtcIceCandidate({
                'candidate': candData['candidate'],
                'sdpMid': candData['sdpMid'],
                'sdpMLineIndex': candData['sdpMLineIndex'],
              });
              _peerConnection!.addIceCandidate(candidate).catchError((e) {
                debugPrint("Viewer addIceCandidate error: $e");
              });
            }
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
    _candidateSubscription?.cancel();
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession({String sessionId = 'kacab_live'}) {
    return _db.collection('webrtc_screen_sessions').doc(sessionId).snapshots();
  }
}
