import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';

class RankingKacabView extends StatefulWidget {
  const RankingKacabView({super.key});

  @override
  State<RankingKacabView> createState() => _RankingKacabViewState();
}

class _RankingKacabViewState extends State<RankingKacabView> {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _isLoading = false;
  List<Map<String, dynamic>> _rankingData = [];

  @override
  void initState() {
    super.initState();
    _loadRankingData();
  }

  Future<void> _loadRankingData() async {
    setState(() => _isLoading = true);
    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final transactions = trProvider.transactions;

      final Map<String, Map<String, double>> outletMonthlySales = {};

      final now = DateTime.now();
      final month1Key = DateFormat('MM-yyyy').format(DateTime(now.year, now.month - 2, 1));
      final month2Key = DateFormat('MM-yyyy').format(DateTime(now.year, now.month - 1, 1));
      final month3Key = DateFormat('MM-yyyy').format(now);

      for (var tr in transactions) {
        final custName = tr.customerName.isNotEmpty ? tr.customerName : 'Umum';
        final mKey = DateFormat('MM-yyyy').format(tr.date);

        outletMonthlySales.putIfAbsent(custName, () => {
          month1Key: 0.0,
          month2Key: 0.0,
          month3Key: 0.0,
        });

        if (outletMonthlySales[custName]!.containsKey(mKey)) {
          outletMonthlySales[custName]![mKey] = (outletMonthlySales[custName]![mKey] ?? 0.0) + tr.grandTotal;
        } else {
          outletMonthlySales[custName]![mKey] = (outletMonthlySales[custName]![mKey] ?? 0.0) + tr.grandTotal;
        }
      }

      final List<Map<String, dynamic>> rankedList = [];
      outletMonthlySales.forEach((outlet, months) {
        final m1 = months[month1Key] ?? 0.0;
        final m2 = months[month2Key] ?? 0.0;
        final m3 = months[month3Key] ?? 0.0;
        final total = m1 + m2 + m3;
        final avg = total / 3.0;

        rankedList.add({
          'outlet': outlet,
          'month1': m1,
          'month2': m2,
          'month3': m3,
          'total': total,
          'average': avg,
        });
      });

      rankedList.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));

      setState(() {
        _rankingData = rankedList;
      });
    } catch (e) {
      debugPrint("Error loading ranking data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month1Name = DateFormat('MMMM yyyy', 'id_ID').format(DateTime(now.year, now.month - 2, 1));
    final month2Name = DateFormat('MMMM yyyy', 'id_ID').format(DateTime(now.year, now.month - 1, 1));
    final month3Name = DateFormat('MMMM yyyy', 'id_ID').format(now);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Laporan Weekly & Performance Outlet (Kacab)',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Cabang: JAWA TENGAH | Ranking Omset Penjualan 3 Bulan Terakhir',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
                onPressed: _loadRankingData,
                tooltip: 'Refresh Data',
              ),
            ],
          ),
          const SizedBox(height: 20),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rankingData.isEmpty
                    ? const Center(child: Text('Belum ada data transaksi untuk laporan ranking.', style: TextStyle(color: Color(0xFF94A3B8))))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: DataTable(
                            headingRowHeight: 52,
                            dataRowMaxHeight: 56,
                            columns: [
                              const DataColumn(label: Text('RANK', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('NAMA OUTLET / TOKO', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text(month1Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text(month2Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text(month3Name.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('TOTAL 3 BULAN', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              const DataColumn(label: Text('RATA-RATA / BULAN', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                            ],
                            rows: List.generate(_rankingData.length, (idx) {
                              final item = _rankingData[idx];
                              final rank = idx + 1;
                              Color rankColor = Colors.white;
                              if (rank == 1) rankColor = Colors.amber;
                              if (rank == 2) rankColor = Colors.grey.shade300;
                              if (rank == 3) rankColor = Colors.amber.shade800;

                              return DataRow(
                                cells: [
                                  DataCell(
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: rank <= 3 ? rankColor.withOpacity(0.2) : Colors.white10,
                                      child: Text(
                                        '$rank',
                                        style: TextStyle(color: rankColor, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(item['outlet'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataCell(Text(currencyFormatter.format(item['month1']), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(currencyFormatter.format(item['month2']), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(currencyFormatter.format(item['month3']), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(currencyFormatter.format(item['total']), style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                  DataCell(Text(currencyFormatter.format(item['average']), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
