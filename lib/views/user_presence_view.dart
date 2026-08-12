import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/role_permissions_provider.dart';
import '../models/user_profile.dart';
import '../models/invoice_print_log.dart';
import '../services/firebase_service.dart';

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
      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.developer_board_rounded, color: const Color(0xFF38BDF8), size: isMobile ? 22 : 28),
                      const SizedBox(width: 8),
                      Text(
                        'Developer Control & Monitor',
                        style: TextStyle(color: Colors.white, fontSize: isMobile ? 18 : 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Monitoring Aktivitas User Real-Time & Pengaturan Akses Menu Role KACAB',
                    style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 11 : 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'DEVELOPER MODE ACTIVE',
                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 20),

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
                const SizedBox(width: 8),
                _buildTabButton(
                  index: 1,
                  icon: Icons.admin_panel_settings_rounded,
                  label: 'Hak Akses Role KACAB',
                  isMobile: isMobile,
                ),
                const SizedBox(width: 8),
                _buildTabButton(
                  index: 2,
                  icon: Icons.receipt_long_rounded,
                  label: 'Log Cetak Invoice',
                  isMobile: isMobile,
                ),
              ],
            ),
          ),
          SizedBox(height: isMobile ? 12 : 20),

          // Tab Contents
          Expanded(
            child: _selectedTab == 0
                ? _buildUserPresenceTab(authProvider, currentUser, isMobile)
                : _selectedTab == 1
                    ? _buildKacabPermissionsTab(rolePermissionsProvider, isMobile)
                    : _buildInvoicePrintLogsTab(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({required int index, required IconData icon, required String label, required bool isMobile}) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: isMobile ? 8 : 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isMobile ? 15 : 18,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: isMobile ? 12 : 14,
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
                      const SizedBox(height: 8),
                      _buildStatCard(
                        title: 'User Offline',
                        value: '${offlineUsers.length}',
                        icon: Icons.power_settings_new_rounded,
                        color: const Color(0xFF94A3B8),
                        subtext: 'Tutup app / tidak aktif',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 8),
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
                      const SizedBox(width: 16),
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
                      const SizedBox(width: 16),
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
            SizedBox(height: isMobile ? 10 : 20),

            // Controls & Filter Bar
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white, fontSize: isMobile ? 12 : 14),
                      decoration: InputDecoration(
                        hintText: 'Cari berdasarkan nama, username, atau role...',
                        hintStyle: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 12 : 14),
                        prefixIcon: Icon(Icons.search, color: const Color(0xFF38BDF8), size: isMobile ? 18 : 22),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 8 : 12),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 10 : 16),

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

                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: isMobile ? 10 : 12),
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
        // Top Banner Card
        Container(
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amberAccent, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hak Akses Role KACAB',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '$activeCount / ${_kacabFeatures.length} Menu Aktif',
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aktifkan (ON) atau matikan (OFF) fitur yang akan ditampilkan di sidebar navigasi akun KACAB / Manager secara real-time.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    // Quick Bulk Toggle Buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => permissionsProvider.setAllKacabPermissions(true),
                          icon: const Icon(Icons.select_all_rounded, size: 14),
                          label: const Text('Aktifkan Semua', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4ADE80),
                            side: const BorderSide(color: Color(0xFF4ADE80)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => permissionsProvider.resetKacabToDefault(),
                          icon: const Icon(Icons.restart_alt_rounded, size: 14),
                          label: const Text('Reset Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.amberAccent, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Pengaturan Menu Sidebar untuk Role KACAB',
                                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$activeCount / ${_kacabFeatures.length} Menu Aktif',
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Aktifkan (ON) atau matikan (OFF) fitur yang akan ditampilkan di sidebar navigasi akun KACAB / Manager secara real-time.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Quick Bulk Toggle Buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => permissionsProvider.setAllKacabPermissions(true),
                          icon: const Icon(Icons.select_all_rounded, size: 16),
                          label: const Text('Aktifkan Semua', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4ADE80),
                            side: const BorderSide(color: Color(0xFF4ADE80)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => permissionsProvider.resetKacabToDefault(),
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('Reset Default (Histori Saja)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        SizedBox(height: isMobile ? 10 : 16),

        // Grid List of Features
        Expanded(
          child: Container(
            padding: EdgeInsets.all(isMobile ? 8 : 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isMobile ? 600 : 500,
                mainAxisExtent: isMobile ? 100 : 110,
                crossAxisSpacing: isMobile ? 8 : 12,
                mainAxisSpacing: isMobile ? 8 : 12,
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
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 12),
                  decoration: BoxDecoration(
                    color: isEnabled ? const Color(0xFF0F172A) : const Color(0xFF1E293B).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isEnabled ? const Color(0xFF38BDF8).withOpacity(0.5) : const Color(0xFF334155),
                      width: isEnabled ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 8 : 10),
                        decoration: BoxDecoration(
                          color: isEnabled ? const Color(0xFF38BDF8).withOpacity(0.15) : const Color(0xFF334155).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          color: isEnabled ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                          size: isMobile ? 20 : 24,
                        ),
                      ),
                      SizedBox(width: isMobile ? 10 : 14),
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
                                      fontSize: isMobile ? 13 : 15,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isEnabled ? const Color(0xFF4ADE80).withOpacity(0.2) : const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isEnabled ? 'ON' : 'OFF',
                                    style: TextStyle(
                                      color: isEnabled ? const Color(0xFF4ADE80) : const Color(0xFF64748B),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontSize: isMobile ? 10 : 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: isEnabled,
                        activeColor: const Color(0xFF38BDF8),
                        activeTrackColor: const Color(0xFF0284C7).withOpacity(0.4),
                        inactiveThumbColor: const Color(0xFF64748B),
                        inactiveTrackColor: const Color(0xFF0F172A),
                        onChanged: (val) {
                          permissionsProvider.updateKacabPermission(key, val);
                        },
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
      padding: EdgeInsets.all(isMobile ? 10 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: isMobile ? 18 : 24),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: color, fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold)),
                Text(
                  subtext,
                  style: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 9 : 10),
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
            // Top Summary Cards
            isMobile
                ? Column(
                    children: [
                      _buildStatCard(
                        title: 'Total Aktivitas Cetak',
                        value: '${allLogs.length}',
                        icon: Icons.print_rounded,
                        color: const Color(0xFF38BDF8),
                        subtext: 'Log cetak & download invoice',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 8),
                      _buildStatCard(
                        title: 'Tanggal Kirim Baru (Diubah)',
                        value: '${dateModifiedLogs.length}',
                        icon: Icons.edit_calendar_rounded,
                        color: Colors.amberAccent,
                        subtext: 'Input tanggal kirim saat cetak',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 8),
                      _buildStatCard(
                        title: 'Dicetak Non-Developer',
                        value: '${nonDevLogs.length}',
                        icon: Icons.badge_rounded,
                        color: const Color(0xFF4ADE80),
                        subtext: 'Aktivitas KACAB & Kasir',
                        isMobile: isMobile,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: 'Total Aktivitas Cetak',
                          value: '${allLogs.length}',
                          icon: Icons.print_rounded,
                          color: const Color(0xFF38BDF8),
                          subtext: 'Log cetak & download invoice',
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Tanggal Kirim Baru (Diubah)',
                          value: '${dateModifiedLogs.length}',
                          icon: Icons.edit_calendar_rounded,
                          color: Colors.amberAccent,
                          subtext: 'Input tanggal kirim saat cetak',
                          isMobile: isMobile,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: 'Dicetak Non-Developer',
                          value: '${nonDevLogs.length}',
                          icon: Icons.badge_rounded,
                          color: const Color(0xFF4ADE80),
                          subtext: 'Aktivitas KACAB & Kasir',
                          isMobile: isMobile,
                        ),
                      ),
                    ],
                  ),
            SizedBox(height: isMobile ? 10 : 16),

            // Controls & Filter Bar
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Search Box
                  SizedBox(
                    width: isMobile ? double.infinity : 280,
                    child: TextField(
                      style: TextStyle(color: Colors.white, fontSize: isMobile ? 12 : 13),
                      decoration: InputDecoration(
                        hintText: 'Cari invoice, customer, user...',
                        hintStyle: TextStyle(color: const Color(0xFF64748B), fontSize: isMobile ? 12 : 13),
                        prefixIcon: Icon(Icons.search, color: const Color(0xFF38BDF8), size: isMobile ? 16 : 20),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: isMobile ? 6 : 10),
                      ),
                      onChanged: (val) => setState(() => _logSearchQuery = val.trim()),
                    ),
                  ),

                  // Role Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _logRoleFilter,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('Semua Role User')),
                          DropdownMenuItem(value: 'NON_DEV', child: Text('⚡ Khusus Non-Dev (Kacab / Kasir)')),
                          DropdownMenuItem(value: 'KACAB', child: Text('👔 Khusus Kacab / Kepala Sales')),
                          DropdownMenuItem(value: 'CASHIER', child: Text('🛒 Khusus Kasir')),
                          DropdownMenuItem(value: 'DEV', child: Text('💻 Khusus Developer')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _logRoleFilter = val);
                        },
                      ),
                    ),
                  ),

                  // Option Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _logOptionFilter,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('Semua Opsi Tanggal')),
                          DropdownMenuItem(value: 'TANGGAL_BARU', child: Text('⚠️ Tanggal Kirim Diubah Baru')),
                          DropdownMenuItem(value: 'TANGGAL_AWAL', child: Text('✓ Tanggal Awal Nota')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _logOptionFilter = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isMobile ? 10 : 16),

            // Log List
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 12),
                            const Text(
                              'Belum ada log cetak invoice tercatat.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ListView.separated(
                          itemCount: filteredLogs.length,
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (context, index) {
                            final log = filteredLogs[index];
                            final roleColor = _getRoleColor(log.userRole);
                            final currencyFormatter = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

                            return Container(
                              padding: EdgeInsets.all(isMobile ? 12 : 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Row 1: User & Action Badges + Timestamp
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // User Avatar Icon
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: roleColor.withOpacity(0.2),
                                        child: Text(
                                          log.userName.isNotEmpty ? log.userName[0].toUpperCase() : 'U',
                                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              log.userName,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            if (log.userUsername.isNotEmpty)
                                              Text(
                                                '(@${log.userUsername})',
                                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: roleColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: roleColor.withOpacity(0.4)),
                                              ),
                                              child: Text(
                                                _getRoleLabel(log.userRole),
                                                style: TextStyle(color: roleColor, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: log.actionType == 'PRINT'
                                                    ? const Color(0xFF0284C7).withOpacity(0.2)
                                                    : const Color(0xFF10B981).withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: log.actionType == 'PRINT'
                                                      ? const Color(0xFF38BDF8)
                                                      : const Color(0xFF34D399),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    log.actionType == 'PRINT' ? Icons.print_rounded : Icons.download_rounded,
                                                    size: 11,
                                                    color: log.actionType == 'PRINT' ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    log.actionType == 'PRINT' ? 'CETAK PDF' : 'DOWNLOAD PDF',
                                                    style: TextStyle(
                                                      color: log.actionType == 'PRINT' ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _formatDateTime(log.timestamp),
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Row 2: Invoice & Customer Info
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                        ),
                                        child: Text(
                                          'Invoice #${log.invoiceNo}',
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          log.customerName,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (log.grandTotal > 0)
                                        Text(
                                          currencyFormatter.format(log.grandTotal),
                                          style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Row 3: DATE SELECTION AUDIT HIGHLIGHT
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: log.isDateModified
                                          ? Colors.amber.withOpacity(0.08)
                                          : const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: log.isDateModified
                                            ? Colors.amber.withOpacity(0.5)
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          log.isDateModified ? Icons.edit_calendar_rounded : Icons.event_available_rounded,
                                          size: 18,
                                          color: log.isDateModified ? Colors.amberAccent : const Color(0xFF38BDF8),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    'Tanggal Kirim Dipilih / Dicetak: ',
                                                    style: TextStyle(
                                                      color: log.isDateModified ? Colors.amberAccent : const Color(0xFF94A3B8),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Text(
                                                    DateFormat('dd MMMM yyyy (dd-MM-yyyy)').format(log.printedDeliveryDate),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                log.isDateModified
                                                    ? '⚠️ Role User (${_getRoleLabel(log.userRole)}) menginput Tanggal Kirim Baru (Tanggal Awal Nota: ${DateFormat('dd-MM-yyyy').format(log.originalDeliveryDate ?? log.originalDate)})'
                                                    : '✓ User mencetak menggunakan Tanggal Awal Nota (${DateFormat('dd-MM-yyyy').format(log.originalDeliveryDate ?? log.originalDate)})',
                                                style: TextStyle(
                                                  color: log.isDateModified ? Colors.amber.shade200 : const Color(0xFF64748B),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
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
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
