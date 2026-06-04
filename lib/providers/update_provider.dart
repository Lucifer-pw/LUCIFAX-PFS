import 'package:flutter/foundation.dart';

import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _updateInfo;
  bool _isChecking = false;
  String? _error;

  UpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  String? get error => _error;
  bool get hasUpdate => _updateInfo != null;

  /// Checks the GitHub repository for a newer release.
  Future<void> checkForUpdate() async {
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      _updateInfo = await UpdateService.checkForUpdate();
    } catch (e) {
      _error = 'Gagal memeriksa update: $e';
      _updateInfo = null;
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  /// Opens the APK download URL in the system browser.
  Future<bool> launchUpdate() async {
    if (_updateInfo == null) return false;

    try {
      return await UpdateService.launchDownloadUrl(_updateInfo!.downloadUrl);
    } catch (e) {
      _error = 'Gagal membuka link download: $e';
      notifyListeners();
      return false;
    }
  }
}
