import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../providers/product_provider.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showProductDialog([Product? product]) {
    final isEdit = product != null;
    final idController = TextEditingController(text: product?.id ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product?.price.toStringAsFixed(0) ?? '');
    final stockController = TextEditingController(text: product?.stock.toStringAsFixed(0) ?? '0');
    final cartonController = TextEditingController(text: product?.isiKarton.toString() ?? '');
    final sizeController = TextEditingController(text: product?.sizeGrams.toStringAsFixed(0) ?? '');

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
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(isEdit ? 'Edit Produk' : 'Tambah Produk Baru', style: const TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: idController,
                    enabled: !isEdit, // Cannot edit ID after creation (primary key)
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(hint: 'Kode Induk (e.g. BA-250)'),
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
                    decoration: _buildInputDecoration(hint: 'Harga (Rupiah)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: stockController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(hint: 'Stok Awal'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: cartonController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: _buildInputDecoration(hint: 'Isi per Karton'),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () async {
                final id = idController.text.trim();
                final name = nameController.text.trim();
                final price = double.tryParse(priceController.text) ?? 0.0;
                final stock = double.tryParse(stockController.text) ?? 0.0;
                final carton = int.tryParse(cartonController.text) ?? 0;
                final size = double.tryParse(sizeController.text) ?? 0.0;

                if (id.isEmpty || name.isEmpty || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Harap lengkapi semua kolom dengan benar!'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                final newProd = Product(
                  id: id,
                  name: name,
                  price: price,
                  stock: stock,
                  isiKarton: carton,
                  sizeGrams: size,
                );

                await Provider.of<ProductProvider>(context, listen: false).saveProduct(newProd);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = Provider.of<ProductProvider>(context);

    // Apply local search filter
    final filteredProducts = productProvider.products.where((p) {
      final nameMatches = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final idMatches = p.id.toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatches || idMatches;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF38BDF8),
        onPressed: () => _showProductDialog(),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Search Input Header
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cari barang berdasarkan nama atau kode induk...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
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
            const SizedBox(height: 20),

            // Products Grid/Table View
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: productProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredProducts.isEmpty
                        ? const Center(
                            child: Text(
                              'Tidak ada barang ditemukan.',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SizedBox(
                              width: double.infinity,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 52,
                                headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                columns: const [
                                  DataColumn(label: Text('KODE INDUK')),
                                  DataColumn(label: Text('NAMA BARANG')),
                                  DataColumn(label: Text('HARGA UNIT'), numeric: true),
                                  DataColumn(label: Text('STOK'), numeric: true),
                                  DataColumn(label: Text('ISI KARTON'), numeric: true),
                                  DataColumn(label: Text('BERAT'), numeric: true),
                                  DataColumn(label: Text('')),
                                ],
                                rows: filteredProducts.map((p) {
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(p.id, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                      DataCell(Text(p.name, style: const TextStyle(color: Colors.white))),
                                      DataCell(Text(_rupiahFormatter.format(p.price), style: const TextStyle(color: Colors.white))),
                                      DataCell(Text(p.stock.toStringAsFixed(0), style: TextStyle(color: p.stock <= 0 ? Colors.redAccent : Colors.greenAccent))),
                                      DataCell(Text('${p.isiKarton} Pcs', style: const TextStyle(color: Colors.white))),
                                      DataCell(Text('${p.sizeGrams.toStringAsFixed(0)} G', style: const TextStyle(color: Colors.white))),
                                      DataCell(
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 20),
                                              onPressed: () => _showProductDialog(p),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                              onPressed: () {
                                                // Confirm delete
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    backgroundColor: const Color(0xFF1E293B),
                                                    title: const Text('Hapus Produk', style: TextStyle(color: Colors.white)),
                                                    content: Text('Apakah Anda yakin ingin menghapus "${p.name}"?', style: const TextStyle(color: Color(0xFF94A3B8))),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context),
                                                        child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                                                      ),
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                        onPressed: () async {
                                                          await productProvider.deleteProduct(p.id);
                                                          if (context.mounted) Navigator.pop(context);
                                                        },
                                                        child: const Text('Hapus'),
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
          ],
        ),
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
    );
  }
}
