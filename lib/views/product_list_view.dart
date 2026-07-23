import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';
import '../services/import_service.dart';

class ProductListView extends StatefulWidget {
  const ProductListView({super.key});

  @override
  State<ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends State<ProductListView> {
  final _searchController = TextEditingController();
  String _searchQuery = "";

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  double _parseCleanDouble(String text) {
    if (text.trim().isEmpty) return 0.0;
    String clean = text.replaceAll('Rp', '').replaceAll(' ', '').trim();
    if (clean.isEmpty) return 0.0;

    // Handle Indonesian number formats
    if (clean.contains('.') && clean.contains(',')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    } else if (clean.contains('.')) {
      // If dot is thousand separator e.g. 69.002 or 1.000.000
      if (RegExp(r'\.\d{3}$').hasMatch(clean) || RegExp(r'\.\d{3}\.').hasMatch(clean)) {
        clean = clean.replaceAll('.', '');
      }
    } else if (clean.contains(',')) {
      if (RegExp(r',\d{3}$').hasMatch(clean)) {
        clean = clean.replaceAll(',', '');
      } else {
        clean = clean.replaceAll(',', '.');
      }
    }
    return double.tryParse(clean) ?? 0.0;
  }

  int _parseCleanInt(String text) {
    if (text.trim().isEmpty) return 0;
    final clean = text.replaceAll('.', '').replaceAll(',', '').replaceAll(RegExp(r'[^\d]'), '').trim();
    return int.tryParse(clean) ?? 0;
  }

  void _showProductDialog([Product? product]) {
    final isEdit = product != null;
    final double initialStock = product?.stock ?? 0.0;

    final idController = TextEditingController(text: product?.id ?? '');
    final kodeIndukController = TextEditingController(text: product?.kodeInduk ?? product?.id ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toStringAsFixed(0) : '');
    final stockController = TextEditingController(text: product != null ? product.stock.toStringAsFixed(0) : '0');
    final cartonController = TextEditingController(text: product?.isiKarton.toString() ?? '');
    final sizeController = TextEditingController(text: product != null ? product.sizeGrams.toStringAsFixed(0) : '');

    // Auto-parse size from name on change
    nameController.addListener(() {
      if (sizeController.text.isEmpty || sizeController.text == '0') {
        final parsed = Product.parseSizeFromName(nameController.text);
        if (parsed > 0) {
          sizeController.text = parsed.toStringAsFixed(0);
        }
      }
    });

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final targetStock = _parseCleanDouble(stockController.text);
            final entryDiff = isEdit ? (targetStock - initialStock) : targetStock;

            Color entryColor;
            IconData entryIcon;

            if (entryDiff > 0) {
              entryColor = const Color(0xFF4ADE80); // Bright Green
              entryIcon = Icons.trending_up_rounded;
            } else if (entryDiff < 0) {
              entryColor = const Color(0xFFF87171); // Bright Red
              entryIcon = Icons.trending_down_rounded;
            } else {
              entryColor = const Color(0xFF94A3B8); // Neutral Grey
              entryIcon = Icons.remove_rounded;
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(isEdit ? Icons.edit_note_rounded : Icons.add_box_rounded, color: const Color(0xFF38BDF8)),
                  const SizedBox(width: 10),
                  Text(isEdit ? 'Edit Data Barang' : 'Tambah Barang Baru', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: idController,
                              enabled: !isEdit, // Cannot edit ID after creation (primary key)
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Kode Barang (ID)').copyWith(
                                labelText: 'Kode Barang (ID)',
                                labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: kodeIndukController,
                              enabled: true, // Always editable!
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: _buildInputDecoration(hint: 'Kode Induk (e.g. BRSM-500)').copyWith(
                                labelText: 'Kode Induk',
                                labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Nama Barang (e.g. BAKSO AYAM 250 G)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Harga Unit (Rupiah)'),
                      ),
                      const SizedBox(height: 12),

                      // Stock & Entry Calculation Container
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isEdit ? entryColor.withOpacity(0.4) : const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isEdit) ...[
                              Text(
                                'Stok Awal Saat Ini: ${initialStock.toStringAsFixed(0)} pcs',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    controller: stockController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    decoration: _buildInputDecoration(hint: isEdit ? 'Stok Baru' : 'Jumlah Stok Saat Ini').copyWith(
                                      labelText: isEdit ? 'Input Stok Baru' : 'Jumlah Stok Saat Ini',
                                      labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                                    ),
                                    onChanged: (val) {
                                      setDialogState(() {});
                                    },
                                  ),
                                ),
                                if (isEdit) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 5,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: entryColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: entryColor.withOpacity(0.5)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            'Entry (Selisih):',
                                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Icon(entryIcon, color: entryColor, size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  entryDiff > 0
                                                      ? '+${entryDiff.toStringAsFixed(0)} pcs'
                                                      : '${entryDiff.toStringAsFixed(0)} pcs',
                                                  style: TextStyle(color: entryColor, fontSize: 15, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cartonController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Isi per Karton (Pcs)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: sizeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Berat (Gram)'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: () async {
                    final id = idController.text.trim().toUpperCase();
                    final kodeIndukRaw = kodeIndukController.text.trim().toUpperCase();
                    final kodeInduk = kodeIndukRaw.isNotEmpty ? kodeIndukRaw : id;
                    final name = nameController.text.trim().toUpperCase();
                    final price = _parseCleanDouble(priceController.text);
                    final stock = _parseCleanDouble(stockController.text);
                    final carton = _parseCleanInt(cartonController.text);
                    final size = _parseCleanDouble(sizeController.text);

                    if (id.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Harap isi Kode Barang (ID)!'), backgroundColor: Colors.orange),
                      );
                      return;
                    }

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Harap isi Nama Barang!'), backgroundColor: Colors.orange),
                      );
                      return;
                    }

                    try {
                      final localProduct = product;
                      if (localProduct != null) {
                        // Edit Existing Product
                        final updated = Product(
                          id: id,
                          kodeInduk: kodeInduk,
                          name: name,
                          price: price,
                          stock: stock,
                          isiKarton: carton,
                          sizeGrams: size,
                        );
                        await Provider.of<ProductProvider>(context, listen: false).saveProduct(updated);
                      } else {
                        // Create New Product
                        final newProd = Product(
                          id: id,
                          kodeInduk: kodeInduk,
                          name: name,
                          price: price,
                          stock: stock,
                          isiKarton: carton,
                          sizeGrams: size,
                        );
                        await Provider.of<ProductProvider>(context, listen: false).saveProduct(newProd);
                      }

                      if (context.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isEdit ? 'Barang $name berhasil diperbarui!' : 'Barang $name berhasil ditambahkan!'),
                            backgroundColor: Colors.teal,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan barang: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  child: Text(isEdit ? 'Simpan Data' : 'Tambah Barang', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importProductsFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null) return;
      final bytes = result.files.single.bytes ??
          (result.files.single.path != null ? await File(result.files.single.path!).readAsBytes() : null);
      if (bytes == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );

      final importResult = await ImportService().importProducts(bytes);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show result dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Hasil Import Excel Barang', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Baris Data: ${importResult.totalRows}', style: const TextStyle(color: Colors.white)),
                Text('Sukses Dimuat: ${importResult.successCount}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                Text('Gagal: ${importResult.errorCount}', style: const TextStyle(color: Colors.redAccent)),
                if (importResult.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Rincian Error:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        importResult.errors.join('\n'),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimport: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);

    // Apply local search filter
    final filteredProducts = productProvider.products.where((p) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      final nameMatches = p.name.toLowerCase().contains(query);
      final idMatches = p.id.toLowerCase().contains(query);
      return nameMatches || idMatches;
    }).toList();

    final totalItems = productProvider.products.length;
    final inStockItems = productProvider.products.where((p) => p.stock > 0).length;
    final outOfStockItems = productProvider.products.where((p) => p.stock <= 0).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Top Toolbar: Search Bar + Summary Badges + Action Buttons
            Row(
              children: [
                // Search Input Field
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Cari barang berdasarkan nama atau kode induk...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
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
                const SizedBox(width: 16),
                
                // Add New Product Button
                ElevatedButton.icon(
                  onPressed: () => _showProductDialog(),
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('Tambah Barang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 12),

                // Import Excel Button
                ElevatedButton.icon(
                  onPressed: _importProductsFromExcel,
                  icon: const Icon(Icons.file_upload_rounded, color: Colors.white),
                  label: const Text('Import Excel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Summary Badges Banner
            Row(
              children: [
                _buildSummaryBadge('Total Master Barang', '$totalItems Produk', const Color(0xFF38BDF8), Icons.inventory_2_rounded),
                const SizedBox(width: 12),
                _buildSummaryBadge('Stok Tersedia', '$inStockItems Produk', Colors.greenAccent, Icons.check_circle_outline_rounded),
                const SizedBox(width: 12),
                _buildSummaryBadge('Stok Habis (0)', '$outOfStockItems Produk', outOfStockItems > 0 ? Colors.redAccent : const Color(0xFF64748B), Icons.warning_amber_rounded),
              ],
            ),
            const SizedBox(height: 16),

            // Products Table View with Horizontal & Vertical Scrolling
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: productProvider.isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                    : filteredProducts.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada barang ditemukan.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 900),
                                child: DataTable(
                                  headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                  dataRowMinHeight: 52,
                                  dataRowMaxHeight: 52,
                                  headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 13),
                                  columns: const [
                                    DataColumn(label: Text('KODE INDUK')),
                                    DataColumn(label: Text('NAMA BARANG')),
                                    DataColumn(label: Text('HARGA UNIT'), numeric: true),
                                    DataColumn(label: Text('STOK'), numeric: true),
                                    DataColumn(label: Text('ISI KARTON'), numeric: true),
                                    DataColumn(label: Text('BERAT'), numeric: true),
                                    DataColumn(label: Text('AKSI')),
                                  ],
                                  rows: filteredProducts.map((p) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(p.kodeInduk, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                        DataCell(Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                                        DataCell(Text(_rupiahFormatter.format(p.price), style: const TextStyle(color: Colors.white))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: (p.stock <= 0 ? Colors.redAccent : Colors.greenAccent).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              p.stock.toStringAsFixed(0),
                                              style: TextStyle(
                                                color: p.stock <= 0 ? Colors.redAccent : Colors.greenAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(Text('${p.isiKarton} Pcs', style: const TextStyle(color: Colors.white))),
                                        DataCell(Text('${p.sizeGrams.toStringAsFixed(0)} G', style: const TextStyle(color: Colors.white))),
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 20),
                                                tooltip: 'Edit Barang',
                                                onPressed: () => _showProductDialog(p),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                                tooltip: 'Hapus Barang',
                                                onPressed: () {
                                                  showDialog(
                                                    context: context,
                                                    builder: (context) => AlertDialog(
                                                      backgroundColor: const Color(0xFF1E293B),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                      title: const Text('Hapus Produk', style: TextStyle(color: Colors.white)),
                                                      content: Text('Apakah Anda yakin ingin menghapus "${p.name}" (${p.id})?', style: const TextStyle(color: Color(0xFF94A3B8))),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(context),
                                                          child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                                                        ),
                                                        ElevatedButton(
                                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                          onPressed: () async {
                                                            await productProvider.deleteProduct(p.id);
                                                            if (context.mounted) {
                                                              Navigator.pop(context);
                                                              ScaffoldMessenger.of(context).showSnackBar(
                                                                SnackBar(content: Text('Barang "${p.name}" telah dihapus.'), backgroundColor: Colors.redAccent),
                                                              );
                                                            }
                                                          },
                                                          child: const Text('Hapus', style: TextStyle(color: Colors.white)),
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
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBadge(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text('$title: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.0),
      ),
    );
  }
}
