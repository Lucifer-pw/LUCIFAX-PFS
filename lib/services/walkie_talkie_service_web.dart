import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

class WalkieTalkieService extends ChangeNotifier {
  static final WalkieTalkieService _instance = WalkieTalkieService._internal();
  factory WalkieTalkieService() => _instance;
  WalkieTalkieService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Identity
  String _myUserId = '';
  String _myUserName = '';
  String _myRole = '';
  String _mySessionId = '';

  // State
  bool _isInitialized = false;
  bool _isTransmitting = false;
  bool _hasMicPermission = false;
  bool _isSpeakerMuted = false;
  double _speakerVolume = 1.0;
  String _statusMessage = 'Menyiapkan Walkie-Talkie...';

  // Target selection (null = Broadcast to everyone)
  String? _currentTargetId;
  String _currentTargetName = 'Semua Staff (Broadcast)';

  // Channel incoming state
  String? _currentSpeakerId;
  String? _currentSpeakerName;
  String? _incomingTargetId;

  // WebRTC
  html.MediaStream? _localStream;
  final Map<String, html.RtcPeerConnection> _peerConnections = {};
  final Map<String, StreamSubscription> _peerSubscriptions = {};
  final Map<String, html.AudioElement> _remoteAudioElements = {};
  final Set<String> _connectedPeerIds = {};

  StreamSubscription? _channelSubscription;
  StreamSubscription? _usersSubscription;
  StreamSubscription? _incomingSignalsSubscription;
  Timer? _healthCheckTimer;

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  // ══════════════════════════════════════════════════════════
  // GETTERS
  // ══════════════════════════════════════════════════════════

  bool get isInitialized => _isInitialized;
  bool get isTransmitting => _isTransmitting;
  bool get hasMicPermission => _hasMicPermission;
  bool get isSpeakerMuted => _isSpeakerMuted;
  double get speakerVolume => _speakerVolume;
  String? get currentSpeakerId => _currentSpeakerId;
  String? get currentSpeakerName => _currentSpeakerName;
  String? get currentTargetId => _currentTargetId;
  String get currentTargetName => _currentTargetName;
  String get statusMessage => _statusMessage;
  int get connectedPeerCount => _connectedPeerIds.length;
  Set<String> get connectedPeerIds => Set.unmodifiable(_connectedPeerIds);

  bool isPeerConnected(String uid) => _connectedPeerIds.contains(uid);

  // Is someone else currently speaking?
  bool get isChannelBusy =>
      _currentSpeakerId != null && _currentSpeakerId != _myUserId;

  // Is this device currently receiving and playing someone's voice?
  bool get isReceiving {
    if (_currentSpeakerId == null || _currentSpeakerId == _myUserId) {
      return false;
    }
    return _incomingTargetId == null || _incomingTargetId == _myUserId;
  }

  // ══════════════════════════════════════════════════════════
  // INITIALIZE & PERMISSIONS
  // ══════════════════════════════════════════════════════════

  Future<bool> initialize({
    required String userId,
    required String userName,
    required String role,
  }) async {
    if (!kIsWeb) return false;
    if (_isInitialized && _myUserId == userId) return true;

    _myUserId = userId;
    _myUserName = userName;
    _myRole = role;
    _mySessionId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      _statusMessage = 'Meminta izin mikrofon...';
      notifyListeners();

      // Request microphone access
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception("Browser tidak mendukung MediaDevices.");
      }

      final audioConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      final jsPromise = js_util.callMethod(
        mediaDevices,
        'getUserMedia',
        [js_util.jsify(audioConstraints)],
      );

      _localStream = await js_util.promiseToFuture<html.MediaStream>(jsPromise);

      // IMMEDIATELY MUTE LOCAL MIC TRACK (STANDBY MODE)
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = false;
      }

      _hasMicPermission = true;
      _isInitialized = true;
      _statusMessage = 'Siap (Standby)';
      notifyListeners();

      // Intercept Alt key on browser window to prevent Windows system menu activation
      html.window.onKeyDown.listen((e) {
        if (e.key == 'Alt') {
          e.preventDefault();
        }
      });

      // Listen to channel status (who is speaking)
      _listenToChannel();

      // Listen to online users and connect peer connections
      _listenToOnlineUsers();

      // Listen to incoming WebRTC signal offers from other peers
      _listenToIncomingSignals();

      // Auto-healing health check timer: checks active peer connections every 6 seconds
      _healthCheckTimer?.cancel();
      _healthCheckTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        _runConnectionHealthCheck();
      });

      return true;
    } catch (e) {
      debugPrint("WalkieTalkie initialization error: $e");
      _hasMicPermission = false;
      _isInitialized = false;
      _statusMessage = 'Izin mikrofon diperlukan untuk Radio.';
      notifyListeners();
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════
  // PUSH-TO-TALK & TOGGLE CONTROLS
  // ══════════════════════════════════════════════════════════

  Future<void> toggleTransmitting() async {
    if (_isTransmitting) {
      await stopTransmitting();
    } else {
      await startTransmitting();
    }
  }

  Future<void> startTransmitting() async {
    if (!_isInitialized || _localStream == null) {
      if (_myUserId.isNotEmpty) {
        await initialize(userId: _myUserId, userName: _myUserName, role: _myRole);
      }
      return;
    }

    if (_isTransmitting) return;

    // Half-Duplex collision prevention: if someone else is speaking, do not allow transmitting!
    if (isChannelBusy) {
      debugPrint("Channel is busy: $_currentSpeakerName sedang berbicara.");
      return;
    }

    try {
      _isTransmitting = true;

      // UNMUTE LOCAL MIC AUDIO TRACKS
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = true;
      }

      _statusMessage = 'Bicara...';
      notifyListeners();

      // Broadcast to Firestore who is currently speaking
      await _db.collection('walkie_talkie_channels').doc('main').set({
        'currentSpeakerId': _myUserId,
        'currentSpeakerName': _myUserName,
        'targetId': _currentTargetId,
        'targetName': _currentTargetName,
        'status': 'transmitting',
        'startedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error startTransmitting: $e");
      _isTransmitting = false;
      if (_localStream != null) {
        for (final track in _localStream!.getAudioTracks()) {
          track.enabled = false;
        }
      }
      notifyListeners();
    }
  }

  Future<void> stopTransmitting() async {
    if (!_isTransmitting) return;

    try {
      _isTransmitting = false;

      // MUTE LOCAL MIC AUDIO TRACKS
      if (_localStream != null) {
        for (final track in _localStream!.getAudioTracks()) {
          track.enabled = false;
        }
      }

      _statusMessage = 'Siap (Standby)';
      notifyListeners();

      // Release channel in Firestore
      await _db.collection('walkie_talkie_channels').doc('main').set({
        'currentSpeakerId': null,
        'currentSpeakerName': null,
        'targetId': null,
        'status': 'idle',
        'endedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error stopTransmitting: $e");
    }
  }

  // ══════════════════════════════════════════════════════════
  // TARGET & AUDIO SETTINGS
  // ══════════════════════════════════════════════════════════

  void setTarget({String? targetId, String? targetName}) {
    _currentTargetId = targetId;
    _currentTargetName = targetName ?? 'Semua Staff (Broadcast)';
    notifyListeners();
  }

  void toggleSpeakerMute() {
    _isSpeakerMuted = !_isSpeakerMuted;
    _syncAllAudioElements();
    notifyListeners();
  }

  void setVolume(double volume) {
    _speakerVolume = volume.clamp(0.0, 1.0);
    _syncAllAudioElements();
    notifyListeners();
  }

  void _syncAllAudioElements() {
    final effectiveVolume = _isSpeakerMuted ? 0.0 : _speakerVolume;
    for (final audioEl in _remoteAudioElements.values) {
      audioEl.volume = effectiveVolume;
      audioEl.muted = _isSpeakerMuted;
    }
  }

  Future<void> unlockAudio() async {
    for (final audioEl in _remoteAudioElements.values) {
      try {
        await audioEl.play();
      } catch (_) {}
    }
  }

  // ══════════════════════════════════════════════════════════
  // FIRESTORE CHANNEL LISTENER (WHO IS TALKING)
  // ══════════════════════════════════════════════════════════

  void _listenToChannel() {
    _channelSubscription?.cancel();
    _channelSubscription = _db
        .collection('walkie_talkie_channels')
        .doc('main')
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String?;
      final speakerId = data['currentSpeakerId'] as String?;
      final speakerName = data['currentSpeakerName'] as String?;
      final targetId = data['targetId'] as String?;

      if (status == 'transmitting' && speakerId != null) {
        _currentSpeakerId = speakerId;
        _currentSpeakerName = speakerName ?? 'Seseorang';
        _incomingTargetId = targetId;

        // Is this transmission meant for me?
        final isForMe = (_currentSpeakerId != _myUserId) &&
            (_incomingTargetId == null || _incomingTargetId == _myUserId);

        for (final entry in _remoteAudioElements.entries) {
          final peerUid = entry.key;
          final audioEl = entry.value;

          if (isForMe && peerUid == _currentSpeakerId) {
            audioEl.volume = _isSpeakerMuted ? 0.0 : _speakerVolume;
            audioEl.muted = _isSpeakerMuted;
            audioEl.play().catchError((e) => debugPrint("Audio play error: $e"));
          } else {
            audioEl.volume = 0.0;
            audioEl.muted = true;
          }
        }
      } else {
        // Idle
        _currentSpeakerId = null;
        _currentSpeakerName = null;
        _incomingTargetId = null;

        for (final audioEl in _remoteAudioElements.values) {
          audioEl.volume = 0.0;
          audioEl.muted = true;
        }
      }

      notifyListeners();
    });
  }

  // ══════════════════════════════════════════════════════════
  // WEBRTC SIGNALING (ROBUST VANILLA ICE ARCHITECTURE)
  // ══════════════════════════════════════════════════════════

  String _getPairId(String uidA, String uidB) {
    return uidA.compareTo(uidB) < 0 ? '${uidA}_$uidB' : '${uidB}_$uidA';
  }

  bool _isInitiator(String myUid, String peerUid) {
    return myUid.compareTo(peerUid) < 0;
  }

  Future<void> _waitForIceGathering(html.RtcPeerConnection pc, {int timeoutMs = 2500}) async {
    if (pc.iceGatheringState == 'complete') return;
    final completer = Completer<void>();
    StreamSubscription? candidateSub;
    Timer? timer;

    timer = Timer(Duration(milliseconds: timeoutMs), () {
      candidateSub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    candidateSub = pc.onIceCandidate.listen((event) {
      if (event.candidate == null || pc.iceGatheringState == 'complete') {
        timer?.cancel();
        candidateSub?.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    await completer.future;
  }

  void _listenToOnlineUsers() {
    _usersSubscription?.cancel();
    _usersSubscription = _db.collection('users').snapshots().listen((snapshot) {
      for (final doc in snapshot.docs) {
        final uid = doc.id;
        if (uid == _myUserId) continue;

        final data = doc.data();
        final isOnline = data['isOnline'] == true;
        final lastSeen = data['lastSeen'];

        bool isActuallyOnline = isOnline;
        if (lastSeen is Timestamp) {
          final diff = DateTime.now().difference(lastSeen.toDate());
          isActuallyOnline = isOnline && diff.inSeconds <= 90;
        }

        if (isActuallyOnline && !_connectedPeerIds.contains(uid)) {
          if (_isInitiator(_myUserId, uid)) {
            _initiatePeerConnection(uid);
          }
        } else if (!isActuallyOnline && _connectedPeerIds.contains(uid)) {
          _cleanupPeerConnection(uid);
        }
      }
    });
  }

  void _runConnectionHealthCheck() {
    if (!_isInitialized || _localStream == null) return;

    _db.collection('users').get().then((snapshot) {
      for (final doc in snapshot.docs) {
        final uid = doc.id;
        if (uid == _myUserId) continue;

        final data = doc.data();
        final isOnline = data['isOnline'] == true;
        final lastSeen = data['lastSeen'];

        bool isActuallyOnline = isOnline;
        if (lastSeen is Timestamp) {
          final diff = DateTime.now().difference(lastSeen.toDate());
          isActuallyOnline = isOnline && diff.inSeconds <= 90;
        }

        if (isActuallyOnline) {
          final pc = _peerConnections[uid];
          final state = pc?.iceConnectionState;
          final isStale = pc == null ||
              state == 'failed' ||
              state == 'disconnected' ||
              state == 'closed';

          if (isStale) {
            debugPrint("WalkieTalkie HealthCheck: Reconnecting with peer $uid (state: $state)");
            _cleanupPeerConnection(uid);
            if (_isInitiator(_myUserId, uid)) {
              _initiatePeerConnection(uid);
            }
          }
        }
      }
    }).catchError((_) {});
  }

  void _listenToIncomingSignals() {
    _incomingSignalsSubscription?.cancel();
    _incomingSignalsSubscription = _db
        .collection('walkie_talkie_signals')
        .where('receiverId', isEqualTo: _myUserId)
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final initiatorId = data['initiatorId'] as String?;
        final status = data['status'] as String?;
        final offer = data['offer'];

        if (initiatorId != null && status == 'offering' && offer != null) {
          _answerPeerConnection(initiatorId, doc.id, offer);
        }
      }
    });
  }

  Future<void> _initiatePeerConnection(String peerUid) async {
    if (_peerConnections.containsKey(peerUid)) {
      final state = _peerConnections[peerUid]?.iceConnectionState;
      if (state == 'connected' || state == 'completed') return;
      _cleanupPeerConnection(peerUid);
    }
    if (_localStream == null) return;

    try {
      final pairId = _getPairId(_myUserId, peerUid);
      debugPrint("WalkieTalkie: Initiating connection to $peerUid ($pairId)");

      final pc = html.RtcPeerConnection(_rtcConfig);
      _peerConnections[peerUid] = pc;

      // Add local audio track
      for (final track in _localStream!.getAudioTracks()) {
        pc.addTrack(track, _localStream!);
      }

      // Handle incoming remote audio track
      pc.onTrack.listen((event) {
        _handleRemoteTrack(peerUid, event);
      });

      pc.onIceConnectionStateChange.listen((_) {
        final state = pc.iceConnectionState;
        debugPrint("WalkieTalkie ICE State (Initiator) with $peerUid: $state");
        if (state == 'connected' || state == 'completed') {
          _connectedPeerIds.add(peerUid);
          notifyListeners();
        } else if (state == 'disconnected' || state == 'failed' || state == 'closed') {
          _connectedPeerIds.remove(peerUid);
          notifyListeners();
        }
      });

      // Create Offer
      final offer = await pc.createOffer({'offerToReceiveAudio': true});
      await pc.setLocalDescription({
        'sdp': offer.sdp,
        'type': offer.type,
      });

      // Wait until ICE candidates (including STUN public srflx) are bundled
      await _waitForIceGathering(pc);

      final localDesc = pc.localDescription;
      final signalRef = _db.collection('walkie_talkie_signals').doc(pairId);

      await signalRef.set({
        'pairId': pairId,
        'initiatorId': _myUserId,
        'receiverId': peerUid,
        'status': 'offering',
        'session': _mySessionId,
        'offer': {
          'sdp': localDesc?.sdp ?? offer.sdp,
          'type': localDesc?.type ?? offer.type,
        },
        'answer': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Listen for Answer
      String? lastAnswerSdp;
      _peerSubscriptions[pairId]?.cancel();
      _peerSubscriptions[pairId] = signalRef.snapshots().listen((snap) async {
        final data = snap.data();
        if (data != null && data['answer'] != null && _peerConnections[peerUid] != null) {
          final answer = data['answer'] as Map<String, dynamic>;
          final sdp = answer['sdp'] as String?;
          if (sdp != null && sdp != lastAnswerSdp) {
            lastAnswerSdp = sdp;
            try {
              await pc.setRemoteDescription({
                'sdp': sdp,
                'type': answer['type'] ?? 'answer',
              });
              _connectedPeerIds.add(peerUid);
              notifyListeners();
            } catch (e) {
              debugPrint("Error setting remote answer on initiator: $e");
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Error in _initiatePeerConnection with $peerUid: $e");
    }
  }

  Future<void> _answerPeerConnection(
    String initiatorId,
    String pairId,
    dynamic rawOffer,
  ) async {
    // If connection exists but received a new offer, reset to accept fresh connection
    if (_peerConnections.containsKey(initiatorId)) {
      _peerConnections[initiatorId]?.close();
      _peerConnections.remove(initiatorId);
    }

    if (_localStream == null) return;

    try {
      debugPrint("WalkieTalkie: Answering connection from $initiatorId ($pairId)");

      final pc = html.RtcPeerConnection(_rtcConfig);
      _peerConnections[initiatorId] = pc;

      // Add local audio track
      for (final track in _localStream!.getAudioTracks()) {
        pc.addTrack(track, _localStream!);
      }

      // Handle incoming remote audio track
      pc.onTrack.listen((event) {
        _handleRemoteTrack(initiatorId, event);
      });

      pc.onIceConnectionStateChange.listen((_) {
        final state = pc.iceConnectionState;
        debugPrint("WalkieTalkie ICE State (Answerer) with $initiatorId: $state");
        if (state == 'connected' || state == 'completed') {
          _connectedPeerIds.add(initiatorId);
          notifyListeners();
        } else if (state == 'disconnected' || state == 'failed' || state == 'closed') {
          _connectedPeerIds.remove(initiatorId);
          notifyListeners();
        }
      });

      // 1. Set Remote Description (Offer from initiator)
      final offerMap = rawOffer as Map<String, dynamic>;
      await pc.setRemoteDescription({
        'sdp': offerMap['sdp'],
        'type': offerMap['type'],
      });

      // 2. Create SDP Answer
      final answer = await pc.createAnswer();
      await pc.setLocalDescription({
        'sdp': answer.sdp,
        'type': answer.type,
      });

      // 3. Wait for ICE gathering
      await _waitForIceGathering(pc);

      // 4. Update Answer to Firestore
      final localDesc = pc.localDescription;
      final signalRef = _db.collection('walkie_talkie_signals').doc(pairId);

      await signalRef.update({
        'answer': {
          'sdp': localDesc?.sdp ?? answer.sdp,
          'type': localDesc?.type ?? answer.type,
        },
        'status': 'connected',
        'connectedAt': FieldValue.serverTimestamp(),
      });

      _connectedPeerIds.add(initiatorId);
      notifyListeners();
    } catch (e) {
      debugPrint("Error in _answerPeerConnection with $initiatorId: $e");
    }
  }

  void _handleRemoteTrack(String peerUid, html.RtcTrackEvent event) {
    html.MediaStream? remoteStream;
    if (event.streams != null && event.streams!.isNotEmpty) {
      remoteStream = event.streams!.first;
    } else if (event.track != null) {
      remoteStream = html.MediaStream([event.track!]);
    }

    if (remoteStream != null) {
      debugPrint("WalkieTalkie: Remote audio track received from peer $peerUid");
      var audioEl = _remoteAudioElements[peerUid];
      if (audioEl == null) {
        audioEl = html.AudioElement();
        audioEl.id = 'wt-audio-$peerUid';
        audioEl.autoplay = true;
        audioEl.style.display = 'none';
        html.document.body?.append(audioEl); // Attached to DOM so Chrome plays it!
        _remoteAudioElements[peerUid] = audioEl;
      }

      audioEl.volume = 0.0; // Start silent until channel speaker is active
      audioEl.muted = _isSpeakerMuted;
      js_util.setProperty(audioEl, 'srcObject', remoteStream);

      audioEl.play().catchError((e) {
        debugPrint("Remote audio initial play catch for $peerUid: $e");
      });
    }
  }

  void _cleanupPeerConnection(String peerUid) {
    final pairId = _getPairId(_myUserId, peerUid);
    _peerSubscriptions[pairId]?.cancel();
    _peerSubscriptions.remove(pairId);

    _peerConnections[peerUid]?.close();
    _peerConnections.remove(peerUid);

    final audioEl = _remoteAudioElements[peerUid];
    if (audioEl != null) {
      audioEl.srcObject = null;
      audioEl.remove();
      _remoteAudioElements.remove(peerUid);
    }

    _connectedPeerIds.remove(peerUid);
    notifyListeners();
  }

  void refreshPeers() {
    _runConnectionHealthCheck();
  }

  // ══════════════════════════════════════════════════════════
  // DISPOSE & CLEANUP
  // ══════════════════════════════════════════════════════════

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _channelSubscription?.cancel();
    _usersSubscription?.cancel();
    _incomingSignalsSubscription?.cancel();

    for (final sub in _peerSubscriptions.values) {
      sub.cancel();
    }
    _peerSubscriptions.clear();

    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();

    for (final el in _remoteAudioElements.values) {
      el.srcObject = null;
      el.remove();
    }
    _remoteAudioElements.clear();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        track.stop();
      }
      _localStream = null;
    }

    _isInitialized = false;
    _isTransmitting = false;
    super.dispose();
  }
}
