import 'dart:typed_data';

export 'ktp_cache_service_io.dart'
    if (dart.library.html) 'ktp_cache_service_web.dart';

class KtpCacheResult {
  final Uint8List bytes;
  final bool isFromCache;
  final String? localFilePath;

  KtpCacheResult({
    required this.bytes,
    required this.isFromCache,
    this.localFilePath,
  });
}
