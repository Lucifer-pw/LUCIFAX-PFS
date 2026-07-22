class UserProfile {
  final String uid;
  final String username;
  final String name;
  final String role; // 'developer', 'cashier', 'manager'

  UserProfile({
    required this.uid,
    required this.username,
    required this.name,
    required this.role,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map, String uid) {
    return UserProfile(
      uid: uid,
      username: map['username'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'cashier',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'name': name,
      'role': role,
    };
  }

  bool get isDeveloper => role == 'developer';
  bool get isKacab => role == 'kacab' || role == 'manager';
  bool get isAdmin => role == 'admin' || role == 'developer';
}
