import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../models/billing_cost.dart';

class BillingReportView extends StatefulWidget {
  const BillingReportView({super.key});

  @override
  State<BillingReportView> createState() => _BillingReportViewState();
}

class _BillingReportViewState extends State<BillingReportView> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription? _subscription;
  List<BillingCost> _costs = [];
  bool _isLoading = true;

  // Selected month
  int _selectedYear = 2026;
  int _selectedMonth = 8; // August

  // Previous month total for comparison
  double _prevMonthTotal = 46203.75; // July baseline (86,528.45 - 40,324.70)

  // Default seed values matching the exact screenshot (sums to 86,528.45)
  static final Map<int, double> _defaultAugust2026Costs = {
    1: 10850.00,
    2: 7200.00,
    3: 10500.00,
    4: 6120.00,
    5: 1350.00,
    6: 950.00,
    7: 0.00,
    8: 14800.00,
    9: 8450.00,
    10: 8200.00,
    11: 1450.00,
    12: 6100.00,
    13: 6850.00,
    14: 4708.45,
  };

  // Forecast points for each day
  static final Map<int, double> _forecastPoints = {
    1: 5800.0,
    2: 6900.0,
    3: 5900.0,
    4: 4400.0,
    5: 1100.0,
    6: 800.0,
    7: 0.0,
    8: 7200.0,
    9: 6100.0,
    10: 4900.0,
    11: 1100.0,
    12: 5200.0,
    13: 4600.0,
    14: 3800.0,
  };

  final _usCurrencyFormatter = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'IDR',
    decimalDigits: 2,
  );

  final _rpFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _startListening();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startListening() {
    _subscription?.cancel();
    _subscription = _db
        .collection('billing_costs')
        .orderBy('date')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final allCosts = snapshot.docs.map((doc) => BillingCost.fromFirestore(doc)).toList();

      final currentMonthCosts = allCosts.where((c) =>
          c.date.year == _selectedYear && c.date.month == _selectedMonth).toList();

      final prevMonth = _selectedMonth == 1 ? 12 : _selectedMonth - 1;
      final prevYear = _selectedMonth == 1 ? _selectedYear - 1 : _selectedYear;
      double prevTotal = 0;
      for (var c in allCosts) {
        if (c.date.year == prevYear && c.date.month == prevMonth) {
          prevTotal += c.amount;
        }
      }

      setState(() {
        _costs = currentMonthCosts;
        if (prevTotal > 0) {
          _prevMonthTotal = prevTotal;
        } else {
          _prevMonthTotal = 46203.75;
        }
        _isLoading = false;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    });
  }

  // Get active daily map (uses Firestore data if present, otherwise default sample data)
  Map<int, double> _getEffectiveDailyCosts() {
    if (_costs.isNotEmpty) {
      final Map<int, double> map = {};
      for (var c in _costs) {
        map[c.date.day] = (map[c.date.day] ?? 0) + c.amount;
      }
      return map;
    }
    // Fallback to exact screenshot sample data for August 2026
    if (_selectedYear == 2026 && _selectedMonth == 8) {
      return Map.from(_defaultAugust2026Costs);
    }
    return {};
  }

  void _changeMonth(int year, int month) {
    setState(() {
      _selectedYear = year;
      _selectedMonth = month;
      _isLoading = true;
    });
    _startListening();
  }

  // ======================================================
  // HIDDEN CRUD DIALOGS
  // ======================================================
  Future<void> _showAddDialog([DateTime? prefilledDate]) async {
    final dateController = TextEditingController(
      text: prefilledDate != null ? DateFormat('dd/MM/yyyy').format(prefilledDate) : '',
    );
    final amountController = TextEditingController();
    DateTime? selectedDate = prefilledDate;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF333842)),
        ),
        title: const Text('Input Nominal Biaya Harian', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateController,
              readOnly: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Tanggal',
                labelStyle: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF131418),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
                suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF8AB4F8), size: 16),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: selectedDate ?? DateTime(_selectedYear, _selectedMonth, 1),
                  firstDate: DateTime(_selectedYear, _selectedMonth, 1),
                  lastDate: DateTime(_selectedYear, _selectedMonth + 1, 0),
                  builder: (context, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(primary: Color(0xFF1A73E8), surface: Color(0xFF1E222B)),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  selectedDate = picked;
                  dateController.text = DateFormat('dd/MM/yyyy').format(picked);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Nominal Biaya (IDR)',
                hintText: 'Contoh: 10850 atau 4708.45',
                hintStyle: const TextStyle(color: Color(0xFF5F6368), fontSize: 12),
                labelStyle: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF131418),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF9AA0A6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8)),
            onPressed: () async {
              if (selectedDate == null || amountController.text.isEmpty) return;
              final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
              if (amount == null || amount < 0) return;

              // Check if doc exists for this date
              final existingDocs = await _db
                  .collection('billing_costs')
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day)))
                  .where('date', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, 23, 59, 59)))
                  .get();

              if (existingDocs.docs.isNotEmpty) {
                await _db.collection('billing_costs').doc(existingDocs.docs.first.id).update({'amount': amount});
              } else {
                await _db.collection('billing_costs').add(BillingCost(
                  id: '',
                  date: selectedDate!,
                  amount: amount,
                ).toFirestore());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(int day, double currentAmount) async {
    final amountController = TextEditingController(text: currentAmount.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF333842)),
        ),
        title: Text(
          'Edit Biaya: Aug $day, $_selectedYear',
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Nominal Biaya (IDR)',
            labelStyle: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF131418),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF333842))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Delete doc
              final targetDate = DateTime(_selectedYear, _selectedMonth, day);
              final docs = await _db
                  .collection('billing_costs')
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(targetDate.year, targetDate.month, targetDate.day)))
                  .where('date', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59)))
                  .get();

              for (var doc in docs.docs) {
                await doc.reference.delete();
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Hapus / Reset', style: TextStyle(color: Color(0xFFEA4335))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8)),
            onPressed: () async {
              final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
              if (amount == null || amount < 0) return;

              final targetDate = DateTime(_selectedYear, _selectedMonth, day);
              final docs = await _db
                  .collection('billing_costs')
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(targetDate.year, targetDate.month, targetDate.day)))
                  .where('date', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59)))
                  .get();

              if (docs.docs.isNotEmpty) {
                await docs.docs.first.reference.update({'amount': amount});
              } else {
                await _db.collection('billing_costs').add(BillingCost(
                  id: '',
                  date: targetDate,
                  amount: amount,
                ).toFirestore());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ======================================================
  // BUILD
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    if (user == null || !user.isDeveloper) {
      return Scaffold(
        backgroundColor: const Color(0xFF131418),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 48),
              SizedBox(height: 16),
              Text('Akses Terbatas (Developer Only)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Halaman ini khusus untuk Role Developer.', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final dailyCosts = _getEffectiveDailyCosts();
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final int activeDaysCount = dailyCosts.keys.isNotEmpty
        ? dailyCosts.keys.reduce((a, b) => a > b ? a : b)
        : 24;

    final double totalCost = dailyCosts.values.fold(0.0, (sum, v) => sum + v);

    // Exact or calculated forecast
    double forecastedCost = totalCost > 0 ? (totalCost * 0.9997) : 86502.26;
    if (_selectedYear == 2026 && _selectedMonth == 8 && (totalCost - 86528.45).abs() < 1) {
      forecastedCost = 86502.26;
    }

    // Comparison against baseline
    double pctChange = 126.49;
    double diffAmount = 40324.70;
    if (_prevMonthTotal > 0 && totalCost > 0) {
      pctChange = ((totalCost - _prevMonthTotal) / _prevMonthTotal) * 100;
      diffAmount = totalCost - _prevMonthTotal;
    }

    double forecastPctChange = 126.42;
    double forecastDiffAmount = 40298.53;
    if (_prevMonthTotal > 0 && forecastedCost > 0) {
      forecastPctChange = ((forecastedCost - _prevMonthTotal) / _prevMonthTotal) * 100;
      forecastDiffAmount = forecastedCost - _prevMonthTotal;
    }

    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final prevMonthName = monthNames[(_selectedMonth - 2) % 12];
    final prevMonthYear = _selectedMonth == 1 ? _selectedYear - 1 : _selectedYear;

    return Scaffold(
      backgroundColor: const Color(0xFF131418), // Deep Google Cloud Dark
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8)))
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ========================================================
                // LEFT GOOGLE CLOUD SIDEBAR (Exact Replica)
                // ========================================================
                _buildGcpLeftSidebar(),

                // ========================================================
                // MAIN REPORT CONTENT
                // ========================================================
                Expanded(
                  child: Container(
                    color: const Color(0xFF131418),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top GCP Global Bar Replica
                          _buildGcpTopNavBar(),

                          // Services - this month Title Row
                          _buildServicesTitleRow(),

                          // Ask Gemini Cloud Assist Banner
                          _buildAskGeminiBanner(),

                          // Filter Chips Bar (Row 1 & Row 2)
                          _buildFilterChips(),

                          // Summary Provided by Gemini Cloud Assist Card
                          _buildGeminiSummaryCard(
                            monthNames: monthNames,
                            activeDaysCount: activeDaysCount,
                            daysInMonth: daysInMonth,
                            totalCost: totalCost,
                            pctChange: pctChange,
                            diffAmount: diffAmount,
                            prevMonthName: prevMonthName,
                            prevMonthYear: prevMonthYear,
                            forecastedCost: forecastedCost,
                            forecastPctChange: forecastPctChange,
                            forecastDiffAmount: forecastDiffAmount,
                          ),

                          // Daily Bar Chart Area
                          _buildDailyChartSection(
                            dailyCosts: dailyCosts,
                            daysInMonth: daysInMonth,
                          ),

                          // Bottom Service Breakdown Table
                          _buildServiceBreakdownTable(
                            totalCost: totalCost,
                            pctChange: pctChange,
                          ),

                          // Release Notes footer
                          Padding(
                            padding: const EdgeInsets.only(left: 24, bottom: 20, top: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.sticky_note_2_outlined, color: Color(0xFF9AA0A6), size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Release Notes',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ======================================================
  // 1. LEFT GCP SIDEBAR REPLICA
  // ======================================================
  Widget _buildGcpLeftSidebar() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Color(0xFF131418),
        border: Border(right: BorderSide(color: Color(0xFF26282E), width: 1)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Breadcrumb in Sidebar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                'Billing  /  Reports',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ),
            const SizedBox(height: 6),
            // Billing Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Billing',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),

            // Billing Account Dropdown Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF333842)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Billing account', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9.5)),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('Firebase Payment', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                      Icon(Icons.arrow_drop_down, color: Color(0xFF9AA0A6), size: 14),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Cost management Section
            _buildSidebarItem(Icons.dashboard_outlined, 'Overview', false),
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text('Cost management', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            _buildSidebarItem(Icons.bar_chart_rounded, 'Reports', true), // ACTIVE
            _buildSidebarItem(Icons.table_chart_outlined, 'Cost table', false),
            _buildSidebarItem(Icons.pie_chart_outline, 'Cost breakdown', false),
            _buildSidebarItem(Icons.notifications_none, 'Budgets & alerts', false),
            _buildSidebarItem(Icons.file_upload_outlined, 'Billing export', false),
            _buildSidebarItem(Icons.error_outline, 'Anomalies', false),

            const SizedBox(height: 10),
            // Cost optimization Section
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text('Cost optimization', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            _buildSidebarItem(Icons.hub_outlined, 'FinOps hub', false),
            _buildSidebarItem(Icons.card_membership_outlined, 'Committed use discoun...', false),
            _buildSidebarItem(Icons.pie_chart_outline, 'CUD analysis', false),
            _buildSidebarItem(Icons.sell_outlined, 'Pricing', false),
            _buildSidebarItem(Icons.calculate_outlined, 'Cost estimation', false),
            _buildSidebarItem(Icons.credit_card_outlined, 'Credits', false),

            const SizedBox(height: 10),
            // Payments Section
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text('Payments', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            _buildSidebarItem(Icons.receipt_outlined, 'Invoices', false),
            _buildSidebarItem(Icons.swap_horiz, 'Transactions', false),
            _buildSidebarItem(Icons.settings_outlined, 'Payment settings', false),
            _buildSidebarItem(Icons.credit_card, 'Payment method', false),

            const SizedBox(height: 10),
            // Billing management
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text('Billing management', style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            _buildSidebarItem(Icons.manage_accounts_outlined, 'Account management', false),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String label, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1E3A5F) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isActive ? const Border(left: BorderSide(color: Color(0xFF1A73E8), width: 3)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: isActive ? const Color(0xFF8AB4F8) : const Color(0xFF9AA0A6), size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF8AB4F8) : const Color(0xFFE8EAED),
                fontSize: 11.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ======================================================
  // 2. TOP GCP GLOBAL BAR REPLICA
  // ======================================================
  Widget _buildGcpTopNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF131418),
        border: Border(bottom: BorderSide(color: Color(0xFF26282E))),
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              const Icon(Icons.menu, color: Color(0xFFE8EAED), size: 18),
              const SizedBox(width: 10),
              Image.network(
                'https://www.gstatic.com/images/branding/googlelogo/svg/googlelogo_clr_74x24px.svg',
                height: 18,
                errorBuilder: (_, __, ___) => const Text('Google Cloud', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              const SizedBox(width: 4),
              const Text(' Cloud', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w400)),
            ],
          ),
          const SizedBox(width: 24),

          // Search Bar
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E222B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF333842)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search (/) for resources, docs, products, and more',
                      style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11.5),
                    ),
                  ),
                  const Icon(Icons.search, color: Color(0xFF9AA0A6), size: 16),
                ],
              ),
            ),
          ),

          const SizedBox(width: 20),

          // Right Icons
          Row(
            children: [
              const Icon(Icons.add, color: Color(0xFF9AA0A6), size: 18),
              const SizedBox(width: 14),
              const Icon(Icons.notifications_none, color: Color(0xFF9AA0A6), size: 18),
              const SizedBox(width: 14),
              const Icon(Icons.help_outline, color: Color(0xFF9AA0A6), size: 18),
              const SizedBox(width: 14),
              // Profile Circle
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF8E24AA),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('C', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ======================================================
  // 3. SERVICES - THIS MONTH TITLE ROW
  // ======================================================
  Widget _buildServicesTitleRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF131418),
        border: Border(bottom: BorderSide(color: Color(0xFF26282E))),
      ),
      child: Row(
        children: [
          const Text(
            'Services – this month',
            style: TextStyle(color: Color(0xFFE8EAED), fontSize: 18, fontWeight: FontWeight.w400),
          ),
          const SizedBox(width: 24),
          _buildLinkButton(Icons.list_alt, 'See all reports'),
          const SizedBox(width: 16),
          _buildLinkButton(Icons.code, 'Generate query'),
          const SizedBox(width: 16),
          _buildLinkButton(Icons.share, 'Share'),
          const Spacer(),
          // Hidden Month Switcher on Learn double-click
          GestureDetector(
            onDoubleTap: () => _showMonthPicker(),
            child: Row(
              children: const [
                Icon(Icons.school_outlined, color: Color(0xFF8AB4F8), size: 15),
                SizedBox(width: 5),
                Text('Learn', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkButton(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF8AB4F8), size: 14),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFF8AB4F8), fontSize: 12)),
      ],
    );
  }

  // ======================================================
  // 4. ASK GEMINI CLOUD ASSIST BANNER
  // ======================================================
  Widget _buildAskGeminiBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF333842)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFF8AB4F8), size: 16),
          const SizedBox(width: 8),
          const Text(
            'Ask Gemini Cloud Assist to create a report',
            style: TextStyle(color: Color(0xFFE8EAED), fontSize: 12),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFF2D333F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Preview', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 9.5, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8AB4F8), size: 18),
        ],
      ),
    );
  }

  // ======================================================
  // 5. FILTER CHIPS (Row 1 & Row 2)
  // ======================================================
  Widget _buildFilterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPill('Group by (Service)', true),
              _buildPill('Time range by charge period (Current month)', true),
              _buildPill('Subaccounts (All 1)', false),
              _buildPill('Products (All 4)', false, icon: Icons.grid_view),
              _buildPill('Originating products (All 4)', false, icon: Icons.grid_view),
              _buildPill('Spend-based CUDs (All 1)', false, icon: Icons.credit_card),
              _buildPill('Services (All 4)', false, icon: Icons.tune),
              _buildPill('Originating services (All 1)', false, icon: Icons.tune),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPill('Projects (All 2)', false, icon: Icons.tune),
              _buildPill('SKUs (All 20)', false, icon: Icons.format_list_bulleted),
              _buildPill('Applications (All 1)', false, icon: Icons.apps),
              _buildPill('Locations (All 4)', false, icon: Icons.location_on_outlined),
              _buildPill('Labels (None)', false, icon: Icons.label_outline),
              _buildPill('Invoice level charges (None)', false, icon: Icons.receipt_outlined),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.unfold_less, color: Color(0xFF8AB4F8), size: 14),
                    SizedBox(width: 2),
                    Text('Show less', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPill(String label, bool isPrimary, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFF1E3A5F) : const Color(0xFF1E222B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPrimary ? const Color(0xFF1A73E8) : const Color(0xFF333842),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white.withOpacity(0.6), size: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: isPrimary ? const Color(0xFF8AB4F8) : const Color(0xFFE8EAED),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, color: Color(0xFF9AA0A6), size: 14),
        ],
      ),
    );
  }

  // ======================================================
  // 6. SUMMARY PROVIDED BY GEMINI CLOUD ASSIST CARD
  // ======================================================
  Widget _buildGeminiSummaryCard({
    required List<String> monthNames,
    required int activeDaysCount,
    required int daysInMonth,
    required double totalCost,
    required double pctChange,
    required double diffAmount,
    required String prevMonthName,
    required int prevMonthYear,
    required double forecastedCost,
    required double forecastPctChange,
    required double forecastDiffAmount,
  }) {
    return GestureDetector(
      onDoubleTap: () => _showAddDialog(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E222B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF333842)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Title
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF8AB4F8), size: 15),
                const SizedBox(width: 6),
                const Text(
                  'Summary provided by Gemini Cloud Assist',
                  style: TextStyle(color: Color(0xFFE8EAED), fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D333F),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('Preview', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8AB4F8), size: 18),
              ],
            ),

            const SizedBox(height: 14),

            // Two Metrics Side by Side
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT METRIC: Current Period
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${monthNames[_selectedMonth - 1]} 1 – $activeDaysCount, $_selectedYear',
                        style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _usCurrencyFormatter.format(totalCost).replaceAll(' ', ''),
                        style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 20, fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Includes IDR0.00 in savings',
                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward, color: Color(0xFF81C995), size: 13),
                          const SizedBox(width: 2),
                          Text(
                            '${pctChange.abs().toStringAsFixed(2)}%',
                            style: const TextStyle(color: Color(0xFF81C995), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_usCurrencyFormatter.format(diffAmount.abs()).replaceAll(' ', '')} over July 8 – 31, 2026',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1,
                  height: 70,
                  color: const Color(0xFF333842),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                ),

                // RIGHT METRIC: Forecasted
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${monthNames[_selectedMonth - 1]} 1 – $daysInMonth, $_selectedYear (forecasted)',
                            style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.info_outline, color: Colors.white.withOpacity(0.35), size: 13),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _usCurrencyFormatter.format(forecastedCost).replaceAll(' ', ''),
                        style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 20, fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Includes IDR0.00 in savings',
                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward, color: Color(0xFF81C995), size: 13),
                          const SizedBox(width: 2),
                          Text(
                            '${forecastPctChange.abs().toStringAsFixed(2)}%',
                            style: const TextStyle(color: Color(0xFF81C995), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_usCurrencyFormatter.format(forecastDiffAmount.abs()).replaceAll(' ', '')} over July 1 – 31, 2026',
                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================
  // 7. DAILY BAR CHART AREA
  // ======================================================
  Widget _buildDailyChartSection({
    required Map<int, double> dailyCosts,
    required int daysInMonth,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        children: [
          // Chart Controls (Toggle & Bar/Line Icons)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Show cumulative toggle
              Container(
                width: 32,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF333842),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(left: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('Show cumulative', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11.5)),
              const SizedBox(width: 14),

              // Bar / Line Switcher
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF333842)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const Icon(Icons.bar_chart, color: Color(0xFF8AB4F8), size: 15),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.show_chart, color: Color(0xFF5F6368), size: 15),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Bar Chart Canvas
          SizedBox(
            height: 250,
            child: GestureDetector(
              onDoubleTap: () => _showAddDialog(),
              child: _buildGcpBarChart(dailyCosts, daysInMonth),
            ),
          ),

          // Forecasted Cost Legend + Download CSV
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF424A58),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text('Forecasted cost', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11)),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, color: Colors.white.withOpacity(0.35), size: 13),
                const Spacer(),
                Row(
                  children: const [
                    Icon(Icons.download, color: Color(0xFF8AB4F8), size: 14),
                    SizedBox(width: 4),
                    Text('Download CSV', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGcpBarChart(Map<int, double> dailyCosts, int daysInMonth) {
    const double chartMaxY = 16000.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: chartMaxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 4,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = group.x + 1;
              final amount = dailyCosts[day] ?? 0;
              return BarTooltipItem(
                'Aug $day\n${_rpFormatter.format(amount)}',
                const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
              );
            },
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.spot != null) {
              final day = response!.spot!.touchedBarGroupIndex + 1;
              final amount = dailyCosts[day] ?? 0;
              if (amount > 0) {
                _showEditDialog(day, amount);
              } else {
                _showAddDialog(DateTime(_selectedYear, _selectedMonth, day));
              }
            }
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: 5000,
              getTitlesWidget: (value, meta) {
                String text = '';
                if (value == 15000) text = 'Rp15K';
                if (value == 10000) text = 'Rp10K';
                if (value == 5000) text = 'Rp5K';
                if (value == 0) text = 'Rp0';
                if (text.isEmpty) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    text,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9.5),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final day = value.toInt() + 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Aug $day',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 8),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 5000,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.08),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(daysInMonth, (index) {
          final day = index + 1;
          final amount = dailyCosts[day] ?? 0;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: amount,
                width: 14,
                color: const Color(0xFF3B82F6), // Vibrant Google Blue
                borderRadius: BorderRadius.zero,
              ),
            ],
          );
        }),
      ),
    );
  }

  // ======================================================
  // 8. BOTTOM SERVICE BREAKDOWN TABLE
  // ======================================================
  Widget _buildServiceBreakdownTable({
    required double totalCost,
    required double pctChange,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181A20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2E38)),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E222B),
              border: Border(bottom: BorderSide(color: Color(0xFF2A2E38))),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildTableHeaderText('Service')),
                Expanded(flex: 2, child: _buildTableHeaderText('Usage cost ⓘ', align: TextAlign.right)),
                Expanded(flex: 2, child: _buildTableHeaderText('Negotiated savings ⓘ', align: TextAlign.right)),
                Expanded(flex: 2, child: _buildTableHeaderText('Savings programs ⓘ', align: TextAlign.center)),
                Expanded(flex: 2, child: _buildTableHeaderText('Other savings ⓘ', align: TextAlign.center)),
                Expanded(flex: 2, child: _buildTableHeaderText('↓ Subtotal', align: TextAlign.right)),
                Expanded(flex: 2, child: _buildTableHeaderText('% Change ⓘ', align: TextAlign.right)),
              ],
            ),
          ),

          // Row 1: App Engine
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2E38))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: const [
                      Icon(Icons.circle, color: Color(0xFF3B82F6), size: 9),
                      SizedBox(width: 8),
                      Text('App Engine', style: TextStyle(color: Color(0xFFE8EAED), fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: Text(_rpFormatter.format(totalCost), style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 12), textAlign: TextAlign.right)),
                const Expanded(flex: 2, child: Text('Rp0', style: TextStyle(color: Color(0xFFE8EAED), fontSize: 12), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('—', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('—', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(_rpFormatter.format(totalCost), style: const TextStyle(color: Color(0xFFE8EAED), fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(Icons.arrow_upward, color: Color(0xFF81C995), size: 12),
                      const SizedBox(width: 2),
                      Text('${pctChange.toStringAsFixed(0)}%', style: const TextStyle(color: Color(0xFF81C995), fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Table Footer Subtotal/Tax/Total
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildSummaryLine('Subtotal ⓘ', _rpFormatter.format(totalCost)),
                const SizedBox(height: 4),
                _buildSummaryLine('Tax ⓘ', 'Rp0'),
                const SizedBox(height: 4),
                _buildSummaryLine('Total ⓘ', _rpFormatter.format(totalCost), isBold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderText(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 11, fontWeight: FontWeight.bold),
      textAlign: align,
    );
  }

  Widget _buildSummaryLine(String title, String value, {bool isBold = false}) {
    return SizedBox(
      width: 200,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // ======================================================
  // MONTH PICKER
  // ======================================================
  void _showMonthPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFF333842)),
            ),
            title: const Text('Pilih Periode Laporan', style: TextStyle(color: Colors.white, fontSize: 14)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Color(0xFF8AB4F8)),
                      onPressed: () => setDialogState(() => tempYear--),
                    ),
                    Text('$tempYear', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Color(0xFF8AB4F8)),
                      onPressed: () => setDialogState(() => tempYear++),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    final isSelected = m == tempMonth;
                    return GestureDetector(
                      onTap: () => setDialogState(() => tempMonth = m),
                      child: Container(
                        width: 58,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1A73E8) : const Color(0xFF131418),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isSelected ? const Color(0xFF1A73E8) : const Color(0xFF333842)),
                        ),
                        child: Center(
                          child: Text(
                            ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][i],
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF9AA0A6),
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: Color(0xFF9AA0A6))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _changeMonth(tempYear, tempMonth);
                },
                child: const Text('Terapkan', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}
