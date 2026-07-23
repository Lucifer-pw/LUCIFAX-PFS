import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String username;
  final String name;
  final String role; // 'developer', 'cashier', 'kacab', 'manager'
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? lastLogin;

  UserProfile({
    required this.uid,
    required this.username,
    required this.name,
    required this.role,
    this.isOnline = false,
    this.lastSeen,
    this.lastLogin,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return UserProfile(
      uid: uid,
      username: map['username'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'cashier',
      isOnline: map['isOnline'] == true,
      lastSeen: parseDate(map['lastSeen']),
      lastLogin: parseDate(map['lastLogin']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'name': name,
      'role': role,
      'isOnline': isOnline,
      if (lastSeen != null) 'lastSeen': Timestamp.fromDate(lastSeen!),
      if (lastLogin != null) 'lastLogin': Timestamp.fromDate(lastLogin!),
    };
  }

  // Calculate actual online status: isOnline flag AND lastSeen within last 90 seconds
  bool get isActuallyOnline {
    if (!isOnline) return false;
    if (lastSeen == null) return false;
    final diff = DateTime.now().difference(lastSeen!);
    return diff.inSeconds <= 90;
  }

  bool get isDeveloper => role == 'developer';
  bool get isKacab => role == 'kacab' || role == 'manager';
  bool get isAdmin => role == 'admin' || role == 'developer';
}
