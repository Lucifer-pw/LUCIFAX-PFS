import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/update_provider.dart';
import '../providers/role_permissions_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_provider.dart';
import '../models/remote_print_command.dart';
import '../models/transaction.dart' as model_tr;
import '../models/customer.dart';
import '../services/firebase_service.dart';
import '../services/print_service.dart';
import '../services/webrtc_service.dart';
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
import 'user_presence_view.dart';
import 'kmeans_analysis_view.dart';
import 'operational_invoice_view.dart';
import 'monthly_operational_expenses_view.dart';

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  int _currentIndex = 0;
  String _appVersion = '3.3.13';
  String _menuSearchQuery = '';
  final TextEditingController _menuSearchController = TextEditingController();
  StreamSubscription<List<RemotePrintCommand>>? _printCommandSubscription;
  final Set<String> _processedCommandIds = {};
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _loadVersionAndCheckUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupRemotePrintListener();
    });
  }

  @override
  void dispose() {
    _printCommandSubscription?.cancel();
    _menuSearchController.dispose();
    super.dispose();
  }

  void _setupRemotePrintListener() {
    _printCommandSubscription?.cancel();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return;

    // Listen for remote print commands targeted for this user or their role
    _printCommandSubscription = _firebaseService
        .streamPendingPrintCommands(targetUserId: user.uid, role: user.role)
        .listen((commands) async {
      for (final cmd in commands) {
        if (_processedCommandIds.contains(cmd.id)) continue;
        _processedCommandIds.add(cmd.id);

        await _processIncomingRemotePrint(cmd, user.name.isNotEmpty ? user.name : user.username);
      }
    }, onError: (err) {
      debugPrint("Error in remote print command listener: $err");
    });
  }

  Future<void> _processIncomingRemotePrint(RemotePrintCommand cmd, String stationName) async {
    try {
      // 1. Mark command as processing
      await _firebaseService.updatePrintCommandStatus(
        cmd.id,
        'PROCESSING',
        printerStationName: stationName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.print_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🖨️ Perintah Cetak dari ${cmd.requestedByUserName}: Invoice #${cmd.invoiceNo} (${cmd.customerName})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0284C7),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // 2. Find transaction model
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      model_tr.Transaction? tr;
      try {
        tr = trProvider.transactions.firstWhere((t) => t.invoiceNo.toString() == cmd.invoiceNo.toString());
      } catch (_) {}

      if (tr == null) {
        // Fallback: query from Firestore directly if not found in memory
        final snap = await FirebaseFirestore.instance
            .collection('transactions')
            .where('invoiceNo', isEqualTo: cmd.invoiceNo)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          tr = model_tr.Transaction.fromMap(snap.docs.first.data(), snap.docs.first.id);
        }
      }

      if (tr == null) {
        await _firebaseService.updatePrintCommandStatus(
          cmd.id,
          'FAILED',
          errorMessage: 'Data transaksi Invoice #${cmd.invoiceNo} tidak ditemukan di database.',
        );
        return;
      }

      // Build model to print with the specified delivery date
      final masterCustomers = Provider.of<CustomerProvider>(context, listen: false).customers;
      Customer? c;
      try {
        c = masterCustomers.firstWhere((cust) => cust.id == tr!.customerId);
      } catch (_) {}

      final toPrint = model_tr.Transaction(
        invoiceNo: tr.invoiceNo,
        customerId: tr.customerId,
        customerName: tr.customerName,
        aliasName: (c != null && c.aliasName.isNotEmpty) ? c.aliasName : tr.customerName,
        date: tr.date,
        deliveryDate: cmd.printedDeliveryDate,
        city: (c != null && c.city.isNotEmpty) ? c.city : tr.city,
        province: (c != null && c.province.isNotEmpty) ? c.province : tr.province,
        country: (c != null && c.country.isNotEmpty) ? c.country : tr.country,
        items: tr.items,
        grandTotal: tr.grandTotal,
        note: tr.note,
        status: tr.status,
        statusTransfer: tr.statusTransfer,
        transferDate: tr.transferDate,
        erpSyncDate: tr.erpSyncDate,
        createdBy: tr.createdBy,
        createdAt: tr.createdAt,
      );

      // 3. Trigger printing to physical printer via PrintService
      await PrintService.printInvoice(toPrint);

      // 4. Mark command as completed
      await _firebaseService.updatePrintCommandStatus(
        cmd.id,
        'COMPLETED',
        printerStationName: stationName,
      );

      // 5. Log print action to Firestore audit log
      await _firebaseService.logInvoicePrint(
        invoiceNo: tr.invoiceNo,
        customerName: tr.customerName,
        originalDate: tr.date,
        originalDeliveryDate: tr.deliveryDate,
        printedDeliveryDate: cmd.printedDeliveryDate,
        optionType: cmd.optionType,
        actionType: 'REMOTE_PRINT',
        userId: cmd.requestedByUserId,
        userName: '${cmd.requestedByUserName} (via $stationName)',
        userUsername: 'remote_station',
        userRole: 'developer',
        isDeveloper: true,
        grandTotal: tr.grandTotal,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Invoice #${tr.invoiceNo} berhasil diproses ke printer kantor!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error executing remote print on station: $e');
      await _firebaseService.updatePrintCommandStatus(
        cmd.id,
        'FAILED',
        errorMessage: e.toString(),
      );
    }
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
          _appVersion = '3.3.13';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = '3.3.13';
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

  // Sidebar sections configuration based on user roles and developer permissions
  List<Map<String, dynamic>> _getNavItems(String role, RolePermissionsProvider permissionsProvider) {
    final kacabPerms = permissionsProvider.kacabPermissions;

    // Kacab / Manager Role: Dynamically configured by Developer Settings
    if (role == 'kacab' || role == 'manager') {
      final List<Map<String, dynamic>> items = [];

      if (kacabPerms['transaction_entry'] == true) {
        items.add({
          'title': 'Transaksi Kasir',
          'icon': Icons.point_of_sale_rounded,
          'widget': const TransactionEntryView(),
        });
      }

      if (kacabPerms['transaction_history'] == true) {
        items.add({
          'title': 'Histori Transaksi',
          'icon': Icons.history_rounded,
          'widget': const TransactionHistoryView(),
        });
      }

      if (kacabPerms['master_product'] == true) {
        items.add({
          'title': 'Master Barang',
          'icon': Icons.shopping_bag_outlined,
          'widget': const ProductListView(),
        });
      }

      if (kacabPerms['master_customer'] == true) {
        items.add({
          'title': 'Master Pelanggan',
          'icon': Icons.people_outline_rounded,
          'widget': const CustomerListView(),
        });
      }

      if (kacabPerms['stock_input'] == true) {
        items.add({
          'title': 'Input Stok',
          'icon': Icons.add_box_outlined,
          'widget': const StockInputView(),
        });
      }

      if (kacabPerms['erp_matrix'] == true) {
        items.add({
          'title': 'Stok Opname & ERP',
          'icon': Icons.table_chart_outlined,
          'widget': const ErpMatrixView(),
        });
      }

      if (kacabPerms['receivable_list'] == true) {
        items.add({
          'title': 'Kartu Piutang Toko',
          'icon': Icons.account_balance_wallet_outlined,
          'widget': const ReceivableListView(),
        });
      }

      if (kacabPerms['ranking_kacab'] == true) {
        items.add({
          'title': 'Ranking Kacab',
          'icon': Icons.leaderboard_outlined,
          'widget': const RankingKacabView(),
        });
      }

      if (kacabPerms['attendance'] == true) {
        items.add({
          'title': 'Absensi Pegawai',
          'icon': Icons.assignment_ind_rounded,
          'widget': const AttendanceView(),
        });
      }

      if (kacabPerms['dashboard'] == true) {
        items.add({
          'title': 'Analitik & Klasifikasi',
          'icon': Icons.bar_chart_rounded,
          'widget': const DashboardView(),
        });
      }

      if (kacabPerms['kmeans_analysis'] == true) {
        items.add({
          'title': 'Clustering K-Means (Skripsi)',
          'icon': Icons.hub_rounded,
          'widget': const KMeansAnalysisView(),
        });
      }

      if (kacabPerms['monthly_operational_expenses'] == true) {
        items.add({
          'title': 'Biaya Operasional Bulanan',
          'icon': Icons.request_quote_rounded,
          'widget': const MonthlyOperationalExpensesView(),
        });
      }

      // Safety fallback: If developer turns off all menus, show Histori Transaksi as default
      if (items.isEmpty) {
        items.add({
          'title': 'Histori Transaksi',
          'icon': Icons.history_rounded,
          'widget': const TransactionHistoryView(),
        });
      }

      return items;
    }

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
    if (role == 'developer' || role == 'admin') {
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

    // ERP and Dashboard views
    items.addAll([
      {
        'title': 'Input Stok',
        'icon': Icons.add_box_outlined,
        'widget': const StockInputView(),
      },
      {
        'title': 'Stok Opname & ERP',
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
      {
        'title': 'Clustering K-Means (Skripsi)',
        'icon': Icons.hub_rounded,
        'widget': const KMeansAnalysisView(),
      },
      {
        'title': 'Biaya Operasional Bulanan',
        'icon': Icons.request_quote_rounded,
        'widget': const MonthlyOperationalExpensesView(),
      },
    ]);

    // Developer-Only Activity & Presence Monitor Screen
    if (role == 'developer') {
      items.add({
        'title': 'Developer Control & Monitor',
        'icon': Icons.sensors_rounded,
        'widget': const UserPresenceView(),
      });
      items.add({
        'title': 'Invoice Operasional Dev',
        'icon': Icons.receipt_long_rounded,
        'widget': const OperationalInvoiceView(),
      });
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final updateProvider = Provider.of<UpdateProvider>(context);
    final permissionsProvider = Provider.of<RolePermissionsProvider>(context);
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

    final navItems = _getNavItems(user.role, permissionsProvider);
    if (_currentIndex >= navItems.length) {
      _currentIndex = 0;
    }

    final isMobile = MediaQuery.of(context).size.width < 768;
    final isLargeScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate Dark Background
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Text(
          navItems[_currentIndex]['title'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 15 : 18,
          ),
        ),
        actions: [
          // Update check button with badge
          if (updateProvider.hasUpdate)
            Padding(
              padding: const EdgeInsets.only(right: 2.0),
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
              padding: const EdgeInsets.only(right: 2.0),
              child: IconButton(
                icon: updateProvider.isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF64748B),
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, color: Color(0xFF64748B), size: 20),
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

          // WebRTC Screen Share Button (For non-developer / Kacab to share screen with Developer)
          if (!user.isDeveloper)
            Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: WebRtcScreenService().streamSession(sessionId: 'kacab_live'),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final isActive = data != null && data['status'] == 'active' && data['broadcasterId'] == user.uid;

                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: isMobile ? 6 : 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    icon: Icon(
                      isActive ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                      size: isMobile ? 14 : 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      isActive
                          ? (isMobile ? 'STOP' : '🛑 Hentikan Siaran')
                          : (isMobile ? 'LAYAR' : '📺 Bagikan Layar'),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 10.5 : 12,
                      ),
                    ),
                    onPressed: () async {
                      final webrtc = WebRtcScreenService();
                      if (isActive) {
                        await webrtc.stopBroadcasting(sessionId: 'kacab_live');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Siaran layar dihentikan.'),
                              backgroundColor: Color(0xFF1E293B),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else {
                        final success = await webrtc.startBroadcasting(
                          userId: user.uid,
                          userName: user.name,
                          sessionId: 'kacab_live',
                          onStoppedByUser: () {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Siaran layar dihentikan dari browser.'),
                                  backgroundColor: Color(0xFF1E293B),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        );

                        if (context.mounted) {
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('📡 Siaran layar aktif! Developer sekarang dapat melihat layar Anda secara live.'),
                                backgroundColor: Color(0xFF059669),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Gagal memulai siaran layar atau dibatalkan.'),
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      }
                    },
                  );
                },
              ),
            ),

          // User profile chips and sign-out
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6.0 : 12.0),
            child: Row(
              children: [
                if (!isMobile) ...[
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
                  const SizedBox(width: 10),
                ],
                CircleAvatar(
                  radius: isMobile ? 14 : 18,
                  backgroundColor: const Color(0xFF334155),
                  child: Text(
                    user.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: const Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 12 : 14,
                    ),
                  ),
                ),
                SizedBox(width: isMobile ? 2 : 6),
                IconButton(
                  icon: Icon(Icons.logout_rounded, color: Colors.redAccent, size: isMobile ? 20 : 24),
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
              child: IndexedStack(
                index: _currentIndex,
                children: navItems.map<Widget>((item) => item['widget'] as Widget).toList(),
              ),
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
                    'Lucifax PFS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                  ),
                  Text(
                    'PT. Putra Fiva Sejahtera • v$_appVersion',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              )
            ],
          ),
        ),
        const Divider(color: Color(0xFF334155), height: 1),
        const SizedBox(height: 12),

        // Search Menu Input Box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: TextField(
            controller: _menuSearchController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Cari Menu...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
              suffixIcon: _menuSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 16),
                      onPressed: () {
                        _menuSearchController.clear();
                        setState(() {
                          _menuSearchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.0),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.0),
                borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.0),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _menuSearchQuery = val;
              });
            },
          ),
        ),
        const SizedBox(height: 8),

        // Filtered Menu list items
        Expanded(
          child: Builder(
            builder: (context) {
              final query = _menuSearchQuery.trim().toLowerCase();
              final filteredNavItems = <Map<String, dynamic>>[];
              for (int i = 0; i < navItems.length; i++) {
                final title = navItems[i]['title'].toString();
                if (query.isEmpty || title.toLowerCase().contains(query)) {
                  filteredNavItems.add({'originalIndex': i, 'item': navItems[i]});
                }
              }

              if (filteredNavItems.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Menu tidak ditemukan', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                  ),
                );
              }

              return ListView.builder(
                itemCount: filteredNavItems.length,
                itemBuilder: (context, index) {
                  final entry = filteredNavItems[index];
                  final originalIndex = entry['originalIndex'] as int;
                  final item = entry['item'] as Map<String, dynamic>;
                  final isSelected = _currentIndex == originalIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 3.0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                      selected: isSelected,
                      selectedTileColor: const Color(0xFF0284C7).withOpacity(0.2),
                      leading: Icon(
                        item['icon'],
                        color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                        size: 20,
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
                          _currentIndex = originalIndex;
                        });
                        if (Scaffold.of(context).isDrawerOpen) {
                          Navigator.pop(context); // Close drawer on mobile
                        }
                      },
                    ),
                  );
                },
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
