import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'ktp_cache_service.dart';

class KtpCacheManager {
  static final Map<String, Uint8List> _memCache = {};

  static String _generateHash(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
    }
    return hash.toRadixString(16).replaceAll('-', 'n');
  }

  static Future<Directory> getKtpCacheDir() async {
    Directory? baseDir;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final extDirs = await getExternalCacheDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          baseDir = extDirs.first;
        }
      } catch (e) {
        debugPrint('Notice accessing external cache dirs: $e');
      }
    }
    baseDir ??= await getTemporaryDirectory();
    final ktpDir = Directory('${baseDir.path}/ktp');
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

    // 1. Check RAM memory cache
    if (_memCache.containsKey(imageUrl)) {
      return KtpCacheResult(
        bytes: _memCache[imageUrl]!,
        isFromCache: true,
      );
    }

    // 2. Check Android / Local Disk storage
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

      // If URL changed, clean any older cached image for this customer
      try {
        final allFiles = ktpDir.listSync();
        for (var entity in allFiles) {
          if (entity is File && entity.path.contains('KTP_${cleanId}_')) {
            entity.deleteSync();
          }
        }
      } catch (_) {}

      // 3. Download once from Firebase Storage
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
