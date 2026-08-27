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
import 'billing_report_view.dart';

class ShellView extends StatefulWidget {
  const ShellView({super.key});

  @override
  State<ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<ShellView> {
  int _currentIndex = 0;
  String _appVersion = '3.3.145';
  String _menuSearchQuery = '';
  final TextEditingController _menuSearchController = TextEditingController();
  StreamSubscription<List<RemotePrintCommand>>? _printCommandSubscription;
  final Set<String> _processedCommandIds = {};
  final FirebaseService _firebaseService = FirebaseService();
  bool _hasShownSyncPrompt = false;

  @override
  void initState() {
    super.initState();
    _loadVersionAndCheckUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupRemotePrintListener();
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      if (user != null && !user.isDeveloper && !WebRtcScreenService().isBroadcasting) {
        FirebaseFirestore.instance.collection('webrtc_screen_sessions').doc('kacab_live').set({
          'status': 'ended',
          'endedAt': Timestamp.now(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          _checkAndShowSyncPrompt();
        }
      });
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

    // STRICT: Only PC Kantor with role 'kacab' (Joko Setiawan) is allowed to act as physical print station!
    // Developers, Admins, and other remote users must NEVER listen to or execute print commands!
    if (user.role.toLowerCase() != 'kacab' && !user.isKacab) {
      return;
    }

    _printCommandSubscription = _firebaseService
        .streamPendingPrintCommands(targetUserId: user.uid, role: user.role)
        .listen((commands) async {
      for (final cmd in commands) {
        // Do not process commands that this user requested (prevent self-print)
        if (cmd.requestedByUserId == user.uid) continue;
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
        customerName: cmd.customerName.isNotEmpty
            ? cmd.customerName
            : (tr.aliasName.isNotEmpty
                ? '${tr.aliasName} (${tr.customerName})'
                : tr.customerName),
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
          _appVersion = '3.3.145';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = '3.3.145';
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

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Selamat Pagi';
    } else if (hour >= 12 && hour < 15) {
      return 'Selamat Siang';
    } else if (hour >= 15 && hour < 18) {
      return 'Selamat Sore';
    } else {
      return 'Selamat Malam';
    }
  }

  void _checkAndShowSyncPrompt() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (user == null) return;
    if (user.role != 'kacab' && user.role != 'staf') return;

    final webrtc = WebRtcScreenService();
    if (webrtc.isBroadcasting) return;

    final greeting = _getTimeBasedGreeting();
    final displayName = user.name.isNotEmpty ? user.name : 'Joko Setiawan';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    border: Border(bottom: BorderSide(color: Color(0xFF334155))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.storefront_rounded, color: Color(0xFF38BDF8), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'PT. PUTRA FIVA SEJAHTERAH — KANTOR CABANG',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Body Content
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0284C7).withOpacity(0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sync_rounded, color: Colors.white, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '$greeting, $displayName!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Komputer Kantor Siap Siaga.',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Silakan klik tombol di bawah untuk menyinkronkan database transaksi dan mengaktifkan jalur cetak invoice otomatis kantor.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.45),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),

                      // Big Action Button: SINKRONKAN DATABASE
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(0xFF0284C7).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 20),
                          label: const Text(
                            '🔄  SINKRONKAN DATABASE',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          onPressed: () async {
                            Navigator.of(ctx).pop();

                            // Start broadcast
                            final success = await webrtc.startBroadcasting(
                              userId: user.uid,
                              userName: user.name.isNotEmpty ? user.name : user.username,
                              sessionId: 'kacab_live',
                              onStoppedByUser: () {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Siaran layar kantor dihentikan dari browser.'),
                                      backgroundColor: Color(0xFF1E293B),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                            );

                            if (mounted && success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 20),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '✅ Database tersinkron & Komputer Kantor Siap Siaga!',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: Color(0xFF0F172A),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Helper Hint Note
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFFBBF24), size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Petunjuk: Setelah menekan tombol di atas, klik tombol [ Allow / Izinkan ] pada jendela browser yang muncul.',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Dismiss button
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text(
                          'Nanti Saja',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
      items.add({
        'title': 'Billing Report',
        'icon': Icons.analytics_outlined,
        'widget': const BillingReportView(),
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
              child: Builder(
                builder: (context) {
                  final webrtc = WebRtcScreenService();
                  final isActive = webrtc.isBroadcasting;

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
                      if (isActive) {
                        await webrtc.stopBroadcasting(sessionId: 'kacab_live');
                        if (mounted) setState(() {});
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
                          userName: user.name.isNotEmpty ? user.name : user.username,
                          sessionId: 'kacab_live',
                          onStoppedByUser: () {
                            if (mounted) setState(() {});
                          },
                        );
                        if (mounted) setState(() {});
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
                children: navItems.asMap().entries.map<Widget>((entry) {
                  final isSelected = entry.key == _currentIndex;
                  return ExcludeFocus(
                    excluding: !isSelected,
                    child: FocusScope(
                      canRequestFocus: isSelected,
                      child: entry.value['widget'] as Widget,
                    ),
                  );
                }).toList(),
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
