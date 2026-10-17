import 'package:cloud_firestore/cloud_firestore.dart';

class WaGatewaySession {
  final String status; // 'CONNECTED', 'QR_READY', 'CONNECTING', 'DISCONNECTED', 'ERROR'
  final String? qrCode; // base64 data url 'data:image/png;base64,...'
  final String? phone;
  final String? pushName;
  final DateTime? updatedAt;
  final DateTime? lastConnectedAt;
  final String? lastDisconnectReason;

  WaGatewaySession({
    required this.status,
    this.qrCode,
    this.phone,
    this.pushName,
    this.updatedAt,
    this.lastConnectedAt,
    this.lastDisconnectReason,
  });

  bool get isConnected => status == 'CONNECTED';
  bool get isQrReady => status == 'QR_READY' && qrCode != null && qrCode!.isNotEmpty;

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
      updatedAt: parseDate(map['updatedAt'] ?? map['lastUpdated']),
      lastConnectedAt: parseDate(map['lastConnectedAt']),
      lastDisconnectReason: map['lastDisconnectReason'] as String?,
    );
  }
}
