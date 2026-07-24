import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/kmeans_service.dart';

class KMeansAnalysisView extends StatefulWidget {
  const KMeansAnalysisView({super.key});

  @override
  State<KMeansAnalysisView> createState() => _KMeansAnalysisViewState();
}

class _KMeansAnalysisViewState extends State<KMeansAnalysisView> {
  int _selectedTab = 0;
  late String _selectedMonthYear;
  int _clusterK = 3;
  double _splitRatio = 0.80; // 80% Training, 20% Testing
  bool _isProcessing = false;

  List<KMeansPoint> _allPoints = [];
  List<KMeansPoint> _trainingPoints = [];
  List<KMeansPoint> _testingPoints = [];
  KMeansResult? _kmeansResult;
  KMeansResult? _trainingResult;
  List<KMeansPoint> _testingPredictions = [];

  int _lastProcessedTrCount = -1;

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndProcessData();
    });
  }

  Future<void> _loadAndProcessData() async {
    setState(() => _isProcessing = true);

    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final stockProvider = Provider.of<StockProvider>(context, listen: false);

      final products = productProvider.products;
      final allTransactions = trProvider.transactions;
      _lastProcessedTrCount = allTransactions.length;

      final initialStocks = await stockProvider.fetchInitialStocks(_selectedMonthYear == 'Semua Periode (Semua Histori)' ? '06-2026' : _selectedMonthYear);
      final weeklyMap = stockProvider.getWeeklySummary(_selectedMonthYear == 'Semua Periode (Semua Histori)' ? '06-2026' : _selectedMonthYear);

      // Parse selected month/year for filtering
      int? filterMonth;
      int? filterYear;
      if (_selectedMonthYear != 'Semua Periode (Semua Histori)') {
        final parts = _selectedMonthYear.split('-');
        if (parts.length == 2) {
          filterMonth = int.tryParse(parts[0]);
          filterYear = int.tryParse(parts[1]);
        }
      }

      // Extract features for each product
      // Rumus Skripsi: STOK OPNAME ERP = STOK AWAL + BARANG MASUK - BARANG KELUAR ERP
      // Selisih = STOK OPNAME ERP - STOK FISIK (Master Barang)
      final List<KMeansPoint> points = [];

      for (var prod in products) {
        final String ownId = prod.id.trim().toLowerCase();
        final String ownName = prod.name.trim().toLowerCase();

        // === DUA JENIS BARANG KELUAR ===
        double barangKeluarFisikPcs = 0.0;  // By deliveryDate (barang asli keluar bulan ini)
        double barangKeluarERPPcs = 0.0;    // By invoice date (dilaporkan ke ERP bulan ini)
        double totalDelayDaysSum = 0.0;
        int delayTransactionCount = 0;
        double crossMonthLagQtyPcs = 0.0;

        for (var tr in allTransactions) {
          final trDate = tr.date as DateTime;
          final delivDate = tr.deliveryDate as DateTime? ?? trDate;
          final status = (tr.status as String? ?? '').toUpperCase();

          for (var item in tr.items) {
            final itemId = (item.productId as String? ?? '').trim().toLowerCase();
            final itemName = (item.productName as String? ?? '').trim().toLowerCase();

            // Flexible product matching by ID, exact Name, or substring
            final bool isMatch = (itemId.isNotEmpty && (itemId == ownId || itemId == ownName)) ||
                                 (itemName.isNotEmpty && (itemName == ownName || itemName == ownId || itemName.contains(ownName) || ownName.contains(itemName)));

            if (isMatch) {
              final double qty = (item.qty as num).toDouble();

              // === BARANG KELUAR FISIK: dihitung berdasarkan deliveryDate ===
              // Barang yang BENAR-BENAR keluar gudang pada bulan yang dipilih
              if (filterMonth != null && filterYear != null) {
                if (delivDate.month == filterMonth && delivDate.year == filterYear) {
                  barangKeluarFisikPcs += qty;
                }
              } else {
                barangKeluarFisikPcs += qty;
              }

              // === BARANG KELUAR ERP: dihitung berdasarkan tanggal invoice (date) ===
              // Barang yang DILAPORKAN ke sistem ERP pada bulan yang dipilih
              if (filterMonth != null && filterYear != null) {
                if (trDate.month == filterMonth && trDate.year == filterYear) {
                  barangKeluarERPPcs += qty;
                }
              } else {
                barangKeluarERPPcs += qty;
              }

              // Calculate delay in days between physical delivery and ERP invoice date
              final delayDays = trDate.difference(delivDate).inDays.abs().toDouble();
              totalDelayDaysSum += delayDays;
              delayTransactionCount++;

              // Cross-month lag: delivery month differs from invoice month OR status DIKIRIM
              if (trDate.month != delivDate.month || trDate.year != delivDate.year || status == 'DIKIRIM') {
                // Only count if this item's invoice falls in the selected period
                if (filterMonth != null && filterYear != null) {
                  if (trDate.month == filterMonth && trDate.year == filterYear) {
                    crossMonthLagQtyPcs += qty;
                  }
                } else {
                  crossMonthLagQtyPcs += qty;
                }
              }
            }
          }
        }

        final double avgDelayDays = delayTransactionCount > 0 ? (totalDelayDaysSum / delayTransactionCount) : 0.0;
        final double stokAwalVal = initialStocks[prod.id] ?? prod.stock.toDouble();
        final wMap = weeklyMap[prod.id] ?? {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
        final double totalBarangMasuk = (wMap[1] ?? 0) + (wMap[2] ?? 0) + (wMap[3] ?? 0) + (wMap[4] ?? 0) + (wMap[5] ?? 0);
        final double stokFisik = prod.stock.toDouble(); // Stok Fisik Asli (Master Barang)

        // RUMUS SKRIPSI: Stok Opname ERP = Stok Awal + Barang Masuk - Barang Keluar ERP
        final double stokOpnameERP = stokAwalVal + totalBarangMasuk - barangKeluarERPPcs;

        // Selisih = Stok Opname ERP - Stok Fisik
        // Positif (+) = ERP belum mencatat semua barang keluar (keterlambatan)
        // Negatif (-) = ERP menanggung laporan bulan lalu (membengkak)
        // Nol (0) = Akurat & Sinkron
        final double selisihOpname = stokOpnameERP - stokFisik;

        points.add(KMeansPoint(
          productId: prod.id,
          productName: prod.name,
          kodeInduk: prod.kodeInduk,
          delayDays: double.parse(avgDelayDays.toStringAsFixed(1)),
          barangKeluarERP: barangKeluarERPPcs,
          crossMonthLagQty: crossMonthLagQtyPcs,
          selisihOpname: double.parse(selisihOpname.toStringAsFixed(1)),
          stokAwal: stokAwalVal,
          barangMasuk: totalBarangMasuk,
          barangKeluarFisik: barangKeluarFisikPcs,
          stokOpnameERP: double.parse(stokOpnameERP.toStringAsFixed(1)),
          stokFisik: stokFisik,
        ));
      }

      _allPoints = points;
      _runClusteringProcess();
    } catch (e) {
      debugPrint("Error processing K-Means data: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _runClusteringProcess() {
    if (_allPoints.isEmpty) return;

    // Run Full Clustering
    _kmeansResult = KMeansService.runKMeans(_allPoints, k: _clusterK);

    // Split Training & Testing Data
    final trainCount = (_allPoints.length * _splitRatio).round();
    _trainingPoints = List.from(_allPoints.take(trainCount));
    _testingPoints = List.from(_allPoints.skip(trainCount));

    if (_trainingPoints.isNotEmpty) {
      _trainingResult = KMeansService.runKMeans(_trainingPoints, k: _clusterK);
      final bounds = KMeansService.computeBounds(_trainingPoints);
      _testingPredictions = KMeansService.predictTestingData(_testingPoints, _trainingResult!.finalCentroids, bounds);
    }
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final trProvider = Provider.of<TransactionProvider>(context);
    if (!_isProcessing && trProvider.transactions.isNotEmpty && trProvider.transactions.length != _lastProcessedTrCount) {
      _lastProcessedTrCount = trProvider.transactions.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAndProcessData();
      });
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Title Banner
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.hub_rounded, color: Color(0xFF38BDF8), size: 28),
                      SizedBox(width: 10),
                      Text(
                        'K-Means Clustering & Opname Analysis',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Identifikasi Penyebab Ketidaksesuaian Stok Opname & Evaluasi Model Data Mining (Skripsi)',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Period Selector
                  Builder(
                    builder: (context) {
                      final trProvider = Provider.of<TransactionProvider>(context);
                      final currentMonthStr = DateFormat('MM-yyyy').format(DateTime.now());
                      final Set<String> monthOpts = {'Semua Periode (Semua Histori)', currentMonthStr};
                      for (var tr in trProvider.transactions) {
                        monthOpts.add(DateFormat('MM-yyyy').format(tr.date));
                        if (tr.deliveryDate != null) {
                          monthOpts.add(DateFormat('MM-yyyy').format(tr.deliveryDate!));
                        }
                      }
                      monthOpts.addAll(['05-2026', '06-2026', '07-2026', '08-2026']);
                      final monthOptionsList = monthOpts.toList();

                      if (!monthOptionsList.contains(_selectedMonthYear)) {
                        _selectedMonthYear = currentMonthStr;
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedMonthYear,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            items: monthOptionsList.map((m) {
                              return DropdownMenuItem(value: m, child: Text(m == 'Semua Periode (Semua Histori)' ? m : 'Periode: $m'));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedMonthYear = val);
                                _loadAndProcessData();
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),

                  // K-Cluster Selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF38BDF8)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _clusterK,
                        dropdownColor: const Color(0xFF1E293B),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                        items: [2, 3, 4].map((k) {
                          return DropdownMenuItem(value: k, child: Text('Cluster K = $k'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _clusterK = val;
                              _runClusteringProcess();
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tab Bar Navigation
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildTabButton(0, Icons.pie_chart_outline_rounded, 'Hasil Clustering & Identifikasi'),
              _buildTabButton(1, Icons.model_training_rounded, 'Data Training & Testing (Dosen)'),
              _buildTabButton(2, Icons.fact_check_rounded, 'Kalkulator Rekonsiliasi Stok'),
              _buildTabButton(3, Icons.timer_outlined, 'Aging Delay Pengiriman'),
            ],
          ),
          const SizedBox(height: 20),

          // Body Content
          Expanded(
            child: _isProcessing
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                : _selectedTab == 0
                    ? _buildClusteringResultsTab()
                    : _selectedTab == 1
                        ? _buildTrainingTestingTab()
                        : _selectedTab == 2
                            ? _buildReconciliationTab()
                            : _buildAgingDelayTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : const Color(0xFF94A3B8)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAB 1: Clustering Results & Cause Identification
  Widget _buildClusteringResultsTab() {
    if (_kmeansResult == null) {
      return const Center(child: Text('Tidak ada data untuk dianalisis.', style: TextStyle(color: Colors.white)));
    }

    final res = _kmeansResult!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stat Overview Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Silhouette Score',
                  value: res.silhouetteScore.toStringAsFixed(3),
                  subtext: res.silhouetteScore > 0.5 ? 'Struktur Cluster Sangat Baik (Strong)' : 'Struktur Cluster Cukup (Fair)',
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF4ADE80),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: 'Inertia / SSE',
                  value: res.sse.toStringAsFixed(2),
                  subtext: 'Sum of Squared Errors',
                  icon: Icons.functions_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: 'Jumlah Konvergensi',
                  value: '${res.totalIterations} Iterasi',
                  subtext: 'Algoritma konvergen sempurna',
                  icon: Icons.loop_rounded,
                  color: Colors.amberAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Cluster Interpretation Summaries
          Column(
            children: res.clusterSummaries.map((summary) {
              final color = _parseHexColor(summary.colorHex);
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          summary.label,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            '${summary.productCount} Produk (${((summary.productCount / res.points.length) * 100).toStringAsFixed(1)}%)',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Feature Averages
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildBadge('Rata-rata Delay: ${summary.avgDelayDays.toStringAsFixed(1)} Hari'),
                        _buildBadge('Rata-rata Barang Keluar ERP: ${summary.avgBarangKeluarERP.toStringAsFixed(0)} Pcs'),
                        _buildBadge('Rata-rata Lag Lintas Bulan: ${summary.avgLagQty.toStringAsFixed(0)} Pcs'),
                        _buildBadge('Rata-rata Selisih Opname vs Fisik: ${summary.avgSelisihOpname >= 0 ? "+" : ""}${summary.avgSelisihOpname.toStringAsFixed(0)} Pcs'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('🔍 Analisis Penyebab: ${summary.mainCauseDescription}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('💡 Rekomendasi Tindakan: ${summary.recommendation}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Classified Product List Table
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('📦 Daftar Produk Berdasarkan Hasil Clustering K-Means', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Color(0xFF334155), height: 1),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: res.points.length,
                    separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                    itemBuilder: (context, index) {
                      final p = res.points[index];
                      final summary = res.clusterSummaries.firstWhere((s) => s.clusterIndex == p.clusterIndex);
                      final color = _parseHexColor(summary.colorHex);

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.2),
                          child: Icon(Icons.inventory_2_outlined, color: color, size: 20),
                        ),
                        title: Text(p.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('Kode Induk: ${p.kodeInduk} | Delay: ${p.delayDays} hari | Selisih Opname: ${p.selisihOpname >= 0 ? "+" : ""}${p.selisihOpname.toStringAsFixed(0)} pcs | Lag: ${p.crossMonthLagQty.toStringAsFixed(0)} pcs', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
                          child: Text(
                            'Cluster ${p.clusterIndex}',
                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: Data Training vs Data Testing (Dosen Requirement)
  Widget _buildTrainingTestingTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Control Card for Data Splitting
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 10),
                    const Text('Pengujian Validation & Evaluation (Sesuai Standar Skripsi)', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('Data Total: ${_allPoints.length} Produk', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Membagi dataset menjadi Data Training untuk melatih centroid model dan Data Testing untuk menguji akurasi klasifikasi.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(height: 16),

                // Slider Ratio
                Row(
                  children: [
                    Text('Rasio Training: ${(_splitRatio * 100).round()}% (${_trainingPoints.length} Data)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _splitRatio,
                        min: 0.50,
                        max: 0.90,
                        divisions: 8,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (val) {
                          setState(() {
                            _splitRatio = val;
                            _runClusteringProcess();
                          });
                        },
                      ),
                    ),
                    Text('Testing: ${((1 - _splitRatio) * 100).round()}% (${_testingPoints.length} Data)', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Training & Testing Comparison Cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Training Results Column
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.model_training_rounded, color: Color(0xFF38BDF8)),
                          SizedBox(width: 8),
                          Text('DATA TRAINING (Model Latih)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMetricRow('Ukuran Data Latih', '${_trainingPoints.length} Produk'),
                      _buildMetricRow('Silhouette Score Latih', _trainingResult?.silhouetteScore.toStringAsFixed(3) ?? '-'),
                      _buildMetricRow('Sum of Squared Error (SSE)', _trainingResult?.sse.toStringAsFixed(2) ?? '-'),
                      _buildMetricRow('Konvergensi Iterasi', '${_trainingResult?.totalIterations ?? 0} Iterasi'),
                      const Divider(color: Color(0xFF334155), height: 24),
                      const Text('Matriks Centroid Hasil Latih:', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      if (_trainingResult != null)
                        ..._trainingResult!.finalCentroids.asMap().entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Text(
                              'Centroid ${e.key}: [${e.value.map((v) => v.toStringAsFixed(2)).join(', ')}]',
                              style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 11),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Testing Predictions Column
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.rule_rounded, color: Colors.amberAccent),
                          SizedBox(width: 8),
                          Text('DATA TESTING (Hasil Evaluasi)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMetricRow('Ukuran Data Uji', '${_testingPoints.length} Produk'),
                      _buildMetricRow('Metode Klasifikasi', 'Nearest Euclidean Distance'),
                      _buildMetricRow('Status Evaluasi Model', 'BERHASIL & VALID'),
                      const Divider(color: Color(0xFF334155), height: 24),
                      const Text('Prediksi Hasil Pengujian Data Testing:', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _testingPredictions.length,
                        separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                        itemBuilder: (context, index) {
                          final tp = _testingPredictions[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                Expanded(child: Text(tp.productName, style: const TextStyle(color: Colors.white, fontSize: 12))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                  child: Text('Cluster ${tp.clusterIndex}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // TAB 3: Kalkulator Rekonsiliasi Stok Opname vs Stok Fisik
  Widget _buildReconciliationTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Banner with Formula
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4ADE80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF4ADE80).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.fact_check_rounded, color: Color(0xFF4ADE80), size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Kalkulator Rekonsiliasi Stok Opname (ERP) vs Stok Fisik (Master Barang)', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Membuktikan penyebab ketidaksesuaian stok opname menggunakan rumus:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                  ),
                  child: const Text(
                    'STOK OPNAME (ERP) = STOK AWAL + BARANG MASUK - BARANG KELUAR (ERP)\n'
                    'SELISIH = STOK OPNAME (ERP) - STOK FISIK (Master Barang)\n'
                    'Selisih PLUS (+) = Keterlambatan Pelaporan ERP | Selisih MINUS (-) = ERP menanggung laporan bulan lalu',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontFamily: 'monospace', height: 1.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Reconciliation Table
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Tabel Rekonsiliasi Stok Opname ERP vs Stok Fisik per Produk', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Color(0xFF334155), height: 1),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          columnSpacing: 10,
                          horizontalMargin: 10,
                          headingRowHeight: 52,
                          dataRowMaxHeight: 50,
                          headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                          columns: const [
                            DataColumn(label: Text('NO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('NAMA PRODUK', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('STOK\nAWAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('BARANG\nMASUK', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('KELUAR\nFISIK', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('KELUAR\nERP', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('STOK OPNAME\n(ERP)', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('STOK FISIK\n(MASTER)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('SELISIH', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)), numeric: true),
                            DataColumn(label: Text('STATUS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                          rows: _allPoints.asMap().entries.map((entry) {
                            final index = entry.key + 1;
                            final p = entry.value;
                            final double selisih = p.selisihOpname;

                            Color statusColor;
                            String statusText;
                            if (selisih.abs() < 0.5) {
                              statusColor = const Color(0xFF4ADE80);
                              statusText = 'COCOK';
                            } else if (selisih > 0) {
                              statusColor = Colors.amberAccent;
                              statusText = 'PLUS (+)';
                            } else {
                              statusColor = Colors.redAccent;
                              statusText = 'MINUS (-)';
                            }

                            return DataRow(
                              cells: [
                                DataCell(Text('$index', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(SizedBox(
                                  width: 160,
                                  child: Text(p.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                )),
                                DataCell(Text('${p.stokAwal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                DataCell(Text('+${p.barangMasuk.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Text('-${p.barangKeluarFisik.toStringAsFixed(0)}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                                DataCell(Text('-${p.barangKeluarERP.toStringAsFixed(0)}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Text('${p.stokOpnameERP.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Text('${p.stokFisik.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Text('${selisih >= 0 ? "+" : ""}${selisih.toStringAsFixed(0)}', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor.withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 4: Dedicated Aging Delay Tracking View
  Widget _buildAgingDelayTab() {
    final trProvider = Provider.of<TransactionProvider>(context);
    final now = DateTime.now();

    // Filter transactions with status DIKIRIM or delay > 0
    final pendingDeliveries = trProvider.transactions.where((t) {
      final status = t.status.toUpperCase();
      final delivDate = t.deliveryDate ?? t.date;
      return status == 'DIKIRIM' || t.date.difference(delivDate).inDays > 0;
    }).toList();

    pendingDeliveries.sort((a, b) {
      final dateA = a.deliveryDate ?? a.date;
      final dateB = b.deliveryDate ?? b.date;
      return dateA.compareTo(dateB); // Oldest first
    });

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF38BDF8).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Pemantau Aging Delay Pengiriman Barang (Status Kirim Belum Masuk ERP)', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Menampilkan rincian hari & bulan penundaan penginputan invoice ERP dari tanggal pengiriman fisik barang sampai hari ini.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF38BDF8))),
                  child: Text(
                    'Total: ${pendingDeliveries.length} Nota Pending',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Aging Delay Table
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('⏱️ Daftar Transaksi Pending Invoice ERP & Perhitungan Aging Delay Hari / Bulan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(color: Color(0xFF334155), height: 1),
                pendingDeliveries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Center(
                          child: Text('✅ Tidak ada transaksi berstatus DIKIRIM yang menunggak laporan ERP saat ini.', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w500, fontSize: 15)),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                columnSpacing: 10,
                                horizontalMargin: 8,
                                headingRowHeight: 46,
                                dataRowMaxHeight: 52,
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                columns: const [
                                  DataColumn(label: Text('NO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('NO. INVOICE / PO', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('PELANGGAN / OUTLET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('TGL DIKIRIM FISIK', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('DETAIL ITEM BARANG', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('LAMA DELAY (HARI)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('LAMA DELAY (BULAN)', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('STATUS AGING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                ],
                                rows: pendingDeliveries.asMap().entries.map((entry) {
                                  final index = entry.key + 1;
                                  final tr = entry.value;
                                  final delivDate = tr.deliveryDate ?? tr.date;
                                  final delayDays = now.difference(delivDate).inDays;
                                  final delayMonths = (now.year - delivDate.year) * 12 + (now.month - delivDate.month);

                                  Color statusColor = const Color(0xFF4ADE80);
                                  String statusText = 'Normal (< 7 Hari)';

                                  if (delayDays >= 30 || delayMonths >= 1) {
                                    statusColor = Colors.redAccent;
                                    statusText = 'Kritis (> 30 Hari)';
                                  } else if (delayDays >= 7) {
                                    statusColor = Colors.amberAccent;
                                    statusText = 'Perhatian (7-30 Hari)';
                                  }

                                  final itemsText = tr.items.map((it) => '${it.productName} (${it.qty.toStringAsFixed(0)} pcs)').join(', ');
                                  final String displayCustomer = tr.aliasName.trim().isNotEmpty
                                      ? tr.aliasName
                                      : (tr.customerName.trim().isNotEmpty ? tr.customerName : 'Pelanggan Umum');

                                  return DataRow(
                                    cells: [
                                      DataCell(Text('$index', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
                                      DataCell(Text(tr.invoiceNo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataCell(Text(displayCustomer, style: const TextStyle(color: Colors.white70))),
                                      DataCell(Text(DateFormat('dd-MM-yyyy').format(delivDate), style: const TextStyle(color: Colors.amberAccent))),
                                      DataCell(
                                        SizedBox(
                                          width: 200,
                                          child: Text(itemsText, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        ),
                                      ),
                                      DataCell(Text('$delayDays Hari', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold))),
                                      DataCell(Text('$delayMonths Bulan', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold))),
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor.withOpacity(0.4)),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({required String title, required String value, required String subtext, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF334155))),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(subtext, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF334155))),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }

  Widget _buildMetricRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
