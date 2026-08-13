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

      // 2. Create RTC Peer Connection
      _peerConnection?.close();
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      // Add local stream tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);

      // Listen for local ICE candidates and append to document array
      _peerConnection!.onIceCandidate.listen((event) {
        if (event.candidate != null && event.candidate!.candidate != null) {
          sessionRef.update({
            'broadcasterCandidates': FieldValue.arrayUnion([
              {
                'candidate': event.candidate!.candidate,
                'sdpMid': event.candidate!.sdpMid,
                'sdpMLineIndex': event.candidate!.sdpMLineIndex,
              }
            ])
          }).catchError((_) {});
        }
      });

      _peerConnection!.onIceConnectionStateChange.listen((_) {
        debugPrint("Broadcaster ICE State: ${_peerConnection?.iceConnectionState}");
        onStatusUpdate?.call('Koneksi: ${_peerConnection?.iceConnectionState}');
      });

      // 3. Create SDP Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      // 4. Save Initial Session Document to Firestore
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
        'broadcasterCandidates': [],
        'viewerCandidates': [],
        'startedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      onStatusUpdate?.call('Siaran aktif, menunggu Developer...');

      // 5. Listen for SDP Answer and Viewer ICE Candidates
      bool hasSetRemote = false;
      final processedViewerCandidates = <String>{};

      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) async {
        final data = snapshot.data();
        if (data == null || _peerConnection == null) return;

        // A. Set SDP Answer from Developer
        if (data['answer'] != null && !hasSetRemote) {
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

        // B. Process Viewer ICE Candidates
        if (data['viewerCandidates'] != null) {
          final candidates = List<dynamic>.from(data['viewerCandidates']);
          for (var cand in candidates) {
            if (cand is Map<String, dynamic>) {
              final candStr = cand['candidate']?.toString() ?? '';
              if (candStr.isNotEmpty && !processedViewerCandidates.contains(candStr)) {
                processedViewerCandidates.add(candStr);
                final rtcCand = html.RtcIceCandidate({
                  'candidate': cand['candidate'],
                  'sdpMid': cand['sdpMid'],
                  'sdpMLineIndex': cand['sdpMLineIndex'],
                });
                _peerConnection!.addIceCandidate(rtcCand).catchError((e) {
                  debugPrint("Broadcaster addIceCandidate error: $e");
                });
              }
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
        debugPrint("Viewer onTrack event received streams: ${event.streams}");
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
          sessionRef.update({
            'viewerCandidates': FieldValue.arrayUnion([
              {
                'candidate': event.candidate!.candidate,
                'sdpMid': event.candidate!.sdpMid,
                'sdpMLineIndex': event.candidate!.sdpMLineIndex,
              }
            ])
          }).catchError((_) {});
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

      // 4. Listen for Broadcaster ICE Candidates in real-time
      final processedBroadcasterCandidates = <String>{};
      _sessionSubscription?.cancel();
      _sessionSubscription = sessionRef.snapshots().listen((snapshot) {
        final docData = snapshot.data();
        if (docData == null || _peerConnection == null) return;

        if (docData['broadcasterCandidates'] != null) {
          final candidates = List<dynamic>.from(docData['broadcasterCandidates']);
          for (var cand in candidates) {
            if (cand is Map<String, dynamic>) {
              final candStr = cand['candidate']?.toString() ?? '';
              if (candStr.isNotEmpty && !processedBroadcasterCandidates.contains(candStr)) {
                processedBroadcasterCandidates.add(candStr);
                final rtcCand = html.RtcIceCandidate({
                  'candidate': cand['candidate'],
                  'sdpMid': cand['sdpMid'],
                  'sdpMLineIndex': cand['sdpMLineIndex'],
                });
                _peerConnection!.addIceCandidate(rtcCand).catchError((e) {
                  debugPrint("Viewer addIceCandidate error: $e");
                });
              }
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
