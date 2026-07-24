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
  String _selectedPeriodKey = '3_MONTHS_RECENT'; // Default: 3 Bulan Terakhir
  String _searchQuery = '';
  
  List<Map<String, dynamic>> _rankingData = [];
  double _totalPeriodSales = 0.0;
  String _top1StoreName = '-';
  double _top1Amount = 0.0;
  int _totalStoreCount = 0;

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
      
      final transactions = trProvider.transactions;
      final customers = custProvider.customers;

      DateTime now = DateTime.now();
      DateTime m3Date = DateTime(now.year, now.month, 1);
      DateTime m2Date = DateTime(now.year, now.month - 1, 1);
      DateTime m1Date = DateTime(now.year, now.month - 2, 1);

      // Period Presets
      if (_selectedPeriodKey == 'MEI_JULI_2026') {
        m1Date = DateTime(2026, 5, 1);
        m2Date = DateTime(2026, 6, 1);
        m3Date = DateTime(2026, 7, 1);
      } else if (_selectedPeriodKey == 'APR_JUNI_2026') {
        m1Date = DateTime(2026, 4, 1);
        m2Date = DateTime(2026, 5, 1);
        m3Date = DateTime(2026, 6, 1);
      } else if (_selectedPeriodKey == 'MAR_MEI_2026') {
        m1Date = DateTime(2026, 3, 1);
        m2Date = DateTime(2026, 4, 1);
        m3Date = DateTime(2026, 5, 1);
      }

      _month1Name = DateFormat('MMMM yyyy', 'id_ID').format(m1Date);
      _month2Name = DateFormat('MMMM yyyy', 'id_ID').format(m2Date);
      _month3Name = DateFormat('MMMM yyyy', 'id_ID').format(m3Date);

      final m1Key = DateFormat('MM-yyyy').format(m1Date);
      final m2Key = DateFormat('MM-yyyy').format(m2Date);
      final m3Key = DateFormat('MM-yyyy').format(m3Date);

      final Map<String, Map<String, dynamic>> storeMap = {};

      for (var tr in transactions) {
        final trMonthKey = DateFormat('MM-yyyy').format(tr.date);
        
        // Filter transactions within the 3-month window
        if (trMonthKey != m1Key && trMonthKey != m2Key && trMonthKey != m3Key) {
          continue;
        }

        // Resolve Customer Alias and City
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
          m1Key: 0.0,
          m2Key: 0.0,
          m3Key: 0.0,
          'txCount': 0,
        });

        storeMap[aliasName]![trMonthKey] = (storeMap[aliasName]![trMonthKey] as double) + tr.grandTotal;
        storeMap[aliasName]!['txCount'] = (storeMap[aliasName]!['txCount'] as int) + 1;
      }

      final List<Map<String, dynamic>> allRankedStores = [];
      double grandTotalAll = 0.0;

      storeMap.forEach((alias, data) {
        final m1 = data[m1Key] as double;
        final m2 = data[m2Key] as double;
        final m3 = data[m3Key] as double;
        final total = m1 + m2 + m3;
        final avg = total / 3.0;

        grandTotalAll += total;

        allRankedStores.add({
          'alias': alias,
          'city': data['city'],
          'month1': m1,
          'month2': m2,
          'month3': m3,
          'total': total,
          'average': avg,
          'txCount': data['txCount'],
          'isOther': false,
        });
      });

      // Sort descending by total nominal sales
      allRankedStores.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

      // Separate Top 15 and OTHER category
      final List<Map<String, dynamic>> finalDisplayList = [];
      
      final int topCount = allRankedStores.length < 15 ? allRankedStores.length : 15;
      for (int i = 0; i < topCount; i++) {
        final item = Map<String, dynamic>.from(allRankedStores[i]);
        item['rank'] = i + 1;
        finalDisplayList.add(item);
      }

      // If stores exceed 15, aggregate ranks 16+ into "OTHER" category
      if (allRankedStores.length > 15) {
        double otherM1 = 0.0;
        double otherM2 = 0.0;
        double otherM3 = 0.0;
        double otherTotal = 0.0;
        int otherTxCount = 0;

        for (int i = 15; i < allRankedStores.length; i++) {
          final item = allRankedStores[i];
          otherM1 += item['month1'] as double;
          otherM2 += item['month2'] as double;
          otherM3 += item['month3'] as double;
          otherTotal += item['total'] as double;
          otherTxCount += item['txCount'] as int;
        }

        final int otherStoreCount = allRankedStores.length - 15;
        finalDisplayList.add({
          'rank': 16,
          'alias': 'OTHER ($otherStoreCount Toko Lainnya)',
          'city': 'MULTIPLE CITIES',
          'month1': otherM1,
          'month2': otherM2,
          'month3': otherM3,
          'total': otherTotal,
          'average': otherTotal / 3.0,
          'txCount': otherTxCount,
          'isOther': true,
          'otherCount': otherStoreCount,
        });
      }

      setState(() {
        _rankingData = finalDisplayList;
        _totalPeriodSales = grandTotalAll;
        _totalStoreCount = allRankedStores.length;
        _top1StoreName = allRankedStores.isNotEmpty ? allRankedStores.first['alias'] : '-';
        _top1Amount = allRankedStores.isNotEmpty ? allRankedStores.first['total'] : 0.0;
      });
    } catch (e) {
      debugPrint("Error loading ranking data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
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
          // Top Header Row
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
                        child: const Icon(Icons.leaderboard_rounded, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Ranking Kacab - Omset Laporan ERP',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ranking Toko Peringkat 1 s/d 15 Berdasarkan ALIASTOKO & NOMINAL (Periode 3 Bulan), Peringkat 16+ Masuk Kategori OTHER',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  // Period Selector Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedPeriodKey,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 18),
                        items: const [
                          DropdownMenuItem(value: '3_MONTHS_RECENT', child: Text('3 Bulan Terakhir (Dynamic)')),
                          DropdownMenuItem(value: 'MEI_JULI_2026', child: Text('Mei - Juli 2026')),
                          DropdownMenuItem(value: 'APR_JUNI_2026', child: Text('April - Juni 2026')),
                          DropdownMenuItem(value: 'MAR_MEI_2026', child: Text('Maret - Mei 2026')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedPeriodKey = val;
                            });
                            _loadRankingData();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                    onPressed: _loadRankingData,
                    tooltip: 'Refresh Data Ranking',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Summary Stats Cards Row
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'TOTAL OMSET 3 BULAN',
                  value: currencyFormatter.format(_totalPeriodSales),
                  subtitle: 'Periode: $_month1Name - $_month3Name',
                  icon: Icons.payments_rounded,
                  accentColor: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'TOKO PERINGKAT #1 🥇',
                  value: _top1StoreName,
                  subtitle: 'Total Sales: ${currencyFormatter.format(_top1Amount)}',
                  icon: Icons.emoji_events_rounded,
                  accentColor: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatCard(
                  title: 'TOTAL TOKO AKTIF',
                  value: '$_totalStoreCount Toko',
                  subtitle: _totalStoreCount > 15
                      ? '15 Peringkat Atas + ${_totalStoreCount - 15} Kategori OTHER'
                      : 'Semua Toko Masuk Peringkat Utama',
                  icon: Icons.store_rounded,
                  accentColor: Colors.tealAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar & Info
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Cari Nama Toko / Alias / Kota...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 20),
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
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Main Data Table Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty
                    ? const Center(child: Text('Belum ada data omset Laporan ERP untuk periode 3 bulan ini.', style: TextStyle(color: Color(0xFF94A3B8))))
                    : Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowHeight: 48,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 56,
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                columns: [
                                  const DataColumn(label: Text('RANK', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('ALIAS TOKO', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('KOTA', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text(_month1Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text(_month2Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text(_month3Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('TOTAL 3 BULAN', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('RATA-RATA / BLN', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                  const DataColumn(label: Text('% KONTRIBUSI', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                                ],
                                rows: List.generate(filteredList.length, (idx) {
                                  final item = filteredList[idx];
                                  final rank = item['rank'] as int;
                                  final isOther = item['isOther'] == true;
                                  final total = item['total'] as double;
                                  final contribPercent = _totalPeriodSales > 0 ? (total / _totalPeriodSales * 100) : 0.0;

                                  Widget rankWidget;
                                  if (isOther) {
                                    rankWidget = Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purpleAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
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
                                        borderRadius: BorderRadius.circular(10),
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
                                      DataCell(Text(item['city'], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(item['month1']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(item['month2']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(item['month3']), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                      DataCell(Text(currencyFormatter.format(item['total']), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(Text(currencyFormatter.format(item['average']), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0F172A),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${contribPercent.toStringAsFixed(1)}%',
                                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
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
      padding: const EdgeInsets.all(16),
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
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.bold),
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
