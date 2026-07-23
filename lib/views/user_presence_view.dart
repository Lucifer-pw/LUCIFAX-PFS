import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../models/user_profile.dart';

class UserPresenceView extends StatefulWidget {
  const UserPresenceView({super.key});

  @override
  State<UserPresenceView> createState() => _UserPresenceViewState();
}

class _UserPresenceViewState extends State<UserPresenceView> {
  String _searchQuery = '';

  String _formatRelativeTime(DateTime? date, bool isOnline) {
    if (isOnline) return 'Online (Aktif)';
    if (date == null) return 'Belum Pernah';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds} detik lalu';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} menit lalu';
    } else if (diff.inHours < 24 && date.day == now.day) {
      return 'Hari ini ${DateFormat('HH:mm').format(date)}';
    } else if (diff.inDays < 2) {
      return 'Kemarin ${DateFormat('HH:mm').format(date)}';
    } else {
      return DateFormat('dd-MM-yyyy HH:mm').format(date);
    }
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '-';
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return 'Hari ini ${DateFormat('HH:mm').format(date)}';
    }
    return DateFormat('dd-MM-yyyy HH:mm').format(date);
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'developer':
        return const Color(0xFF38BDF8); // Cyan
      case 'kacab':
      case 'manager':
        return Colors.amberAccent; // Gold
      case 'cashier':
      case 'kasir':
        return const Color(0xFFC084FC); // Purple
      default:
        return const Color(0xFF94A3B8); // Grey
    }
  }

  String _getRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'developer':
        return 'DEVELOPER';
      case 'kacab':
      case 'manager':
        return 'KEPALA SALES / KACAB';
      case 'cashier':
      case 'kasir':
        return 'KASIR';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;

    // Security Gate: Developer role check
    if (currentUser?.isDeveloper != true) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.gpp_bad_rounded, size: 72, color: Colors.redAccent),
              SizedBox(height: 16),
              Text(
                'Akses Ditolak',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Halaman ini khusus untuk Role Developer.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.sensors_rounded, color: Color(0xFF38BDF8), size: 28),
                      SizedBox(width: 10),
                      Text(
                        'User Active & Presence Monitor',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Pantau Status Online Real-Time & History Last Seen Seluruh Pengguna App (Developer Only)',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'DEVELOPER MODE ACTIVE',
                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Real-time Stream of Users
          Expanded(
            child: StreamBuilder<List<UserProfile>>(
              stream: authProvider.getUsersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                }

                final users = snapshot.data ?? [];
                final onlineUsers = users.where((u) => u.isActuallyOnline).toList();
                final offlineUsers = users.where((u) => !u.isActuallyOnline).toList();

                // Apply search query filter
                final filteredUsers = users.where((u) {
                  if (_searchQuery.isEmpty) return true;
                  final q = _searchQuery.toLowerCase();
                  return u.name.toLowerCase().contains(q) ||
                      u.username.toLowerCase().contains(q) ||
                      u.role.toLowerCase().contains(q);
                }).toList();

                // Sort: Online users first, then by lastSeen descending
                filteredUsers.sort((a, b) {
                  if (a.isActuallyOnline && !b.isActuallyOnline) return -1;
                  if (!a.isActuallyOnline && b.isActuallyOnline) return 1;
                  final aTime = a.lastSeen ?? DateTime(2000);
                  final bTime = b.lastSeen ?? DateTime(2000);
                  return bTime.compareTo(aTime);
                });

                return Column(
                  children: [
                    // Summary Stat Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'User Online / Aktif',
                            value: '${onlineUsers.length}',
                            icon: Icons.online_prediction_rounded,
                            color: const Color(0xFF4ADE80),
                            subtext: 'Sedang membuka aplikasi',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'User Offline',
                            value: '${offlineUsers.length}',
                            icon: Icons.power_settings_new_rounded,
                            color: const Color(0xFF94A3B8),
                            subtext: 'Tutup app / tidak aktif',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Total Akun Terdaftar',
                            value: '${users.length}',
                            icon: Icons.people_alt_rounded,
                            color: const Color(0xFF38BDF8),
                            subtext: 'Seluruh akun di sistem',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Controls & Filter Bar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Cari berdasarkan nama, username, atau role...',
                                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                                prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // User List Table
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: filteredUsers.isEmpty
                            ? const Center(
                                child: Text(
                                  'Tidak ada pengguna ditemukan.',
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ListView.separated(
                                  itemCount: filteredUsers.length,
                                  separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                                  itemBuilder: (context, index) {
                                    final u = filteredUsers[index];
                                    final isOnline = u.isActuallyOnline;
                                    final roleColor = _getRoleColor(u.role);
                                    final isSelf = currentUser != null && u.uid == currentUser.uid;

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      leading: Stack(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: roleColor.withOpacity(0.2),
                                            child: Text(
                                              u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                                              style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: const Color(0xFF1E293B), width: 2),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      title: Row(
                                        children: [
                                          Text(
                                            u.name,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '@${u.username}',
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                                          ),
                                          if (isSelf) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF38BDF8).withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text('ANDA', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: roleColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: roleColor.withOpacity(0.3)),
                                              ),
                                              child: Text(
                                                _getRoleLabel(u.role),
                                                style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.login_rounded, size: 14, color: Color(0xFF64748B)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Login: ${_formatDateTime(u.lastLogin)}',
                                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isOnline ? const Color(0xFF4ADE80).withOpacity(0.15) : const Color(0xFF334155),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isOnline ? const Color(0xFF4ADE80).withOpacity(0.4) : Colors.transparent,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  isOnline ? 'ONLINE' : 'OFFLINE',
                                                  style: TextStyle(
                                                    color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Aktif: ${_formatRelativeTime(u.lastSeen, isOnline)}',
                                            style: TextStyle(
                                              color: isOnline ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                Text(subtext, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
