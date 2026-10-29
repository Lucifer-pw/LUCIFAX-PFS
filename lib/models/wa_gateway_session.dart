import 'package:cloud_firestore/cloud_firestore.dart';

class WaGatewaySession {
  final String status; // 'CONNECTED', 'QR_READY', 'CONNECTING', 'DISCONNECTED', 'ERROR', 'STANDBY'
  final String? qrCode; // base64 data url 'data:image/png;base64,...'
  final String? phone;
  final String? pushName;
  final String? deviceName;
  final String? devicePlatform;
  final String? instanceId;
  final Map<String, dynamic>? deviceDetails;
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
    this.deviceDetails,
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

  // Rincian Spesifikasi Perangkat
  String? get brand => deviceDetails?['brand'] as String?;
  String? get model => deviceDetails?['model'] as String?;
  String? get fullModelName => (deviceDetails?['fullModelName'] as String?) ?? deviceName;
  String? get osVersion => deviceDetails?['osVersion'] as String?;
  String? get ramInfo => deviceDetails?['ramInfo'] as String?;
  String? get batteryInfo => deviceDetails?['batteryInfo'] as String?;
  String? get hostname => deviceDetails?['hostname'] as String?;

  /// Nama perangkat yang ramah pengguna
  String get formattedDeviceName {
    if (fullModelName != null && fullModelName!.trim().isNotEmpty) {
      return fullModelName!.trim();
    }
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
      deviceDetails: map['deviceDetails'] is Map ? Map<String, dynamic>.from(map['deviceDetails'] as Map) : null,
      updatedAt: parseDate(map['updatedAt'] ?? map['lastUpdated']),
      lastConnectedAt: parseDate(map['lastConnectedAt']),
      lastHeartbeat: parseDate(map['lastHeartbeat'] ?? map['updatedAt']),
      lastDisconnectReason: map['lastDisconnectReason'] as String?,
    );
  }
}

/// Model untuk node perangkat dalam cluster WA Gateway
class WaGatewayNode {
  final String instanceId;
  final String deviceName;
  final String devicePlatform;
  final Map<String, dynamic>? deviceDetails;
  final String status; // 'CONNECTED', 'STANDBY', 'OFFLINE'
  final DateTime? lastHeartbeat;
  final DateTime? updatedAt;

  WaGatewayNode({
    required this.instanceId,
    required this.deviceName,
    required this.devicePlatform,
    this.deviceDetails,
    required this.status,
    this.lastHeartbeat,
    this.updatedAt,
  });

  bool get isConnected => status == 'CONNECTED';
  bool get isStandby => status == 'STANDBY';

  bool get isAlive {
    if (lastHeartbeat == null) return false;
    return DateTime.now().difference(lastHeartbeat!).inSeconds < 130;
  }

  String get fullModelName {
    final fm = deviceDetails?['fullModelName'] as String?;
    if (fm != null && fm.trim().isNotEmpty) return fm.trim();
    final m = deviceDetails?['model'] as String?;
    if (m != null && m.trim().isNotEmpty) return m.trim();
    return deviceName.trim();
  }

  String? get batteryInfo => deviceDetails?['battery'] as String? ?? deviceDetails?['batteryInfo'] as String?;
  String? get ramInfo => deviceDetails?['ram'] as String? ?? deviceDetails?['ramInfo'] as String?;
  String? get osVersion => deviceDetails?['osVersion'] as String?;

  String get heartbeatAgo {
    if (lastHeartbeat == null) return 'Tidak diketahui';
    final diff = DateTime.now().difference(lastHeartbeat!);
    if (diff.inSeconds < 5) return 'Baru saja';
    if (diff.inSeconds < 60) return '${diff.inSeconds} detik lalu';
    return '${diff.inMinutes} menit lalu';
  }

  factory WaGatewayNode.fromMap(Map<String, dynamic> map, String id) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return WaGatewayNode(
      instanceId: (map['instanceId'] as String?) ?? id,
      deviceName: (map['deviceName'] as String?) ?? 'Perangkat Gateway',
      devicePlatform: (map['devicePlatform'] as String?) ?? 'unknown',
      deviceDetails: map['deviceDetails'] is Map ? Map<String, dynamic>.from(map['deviceDetails'] as Map) : null,
      status: (map['status'] as String?) ?? 'STANDBY',
      lastHeartbeat: parseDate(map['lastHeartbeat'] ?? map['updatedAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }
}
