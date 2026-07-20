import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/update_provider.dart';
import 'login_view.dart';
import 'transaction_entry_view.dart';
import 'product_list_view.dart';
import 'customer_list_view.dart';
import 'erp_matrix_view.dart';
import 'dashboard_view.dart';
import 'update_dialog.dart';
import 'transaction_history_view.dart';
import 'receivable_list_view.dart';
import 'ranking_kacab_view.dart';
import 'stock_input_view.dart';
import 'attendance_view.dart';

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  int _currentIndex = 0;
  String _appVersion = '1.6.9';

  @override
  void initState() {
    super.initState();
    _loadVersionAndCheckUpdate();
  }

  Future<void> _loadVersionAndCheckUpdate() async {
    // Load current app version
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted && packageInfo.version.isNotEmpty && packageInfo.version != '1.0.0') {
        setState(() {
          _appVersion = packageInfo.version;
        });
      } else if (mounted) {
        setState(() {
          _appVersion = '1.6.2';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = '1.6.2';
        });
      }
    }

    // Auto-check for updates after a short delay
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final updateProvider = Provider.of<UpdateProvider>(context, listen: false);
    await updateProvider.checkForUpdate();

    if (mounted && updateProvider.hasUpdate && updateProvider.updateInfo != null) {
      _showUpdateDialog(updateProvider.updateInfo!);
    }
  }

  void _showUpdateDialog(updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(
        info: updateInfo,
        currentVersion: _appVersion,
      ),
    );
  }

  // Sidebar sections configuration based on user roles
  List<Map<String, dynamic>> _getNavItems(String role) {
    final List<Map<String, dynamic>> items = [
      {
        'title': 'Transaksi Kasir',
        'icon': Icons.point_of_sale_rounded,
        'widget': const TransactionEntryView(),
      },
      {
        'title': 'Histori Transaksi',
        'icon': Icons.history_rounded,
        'widget': const TransactionHistoryView(),
      },
    ];

    // Master data screens (Admin/Developer only)
    if (role == 'developer') {
      items.addAll([
        {
          'title': 'Master Barang',
          'icon': Icons.shopping_bag_outlined,
          'widget': const ProductListView(),
        },
        {
          'title': 'Master Pelanggan',
          'icon': Icons.people_outline_rounded,
          'widget': const CustomerListView(),
        },
      ]);
    }

    // ERP and Dashboard views (everyone, but CRUD inside restricted)
    items.addAll([
      {
        'title': 'Input Stok',
        'icon': Icons.add_box_outlined,
        'widget': const StockInputView(),
      },
      {
        'title': 'Stok ERP & Opname',
        'icon': Icons.table_chart_outlined,
        'widget': const ErpMatrixView(),
      },
      {
        'title': 'Kartu Piutang Toko',
        'icon': Icons.account_balance_wallet_outlined,
        'widget': const ReceivableListView(),
      },
      {
        'title': 'Ranking Kacab',
        'icon': Icons.leaderboard_outlined,
        'widget': const RankingKacabView(),
      },
      {
        'title': 'Absensi Pegawai',
        'icon': Icons.assignment_ind_rounded,
        'widget': const AttendanceView(),
      },
      {
        'title': 'Analitik & Klasifikasi',
        'icon': Icons.bar_chart_rounded,
        'widget': const DashboardView(),
      },
    ]);

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);
    final user = authProvider.currentUser;

    // Redirect to login if user session is lost
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginView()),
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final navItems = _getNavItems(user.role);
    if (_currentIndex >= navItems.length) {
      _currentIndex = 0;
    }

    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate Dark Background
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          navItems[_currentIndex]['title'],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // Update check button with badge
          if (updateProvider.hasUpdate)
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: IconButton(
                icon: const Badge(
                  backgroundColor: Colors.redAccent,
                  smallSize: 10,
                  child: Icon(Icons.system_update_rounded, color: Color(0xFF38BDF8)),
                ),
                tooltip: 'Update Tersedia!',
                onPressed: () {
                  if (updateProvider.updateInfo != null) {
                    _showUpdateDialog(updateProvider.updateInfo!);
                  }
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: IconButton(
                icon: updateProvider.isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF64748B),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                tooltip: 'Cek Update',
                onPressed: updateProvider.isChecking
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await updateProvider.checkForUpdate();
                        if (mounted && updateProvider.hasUpdate && updateProvider.updateInfo != null) {
                          _showUpdateDialog(updateProvider.updateInfo!);
                        } else if (mounted && !updateProvider.hasUpdate) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('✅ Aplikasi sudah versi terbaru!'),
                              backgroundColor: const Color(0xFF1E293B),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
              ),
            ),

          // User profile chips and sign-out
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      user.role.toUpperCase(),
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  backgroundColor: const Color(0xFF334155),
                  child: Text(
                    user.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                  tooltip: 'Keluar',
                  onPressed: () async {
                    await authProvider.signOut();
                  },
                ),
              ],
            ),
          )
        ],
      ),
      drawer: isLargeScreen
          ? null
          : Drawer(
              backgroundColor: const Color(0xFF1E293B),
              child: _buildDrawerContent(navItems, updateProvider),
            ),
      body: Row(
        children: [
          // Navigation rail for large screens (tablets/desktops)
          if (isLargeScreen)
            Container(
              width: 250,
              color: const Color(0xFF1E293B),
              child: _buildDrawerContent(navItems, updateProvider),
            ),
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              child: navItems[_currentIndex]['widget'],
            ),
          ),
        ],
      ),
    );
  }

  // Sidebar Layout Content
  Widget _buildDrawerContent(List<Map<String, dynamic>> navItems, UpdateProvider updateProvider) {
    return Column(
      children: [
        // App banner logo
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.store_rounded, color: Color(0xFF38BDF8), size: 28),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lucifax PFS v1.8.2',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
                  ),
                  Text(
                    'FIVA SOLO • v$_appVersion',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              )
            ],
          ),
        ),
        const Divider(color: Color(0xFF334155), height: 1),
        const SizedBox(height: 16),
        // Menu list items
        Expanded(
          child: ListView.builder(
            itemCount: navItems.length,
            itemBuilder: (context, index) {
              final item = navItems[index];
              final isSelected = _currentIndex == index;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  selected: isSelected,
                  selectedTileColor: const Color(0xFF0284C7).withOpacity(0.2),
                  leading: Icon(
                    item['icon'],
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                  ),
                  title: Text(
                    item['title'],
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13.0,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _currentIndex = index;
                    });
                    if (Scaffold.of(context).isDrawerOpen) {
                      Navigator.pop(context); // Close drawer on mobile
                    }
                  },
                ),
              );
            },
          ),
        ),

        // Update notification banner in sidebar
        if (updateProvider.hasUpdate)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: InkWell(
              onTap: () {
                if (updateProvider.updateInfo != null) {
                  _showUpdateDialog(updateProvider.updateInfo!);
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Update Tersedia!',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            'v${updateProvider.updateInfo?.latestVersion ?? "?"}',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                  ],
                ),
              ),
            ),
          ),

        // Footer signature
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'PT Putra Fiva Sejahtera © 2026 • v$_appVersion',
            style: const TextStyle(color: Color(0xFF475569), fontSize: 10),
          ),
        ),
      ],
    );
  }
}
