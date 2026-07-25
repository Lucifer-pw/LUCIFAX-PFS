import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';

class RankingKacabView extends StatefulWidget {
  const RankingKacabView({super.key});

  @override
  State<RankingKacabView> createState() => _RankingKacabViewState();
}

class _RankingKacabViewState extends State<RankingKacabView> {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  String _erpSourceFilter = 'ERP_ONLY'; // 'ERP_ONLY' or 'ALL_TRANSACTIONS'
  
  // Selected 3-Month Range Start (Month & Year)
  int _startMonth = 5;
  int _startYear = 2026;
  
  String _searchQuery = '';
  bool _isFallbackToAll = false;
  
  List<Map<String, dynamic>> _rankingData = [];
  
  // Grand totals across ALL outlets
  double _grandTotalM1 = 0.0;
  double _grandTotalM2 = 0.0;
  double _grandTotalM3 = 0.0;
  double _grandTotalAll = 0.0;
  double _grandAverageAll = 0.0;
  
  int _totalStoreCount = 0;
  String _top1StoreName = '-';
  double _top1Average = 0.0;

  String _month1Name = '';
  String _month2Name = '';
  String _month3Name = '';

  // Dynamic period dropdown items
  List<Map<String, dynamic>> _periodItems = [];

  @override
  void initState() {
    super.initState();
    _initDefaultPeriod();
    _buildPeriodItems();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRankingData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Set default period: 3 bulan terakhir berdasarkan tanggal saat ini
  void _initDefaultPeriod() {
    final now = DateTime.now();
    int m = now.month - 2;
    int y = now.year;
    if (m <= 0) {
      m += 12;
      y -= 1;
    }
    _startMonth = m;
    _startYear = y;

    DateTime m1Date = DateTime(_startYear, _startMonth, 1);
    DateTime m2Date = DateTime(_startYear, _startMonth + 1, 1);
    DateTime m3Date = DateTime(_startYear, _startMonth + 2, 1);

    _month1Name = DateFormat('MMMM', 'id_ID').format(m1Date);
    _month2Name = DateFormat('MMMM', 'id_ID').format(m2Date);
    _month3Name = DateFormat('MMMM yyyy', 'id_ID').format(m3Date);
  }

  /// Generate daftar periode 3 bulan secara dinamis dari tahun 2024 s/d 6 bulan ke depan
  void _buildPeriodItems() {
    final items = <Map<String, dynamic>>[];
    final now = DateTime.now();
    
    // Mulai dari 6 bulan ke depan hingga Januari 2024
    DateTime cursor = DateTime(now.year, now.month + 6, 1);
    final DateTime earliest = DateTime(2024, 1, 1);

    final Set<String> addedValues = {};

    while (!cursor.isBefore(earliest)) {
      final m1 = cursor;
      final m3 = DateTime(cursor.year, cursor.month + 2, 1);

      final val = '${m1.month}_${m1.year}';
      if (!addedValues.contains(val)) {
        addedValues.add(val);
        final m1Label = DateFormat('MMMM', 'id_ID').format(m1);
        final m3Label = DateFormat('MMMM yyyy', 'id_ID').format(m3);

        items.add({
          'value': val,
          'label': '$m1Label - $m3Label',
        });
      }

      // Mundur 1 bulan
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }

    // Pastikan _startMonth & _startYear terpilih SELALU ada dalam daftar dropdown
    final currentVal = '${_startMonth}_$_startYear';
    if (!addedValues.contains(currentVal)) {
      final m1 = DateTime(_startYear, _startMonth, 1);
      final m3 = DateTime(_startYear, _startMonth + 2, 1);
      final m1Label = DateFormat('MMMM', 'id_ID').format(m1);
      final m3Label = DateFormat('MMMM yyyy', 'id_ID').format(m3);
      items.insert(0, {
        'value': currentVal,
        'label': '$m1Label - $m3Label',
      });
    }

    _periodItems = items;
  }

  /// Load ranking data dari transaksi di memori (0 Firestore Reads)
  Future<void> _loadRankingData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final custProvider = Provider.of<CustomerProvider>(context, listen: false);
      
      final allTransactions = trProvider.transactions;
      final customers = custProvider.customers;

      // 1. Build 3-Month Window dates based on selected _startMonth & _startYear
      DateTime m1Date = DateTime(_startYear, _startMonth, 1);
      DateTime m2Date = DateTime(_startYear, _startMonth + 1, 1);
      DateTime m3Date = DateTime(_startYear, _startMonth + 2, 1);

      _month1Name = DateFormat('MMMM', 'id_ID').format(m1Date);
      _month2Name = DateFormat('MMMM', 'id_ID').format(m2Date);
      _month3Name = DateFormat('MMMM yyyy', 'id_ID').format(m3Date);

      final m1Key = DateFormat('MM-yyyy').format(m1Date);
      final m2Key = DateFormat('MM-yyyy').format(m2Date);
      final m3Key = DateFormat('MM-yyyy').format(m3Date);

      // 2. Filter transaksi langsung dari memori (0 Reads!)
      final Map<String, Map<String, dynamic>> storeMap = {};
      _isFallbackToAll = false;

      if (_erpSourceFilter == 'ERP_ONLY') {
        // Filter hanya transaksi yang SUDAH masuk ERP (erpSyncDate != null)
        final erpTransactions = allTransactions.where((tr) {
          if (tr.erpSyncDate == null) return false;
          final trMonthKey = DateFormat('MM-yyyy').format(tr.erpSyncDate!);
          return trMonthKey == m1Key || trMonthKey == m2Key || trMonthKey == m3Key;
        }).toList();

        if (erpTransactions.isEmpty) {
          // Tidak ada transaksi ERP → fallback ke semua transaksi
          _isFallbackToAll = true;
          _processAllTransactions(allTransactions, customers, storeMap, m1Key, m2Key, m3Key);
        } else {
          // Proses transaksi ERP
          for (var tr in erpTransactions) {
            final trMonthKey = DateFormat('MM-yyyy').format(tr.erpSyncDate!);
            _addToStoreMap(tr, customers, storeMap, trMonthKey, m1Key, m2Key, m3Key);
          }
        }
      } else {
        // ALL_TRANSACTIONS: Gunakan semua transaksi
        _processAllTransactions(allTransactions, customers, storeMap, m1Key, m2Key, m3Key);
      }

      // 3. Build ranking list dari storeMap — TANPA batasan, tampilkan SEMUA outlet
      final List<Map<String, dynamic>> allOutlets = [];
      double sumM1 = 0.0;
      double sumM2 = 0.0;
      double sumM3 = 0.0;
      double sumTotal = 0.0;

      storeMap.forEach((alias, data) {
        final m1 = ((data['m1'] ?? 0.0) as num).toDouble();
        final m2 = ((data['m2'] ?? 0.0) as num).toDouble();
        final m3 = ((data['m3'] ?? 0.0) as num).toDouble();
        final total = m1 + m2 + m3;
        final average = total / 3.0;

        sumM1 += m1;
        sumM2 += m2;
        sumM3 += m3;
        sumTotal += total;

        allOutlets.add({
          'alias': alias,
          'city': (data['city'] ?? '-').toString(),
          'month1': m1,
          'month2': m2,
          'month3': m3,
          'total': total,
          'average': average,
        });
      });

      // Sort ALL outlets in descending order by average 3-month sales
      allOutlets.sort((a, b) => ((b['average'] ?? 0.0) as num).compareTo((a['average'] ?? 0.0) as num));

      // Assign rank ke SEMUA outlet
      for (int i = 0; i < allOutlets.length; i++) {
        allOutlets[i]['rank'] = i + 1;
      }

      if (mounted) {
        setState(() {
          _rankingData = allOutlets;
          _grandTotalM1 = sumM1;
          _grandTotalM2 = sumM2;
          _grandTotalM3 = sumM3;
          _grandTotalAll = sumTotal;
          _grandAverageAll = sumTotal / 3.0;

          _totalStoreCount = allOutlets.length;
          _top1StoreName = allOutlets.isNotEmpty ? (allOutlets.first['alias'] ?? '-').toString() : '-';
          _top1Average = allOutlets.isNotEmpty ? ((allOutlets.first['average'] ?? 0.0) as num).toDouble() : 0.0;
        });
      }
    } catch (e, stack) {
      debugPrint("Error loading ranking data: $e\n$stack");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Helper: Tambahkan transaksi ke storeMap berdasarkan aliasName
  void _addToStoreMap(
    dynamic tr,
    List<Customer> customers,
    Map<String, Map<String, dynamic>> storeMap,
    String trMonthKey,
    String m1Key,
    String m2Key,
    String m3Key,
  ) {
    Customer? cust;
    try {
      cust = customers.firstWhere((c) => c.id == tr.customerId);
    } catch (_) {}

    String aliasName = (cust != null && cust.aliasName.isNotEmpty)
        ? cust.aliasName
        : (tr.aliasName != null && tr.aliasName.toString().isNotEmpty ? tr.aliasName.toString() : ((tr.customerName ?? 'TOKO TANPA NAMA').toString()));
    if (aliasName.isEmpty) aliasName = 'TOKO TANPA NAMA';

    String city = (cust != null && cust.city.isNotEmpty)
        ? cust.city
        : (tr.city != null && tr.city.toString().isNotEmpty ? tr.city.toString() : '-');

    storeMap.putIfAbsent(aliasName, () => {
      'alias': aliasName,
      'city': city,
      'm1': 0.0,
      'm2': 0.0,
      'm3': 0.0,
    });

    double grandTotal = ((tr.grandTotal ?? 0.0) as num).toDouble();

    if (trMonthKey == m1Key) {
      storeMap[aliasName]!['m1'] = ((storeMap[aliasName]!['m1'] ?? 0.0) as num).toDouble() + grandTotal;
    } else if (trMonthKey == m2Key) {
      storeMap[aliasName]!['m2'] = ((storeMap[aliasName]!['m2'] ?? 0.0) as num).toDouble() + grandTotal;
    } else if (trMonthKey == m3Key) {
      storeMap[aliasName]!['m3'] = ((storeMap[aliasName]!['m3'] ?? 0.0) as num).toDouble() + grandTotal;
    }
  }

  /// Helper: Proses semua transaksi (fallback / mode ALL_TRANSACTIONS)
  void _processAllTransactions(
    List<dynamic> allTransactions,
    List<Customer> customers,
    Map<String, Map<String, dynamic>> storeMap,
    String m1Key,
    String m2Key,
    String m3Key,
  ) {
    for (var tr in allTransactions) {
      final DateTime effectiveDate = tr.erpSyncDate ?? tr.deliveryDate ?? tr.date ?? DateTime.now();
      final trMonthKey = DateFormat('MM-yyyy').format(effectiveDate);

      if (trMonthKey != m1Key && trMonthKey != m2Key && trMonthKey != m3Key) {
        continue;
      }

      _addToStoreMap(tr, customers, storeMap, trMonthKey, m1Key, m2Key, m3Key);
    }
  }

  void _setPeriodPreset(int startMonth, int startYear) {
    setState(() {
      _startMonth = startMonth;
      _startYear = startYear;
    });
    _loadRankingData();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, stack) {
      debugPrint("RankingKacabView render error: $e\n$stack");
      return Container(
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Terjadi Kesalahan Tampilan Ranking Kacab',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$e\n\n$stack',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    // Search filtering
    final filteredList = _rankingData.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final alias = (item['alias'] ?? '').toString().toLowerCase();
      final city = (item['city'] ?? '').toString().toLowerCase();
      return alias.contains(q) || city.contains(q);
    }).toList();

    // Pastikan _periodItems tidak kosong & value dropdown selalu valid
    if (_periodItems.isEmpty) {
      _buildPeriodItems();
    }
    final String targetVal = '${_startMonth}_$_startYear';
    final bool valueExists = _periodItems.any((item) => item['value'] == targetVal);
    final String? dropdownValue = valueExists 
        ? targetVal 
        : (_periodItems.isNotEmpty ? _periodItems.first['value'] as String : null);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Row (Title & Excel Style Info)
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
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cabang: JAWA TENGAH | Periode: $_month1Name - $_month3Name',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Filter Source (Hanya ERP vs Semua Data)
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
                            setState(() {
                              _erpSourceFilter = val;
                            });
                            _loadRankingData();
                          }
                        },
                      ),
                    ),
                  ),

                  // Dynamic 3-Month Range Selector
                  if (_periodItems.isNotEmpty)
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
                          items: _periodItems.map<DropdownMenuItem<String>>((item) {
                            return DropdownMenuItem<String>(
                              value: (item['value'] ?? '').toString(),
                              child: Text((item['label'] ?? '').toString()),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              final parts = val.split('_');
                              _setPeriodPreset(int.parse(parts[0]), int.parse(parts[1]));
                            }
                          },
                        ),
                      ),
                    ),

                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                    onPressed: _loadRankingData,
                    tooltip: 'Refresh Data',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fallback Banner
          if (_isFallbackToAll) ...[
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
                      'Info: Transaksi belum di-set Status "SUDAH ERP" untuk periode ini. Menampilkan data berdasarkan semua transaksi. Anda dapat mengupdate Status ERP di menu Histori Transaksi.',
                      style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Summary KPI Stat Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'TOTAL RATA-RATA 3 BULAN',
                  value: currencyFormatter.format(_grandAverageAll),
                  subtitle: 'Total Omset: ${currencyFormatter.format(_grandTotalAll)}',
                  icon: Icons.analytics_rounded,
                  accentColor: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'TOKO PERINGKAT #1 🥇',
                  value: _top1StoreName,
                  subtitle: 'Rata-rata/Bln: ${currencyFormatter.format(_top1Average)}',
                  icon: Icons.emoji_events_rounded,
                  accentColor: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'TOTAL TOKO / OUTLET',
                  value: '$_totalStoreCount Toko',
                  subtitle: 'Semua Toko Masuk Peringkat',
                  icon: Icons.store_rounded,
                  accentColor: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search Bar
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
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          const SizedBox(height: 12),

          // Excel Style Data Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                    ? const Center(child: Text('Belum ada data transaksi untuk periode 3 bulan ini.', style: TextStyle(color: Color(0xFF94A3B8))))
                    : Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                                ...List.generate(filteredList.length, (idx) {
                                  final item = filteredList[idx];
                                  final rank = ((item['rank'] ?? (idx + 1)) as num).toInt();

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
                                          (item['alias'] ?? '-').toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(currencyFormatter.format(((item['month1'] ?? 0.0) as num).toDouble()), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(((item['month2'] ?? 0.0) as num).toDouble()), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(((item['month3'] ?? 0.0) as num).toDouble()), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(((item['total'] ?? 0.0) as num).toDouble()), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(Text(currencyFormatter.format(((item['average'] ?? 0.0) as num).toDouble()), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                    ],
                                  );
                                }),

                                // TOTAL GRANDTOTAL (SEMUA) Summary Row
                                DataRow(
                                  color: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                  cells: [
                                    const DataCell(Text('TOTAL', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    const DataCell(Text('TOTAL GRANDTOTAL (SEMUA)', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                    DataCell(Text(currencyFormatter.format(_grandTotalM1), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(currencyFormatter.format(_grandTotalM2), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(currencyFormatter.format(_grandTotalM3), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                    DataCell(Text(currencyFormatter.format(_grandTotalAll), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                    DataCell(Text(currencyFormatter.format(_grandAverageAll), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
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

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 22),
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
                  style: TextStyle(color: accentColor, fontSize: 15, fontWeight: FontWeight.bold),
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
