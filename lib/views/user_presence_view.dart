import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/role_permissions_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import '../models/invoice_print_log.dart';
import '../models/remote_print_command.dart';
import '../services/firebase_service.dart';
import '../services/webrtc_service.dart';
import '../widgets/live_screen_viewer.dart';

class UserPresenceView extends StatefulWidget {
  const UserPresenceView({super.key});

  @override
  State<UserPresenceView> createState() => _UserPresenceViewState();
}

class _UserPresenceViewState extends State<UserPresenceView> {
  final FirebaseService _firebaseService = FirebaseService();
  int _selectedTab = 0; // 0: User Online Monitor, 1: Role KACAB Permissions, 2: Log Cetak Invoice
  String _searchQuery = '';
  String _logSearchQuery = '';
  String _logRoleFilter = 'ALL'; // 'ALL', 'NON_DEV', 'KACAB', 'CASHIER', 'DEV'
  String _logOptionFilter = 'ALL'; // 'ALL', 'TANGGAL_BARU', 'TANGGAL_AWAL'

  final List<Map<String, dynamic>> _kacabFeatures = [
    {
      'key': 'transaction_entry',
      'title': 'Transaksi Kasir',
      'icon': Icons.point_of_sale_rounded,
      'desc': 'Menu untuk membuat invoice baru dan pencatatan transaksi penjualan kasir.',
    },
    {
      'key': 'transaction_history',
      'title': 'Histori Transaksi',
      'icon': Icons.history_rounded,
      'desc': 'Daftar dan riwayat seluruh nota transaksi penjualan cabang (Default ON).',
    },
    {
      'key': 'master_product',
      'title': 'Master Barang',
      'icon': Icons.shopping_bag_outlined,
      'desc': 'Katalog data produk, harga unit, dan pengeditan Kode Induk / SKU.',
    },
    {
      'key': 'master_customer',
      'title': 'Master Pelanggan',
      'icon': Icons.people_outline_rounded,
      'desc': 'Daftar data toko/pelanggan dan pengeditan profil customer.',
    },
    {
      'key': 'stock_input',
      'title': 'Input Stok',
      'icon': Icons.add_box_outlined,
      'desc': 'Menu input penerimaan stok barang mingguan (M1-M5).',
    },
    {
      'key': 'erp_matrix',
      'title': 'Stok Opname & ERP',
      'icon': Icons.table_chart_outlined,
      'desc': 'Tabel matriks monitoring pergerakan stok awal, total keluar, dan stok akhir.',
    },
    {
      'key': 'receivable_list',
      'title': 'Kartu Piutang Toko',
      'icon': Icons.account_balance_wallet_outlined,
      'desc': 'Rekapitulasi sisa tagihan piutang toko dan pencatatan pembayaran.',
    },
    {
      'key': 'ranking_kacab',
      'title': 'Ranking Kacab',
      'icon': Icons.leaderboard_outlined,
      'desc': 'Peringkat omset bulanan dan performa penjualan antar cabang.',
    },
    {
      'key': 'attendance',
      'title': 'Absensi Pegawai',
      'icon': Icons.assignment_ind_rounded,
      'desc': 'Pencatatan absensi, daftar hadir, dan rekap jam kerja karyawan.',
    },
    {
      'key': 'dashboard',
      'title': 'Analitik & Klasifikasi',
      'icon': Icons.bar_chart_rounded,
      'desc': 'Grafik analisis performa bisnis, omset bulanan, dan statistik barang.',
    },
    {
      'key': 'kmeans_analysis',
      'title': 'Clustering K-Means (Skripsi)',
      'icon': Icons.hub_rounded,
      'desc': 'Analisis K-Means Clustering, Data Training & Testing, dan Rekonsiliasi Stok.',
    },
    {
      'key': 'monthly_operational_expenses',
      'title': 'Biaya Operasional Bulanan',
      'icon': Icons.request_quote_rounded,
      'desc': 'Pencatatan & rekapitulasi pengeluaran operasional serta biaya of country bulanan.',
    },
  ];

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

  Widget _buildTableHeader(String label, {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        textAlign: align,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final rolePermissionsProvider = Provider.of<RolePermissionsProvider>(context);
    final currentUser = authProvider.currentUser;

    // Security Gate: Developer role check
    if (currentUser?.isDeveloper != true) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10.0 : 16.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section (Compact)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.developer_board_rounded, color: const Color(0xFF38BDF8), size: isMobile ? 18 : 22),
                      const SizedBox(width: 6),
                      Text(
                        'Developer Control & Monitor',
                        style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Monitoring Aktivitas User Real-Time & Pengaturan Akses Menu Role KACAB',
                    style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 10.5 : 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'DEVELOPER MODE ACTIVE',
                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal Scrollable Tab Bar Selector for Mobile & Desktop
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabButton(
                  index: 0,
                  icon: Icons.sensors_rounded,
                  label: 'User Online Monitor',
                  isMobile: isMobile,
                ),
                const SizedBox(width: 6),
                _buildTabButton(
                  index: 1,
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Hak Akses Role KACAB',
                  isMobile: isMobile,
                ),
                const SizedBox(width: 6),
                _buildTabButton(
                  index: 2,
                  icon: Icons.receipt_long_rounded,
                  label: 'Log Cetak Invoice',
                  isMobile: isMobile,
                ),
                const SizedBox(width: 6),
                _buildTabButton(
                  index: 3,
                  icon: Icons.podcasts_rounded,
                  label: '📡 Remote Print Console',
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Tab Contents
          Expanded(
            child: _selectedTab == 0
                ? _buildUserPresenceTab(authProvider, currentUser, isMobile)
                : _selectedTab == 1
                    ? _buildKacabPermissionsTab(rolePermissionsProvider, isMobile)
                    : _selectedTab == 2
                        ? _buildInvoicePrintLogsTab(isMobile)
                        : _buildRemotePrintConsoleTab(authProvider, isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({required int index, required IconData icon, required String label, required bool isMobile}) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 6 : 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isMobile ? 14 : 16,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: isMobile ? 11 : 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: User Presence Monitor
  Widget _buildUserPresenceTab(AuthProvider authProvider, UserProfile? currentUser, bool isMobile) {
    return StreamBuilder<List<UserProfile>>(
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
            // Summary Stat Cards (Responsive Stack on Mobile)
            isMobile
                ? Column(
                    children: [
                      _buildStatCard(
                        title: 'User Online / Aktif',
                        value: '${onlineUsers.length}',
                        icon: Icons.online_prediction_rounded,
                        color: const Color(0xFF4ADE80),
                        subtext: 'Sedang membuka aplikasi',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 6),
                      _buildStatCard(
                        title: 'User Offline',
                        value: '${offlineUsers.length}',
                        icon: Icons.power_settings_new_rounded,
                        color: const Color(0xFF94A3B8),
                        subtext: 'Tutup app / tidak aktif',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 6),
                      _buildStatCard(
                        title: 'Total Akun Terdaftar',
                        value: '${users.length}',
                        icon: Icons.people_alt_rounded,
                        color: const Color(0xFF38BDF8),
                        subtext: 'Seluruh akun di sistem',
                        isMobile: isMobile,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'User Online / Aktif',
                          value: '${onlineUsers.length}',
                          icon: Icons.online_prediction_rounded,
                          color: const Color(0xFF4ADE80),
                          subtext: 'Sedang membuka aplikasi',
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatCard(
                          title: 'User Offline',
                          value: '${offlineUsers.length}',
                          icon: Icons.power_settings_new_rounded,
                          color: const Color(0xFF94A3B8),
                          subtext: 'Tutup app / tidak aktif',
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Total Akun Terdaftar',
                          value: '${users.length}',
                          icon: Icons.people_alt_rounded,
                          color: const Color(0xFF38BDF8),
                          subtext: 'Seluruh akun di sistem',
                          isMobile: isMobile,
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 6),

            // Controls & Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: SizedBox(
                height: 32,
                child: TextField(
                  style: TextStyle(color: Colors.white, fontSize: isMobile ? 11.5 : 12.5),
                  decoration: InputDecoration(
                    hintText: 'Cari berdasarkan nama, username, atau role...',
                    hintStyle: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 11 : 12),
                    prefixIcon: Icon(Icons.search, color: const Color(0xFF38BDF8), size: isMobile ? 16 : 18),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // User List Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
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
                        borderRadius: BorderRadius.circular(10),
                        child: ListView.separated(
                          itemCount: filteredUsers.length,
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (context, index) {
                            final u = filteredUsers[index];
                            final isOnline = u.isActuallyOnline;
                            final roleColor = _getRoleColor(u.role);
                            final isSelf = currentUser != null && u.uid == currentUser.uid;

                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 6 : 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // User Avatar
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: isMobile ? 18 : 22,
                                        backgroundColor: roleColor.withOpacity(0.2),
                                        child: Text(
                                          u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: isMobile ? 14 : 16),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: isMobile ? 10 : 12,
                                          height: isMobile ? 10 : 12,
                                          decoration: BoxDecoration(
                                            color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: const Color(0xFF1E293B), width: 2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // User Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                u.name,
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 13 : 15),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '@${u.username}',
                                              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 11 : 13),
                                            ),
                                            if (isSelf) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF38BDF8).withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text('ANDA', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: roleColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: roleColor.withOpacity(0.3)),
                                              ),
                                              child: Text(
                                                _getRoleLabel(u.role),
                                                style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Text(
                                              'Login: ${_formatDateTime(u.lastLogin)}',
                                              style: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 10 : 12),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Status Badge
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: isMobile ? 2.5 : 4),
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
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isOnline ? 'ONLINE' : 'OFFLINE',
                                              style: TextStyle(
                                                color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8),
                                                fontWeight: FontWeight.bold,
                                                fontSize: isMobile ? 9 : 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _formatRelativeTime(u.lastSeen, isOnline),
                                        style: TextStyle(
                                          color: isOnline ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                          fontSize: isMobile ? 9 : 11,
                                        ),
                                      ),
                                      if (isOnline && (u.role.toLowerCase() == 'kacab' || u.role.toLowerCase() == 'manager' || u.role.toLowerCase() == 'cashier')) ...[
                                        const SizedBox(height: 3),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0284C7).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.print_rounded, color: Color(0xFF38BDF8), size: 10),
                                              SizedBox(width: 3),
                                              Text(
                                                'PRINT STATION SIAGA',
                                                style: TextStyle(
                                                  color: Color(0xFF38BDF8),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 8.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
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
    );
  }

  // TAB 2: Role KACAB Menu Permissions Control
  Widget _buildKacabPermissionsTab(RolePermissionsProvider permissionsProvider, bool isMobile) {
    final perms = permissionsProvider.kacabPermissions;
    final activeCount = perms.values.where((v) => v == true).length;

    return Column(
      children: [
        // Top Banner Card (Compact)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amberAccent, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Hak Akses Menu Role KACAB',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        '$activeCount / ${_kacabFeatures.length} Menu Aktif',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              // Quick Bulk Toggle Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => permissionsProvider.setAllKacabPermissions(true),
                    icon: const Icon(Icons.select_all_rounded, size: 13),
                    label: const Text('Aktifkan Semua', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4ADE80),
                      side: const BorderSide(color: Color(0xFF4ADE80)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () => permissionsProvider.resetKacabToDefault(),
                    icon: const Icon(Icons.restart_alt_rounded, size: 13),
                    label: const Text('Reset Default', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Grid List of Features (Compact Height)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isMobile ? 600 : 450,
                mainAxisExtent: isMobile ? 56 : 60,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              itemCount: _kacabFeatures.length,
              itemBuilder: (context, index) {
                final item = _kacabFeatures[index];
                final String key = item['key'];
                final String title = item['title'];
                final IconData icon = item['icon'];
                final String desc = item['desc'];
                final bool isEnabled = perms[key] ?? false;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEnabled ? const Color(0xFF0F172A) : const Color(0xFF1E293B).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isEnabled ? const Color(0xFF38BDF8).withOpacity(0.5) : const Color(0xFF334155),
                      width: isEnabled ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isEnabled ? const Color(0xFF38BDF8).withOpacity(0.15) : const Color(0xFF334155).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          icon,
                          color: isEnabled ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: isEnabled ? Colors.white : const Color(0xFF94A3B8),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                  decoration: BoxDecoration(
                                    color: isEnabled ? const Color(0xFF4ADE80).withOpacity(0.2) : const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    isEnabled ? 'ON' : 'OFF',
                                    style: TextStyle(
                                      color: isEnabled ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: isEnabled,
                          activeColor: const Color(0xFF38BDF8),
                          activeTrackColor: const Color(0xFF0284C7).withOpacity(0.4),
                          inactiveThumbColor: const Color(0xFF64748B),
                          inactiveTrackColor: const Color(0xFF0F172A),
                          onChanged: (val) {
                            permissionsProvider.updateKacabPermission(key, val);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String subtext,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: isMobile ? 15 : 17),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 10 : 11, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(value, style: TextStyle(color: color, fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                  subtext,
                  style: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 8.5 : 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3: Real-Time Invoice Print & Date Selection Audit Logs
  Widget _buildInvoicePrintLogsTab(bool isMobile) {
    return StreamBuilder<List<InvoicePrintLog>>(
      stream: _firebaseService.streamInvoicePrintLogs(limit: 200),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Gagal memuat log: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allLogs = snapshot.data ?? [];
        final dateModifiedLogs = allLogs.where((l) => l.isDateModified).toList();
        final nonDevLogs = allLogs.where((l) => !l.isDeveloper).toList();

        // Apply search and filter
        final filteredLogs = allLogs.where((l) {
          if (_logRoleFilter == 'NON_DEV' && l.isDeveloper) return false;
          if (_logRoleFilter == 'DEV' && !l.isDeveloper) return false;
          if (_logRoleFilter == 'KACAB' && l.userRole.toLowerCase() != 'kacab' && l.userRole.toLowerCase() != 'manager') return false;
          if (_logRoleFilter == 'CASHIER' && l.userRole.toLowerCase() != 'cashier' && l.userRole.toLowerCase() != 'kasir') return false;

          if (_logOptionFilter == 'TANGGAL_BARU' && !l.isDateModified) return false;
          if (_logOptionFilter == 'TANGGAL_AWAL' && l.isDateModified) return false;

          if (_logSearchQuery.isNotEmpty) {
            final q = _logSearchQuery.toLowerCase();
            final matchInv = l.invoiceNo.toString().toLowerCase().contains(q);
            final matchCust = l.customerName.toLowerCase().contains(q);
            final matchUser = l.userName.toLowerCase().contains(q) || l.userUsername.toLowerCase().contains(q);
            final matchRole = l.userRole.toLowerCase().contains(q);
            if (!matchInv && !matchCust && !matchUser && !matchRole) return false;
          }

          return true;
        }).toList();

        return Column(
          children: [
            // Compact Header: Stats Badges & Search/Filter Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                children: [
                  // Row 1: Stat Pills + Total Log Count
                  Row(
                    children: [
                      // Stat 1: Total
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.print_rounded, size: 12, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 4),
                            Text('Total: ${allLogs.length}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Stat 2: Tanggal Baru
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_calendar_rounded, size: 12, color: Colors.amberAccent),
                            const SizedBox(width: 4),
                            Text('Tanggal Diubah: ${dateModifiedLogs.length}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Stat 3: Non-Dev
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.badge_rounded, size: 12, color: Color(0xFF4ADE80)),
                            const SizedBox(width: 4),
                            Text('Non-Dev: ${nonDevLogs.length}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Log Count
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          '${filteredLogs.length} dari ${allLogs.length} Log',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Row 2: Search Box & Dropdown Filters
                  Row(
                    children: [
                      // Search Box
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 30,
                          child: TextField(
                            style: const TextStyle(color: Colors.white, fontSize: 11.5),
                            decoration: InputDecoration(
                              hintText: 'Cari No. Invoice, Customer, User...',
                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 15),
                              suffixIcon: _logSearchQuery.isNotEmpty
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.clear, color: Color(0xFF94A3B8), size: 13),
                                      onPressed: () => setState(() => _logSearchQuery = ''),
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF334155)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            onChanged: (val) => setState(() => _logSearchQuery = val.trim()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Role Filter Dropdown
                      Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _logRoleFilter,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 15),
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('Semua Role')),
                              DropdownMenuItem(value: 'NON_DEV', child: Text('Non-Dev (Kacab/Kasir)')),
                              DropdownMenuItem(value: 'KACAB', child: Text('Kacab / Manager')),
                              DropdownMenuItem(value: 'CASHIER', child: Text('Kasir')),
                              DropdownMenuItem(value: 'DEV', child: Text('Developer')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _logRoleFilter = val);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Option Filter Dropdown
                      Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _logOptionFilter,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 15),
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('📅 Semua Tanggal')),
                              DropdownMenuItem(value: 'TANGGAL_BARU', child: Text('⚠️ Tanggal Baru')),
                              DropdownMenuItem(value: 'TANGGAL_AWAL', child: Text('✓ Tanggal Awal')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _logOptionFilter = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Log List Container
            Expanded(
              child: filteredLogs.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 42, color: Colors.white.withOpacity(0.15)),
                            const SizedBox(height: 10),
                            const Text(
                              'Tidak ada aktivitas log cetak invoice.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Coba ubah kata kunci pencarian atau filter role.',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Table Header Row (Sticky)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(8),
                              topRight: Radius.circular(8),
                            ),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              _buildTableHeader('Waktu', flex: 2),
                              _buildTableHeader('Operator', flex: 3),
                              _buildTableHeader('Aksi', flex: 2),
                              _buildTableHeader('Invoice', flex: 2),
                              _buildTableHeader('Customer', flex: 3),
                              _buildTableHeader('Status Tanggal', flex: 3),
                              _buildTableHeader('Total', flex: 2, align: TextAlign.right),
                              const SizedBox(width: 28), // space for delete button
                            ],
                          ),
                        ),
                        // Table Data Rows (Scrollable)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(8),
                                bottomRight: Radius.circular(8),
                              ),
                              child: ListView.builder(
                                itemCount: filteredLogs.length,
                                itemBuilder: (context, index) {
                                  final log = filteredLogs[index];
                                  final roleColor = _getRoleColor(log.userRole);
                                  final currencyFormatter = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
                                  final isNewDate = log.isDateModified;
                                  final isEven = index % 2 == 0;

                                  // Determine action type properties (PRINT / DOWNLOAD / REMOTE_PRINT)
                                  String actionLabel;
                                  IconData actionIcon;
                                  Color actionColor;
                                  if (log.actionType == 'PRINT') {
                                    actionLabel = 'CETAK';
                                    actionIcon = Icons.print_rounded;
                                    actionColor = const Color(0xFF38BDF8);
                                  } else if (log.actionType == 'REMOTE_PRINT') {
                                    actionLabel = 'REMOTE';
                                    actionIcon = Icons.cell_tower_rounded;
                                    actionColor = const Color(0xFFA78BFA); // violet
                                  } else {
                                    actionLabel = 'DOWNLOAD';
                                    actionIcon = Icons.download_rounded;
                                    actionColor = const Color(0xFF34D399);
                                  }

                                  // Date status
                                  final String dateStatusText = isNewDate
                                      ? 'Diubah → ${DateFormat('dd-MM-yyyy').format(log.printedDeliveryDate)}'
                                      : 'Sesuai Nota';
                                  final String dateTooltip = isNewDate
                                      ? 'Tgl Kirim Dicetak: ${DateFormat('dd-MM-yyyy').format(log.printedDeliveryDate)}\nTgl Awal Nota: ${DateFormat('dd-MM-yyyy').format(log.originalDeliveryDate ?? log.originalDate)}'
                                      : 'Tgl Kirim Dicetak: ${DateFormat('dd-MM-yyyy').format(log.printedDeliveryDate)} (Sesuai tanggal awal nota)';

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: isNewDate
                                          ? Colors.amber.withOpacity(0.04)
                                          : isEven
                                              ? const Color(0xFF1E293B)
                                              : const Color(0xFF172033),
                                      border: Border(
                                        left: BorderSide(
                                          color: isNewDate ? Colors.amberAccent : Colors.transparent,
                                          width: 3,
                                        ),
                                        bottom: BorderSide(
                                          color: const Color(0xFF334155).withOpacity(0.5),
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    child: Row(
                                      children: [
                                        // Column: Waktu
                                        Expanded(
                                          flex: 2,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFF64748B)),
                                              const SizedBox(width: 3),
                                              Flexible(
                                                child: Text(
                                                  _formatDateTime(log.timestamp),
                                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Column: Operator (Avatar + Name + Role Badge)
                                        Expanded(
                                          flex: 3,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 10,
                                                backgroundColor: roleColor.withOpacity(0.2),
                                                child: Text(
                                                  log.userName.isNotEmpty ? log.userName[0].toUpperCase() : 'U',
                                                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 9),
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Flexible(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      log.userName,
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Container(
                                                      margin: const EdgeInsets.only(top: 1),
                                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                      decoration: BoxDecoration(
                                                        color: roleColor.withOpacity(0.12),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text(
                                                        _getRoleLabel(log.userRole),
                                                        style: TextStyle(color: roleColor, fontSize: 7.5, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Column: Aksi (Action Badge)
                                        Expanded(
                                          flex: 2,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: actionColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: actionColor.withOpacity(0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(actionIcon, size: 11, color: actionColor),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    actionLabel,
                                                    style: TextStyle(color: actionColor, fontSize: 9, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Column: Invoice
                                        Expanded(
                                          flex: 2,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              '#${log.invoiceNo}',
                                              style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5),
                                            ),
                                          ),
                                        ),

                                        // Column: Customer
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            log.customerName,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),

                                        // Column: Status Tanggal (simplified + tooltip)
                                        Expanded(
                                          flex: 3,
                                          child: Tooltip(
                                            message: dateTooltip,
                                            textStyle: const TextStyle(color: Colors.white, fontSize: 11),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF475569)),
                                            ),
                                            preferBelow: true,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isNewDate ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                                                  size: 13,
                                                  color: isNewDate ? Colors.amberAccent : const Color(0xFF4ADE80),
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    dateStatusText,
                                                    style: TextStyle(
                                                      color: isNewDate ? Colors.amberAccent : const Color(0xFF4ADE80),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 10.5,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        // Column: Total (right-aligned)
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            log.grandTotal > 0 ? currencyFormatter.format(log.grandTotal) : '-',
                                            style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11),
                                            textAlign: TextAlign.right,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),

                                        // Column: Delete Button
                                        SizedBox(
                                          width: 28,
                                          child: Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: const Color(0xFF64748B).withOpacity(0.6),
                                                  size: 14,
                                                ),
                                                tooltip: 'Hapus Log Ini',
                                                splashRadius: 12,
                                                onPressed: () {
                                                  _firebaseService.deleteInvoicePrintLog(log.id);
                                                },
                                              ),
                                            ),
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
                    ),
            ),
          ],
        );
      },
    );
  }

  // TAB 4: Real-Time Remote Print Console (WFH -> Office Print Station)
  Widget _buildRemotePrintConsoleTab(AuthProvider authProvider, bool isMobile) {
    return StreamBuilder<List<RemotePrintCommand>>(
      stream: _firebaseService.streamRecentPrintCommands(limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Gagal memuat perintah remote print: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final allCommands = snapshot.data ?? [];
        final pendingCmds = allCommands.where((c) => c.isPending).toList();
        final processingCmds = allCommands.where((c) => c.isProcessing).toList();
        final completedCmds = allCommands.where((c) => c.isCompleted).toList();
        final failedCmds = allCommands.where((c) => c.isFailed).toList();

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: isMobile ? 32 : 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Office PC & Printer Live Status Banner
              StreamBuilder<List<UserProfile>>(
                stream: authProvider.getUsersStream(),
                builder: (context, userSnap) {
                  final users = userSnap.data ?? [];
                  final kacabUser = users.firstWhere(
                    (u) => u.role.toLowerCase() == 'kacab' || u.isKacab,
                    orElse: () => UserProfile(uid: '', name: 'Joko Setiawan', username: 'kacabjateng', role: 'kacab'),
                  );

                  final isKacabOnline = kacabUser.isActuallyOnline;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isKacabOnline ? const Color(0xFF064E3B).withOpacity(0.35) : const Color(0xFF7F1D1D).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isKacabOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: (isKacabOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isKacabOnline ? Icons.print_rounded : Icons.print_disabled_rounded,
                            color: isKacabOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                            size: isMobile ? 15 : 17,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: isKacabOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      isKacabOnline
                                          ? 'KOMPUTER & PRINTER KANTOR ONLINE (SIAP CETAK INSTAN)'
                                          : 'KOMPUTER KANTOR OFFLINE (PC BELUM DINYALAKAN)',
                                      style: TextStyle(
                                        color: isKacabOnline ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                                        fontWeight: FontWeight.bold,
                                        fontSize: isMobile ? 11 : 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                isKacabOnline
                                    ? 'Aplikasi kantor aktif (${kacabUser.name}). Perintah cetak dari WFH langsung keluar di printer EPSON.'
                                    : 'Aplikasi kasir sedang tutup / PC belum hidup. Perintah baru disimpan di antrean PENDING.',
                                style: TextStyle(
                                  color: isKacabOnline ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                                  fontSize: isMobile ? 10 : 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Top Summary Cards
              isMobile
                  ? Column(
                      children: [
                        _buildStatCard(
                          title: 'Total Perintah Remote',
                          value: '${allCommands.length}',
                          icon: Icons.podcasts_rounded,
                          color: const Color(0xFF38BDF8),
                          subtext: 'Seluruh antrean cetak dari WFH',
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 6),
                        _buildStatCard(
                          title: 'Menunggu Kantor (Pending)',
                          value: '${pendingCmds.length + processingCmds.length}',
                          icon: Icons.hourglass_top_rounded,
                          color: Colors.amberAccent,
                          subtext: 'Siaga diproses printer kantor',
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 6),
                        _buildStatCard(
                          title: 'Berhasil Tercetak',
                          value: '${completedCmds.length}',
                          icon: Icons.check_circle_rounded,
                          color: const Color(0xFF4ADE80),
                          subtext: 'Keluar di printer fisik kantor',
                          isMobile: isMobile,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            title: 'Total Perintah Remote',
                            value: '${allCommands.length}',
                            icon: Icons.podcasts_rounded,
                            color: const Color(0xFF38BDF8),
                            subtext: 'Seluruh antrean cetak dari WFH',
                            isMobile: isMobile,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Menunggu Kantor (Pending)',
                            value: '${pendingCmds.length + processingCmds.length}',
                            icon: Icons.hourglass_top_rounded,
                            color: Colors.amberAccent,
                            subtext: 'Siaga diproses printer kantor',
                            isMobile: isMobile,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatCard(
                            title: 'Berhasil Tercetak',
                            value: '${completedCmds.length}',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF4ADE80),
                            subtext: 'Keluar di printer fisik kantor',
                            isMobile: isMobile,
                          ),
                        ),
                        if (failedCmds.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              title: 'Gagal / Error',
                              value: '${failedCmds.length}',
                              icon: Icons.cancel_rounded,
                              color: Colors.redAccent,
                              subtext: 'Perlu dicek ulang',
                              isMobile: isMobile,
                            ),
                          ),
                        ],
                      ],
                    ),
              const SizedBox(height: 6),

              // Real-Time WebRTC Live Screen Viewer (When Kacab is sharing screen)
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: WebRtcScreenService().streamSession(sessionId: 'kacab_live'),
                builder: (context, screenSnap) {
                  final screenData = screenSnap.data?.data();
                  final isScreenActive = screenData != null && screenData['status'] == 'active';

                  if (!isScreenActive) return const SizedBox.shrink();

                  final broadcasterName = screenData['broadcasterName'] ?? 'Kacab Kantor';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: isMobile ? 220 : 360,
                    child: LiveScreenViewer(
                      sessionId: 'kacab_live',
                      stationName: broadcasterName,
                    ),
                  );
                },
              ),

              // Header info bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.podcasts_rounded, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Antrean Cetak Jarak Jauh (Remote Print Queue)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                      ),
                      child: Text(
                        '${allCommands.length} Perintah',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Commands List
              allCommands.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.print_disabled_rounded, size: 42, color: Colors.white.withOpacity(0.15)),
                            const SizedBox(height: 10),
                            const Text(
                              'Belum ada perintah cetak remote.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Gunakan tombol "📡 Cetak ke Kantor" di menu Histori Transaksi untuk mengirim cetakan.',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: allCommands.length,
                      itemBuilder: (context, index) {
                        final cmd = allCommands[index];
                        final currencyFormatter = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

                        Color statusColor;
                        String statusLabel;
                        IconData statusIcon;

                        if (cmd.isPending) {
                          statusColor = Colors.amberAccent;
                          statusLabel = 'PENDING';
                          statusIcon = Icons.hourglass_top_rounded;
                        } else if (cmd.isProcessing) {
                          statusColor = const Color(0xFF38BDF8);
                          statusLabel = 'DIPROSES';
                          statusIcon = Icons.sync_rounded;
                        } else if (cmd.isCompleted) {
                          statusColor = const Color(0xFF4ADE80);
                          statusLabel = 'TERCETAK';
                          statusIcon = Icons.check_circle_rounded;
                        } else {
                          statusColor = Colors.redAccent;
                          statusLabel = 'GAGAL';
                          statusIcon = Icons.error_outline_rounded;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withOpacity(0.4),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Row 1: Status badge, invoice, customer, total, time, actions
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: statusColor.withOpacity(0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(statusIcon, size: 10, color: statusColor),
                                            const SizedBox(width: 3),
                                            Text(
                                              statusLabel,
                                              style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),

                                      // Invoice Number
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0284C7).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                        ),
                                        child: Text(
                                          '#${cmd.invoiceNo}',
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 6),

                                      // Customer Name
                                      Expanded(
                                        child: Text(
                                          cmd.customerName,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),

                                      // Grand Total
                                      if (cmd.grandTotal > 0) ...[
                                        Text(
                                          currencyFormatter.format(cmd.grandTotal),
                                          style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                        const SizedBox(width: 8),
                                      ],

                                      // Timestamp
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFF64748B)),
                                          const SizedBox(width: 3),
                                          Text(
                                            _formatDateTime(cmd.createdAt),
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 4),

                                      // Re-send / Retry button
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.replay_rounded, color: Color(0xFF38BDF8), size: 15),
                                          tooltip: 'Kirim Ulang ke Komputer Kantor',
                                          splashRadius: 12,
                                          onPressed: () async {
                                            await _firebaseService.updatePrintCommandStatus(cmd.id, 'PENDING');
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Perintah cetak #${cmd.invoiceNo} dikirim ulang ke kantor!'),
                                                  backgroundColor: const Color(0xFF0284C7),
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),

                                      // Delete / Cancel Button
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: cmd.isPending
                                            ? IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 15),
                                                tooltip: 'Batalkan Cetakan Kantor',
                                                splashRadius: 12,
                                                onPressed: () {
                                                  _showCancelPrintDialog(context, cmd);
                                                },
                                              )
                                            : IconButton(
                                                padding: EdgeInsets.zero,
                                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF64748B), size: 15),
                                                tooltip: 'Hapus dari Riwayat',
                                                splashRadius: 12,
                                                onPressed: () {
                                                  _showDeletePrintLogDialog(context, cmd);
                                                },
                                              ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),

                                  // Row 2: Delivery Date & Station confirmation
                                  Row(
                                    children: [
                                      const Icon(Icons.event_available_rounded, size: 12, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tgl Kirim Dicetak: ${DateFormat('dd-MM-yyyy').format(cmd.printedDeliveryDate)}',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                      if (cmd.printerStationName != null) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.print_rounded, size: 12, color: Color(0xFF4ADE80)),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            'Station: ${cmd.printerStationName}${cmd.processedAt != null ? ' (${_formatDateTime(cmd.processedAt)})' : ''}',
                                            style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 10.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                      if (cmd.errorMessage != null && cmd.errorMessage!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '⚠️ Error: ${cmd.errorMessage}',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 10.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCancelPrintDialog(BuildContext context, RemotePrintCommand cmd) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final currencyFormatter = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Batalkan Cetak #${cmd.invoiceNo}?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Konfirmasi pembatalan antrean cetak kantor',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Body Info
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Pelanggan:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                                Flexible(
                                  child: Text(
                                    cmd.customerName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (cmd.grandTotal > 0) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Total Tagihan:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                                  Text(
                                    currencyFormatter.format(cmd.grandTotal),
                                    style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Status Antrean:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amberAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'MENUNGGU KANTOR (PENDING)',
                                    style: TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Warning Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.shield_outlined, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Printer fisik di kantor TIDAK AKAN mencetak nota ini jika dibatalkan sekarang. Dokumen akan langsung dihapus dari antrean.',
                                style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Footer Actions
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF475569)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Jangan Batalkan', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                          label: const Text('Ya, Batalkan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => Navigator.pop(ctx, true),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _firebaseService.deletePrintCommand(cmd.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('✅ Perintah cetak #${cmd.invoiceNo} berhasil dibatalkan. Printer kantor aman!'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showDeletePrintLogDialog(BuildContext context, RemotePrintCommand cmd) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20),
              const SizedBox(width: 8),
              Text('Hapus Riwayat #${cmd.invoiceNo}?', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Text(
            'Hapus catatan riwayat cetak invoice #${cmd.invoiceNo} (${cmd.customerName}) dari daftar ini?',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF334155),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _firebaseService.deletePrintCommand(cmd.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Riwayat #${cmd.invoiceNo} dihapus dari daftar.'),
            backgroundColor: const Color(0xFF334155),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
