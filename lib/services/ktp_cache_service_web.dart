import 'dart:convert';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:indexed_db' as idb;
import 'package:http/http.dart' as http;
import 'ktp_cache_service.dart';

class KtpCacheManager {
  static final Map<String, Uint8List> _memCache = {};
  static const String _keyPrefix = 'ktp_c_';
  static const String _idbName = 'lucifax_media_cache';
  static const String _storeName = 'photos';
  static idb.Database? _db;
  static bool _idbInitAttempted = false;

  static String _generateHash(String input) {
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

  static Future<idb.Database?> _getIdb() async {
    if (_db != null) return _db;
    if (_idbInitAttempted && _db == null) return null;
    _idbInitAttempted = true;
    try {
      if (!idb.IdbFactory.supported || html.window.indexedDB == null) {
        return null;
      }
      _db = await html.window.indexedDB!.open(
        _idbName,
        version: 1,
        onUpgradeNeeded: (event) {
          final req = event.target as idb.OpenDBRequest;
          final db = req.result as idb.Database;
          if (!db.objectStoreNames!.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        },
      );
      return _db;
    } catch (e) {
      debugPrint('IndexedDB open notice: $e');
      return null;
    }
  }

  static Future<Uint8List?> _readFromIdb(String hash) async {
    try {
      final db = await _getIdb();
      if (db == null) return null;
      final txn = db.transaction(_storeName, 'readonly');
      final store = txn.objectStore(_storeName);
      final raw = await store.getObject(hash);
      if (raw != null && raw is String && raw.isNotEmpty) {
        return base64Decode(raw);
      }
    } catch (e) {
      debugPrint('IndexedDB read notice: $e');
    }
    return null;
  }

  static Future<void> _writeToIdb(String hash, Uint8List bytes) async {
    try {
      final db = await _getIdb();
      if (db == null) return;
      final txn = db.transaction(_storeName, 'readwrite');
      final store = txn.objectStore(_storeName);
      final b64 = base64Encode(bytes);
      await store.put(b64, hash);
    } catch (e) {
      debugPrint('IndexedDB write notice: $e');
    }
  }

  /// Synchronous peek into RAM & Web LocalStorage for 0ms instant display
  static Uint8List? peekMemoryCache(String imageUrl) {
    if (imageUrl.isEmpty) return null;
    if (_memCache.containsKey(imageUrl)) {
      return _memCache[imageUrl];
    }
    try {
      final hash = _generateHash(imageUrl);
      final storageKey = '$_keyPrefix$hash';
      final savedBase64 = html.window.localStorage[storageKey];
      if (savedBase64 != null && savedBase64.isNotEmpty) {
        final bytes = base64Decode(savedBase64);
        _memCache[imageUrl] = bytes;
        return bytes;
      }
    } catch (_) {}
    return null;
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

    // 2. Check Browser LocalStorage (Synchronous peek)
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

    // 3. Check Browser IndexedDB (Persistent across restarts, NO 5MB/15-file limit)
    try {
      final idbBytes = await _readFromIdb(hash);
      if (idbBytes != null && idbBytes.isNotEmpty) {
        _memCache[imageUrl] = idbBytes;
        // Also put in LocalStorage if space permits for future synchronous peek
        try {
          _pruneLocalStorageIfFull();
          html.window.localStorage[storageKey] = base64Encode(idbBytes);
        } catch (_) {}
        return KtpCacheResult(
          bytes: idbBytes,
          isFromCache: true,
        );
      }
    } catch (e) {
      debugPrint('IndexedDB check notice: $e');
    }

    // 4. Download ONCE from Firebase Storage only when totally missing
    try {
      final resp = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 35));
      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        _memCache[imageUrl] = bytes;

        // Persist permanently to IndexedDB (virtually unlimited quota in Chrome)
        _writeToIdb(hash, bytes).catchError((_) {});

        // Persist to LocalStorage with safe quota management for fast 0ms peek
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
    try {
      final db = await _getIdb();
      if (db != null) {
        final txn = db.transaction(_storeName, 'readwrite');
        final store = txn.objectStore(_storeName);
        await store.clear();
      }
    } catch (_) {}
  }
}
