import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../models/product.dart';
import '../models/stock_entry.dart';

class StockInputView extends StatefulWidget {
  const StockInputView({super.key});

  @override
  State<StockInputView> createState() => _StockInputViewState();
}

class _StockInputViewState extends State<StockInputView> with SingleTickerProviderStateMixin {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormatter = DateFormat('dd-MM-yyyy');

  Product? _selectedProduct;
  int _selectedWeek = 1;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _stockInputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _qtyFocusNode = FocusNode();
  String _searchQuery = '';
  TabController? _tabController;
  String _historyFilterMonthYear = DateFormat('MM-yyyy').format(DateTime.now());
  int? _historyFilterWeek; // null = Semua Minggu (M1-M5), 1..5 = filter by specific week
  bool _isSavingStock = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<StockProvider>(context, listen: false).fetchStockEntries();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _stockInputController.dispose();
    _searchController.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  void _selectProduct(Product prod) {
    setState(() {
      _selectedProduct = prod;
    });
    _qtyFocusNode.requestFocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Produk "${prod.name}" dipilih! Silakan masukkan jumlah stok.'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _saveStockInput() async {
    if (_isSavingStock) return;

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih Nama Barang terlebih dahulu!'), backgroundColor: Colors.orange),
      );
      return;
    }

    final qty = double.tryParse(_stockInputController.text.trim()) ?? 0.0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah stok barang yang valid!'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSavingStock = true;
    });

    try {
      final monthYear = DateFormat('MM-yyyy').format(_selectedDate);
      final stockBefore = _selectedProduct!.stock;
      final stockAfter = stockBefore + qty;

      final entry = StockEntry(
        id: '',
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name,
        price: _selectedProduct!.price,
        date: _selectedDate,
        monthYear: monthYear,
        weekNumber: _selectedWeek,
        qty: qty,
        stockBefore: stockBefore,
        stockAfter: stockAfter,
      );

      final stockProvider = Provider.of<StockProvider>(context, listen: false);
      final productProvider = Provider.of<ProductProvider>(context, listen: false);

      final success = await stockProvider.saveStockEntry(entry);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stok ${_selectedProduct!.name} (Minggu $_selectedWeek) +${qty.toInt()} Pack berhasil disimpan!'),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _stockInputController.clear();
        await productProvider.fetchProducts();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingStock = false;
        });
      }
    }
  }

  Future<void> _printPdf() async {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final products = productProvider.products;

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'LAPORAN DAFTAR STOK BARANG',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text('Tanggal Cetak: ${dateFormatter.format(DateTime.now())}'),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['NO', 'NAMA BARANG', 'HARGA', 'STOK TERKINI'],
                data: List.generate(products.length, (idx) {
                  final p = products[idx];
                  return [
                    '${idx + 1}',
                    p.name,
                    'Rp ${NumberFormat('#,###').format(p.price)}',
                    '${p.stock.toInt()}',
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
      name: 'laporan_stok_barang.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);
    final stockProvider = Provider.of<StockProvider>(context);
    final products = productProvider.products;

    final filteredProducts = products.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.id.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar (Desktop Only - Mobile header is inside SingleChildScrollView)
          if (!isMobile) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Input Stok Mingguan',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Klik barang di daftar sebelah kanan untuk langsung memilih & mengisi stok masuk',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _printPdf,
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Cetak Laporan PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // Main Responsive Grid
          Expanded(
            child: isMobile
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        // Mobile Header Bar (Inside ScrollView so it scrolls away gracefully)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Input Stok Mingguan',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Pilih produk & isi stok masuk mingguan',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: const Color(0xFF38BDF8),
                                  side: const BorderSide(color: Color(0xFF38BDF8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _printPdf,
                                icon: const Icon(Icons.print_rounded, size: 16),
                                label: const Text('Cetak Laporan PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Form Card (Top on mobile)
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.add_box_rounded, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Form Entry Stok Masuk',
                                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // NAMA BARANG
                              const Text('PILIH PRODUK', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<Product>(
                                value: _selectedProduct,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                ),
                                hint: const Text('-- Pilih Barang --', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                                items: products.map((prod) {
                                  return DropdownMenuItem<Product>(
                                    value: prod,
                                    child: Text('${prod.name} (Stok: ${prod.stock.toInt()})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) _selectProduct(val);
                                },
                              ),
                              const SizedBox(height: 10),

                              // HARGA SATUAN
                              const Text('HARGA SATUAN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _selectedProduct != null
                                      ? currencyFormatter.format(_selectedProduct!.price)
                                      : 'Rp 0',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // MINGGU & TANGGAL
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('MINGGU KE-', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        DropdownButtonFormField<int>(
                                          value: _selectedWeek,
                                          dropdownColor: const Color(0xFF1E293B),
                                          style: const TextStyle(color: Colors.white, fontSize: 13),
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: const Color(0xFF0F172A),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                          ),
                                          items: [1, 2, 3, 4, 5].map((w) {
                                            return DropdownMenuItem<int>(
                                              value: w,
                                              child: Text('Minggu $w', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) setState(() => _selectedWeek = val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('TANGGAL ENTRY', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: _selectedDate,
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2030),
                                            );
                                            if (picked != null) {
                                              setState(() => _selectedDate = picked);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF0F172A),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    dateFormatter.format(_selectedDate),
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF38BDF8)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // INPUT STOK BARANG
                              const Text('JUMLAH STOK MASUK (PACK)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _stockInputController,
                                focusNode: _qtyFocusNode,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  hintText: 'Misal: 100',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // SIMPAN BUTTON
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isSavingStock ? const Color(0xFF334155) : const Color(0xFF38BDF8),
                                    foregroundColor: _isSavingStock ? Colors.white70 : Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isSavingStock ? null : _saveStockInput,
                                  icon: _isSavingStock
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                                        )
                                      : const Icon(Icons.save_rounded, color: Colors.black, size: 18),
                                  label: Text(
                                    _isSavingStock ? 'Memproses...' : 'Simpan Stok Masuk',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _isSavingStock ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Table & Log Tabs (Below on mobile - expanded scrollable container)
                        SizedBox(
                          height: 880,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tab Bar Header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.white10)),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  indicatorColor: const Color(0xFF38BDF8),
                                  labelColor: const Color(0xFF38BDF8),
                                  unselectedLabelColor: const Color(0xFF94A3B8),
                                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                                  tabs: const [
                                    Tab(text: 'Daftar Stok Produk'),
                                    Tab(text: 'Riwayat Entry Stok'),
                                  ],
                                ),
                              ),

                              // Tab Views
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    // Tab 1: Interactive Product List
                                    Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(10.0),
                                          child: TextField(
                                            controller: _searchController,
                                            onChanged: (val) => setState(() => _searchQuery = val),
                                            style: const TextStyle(color: Colors.white, fontSize: 13),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: const Color(0xFF0F172A),
                                              hintText: 'Cari produk...',
                                              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: productProvider.isLoading
                                              ? const Center(child: CircularProgressIndicator())
                                              : ListView.separated(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  itemCount: filteredProducts.length,
                                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                                  itemBuilder: (context, idx) {
                                                    final prod = filteredProducts[idx];
                                                    final isSelected = _selectedProduct?.id == prod.id;
                                                    return InkWell(
                                                      onTap: () => _selectProduct(prod),
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                        decoration: BoxDecoration(
                                                          color: isSelected ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(
                                                            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
                                                            width: isSelected ? 1.5 : 1,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Text(
                                                              '${idx + 1}.',
                                                              style: TextStyle(
                                                                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 8),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    prod.name,
                                                                    style: TextStyle(
                                                                      color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 12,
                                                                    ),
                                                                    maxLines: 2,
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    currencyFormatter.format(prod.price),
                                                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                              decoration: BoxDecoration(
                                                                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF0284C7).withOpacity(0.2),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                '${prod.stock.toInt()} Pack',
                                                                style: TextStyle(
                                                                  color: isSelected ? Colors.black : const Color(0xFF38BDF8),
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 6),
                                                            SizedBox(
                                                              height: 28,
                                                              child: ElevatedButton(
                                                                style: ElevatedButton.styleFrom(
                                                                  backgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
                                                                  foregroundColor: isSelected ? Colors.black : const Color(0xFF38BDF8),
                                                                  elevation: 0,
                                                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                                                  minimumSize: Size.zero,
                                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                  shape: RoundedRectangleBorder(
                                                                    borderRadius: BorderRadius.circular(6),
                                                                    side: BorderSide(color: isSelected ? Colors.transparent : const Color(0xFF38BDF8)),
                                                                  ),
                                                                ),
                                                                onPressed: () => _selectProduct(prod),
                                                                child: Text(
                                                                  isSelected ? 'TERPILIH' : 'PILIH',
                                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                        ),
                                      ],
                                    ),

                                    // Tab 2: Stock Entry History Logs
                                    _buildHistoryTab(stockProvider),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form Card (Left)
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(24.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.add_box_rounded, color: Color(0xFF38BDF8), size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'Form Entry Stok Masuk',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // NAMA BARANG
                                const Text('PILIH PRODUK', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<Product>(
                                  value: _selectedProduct,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF1E293B),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                  ),
                                  hint: const Text('-- Pilih Barang --', style: TextStyle(color: Color(0xFF64748B))),
                                  items: products.map((prod) {
                                    return DropdownMenuItem<Product>(
                                      value: prod,
                                      child: Text('${prod.name} (Stok: ${prod.stock.toInt()})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) _selectProduct(val);
                                  },
                                ),
                                const SizedBox(height: 16),

                                // HARGA BARANG
                                const Text('HARGA SATUAN', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _selectedProduct != null
                                        ? currencyFormatter.format(_selectedProduct!.price)
                                        : 'Rp 0',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // MINGGU & TANGGAL
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('MINGGU KE-', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 6),
                                          DropdownButtonFormField<int>(
                                            value: _selectedWeek,
                                            dropdownColor: const Color(0xFF1E293B),
                                            style: const TextStyle(color: Colors.white),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: const Color(0xFF0F172A),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                            ),
                                            items: [1, 2, 3, 4, 5].map((w) {
                                              return DropdownMenuItem<int>(
                                                value: w,
                                                child: Text('Minggu $w', style: const TextStyle(color: Colors.white)),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) setState(() => _selectedWeek = val);
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('TANGGAL ENTRY', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 6),
                                          InkWell(
                                            onTap: () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _selectedDate,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2030),
                                              );
                                              if (picked != null) {
                                                setState(() => _selectedDate = picked);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0F172A),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    dateFormatter.format(_selectedDate),
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                  ),
                                                  const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF38BDF8)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // INPUT STOK BARANG
                                const Text('JUMLAH STOK MASUK (PACK)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _stockInputController,
                                  focusNode: _qtyFocusNode,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    hintText: 'Misal: 100',
                                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // SIMPAN BUTTON
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isSavingStock ? const Color(0xFF334155) : const Color(0xFF38BDF8),
                                      foregroundColor: _isSavingStock ? Colors.white70 : Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _isSavingStock ? null : _saveStockInput,
                                    icon: _isSavingStock
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF38BDF8)),
                                          )
                                        : const Icon(Icons.save_rounded, color: Colors.black),
                                    label: Text(
                                      _isSavingStock ? 'Memproses Simpan Stok...' : 'Simpan Stok Masuk',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: _isSavingStock ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Table & Log Tabs (Right Side)
                      Expanded(
                        flex: 7,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tab Bar Header
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.white10)),
                                ),
                                child: TabBar(
                                  controller: _tabController,
                                  indicatorColor: const Color(0xFF38BDF8),
                                  labelColor: const Color(0xFF38BDF8),
                                  unselectedLabelColor: const Color(0xFF94A3B8),
                                  tabs: const [
                                    Tab(text: 'Daftar Stok Produk (Klik untuk Pilih)'),
                                    Tab(text: 'Riwayat Entry Stok'),
                                  ],
                                ),
                              ),

                              // Tab Views
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    // Tab 1: Interactive Product List Cards with InkWell Tap
                                    Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: TextField(
                                            controller: _searchController,
                                            onChanged: (val) => setState(() => _searchQuery = val),
                                            style: const TextStyle(color: Colors.white),
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: const Color(0xFF0F172A),
                                              hintText: 'Cari produk...',
                                              hintStyle: const TextStyle(color: Color(0xFF64748B)),
                                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: productProvider.isLoading
                                              ? const Center(child: CircularProgressIndicator())
                                              : ListView.separated(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                  itemCount: filteredProducts.length,
                                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                                  itemBuilder: (context, idx) {
                                                    final prod = filteredProducts[idx];
                                                    final isSelected = _selectedProduct?.id == prod.id;
                                                    return InkWell(
                                                      onTap: () => _selectProduct(prod),
                                                      borderRadius: BorderRadius.circular(10),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                        decoration: BoxDecoration(
                                                          color: isSelected ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(
                                                            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
                                                            width: isSelected ? 1.5 : 1,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Text(
                                                              '${idx + 1}.',
                                                              style: TextStyle(
                                                                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 10),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    prod.name,
                                                                    style: TextStyle(
                                                                      color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 13,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    currencyFormatter.format(prod.price),
                                                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                              decoration: BoxDecoration(
                                                                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF0284C7).withOpacity(0.2),
                                                                borderRadius: BorderRadius.circular(6),
                                                              ),
                                                              child: Text(
                                                                '${prod.stock.toInt()} Pack',
                                                                style: TextStyle(
                                                                  color: isSelected ? Colors.black : const Color(0xFF38BDF8),
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 10),
                                                            ElevatedButton(
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
                                                                foregroundColor: isSelected ? Colors.black : const Color(0xFF38BDF8),
                                                                elevation: 0,
                                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                minimumSize: Size.zero,
                                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(6),
                                                                  side: BorderSide(color: isSelected ? Colors.transparent : const Color(0xFF38BDF8)),
                                                                ),
                                                              ),
                                                              onPressed: () => _selectProduct(prod),
                                                              child: Text(
                                                                isSelected ? 'TERPILIH' : 'PILIH',
                                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                        ),
                                      ],
                                    ),

                                    // Tab 2: Stock Entry History Logs Grouped by Period & Week
                                    _buildHistoryTab(stockProvider),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  List<String> _getAvailableHistoryMonths(List<StockEntry> entries) {
    final current = DateFormat('MM-yyyy').format(DateTime.now());
    final Set<String> months = {current};
    for (var e in entries) {
      if (e.monthYear.isNotEmpty) months.add(e.monthYear);
    }
    final list = months.toList();
    list.sort((a, b) {
      final partsA = a.split('-');
      final partsB = b.split('-');
      if (partsA.length == 2 && partsB.length == 2) {
        final keyA = '${partsA[1]}-${partsA[0]}';
        final keyB = '${partsB[1]}-${partsB[0]}';
        return keyB.compareTo(keyA);
      }
      return b.compareTo(a);
    });
    return ['SEMUA PERIODE', ...list];
  }

  String _formatMonthName(String monthYear) {
    if (monthYear == 'SEMUA PERIODE') return 'Semua Periode';
    try {
      final parts = monthYear.split('-');
      if (parts.length == 2) {
        final monthInt = int.tryParse(parts[0]) ?? 1;
        final yearStr = parts[1];
        const monthNames = [
          '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ];
        if (monthInt >= 1 && monthInt <= 12) {
          return '${monthNames[monthInt]} $yearStr ($monthYear)';
        }
      }
    } catch (_) {}
    return monthYear;
  }

  Widget _buildHistoryTab(StockProvider stockProvider) {
    if (stockProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final allEntries = stockProvider.stockEntries;
    if (allEntries.isEmpty) {
      return const Center(
        child: Text('Belum ada riwayat entri stok.', style: TextStyle(color: Color(0xFF64748B))),
      );
    }

    final availableMonths = _getAvailableHistoryMonths(allEntries);
    if (!availableMonths.contains(_historyFilterMonthYear)) {
      final currentMonth = DateFormat('MM-yyyy').format(DateTime.now());
      _historyFilterMonthYear = availableMonths.contains(currentMonth)
          ? currentMonth
          : (availableMonths.length > 1 ? availableMonths[1] : 'SEMUA PERIODE');
    }

    final filteredEntries = allEntries.where((e) {
      if (_historyFilterMonthYear == 'SEMUA PERIODE') return true;
      return e.monthYear == _historyFilterMonthYear;
    }).toList();

    double totalMonthQty = 0;
    final Map<int, double> weekTotals = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
    final Map<int, List<StockEntry>> groupedByWeek = {1: [], 2: [], 3: [], 4: [], 5: []};

    for (var entry in filteredEntries) {
      totalMonthQty += entry.qty;
      final w = entry.weekNumber;
      if (groupedByWeek.containsKey(w)) {
        groupedByWeek[w]!.add(entry);
        weekTotals[w] = (weekTotals[w] ?? 0.0) + entry.qty;
      } else {
        groupedByWeek.putIfAbsent(w, () => []).add(entry);
        weekTotals[w] = (weekTotals[w] ?? 0.0) + entry.qty;
      }
    }

    final allActiveWeeks = [1, 2, 3, 4, 5].where((w) => (groupedByWeek[w] ?? []).isNotEmpty).toList();
    final activeWeeks = _historyFilterWeek != null
        ? ((groupedByWeek[_historyFilterWeek!] ?? []).isNotEmpty ? [_historyFilterWeek!] : <int>[])
        : allActiveWeeks;

    final displayedQty = _historyFilterWeek != null
        ? (weekTotals[_historyFilterWeek!] ?? 0.0)
        : totalMonthQty;

    final displayedEntriesCount = _historyFilterWeek != null
        ? (groupedByWeek[_historyFilterWeek!]?.length ?? 0)
        : filteredEntries.length;

    return Column(
      children: [
        // Top Filter & Summary Card (Compact 2-Row Design)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Total Input Summary (Left) & Compact Month Dropdown (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(fontSize: 12.5, fontFamily: 'Roboto'),
                              children: [
                                const TextSpan(
                                  text: 'Total Input: ',
                                  style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                                ),
                                TextSpan(
                                  text: '+${NumberFormat('#,###').format(displayedQty)} Pack',
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: ' ($displayedEntriesCount Entri)',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _historyFilterMonthYear,
                        dropdownColor: const Color(0xFF1E293B),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF38BDF8), size: 16),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _historyFilterMonthYear = val;
                              _historyFilterWeek = null; // Reset week filter on month change
                            });
                          }
                        },
                        items: availableMonths.map((m) {
                          return DropdownMenuItem<String>(
                            value: m,
                            child: Text(_formatMonthName(m)),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Weekly Breakdown Interactive Filter Pills (Semua & M1 .. M5)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Pill: Semua Minggu (M1-M5)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _historyFilterWeek = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _historyFilterWeek == null
                              ? const Color(0xFF0284C7).withOpacity(0.35)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _historyFilterWeek == null
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF334155),
                            width: _historyFilterWeek == null ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_historyFilterWeek == null) ...[
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 12),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              'Semua (M1-M5): +${totalMonthQty.toInt()} Pack',
                              style: TextStyle(
                                color: _historyFilterWeek == null ? const Color(0xFF38BDF8) : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Pills: M1 .. M5
                    ...[1, 2, 3, 4, 5].map((w) {
                      final isSelected = _historyFilterWeek == w;
                      final sumW = weekTotals[w] ?? 0.0;
                      final hasData = (groupedByWeek[w] ?? []).isNotEmpty;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (_historyFilterWeek == w) {
                              _historyFilterWeek = null; // Toggle back to all weeks
                            } else {
                              _historyFilterWeek = w;
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0284C7).withOpacity(0.35)
                                : (hasData ? const Color(0xFF0284C7).withOpacity(0.12) : const Color(0xFF1E293B)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : (hasData ? const Color(0xFF0284C7).withOpacity(0.5) : const Color(0xFF334155)),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected) ...[
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 12),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                'M$w: +${sumW.toInt()} Pack',
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF38BDF8)
                                      : (hasData ? Colors.white : const Color(0xFF64748B)),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // List of Grouped Weekly Entries
        Expanded(
          child: filteredEntries.isEmpty
              ? const Center(
                  child: Text('Tidak ada entri stok pada periode ini.', style: TextStyle(color: Color(0xFF64748B))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: activeWeeks.length,
                  itemBuilder: (context, weekIdx) {
                    final w = activeWeeks[weekIdx];
                    final entriesInWeek = groupedByWeek[w]!;
                    final sumWeek = weekTotals[w] ?? 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Weekly Header Bar (Sleek 30px bar)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E293B),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(9),
                                topRight: Radius.circular(9),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'M$w',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'MINGGU $w',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '(${entriesInWeek.length} Entri)',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Total M$w: +${sumWeek.toInt()} Pack',
                                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Compact Rows in Week w (Table-Style Single Row ~40px)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(6),
                            itemCount: entriesInWeek.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemBuilder: (context, idx) {
                              final entry = entriesInWeek[idx];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF1E293B)),
                                ),
                                child: Row(
                                  children: [
                                    // Number Badge
                                    Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                                      ),
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Product Name & Date / Stock Pill
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  entry.productName,
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  dateFormatter.format(entry.date),
                                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (entry.stockBefore != null) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1E293B),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFF334155)),
                                              ),
                                              child: Text(
                                                '${entry.stockBefore!.toInt()} ➔ ${(entry.stockAfter ?? (entry.stockBefore! + entry.qty)).toInt()}',
                                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Added Qty (Green Bold)
                                    Text(
                                      '+${entry.qty.toInt()} Pack',
                                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(width: 4),

                                    // Delete Action Button
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                        splashRadius: 14,
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(0xFF1E293B),
                                              title: const Text('Hapus Entri Stok', style: TextStyle(color: Colors.white)),
                                              content: Text(
                                                'Apakah Anda yakin ingin menghapus entri stok "${entry.productName}" (+${entry.qty.toInt()} Pack)?',
                                                style: const TextStyle(color: Color(0xFF94A3B8)),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, false),
                                                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                                                ),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                  onPressed: () => Navigator.pop(ctx, true),
                                                  child: const Text('Hapus'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await stockProvider.deleteStockEntry(entry.id);
                                            if (mounted) {
                                              Provider.of<ProductProvider>(context, listen: false).fetchProducts();
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
