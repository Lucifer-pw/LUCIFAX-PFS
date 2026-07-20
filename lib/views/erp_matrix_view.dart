import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  String _searchQuery = "";
  bool _showPcs = true; // true = Pcs, false = Kg
  List<Map<String, dynamic>> _erpRecords = [];
  Map<String, double> _initialStocks = {};
  bool _loadingErp = false;
  int _activeTab = 0; // 0 = Stok Matrix, 1 = Detail Invoice ERP

  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
    _loadErpData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
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
    final Set<String> optionsSet = {};
    final now = DateTime.now();
    final currentYear = now.year;

    // Generate past 3 years to 1 year in future (e.g. 2023 to 2027)
    for (int y = currentYear + 1; y >= currentYear - 3; y--) {
      for (int m = 12; m >= 1; m--) {
        final monthStr = m.toString().padLeft(2, '0');
        optionsSet.add('$monthStr-$y');
      }
    }

    if (_selectedMonthYear.isNotEmpty) {
      optionsSet.add(_selectedMonthYear);
    }

    final List<String> list = optionsSet.toList();
    list.sort((a, b) {
      final partsA = a.split('-');
      final partsB = b.split('-');
      if (partsA.length == 2 && partsB.length == 2) {
        final yearA = int.tryParse(partsA[1]) ?? 0;
        final yearB = int.tryParse(partsB[1]) ?? 0;
        if (yearA != yearB) return yearB.compareTo(yearA);
        final monthA = int.tryParse(partsA[0]) ?? 0;
        final monthB = int.tryParse(partsB[0]) ?? 0;
        return monthB.compareTo(monthA);
      }
      return b.compareTo(a);
    });

    return list;
  }

  Map<String, double> _calculateProductStats(dynamic prod, Map<int, double> wMap) {
    final factor = _showPcs ? 1.0 : (prod.sizeGrams / 1000.0);
    final initialStockVal = _initialStocks[prod.id] ?? prod.stock.toDouble();
    final stockBefore = initialStockVal * factor;

    double totalPenjualan = 0.0;
    double sampleBonus = 0.0;

    for (var r in _erpRecords) {
      if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
        continue;
      }
      final invoices = r['invoices'] as List<dynamic>?;
      if (invoices != null && invoices.isNotEmpty) {
        for (var inv in invoices) {
          final invNoStr = (inv['invoiceNo'] ?? '').toString().toUpperCase();
          final isSampleInvoice = invNoStr.startsWith('SA');

          final items = inv['items'] as List<dynamic>?;
          if (items != null) {
            for (var item in items) {
              final itemMap = Map<String, dynamic>.from(item as Map);
              final itemPId = (itemMap['productId'] ?? '').toString().trim().toLowerCase();
              final itemPName = (itemMap['productName'] ?? '').toString().trim().toLowerCase();
              final targetId = prod.id.toString().trim().toLowerCase();
              final targetName = prod.name.toString().trim().toLowerCase();

              final isMatch = (itemPId.isNotEmpty && (itemPId == targetId || itemPId == targetName)) ||
                              (itemPName.isNotEmpty && (itemPName == targetName || itemPName == targetId));

              if (isMatch) {
                final qty = (itemMap['qty'] ?? 0.0).toDouble();
                final weightKg = (itemMap['weightKg'] ?? 0.0).toDouble();
                final isBonusItem = itemMap['isBonus'] == true;
                final val = _showPcs ? qty : weightKg;

                if (isSampleInvoice || isBonusItem) {
                  sampleBonus += val;
                } else {
                  totalPenjualan += val;
                }
              }
            }
          }
        }
      } else {
        final prodSales = r['products'] as Map<String, dynamic>?;
        if (prodSales != null) {
          totalPenjualan += _getProductSoldQty(prodSales, prod.id, _showPcs, prod.sizeGrams);
        }
      }
    }

    final totalKeluar = totalPenjualan + sampleBonus;

    final m1 = (wMap[1] ?? 0.0) * factor;
    final m2 = (wMap[2] ?? 0.0) * factor;
    final m3 = (wMap[3] ?? 0.0) * factor;
    final m4 = (wMap[4] ?? 0.0) * factor;
    final m5 = (wMap[5] ?? 0.0) * factor;
    final totalMasuk = m1 + m2 + m3 + m4 + m5;

    final stockAkhir = stockBefore + totalMasuk - totalKeluar;

    return {
      'totalPenjualan': totalPenjualan,
      'stockBefore': stockBefore,
      'sampleBonus': sampleBonus,
      'totalKeluar': totalKeluar,
      'm1': m1,
      'm2': m2,
      'm3': m3,
      'm4': m4,
      'm5': m5,
      'totalMasuk': totalMasuk,
      'stockAkhir': stockAkhir,
    };
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
                headers: [
                  'Produk',
                  'Total Penjualan',
                  'Stock Before',
                  'Sample Bonus',
                  'Total Keluar',
                  'M1',
                  'M2',
                  'M3',
                  'M4',
                  'M5',
                  'Total Masuk',
                  'Total Stock Akhir',
                ],
                data: List.generate(products.length, (idx) {
                  final prod = products[idx];
                  final wMap = weeklyMap[prod.id] ?? {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
                  final stats = _calculateProductStats(prod, wMap);

                  final fmt = _showPcs ? 0 : 2;

                  return [
                    prod.name,
                    stats['totalPenjualan']!.toStringAsFixed(fmt),
                    stats['stockBefore']!.toStringAsFixed(fmt),
                    stats['sampleBonus']!.toStringAsFixed(fmt),
                    stats['totalKeluar']!.toStringAsFixed(fmt),
                    stats['m1']!.toStringAsFixed(fmt),
                    stats['m2']!.toStringAsFixed(fmt),
                    stats['m3']!.toStringAsFixed(fmt),
                    stats['m4']!.toStringAsFixed(fmt),
                    stats['m5']!.toStringAsFixed(fmt),
                    stats['totalMasuk']!.toStringAsFixed(fmt),
                    stats['stockAkhir']!.toStringAsFixed(fmt),
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
                const SizedBox(width: 20),

                // Product Search
                SizedBox(
                  width: 180,
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Cari barang...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
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

          // Tab selector: Stok Matrix vs Detail Invoice
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _activeTab == 0 ? const Color(0xFF0284C7) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_chart_rounded, size: 18, color: _activeTab == 0 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text('Stok Matrix', style: TextStyle(
                            color: _activeTab == 0 ? Colors.white : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold, fontSize: 13,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _activeTab == 1 ? const Color(0xFF0284C7) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 18, color: _activeTab == 1 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text('Detail Invoice ERP', style: TextStyle(
                            color: _activeTab == 1 ? Colors.white : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold, fontSize: 13,
                          )),
                          if (_erpRecords.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _activeTab == 1 ? Colors.white.withOpacity(0.2) : const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_getTotalInvoiceCount()}',
                                style: TextStyle(color: _activeTab == 1 ? Colors.white : const Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Main Content Area
          Expanded(
            child: _activeTab == 0
                ? _buildStockMatrixTab(products, weeklyMap, stockProvider)
                : _buildInvoiceDetailTab(),
          ),
        ],
      ),
    );
  }

  int _getTotalInvoiceCount() {
    int count = 0;
    for (var r in _erpRecords) {
      final invoices = r['invoices'] as List<dynamic>?;
      count += invoices?.length ?? 0;
    }
    return count;
  }

  Widget _buildStockMatrixTab(List products, Map weeklyMap, dynamic stockProvider) {
    final filteredProducts = products.where((p) {
      if (_searchQuery.isEmpty) return true;
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: _loadingErp || stockProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 44,
                    dataRowMaxHeight: 48,
                    columnSpacing: 10,
                    horizontalMargin: 12,
                    columns: const [
                      DataColumn(
                        label: Text('NAMA PRODUK', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Total Penjualan', child: Text('TOT. JUAL', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Stok Awal Bulan', child: Text('STOK BEFORE', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Sample Bonus', child: Text('SAMPLE', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Total Barang Keluar (Jual + Sample)', child: Text('TOT. KELUAR', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Minggu 1', child: Text('M1', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Minggu 2', child: Text('M2', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Minggu 3', child: Text('M3', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Minggu 4', child: Text('M4', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Minggu 5', child: Text('M5', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Total Barang Masuk (M1-M5)', child: Text('TOT. MASUK', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Total Stok Akhir', child: Text('STOK AKHIR', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                    ],
                    rows: List.generate(filteredProducts.length, (idx) {
                      final prod = filteredProducts[idx];
                      final wMap = weeklyMap[prod.id] ?? {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
                      final stats = _calculateProductStats(prod, wMap);

                      final fmt = _showPcs ? 0 : 2;

                      final totalPenjualan = stats['totalPenjualan']!;
                      final stockBefore = stats['stockBefore']!;
                      final sampleBonus = stats['sampleBonus']!;
                      final totalKeluar = stats['totalKeluar']!;
                      final m1 = stats['m1']!;
                      final m2 = stats['m2']!;
                      final m3 = stats['m3']!;
                      final m4 = stats['m4']!;
                      final m5 = stats['m5']!;
                      final totalMasuk = stats['totalMasuk']!;
                      final stockAkhir = stats['stockAkhir']!;

                      return DataRow(
                        cells: [
                          DataCell(Text(prod.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          DataCell(Text(totalPenjualan.toStringAsFixed(fmt), style: TextStyle(color: totalPenjualan > 0 ? const Color(0xFF38BDF8) : Colors.white70, fontWeight: totalPenjualan > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(stockBefore.toStringAsFixed(fmt), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          DataCell(Text(sampleBonus.toStringAsFixed(fmt), style: TextStyle(color: sampleBonus > 0 ? Colors.purpleAccent : Colors.white70, fontWeight: sampleBonus > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(totalKeluar.toStringAsFixed(fmt), style: TextStyle(color: totalKeluar > 0 ? Colors.redAccent : Colors.white70, fontWeight: totalKeluar > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(m1.toStringAsFixed(fmt), style: TextStyle(color: m1 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m1 > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(m2.toStringAsFixed(fmt), style: TextStyle(color: m2 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m2 > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(m3.toStringAsFixed(fmt), style: TextStyle(color: m3 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m3 > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(m4.toStringAsFixed(fmt), style: TextStyle(color: m4 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m4 > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(m5.toStringAsFixed(fmt), style: TextStyle(color: m5 > 0 ? const Color(0xFF38BDF8) : Colors.white38, fontWeight: m5 > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(Text(totalMasuk.toStringAsFixed(fmt), style: TextStyle(color: totalMasuk > 0 ? Colors.amberAccent : Colors.white70, fontWeight: totalMasuk > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                              ),
                              child: Text(
                                stockAkhir.toStringAsFixed(fmt),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
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
    );
  }

  Widget _buildInvoiceDetailTab() {
    if (_loadingErp) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter ERP records by selected customer
    final filteredRecords = _selectedCustomer != null
        ? _erpRecords.where((r) => r['customerId'] == _selectedCustomer!.id).toList()
        : _erpRecords;

    if (filteredRecords.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_rounded, size: 64, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              Text(
                'Belum ada invoice yang masuk ERP\npada periode $_selectedMonthYear',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set Status ERP di Histori Transaksi untuk memasukkan invoice',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF475569), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Sort records by customerName
    filteredRecords.sort((a, b) => (a['customerName'] ?? '').toString().compareTo((b['customerName'] ?? '').toString()));

    // Calculate Summary stats for Detail Invoice ERP tab
    double grandTotalIncome = 0.0;
    double grandTotalWeightKg = 0.0;

    for (var record in filteredRecords) {
      grandTotalIncome += (record['totalIncome'] ?? 0.0).toDouble();
      final invoices = List<dynamic>.from(record['invoices'] ?? []);
      for (var inv in invoices) {
        final items = List<dynamic>.from(inv['items'] ?? []);
        for (var item in items) {
          final itemMap = Map<String, dynamic>.from(item as Map);
          grandTotalWeightKg += (itemMap['weightKg'] ?? 0.0).toDouble();
        }
      }
    }

    return Column(
      children: [
        // Summary Cards for Total Income & Total Weight (Kg)
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.attach_money_rounded, color: Colors.greenAccent, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Income ERP', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormatter.format(grandTotalIncome),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.scale_rounded, color: Color(0xFF38BDF8), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Berat ERP (Kg)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${grandTotalWeightKg.toStringAsFixed(2)} Kg',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Scrollbar(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredRecords.length,
                itemBuilder: (context, index) {
            final record = filteredRecords[index];
            final customerName = record['customerName'] ?? 'Unknown';
            final totalIncome = (record['totalIncome'] ?? 0.0).toDouble();
            final invoices = List<dynamic>.from(record['invoices'] ?? []);
            final productsMap = Map<String, dynamic>.from(record['products'] ?? {});

            // Sort invoices by invoiceNo
            invoices.sort((a, b) => ((a['invoiceNo'] ?? 0) as int).compareTo((b['invoiceNo'] ?? 0) as int));

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                    ),
                  ),
                  title: Text(
                    customerName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${invoices.length} Invoice',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currencyFormatter.format(totalIncome),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  iconColor: const Color(0xFF94A3B8),
                  collapsedIconColor: const Color(0xFF64748B),
                  children: [
                    // Summary of products bought by this customer
                    if (productsMap.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📦 Ringkasan Produk yang Dibeli:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: productsMap.entries.map((entry) {
                                final prodData = entry.value is Map ? Map<String, dynamic>.from(entry.value) : {};
                                final pcs = (prodData['pcs'] ?? 0.0).toDouble();
                                final kg = (prodData['kg'] ?? 0.0).toDouble();
                                final displayVal = _showPcs ? pcs.toStringAsFixed(0) : kg.toStringAsFixed(2);
                                final unit = _showPcs ? 'pcs' : 'kg';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Text(
                                    '${entry.key}: $displayVal $unit',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Invoice list
                    ...invoices.map((inv) {
                      final invNo = inv['invoiceNo'] ?? 0;
                      final invItems = List<dynamic>.from(inv['items'] ?? []);
                      final calculatedInvTotal = invItems.fold(0.0, (sum, it) {
                        final itemMap = Map<String, dynamic>.from(it as Map);
                        final isBonus = itemMap['isBonus'] == true;
                        final sub = ((itemMap['subtotal'] ?? 0.0) as num).toDouble().roundToDouble();
                        return sum + (isBonus ? 0.0 : sub);
                      });
                      final invTotal = calculatedInvTotal > 0 ? calculatedInvTotal : ((inv['grandTotal'] ?? 0.0) as num).toDouble().roundToDouble();
                      DateTime? invDate;
                      try {
                        if (inv['date'] != null) {
                          if (inv['date'] is Timestamp) {
                            invDate = (inv['date'] as Timestamp).toDate();
                          }
                        }
                      } catch (_) {}

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                              ),
                              child: Text(
                                '#$invNo',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  currencyFormatter.format(invTotal),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                if (invDate != null)
                                  Text(
                                    dateFormatter.format(invDate),
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${invItems.length} item',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            ),
                            iconColor: const Color(0xFF94A3B8),
                            collapsedIconColor: const Color(0xFF475569),
                            children: [
                              // Items table
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    // Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                        border: Border.all(color: const Color(0xFF334155)),
                                      ),
                                      child: const Row(
                                        children: [
                                          Expanded(flex: 4, child: Text('Nama Barang', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                          SizedBox(width: 80, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                          SizedBox(width: 100, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold))),
                                        ],
                                      ),
                                    ),
                                    // Items
                                    ...invItems.map((item) {
                                      final itemMap = item is Map ? Map<String, dynamic>.from(item) : {};
                                      final productName = itemMap['productName'] ?? '';
                                      final qty = (itemMap['qty'] ?? 0.0).toDouble();
                                      final weightKg = (itemMap['weightKg'] ?? 0.0).toDouble();
                                      final subtotal = (itemMap['subtotal'] ?? 0.0).toDouble();
                                      final isBonus = itemMap['isBonus'] ?? false;
                                      final displayQty = _showPcs ? qty.toStringAsFixed(0) : weightKg.toStringAsFixed(2);
                                      final unit = _showPcs ? 'pcs' : 'kg';

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.03))),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      productName,
                                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (isBonus) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.purple.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text('BONUS', style: TextStyle(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            SizedBox(
                                              width: 80,
                                              child: Text(
                                                '$displayQty $unit',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                isBonus ? 'Rp 0' : currencyFormatter.format(subtotal),
                                                textAlign: TextAlign.right,
                                                style: TextStyle(color: isBonus ? const Color(0xFF64748B) : Colors.white70, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  ),
],
);
}
}
