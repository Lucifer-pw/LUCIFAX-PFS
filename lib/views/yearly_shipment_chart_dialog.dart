import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/transaction.dart' as model_tr;
import '../providers/transaction_provider.dart';
import '../services/firebase_service.dart';

class YearlyShipmentChartDialog extends StatefulWidget {
  final int initialYear;

  const YearlyShipmentChartDialog({
    super.key,
    this.initialYear = 2026,
  });

  static void show(BuildContext context, {int initialYear = 2026}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => YearlyShipmentChartDialog(initialYear: initialYear),
    );
  }

  @override
  State<YearlyShipmentChartDialog> createState() => _YearlyShipmentChartDialogState();
}

class _YearlyShipmentChartDialogState extends State<YearlyShipmentChartDialog> {
  late int _selectedYear;
  String _selectedMetric = 'NOMINAL'; // 'NOMINAL', 'BERAT', 'INVOICE'
  final FirebaseService _firebaseService = FirebaseService();
  final Map<int, double> _monthlyTargets = {};

  StreamSubscription? _targetSubscription;
  Map<String, double> _cachedTargetsMap = {};

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  final List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  final List<String> _monthShortNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _initMonthlyTargets();
  }

  @override
  void dispose() {
    _targetSubscription?.cancel();
    super.dispose();
  }

  void _initMonthlyTargets() {
    // 1. Instant fallback targets (0ms latency, eliminates loading delay)
    _applyTargetsForYear();

    // 2. Real-time stream from Firestore for instant reactive updates
    _targetSubscription = _firebaseService.streamAllMonthlyTargets().listen((targetsMap) {
      if (!mounted) return;
      setState(() {
        _cachedTargetsMap = targetsMap;
        _applyTargetsForYear();
      });
    });
  }

  void _applyTargetsForYear() {
    for (int m = 1; m <= 12; m++) {
      final mStr = m.toString().padLeft(2, '0');
      final key = '$mStr-$_selectedYear';
      if (_cachedTargetsMap.containsKey(key)) {
        _monthlyTargets[m] = _cachedTargetsMap[key]!;
      } else {
        _monthlyTargets[m] = 310947810.0;
      }
    }
  }

  List<int> _getAvailableYears(List<model_tr.Transaction> transactions) {
    final Set<int> years = {2025, 2026, 2027, DateTime.now().year};
    for (var tr in transactions) {
      final effectiveDate = tr.deliveryDate ?? tr.date;
      years.add(effectiveDate.year);
    }
    final list = years.toList();
    list.sort((a, b) => b.compareTo(a));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final trProvider = Provider.of<TransactionProvider>(context);
    final allTransactions = trProvider.transactions;
    final availableYears = _getAvailableYears(allTransactions);

    // Filter only DIKIRIM transactions in the selected year
    final shippedInYear = allTransactions.where((tr) {
      // Must be status DIKIRIM (status barang = DIKIRIM)
      final isDikirim = tr.status.toUpperCase() == 'DIKIRIM';
      if (!isDikirim) return false;

      final effectiveDate = tr.deliveryDate ?? tr.date;
      return effectiveDate.year == _selectedYear;
    }).toList();

    // Aggregate data for 12 months (1 to 12)
    final Map<int, Map<String, dynamic>> monthlyData = {};
    for (int m = 1; m <= 12; m++) {
      monthlyData[m] = {
        'month': m,
        'name': _monthNames[m - 1],
        'short': _monthShortNames[m - 1],
        'nominal': 0.0,
        'weightKg': 0.0,
        'invoiceCount': 0,
        'itemsCount': 0,
        'erpNominal': 0.0,
        'erpWeightKg': 0.0,
        'erpInvoiceCount': 0,
      };
    }

    for (var tr in shippedInYear) {
      final effectiveDate = tr.deliveryDate ?? tr.date;
      final m = effectiveDate.month;
      if (monthlyData.containsKey(m)) {
        double trNominal = tr.grandTotal;
        double trWeight = tr.items.fold(0.0, (sum, it) => sum + it.weightKg);

        if (tr.items.isNotEmpty) {
          double itemsNominal = 0;
          for (var item in tr.items) {
            itemsNominal += (item.isBonus ? 0.0 : item.subtotal);
          }
          if (itemsNominal > 0) trNominal = itemsNominal;
        }

        monthlyData[m]!['nominal'] = (monthlyData[m]!['nominal'] as double) + trNominal;
        monthlyData[m]!['weightKg'] = (monthlyData[m]!['weightKg'] as double) + trWeight;
        monthlyData[m]!['invoiceCount'] = (monthlyData[m]!['invoiceCount'] as int) + 1;
        monthlyData[m]!['itemsCount'] = (monthlyData[m]!['itemsCount'] as int) + tr.items.length;
      }
    }

    // Aggregate ERP data reported in Menu ERP (transactions with erpSyncDate in selected year)
    for (var tr in allTransactions) {
      if (tr.erpSyncDate == null) continue;
      final erpDate = tr.erpSyncDate!;
      if (erpDate.year != _selectedYear) continue;
      final m = erpDate.month;
      if (monthlyData.containsKey(m)) {
        double trNominal = tr.grandTotal;
        double trWeight = tr.items.fold(0.0, (sum, it) => sum + it.weightKg);

        if (tr.items.isNotEmpty) {
          double itemsNominal = 0;
          for (var item in tr.items) {
            itemsNominal += (item.isBonus ? 0.0 : item.subtotal);
          }
          if (itemsNominal > 0) trNominal = itemsNominal;
        }

        monthlyData[m]!['erpNominal'] = (monthlyData[m]!['erpNominal'] as double) + trNominal;
        monthlyData[m]!['erpWeightKg'] = (monthlyData[m]!['erpWeightKg'] as double) + trWeight;
        monthlyData[m]!['erpInvoiceCount'] = (monthlyData[m]!['erpInvoiceCount'] as int) + 1;
      }
    }

    // Calculate Summary Stats
    double grandTotalNominal = 0.0;
    double grandTotalWeight = 0.0;
    double grandTotalErpNominal = 0.0;
    int grandTotalInvoices = 0;
    int activeMonthsCount = 0;
    int peakMonth = 1;
    double maxNominalInMonth = 0.0;

    for (int m = 1; m <= 12; m++) {
      final nom = monthlyData[m]!['nominal'] as double;
      final wt = monthlyData[m]!['weightKg'] as double;
      final inv = monthlyData[m]!['invoiceCount'] as int;
      final erpNom = monthlyData[m]!['erpNominal'] as double;

      grandTotalNominal += nom;
      grandTotalWeight += wt;
      grandTotalErpNominal += erpNom;
      grandTotalInvoices += inv;

      if (nom > 0 || inv > 0 || erpNom > 0) {
        activeMonthsCount++;
      }
      if (nom > maxNominalInMonth) {
        maxNominalInMonth = nom;
        peakMonth = m;
      }
    }

    final double avgNominal = activeMonthsCount > 0 ? (grandTotalNominal / activeMonthsCount) : 0.0;
    final double avgWeight = activeMonthsCount > 0 ? (grandTotalWeight / activeMonthsCount) : 0.0;

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 768;

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 10 : 24,
        vertical: isSmallScreen ? 14 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      child: Container(
        width: isSmallScreen ? double.infinity : (screenSize.width > 1200 ? 1120 : screenSize.width * 0.95),
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.94,
        ),
        child: Column(
          children: [
            // ========================================================
            // 1. DIALOG HEADER
            // ========================================================
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 14 : 20,
                vertical: isSmallScreen ? 12 : 16,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: isSmallScreen
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF6366F1), Color(0xFF0284C7)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(Icons.insights_rounded, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Grafik Pengiriman Tahunan',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                              tooltip: 'Tutup',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                              ),
                              child: const Text(
                                'STATUS: DIKIRIM',
                                style: TextStyle(color: Colors.greenAccent, fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8), size: 13),
                                  const SizedBox(width: 6),
                                  DropdownButton<int>(
                                    value: _selectedYear,
                                    dropdownColor: const Color(0xFF1E293B),
                                    underline: const SizedBox(),
                                    isDense: true,
                                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8)),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    items: availableYears.map((yr) {
                                      return DropdownMenuItem<int>(
                                        value: yr,
                                        child: Text('Tahun $yr'),
                                      );
                                    }).toList(),
                                    onChanged: (newYr) {
                                      if (newYr != null && newYr != _selectedYear) {
                                        setState(() {
                                          _selectedYear = newYr;
                                          _applyTargetsForYear();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF0284C7)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.insights_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Grafik & Analisis Pengiriman Tahunan',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                                          ),
                                          child: const Text(
                                            'STATUS: DIKIRIM',
                                            style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Data Distribusi Barang Terkirim Cabang Jawa Tengah - Tahun $_selectedYear',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Year Selector Dropdown
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8), size: 16),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: _selectedYear,
                                dropdownColor: const Color(0xFF1E293B),
                                underline: const SizedBox(),
                                icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8)),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                items: availableYears.map((yr) {
                                  return DropdownMenuItem<int>(
                                    value: yr,
                                    child: Text('Tahun $yr'),
                                  );
                                }).toList(),
                                onChanged: (newYr) {
                                  if (newYr != null && newYr != _selectedYear) {
                                    setState(() {
                                      _selectedYear = newYr;
                                      _applyTargetsForYear();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Close Button
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
            ),

            // ========================================================
            // 2. DIALOG BODY (SCROLLABLE)
            // ========================================================
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 2A. KPI SUMMARY CARDS ---
                    _buildKpiCards(
                      grandTotalNominal: grandTotalNominal,
                      grandTotalWeight: grandTotalWeight,
                      grandTotalInvoices: grandTotalInvoices,
                      avgNominal: avgNominal,
                      peakMonth: peakMonth,
                      maxNominalInMonth: maxNominalInMonth,
                      isSmall: isSmallScreen,
                    ),

                    const SizedBox(height: 16),

                    // --- 2B. CHART SECTION WITH METRIC TOGGLE ---
                    Container(
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isSmallScreen) ...[
                            Row(
                              children: [
                                const Icon(Icons.bar_chart_rounded, color: Color(0xFF38BDF8), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Grafik Penjualan & Pengiriman ($_selectedYear)',
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Row(
                                  children: [
                                    _buildMetricButton('NOMINAL', 'Nominal (Rp)', Icons.attach_money_rounded),
                                    _buildMetricButton('BERAT', 'Berat (Kg)', Icons.scale_rounded),
                                    _buildMetricButton('INVOICE', 'Jml Invoice', Icons.receipt_long_rounded),
                                  ],
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.bar_chart_rounded, color: Color(0xFF38BDF8), size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Grafik Tren Penjualan & Pengiriman ($_selectedYear)',
                                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Pencapaian barang berstatus DIKIRIM setiap bulan',
                                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                                    ),
                                  ],
                                ),

                                // Metric Segment Buttons
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: Row(
                                    children: [
                                      _buildMetricButton('NOMINAL', 'Nominal (Rp)', Icons.attach_money_rounded),
                                      _buildMetricButton('BERAT', 'Berat (Kg)', Icons.scale_rounded),
                                      _buildMetricButton('INVOICE', 'Jml Invoice', Icons.receipt_long_rounded),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),

                          // FL_CHART BAR CHART
                          SizedBox(
                            height: 260,
                            child: isSmallScreen
                                ? SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: 580,
                                      child: _buildBarChart(monthlyData),
                                    ),
                                  )
                                : _buildBarChart(monthlyData),
                          ),

                          const SizedBox(height: 12),
                          // Legend Bar Chart
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildLegendItem(const Color(0xFF38BDF8), 'Realisasi Pengiriman ($_selectedMetric)'),
                                const SizedBox(width: 16),
                                if (_selectedMetric == 'NOMINAL') ...[
                                  _buildLegendItem(const Color(0xFFF59E0B), 'Target Bulanan (Rp)'),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- 2C. MONTHLY BREAKDOWN TABLE ---
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isSmallScreen) ...[
                            Row(
                              children: [
                                const Icon(Icons.table_chart_rounded, color: Color(0xFF10B981), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Rekapitulasi Pencapaian ($_selectedYear)',
                                    style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Area: Cabang Jawa Tengah',
                              style: TextStyle(color: const Color(0xFF38BDF8).withOpacity(0.9), fontSize: 11.5, fontWeight: FontWeight.w500),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.table_chart_rounded, color: Color(0xFF10B981), size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tabel Rekapitulasi Pencapaian Bulanan ($_selectedYear)',
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                Text(
                                  'Area: Cabang Jawa Tengah',
                                  style: TextStyle(color: const Color(0xFF38BDF8).withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),

                          // Data Table
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
                                dataTextStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
                                horizontalMargin: 16,
                                columnSpacing: isSmallScreen ? 14 : 20,
                                columns: const [
                                  DataColumn(label: Center(child: Text('No', textAlign: TextAlign.center))),
                                  DataColumn(label: Text('Bulan')),
                                  DataColumn(numeric: true, label: Text('Jml Invoice')),
                                  DataColumn(numeric: true, label: Text('Total Berat (Kg)')),
                                  DataColumn(numeric: true, label: Text('Pencapaian Value (Rp)')),
                                  DataColumn(numeric: true, label: Text('Target Bulan (Rp)')),
                                  DataColumn(numeric: true, label: Text('ERP (Rp)')),
                                  DataColumn(label: Center(child: Text('Pencapaian (%)', textAlign: TextAlign.center))),
                                  DataColumn(label: Center(child: Text('Status', textAlign: TextAlign.center))),
                                ],
                                rows: [
                                  // 12 Months Rows
                                  ...List.generate(12, (index) {
                                    final m = index + 1;
                                    final data = monthlyData[m]!;
                                    final nom = data['nominal'] as double;
                                    final wt = data['weightKg'] as double;
                                    final inv = data['invoiceCount'] as int;
                                    final erpNom = data['erpNominal'] as double;
                                    final target = _monthlyTargets[m] ?? 310947810.0;
                                    final pct = target > 0 ? (nom / target) * 100 : (nom > 0 ? 100.0 : 0.0);
                                    final isReached = target > 0 ? nom >= target : nom > 0;

                                    return DataRow(
                                      color: MaterialStateProperty.resolveWith((states) {
                                        if (index % 2 == 0) return Colors.white.withOpacity(0.02);
                                        return Colors.transparent;
                                      }),
                                      cells: [
                                        DataCell(Center(child: Text('${index + 1}'))),
                                        DataCell(Text(
                                          '${data['name']} $_selectedYear',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(inv > 0 ? '$inv inv' : '-')),
                                        DataCell(Text(wt > 0 ? '${wt.toStringAsFixed(2)} Kg' : '-')),
                                        DataCell(Text(
                                          nom > 0 ? _rupiahFormatter.format(nom) : '-',
                                          style: TextStyle(
                                            color: nom > 0 ? Colors.greenAccent : const Color(0xFF64748B),
                                            fontWeight: nom > 0 ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(
                                          InkWell(
                                            onTap: () {
                                              final mStr = m.toString().padLeft(2, '0');
                                              _showEditTargetDialog(context, '$mStr-$_selectedYear', target);
                                            },
                                            borderRadius: BorderRadius.circular(4),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    target > 0 ? _rupiahFormatter.format(target) : '-',
                                                    style: const TextStyle(color: Color(0xFFF59E0B)),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.edit_rounded, color: Color(0xFFF59E0B), size: 11),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Kolom ERP (Rp)
                                        DataCell(Text(
                                          erpNom > 0 ? _rupiahFormatter.format(erpNom) : '-',
                                          style: TextStyle(
                                            color: erpNom > 0 ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                                            fontWeight: erpNom > 0 ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(Center(
                                          child: Text(
                                            nom > 0 && target > 0 ? '${pct.toStringAsFixed(1)}%' : (nom > 0 ? '-' : '0%'),
                                            style: TextStyle(
                                              color: pct >= 100 ? Colors.greenAccent : (pct >= 50 ? const Color(0xFF38BDF8) : const Color(0xFFA78BFA)),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )),
                                        DataCell(Center(
                                          child: nom == 0
                                              ? const Text('-', style: TextStyle(color: Color(0xFF64748B)))
                                              : Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isReached
                                                        ? Colors.green.withOpacity(0.2)
                                                        : Colors.red.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: isReached
                                                          ? Colors.greenAccent.withOpacity(0.4)
                                                          : Colors.redAccent.withOpacity(0.4),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    isReached ? 'On-Target' : 'Un-Target',
                                                    style: TextStyle(
                                                      color: isReached ? Colors.greenAccent : Colors.redAccent,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                        )),
                                      ],
                                    );
                                  }),

                                  // TOTAL TAHUNAN ROW
                                  DataRow(
                                    color: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                    cells: [
                                      const DataCell(SizedBox()),
                                      const DataCell(Text('TOTAL TAHUNAN', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(Text('$grandTotalInvoices inv', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataCell(Text('${grandTotalWeight.toStringAsFixed(2)} Kg', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                      DataCell(Text(_rupiahFormatter.format(grandTotalNominal), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                      const DataCell(SizedBox()),
                                      DataCell(Text(grandTotalErpNominal > 0 ? _rupiahFormatter.format(grandTotalErpNominal) : '-', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                      const DataCell(SizedBox()),
                                      const DataCell(SizedBox()),
                                    ],
                                  ),

                                  // RATA-RATA BULANAN ROW
                                  DataRow(
                                    color: MaterialStateProperty.all(const Color(0xFF1E293B)),
                                    cells: [
                                      const DataCell(SizedBox()),
                                      const DataCell(Text('RATA-RATA BULANAN', style: TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(Text(activeMonthsCount > 0 ? '${(grandTotalInvoices / activeMonthsCount).toStringAsFixed(1)} inv' : '-', style: const TextStyle(color: Colors.white70))),
                                      DataCell(Text('${avgWeight.toStringAsFixed(2)} Kg', style: const TextStyle(color: Color(0xFF38BDF8)))),
                                      DataCell(Text(_rupiahFormatter.format(avgNominal), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                      const DataCell(SizedBox()),
                                      DataCell(Text(activeMonthsCount > 0 && grandTotalErpNominal > 0 ? _rupiahFormatter.format(grandTotalErpNominal / activeMonthsCount) : '-', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                      const DataCell(SizedBox()),
                                      const DataCell(SizedBox()),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ========================================================
            // 3. DIALOG FOOTER
            // ========================================================
            Container(
              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 20, vertical: isSmallScreen ? 10 : 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: Color(0xFF334155))),
              ),
              child: isSmallScreen
                  ? Column(
                      children: [
                        Text(
                          'Total $activeMonthsCount bulan aktif transaksi di tahun $_selectedYear',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.edit_calendar_rounded, size: 14, color: Color(0xFFF59E0B)),
                                label: const Text('Atur Target', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11.5)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFF59E0B)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  final currentMonthStr = DateTime.now().month.toString().padLeft(2, '0');
                                  final activeKey = '$currentMonthStr-$_selectedYear';
                                  _showEditTargetDialog(context, activeKey, _monthlyTargets[DateTime.now().month] ?? 0.0);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total $activeMonthsCount bulan aktif transaksi di tahun $_selectedYear',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.edit_calendar_rounded, size: 16, color: Color(0xFFF59E0B)),
                              label: const Text('Atur Target Bulanan', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFF59E0B)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                final currentMonthStr = DateTime.now().month.toString().padLeft(2, '0');
                                final activeKey = '$currentMonthStr-$_selectedYear';
                                _showEditTargetDialog(context, activeKey, _monthlyTargets[DateTime.now().month] ?? 0.0);
                              },
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET HELPER: KPI CARDS ---
  Widget _buildKpiCards({
    required double grandTotalNominal,
    required double grandTotalWeight,
    required int grandTotalInvoices,
    required double avgNominal,
    required int peakMonth,
    required double maxNominalInMonth,
    required bool isSmall,
  }) {
    final card1 = _buildKpiCard(
      title: isSmall ? 'TOTAL OMZET ($_selectedYear)' : 'TOTAL OMZET DIKIRIM ($_selectedYear)',
      value: _rupiahFormatter.format(grandTotalNominal),
      subtitle: '$grandTotalInvoices Total Invoice Terkirim',
      icon: Icons.attach_money_rounded,
      iconColor: Colors.greenAccent,
      borderColor: Colors.greenAccent.withOpacity(0.3),
      bgColor: Colors.green.withOpacity(0.12),
      isSmall: isSmall,
    );

    final card2 = _buildKpiCard(
      title: isSmall ? 'TOTAL BERAT (KG)' : 'TOTAL BERAT BARANG (KG)',
      value: '${grandTotalWeight.toStringAsFixed(2)} Kg',
      subtitle: 'Distribusi Fisik Tahunan',
      icon: Icons.scale_rounded,
      iconColor: const Color(0xFF38BDF8),
      borderColor: const Color(0xFF38BDF8).withOpacity(0.3),
      bgColor: const Color(0xFF0284C7).withOpacity(0.12),
      isSmall: isSmall,
    );

    final card3 = _buildKpiCard(
      title: isSmall ? 'RATA-RATA / BULAN' : 'RATA-RATA PENJUALAN BULANAN',
      value: _rupiahFormatter.format(avgNominal),
      subtitle: 'Performa rata-rata / bulan aktif',
      icon: Icons.trending_up_rounded,
      iconColor: const Color(0xFFA78BFA),
      borderColor: const Color(0xFFA78BFA).withOpacity(0.3),
      bgColor: const Color(0xFF7C3AED).withOpacity(0.12),
      isSmall: isSmall,
    );

    final card4 = _buildKpiCard(
      title: isSmall ? 'BULAN TERTINGGI' : 'BULAN TERTINGGI (PEAK)',
      value: maxNominalInMonth > 0 ? _monthNames[peakMonth - 1] : '-',
      subtitle: maxNominalInMonth > 0 ? _rupiahFormatter.format(maxNominalInMonth) : 'Belum ada data',
      icon: Icons.star_rounded,
      iconColor: const Color(0xFFF59E0B),
      borderColor: const Color(0xFFF59E0B).withOpacity(0.3),
      bgColor: const Color(0xFFF59E0B).withOpacity(0.12),
      isSmall: isSmall,
    );

    if (isSmall) {
      return Column(
        children: [
          Row(children: [Expanded(child: card1), const SizedBox(width: 8), Expanded(child: card2)]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: card3), const SizedBox(width: 8), Expanded(child: card4)]),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: card1),
        const SizedBox(width: 12),
        Expanded(child: card2),
        const SizedBox(width: 12),
        Expanded(child: card3),
        const SizedBox(width: 12),
        Expanded(child: card4),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required Color bgColor,
    bool isSmall = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 10 : 14,
        vertical: isSmall ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isSmall ? 6 : 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: isSmall ? 16 : 20),
          ),
          SizedBox(width: isSmall ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isSmall ? 8.5 : 9.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(color: iconColor, fontSize: isSmall ? 13 : 14, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(color: const Color(0xFF64748B), fontSize: isSmall ? 9 : 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET HELPER: METRIC SELECTOR BUTTON ---
  Widget _buildMetricButton(String metricKey, String label, IconData icon) {
    final isSelected = _selectedMetric == metricKey;
    return InkWell(
      onTap: () => setState(() => _selectedMetric = metricKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET HELPER: BAR CHART BUILDER ---
  Widget _buildBarChart(Map<int, Map<String, dynamic>> monthlyData) {
    double maxY = 0;
    for (int m = 1; m <= 12; m++) {
      double val = 0;
      if (_selectedMetric == 'NOMINAL') {
        val = monthlyData[m]!['nominal'] as double;
        final target = _monthlyTargets[m] ?? 0.0;
        if (target > val) val = target;
      } else if (_selectedMetric == 'BERAT') {
        val = monthlyData[m]!['weightKg'] as double;
      } else {
        val = (monthlyData[m]!['invoiceCount'] as int).toDouble();
      }
      if (val > maxY) maxY = val;
    }

    if (maxY == 0) maxY = 100;
    maxY = maxY * 1.2; // Add top padding

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (group) => const Color(0xFF0F172A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final m = group.x.toInt() + 1;
              final data = monthlyData[m]!;
              final nom = data['nominal'] as double;
              final wt = data['weightKg'] as double;
              final inv = data['invoiceCount'] as int;
              final erpNom = data['erpNominal'] as double;
              final target = _monthlyTargets[m] ?? 0.0;
              final pct = target > 0 ? (nom / target) * 100 : 0.0;

              String text = '${data['name']} $_selectedYear\n';
              text += '• Nominal: ${_rupiahFormatter.format(nom)}\n';
              if (erpNom > 0) {
                text += '• ERP: ${_rupiahFormatter.format(erpNom)}\n';
              }
              text += '• Berat: ${wt.toStringAsFixed(1)} Kg\n';
              text += '• Invoice: $inv Inv\n';
              if (target > 0) {
                text += '• Target: ${_rupiahFormatter.format(target)} (${pct.toStringAsFixed(1)}%)';
              }

              return BarTooltipItem(
                text,
                const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < 12) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _monthShortNames[idx],
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 65,
              getTitlesWidget: (val, meta) {
                if (val == 0) return const SizedBox();
                String label = '';
                if (_selectedMetric == 'NOMINAL') {
                  if (val >= 1000000000) {
                    label = '${(val / 1000000000).toStringAsFixed(1)}M';
                  } else if (val >= 1000000) {
                    label = '${(val / 1000000).toStringAsFixed(0)}Jt';
                  } else {
                    label = '${(val / 1000).toStringAsFixed(0)}rb';
                  }
                } else if (_selectedMetric == 'BERAT') {
                  label = '${val.toStringAsFixed(0)} kg';
                } else {
                  label = '${val.toInt()} inv';
                }
                return Text(
                  label,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withOpacity(0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(12, (index) {
          final m = index + 1;
          final data = monthlyData[m]!;
          double val = 0;
          if (_selectedMetric == 'NOMINAL') {
            val = data['nominal'] as double;
          } else if (_selectedMetric == 'BERAT') {
            val = data['weightKg'] as double;
          } else {
            val = (data['invoiceCount'] as int).toDouble();
          }

          final hasData = val > 0;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: val,
                width: 18,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                gradient: hasData
                    ? const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      )
                    : LinearGradient(
                        colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.08)],
                      ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
        ),
      ],
    );
  }

  void _showEditTargetDialog(BuildContext context, String initialMonth, double currentTarget) {
    String targetMonth = initialMonth;
    final targetController = TextEditingController(
      text: currentTarget > 0 ? currentTarget.toInt().toString() : '310947810',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isSaving = false;
          return StatefulBuilder(
            builder: (ctx, setInnerState) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.track_changes_rounded, color: Color(0xFF38BDF8), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text('Atur Target Bulanan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Target Penjualan Cabang Jawa Tengah',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Periode Target:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          DropdownButton<String>(
                            value: targetMonth,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                            underline: const SizedBox(),
                            items: List.generate(12, (idx) {
                              final mStr = (idx + 1).toString().padLeft(2, '0');
                              return '$mStr-$_selectedYear';
                            }).map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                            onChanged: isSaving ? null : (val) async {
                              if (val != null) {
                                setInnerState(() => targetMonth = val);
                                final parts = val.split('-');
                                final mIdx = int.tryParse(parts[0]) ?? 1;
                                final t = await _firebaseService.getMonthlyTarget(
                                  val,
                                  defaultTarget: (mIdx == 8 && _selectedYear == 2026 ? 310947810.0 : 0.0),
                                );
                                targetController.text = t > 0 ? t.toInt().toString() : '310947810';
                                setInnerState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Nominal Target (Rp):', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: targetController,
                      enabled: !isSaving,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: '310947810',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '* Target tersimpan di database dan berlaku untuk seluruh laporan cabang.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(isSaving ? 'Menyimpan...' : 'Simpan Target'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: isSaving ? null : () async {
                    final cleanStr = targetController.text.replaceAll(RegExp(r'[^0-9]'), '');
                    final val = double.tryParse(cleanStr) ?? 0.0;
                    if (val <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nominal target harus lebih dari 0!'), backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    setInnerState(() => isSaving = true);
                    try {
                      await _firebaseService.setMonthlyTarget(targetMonth, val);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Target periode $targetMonth berhasil disimpan: ${_rupiahFormatter.format(val)}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _cachedTargetsMap[targetMonth] = val;
                        _applyTargetsForYear();
                      }
                    } catch (e) {
                      setInnerState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Gagal menyimpan target: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
