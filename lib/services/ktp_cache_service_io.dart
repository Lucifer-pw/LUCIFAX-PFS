import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'ktp_cache_service.dart';

class KtpCacheManager {
  static final Map<String, Uint8List> _memCache = {};

  /// Synchronous peek into RAM memory cache for 0ms instant display
  static Uint8List? peekMemoryCache(String imageUrl) {
    if (imageUrl.isEmpty) return null;
    return _memCache[imageUrl];
  }

  static String _generateHash(String input) {
    // Strip query parameters (like ?alt=media&token=...) so token refreshes never invalidate the cache!
    String cleanUrl = input;
    try {
      final uri = Uri.parse(input);
      cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';
    } catch (_) {}
    int hash = 5381;
    for (int i = 0; i < cleanUrl.length; i++) {
      hash = ((hash << 5) + hash) + cleanUrl.codeUnitAt(i);
    }
    return hash.toRadixString(16).replaceAll('-', 'n');
  }

  /// Get permanent storage directory on Android/Desktop so OS never auto-cleans it
  /// On Android, uses getExternalStorageDirectory() so it appears in:
  /// Penyimpanan internal > Android > data > com.lucifax.Lucifax_PFS > files > ktp_photos
  static Future<Directory> getKtpCacheDir() async {
    Directory? baseDir;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        baseDir = await getExternalStorageDirectory();
      } catch (e) {
        debugPrint('Notice accessing external storage dir: $e');
      }
    }
    try {
      baseDir ??= await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = await getTemporaryDirectory();
    }
    final ktpDir = Directory('${baseDir.path}/ktp_photos');
    if (!await ktpDir.exists()) {
      await ktpDir.create(recursive: true);
    }
    return ktpDir;
  }

  static Future<KtpCacheResult?> getOrFetchKtpImage({
    required String customerId,
    required String imageUrl,
  }) async {
    if (imageUrl.isEmpty) return null;

    final cleanId = customerId.trim().replaceAll(RegExp(r'[^\w\-]'), '_');
    final hash = _generateHash(imageUrl);

    // 1. Check RAM memory cache (Instant 0ms)
    if (_memCache.containsKey(imageUrl)) {
      return KtpCacheResult(
        bytes: _memCache[imageUrl]!,
        isFromCache: true,
      );
    }

    // 2. Check Android Permanent Document Storage
    try {
      final ktpDir = await getKtpCacheDir();
      final cacheFile = File('${ktpDir.path}/KTP_${cleanId}_$hash.jpg');

      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _memCache[imageUrl] = bytes;
          return KtpCacheResult(
            bytes: bytes,
            isFromCache: true,
            localFilePath: cacheFile.path,
          );
        }
      }

      // Check legacy directories if exists to migrate smoothly
      try {
        final legacyDirs = <Directory>[];
        try {
          final extCache = await getExternalCacheDirectories();
          if (extCache != null && extCache.isNotEmpty) {
            legacyDirs.add(Directory('${extCache.first.path}/ktp'));
          }
        } catch (_) {}
        try {
          final tempDir = await getTemporaryDirectory();
          legacyDirs.add(Directory('${tempDir.path}/ktp'));
          legacyDirs.add(Directory('${tempDir.path}/ktp_photos'));
        } catch (_) {}
        try {
          final docDir = await getApplicationDocumentsDirectory();
          legacyDirs.add(Directory('${docDir.path}/ktp_photos'));
        } catch (_) {}

        for (final dir in legacyDirs) {
          if (await dir.exists()) {
            final legacyFile = File('${dir.path}/KTP_${cleanId}_$hash.jpg');
            if (await legacyFile.exists()) {
              final bytes = await legacyFile.readAsBytes();
              if (bytes.isNotEmpty) {
                await cacheFile.writeAsBytes(bytes);
                _memCache[imageUrl] = bytes;
                return KtpCacheResult(
                  bytes: bytes,
                  isFromCache: true,
                  localFilePath: cacheFile.path,
                );
              }
            }
          }
        }
      } catch (_) {}

      // If URL changed, clean any older cached image for this customer
      try {
        final allFiles = ktpDir.listSync();
        for (var entity in allFiles) {
          if (entity is File && entity.path.contains('KTP_${cleanId}_')) {
            entity.deleteSync();
          }
        }
      } catch (_) {}

      // 3. Download once from Firebase Storage and store permanently in phone storage
      final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 35));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        await cacheFile.writeAsBytes(bytes);
        _memCache[imageUrl] = bytes;
        return KtpCacheResult(
          bytes: bytes,
          isFromCache: false,
          localFilePath: cacheFile.path,
        );
      }
    } catch (e) {
      debugPrint('KtpCacheManager IO error: $e');
    }

    return null;
  }

  static Future<void> clearKtpCache() async {
    _memCache.clear();
    try {
      final ktpDir = await getKtpCacheDir();
      if (await ktpDir.exists()) {
        await ktpDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing KTP cache: $e');
    }
  }
}
