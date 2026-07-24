import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import '../services/firebase_service.dart';

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
  int _startMonth = 5; // Default: Mei (5)
  int _startYear = 2026; // Default: 2026
  
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

  @override
  void initState() {
    super.initState();
    _loadRankingData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRankingData() async {
    setState(() => _isLoading = true);
    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final custProvider = Provider.of<CustomerProvider>(context, listen: false);
      
      final allTransactions = trProvider.transactions;
      final customers = custProvider.customers;
      final FirebaseService dbService = FirebaseService();

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

      // 2. Fetch ERP Summaries for each month (same data source as Stok ERP & Opname Cabang)
      final m1Records = await dbService.getErpSummaries(m1Key, cachedTransactions: allTransactions);
      final m2Records = await dbService.getErpSummaries(m2Key, cachedTransactions: allTransactions);
      final m3Records = await dbService.getErpSummaries(m3Key, cachedTransactions: allTransactions);

      final Map<String, Map<String, dynamic>> storeMap = {};
      bool usedErpSummaries = false;

      if (_erpSourceFilter == 'ERP_ONLY' && (m1Records.isNotEmpty || m2Records.isNotEmpty || m3Records.isNotEmpty)) {
        usedErpSummaries = true;
        _isFallbackToAll = false;

        void processErpMonthRecords(List<Map<String, dynamic>> records, String mKey) {
          for (var rec in records) {
            final customerId = (rec['customerId'] ?? '').toString();
            Customer? cust;
            try {
              cust = customers.firstWhere((c) => c.id == customerId);
            } catch (_) {}

            String aliasName = (cust != null && cust.aliasName.isNotEmpty)
                ? cust.aliasName
                : (rec['aliasName'] ?? rec['customerName'] ?? 'TOKO TANPA NAMA').toString();
            if (aliasName.isEmpty) aliasName = 'TOKO TANPA NAMA';

            String city = (cust != null && cust.city.isNotEmpty)
                ? cust.city
                : (rec['city'] ?? '-').toString();

            double income = (rec['totalIncome'] ?? 0.0).toDouble();

            storeMap.putIfAbsent(aliasName, () => {
              'alias': aliasName,
              'city': city,
              'm1': 0.0,
              'm2': 0.0,
              'm3': 0.0,
            });

            if (mKey == m1Key) {
              storeMap[aliasName]!['m1'] = (storeMap[aliasName]!['m1'] as double) + income;
            } else if (mKey == m2Key) {
              storeMap[aliasName]!['m2'] = (storeMap[aliasName]!['m2'] as double) + income;
            } else if (mKey == m3Key) {
              storeMap[aliasName]!['m3'] = (storeMap[aliasName]!['m3'] as double) + income;
            }
          }
        }

        processErpMonthRecords(m1Records, m1Key);
        processErpMonthRecords(m2Records, m2Key);
        processErpMonthRecords(m3Records, m3Key);
      }

      if (!usedErpSummaries) {
        if (_erpSourceFilter == 'ERP_ONLY') {
          _isFallbackToAll = true;
        } else {
          _isFallbackToAll = false;
        }

        for (var tr in allTransactions) {
          final DateTime effectiveDate = tr.erpSyncDate ?? tr.deliveryDate ?? tr.date;
          final trMonthKey = DateFormat('MM-yyyy').format(effectiveDate);

          if (trMonthKey != m1Key && trMonthKey != m2Key && trMonthKey != m3Key) {
            continue;
          }

          Customer? cust;
          try {
            cust = customers.firstWhere((c) => c.id == tr.customerId);
          } catch (_) {}

          String aliasName = (cust != null && cust.aliasName.isNotEmpty)
              ? cust.aliasName
              : (tr.aliasName.isNotEmpty ? tr.aliasName : tr.customerName);
          if (aliasName.isEmpty) aliasName = 'TOKO TANPA NAMA';

          String city = (cust != null && cust.city.isNotEmpty)
              ? cust.city
              : (tr.city.isNotEmpty ? tr.city : '-');

          storeMap.putIfAbsent(aliasName, () => {
            'alias': aliasName,
            'city': city,
            'm1': 0.0,
            'm2': 0.0,
            'm3': 0.0,
          });

          if (trMonthKey == m1Key) {
            storeMap[aliasName]!['m1'] = (storeMap[aliasName]!['m1'] as double) + tr.grandTotal;
          } else if (trMonthKey == m2Key) {
            storeMap[aliasName]!['m2'] = (storeMap[aliasName]!['m2'] as double) + tr.grandTotal;
          } else if (trMonthKey == m3Key) {
            storeMap[aliasName]!['m3'] = (storeMap[aliasName]!['m3'] as double) + tr.grandTotal;
          }
        }
      }

      final List<Map<String, dynamic>> allOutlets = [];
      double sumM1 = 0.0;
      double sumM2 = 0.0;
      double sumM3 = 0.0;
      double sumTotal = 0.0;

      storeMap.forEach((alias, data) {
        final m1 = (data['m1'] ?? 0.0) as double;
        final m2 = (data['m2'] ?? 0.0) as double;
        final m3 = (data['m3'] ?? 0.0) as double;
        final total = m1 + m2 + m3;
        final average = total / 3.0;

        sumM1 += m1;
        sumM2 += m2;
        sumM3 += m3;
        sumTotal += total;

        allOutlets.add({
          'alias': alias,
          'city': data['city'],
          'month1': m1,
          'month2': m2,
          'month3': m3,
          'total': total,
          'average': average,
          'isOther': false,
        });
      });

      // Sort ALL outlets in descending order by average 3-month sales
      allOutlets.sort((a, b) => (b['average'] as double).compareTo(a['average'] as double));

      // Separate Top 15 and OTHER
      final List<Map<String, dynamic>> finalDisplayList = [];
      
      final int topCount = allOutlets.length < 15 ? allOutlets.length : 15;
      for (int i = 0; i < topCount; i++) {
        final item = Map<String, dynamic>.from(allOutlets[i]);
        item['rank'] = i + 1;
        finalDisplayList.add(item);
      }

      // If stores exceed 15, aggregate ranks 16+ into "OTHER" category
      if (allOutlets.length > 15) {
        double otherM1 = 0.0;
        double otherM2 = 0.0;
        double otherM3 = 0.0;
        double otherTotal = 0.0;

        for (int i = 15; i < allOutlets.length; i++) {
          final item = allOutlets[i];
          otherM1 += item['month1'] as double;
          otherM2 += item['month2'] as double;
          otherM3 += item['month3'] as double;
          otherTotal += item['total'] as double;
        }

        final int otherStoreCount = allOutlets.length - 15;
        finalDisplayList.add({
          'rank': 16,
          'alias': 'OTHER ($otherStoreCount Toko)',
          'city': '-',
          'month1': otherM1,
          'month2': otherM2,
          'month3': otherM3,
          'total': otherTotal,
          'average': otherTotal / 3.0,
          'isOther': true,
          'otherCount': otherStoreCount,
        });
      }

      setState(() {
        _rankingData = finalDisplayList;
        _grandTotalM1 = sumM1;
        _grandTotalM2 = sumM2;
        _grandTotalM3 = sumM3;
        _grandTotalAll = sumTotal;
        _grandAverageAll = sumTotal / 3.0;

        _totalStoreCount = allOutlets.length;
        _top1StoreName = allOutlets.isNotEmpty ? allOutlets.first['alias'] : '-';
        _top1Average = allOutlets.isNotEmpty ? allOutlets.first['average'] : 0.0;
      });
    } catch (e) {
      debugPrint("Error loading ranking data: $e");
    } finally {
      setState(() => _isLoading = false);
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
    // Search filtering
    final filteredList = _rankingData.where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final alias = (item['alias'] as String).toLowerCase();
      final city = (item['city'] as String).toLowerCase();
      return alias.contains(q) || city.contains(q);
    }).toList();

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

                  // Preset 3-Month Range Selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: '${_startMonth}_$_startYear',
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        icon: const Icon(Icons.date_range_rounded, color: Color(0xFF38BDF8), size: 18),
                        items: const [
                          DropdownMenuItem(value: '5_2026', child: Text('Mei - Juli 2026')),
                          DropdownMenuItem(value: '4_2026', child: Text('April - Juni 2026')),
                          DropdownMenuItem(value: '3_2026', child: Text('Maret - Mei 2026')),
                          DropdownMenuItem(value: '2_2026', child: Text('Februari - April 2026')),
                          DropdownMenuItem(value: '1_2026', child: Text('Januari - Maret 2026')),
                        ],
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
                      'Info: Transaksi belum di-set Status "SUDAH ERP". Menampilkan data berdasarkan transaksi saat ini. Anda dapat mengupdate Status ERP di menu Histori Transaksi.',
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
                  subtitle: _totalStoreCount > 15
                      ? '15 Toko Utama + ${_totalStoreCount - 15} Kategori OTHER'
                      : 'Semua Toko Masuk Peringkat Utama',
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
                        child: Scrollbar(
                          thumbVisibility: true,
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
                                    final rank = item['rank'] as int;
                                    final isOther = item['isOther'] == true;

                                    Widget rankWidget;
                                    if (isOther) {
                                      rankWidget = Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.purpleAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.purpleAccent, width: 0.8),
                                        ),
                                        child: const Text(
                                          'OTHER',
                                          style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      );
                                    } else {
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

                                      rankWidget = Container(
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
                                    }

                                    return DataRow(
                                      color: MaterialStateProperty.resolveWith<Color?>((states) {
                                        if (isOther) return Colors.purple.withOpacity(0.08);
                                        if (rank == 1) return Colors.amber.withOpacity(0.05);
                                        return idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02);
                                      }),
                                      cells: [
                                        DataCell(rankWidget),
                                        DataCell(
                                          Text(
                                            item['alias'],
                                            style: TextStyle(
                                              color: isOther ? Colors.purpleAccent : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(currencyFormatter.format(item['month1']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                        DataCell(Text(currencyFormatter.format(item['month2']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                        DataCell(Text(currencyFormatter.format(item['month3']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                        DataCell(Text(currencyFormatter.format(item['total']), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                        DataCell(Text(currencyFormatter.format(item['average']), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
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
