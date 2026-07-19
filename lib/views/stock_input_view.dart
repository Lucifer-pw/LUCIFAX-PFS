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

    final monthYear = DateFormat('MM-yyyy').format(_selectedDate);

    final entry = StockEntry(
      id: '',
      productId: _selectedProduct!.id,
      productName: _selectedProduct!.name,
      price: _selectedProduct!.price,
      date: _selectedDate,
      monthYear: monthYear,
      weekNumber: _selectedWeek,
      qty: qty,
    );

    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);

    final success = await stockProvider.saveStockEntry(entry);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok ${_selectedProduct!.name} (Minggu $_selectedWeek) +${qty.toInt()} Pcs berhasil disimpan!'),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _stockInputController.clear();
      productProvider.fetchProducts();
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

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
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
          const SizedBox(height: 20),

          // Main Responsive Grid
          Expanded(
            child: Row(
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
                          const Text('JUMLAH STOK MASUK (PCS)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
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
                                backgroundColor: const Color(0xFF38BDF8),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _saveStockInput,
                              icon: const Icon(Icons.save_rounded, color: Colors.black),
                              label: const Text('Simpan Stok Masuk', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                                                          '${prod.stock.toInt()} Pcs',
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

                              // Tab 2: Stock Entry History Logs with Delete action
                              stockProvider.isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : stockProvider.stockEntries.isEmpty
                                      ? const Center(child: Text('Belum ada riwayat entri stok.', style: TextStyle(color: Color(0xFF64748B))))
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(12),
                                          itemCount: stockProvider.stockEntries.length,
                                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                                          itemBuilder: (context, index) {
                                            final entry = stockProvider.stockEntries[index];
                                            return Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0F172A),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF0284C7).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text('M${entry.weekNumber}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(entry.productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                                        const SizedBox(height: 2),
                                                        Text('${dateFormatter.format(entry.date)} • Periode: ${entry.monthYear}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                                                      ],
                                                    ),
                                                  ),
                                                  Text('+${entry.qty.toInt()} Pcs', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                                                  const SizedBox(width: 12),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                                    onPressed: () async {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (ctx) => AlertDialog(
                                                          backgroundColor: const Color(0xFF1E293B),
                                                          title: const Text('Hapus Entri Stok', style: TextStyle(color: Colors.white)),
                                                          content: Text('Apakah Anda yakin ingin menghapus entri stok "${entry.productName}" (+${entry.qty.toInt()} Pcs)?', style: const TextStyle(color: Color(0xFF94A3B8))),
                                                          actions: [
                                                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
                                                            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm == true) {
                                                        await stockProvider.deleteStockEntry(entry.id);
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
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
}
