import 'package:cloud_firestore/cloud_firestore.dart';

class WaGatewaySession {
  final String status; // 'CONNECTED', 'QR_READY', 'CONNECTING', 'DISCONNECTED', 'ERROR', 'STANDBY'
  final String? qrCode; // base64 data url 'data:image/png;base64,...'
  final String? phone;
  final String? pushName;
  final String? deviceName;
  final String? devicePlatform;
  final String? instanceId;
  final DateTime? updatedAt;
  final DateTime? lastConnectedAt;
  final DateTime? lastHeartbeat;
  final String? lastDisconnectReason;

  WaGatewaySession({
    required this.status,
    this.qrCode,
    this.phone,
    this.pushName,
    this.deviceName,
    this.devicePlatform,
    this.instanceId,
    this.updatedAt,
    this.lastConnectedAt,
    this.lastHeartbeat,
    this.lastDisconnectReason,
  });

  bool get isConnected => status == 'CONNECTED';
  bool get isStandby => status == 'STANDBY';
  bool get isQrReady => status == 'QR_READY' && qrCode != null && qrCode!.isNotEmpty;

  /// Cek apakah detak jantung (heartbeat) aktif dalam 45 detik terakhir
  bool get isHeartbeatAlive {
    if (lastHeartbeat == null) return false;
    return DateTime.now().difference(lastHeartbeat!).inSeconds < 45;
  }

  /// Nama perangkat yang ramah pengguna
  String get formattedDeviceName {
    if (deviceName != null && deviceName!.trim().isNotEmpty) {
      return deviceName!.trim();
    }
    if (devicePlatform == 'android') return '📱 HP Android (Termux)';
    if (devicePlatform == 'win32') return '💻 Laptop Kasir (Windows)';
    return '🖥️ Perangkat Gateway';
  }

  /// Format teks waktu sinyal terakhir
  String get heartbeatAgo {
    if (lastHeartbeat == null) return 'Belum ada detak';
    final diff = DateTime.now().difference(lastHeartbeat!);
    if (diff.inSeconds < 0) return 'Baru saja';
    if (diff.inSeconds < 15) return 'Aktif (${diff.inSeconds} detik lalu)';
    if (diff.inSeconds < 60) return '${diff.inSeconds} detik lalu';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    return '${diff.inHours} jam lalu';
  }

  factory WaGatewaySession.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return WaGatewaySession(status: 'DISCONNECTED');
    }

    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        try {
          return DateTime.parse(val);
        } catch (_) {}
      }
      return null;
    }

    return WaGatewaySession(
      status: (map['status'] ?? 'DISCONNECTED').toString(),
      qrCode: map['qrCode'] as String?,
      phone: map['phone'] as String?,
      pushName: map['pushName'] as String?,
      deviceName: map['deviceName'] as String?,
      devicePlatform: map['devicePlatform'] as String?,
      instanceId: map['instanceId'] as String?,
      updatedAt: parseDate(map['updatedAt'] ?? map['lastUpdated']),
      lastConnectedAt: parseDate(map['lastConnectedAt']),
      lastHeartbeat: parseDate(map['lastHeartbeat'] ?? map['updatedAt']),
      lastDisconnectReason: map['lastDisconnectReason'] as String?,
    );
  }
}
