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
  Map<String, double> _initialStocks = {};
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
      final initialStocks = await stockProvider.fetchInitialStocks(_selectedMonthYear);

      setState(() {
        _erpRecords = data;
        _initialStocks = initialStocks;
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
                  final factor = _showPcs ? 1.0 : (prod.sizeGrams / 1000.0);
                  final initialStockVal = _initialStocks[prod.id] ?? prod.stock.toDouble();
                  final stockBefore = initialStockVal * factor;

                  double totalKeluar = 0.0;
                  for (var r in _erpRecords) {
                    final prodSales = r['products'] as Map<String, dynamic>?;
                    if (prodSales != null) {
                      totalKeluar += _getProductSoldQty(prodSales, prod.id, _showPcs, prod.sizeGrams);
                    }
                  }

                  final sampleBonus = 0.0;
                  final stockAkhir = stockBefore + (totalMasuk * factor) - totalKeluar - sampleBonus;

                  final fmt = _showPcs ? 0 : 2;

                  return [
                    prod.name,
                    stockBefore.toStringAsFixed(fmt),
                    sampleBonus.toStringAsFixed(fmt),
                    totalKeluar.toStringAsFixed(fmt),
                    (m1 * factor).toStringAsFixed(fmt),
                    (m2 * factor).toStringAsFixed(fmt),
                    (m3 * factor).toStringAsFixed(fmt),
                    (m4 * factor).toStringAsFixed(fmt),
                    (m5 * factor).toStringAsFixed(fmt),
                    (totalMasuk * factor).toStringAsFixed(fmt),
                    stockAkhir.toStringAsFixed(fmt),
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

  double _getProductSoldQty(Map<String, dynamic> prodSales, String productId, bool showPcs, double sizeGrams) {
    final record = prodSales[productId];
    if (record == null) return 0.0;
    if (record is Map) {
      if (showPcs) {
        return (record['pcs'] ?? 0.0).toDouble();
      } else {
        return (record['kg'] ?? 0.0).toDouble();
      }
    } else if (record is num) {
      // Fallback for older flat num format
      final double pcs = record.toDouble();
      if (showPcs) {
        return pcs;
      } else {
        return pcs * (sizeGrams / 1000.0);
      }
    }
    return 0.0;
  }

  void _showSetInitialStockDialog() {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final products = productProvider.products;

    // Build controllers map pre-filled with current initial stock values
    final Map<String, TextEditingController> controllers = {};
    for (var prod in products) {
      final currentVal = _initialStocks[prod.id] ?? prod.stock.toDouble();
      controllers[prod.id] = TextEditingController(text: currentVal.toStringAsFixed(0));
    }

    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filteredProducts = products.where((p) {
              if (searchQuery.isEmpty) return true;
              return p.name.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 600,
                height: 600,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dialog Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Set Stok Awal Bulan',
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Periode: $_selectedMonthYear',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Search Bar
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Cari produk...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (val) => setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),

                    // Auto-fill from master stock button
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            for (var prod in products) {
                              controllers[prod.id]!.text = prod.stock.toStringAsFixed(0);
                            }
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text('Isi dari Stok Master', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            for (var prod in products) {
                              controllers[prod.id]!.text = '0';
                            }
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('Reset Semua ke 0', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Product list with editable stock
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: filteredProducts.length,
                          separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 1),
                          itemBuilder: (ctx, i) {
                            final prod = filteredProducts[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(prod.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                        Text('Master: ${prod.stock.toStringAsFixed(0)} pcs', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 120,
                                    child: TextField(
                                      controller: controllers[prod.id],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFF1E293B),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 2)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        suffixText: 'pcs',
                                        suffixStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Batal', style: TextStyle(color: Colors.white54)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final Map<String, double> stocksToSave = {};
                            for (var prod in products) {
                              final val = double.tryParse(controllers[prod.id]!.text) ?? 0.0;
                              stocksToSave[prod.id] = val;
                            }
                            await stockProvider.saveInitialStocks(_selectedMonthYear, stocksToSave);
                            Navigator.pop(ctx);
                            _loadErpData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Stok awal bulan $_selectedMonthYear berhasil disimpan!'),
                                backgroundColor: Colors.teal,
                              ),
                            );
                          },
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Simpan Stok Awal', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
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
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF38BDF8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _showSetInitialStockDialog,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Set Stok Awal Bulan', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: Colors.amberAccent,
                      side: const BorderSide(color: Colors.amberAccent),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      productProvider.fetchProducts();
                      _loadErpData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Data berhasil di-refresh!'), backgroundColor: Colors.teal),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh Data', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
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
                              final factor = _showPcs ? 1.0 : (prod.sizeGrams / 1000.0);
                              final initialStockVal = _initialStocks[prod.id] ?? prod.stock.toDouble();
                              final stockBefore = initialStockVal * factor;

                              double totalKeluar = 0.0;
                              for (var r in _erpRecords) {
                                if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
                                  continue;
                                }
                                final prodSales = r['products'] as Map<String, dynamic>?;
                                if (prodSales != null) {
                                  totalKeluar += _getProductSoldQty(prodSales, prod.id, _showPcs, prod.sizeGrams);
                                }
                              }

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
