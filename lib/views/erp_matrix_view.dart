import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/stock_provider.dart';
import '../models/customer.dart';

class ErpMatrixView extends StatefulWidget {
  const ErpMatrixView({super.key});

  @override
  State<ErpMatrixView> createState() => _ErpMatrixViewState();
}

class _ErpMatrixViewState extends State<ErpMatrixView> {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormatter = DateFormat('dd-MM-yyyy');

  String _selectedMonthYear = "";
  Customer? _selectedCustomer;
  bool _showPcs = true; // true = Pcs, false = Kg
  List<Map<String, dynamic>> _erpRecords = [];
  bool _loadingErp = false;

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
    _loadErpData();
  }

  Future<void> _loadErpData() async {
    setState(() => _loadingErp = true);

    try {
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final stockProvider = Provider.of<StockProvider>(context, listen: false);

      await stockProvider.fetchStockEntries();
      final data = await trProvider.getMonthlyErpSummary(_selectedMonthYear);

      setState(() {
        _erpRecords = data;
      });
    } catch (e) {
      debugPrint("Error loading ERP summary: $e");
    } finally {
      setState(() => _loadingErp = false);
    }
  }

  List<String> _getMonthOptions() {
    final List<String> options = [];
    final now = DateTime.now();
    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      options.add(DateFormat('MM-yyyy').format(date));
    }
    if (!options.contains('05-2026')) options.add('05-2026');
    if (!options.contains('07-2026')) options.add('07-2026');
    if (!options.contains('08-2026')) options.add('08-2026');
    return options.toSet().toList();
  }

  Future<void> _printPdfErp() async {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final products = productProvider.products;
    final weeklyMap = stockProvider.getWeeklySummary(_selectedMonthYear);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'LAPORAN MENU ERP & STOK MASUK CABANG - PERIODE $_selectedMonthYear',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['Produk', 'Stock Before', 'Sample BONUS', 'Total Keluar', 'M1', 'M2', 'M3', 'M4', 'M5', 'Total Masuk', 'Stock Akhir'],
                data: List.generate(products.length, (idx) {
                  final prod = products[idx];
                  final wMap = weeklyMap[prod.id] ?? {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
                  final m1 = wMap[1] ?? 0.0;
                  final m2 = wMap[2] ?? 0.0;
                  final m3 = wMap[3] ?? 0.0;
                  final m4 = wMap[4] ?? 0.0;
                  final m5 = wMap[5] ?? 0.0;
                  final totalMasuk = m1 + m2 + m3 + m4 + m5;

                  int totalSoldPcs = 0;
                  for (var r in _erpRecords) {
                    final prodSales = r['products'] as Map<String, dynamic>?;
                    if (prodSales != null && prodSales.containsKey(prod.id)) {
                      totalSoldPcs += (prodSales[prod.id] as num).toInt();
                    }
                  }

                  final stockBefore = prod.stock;
                  final totalKeluar = totalSoldPcs.toDouble();
                  final sampleBonus = 0.0;
                  final stockAkhir = stockBefore + totalMasuk - totalKeluar - sampleBonus;

                  return [
                    prod.name,
                    '${stockBefore.toInt()}',
                    '${sampleBonus.toInt()}',
                    '${totalKeluar.toInt()}',
                    '${m1.toInt()}',
                    '${m2.toInt()}',
                    '${m3.toInt()}',
                    '${m4.toInt()}',
                    '${m5.toInt()}',
                    '${totalMasuk.toInt()}',
                    '${stockAkhir.toInt()}',
                  ];
                }),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'laporan_erp_stok_$_selectedMonthYear.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);
    final customerProvider = Provider.of<CustomerProvider>(context);
    final stockProvider = Provider.of<StockProvider>(context);

    final products = productProvider.products;
    final weeklyMap = stockProvider.getWeeklySummary(_selectedMonthYear);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Stok ERP & Opname Cabang',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Monitoring Pergerakan Stok Awal, Influx Masuk Mingguan (M1-M5), & Saldo Akhir',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      productProvider.fetchProducts();
                      _loadErpData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stok awal berhasil diperbarui!'), backgroundColor: Colors.teal),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Update Stok Awal', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _printPdfErp,
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Cetak ERP PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Control Bar: Periode, Customer Filter, Pcs/Kg Toggle
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                const Text('Periode:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedMonthYear,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: _getMonthOptions().map((m) {
                    return DropdownMenuItem<String>(value: m, child: Text(m));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedMonthYear = val);
                      _loadErpData();
                    }
                  },
                ),
                const SizedBox(width: 24),

                const Icon(Icons.store_rounded, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                const Text('Outlet/Customer:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<Customer>(
                    value: _selectedCustomer,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    hint: const Text('-- Semua Customer --', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    items: customerProvider.customers.map((c) {
                      return DropdownMenuItem<Customer>(
                        value: c,
                        child: Text(c.customerName),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedCustomer = val),
                  ),
                ),
                if (_selectedCustomer != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                    onPressed: () => setState(() => _selectedCustomer = null),
                    tooltip: 'Reset Filter Customer',
                  ),
                const Spacer(),

                // Toggle Pcs vs Kg
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          backgroundColor: _showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('PCS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = false),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          backgroundColor: !_showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('KG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Main Table Container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: _loadingErp || stockProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 48,
                            dataRowMaxHeight: 52,
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('NAMA PRODUK', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('STOCK BEFORE', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('SAMPLE BONUS', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('TOTAL KELUAR', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('MINGGU 1', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('MINGGU 2', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('MINGGU 3', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('MINGGU 4', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('MINGGU 5', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('TOTAL MASUK', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('STOCK AKHIR', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                            ],
                            rows: List.generate(products.length, (idx) {
                              final prod = products[idx];
                              final wMap = weeklyMap[prod.id] ?? {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
                              final m1 = wMap[1] ?? 0.0;
                              final m2 = wMap[2] ?? 0.0;
                              final m3 = wMap[3] ?? 0.0;
                              final m4 = wMap[4] ?? 0.0;
                              final m5 = wMap[5] ?? 0.0;
                              final totalMasuk = m1 + m2 + m3 + m4 + m5;

                              int totalSoldPcs = 0;
                              for (var r in _erpRecords) {
                                if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
                                  continue;
                                }
                                final prodSales = r['products'] as Map<String, dynamic>?;
                                if (prodSales != null && prodSales.containsKey(prod.id)) {
                                  totalSoldPcs += (prodSales[prod.id] as num).toInt();
                                }
                              }

                              final factor = _showPcs ? 1.0 : (prod.sizeGrams / 1000.0);
                              final stockBefore = prod.stock * factor;
                              final totalKeluar = totalSoldPcs * factor;
                              final sampleBonus = 0.0;
                              final stockAkhir = stockBefore + (totalMasuk * factor) - totalKeluar - sampleBonus;

                              final fmt = _showPcs ? 0 : 2;

                              return DataRow(
                                cells: [
                                  DataCell(Text(prod.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataCell(Text(stockBefore.toStringAsFixed(fmt), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(sampleBonus.toStringAsFixed(fmt), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(totalKeluar.toStringAsFixed(fmt), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                                  DataCell(Text((m1 * factor).toStringAsFixed(fmt), style: TextStyle(color: m1 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m1 > 0 ? FontWeight.bold : FontWeight.normal))),
                                  DataCell(Text((m2 * factor).toStringAsFixed(fmt), style: TextStyle(color: m2 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m2 > 0 ? FontWeight.bold : FontWeight.normal))),
                                  DataCell(Text((m3 * factor).toStringAsFixed(fmt), style: TextStyle(color: m3 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m3 > 0 ? FontWeight.bold : FontWeight.normal))),
                                  DataCell(Text((m4 * factor).toStringAsFixed(fmt), style: TextStyle(color: m4 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m4 > 0 ? FontWeight.bold : FontWeight.normal))),
                                  DataCell(Text((m5 * factor).toStringAsFixed(fmt), style: TextStyle(color: m5 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m5 > 0 ? FontWeight.bold : FontWeight.normal))),
                                  DataCell(Text((totalMasuk * factor).toStringAsFixed(fmt), style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold))),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                                      ),
                                      child: Text(
                                        stockAkhir.toStringAsFixed(fmt),
                                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
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
}
