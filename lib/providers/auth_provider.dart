import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  UserProfile? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _presenceTimer;

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _currentUser != null;

  AuthProvider() {
    _authService.authStateChanges.listen((user) async {
      if (user == null) {
        _stopPresenceHeartbeat();
        _currentUser = null;
        notifyListeners();
      } else {
        _isLoading = true;
        notifyListeners();
        try {
          _currentUser = await _authService.getCurrentUserProfile();
          if (_currentUser != null) {
            _startPresenceHeartbeat();
          }
        } catch (e) {
          _errorMessage = e.toString();
        } finally {
          _isLoading = false;
          notifyListeners();
        }
      }
    });
  }

  void _startPresenceHeartbeat() {
    _stopPresenceHeartbeat();
    final uid = _currentUser?.uid;
    if (uid == null) return;

    // Send immediate presence update
    _authService.updateUserPresence(uid, true);

    // Heartbeat every 25 seconds
    _presenceTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_currentUser != null) {
        _authService.updateUserPresence(_currentUser!.uid, true);
      }
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  Stream<List<UserProfile>> getUsersStream() {
    return _authService.getUsersStream();
  }

  Future<void> signIn(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signIn(username, password);
      if (_currentUser != null) {
        _startPresenceHeartbeat();
      }
    } catch (e) {
      _errorMessage = "Username atau Password yang Anda masukkan salah.";
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp(String username, String password, {String name = '', String role = 'kacab'}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signUp(username, password, name: name, role: role);
      if (_currentUser != null) {
        _startPresenceHeartbeat();
      }
    } catch (e) {
      _errorMessage = "Pendaftaran gagal: Username sudah terpakai atau password kurang kuat.";
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      _stopPresenceHeartbeat();
      if (_currentUser != null) {
        await _authService.updateUserPresence(_currentUser!.uid, false);
      }
      await _authService.signOut();
      _currentUser = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> seedDefaultUsers() async {
    await _authService.seedDefaultUsers();
  }

  @override
  void dispose() {
    _stopPresenceHeartbeat();
    super.dispose();
  }
}
