import 'dart:convert';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'ktp_cache_service.dart';

class KtpCacheManager {
  static final Map<String, Uint8List> _memCache = {};
  static const String _keyPrefix = 'ktp_c_';

  static String _generateHash(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
    }
    return hash.toRadixString(16).replaceAll('-', 'n');
  }

  static Future<KtpCacheResult?> getOrFetchKtpImage({
    required String customerId,
    required String imageUrl,
  }) async {
    if (imageUrl.isEmpty) return null;

    final hash = _generateHash(imageUrl);
    final storageKey = '$_keyPrefix$hash';

    // 1. Check RAM memory cache (Instant 0ms)
    if (_memCache.containsKey(imageUrl)) {
      return KtpCacheResult(
        bytes: _memCache[imageUrl]!,
        isFromCache: true,
      );
    }

    // 2. Check Browser LocalStorage (Persistent across reloads)
    try {
      final savedBase64 = html.window.localStorage[storageKey];
      if (savedBase64 != null && savedBase64.isNotEmpty) {
        final bytes = base64Decode(savedBase64);
        _memCache[imageUrl] = bytes;
        return KtpCacheResult(
          bytes: bytes,
          isFromCache: true,
        );
      }
    } catch (e) {
      debugPrint('LocalStorage read notice: $e');
    }

    // 3. Fetch from Firebase Storage
    try {
      final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 35));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        _memCache[imageUrl] = bytes;

        // Persist to LocalStorage with safe quota management
        try {
          final b64 = base64Encode(bytes);
          _pruneLocalStorageIfFull();
          html.window.localStorage[storageKey] = b64;
        } catch (e) {
          try {
            _clearOldKtpLocalStorage();
            html.window.localStorage[storageKey] = base64Encode(bytes);
          } catch (_) {}
        }

        return KtpCacheResult(
          bytes: bytes,
          isFromCache: false,
        );
      }
    } catch (e) {
      debugPrint('Web KTP fetch error: $e');
    }

    return null;
  }

  static void _pruneLocalStorageIfFull() {
    try {
      final ktpKeys = html.window.localStorage.keys
          .where((k) => k.startsWith(_keyPrefix))
          .toList();
      if (ktpKeys.length > 15) {
        for (int i = 0; i < (ktpKeys.length - 15); i++) {
          html.window.localStorage.remove(ktpKeys[i]);
        }
      }
    } catch (_) {}
  }

  static void _clearOldKtpLocalStorage() {
    try {
      final ktpKeys = html.window.localStorage.keys
          .where((k) => k.startsWith(_keyPrefix))
          .toList();
      for (final k in ktpKeys) {
        html.window.localStorage.remove(k);
      }
    } catch (_) {}
  }

  static Future<void> clearKtpCache() async {
    _memCache.clear();
    _clearOldKtpLocalStorage();
  }
}
