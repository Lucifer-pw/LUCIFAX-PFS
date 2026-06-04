import 'dart:io';
import 'package:flutter/foundation.dart';

import '../services/update_service.dart';

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _updateInfo;
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _error;

  UpdateInfo? get updateInfo => _updateInfo;
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
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

  /// Downloads the APK in the background and launches the installer directly.
  /// Falls back to browser launch if installation or download fails.
  Future<bool> downloadAndInstall() async {
    if (_updateInfo == null) return false;
    
    _isDownloading = true;
    _downloadProgress = 0.0;
    _error = null;
    notifyListeners();

    try {
      final File? apkFile = await UpdateService.downloadApk(
        _updateInfo!.downloadUrl,
        (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );

      if (apkFile == null) {
        throw Exception("Gagal mengunduh file APK.");
      }

      final success = await UpdateService.installApk(apkFile.path);
      if (!success) {
        // Fallback to launching in browser if installer can't be triggered
        return await launchUpdate();
      }
      return true;
    } catch (e) {
      _error = 'Gagal memasang update otomatis: $e';
      notifyListeners();
      // Fallback to launching in browser
      return await launchUpdate();
    } finally {
      _isDownloading = false;
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
