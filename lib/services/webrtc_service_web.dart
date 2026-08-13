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
  StreamSubscription? _candidatesSubscription;
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
  // KACAB: START SCREEN BROADCAST (STANDARD TRICKLE ICE)
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
      onStatusUpdate?.call('Layar aktif, menyiapkan saluran siaran...');

      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.onEnded.listen((_) {
        stopBroadcasting(sessionId: sessionId);
        if (onStoppedByUser != null) onStoppedByUser();
      });

      // Close previous connection
      _peerConnection?.close();
      _peerConnection = html.RtcPeerConnection(_rtcConfig);

      final sessionRef = _db.collection('webrtc_screen_sessions').doc(sessionId);

      // Clean previous subcollection candidates
      try {
        final bSnap = await sessionRef.collection('broadcasterCandidates').get();
        for (var d in bSnap.docs) {
          d.reference.delete();
        }
        final vSnap = await sessionRef.collection('viewerCandidates').get();
        for (var d in vSnap.docs) {
          d.reference.delete();
        }
      } catch (_) {}

      // Add track to peer connection
      _peerConnection!.addTrack(videoTrack, _localStream!);

      // Listen for ICE Candidates and save to subcollection
      _peerConnection!.onIceCandidate.listen((event) {
        if (event.candidate != null && event.candidate!.candidate != null) {
          sessionRef.collection('broadcasterCandidates').add({
            'candidate': event.candidate!.candidate,
            'sdpMid': event.candidate!.sdpMid,
            'sdpMLineIndex': event.candidate!.sdpMLineIndex,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      // Create Offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      // Save Offer document
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

      // Listen for Answer from Developer
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

      // Listen for Viewer ICE Candidates
      _candidatesSubscription?.cancel();
      _candidatesSubscription = sessionRef.collection('viewerCandidates').snapshots().listen((snap) {
        for (var change in snap.docChanges) {
          if (change.type == DocumentChangeType.added && _peerConnection != null) {
            final cData = change.doc.data();
            if (cData != null && cData['candidate'] != null) {
              try {
                _peerConnection!.addIceCandidate(html.RtcIceCandidate({
                  'candidate': cData['candidate'],
                  'sdpMid': cData['sdpMid'],
                  'sdpMLineIndex': cData['sdpMLineIndex'],
                }));
              } catch (_) {}
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
    _candidatesSubscription?.cancel();

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
  // DEVELOPER: CONNECT (STANDARD TRICKLE ICE)
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
        debugPrint("Viewer onTrack event: ${event.streams}");
        if (event.streams != null && event.streams!.isNotEmpty) {
          onRemoteStreamReceived(event.streams!.first);
          onStatusUpdate?.call('Siaran Langsung Terhubung (60 FPS)');
        }
      });

      // Listen for Viewer candidates and send to Firestore
      _peerConnection!.onIceCandidate.listen((event) {
        if (event.candidate != null && event.candidate!.candidate != null) {
          sessionRef.collection('viewerCandidates').add({
            'candidate': event.candidate!.candidate,
            'sdpMid': event.candidate!.sdpMid,
            'sdpMLineIndex': event.candidate!.sdpMLineIndex,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      _peerConnection!.onIceConnectionStateChange.listen((_) {
        final state = _peerConnection?.iceConnectionState ?? '';
        debugPrint("Viewer ICE State: $state");
        if (state == 'connected' || state == 'completed') {
          onStatusUpdate?.call('Terhubung Lancar (60 FPS)');
        }
      });

      // 1. Set Remote Description (Offer)
      final offer = data['offer'] as Map<String, dynamic>;
      await _peerConnection!.setRemoteDescription({
        'sdp': offer['sdp'],
        'type': offer['type'],
      });

      // 2. Create Answer
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

      // 4. Listen for Broadcaster ICE candidates
      _candidatesSubscription?.cancel();
      _candidatesSubscription = sessionRef.collection('broadcasterCandidates').snapshots().listen((snap) {
        for (var change in snap.docChanges) {
          if (change.type == DocumentChangeType.added && _peerConnection != null) {
            final cData = change.doc.data();
            if (cData != null && cData['candidate'] != null) {
              try {
                _peerConnection!.addIceCandidate(html.RtcIceCandidate({
                  'candidate': cData['candidate'],
                  'sdpMid': cData['sdpMid'],
                  'sdpMLineIndex': cData['sdpMLineIndex'],
                }));
              } catch (_) {}
            }
          }
        }
      });

      onStatusUpdate?.call('Sinyal terkirim, menyambungkan video...');
    } catch (e) {
      debugPrint("Error connecting as viewer: $e");
      _isViewing = false;
      onStatusUpdate?.call('Gagal: $e');
    }
  }

  void disconnectViewer() {
    _isViewing = false;
    _sessionSubscription?.cancel();
    _candidatesSubscription?.cancel();
    if (_peerConnection != null) {
      _peerConnection!.close();
      _peerConnection = null;
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession({String sessionId = 'kacab_live'}) {
    return _db.collection('webrtc_screen_sessions').doc(sessionId).snapshots();
  }
}
