import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart' as model_tr;

class RankingKacabView extends StatefulWidget {
  const RankingKacabView({super.key});

  @override
  State<RankingKacabView> createState() => _RankingKacabViewState();
}

class _RankingKacabViewState extends State<RankingKacabView> {
  final _currency = NumberFormat.currency(symbol: 'Rp ', decimalDigits: 0);
  final TextEditingController _searchController = TextEditingController();

  String _erpSourceFilter = 'ERP_ONLY'; // 'ERP_ONLY' or 'ALL_TRANSACTIONS'

  // Selected 3-Month Range Start
  int _startMonth = 5;
  int _startYear = 2026;

  String _searchQuery = '';

  String _month1Name = 'Mei';
  String _month2Name = 'Juni';
  String _month3Name = 'Juli 2026';

  List<Map<String, String>> _periodOptions = [];

  static const List<String> _monthNamesIndo = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  String _getMonthName(int month) {
    if (month >= 1 && month <= 12) {
      return _monthNamesIndo[month - 1];
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _initPeriod();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  void _initPeriod() {
    final now = DateTime.now();
    int m = now.month - 2;
    int y = now.year;
    if (m <= 0) {
      m += 12;
      y -= 1;
    }
    _startMonth = m;
    _startYear = y;

    _updateMonthNames();
    _buildPeriodOptions();
  }

  void _updateMonthNames() {
    final m1Date = DateTime(_startYear, _startMonth, 1);
    final m2Date = DateTime(_startYear, _startMonth + 1, 1);
    final m3Date = DateTime(_startYear, _startMonth + 2, 1);

    _month1Name = _getMonthName(m1Date.month);
    _month2Name = _getMonthName(m2Date.month);
    _month3Name = '${_getMonthName(m3Date.month)} ${m3Date.year}';
  }

  void _buildPeriodOptions() {
    final List<Map<String, String>> options = [];
    final now = DateTime.now();

    // From 6 months ahead down to Jan 2024
    DateTime cursor = DateTime(now.year, now.month + 6, 1);
    final DateTime limit = DateTime(2024, 1, 1);
    final Set<String> seen = {};

    while (!cursor.isBefore(limit)) {
      final m1 = cursor;
      final m3 = DateTime(cursor.year, cursor.month + 2, 1);
      final key = '${m1.month}_${m1.year}';

      if (!seen.contains(key)) {
        seen.add(key);
        final m1Label = _getMonthName(m1.month);
        final m3Label = '${_getMonthName(m3.month)} ${m3.year}';
        options.add({
          'value': key,
          'label': '$m1Label - $m3Label',
        });
      }

      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }

    final selectedKey = '${_startMonth}_$_startYear';
    if (!seen.contains(selectedKey)) {
      final m1 = DateTime(_startYear, _startMonth, 1);
      final m3 = DateTime(_startYear, _startMonth + 2, 1);
      final m1Label = _getMonthName(m1.month);
      final m3Label = '${_getMonthName(m3.month)} ${m3.year}';
      options.insert(0, {
        'value': selectedKey,
        'label': '$m1Label - $m3Label',
      });
    }

    _periodOptions = options;
  }

  Map<String, dynamic> _computeRankingData(
    List<model_tr.Transaction> allTr,
    List<Customer> customers,
  ) {
    _updateMonthNames();

    final m1Date = DateTime(_startYear, _startMonth, 1);
    final m2Date = DateTime(_startYear, _startMonth + 1, 1);
    final m3Date = DateTime(_startYear, _startMonth + 2, 1);

    final m1Key = DateFormat('MM-yyyy').format(m1Date);
    final m2Key = DateFormat('MM-yyyy').format(m2Date);
    final m3Key = DateFormat('MM-yyyy').format(m3Date);

    final Map<String, Map<String, dynamic>> storeMap = {};
    bool isFallback = false;

    if (_erpSourceFilter == 'ERP_ONLY') {
      final erpTr = allTr.where((tr) {
        if (tr.erpSyncDate == null) return false;
        final key = DateFormat('MM-yyyy').format(tr.erpSyncDate!);
        return key == m1Key || key == m2Key || key == m3Key;
      }).toList();

      if (erpTr.isEmpty) {
        isFallback = true;
        _aggregateTransactions(allTr, customers, storeMap, m1Key, m2Key, m3Key, isErpOnly: false);
      } else {
        _aggregateTransactions(erpTr, customers, storeMap, m1Key, m2Key, m3Key, isErpOnly: true);
      }
    } else {
      _aggregateTransactions(allTr, customers, storeMap, m1Key, m2Key, m3Key, isErpOnly: false);
    }

    final List<Map<String, dynamic>> outlets = [];
    double gM1 = 0.0;
    double gM2 = 0.0;
    double gM3 = 0.0;
    double gTotal = 0.0;

    storeMap.forEach((alias, data) {
      final m1 = _parseNum(data['m1']);
      final m2 = _parseNum(data['m2']);
      final m3 = _parseNum(data['m3']);
      final total = m1 + m2 + m3;
      final average = total / 3.0;

      gM1 += m1;
      gM2 += m2;
      gM3 += m3;
      gTotal += total;

      outlets.add({
        'alias': alias,
        'city': (data['city'] ?? '-').toString(),
        'month1': m1,
        'month2': m2,
        'month3': m3,
        'total': total,
        'average': average,
      });
    });

    // Sort descending by 3-month average
    outlets.sort((a, b) => _parseNum(b['average']).compareTo(_parseNum(a['average'])));

    // Assign rank to ALL outlets (no limit)
    for (int i = 0; i < outlets.length; i++) {
      outlets[i]['rank'] = i + 1;
    }

    return {
      'outlets': outlets,
      'gM1': gM1,
      'gM2': gM2,
      'gM3': gM3,
      'gTotal': gTotal,
      'gAverage': gTotal / 3.0,
      'storeCount': outlets.length,
      'top1Name': outlets.isNotEmpty ? outlets.first['alias'].toString() : '-',
      'top1Average': outlets.isNotEmpty ? _parseNum(outlets.first['average']) : 0.0,
      'isFallback': isFallback,
    };
  }

  void _aggregateTransactions(
    List<model_tr.Transaction> transactions,
    List<Customer> customers,
    Map<String, Map<String, dynamic>> storeMap,
    String m1Key,
    String m2Key,
    String m3Key, {
    required bool isErpOnly,
  }) {
    for (final tr in transactions) {
      final DateTime? dateToUse = isErpOnly ? tr.erpSyncDate : (tr.erpSyncDate ?? tr.deliveryDate ?? tr.date);
      if (dateToUse == null) continue;

      final key = DateFormat('MM-yyyy').format(dateToUse);
      if (key != m1Key && key != m2Key && key != m3Key) continue;

      Customer? cust;
      try {
        cust = customers.firstWhere((c) => c.id == tr.customerId);
      } catch (_) {}

      String aliasName = (cust != null && cust.aliasName.trim().isNotEmpty)
          ? cust.aliasName.trim()
          : (tr.aliasName.trim().isNotEmpty ? tr.aliasName.trim() : (tr.customerName.trim().isNotEmpty ? tr.customerName.trim() : 'TOKO TANPA NAMA'));
      if (aliasName.isEmpty) aliasName = 'TOKO TANPA NAMA';

      String city = (cust != null && cust.city.trim().isNotEmpty)
          ? cust.city.trim()
          : (tr.city.trim().isNotEmpty ? tr.city.trim() : '-');

      storeMap.putIfAbsent(aliasName, () => {
        'alias': aliasName,
        'city': city,
        'm1': 0.0,
        'm2': 0.0,
        'm3': 0.0,
      });

      final double amount = tr.grandTotal;

      if (key == m1Key) {
        storeMap[aliasName]!['m1'] = _parseNum(storeMap[aliasName]!['m1']) + amount;
      } else if (key == m2Key) {
        storeMap[aliasName]!['m2'] = _parseNum(storeMap[aliasName]!['m2']) + amount;
      } else if (key == m3Key) {
        storeMap[aliasName]!['m3'] = _parseNum(storeMap[aliasName]!['m3']) + amount;
      }
    }
  }

  void _onPeriodChanged(String? val) {
    if (val == null) return;
    final parts = val.split('_');
    if (parts.length == 2) {
      setState(() {
        _startMonth = int.tryParse(parts[0]) ?? _startMonth;
        _startYear = int.tryParse(parts[1]) ?? _startYear;
      });
    }
  }

  /// Export data ranking ke format CSV / Excel
  Future<void> _exportToExcel(
    List<Map<String, dynamic>> filteredList,
    Map<String, dynamic> computed,
  ) async {
    try {
      final StringBuffer csv = StringBuffer();
      // UTF-8 BOM for Microsoft Excel compatibility
      csv.write('\uFEFF');

      // CSV Header
      csv.writeln('"NO","OUTLET","$_month1Name","$_month2Name","$_month3Name","TOTAL","RATA-RATA 3 BULAN"');

      // Data Rows
      for (final item in filteredList) {
        final rank = item['rank'];
        final alias = item['alias'].toString().replaceAll('"', '""');
        final m1 = _currency.format(_parseNum(item['month1'])).replaceAll('"', '""');
        final m2 = _currency.format(_parseNum(item['month2'])).replaceAll('"', '""');
        final m3 = _currency.format(_parseNum(item['month3'])).replaceAll('"', '""');
        final total = _currency.format(_parseNum(item['total'])).replaceAll('"', '""');
        final avg = _currency.format(_parseNum(item['average'])).replaceAll('"', '""');

        csv.writeln('"$rank","$alias","$m1","$m2","$m3","$total","$avg"');
      }

      // Grand Total Row
      final gM1 = _currency.format(_parseNum(computed['gM1'])).replaceAll('"', '""');
      final gM2 = _currency.format(_parseNum(computed['gM2'])).replaceAll('"', '""');
      final gM3 = _currency.format(_parseNum(computed['gM3'])).replaceAll('"', '""');
      final gTotal = _currency.format(_parseNum(computed['gTotal'])).replaceAll('"', '""');
      final gAvg = _currency.format(_parseNum(computed['gAverage'])).replaceAll('"', '""');

      csv.writeln('"TOTAL","TOTAL GRANDTOTAL (SEMUA)","$gM1","$gM2","$gM3","$gTotal","$gAvg"');

      final bytes = Uint8List.fromList(utf8.encode(csv.toString()));
      final fileName = 'Ranking_Kacab_Jateng_${_month1Name}_$_month3Name.csv'.replaceAll(' ', '_');

      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel: $e')),
        );
      }
    }
  }

  /// Cetak Laporan PDF Ranking Kacab
  Future<void> _printPdf(
    List<Map<String, dynamic>> filteredList,
    Map<String, dynamic> computed,
  ) async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              // Header Title
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LAPORAN WEEKLY KACAB',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Cabang: JAWA TENGAH | Periode: $_month1Name - $_month3Name',
                        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('LUCIFAX PFS JATENG', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Tanggal Cetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 10),

              // KPI Stats Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL RATA-RATA 3 BULAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.Text(_currency.format(_parseNum(computed['gAverage'])), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOKO PERINGKAT #1', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.Text(computed['top1Name'].toString(), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL OUTLET', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                        pw.Text('${computed['storeCount']} Toko', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),

              // Ranking Table
              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                headerHeight: 24,
                cellHeight: 20,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                headers: ['NO', 'OUTLET', _month1Name.toUpperCase(), _month2Name.toUpperCase(), _month3Name.toUpperCase(), 'TOTAL', 'RATA-RATA 3 BULAN'],
                data: [
                  ...filteredList.map((item) => [
                    '${item['rank']}',
                    item['alias'].toString(),
                    _currency.format(_parseNum(item['month1'])),
                    _currency.format(_parseNum(item['month2'])),
                    _currency.format(_parseNum(item['month3'])),
                    _currency.format(_parseNum(item['total'])),
                    _currency.format(_parseNum(item['average'])),
                  ]),
                  [
                    'TOTAL',
                    'TOTAL GRANDTOTAL (SEMUA)',
                    _currency.format(_parseNum(computed['gM1'])),
                    _currency.format(_parseNum(computed['gM2'])),
                    _currency.format(_parseNum(computed['gM3'])),
                    _currency.format(_parseNum(computed['gTotal'])),
                    _currency.format(_parseNum(computed['gAverage'])),
                  ],
                ],
              ),
            ];
          },
        ),
      );

      final fileName = 'Laporan_Ranking_Kacab_${_month1Name}_$_month3Name.pdf'.replaceAll(' ', '_');
      await Printing.layoutPdf(
        onLayout: (format) async => doc.save(),
        name: fileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to providers so view updates automatically when data arrives
    final trProvider = Provider.of<TransactionProvider>(context);
    final custProvider = Provider.of<CustomerProvider>(context);

    final computed = _computeRankingData(trProvider.transactions, custProvider.customers);
    final List<Map<String, dynamic>> rankingData = computed['outlets'] as List<Map<String, dynamic>>;
    final bool isFallbackToAll = computed['isFallback'] as bool;

    final filtered = rankingData.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final alias = item['alias'].toString().toLowerCase();
      final city = item['city'].toString().toLowerCase();
      return alias.contains(q) || city.contains(q);
    }).toList();

    final selectedKey = '${_startMonth}_$_startYear';
    final hasKey = _periodOptions.any((opt) => opt['value'] == selectedKey);
    final dropdownValue = hasKey ? selectedKey : (_periodOptions.isNotEmpty ? _periodOptions.first['value'] : null);

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.table_chart_rounded, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'LAPORAN WEEKLY KACAB',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cabang: JAWA TENGAH | Periode: $_month1Name - $_month3Name',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),

              // Actions Header (Filter, Range, Export Excel, Cetak PDF, Refresh)
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Filter Source Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _erpSourceFilter,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
                        icon: const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 18),
                        items: const [
                          DropdownMenuItem(value: 'ERP_ONLY', child: Text('Filter: Data Laporan ERP')),
                          DropdownMenuItem(value: 'ALL_TRANSACTIONS', child: Text('Filter: Semua Transaksi')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _erpSourceFilter = val);
                          }
                        },
                      ),
                    ),
                  ),

                  // 3-Month Range Selector
                  if (_periodOptions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: dropdownValue,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          icon: const Icon(Icons.date_range_rounded, color: Color(0xFF38BDF8), size: 18),
                          menuMaxHeight: 400,
                          items: _periodOptions.map((opt) {
                            return DropdownMenuItem<String>(
                              value: opt['value']!,
                              child: Text(opt['label']!),
                            );
                          }).toList(),
                          onChanged: _onPeriodChanged,
                        ),
                      ),
                    ),

                  // Tombol Export Excel
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: filtered.isEmpty ? null : () => _exportToExcel(filtered, computed),
                    icon: const Icon(Icons.table_view_rounded, size: 18),
                    label: const Text('Export Excel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),

                  // Tombol Cetak PDF
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: filtered.isEmpty ? null : () => _printPdf(filtered, computed),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak PDF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),

                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () => setState(() {}),
                    tooltip: 'Refresh Data',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fallback Alert Banner
          if (isFallbackToAll) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Info: Transaksi belum di-set Status "SUDAH ERP" untuk periode ini. Menampilkan data berdasarkan semua transaksi.',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // KPI Cards Row
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'TOTAL RATA-RATA 3 BULAN',
                  value: _currency.format(_parseNum(computed['gAverage'])),
                  subtitle: 'Total Omset: ${_currency.format(_parseNum(computed['gTotal']))}',
                  icon: Icons.analytics_rounded,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildKpiCard(
                  title: 'TOKO PERINGKAT #1 🥇',
                  value: computed['top1Name'].toString(),
                  subtitle: 'Rata-rata/Bln: ${_currency.format(_parseNum(computed['top1Average']))}',
                  icon: Icons.emoji_events_rounded,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildKpiCard(
                  title: 'TOTAL TOKO / OUTLET',
                  value: '${computed['storeCount']} Toko',
                  subtitle: 'Semua Toko Masuk Peringkat',
                  icon: Icons.store_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search Input Bar
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Cari Nama Outlet / Toko / Kota...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 12),

          // Ranking Data Table Area
          Expanded(
            child: trProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada data transaksi untuk periode 3 bulan ini.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 46,
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 52,
                              headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                              columns: [
                                const DataColumn(label: Text('NO', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                const DataColumn(label: Text('OUTLET', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                DataColumn(label: Text(_month1Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                DataColumn(label: Text(_month2Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                DataColumn(label: Text(_month3Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                const DataColumn(label: Text('TOTAL', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                const DataColumn(label: Text('Rata rata Penjualan 3 Bulan', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                              ],
                              rows: [
                                ...List.generate(filtered.length, (idx) {
                                  final item = filtered[idx];
                                  final int rank = (item['rank'] as num).toInt();

                                  Color badgeColor = Colors.white;
                                  String rankLabel = '$rank';
                                  if (rank == 1) {
                                    badgeColor = Colors.amber;
                                    rankLabel = '🥇 1';
                                  } else if (rank == 2) {
                                    badgeColor = Colors.grey.shade300;
                                    rankLabel = '🥈 2';
                                  } else if (rank == 3) {
                                    badgeColor = Colors.amber.shade800;
                                    rankLabel = '🥉 3';
                                  }

                                  final rankWidget = Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: rank <= 3 ? badgeColor.withOpacity(0.2) : Colors.white10,
                                      borderRadius: BorderRadius.circular(8),
                                      border: rank <= 3 ? Border.all(color: badgeColor, width: 0.8) : null,
                                    ),
                                    child: Text(
                                      rankLabel,
                                      style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  );

                                  return DataRow(
                                    color: MaterialStateProperty.resolveWith<Color?>((states) {
                                      if (rank == 1) return Colors.amber.withOpacity(0.05);
                                      return idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02);
                                    }),
                                    cells: [
                                      DataCell(rankWidget),
                                      DataCell(
                                        Text(
                                          item['alias'].toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(_currency.format(_parseNum(item['month1'])), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(_currency.format(_parseNum(item['month2'])), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(_currency.format(_parseNum(item['month3'])), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(_currency.format(_parseNum(item['total'])), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(Text(_currency.format(_parseNum(item['average'])), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                    ],
                                  );
                                }),

                                // TOTAL SUMMARY ROW
                                DataRow(
                                  color: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                  cells: [
                                    const DataCell(Text('TOTAL', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    const DataCell(Text('TOTAL GRANDTOTAL (SEMUA)', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                    DataCell(Text(_currency.format(_parseNum(computed['gM1'])), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(_currency.format(_parseNum(computed['gM2'])), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(_currency.format(_parseNum(computed['gM3'])), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(_currency.format(_parseNum(computed['gTotal'])), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                    DataCell(Text(_currency.format(_parseNum(computed['gAverage'])), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
