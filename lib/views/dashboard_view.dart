import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/transaction_provider.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  
  // Ranking State
  List<Map<String, dynamic>> _rankData = [];
  
  // Classification State
  List<Map<String, dynamic>> _classData = [];

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _calculateMetrics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _calculateMetrics() async {
    setState(() {
      _loading = true;
    });

    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      
      // Calculate customer rankings based on last 3 months: 08-2026, 09-2026, 10-2026 (or dynamic)
      final summariesB1 = await trProvider.getMonthlyErpSummary('08-2026');
      final summariesB2 = await trProvider.getMonthlyErpSummary('09-2026');
      final summariesB3 = await trProvider.getMonthlyErpSummary('10-2026');

      // 1. Calculate Rankings
      final Map<String, List<double>> customerSales = {}; // name -> [aug, sept, oct]
      
      void addSalesData(List<Map<String, dynamic>> summaries, int monthIdx) {
        for (var record in summaries) {
          final name = record['customerName'] as String;
          final total = (record['totalIncome'] ?? 0.0).toDouble();
          if (!customerSales.containsKey(name)) {
            customerSales[name] = [0.0, 0.0, 0.0];
          }
          customerSales[name]![monthIdx] = total;
        }
      }

      addSalesData(summariesB1, 0);
      addSalesData(summariesB2, 1);
      addSalesData(summariesB3, 2);

      final List<Map<String, dynamic>> rawRank = [];
      customerSales.forEach((name, sales) {
        final total = sales[0] + sales[1] + sales[2];
        final avg = total / 3.0;
        rawRank.add({
          'name': name,
          'august': sales[0],
          'september': sales[1],
          'october': sales[2],
          'total': total,
          'average': avg,
        });
      });

      // Sort by average descending
      rawRank.sort((a, b) => b['average'].compareTo(a['average']));

      // Limit to top 15 and group rest as others (like VBA code!)
      final List<Map<String, dynamic>> finalRank = [];
      if (rawRank.length > 15) {
        finalRank.addAll(rawRank.sublist(0, 15));
        double otherAug = 0, otherSept = 0, otherOct = 0, otherTot = 0, otherAvg = 0;
        for (int i = 15; i < rawRank.length; i++) {
          otherAug += rawRank[i]['august'];
          otherSept += rawRank[i]['september'];
          otherOct += rawRank[i]['october'];
          otherTot += rawRank[i]['total'];
          otherAvg += rawRank[i]['average'];
        }
        finalRank.add({
          'name': 'Others',
          'august': otherAug,
          'september': otherSept,
          'october': otherOct,
          'total': otherTot,
          'average': otherAvg / (rawRank.length - 15),
        });
      } else {
        finalRank.addAll(rawRank);
      }

      // 2. Calculate Sales Classification (Laris vs Tidak Laris)
      // We aggregate product sales from all transactions or monthly erp summaries
      final Map<String, Map<String, dynamic>> productStats = {}; // prodName -> {qty, income}
      
      void addProductStats(List<Map<String, dynamic>> summaries) {
        for (var record in summaries) {
          final products = record['products'] as Map<dynamic, dynamic>? ?? {};
          products.forEach((prodId, val) {
            // Find name of product from transaction provider's transaction details or products list
            // For simplicity, we just aggregate key info
            final pcs = (val['pcs'] ?? 0.0).toDouble();
            final kg = (val['kg'] ?? 0.0).toDouble();
            
            if (!productStats.containsKey(prodId)) {
              productStats[prodId] = {'pcs': 0.0, 'kg': 0.0};
            }
            productStats[prodId]!['pcs'] = productStats[prodId]!['pcs'] + pcs;
            productStats[prodId]!['kg'] = productStats[prodId]!['kg'] + kg;
          });
        }
      }

      addProductStats(summariesB1);
      addProductStats(summariesB2);
      addProductStats(summariesB3);

      final List<Map<String, dynamic>> rawClass = [];
      productStats.forEach((prodId, stats) {
        final double pcs = stats['pcs'];
        // Replicate VBA classification criteria
        // Prediction (Laris if Qty >= 50 Pcs)
        final prediction = pcs >= 50.0 ? 'Laris' : 'Tidak Laris';
        // Manual Label: we mock subtotalVal >= 1,500,000 as "Laris". We can approximate it!
        // We look up product details from product list
        final productsList = trProvider.transactions.expand((t) => t.items).toList();
        final match = productsList.firstWhere((i) => i.productId == prodId, orElse: () => productsList.isNotEmpty ? productsList.first : productsList.first);
        final price = match.price;
        final estIncome = pcs * price;
        final labelManual = estIncome >= 1500000.0 ? 'Laris' : 'Tidak Laris';

        rawClass.add({
          'productId': prodId,
          'name': match.productName,
          'pcs': pcs,
          'income': estIncome,
          'prediction': prediction,
          'labelManual': labelManual,
        });
      });

      setState(() {
        _rankData = finalRank;
        _classData = rawClass;
      });
    } catch (e) {
      debugPrint("Error calculating dashboard metrics: $e");
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF1E293B),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF38BDF8),
            labelColor: const Color(0xFF38BDF8),
            unselectedLabelColor: const Color(0xFF94A3B8),
            tabs: const [
              Tab(text: 'Peringkat Pelanggan (3 Bulan)'),
              Tab(text: 'Klasifikasi Produk (Laris / Tidak)'),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRankTab(),
                _buildClassificationTab(),
              ],
            ),
    );
  }

  // Customers Sales Rank Tab
  Widget _buildRankTab() {
    if (_rankData.isEmpty) {
      return const Center(child: Text('Tidak ada data peringkat.', style: TextStyle(color: Color(0xFF64748B))));
    }

    final barGroups = List.generate(_rankData.length.clamp(0, 10), (i) {
      final val = _rankData[i]['average'] as double;
      // Convert to Millions for readable chart height
      final avgMillions = val / 1000000.0;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: avgMillions,
            color: const Color(0xFF38BDF8),
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: avgMillions * 1.2,
              color: const Color(0xFF334155),
            ),
          )
        ],
      );
    });

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          // Chart Section
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grafik Rata-rata Penjualan Pelanggan (Juta Rp)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: barGroups.isEmpty ? 10 : barGroups.map((g) => g.barRods[0].toY).reduce((a, b) => a > b ? a : b) * 1.2,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (group) => const Color(0xFF0F172A),
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final name = _rankData[group.x]['name'];
                              final val = _rankData[group.x]['average'] as double;
                              return BarTooltipItem(
                                '$name\n${_rupiahFormatter.format(val)}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx >= 0 && idx < _rankData.length) {
                                  final name = _rankData[idx]['name'] as String;
                                  final shortName = name.length > 5 ? name.substring(0, 5) : name;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(shortName, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9)),
                                  );
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: barGroups,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Table Section
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                    headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('No')),
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Agustus')),
                      DataColumn(label: Text('September')),
                      DataColumn(label: Text('Oktober')),
                      DataColumn(label: Text('Total')),
                      DataColumn(label: Text('Rata-rata')),
                    ],
                    rows: List.generate(_rankData.length, (i) {
                      final item = _rankData[i];
                      return DataRow(
                        cells: [
                          DataCell(Text((i + 1).toString(), style: const TextStyle(color: Color(0xFF64748B)))),
                          DataCell(Text(item['name'], style: const TextStyle(color: Colors.white))),
                          DataCell(Text(_rupiahFormatter.format(item['august']), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DataCell(Text(_rupiahFormatter.format(item['september']), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DataCell(Text(_rupiahFormatter.format(item['october']), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DataCell(Text(_rupiahFormatter.format(item['total']), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                          DataCell(Text(_rupiahFormatter.format(item['average']), style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold))),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  // Sales Classification Tab
  Widget _buildClassificationTab() {
    if (_classData.isEmpty) {
      return const Center(child: Text('Tidak ada data klasifikasi.', style: TextStyle(color: Color(0xFF64748B))));
    }

    final int totalCount = _classData.length;
    final int larisCount = _classData.where((item) => item['prediction'] == 'Laris').length;
    final int tidakLarisCount = totalCount - larisCount;

    // Calculate prediction accuracy (where prediction matches manual label)
    final int correctPredictions = _classData.where((item) => item['prediction'] == item['labelManual']).length;
    final double accuracy = (correctPredictions / totalCount) * 100.0;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Row(
            children: [
              // Pie Chart proportion
              Expanded(
                flex: 2,
                child: Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 36,
                            sections: [
                              PieChartSectionData(
                                value: larisCount.toDouble(),
                                title: '${((larisCount/totalCount)*100).toStringAsFixed(0)}%',
                                color: Colors.greenAccent,
                                radius: 48,
                                titleStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                              PieChartSectionData(
                                value: tidakLarisCount.toDouble(),
                                title: '${((tidakLarisCount/totalCount)*100).toStringAsFixed(0)}%',
                                color: Colors.redAccent,
                                radius: 48,
                                titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Chart Legend
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendRow('Laris (>= 50 Pcs)', Colors.greenAccent, larisCount),
                          const SizedBox(height: 8),
                          _buildLegendRow('Tidak Laris (< 50)', Colors.redAccent, tidakLarisCount),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              
              // Accuracy Card
              Expanded(
                flex: 1,
                child: Container(
                  height: 200,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 36),
                      const SizedBox(height: 12),
                      const Text(
                        'AKURASI PREDIKSI',
                        style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${accuracy.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                      ),
                      Text(
                        'Sesuai label manual: $correctPredictions/$totalCount produk',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Datatable of Classification List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                    headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('Kode')),
                      DataColumn(label: Text('Nama Produk')),
                      DataColumn(label: Text('Total Pcs (3 Bln)'), numeric: true),
                      DataColumn(label: Text('Omset Estimasi'), numeric: true),
                      DataColumn(label: Text('Prediksi (Qty)')),
                      DataColumn(label: Text('Label Manual (Omset)')),
                    ],
                    rows: _classData.map((item) {
                      final predLaris = item['prediction'] == 'Laris';
                      final manualLaris = item['labelManual'] == 'Laris';
                      return DataRow(
                        cells: [
                          DataCell(Text(item['productId'], style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                          DataCell(Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DataCell(Text(item['pcs'].toStringAsFixed(0), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(_rupiahFormatter.format(item['income']), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: predLaris ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['prediction'],
                                style: TextStyle(
                                  color: predLaris ? Colors.greenAccent : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: manualLaris ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item['labelManual'],
                                style: TextStyle(
                                  color: manualLaris ? Colors.greenAccent : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendRow(String title, Color color, int count) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(
          '$title: ',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
        Text(
          '$count Item',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
      ],
    );
  }
}
