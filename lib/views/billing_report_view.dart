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

  // Selected month (defaults to current month)
  late int _selectedYear;
  late int _selectedMonth;

  // Previous month data for comparison
  double _prevMonthTotal = 0.0;

  final _idrFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'IDR',
    decimalDigits: 2,
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

    // Listen to ALL billing_costs and filter in-memory (avoids Firestore composite index requirement)
    _subscription = _db
        .collection('billing_costs')
        .orderBy('date')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final allCosts = snapshot.docs.map((doc) => BillingCost.fromFirestore(doc)).toList();

      // Filter current month
      final currentMonthCosts = allCosts.where((c) =>
          c.date.year == _selectedYear && c.date.month == _selectedMonth).toList();

      // Calculate previous month total
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
        _prevMonthTotal = prevTotal;
        _isLoading = false;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('BillingReport stream error: $e');
    });
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
  // HIDDEN CRUD: Double-click on chart area to add
  //              Single-click on bar to edit/delete
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
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Text('Add Cost Entry', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateController,
              readOnly: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Date',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF94A3B8), size: 16),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: selectedDate ?? DateTime(_selectedYear, _selectedMonth, DateTime.now().day),
                  firstDate: DateTime(_selectedYear, _selectedMonth, 1),
                  lastDate: DateTime(_selectedYear, _selectedMonth + 1, 0),
                  builder: (context, child) => Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(primary: Color(0xFF4285F4), surface: Color(0xFF1E293B)),
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
                labelText: 'Amount (IDR)',
                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
            onPressed: () async {
              if (selectedDate == null || amountController.text.isEmpty) return;
              final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
              if (amount == null || amount <= 0) return;
              await _db.collection('billing_costs').add(BillingCost(
                id: '',
                date: selectedDate!,
                amount: amount,
              ).toFirestore());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BillingCost cost) async {
    final amountController = TextEditingController(text: cost.amount.toStringAsFixed(2));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: Text(
          'Edit – ${DateFormat('MMM d, yyyy').format(cost.date)}',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Amount (IDR)',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  backgroundColor: const Color(0xFF1E293B),
                  title: const Text('Delete entry?', style: TextStyle(color: Colors.white, fontSize: 14)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No', style: TextStyle(color: Color(0xFF94A3B8)))),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, Delete', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (confirm == true) {
                await _db.collection('billing_costs').doc(cost.id).delete();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
            onPressed: () async {
              final amount = double.tryParse(amountController.text.replaceAll(',', '.'));
              if (amount == null || amount <= 0) return;
              await _db.collection('billing_costs').doc(cost.id).update({'amount': amount});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Update', style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 48),
              SizedBox(height: 16),
              Text('Akses Terbatas (Developer Only)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Halaman ini khusus untuk Role Developer.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // Calculate data
    final now = DateTime.now();
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final isCurrentMonth = _selectedYear == now.year && _selectedMonth == now.month;
    final currentDay = isCurrentMonth ? now.day : daysInMonth;

    // Aggregate costs per day
    final Map<int, double> dailyCosts = {};
    for (var cost in _costs) {
      final day = cost.date.day;
      dailyCosts[day] = (dailyCosts[day] ?? 0) + cost.amount;
    }

    final double totalCost = _costs.fold(0.0, (sum, c) => sum + c.amount);

    // Forecasted cost: extrapolate based on daily average
    double forecastedCost = totalCost;
    if (isCurrentMonth && currentDay > 0 && currentDay < daysInMonth) {
      final dailyAvg = totalCost / currentDay;
      forecastedCost = dailyAvg * daysInMonth;
    }

    // Percentage change vs prev month
    double pctChange = 0;
    double diffAmount = 0;
    if (_prevMonthTotal > 0) {
      pctChange = ((totalCost - _prevMonthTotal) / _prevMonthTotal) * 100;
      diffAmount = totalCost - _prevMonthTotal;
    }

    double forecastPctChange = 0;
    double forecastDiffAmount = 0;
    if (_prevMonthTotal > 0) {
      forecastPctChange = ((forecastedCost - _prevMonthTotal) / _prevMonthTotal) * 100;
      forecastDiffAmount = forecastedCost - _prevMonthTotal;
    }

    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final monthNameShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final prevMonthName = monthNames[(_selectedMonth - 2) % 12];
    final prevMonthYear = _selectedMonth == 1 ? _selectedYear - 1 : _selectedYear;

    return Scaffold(
      backgroundColor: const Color(0xFF1C2536), // Google Cloud dark BG
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4285F4)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // =====================================================
                  // 1. TOP HEADER BAR (Google Cloud style breadcrumb)
                  // =====================================================
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C2536),
                      border: Border(bottom: BorderSide(color: Color(0xFF303846), width: 1)),
                    ),
                    child: Row(
                      children: [
                        // Breadcrumb
                        Text(
                          'Billing  /  Reports',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // =====================================================
                  // 2. TITLE BAR "Services – this month"
                  // =====================================================
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1C2536),
                      border: Border(bottom: BorderSide(color: Color(0xFF303846), width: 1)),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Services – this month',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(width: 20),
                        _buildHeaderLink(Icons.list_alt, 'See all reports'),
                        const SizedBox(width: 16),
                        _buildHeaderLink(Icons.code, 'Generate query'),
                        const SizedBox(width: 16),
                        _buildHeaderLink(Icons.share, 'Share'),
                        const Spacer(),
                        // Month navigation (hidden style - only visible on hover)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onDoubleTap: () {
                              // Hidden: change month
                              _showMonthPicker();
                            },
                            child: Row(
                              children: [
                                const Icon(Icons.school_outlined, color: Color(0xFF8AB4F8), size: 16),
                                const SizedBox(width: 6),
                                const Text('Learn', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // =====================================================
                  // 3. ASK GEMINI CLOUD ASSIST BANNER
                  // =====================================================
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF263040),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A4A5C)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.blueAccent.shade100, size: 18),
                        const SizedBox(width: 10),
                        const Text(
                          'Ask Gemini Cloud Assist to create a report',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF394A5E),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Preview', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8AB4F8), size: 20),
                      ],
                    ),
                  ),

                  // =====================================================
                  // 4. FILTER CHIPS BAR
                  // =====================================================
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildFilterChip('Group by (Service)', true),
                        _buildFilterChip('Time range by charge period (Current month)', true),
                        _buildFilterChip('Subaccounts (All 1)', false),
                        _buildFilterChip('Products (All 4)', false),
                        _buildFilterChip('Originating products (All 4)', false),
                        _buildFilterChip('Spend-based CUDs (All 1)', false),
                        _buildFilterChip('Services (All 4)', false),
                        _buildFilterChip('Originating services (All 1)', false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildFilterChip('Projects (All 2)', false),
                        _buildFilterChip('SKUs (All 20)', false, icon: Icons.grid_view),
                        _buildFilterChip('Applications (All 1)', false),
                        _buildFilterChip('Locations (All 4)', false),
                        _buildFilterChip('Labels (None)', false),
                        _buildFilterChip('Invoice level charges (None)', false),
                        _buildTextLink('Show less'),
                      ],
                    ),
                  ),

                  // =====================================================
                  // 5. SUMMARY PROVIDED BY GEMINI CLOUD ASSIST
                  // =====================================================
                  GestureDetector(
                    onDoubleTap: () => _showAddDialog(),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF263040),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3A4A5C)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Colors.blueAccent.shade100, size: 16),
                              const SizedBox(width: 8),
                              const Text(
                                'Summary provided by Gemini Cloud Assist',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF394A5E),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Preview', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                              const Spacer(),
                              const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8AB4F8), size: 20),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Two summary cards side by side
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // LEFT: Current period
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${monthNames[_selectedMonth - 1]} 1 – $currentDay, $_selectedYear',
                                      style: const TextStyle(color: Color(0xFFBDC6D0), fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _idrFormatter.format(totalCost),
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w400),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Includes IDR0.00 in savings',
                                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildPctBadge(pctChange, diffAmount, '$prevMonthName ${_selectedMonth == 1 ? 8 : 8} – ${DateTime(_selectedYear, _selectedMonth, 0).day}, $prevMonthYear'),
                                  ],
                                ),
                              ),

                              // Vertical divider
                              Container(
                                width: 1,
                                height: 90,
                                color: const Color(0xFF3A4A5C),
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                              ),

                              // RIGHT: Forecasted
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${monthNames[_selectedMonth - 1]} 1 – $daysInMonth, $_selectedYear (forecasted)',
                                          style: const TextStyle(color: Color(0xFFBDC6D0), fontSize: 13),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.info_outline, color: Colors.white.withOpacity(0.3), size: 14),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _idrFormatter.format(forecastedCost),
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w400),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Includes IDR0.00 in savings',
                                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildPctBadge(forecastPctChange, forecastDiffAmount, '${monthNames[(_selectedMonth - 2) % 12]} 1 – ${DateTime(_selectedYear, _selectedMonth, 0).day}, $prevMonthYear'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // =====================================================
                  // 6. BAR CHART AREA
                  // =====================================================
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      children: [
                        // Chart controls row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Show cumulative toggle (static display)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3A4A5C),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        margin: const EdgeInsets.only(left: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.7),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('Show cumulative', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Chart type icons (static)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF3A4A5C)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.bar_chart, color: Colors.white.withOpacity(0.7), size: 18),
                                  const SizedBox(width: 4),
                                  Icon(Icons.show_chart, color: Colors.white.withOpacity(0.3), size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // THE BAR CHART
                        SizedBox(
                          height: 280,
                          child: GestureDetector(
                            onDoubleTap: () => _showAddDialog(),
                            child: _buildDailyBarChart(dailyCosts, daysInMonth, currentDay, isCurrentMonth),
                          ),
                        ),

                        // Forecasted cost legend
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5F6D7E),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('Forecasted cost', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                              const SizedBox(width: 4),
                              Icon(Icons.info_outline, color: Colors.white.withOpacity(0.3), size: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // =====================================================
                  // 7. DOWNLOAD CSV (bottom right)
                  // =====================================================
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20, top: 12, bottom: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download, color: const Color(0xFF8AB4F8), size: 16),
                          const SizedBox(width: 4),
                          const Text('Download CSV', style: TextStyle(color: Color(0xFF8AB4F8), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ======================================================
  // HELPER WIDGETS
  // ======================================================

  Widget _buildHeaderLink(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF8AB4F8), size: 15),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Color(0xFF8AB4F8), fontSize: 13)),
      ],
    );
  }

  Widget _buildFilterChip(String label, bool isPrimary, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFF1A3A5C) : const Color(0xFF263040),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPrimary ? const Color(0xFF4285F4).withOpacity(0.5) : const Color(0xFF3A4A5C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white.withOpacity(0.7), size: 14),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: isPrimary ? const Color(0xFF8AB4F8) : Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, color: Colors.white.withOpacity(0.5), size: 16),
        ],
      ),
    );
  }

  Widget _buildTextLink(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(color: Color(0xFF8AB4F8), fontSize: 12)),
    );
  }

  Widget _buildPctBadge(double pctChange, double diffAmount, String comparedTo) {
    final isUp = pctChange >= 0;
    final color = isUp ? const Color(0xFF34A853) : const Color(0xFFEA4335);
    return Row(
      children: [
        Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, color: color, size: 14),
        const SizedBox(width: 2),
        Text(
          '${pctChange.abs().toStringAsFixed(2)}%',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Text(
          '${_idrFormatter.format(diffAmount.abs())} over $comparedTo',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
        ),
      ],
    );
  }

  // ======================================================
  // BAR CHART (Google Cloud Style)
  // ======================================================
  Widget _buildDailyBarChart(Map<int, double> dailyCosts, int daysInMonth, int currentDay, bool isCurrentMonth) {
    final maxY = dailyCosts.isEmpty ? 10000.0 : (dailyCosts.values.reduce((a, b) => a > b ? a : b) * 1.3);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 6,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = group.x + 1;
              final amount = dailyCosts[day] ?? 0;
              return BarTooltipItem(
                '${_getMonthShort(_selectedMonth)} $day\n${_idrFormatter.format(amount)}',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              );
            },
          ),
          touchCallback: (event, response) {
            if (event is FlTapUpEvent && response?.spot != null) {
              final day = response!.spot!.touchedBarGroupIndex + 1;
              final cost = _costs.where((c) => c.date.day == day).toList();
              if (cost.isNotEmpty) {
                _showEditDialog(cost.first);
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
              reservedSize: 56,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _formatCompactIDR(value),
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final day = value.toInt() + 1;
                // Show every day label for readability
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_getMonthShort(_selectedMonth)} $day',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(daysInMonth, (index) {
          final day = index + 1;
          final amount = dailyCosts[day] ?? 0;
          final isFuture = isCurrentMonth && day > currentDay;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: isFuture ? 0 : amount,
                width: daysInMonth > 28 ? 8 : 10,
                color: const Color(0xFF4285F4),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                ),
              ),
            ],
            // Show forecasted dot for future days
            showingTooltipIndicators: [],
          );
        }),
      ),
    );
  }

  String _getMonthShort(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(month - 1) % 12];
  }

  String _formatCompactIDR(double value) {
    if (value >= 1000000) {
      return 'Rp${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return 'Rp${(value / 1000).toStringAsFixed(0)}K';
    }
    return 'Rp${value.toStringAsFixed(0)}';
  }

  // ======================================================
  // MONTH PICKER (Hidden - triggered by double-click on Learn)
  // ======================================================
  void _showMonthPicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            title: const Text('Select Period', style: TextStyle(color: Colors.white, fontSize: 15)),
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
                    Text('$tempYear', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Color(0xFF8AB4F8)),
                      onPressed: () => setDialogState(() => tempYear++),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(12, (i) {
                    final m = i + 1;
                    final isSelected = m == tempMonth;
                    return GestureDetector(
                      onTap: () => setDialogState(() => tempMonth = m),
                      child: Container(
                        width: 60,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF4285F4) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? const Color(0xFF4285F4) : const Color(0xFF334155)),
                        ),
                        child: Center(
                          child: Text(
                            _getMonthShort(m),
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                              fontSize: 12,
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
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _changeMonth(tempYear, tempMonth);
                },
                child: const Text('Apply', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }
}
