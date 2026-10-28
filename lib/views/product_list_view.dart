import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/product.dart';
import '../models/stock_entry.dart';
import '../models/stock_mutation.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../services/firebase_service.dart';
import '../services/import_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  String _formatIndoDateTime(DateTime dt) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    final hourStr = dt.hour.toString().padLeft(2, '0');
    final minStr = dt.minute.toString().padLeft(2, '0');
    return '$dayName, ${dt.day} $monthName ${dt.year} pk $hourStr:$minStr';
  }

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

  void _showProductDialog([Product? product]) {
    final isEdit = product != null;
    final double initialStock = product?.stock ?? 0.0;

    final idController = TextEditingController(text: product?.id ?? '');
    final kodeIndukController = TextEditingController(text: product?.kodeInduk ?? product?.id ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toStringAsFixed(0) : '');
    final pricePoSoController = TextEditingController(
      text: product != null && product.pricePoSo > 0
          ? (product.pricePoSo % 1 == 0 ? product.pricePoSo.toInt().toString() : product.pricePoSo.toString())
          : '',
    );
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
            bool isSavingProduct = false;
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
                              enabled: true, // Editable Kode Barang (ID)
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              decoration: _buildInputDecoration(hint: 'Kode Barang (ID)').copyWith(
                                labelText: 'Kode Barang (ID)',
                                labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Harga Unit Jual (Rp)').copyWith(
                                labelText: 'Harga Unit Jual',
                                labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: pricePoSoController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: _buildInputDecoration(hint: 'Harga PT PO / CV SO').copyWith(
                                labelText: 'Harga PT PO / CV SO',
                                labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                                helperText: 'Info ERP Pusat (Opsional)',
                                helperStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                              ),
                            ),
                          ),
                        ],
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
                                'Stok Awal Saat Ini: ${initialStock.toStringAsFixed(0)} Pack',
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
                                                      ? '+${entryDiff.toStringAsFixed(0)} Pack'
                                                      : '${entryDiff.toStringAsFixed(0)} Pack',
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
                              decoration: _buildInputDecoration(hint: 'Isi per Karton (Pack)'),
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
                    backgroundColor: isSavingProduct ? Colors.teal[800] : const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: isSavingProduct ? null : () async {
                    final id = idController.text.trim().toUpperCase();
                    final kodeIndukRaw = kodeIndukController.text.trim().toUpperCase();
                    final kodeInduk = kodeIndukRaw.isNotEmpty ? kodeIndukRaw : id;
                    final name = nameController.text.trim().toUpperCase();
                    final price = _parseCleanDouble(priceController.text);
                    final pricePoSo = _parseCleanDouble(pricePoSoController.text);
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

                    setDialogState(() => isSavingProduct = true);

                    try {
                      final localProduct = product;
                      if (localProduct != null) {
                        // Edit Existing Product
                        if (localProduct.id != id) {
                          await Provider.of<ProductProvider>(context, listen: false).deleteProduct(localProduct.id);
                        }
                        final updated = Product(
                          id: id,
                          kodeInduk: kodeInduk,
                          name: name,
                          price: price,
                          pricePoSo: pricePoSo,
                          stock: stock,
                          isiKarton: carton,
                          sizeGrams: size,
                        );
                        await Provider.of<ProductProvider>(context, listen: false).saveProduct(
                          updated,
                          logMutation: true,
                          oldStock: localProduct.stock,
                        );
                      } else {
                        // Create New Product
                        final newProd = Product(
                          id: id,
                          kodeInduk: kodeInduk,
                          name: name,
                          price: price,
                          pricePoSo: pricePoSo,
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
                      setDialogState(() => isSavingProduct = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan barang: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  child: isSavingProduct
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 8),
                            Text('Menyimpan...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        )
                      : Text(isEdit ? 'Simpan Data' : 'Tambah Barang', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  // -------------------------------------------------------------------
  // EXPORT EXCEL (.xlsx)
  // -------------------------------------------------------------------
  Future<void> _exportProductsToExcel(List<Product> products) async {
    try {
      final sheetName = 'Master Barang';
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      final cellBorder = excel_pkg.Border(
        borderStyle: excel_pkg.BorderStyle.Thin,
        borderColorHex: excel_pkg.ExcelColor.fromHexString('#000000'),
      );

      final titleStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 14,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
      );

      final headerStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final centerDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final leftDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Left,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final rightDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Right,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      // Row 0: Title
      var cTitle = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      cTitle.value = excel_pkg.TextCellValue('DATA MASTER BARANG CABANG JAWA TENGAH - PT PUTRA FIVA SEJAHTERA');
      cTitle.cellStyle = titleStyle;
      sheetObject.merge(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0),
      );

      // Row 2: Table Header
      final headers = ['KODE INDUK', 'NAMA BARANG', 'HARGA UNIT', 'STOK', 'ISI KARTON', 'TOTAL KARTON', 'BERAT (GRAM)'];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2));
        cell.value = excel_pkg.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int curRow = 3;
      for (final p in products) {
        final totalKartonStr = p.isiKarton > 0 ? (p.stock / p.isiKarton).toStringAsFixed(1) : '0';

        var c0 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow));
        c0.value = excel_pkg.TextCellValue(p.kodeInduk);
        c0.cellStyle = centerDataStyle;

        var c1 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow));
        c1.value = excel_pkg.TextCellValue(p.name);
        c1.cellStyle = leftDataStyle;

        var c2 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow));
        c2.value = excel_pkg.TextCellValue(_rupiahFormatter.format(p.price));
        c2.cellStyle = rightDataStyle;

        var c3 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: curRow));
        c3.value = excel_pkg.IntCellValue(p.stock.toInt());
        c3.cellStyle = centerDataStyle;

        var c4 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: curRow));
        c4.value = excel_pkg.TextCellValue('${p.isiKarton} Pack');
        c4.cellStyle = centerDataStyle;

        var c5 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: curRow));
        c5.value = excel_pkg.TextCellValue(totalKartonStr);
        c5.cellStyle = centerDataStyle;

        var c6 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: curRow));
        c6.value = excel_pkg.TextCellValue('${p.sizeGrams.toStringAsFixed(0)} G');
        c6.cellStyle = centerDataStyle;

        curRow++;
      }

      sheetObject.setColumnWidth(0, 16.0);
      sheetObject.setColumnWidth(1, 45.0);
      sheetObject.setColumnWidth(2, 18.0);
      sheetObject.setColumnWidth(3, 10.0);
      sheetObject.setColumnWidth(4, 14.0);
      sheetObject.setColumnWidth(5, 16.0);
      sheetObject.setColumnWidth(6, 14.0);

      List<int>? fileBytes = excel.encode();
      if (fileBytes != null) {
        final bytes = Uint8List.fromList(fileBytes);
        final fileName = 'Master_Barang_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel (.xlsx): $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // -------------------------------------------------------------------
  // CETAK & DOWNLOAD PDF
  // -------------------------------------------------------------------
  pw.Document _buildProductsPdfDoc(List<Product> products) {
    final doc = pw.Document();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Deduplicate products by Kode Induk (ambil salah satu saja jika ada Kode Induk yang sama)
    final Set<String> seenKodeInduk = {};
    final List<Product> pdfProducts = [];

    for (var p in products) {
      final key = p.kodeInduk.trim().isNotEmpty ? p.kodeInduk.trim().toUpperCase() : p.id.trim().toUpperCase();
      if (!seenKodeInduk.contains(key)) {
        seenKodeInduk.add(key);
        pdfProducts.add(p);
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Header Document
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DATA MASTER BARANG CABANG JAWA TENGAH',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'PT PUTRA FIVA SEJAHTERA',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Tanggal Cetak: $dateStr',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('LUCIFAX PFS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text('Total Items: ${pdfProducts.length}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 10),

            // Table
            pw.TableHelper.fromTextArray(
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              headerHeight: 24,
              cellHeight: 20,
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.center,
                6: pw.Alignment.center,
              },
              headers: ['Kode Induk', 'Nama Barang', 'Harga Unit', 'Stok', 'Isi Karton', 'Total Karton', 'Berat'],
              data: pdfProducts.map((p) {
                final totalKartonStr = p.isiKarton > 0 ? (p.stock / p.isiKarton).toStringAsFixed(1) : '0';
                return [
                  p.kodeInduk,
                  p.name,
                  _rupiahFormatter.format(p.price),
                  p.stock.toStringAsFixed(0),
                  '${p.isiKarton} Pack',
                  totalKartonStr,
                  '${p.sizeGrams.toStringAsFixed(0)} G',
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    return doc;
  }

  Future<void> _downloadProductsPdf(List<Product> products) async {
    try {
      final doc = _buildProductsPdfDoc(products);
      final bytes = await doc.save();
      final fileName = 'Master_Barang_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal download PDF: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _printProductsPdf(List<Product> products) async {
    try {
      final doc = _buildProductsPdfDoc(products);
      final fileName = 'Master_Barang_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: fileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e'), backgroundColor: Colors.redAccent),
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

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Toolbar: Search Bar + Summary Badges + Action Buttons
            if (isMobile) ...[
              Row(
                children: [
                  // Search Input Field
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Cari barang / kode...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
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
                          borderRadius: BorderRadius.circular(10.0),
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
                  const SizedBox(width: 8),

                  // 3-Dots Action Menu Button
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 22),
                      tooltip: 'Menu Fitur Master Barang',
                      color: const Color(0xFF0F172A),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                      ),
                      onSelected: (val) {
                        if (val == 'add') {
                          _showProductDialog();
                        } else if (val == 'mutasi') {
                          _showGlobalStockMutationHistory();
                        } else if (val == 'stok_fisik') {
                          _showPhysicalStockHistoryDialog();
                        } else if (val == 'import') {
                          _importProductsFromExcel();
                        } else if (val == 'export') {
                          _exportProductsToExcel(filteredProducts);
                        } else if (val == 'download_pdf') {
                          _downloadProductsPdf(filteredProducts);
                        } else if (val == 'pdf') {
                          _printProductsPdf(filteredProducts);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Tambah Barang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'mutasi',
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Riwayat Mutasi Stok (Semua)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'stok_fisik',
                          child: Row(
                            children: [
                              Icon(Icons.fact_check_outlined, color: Color(0xFF34D399), size: 20),
                              SizedBox(width: 12),
                              Text('Riwayat Stok Fisik', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem(
                          value: 'import',
                          child: Row(
                            children: [
                              Icon(Icons.file_upload_outlined, color: Colors.tealAccent, size: 20),
                              SizedBox(width: 12),
                              Text('Import Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.table_view_rounded, color: Color(0xFF4ADE80), size: 20),
                              SizedBox(width: 12),
                              Text('Export Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem(
                          value: 'download_pdf',
                          child: Row(
                            children: [
                              Icon(Icons.file_download_outlined, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Download PDF (.pdf)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF87171), size: 20),
                              SizedBox(width: 12),
                              Text('Cetak PDF Laporan', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Mobile Action Buttons: Mutasi Stok + Riwayat Stok Fisik
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _showGlobalStockMutationHistory(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 16),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Mutasi Stok',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _showPhysicalStockHistoryDialog(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF10B981)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fact_check_outlined, color: Color(0xFF34D399), size: 16),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Stok Fisik',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Desktop Toolbar Row
              Row(
                children: [
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

                  // Global Riwayat Mutasi Stok Button (Box Logo Icon)
                  Tooltip(
                    message: 'Riwayat Mutasi Stok / Stock Out (Semua Barang)',
                    child: InkWell(
                      onTap: () => _showGlobalStockMutationHistory(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0284C7)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Riwayat Mutasi Stok',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Riwayat Stok Fisik Button (Beside Riwayat Mutasi Stok)
                  Tooltip(
                    message: 'Riwayat Stok Fisik (Sebelum In & Akhir Periode)',
                    child: InkWell(
                      onTap: () => _showPhysicalStockHistoryDialog(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fact_check_outlined, color: Color(0xFF34D399), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Riwayat Stok Fisik',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 3-Dots Action Menu Button
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 24),
                      tooltip: 'Menu Fitur Master Barang',
                      color: const Color(0xFF0F172A),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                      ),
                      onSelected: (val) {
                        if (val == 'add') {
                          _showProductDialog();
                        } else if (val == 'mutasi') {
                          _showGlobalStockMutationHistory();
                        } else if (val == 'import') {
                          _importProductsFromExcel();
                        } else if (val == 'export') {
                          _exportProductsToExcel(filteredProducts);
                        } else if (val == 'download_pdf') {
                          _downloadProductsPdf(filteredProducts);
                        } else if (val == 'pdf') {
                          _printProductsPdf(filteredProducts);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Tambah Barang', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'mutasi',
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Riwayat Mutasi Stok (Semua)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'stok_fisik',
                          child: Row(
                            children: [
                              Icon(Icons.fact_check_outlined, color: Color(0xFF34D399), size: 20),
                              SizedBox(width: 12),
                              Text('Riwayat Stok Fisik', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem(
                          value: 'import',
                          child: Row(
                            children: [
                              Icon(Icons.file_upload_outlined, color: Colors.tealAccent, size: 20),
                              SizedBox(width: 12),
                              Text('Import Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.table_view_rounded, color: Color(0xFF4ADE80), size: 20),
                              SizedBox(width: 12),
                              Text('Export Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        const PopupMenuItem(
                          value: 'download_pdf',
                          child: Row(
                            children: [
                              Icon(Icons.file_download_outlined, color: Color(0xFF38BDF8), size: 20),
                              SizedBox(width: 12),
                              Text('Download PDF (.pdf)', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF87171), size: 20),
                              SizedBox(width: 12),
                              Text('Cetak PDF Laporan', style: TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // Summary Badges Banner (Scrollable horizontally on mobile)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSummaryBadge('Total Master Barang', '$totalItems Produk', const Color(0xFF38BDF8), Icons.inventory_2_rounded),
                  const SizedBox(width: 10),
                  _buildSummaryBadge('Stok Tersedia', '$inStockItems Produk', Colors.greenAccent, Icons.check_circle_outline_rounded),
                  const SizedBox(width: 10),
                  _buildSummaryBadge('Stok Habis (0)', '$outOfStockItems Produk', outOfStockItems > 0 ? Colors.redAccent : const Color(0xFF64748B), Icons.warning_amber_rounded),
                ],
              ),
            ),
            const SizedBox(height: 14),

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
                                    DataColumn(label: Text('TOTAL KARTON'), numeric: true),
                                    DataColumn(label: Text('BERAT'), numeric: true),
                                    DataColumn(label: Text('AKSI')),
                                  ],
                                  rows: filteredProducts.map((p) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(p.kodeInduk, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold))),
                                        DataCell(Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                                        DataCell(
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  _rupiahFormatter.format(p.price),
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                                ),
                                                if (p.pricePoSo > 0)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Text(
                                                      'PO/SO: ${_rupiahFormatter.format(p.pricePoSo)}',
                                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w500),
                                                    ),
                                                  )
                                                else
                                                  const SizedBox(height: 14),
                                              ],
                                            ),
                                          ),
                                        ),
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
                                        DataCell(Text('${p.isiKarton} Pack', style: const TextStyle(color: Colors.white))),
                                        DataCell(
                                          Text(
                                            p.isiKarton > 0 ? (p.stock / p.isiKarton).toStringAsFixed(1) : '-',
                                            style: TextStyle(
                                              color: p.isiKarton > 0 && p.stock > 0 ? const Color(0xFF38BDF8) : Colors.white70,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text('${p.sizeGrams.toStringAsFixed(0)} G', style: const TextStyle(color: Colors.white))),
                                        DataCell(
                                           PopupMenuButton<String>(
                                             icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                                             color: const Color(0xFF1E293B),
                                             tooltip: 'Menu Aksi',
                                             shape: RoundedRectangleBorder(
                                               borderRadius: BorderRadius.circular(10),
                                               side: const BorderSide(color: Color(0xFF334155)),
                                             ),
                                             onSelected: (value) {
                                               if (value == 'edit') {
                                                 _showProductDialog(p);
                                               } else if (value == 'history') {
                                                 _showStockMutationHistory(p);
                                               } else if (value == 'delete') {
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
                                               }
                                             },
                                             itemBuilder: (context) => [
                                               const PopupMenuItem(
                                                 value: 'edit',
                                                 child: Row(
                                                   children: [
                                                     Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 18),
                                                     SizedBox(width: 10),
                                                     Text('Edit Barang', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                   ],
                                                 ),
                                               ),
                                               const PopupMenuItem(
                                                 value: 'history',
                                                 child: Row(
                                                   children: [
                                                     Icon(Icons.history_rounded, color: Color(0xFF38BDF8), size: 18),
                                                     SizedBox(width: 10),
                                                     Text('Riwayat Mutasi', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                   ],
                                                 ),
                                               ),
                                               const PopupMenuDivider(height: 1),
                                               const PopupMenuItem(
                                                 value: 'delete',
                                                 child: Row(
                                                   children: [
                                                     Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                     SizedBox(width: 10),
                                                     Text('Hapus Barang', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                                   ],
                                                 ),
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

  // ==========================================
  // STOCK MUTATION DATE RANGE HELPERS
  // ==========================================

  Future<DateTime?> _showMonthYearPicker(BuildContext context, DateTime initialDate) async {
    int tempYear = initialDate.year;
    int tempMonth = initialDate.month;
    final months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];

    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setPickerState(() {
                        tempYear--;
                      });
                    },
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$tempYear',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setPickerState(() {
                        tempYear++;
                      });
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, idx) {
                    final mIndex = idx + 1;
                    final isSelected = tempMonth == mIndex && tempYear == initialDate.year;
                    final isCurrent = mIndex == DateTime.now().month && tempYear == DateTime.now().year;

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx, DateTime(tempYear, mIndex, 1));
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0284C7)
                              : (isCurrent ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : (isCurrent ? const Color(0xFF38BDF8).withOpacity(0.6) : const Color(0xFF334155)),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          months[idx],
                          style: TextStyle(
                            color: isSelected ? Colors.white : (isCurrent ? const Color(0xFF38BDF8) : Colors.white70),
                            fontWeight: isSelected || isCurrent ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _getMutationDateRange(
    String mode, {
    required DateTime selectedPeriodMonth,
    DateTime? customDate,
  }) {
    final now = DateTime.now();
    final y = selectedPeriodMonth.year;
    final m = selectedPeriodMonth.month;
    final lastDay = DateTime(y, m + 1, 0).day;

    DateTime? start;
    DateTime? end;
    String label;

    switch (mode) {
      case 'ALL':
        start = null;
        end = null;
        label = 'Semua Mutasi';
        break;
      case 'W1':
        start = DateTime(y, m, 1, 0, 0, 0);
        end = DateTime(y, m, 7, 23, 59, 59, 999);
        label = 'Minggu 1 (01 - 07 ${DateFormat('MMM yyyy').format(start)})';
        break;
      case 'W2':
        start = DateTime(y, m, 8, 0, 0, 0);
        end = DateTime(y, m, 14, 23, 59, 59, 999);
        label = 'Minggu 2 (08 - 14 ${DateFormat('MMM yyyy').format(start)})';
        break;
      case 'W3':
        start = DateTime(y, m, 15, 0, 0, 0);
        end = DateTime(y, m, 21, 23, 59, 59, 999);
        label = 'Minggu 3 (15 - 21 ${DateFormat('MMM yyyy').format(start)})';
        break;
      case 'W4':
        start = DateTime(y, m, 22, 0, 0, 0);
        end = DateTime(y, m, 28, 23, 59, 59, 999);
        label = 'Minggu 4 (22 - 28 ${DateFormat('MMM yyyy').format(start)})';
        break;
      case 'W5':
        start = DateTime(y, m, 29, 0, 0, 0);
        end = DateTime(y, m, lastDay, 23, 59, 59, 999);
        label = 'Minggu 5 (29 - $lastDay ${DateFormat('MMM yyyy').format(start)})';
        break;
      case 'MONTH':
        start = DateTime(y, m, 1, 0, 0, 0);
        end = DateTime(y, m, lastDay, 23, 59, 59, 999);
        final isCurrent = y == now.year && m == now.month;
        label = isCurrent
            ? 'Bulan Ini (${DateFormat('MMMM yyyy').format(start)})'
            : 'Bulan ${DateFormat('MMMM yyyy').format(start)}';
        break;
      case 'CUSTOM':
        final target = customDate ?? now;
        start = DateTime(target.year, target.month, target.day, 0, 0, 0);
        end = DateTime(target.year, target.month, target.day, 23, 59, 59, 999);
        label = 'Tanggal ${DateFormat('dd/MM/yyyy').format(target)}';
        break;
      case 'TODAY':
      default:
        start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        label = 'Hari Ini (${DateFormat('dd/MM/yyyy').format(now)})';
        break;
    }
    return {'start': start, 'end': end, 'label': label};
  }

  Widget _buildMutationFilterChips({
    required BuildContext context,
    required String currentMode,
    required DateTime selectedPeriodMonth,
    required DateTime? customDate,
    required Function(String mode, DateTime selectedMonth, DateTime? custom) onFilterChanged,
  }) {
    final now = DateTime.now();
    final isCurrentMonth = selectedPeriodMonth.year == now.year && selectedPeriodMonth.month == now.month;
    final monthChipLabel = isCurrentMonth
        ? 'Bulan Ini'
        : DateFormat('MMM yyyy').format(selectedPeriodMonth);

    final chips = [
      {'label': 'Hari Ini', 'mode': 'TODAY', 'icon': Icons.bolt_rounded},
      {'label': 'Semua Mutasi', 'mode': 'ALL', 'icon': Icons.all_inclusive_rounded},
      {'label': 'M1 (1-7)', 'mode': 'W1', 'icon': null},
      {'label': 'M2 (8-14)', 'mode': 'W2', 'icon': null},
      {'label': 'M3 (15-21)', 'mode': 'W3', 'icon': null},
      {'label': 'M4 (22-28)', 'mode': 'W4', 'icon': null},
      {'label': 'M5 (29+)', 'mode': 'W5', 'icon': null},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var c in chips) ...[
            Builder(builder: (context) {
              final mode = c['mode'] as String;
              final isSelected = currentMode == mode;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => onFilterChanged(mode, selectedPeriodMonth, null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                        width: isSelected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c['icon'] != null) ...[
                          Icon(c['icon'] as IconData, color: isSelected ? Colors.white : const Color(0xFF38BDF8), size: 14),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          c['label'] as String,
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          // Dynamic Month Selector Chip
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () async {
                final picked = await _showMonthYearPicker(context, selectedPeriodMonth);
                if (picked != null) {
                  onFilterChanged('MONTH', picked, null);
                } else if (currentMode != 'MONTH') {
                  onFilterChanged('MONTH', selectedPeriodMonth, null);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: currentMode == 'MONTH' ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: currentMode == 'MONTH' ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                    width: currentMode == 'MONTH' ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_view_month_rounded,
                      color: currentMode == 'MONTH' ? Colors.white : const Color(0xFF38BDF8),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      monthChipLabel,
                      style: TextStyle(
                        color: currentMode == 'MONTH' ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: currentMode == 'MONTH' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: currentMode == 'MONTH' ? Colors.white70 : const Color(0xFF64748B),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Custom Calendar Date Picker Button
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: customDate ?? DateTime.now(),
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFF0284C7),
                        onPrimary: Colors.white,
                        surface: Color(0xFF1E293B),
                        onSurface: Colors.white,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                onFilterChanged('CUSTOM', selectedPeriodMonth, picked);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: currentMode == 'CUSTOM' ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: currentMode == 'CUSTOM' ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  width: currentMode == 'CUSTOM' ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_rounded, color: currentMode == 'CUSTOM' ? Colors.white : const Color(0xFF38BDF8), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    currentMode == 'CUSTOM' && customDate != null
                        ? DateFormat('dd/MM/yyyy').format(customDate)
                        : 'Pilih Tanggal',
                    style: TextStyle(
                      color: currentMode == 'CUSTOM' ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: currentMode == 'CUSTOM' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteMutation(BuildContext dialogCtx, StockMutation m) {
    showDialog(
      context: dialogCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Hapus Log Mutasi?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus log mutasi untuk ${m.productName} (${m.qty > 0 ? "+${m.qty.toStringAsFixed(0)}" : m.qty.toStringAsFixed(0)} Pack) tanggal ${DateFormat("dd/MM/yyyy HH:mm").format(m.timestamp)}?\n\nCatatan: Tindakan ini hanya menghapus catatan log riwayat dan tidak mengubah stok fisik di master barang.',
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                if (m.id.isNotEmpty) {
                  await FirebaseFirestore.instance.collection('stock_mutations').doc(m.id).delete();
                } else {
                  final snap = await FirebaseFirestore.instance.collection('stock_mutations')
                      .where('kodeInduk', isEqualTo: m.kodeInduk)
                      .where('qty', isEqualTo: m.qty)
                      .where('reference', isEqualTo: m.reference)
                      .get();
                  for (var doc in snap.docs) {
                    await doc.reference.delete();
                  }
                }
                if (dialogCtx.mounted) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Log mutasi berhasil dihapus.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (dialogCtx.mounted) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menghapus log mutasi: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Hapus Log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SINGLE PRODUCT STOCK MUTATION DIALOG
  // ==========================================

  void _showStockMutationHistory(Product product) {
    final firebaseService = FirebaseService();
    String dialogSearchQuery = '';
    String filterMode = 'TODAY'; // Default: TODAY
    DateTime selectedPeriodMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime? customDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final range = _getMutationDateRange(
              filterMode,
              selectedPeriodMonth: selectedPeriodMonth,
              customDate: customDate,
            );

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Riwayat Mutasi Stok',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.name} (${product.kodeInduk})',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Quick Filter Period Chips Row
                  _buildMutationFilterChips(
                    context: context,
                    currentMode: filterMode,
                    selectedPeriodMonth: selectedPeriodMonth,
                    customDate: customDate,
                    onFilterChanged: (newMode, newMonth, newCustom) {
                      setDialogState(() {
                        filterMode = newMode;
                        selectedPeriodMonth = newMonth;
                        if (newCustom != null) customDate = newCustom;
                      });
                    },
                  ),
                  const SizedBox(height: 10),

                  // Filter Row: Search Text Input + Active Range Badge
                  Row(
                    children: [
                      // Text Search Input
                      Expanded(
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Cari invoice, referensi...',
                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              dialogSearchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Active Range Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 14),
                            const SizedBox(width: 6),
                            Text(
                              range['label'],
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 768;
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final isDeveloper = authProvider.currentUser?.role == 'developer' || authProvider.currentUser?.role == 'admin';

                  return SizedBox(
                    width: isMobile ? double.maxFinite : 980,
                    height: 440,
                    child: StreamBuilder<List<StockMutation>>(
                      stream: firebaseService.streamStockMutations(
                        product.kodeInduk,
                        startDate: range['start'],
                        endDate: range['end'],
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                          );
                        }
                        var mutations = snapshot.data ?? [];

                        // Apply Text Search Filter
                        if (dialogSearchQuery.isNotEmpty) {
                          mutations = mutations.where((m) {
                            return m.reference.toLowerCase().contains(dialogSearchQuery) ||
                                m.customerName.toLowerCase().contains(dialogSearchQuery) ||
                                m.type.toLowerCase().contains(dialogSearchQuery);
                          }).toList();
                        }

                        if (mutations.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_rounded, color: Colors.white.withOpacity(0.2), size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Belum ada mutasi stok pada ${range['label']}.',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }

                        // Summary Stats (Pack & Karton)
                        double totalKeluarPack = 0;
                        double totalMasukPack = 0;
                        double totalKeluarKarton = 0;
                        double totalMasukKarton = 0;

                        for (var m in mutations) {
                          final double karton = product.isiKarton > 0 ? (m.qty.abs() / product.isiKarton) : 0.0;
                          if (m.qty < 0) {
                            totalKeluarPack += m.qty.abs();
                            totalKeluarKarton += karton;
                          } else {
                            totalMasukPack += m.qty;
                            totalMasukKarton += karton;
                          }
                        }

                        String formatKarton(double ktn) {
                          return (ktn % 1 == 0) ? '${ktn.toInt()} Karton' : '${ktn.toStringAsFixed(1)} Karton';
                        }

                        return Column(
                          children: [
                            // Summary Banner inside Dialog
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF334155)),
                              ),
                              child: isMobile
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ditemukan: ${mutations.length} Mutasi (${range['label']})',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Stock Out: -${totalKeluarPack.toStringAsFixed(0)} Pack (${formatKarton(totalKeluarKarton)})',
                                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                            Text(
                                              'Stock In: +${totalMasukPack.toStringAsFixed(0)} Pack (${formatKarton(totalMasukKarton)})',
                                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Ditemukan: ${mutations.length} Mutasi (${range['label']})',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              'Total Stock Out: -${totalKeluarPack.toStringAsFixed(0)} Pack (${formatKarton(totalKeluarKarton)})',
                                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                            const SizedBox(width: 16),
                                            Text(
                                              'Total Stock In: +${totalMasukPack.toStringAsFixed(0)} Pack (${formatKarton(totalMasukKarton)})',
                                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minWidth: isDeveloper ? 950 : 880),
                                    child: DataTable(
                                columnSpacing: 12,
                                horizontalMargin: 0,
                                headingRowHeight: 36,
                                dataRowMinHeight: 34,
                                dataRowMaxHeight: 50,
                                headingTextStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                columns: [
                                  const DataColumn(label: Text('NO')),
                                  const DataColumn(label: Text('TANGGAL')),
                                  const DataColumn(label: Text('ISI PER KARTON'), numeric: true),
                                  const DataColumn(label: Text('JENIS')),
                                  const DataColumn(label: Text('QTY'), numeric: true),
                                  const DataColumn(label: Text('TOTAL KARTON'), numeric: true),
                                  const DataColumn(label: Text('STOK'), numeric: true),
                                  const DataColumn(label: Text('REFERENSI')),
                                  if (isDeveloper) const DataColumn(label: Text('AKSI')),
                                ],
                                rows: mutations.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final m = entry.value;
                                  Color typeColor;
                                  String typeLabel;
                                  IconData typeIcon;
                                  switch (m.type) {
                                    case 'KELUAR':
                                      typeColor = Colors.redAccent;
                                      typeLabel = 'Keluar';
                                      typeIcon = Icons.arrow_downward_rounded;
                                      break;
                                    case 'MASUK':
                                      typeColor = Colors.greenAccent;
                                      typeLabel = 'Masuk';
                                      typeIcon = Icons.arrow_upward_rounded;
                                      break;
                                    case 'RETUR_STATUS':
                                      typeColor = Colors.orangeAccent;
                                      typeLabel = 'Retur Status';
                                      typeIcon = Icons.undo_rounded;
                                      break;
                                    case 'HAPUS_INVOICE':
                                      typeColor = Colors.orangeAccent;
                                      typeLabel = 'Hapus Invoice';
                                      typeIcon = Icons.delete_outline_rounded;
                                      break;
                                    case 'EDIT_MANUAL':
                                      typeColor = const Color(0xFF38BDF8);
                                      typeLabel = 'Edit Manual';
                                      typeIcon = Icons.edit_outlined;
                                      break;
                                    case 'INPUT_STOK':
                                      typeColor = Colors.greenAccent;
                                      typeLabel = 'Input Stok';
                                      typeIcon = Icons.add_box_outlined;
                                      break;
                                    default:
                                      typeColor = const Color(0xFF94A3B8);
                                      typeLabel = m.type;
                                      typeIcon = Icons.swap_vert_rounded;
                                  }

                                  final qtyStr = m.qty > 0 ? '+${m.qty.toStringAsFixed(0)}' : m.qty.toStringAsFixed(0);

                                  String totalKartonStr = '-';
                                  if (product.isiKarton > 0 && m.qty != 0) {
                                    final totalKtn = m.qty / product.isiKarton;
                                    final formattedKtn = (totalKtn.abs() % 1 == 0)
                                        ? totalKtn.toInt().toString()
                                        : totalKtn.toStringAsFixed(1);
                                    totalKartonStr = totalKtn > 0 ? '+$formattedKtn Ktn' : '$formattedKtn Ktn';
                                  }

                                  return DataRow(
                                    cells: [
                                      DataCell(Text(
                                        '${idx + 1}',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11),
                                      )),
                                      DataCell(Text(
                                        DateFormat('dd/MM/yy HH:mm').format(m.timestamp),
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      )),
                                      DataCell(Text(
                                        product.isiKarton > 0 ? '${product.isiKarton} Pack' : '-',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                      )),
                                      DataCell(Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(typeIcon, color: typeColor, size: 14),
                                          const SizedBox(width: 4),
                                          Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      )),
                                      DataCell(Text(
                                        qtyStr,
                                        style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                      )),
                                      DataCell(Text(
                                        totalKartonStr,
                                        style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                                      )),
                                      DataCell(Text(
                                        '${m.stockBefore.toStringAsFixed(0)} → ${m.stockAfter.toStringAsFixed(0)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                      )),
                                      DataCell(
                                        Tooltip(
                                          message: m.customerName.isNotEmpty ? '${m.reference}\n${m.customerName}' : m.reference,
                                          child: Text(
                                            m.customerName.isNotEmpty ? '${m.reference} (${m.customerName})' : m.reference,
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      if (isDeveloper)
                                        DataCell(
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                            tooltip: 'Hapus Log Mutasi (Developer)',
                                            onPressed: () => _confirmDeleteMutation(context, m),
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
                  );
                },
              ),
            );
          },
        ),
        actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // GLOBAL STOCK MUTATION HISTORY DIALOG (SEMUA BARANG)
  // ==========================================

  void _showGlobalStockMutationHistory() {
    final firebaseService = FirebaseService();
    String dialogSearchQuery = '';
    String selectedType = 'SEMUA';
    String filterMode = 'TODAY'; // Default: TODAY
    DateTime selectedPeriodMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime? customDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final range = _getMutationDateRange(
              filterMode,
              selectedPeriodMonth: selectedPeriodMonth,
              customDate: customDate,
            );
            final isMobile = MediaQuery.of(context).size.width < 768;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 24,
                vertical: isMobile ? 12 : 24,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMobile ? 'Riwayat Mutasi Stok' : 'Riwayat Mutasi Stok / Stock Out (Semua Barang)',
                              style: TextStyle(color: Colors.white, fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pencatatan semua barang keluar, masuk, retur, dan penyesuaian stok terpusat.',
                              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 10 : 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Quick Filter Period Chips Row
                  _buildMutationFilterChips(
                    context: context,
                    currentMode: filterMode,
                    selectedPeriodMonth: selectedPeriodMonth,
                    customDate: customDate,
                    onFilterChanged: (newMode, newMonth, newCustom) {
                      setDialogState(() {
                        filterMode = newMode;
                        selectedPeriodMonth = newMonth;
                        if (newCustom != null) customDate = newCustom;
                      });
                    },
                  ),
                  const SizedBox(height: 10),

                  // Filter Row: Search Input + Type Filter + Active Range Badge
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Text Search Input
                      SizedBox(
                        width: isMobile ? double.infinity : 320,
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Cari nama barang, kode, invoice...',
                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              dialogSearchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),

                      // Dropdown Type Filter
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedType,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 'SEMUA', child: Text('Semua Mutasi')),
                              DropdownMenuItem(value: 'KELUAR', child: Text('🔴 Keluar (Stock Out)')),
                              DropdownMenuItem(value: 'MASUK', child: Text('🟢 Masuk')),
                              DropdownMenuItem(value: 'RETUR_STATUS', child: Text('🟠 Retur Status')),
                              DropdownMenuItem(value: 'EDIT_MANUAL', child: Text('🔵 Edit Manual')),
                              DropdownMenuItem(value: 'INPUT_STOK', child: Text('🟢 Input Stok')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedType = val;
                                });
                              }
                            },
                          ),
                        ),
                      ),

                      // Active Range Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 14),
                            const SizedBox(width: 6),
                            Text(
                              range['label'],
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 768;
                  final authProvider = Provider.of<AuthProvider>(context, listen: false);
                  final isDeveloper = authProvider.currentUser?.role == 'developer' || authProvider.currentUser?.role == 'admin';
                  return SizedBox(
                    width: isMobile ? double.maxFinite : 1240,
                    height: isMobile ? MediaQuery.of(context).size.height * 0.6 : 480,
                    child: StreamBuilder<List<StockMutation>>(
                  stream: firebaseService.streamAllStockMutations(
                    startDate: range['start'],
                    endDate: range['end'],
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)));
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                      );
                    }
                    var mutations = snapshot.data ?? [];

                    // Apply Type Filter
                    if (selectedType != 'SEMUA') {
                      mutations = mutations.where((m) => m.type == selectedType).toList();
                    }

                    // Apply Text Search Filter
                    if (dialogSearchQuery.isNotEmpty) {
                      mutations = mutations.where((m) {
                        return m.kodeInduk.toLowerCase().contains(dialogSearchQuery) ||
                            m.productName.toLowerCase().contains(dialogSearchQuery) ||
                            m.reference.toLowerCase().contains(dialogSearchQuery) ||
                            m.customerName.toLowerCase().contains(dialogSearchQuery);
                      }).toList();
                    }

                    if (mutations.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded, color: Colors.white.withOpacity(0.2), size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'Belum ada riwayat mutasi stok pada ${range['label']}.',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    final productProvider = Provider.of<ProductProvider>(context, listen: false);
                    final prodMap = {for (var p in productProvider.products) p.kodeInduk: p};

                    // Summary Stats (Pack & Karton)
                    double totalKeluarPack = 0;
                    double totalMasukPack = 0;
                    double totalKeluarKarton = 0;
                    double totalMasukKarton = 0;

                    for (var m in mutations) {
                      Product? p = prodMap[m.kodeInduk];
                      if (p == null) {
                        for (var prod in productProvider.products) {
                          if (prod.name.toLowerCase() == m.productName.toLowerCase() || prod.kodeInduk == m.kodeInduk) {
                            p = prod;
                            break;
                          }
                        }
                      }
                      final isiKarton = p?.isiKarton ?? 0;
                      final double karton = isiKarton > 0 ? (m.qty.abs() / isiKarton) : 0.0;

                      if (m.qty < 0) {
                        totalKeluarPack += m.qty.abs();
                        totalKeluarKarton += karton;
                      } else {
                        totalMasukPack += m.qty;
                        totalMasukKarton += karton;
                      }
                    }

                    String formatKarton(double ktn) {
                      return (ktn % 1 == 0) ? '${ktn.toInt()} Karton' : '${ktn.toStringAsFixed(1)} Karton';
                    }

                    return Column(
                      children: [
                        // Summary Banner inside Dialog
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: isMobile
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ditemukan: ${mutations.length} Mutasi (${range['label']})',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Stock Out: -${totalKeluarPack.toStringAsFixed(0)} Pack (${formatKarton(totalKeluarKarton)})',
                                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                        Text(
                                          'Stock In: +${totalMasukPack.toStringAsFixed(0)} Pack (${formatKarton(totalMasukKarton)})',
                                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Ditemukan: ${mutations.length} Mutasi (${range['label']})',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Total Stock Out: -${totalKeluarPack.toStringAsFixed(0)} Pack (${formatKarton(totalKeluarKarton)})',
                                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'Total Stock In: +${totalMasukPack.toStringAsFixed(0)} Pack (${formatKarton(totalMasukKarton)})',
                                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),

                        // Table Content
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: isDeveloper ? 1220 : 1120),
                                child: DataTable(
                                  columnSpacing: 10,
                                  horizontalMargin: 0,
                                  headingRowHeight: 36,
                                  dataRowMinHeight: 34,
                                  dataRowMaxHeight: 50,
                                  headingTextStyle: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                  columns: [
                                    const DataColumn(label: Text('NO')),
                                    const DataColumn(label: Text('TANGGAL')),
                                    const DataColumn(label: Text('KODE INDUK')),
                                    const DataColumn(label: Text('NAMA BARANG')),
                                    const DataColumn(label: Text('ISI PER KARTON'), numeric: true),
                                    const DataColumn(label: Text('JENIS')),
                                    const DataColumn(label: Text('QTY'), numeric: true),
                                    const DataColumn(label: Text('TOTAL KARTON'), numeric: true),
                                    const DataColumn(label: Text('STOK'), numeric: true),
                                    const DataColumn(label: Text('REFERENSI')),
                                    if (isDeveloper) const DataColumn(label: Text('AKSI')),
                                  ],
                                  rows: mutations.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final m = entry.value;

                                    Product? p = prodMap[m.kodeInduk];
                                    if (p == null) {
                                      for (var prod in productProvider.products) {
                                        if (prod.name.toLowerCase() == m.productName.toLowerCase() || prod.kodeInduk == m.kodeInduk) {
                                          p = prod;
                                          break;
                                        }
                                      }
                                    }
                                    final isiKarton = p?.isiKarton ?? 0;

                                    Color typeColor;
                                    String typeLabel;
                                    IconData typeIcon;
                                    switch (m.type) {
                                      case 'KELUAR':
                                        typeColor = Colors.redAccent;
                                        typeLabel = 'Keluar';
                                        typeIcon = Icons.arrow_downward_rounded;
                                        break;
                                      case 'MASUK':
                                        typeColor = Colors.greenAccent;
                                        typeLabel = 'Masuk';
                                        typeIcon = Icons.arrow_upward_rounded;
                                        break;
                                      case 'RETUR_STATUS':
                                        typeColor = Colors.orangeAccent;
                                        typeLabel = 'Retur Status';
                                        typeIcon = Icons.undo_rounded;
                                        break;
                                      case 'HAPUS_INVOICE':
                                        typeColor = Colors.orangeAccent;
                                        typeLabel = 'Hapus Invoice';
                                        typeIcon = Icons.delete_outline_rounded;
                                        break;
                                      case 'EDIT_MANUAL':
                                        typeColor = const Color(0xFF38BDF8);
                                        typeLabel = 'Edit Manual';
                                        typeIcon = Icons.edit_outlined;
                                        break;
                                      case 'INPUT_STOK':
                                        typeColor = Colors.greenAccent;
                                        typeLabel = 'Input Stok';
                                        typeIcon = Icons.add_box_outlined;
                                        break;
                                      default:
                                        typeColor = const Color(0xFF94A3B8);
                                        typeLabel = m.type;
                                        typeIcon = Icons.swap_vert_rounded;
                                    }

                                    final qtyStr = m.qty > 0 ? '+${m.qty.toStringAsFixed(0)}' : m.qty.toStringAsFixed(0);

                                    String totalKartonStr = '-';
                                    if (isiKarton > 0 && m.qty != 0) {
                                      final totalKtn = m.qty / isiKarton;
                                      final formattedKtn = (totalKtn.abs() % 1 == 0)
                                          ? totalKtn.toInt().toString()
                                          : totalKtn.toStringAsFixed(1);
                                      totalKartonStr = totalKtn > 0 ? '+$formattedKtn Ktn' : '$formattedKtn Ktn';
                                    }

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(
                                          '${idx + 1}',
                                          style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11),
                                        )),
                                        DataCell(Text(
                                          DateFormat('dd/MM/yy HH:mm').format(m.timestamp),
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        )),
                                        DataCell(Text(
                                          m.kodeInduk,
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                                        )),
                                        DataCell(Text(
                                          m.productName,
                                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                                        )),
                                        DataCell(Text(
                                          isiKarton > 0 ? '$isiKarton Pack' : '-',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                        )),
                                        DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(typeIcon, color: typeColor, size: 14),
                                            const SizedBox(width: 4),
                                            Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                          ],
                                        )),
                                        DataCell(Text(
                                          qtyStr,
                                          style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                        )),
                                        DataCell(Text(
                                          totalKartonStr,
                                          style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                                        )),
                                        DataCell(Text(
                                          '${m.stockBefore.toStringAsFixed(0)} → ${m.stockAfter.toStringAsFixed(0)}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        )),
                                        DataCell(
                                          Tooltip(
                                            message: m.customerName.isNotEmpty ? '${m.reference}\n${m.customerName}' : m.reference,
                                            child: Text(
                                              m.customerName.isNotEmpty ? '${m.reference} (${m.customerName})' : m.reference,
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        if (isDeveloper)
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                              tooltip: 'Hapus Log Mutasi (Developer)',
                                              onPressed: () => _confirmDeleteMutation(context, m),
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
                    );
                  },
                ),
              );
            },
          ),
          actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===================================================================
  // RIWAYAT STOK FISIK (MINGGUAN & AKHIR BULAN)
  // ===================================================================

  Widget _buildPhysicalStockTotalBadge(String label, String packText, String ctnText, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        Text(
          '$packText ',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          '($ctnText)',
          style: TextStyle(color: color.withOpacity(0.85), fontSize: 10),
        ),
      ],
    );
  }

  // ===================================================================
  // KALKULATOR ESTAFET RIWAYAT STOK FISIK (CHAINED LEDGER)
  // ===================================================================

  List<_PhysicalStockItem> _calculateChainedPhysicalStock({
    required List<Product> products,
    required List<StockEntry> allEntries,
    required List<StockMutation> allMutations,
    required int selectedYear,
    required int selectedMonth,
    required int selectedWeek, // 0 = Semua Minggu, 1..maxWeek
    required int maxWeek,
    required Map<int, List<int>> weekDaysMap,
    Map<String, dynamic>? snapshotData,
    bool isLocked = false,
  }) {
    // 1. Deduplicate catalog products by kodeInduk
    final Map<String, Product> uniqueProducts = {};
    for (var p in products) {
      final key = p.kodeInduk.trim().isNotEmpty ? p.kodeInduk.trim().toUpperCase() : p.id.trim().toUpperCase();
      if (!uniqueProducts.containsKey(key)) {
        uniqueProducts[key] = p;
      }
    }
    final List<Product> catalogProducts = uniqueProducts.values.toList();
    catalogProducts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // 2. Week boundaries
    final Map<int, DateTime> weekStartMap = {};
    final Map<int, DateTime> weekEndMap = {};
    for (int w = 1; w <= maxWeek; w++) {
      final days = weekDaysMap[w] ?? [1];
      weekStartMap[w] = DateTime(selectedYear, selectedMonth, days.first, 0, 0, 0);
      weekEndMap[w] = DateTime(selectedYear, selectedMonth, days.last, 23, 59, 59, 999);
    }

    final List<_PhysicalStockItem> resultItems = [];

    // 3. For each product, compute week 1 .. maxWeek chained sequentially
    for (var p in catalogProducts) {
      final String pKey = p.kodeInduk.trim().toLowerCase();
      final String pId = p.id.trim().toLowerCase();
      final String pNameLower = p.name.trim().toLowerCase();

      final prodEntries = allEntries.where((e) {
        final eKey = e.productId.trim().toLowerCase();
        final eName = e.productName.trim().toLowerCase();
        return (eKey == pKey || eKey == pId || eName == pNameLower);
      }).toList();

      final prodMutations = allMutations.where((m) {
        final mKey = m.kodeInduk.trim().toLowerCase();
        final mName = m.productName.trim().toLowerCase();
        return (mKey == pKey || mKey == pId || mName == pNameLower);
      }).toList();
      prodMutations.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Determine baseline stock on Day 1 of the month
      double monthBaselineStock;
      if (isLocked && snapshotData != null && snapshotData['items'] != null) {
        final itemsMap = snapshotData['items'] as Map<String, dynamic>;
        final itemData = itemsMap[p.kodeInduk.trim().toUpperCase()] ?? itemsMap[p.id.trim().toUpperCase()];
        monthBaselineStock = (itemData?['initialStock'] as num?)?.toDouble() ?? p.stock;
      } else {
        if (prodMutations.isNotEmpty) {
          monthBaselineStock = prodMutations.first.stockBefore;
        } else if (prodEntries.isNotEmpty && prodEntries.first.stockBefore != null) {
          monthBaselineStock = prodEntries.first.stockBefore!;
        } else {
          monthBaselineStock = p.stock;
        }
      }

      // Sequential loop for each week (Estafet)
      double runningStock = monthBaselineStock;
      final Map<int, _PhysicalStockItem> weekMap = {};

      for (int w = 1; w <= maxWeek; w++) {
        final wStart = weekStartMap[w]!;
        final wEnd = weekEndMap[w]!;
        final wInitial = runningStock;

        // Inflow entries for week w
        final wEntries = prodEntries.where((e) {
          if (e.weekNumber == w) return true;
          return e.date.isAfter(wStart.subtract(const Duration(seconds: 1))) &&
              e.date.isBefore(wEnd.add(const Duration(seconds: 1)));
        }).toList();

        // Mutations for week w
        final wMutations = prodMutations.where((m) {
          return m.timestamp.isAfter(wStart.subtract(const Duration(seconds: 1))) &&
              m.timestamp.isBefore(wEnd.add(const Duration(seconds: 1)));
        }).toList();

        // Calculate total inflow (Pabrik)
        double wInflow = wEntries.fold(0.0, (acc, e) => acc + e.qty);
        for (var m in wMutations) {
          if (m.type == 'INPUT_STOK' && wEntries.isEmpty) {
            wInflow += m.qty.abs();
          }
        }

        // Calculate adjustments (Edit Manual Master Barang / Koreksi Opname)
        double wAdjust = 0.0;
        for (var m in wMutations) {
          if (m.type == 'EDIT_MANUAL' || m.type == 'RETUR_STATUS') {
            wAdjust += m.qty;
          }
        }

        // Calculate pure sales / outflow (Invoice pelanggan / pengeluaran toko)
        double wOutflow = 0.0;
        for (var m in wMutations) {
          if (m.type != 'EDIT_MANUAL' && m.type != 'INPUT_STOK' && m.type != 'RETUR_STATUS') {
            if (m.type == 'KELUAR' || m.qty < 0) {
              wOutflow += m.qty.abs();
            }
          }
        }

        // Look for exact arrival date and time of incoming shipment
        DateTime? wIncomingDate;
        if (wEntries.isNotEmpty) {
          wEntries.sort((a, b) => a.date.compareTo(b.date));
          wIncomingDate = wEntries.first.createdAt ?? wEntries.first.date;
        } else {
          final inputMuts = wMutations.where((m) => m.type == 'INPUT_STOK').toList();
          if (inputMuts.isNotEmpty) {
            inputMuts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            wIncomingDate = inputMuts.first.timestamp;
          }
        }

        double? wStockBeforeIn;
        double wSalesBeforeIn = 0.0;
        double wAdjustBeforeIn = 0.0;

        if (wIncomingDate != null) {
          // Calculate sales & adjustments before arrival
          for (var m in wMutations) {
            if (m.timestamp.isBefore(wIncomingDate)) {
              if (m.type == 'EDIT_MANUAL' || m.type == 'RETUR_STATUS') {
                wAdjustBeforeIn += m.qty;
              } else if (m.type != 'INPUT_STOK' && (m.type == 'KELUAR' || m.qty < 0)) {
                wSalesBeforeIn += m.qty.abs();
              }
            }
          }
          wStockBeforeIn = wInitial + wAdjustBeforeIn - wSalesBeforeIn;
        }

        final wFinal = wInitial + wInflow + wAdjust - wOutflow;

        weekMap[w] = _PhysicalStockItem(
          product: p,
          initialStock: wInitial,
          stockBeforeIn: wStockBeforeIn,
          inflow: wInflow,
          adjust: wAdjust,
          outflow: wOutflow,
          finalStock: wFinal,
          hasIncomingInPeriod: wIncomingDate != null,
          incomingDate: wIncomingDate,
          salesBeforeIncoming: wSalesBeforeIn,
          adjustBeforeIncoming: wAdjustBeforeIn,
        );

        // Relay to next week's initial stock (Hukum Estafet)
        runningStock = wFinal;
      }

      // Format output according to selectedWeek
      if (selectedWeek > 0) {
        resultItems.add(weekMap[selectedWeek]!);
      } else {
        // Rekap Bulanan (Semua Minggu)
        final double monthInitial = weekMap[1]!.initialStock;
        final double monthFinal = weekMap[maxWeek]!.finalStock;
        double monthInflow = 0.0;
        double monthAdjust = 0.0;
        double monthOutflow = 0.0;
        double? earliestStockBeforeIn;
        DateTime? earliestIncomingDate;
        double earliestSalesBeforeIn = 0.0;
        double earliestAdjustBeforeIn = 0.0;

        for (int w = 1; w <= maxWeek; w++) {
          final item = weekMap[w]!;
          monthInflow += item.inflow;
          monthAdjust += item.adjust;
          monthOutflow += item.outflow;
          if (earliestStockBeforeIn == null && item.stockBeforeIn != null) {
            earliestStockBeforeIn = item.stockBeforeIn;
            earliestIncomingDate = item.incomingDate;
            earliestSalesBeforeIn = item.salesBeforeIncoming;
            earliestAdjustBeforeIn = item.adjustBeforeIncoming;
          }
        }

        resultItems.add(_PhysicalStockItem(
          product: p,
          initialStock: monthInitial,
          stockBeforeIn: earliestStockBeforeIn,
          inflow: monthInflow,
          adjust: monthAdjust,
          outflow: monthOutflow,
          finalStock: monthFinal,
          hasIncomingInPeriod: earliestIncomingDate != null,
          incomingDate: earliestIncomingDate,
          salesBeforeIncoming: earliestSalesBeforeIn,
          adjustBeforeIncoming: earliestAdjustBeforeIn,
        ));
      }
    }

    return resultItems;
  }

  void _showPhysicalStockHistoryDialog() {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isDeveloper = authProvider.currentUser?.role == 'developer' || authProvider.currentUser?.role == 'admin';

    int selectedYear = DateTime.now().year;
    int selectedMonth = DateTime.now().month;
    int selectedWeek = 0; // 0 = Semua Minggu (Rekap Bulanan)
    String unitMode = 'PACK'; // 'PACK' or 'KARTON'
    String dialogSearchQuery = '';
    bool isLocking = false;

    final List<String> monthNames = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final List<String> monthNamesShort = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMobile = MediaQuery.of(context).size.width < 768;

            // Calendar calculations for selectedYear and selectedMonth
            final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
            final firstDay = DateTime(selectedYear, selectedMonth, 1);
            final firstDayOffset = firstDay.weekday % 7; // Sunday = 0
            int getWeek(int day) => ((day - 1 + firstDayOffset) ~/ 7) + 1;

            final Map<int, List<int>> weekDaysMap = {};
            for (int d = 1; d <= daysInMonth; d++) {
              final w = getWeek(d);
              weekDaysMap.putIfAbsent(w, () => []).add(d);
            }
            final int maxWeek = weekDaysMap.keys.isEmpty ? 5 : weekDaysMap.keys.reduce((a, b) => a > b ? a : b);
            if (selectedWeek > maxWeek) {
              selectedWeek = 0;
            }

            final DateTime startOfMonth = DateTime(selectedYear, selectedMonth, 1, 0, 0, 0);
            final DateTime endOfMonth = DateTime(selectedYear, selectedMonth, daysInMonth, 23, 59, 59, 999);
            final String formattedMonthYear = '${selectedMonth.toString().padLeft(2, '0')}-$selectedYear';
            final String snapshotDocId = 'snapshot_${selectedYear}_${selectedMonth.toString().padLeft(2, '0')}';

            String periodLabel;
            if (selectedWeek == 0) {
              periodLabel = 'Rekap Bulanan (1 - $daysInMonth ${monthNamesShort[selectedMonth - 1]} $selectedYear)';
            } else {
              final days = weekDaysMap[selectedWeek] ?? [1];
              periodLabel = 'Minggu ke-$selectedWeek (${days.first} - ${days.last} ${monthNamesShort[selectedMonth - 1]} $selectedYear)';
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 6 : 14,
                vertical: isMobile ? 8 : 10,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title Header Row (Compact)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
                        ),
                        child: const Icon(Icons.fact_check_outlined, color: Color(0xFF34D399), size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMobile ? 'Riwayat Stok Fisik' : 'Riwayat Stok Fisik (Per Minggu & Akhir Bulan)',
                              style: TextStyle(color: Colors.white, fontSize: isMobile ? 13 : 15, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Stok sebelum in (kedatangan fleksibel), mutasi estafet mingguan, dan stok akhir.',
                              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 9.5 : 10.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Controls Bar
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Year Picker
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF94A3B8), size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 26),
                              onPressed: () {
                                setDialogState(() {
                                  selectedYear--;
                                  if (selectedWeek > 0) selectedWeek = 0;
                                });
                              },
                            ),
                            Text(
                              '$selectedYear',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 26),
                              onPressed: () {
                                setDialogState(() {
                                  selectedYear++;
                                  if (selectedWeek > 0) selectedWeek = 0;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // Month Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        height: 28,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedMonth,
                            dropdownColor: const Color(0xFF0F172A),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF38BDF8), size: 16),
                            items: List.generate(12, (index) {
                              final m = index + 1;
                              return DropdownMenuItem<int>(
                                value: m,
                                child: Text(
                                  monthNames[index],
                                  style: const TextStyle(color: Colors.white, fontSize: 11.5),
                                ),
                              );
                            }),
                            onChanged: (newMonth) {
                              if (newMonth != null) {
                                setDialogState(() {
                                  selectedMonth = newMonth;
                                  if (selectedWeek > 0) selectedWeek = 0;
                                });
                              }
                            },
                          ),
                        ),
                      ),

                      // Unit Mode Toggle (Pack vs Karton)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        height: 28,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => setDialogState(() => unitMode = 'PACK'),
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                color: unitMode == 'PACK' ? const Color(0xFF10B981) : Colors.transparent,
                                child: Text(
                                  'Pack',
                                  style: TextStyle(
                                    color: unitMode == 'PACK' ? Colors.white : const Color(0xFF94A3B8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => setDialogState(() => unitMode = 'KARTON'),
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                color: unitMode == 'KARTON' ? const Color(0xFF10B981) : Colors.transparent,
                                child: Text(
                                  'Karton',
                                  style: TextStyle(
                                    color: unitMode == 'KARTON' ? Colors.white : const Color(0xFF94A3B8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Search Field
                      SizedBox(
                        width: isMobile ? double.infinity : 200,
                        height: 28,
                        child: TextField(
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                          decoration: InputDecoration(
                            hintText: 'Cari barang / kode...',
                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6.0),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              dialogSearchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Week Filter Chips Row + Snapshot Lock Status integrated in one line
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('monthly_physical_snapshots').doc(snapshotDocId).snapshots(),
                    builder: (context, snapshotDocSnap) {
                      final snapshotDoc = snapshotDocSnap.data;
                      final bool isLocked = (snapshotDoc != null && snapshotDoc.exists && (snapshotDoc.data() as Map<String, dynamic>?)?['isLocked'] == true);
                      final Map<String, dynamic>? snapshotData = isLocked ? (snapshotDoc.data() as Map<String, dynamic>?) : null;

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('stock_entries')
                            .where('monthYear', isEqualTo: formattedMonthYear)
                            .snapshots(),
                        builder: (context, entriesSnap) {
                          final entriesInMonth = entriesSnap.data?.docs.map((d) => StockEntry.fromFirestore(d)).toList() ?? [];

                          return Row(
                            children: [
                              // Week filter chips (Scrollable)
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ChoiceChip(
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                        label: Text('Semua Minggu (1-$daysInMonth ${monthNamesShort[selectedMonth - 1]})'),
                                        selected: selectedWeek == 0,
                                        selectedColor: const Color(0xFF10B981),
                                        backgroundColor: const Color(0xFF0F172A),
                                        labelStyle: TextStyle(
                                          color: selectedWeek == 0 ? Colors.white : const Color(0xFF94A3B8),
                                          fontWeight: selectedWeek == 0 ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 10.5,
                                        ),
                                        onSelected: (val) => setDialogState(() => selectedWeek = 0),
                                      ),
                                      const SizedBox(width: 4),
                                      ...List.generate(maxWeek, (idx) {
                                        final w = idx + 1;
                                        final days = weekDaysMap[w] ?? [1];
                                        final isSelected = selectedWeek == w;
                                        final hasInflow = entriesInMonth.any((e) => e.weekNumber == w);

                                        return Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: ChoiceChip(
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                            avatar: hasInflow
                                                ? const Icon(Icons.circle, size: 7, color: Color(0xFF34D399))
                                                : null,
                                            label: Text('M$w (${days.first}-${days.last} ${monthNamesShort[selectedMonth - 1]})'),
                                            selected: isSelected,
                                            selectedColor: const Color(0xFF10B981),
                                            backgroundColor: const Color(0xFF0F172A),
                                            labelStyle: TextStyle(
                                              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 10.5,
                                            ),
                                            onSelected: (val) => setDialogState(() => selectedWeek = val ? w : 0),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Integrated Lock / Locked Badge
                              if (isLocked) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF064E3B).withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF059669)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lock_rounded, color: Color(0xFF34D399), size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Terkunci (${snapshotData?['lockedBy'] ?? 'Admin'})',
                                        style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 10),
                                      ),
                                      if (isDeveloper) ...[
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                backgroundColor: const Color(0xFF1E293B),
                                                title: const Text('Buka Kunci Stok?', style: TextStyle(color: Colors.white, fontSize: 14)),
                                                content: const Text(
                                                  'Buka kunci arsip stok bulan ini untuk menghitung ulang?',
                                                  style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const Text('Buka Kunci', style: TextStyle(color: Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await FirebaseFirestore.instance.collection('monthly_physical_snapshots').doc(snapshotDocId).delete();
                                            }
                                          },
                                          child: const Icon(Icons.refresh_rounded, color: Color(0xFFFBBF24), size: 14),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ] else if (isDeveloper) ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: isLocking
                                      ? const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                      : const Icon(Icons.lock_outline_rounded, size: 12, color: Colors.white),
                                  label: Text(
                                    isLocking ? 'Mengunci...' : 'Kunci Stok Akhir',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                                  ),
                                  onPressed: isLocking
                                      ? null
                                      : () async {
                                          setDialogState(() => isLocking = true);
                                          try {
                                            // Compute catalog products
                                            final Map<String, Product> uniqueProds = {};
                                            for (var p in productProvider.products) {
                                              final key = p.kodeInduk.trim().isNotEmpty ? p.kodeInduk.trim().toUpperCase() : p.id.trim().toUpperCase();
                                              if (!uniqueProds.containsKey(key)) uniqueProds[key] = p;
                                            }
                                            final catalogList = uniqueProds.values.toList();
                                            final itemsMap = <String, dynamic>{};
                                            for (var p in catalogList) {
                                              final key = p.kodeInduk.trim().isNotEmpty ? p.kodeInduk.trim().toUpperCase() : p.id.trim().toUpperCase();
                                              itemsMap[key] = {
                                                'kodeInduk': p.kodeInduk,
                                                'name': p.name,
                                                'isiKarton': p.isiKarton,
                                                'initialStock': p.stock,
                                                'finalStock': p.stock,
                                              };
                                            }
                                            await FirebaseFirestore.instance.collection('monthly_physical_snapshots').doc(snapshotDocId).set({
                                              'year': selectedYear,
                                              'month': selectedMonth,
                                              'monthYear': formattedMonthYear,
                                              'isLocked': true,
                                              'lockedAt': FieldValue.serverTimestamp(),
                                              'lockedBy': authProvider.currentUser?.name ?? 'Admin',
                                              'items': itemsMap,
                                            });
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Stok fisik $formattedMonthYear berhasil dikunci!'),
                                                  backgroundColor: Colors.teal,
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Gagal mengunci stok: $e'), backgroundColor: Colors.redAccent),
                                              );
                                            }
                                          } finally {
                                            setDialogState(() => isLocking = false);
                                          }
                                        },
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: isMobile ? double.maxFinite : (MediaQuery.of(context).size.width * 0.94).clamp(1150.0, 1600.0),
                height: isMobile ? (MediaQuery.of(context).size.height * 0.85) : (MediaQuery.of(context).size.height * 0.87),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('monthly_physical_snapshots').doc(snapshotDocId).snapshots(),
                  builder: (context, snapshotDocSnap) {
                    final snapshotDoc = snapshotDocSnap.data;
                    final bool isLocked = (snapshotDoc != null && snapshotDoc.exists && (snapshotDoc.data() as Map<String, dynamic>?)?['isLocked'] == true);
                    final Map<String, dynamic>? snapshotData = isLocked ? (snapshotDoc.data() as Map<String, dynamic>?) : null;

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('stock_entries').where('monthYear', isEqualTo: formattedMonthYear).snapshots(),
                      builder: (context, entriesSnap) {
                        final allEntries = entriesSnap.data?.docs.map((d) => StockEntry.fromFirestore(d)).toList() ?? [];

                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('stock_mutations')
                              .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                              .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
                              .snapshots(),
                          builder: (context, mutationsSnap) {
                            if (mutationsSnap.connectionState == ConnectionState.waiting && !mutationsSnap.hasData) {
                              return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
                            }

                            final allMutations = mutationsSnap.data?.docs.map((d) => StockMutation.fromFirestore(d)).toList() ?? [];

                            // Chained sequential calculation across all weeks
                            final computedItems = _calculateChainedPhysicalStock(
                              products: productProvider.products,
                              allEntries: allEntries,
                              allMutations: allMutations,
                              selectedYear: selectedYear,
                              selectedMonth: selectedMonth,
                              selectedWeek: selectedWeek,
                              maxWeek: maxWeek,
                              weekDaysMap: weekDaysMap,
                              snapshotData: snapshotData,
                              isLocked: isLocked,
                            );

                            // Filter by search query
                            final filteredItems = computedItems.where((item) {
                              if (dialogSearchQuery.isEmpty) return true;
                              return item.product.name.toLowerCase().contains(dialogSearchQuery) ||
                                  item.product.kodeInduk.toLowerCase().contains(dialogSearchQuery);
                            }).toList();

                            // Grand Totals
                            final totalInitial = computedItems.fold(0.0, (acc, i) => acc + i.initialStock);
                            final totalStockBeforeIn = computedItems.fold(0.0, (acc, i) => acc + (i.stockBeforeIn ?? 0.0));
                            final totalInflow = computedItems.fold(0.0, (acc, i) => acc + i.inflow);
                            final totalAdjust = computedItems.fold(0.0, (acc, i) => acc + i.adjust);
                            final totalOutflow = computedItems.fold(0.0, (acc, i) => acc + i.outflow);
                            final totalFinal = computedItems.fold(0.0, (acc, i) => acc + i.finalStock);

                            final totalInitialCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 ? i.initialStock / i.product.isiKarton : 0));
                            final totalStockBeforeInCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 && i.stockBeforeIn != null ? i.stockBeforeIn! / i.product.isiKarton : 0));
                            final totalInflowCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 ? i.inflow / i.product.isiKarton : 0));
                            final totalAdjustCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 ? i.adjust / i.product.isiKarton : 0));
                            final totalOutflowCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 ? i.outflow / i.product.isiKarton : 0));
                            final totalFinalCtn = computedItems.fold(0.0, (acc, i) => acc + (i.product.isiKarton > 0 ? i.finalStock / i.product.isiKarton : 0));

                            String formatQty(double qty, int isiKarton) {
                              if (unitMode == 'KARTON') {
                                final perBox = isiKarton > 0 ? isiKarton : 1;
                                final ctn = qty / perBox;
                                return ctn == ctn.roundToDouble() ? '${ctn.toInt()} Ctn' : '${ctn.toStringAsFixed(1)} Ctn';
                              } else {
                                return '${qty.toInt()} Pack';
                              }
                            }

                            return Column(
                              children: [
                                // Data Table Area
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: filteredItems.isEmpty
                                          ? const Center(
                                              child: Text('Tidak ada produk yang sesuai filter', style: TextStyle(color: Color(0xFF94A3B8))),
                                            )
                                          : SingleChildScrollView(
                                              scrollDirection: Axis.vertical,
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: DataTable(
                                                  headingRowHeight: 32,
                                                  dataRowMinHeight: 30,
                                                  dataRowMaxHeight: 32,
                                                  columnSpacing: 12,
                                                  horizontalMargin: 12,
                                                  headingRowColor: MaterialStateProperty.all(const Color(0xFF1E293B)),
                                                  dataRowColor: MaterialStateProperty.resolveWith((states) => const Color(0xFF0F172A)),
                                                  headingTextStyle: const TextStyle(
                                                    color: Color(0xFF38BDF8),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10.5,
                                                  ),
                                                  dataTextStyle: const TextStyle(color: Colors.white, fontSize: 11),
                                                  columns: [
                                                    const DataColumn(label: Text('NO')),
                                                    const DataColumn(label: Text('KODE INDUK')),
                                                    const DataColumn(label: Text('NAMA PRODUK')),
                                                    const DataColumn(label: Text('ISI/CTN')),
                                                    DataColumn(label: Text('STOK AWAL\n($unitMode)')),
                                                    const DataColumn(
                                                      label: Tooltip(
                                                        message: 'Stok fisik riil sebelum kiriman masuk tiba dan dibongkar (Selasa / Rabu / Kamis / Jumat / Sabtu)',
                                                        child: Row(
                                                          children: [
                                                            Text('SBLM IN (KEDATANGAN) '),
                                                            Icon(Icons.info_outline, size: 11, color: Color(0xFFFBBF24)),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const DataColumn(label: Text('MASUK (+IN)')),
                                                    const DataColumn(
                                                      label: Tooltip(
                                                        message: 'Penyesuaian stok opname / edit manual master barang (+ / -)',
                                                        child: Row(
                                                          children: [
                                                            Text('ADJUST (±) '),
                                                            Icon(Icons.tune_rounded, size: 11, color: Color(0xFF38BDF8)),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const DataColumn(label: Text('PENJUALAN (-OUT)')),
                                                    DataColumn(label: Text('STOK AKHIR\n($unitMode)')),
                                                  ],
                                                  rows: filteredItems.asMap().entries.map((entry) {
                                                    final idx = entry.key;
                                                    final item = entry.value;
                                                    final p = item.product;

                                                    return DataRow(
                                                      cells: [
                                                        DataCell(Text('${idx + 1}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10))),
                                                        DataCell(
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF1E293B),
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(color: const Color(0xFF334155)),
                                                            ),
                                                            child: Text(
                                                              p.kodeInduk,
                                                              style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 10.5),
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          SizedBox(
                                                            width: 210,
                                                            child: Text(
                                                              p.name,
                                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(Text('${p.isiKarton} Pk', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5))),
                                                        DataCell(
                                                          Tooltip(
                                                            message: selectedWeek > 1
                                                                ? '🔗 Saldo resmi bersambung dari penutupan Minggu ke-${selectedWeek - 1}'
                                                                : '📌 Saldo fisik awal bulan (1 ${monthNames[selectedMonth - 1]})',
                                                            child: Text(
                                                              formatQty(item.initialStock, p.isiKarton),
                                                              style: const TextStyle(color: Color(0xFFE2E8F0)),
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          item.stockBeforeIn != null
                                                              ? Tooltip(
                                                                  message: item.incomingDate != null
                                                                      ? '📦 Kedatangan: ${_formatIndoDateTime(item.incomingDate!)}\n'
                                                                        '🛒 Penjualan sblm tiba: -${item.salesBeforeIncoming.toInt()} Pack\n'
                                                                        '${item.adjustBeforeIncoming != 0 ? "⚖️ Adjust sblm tiba: ${item.adjustBeforeIncoming > 0 ? "+" : ""}${item.adjustBeforeIncoming.toInt()} Pack\n" : ""}'
                                                                        '📍 Sisa fisik saat tiba: ${formatQty(item.stockBeforeIn!, p.isiKarton)}'
                                                                      : 'Stok fisik saat kiriman tiba',
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                                    decoration: BoxDecoration(
                                                                      color: const Color(0xFF78350F).withOpacity(0.35),
                                                                      borderRadius: BorderRadius.circular(4),
                                                                      border: Border.all(color: const Color(0xFFD97706)),
                                                                    ),
                                                                    child: Row(
                                                                      mainAxisSize: MainAxisSize.min,
                                                                      children: [
                                                                        const Icon(Icons.access_time_rounded, color: Color(0xFFFBBF24), size: 10),
                                                                        const SizedBox(width: 3),
                                                                        Text(
                                                                          formatQty(item.stockBeforeIn!, p.isiKarton),
                                                                          style: const TextStyle(
                                                                            color: Color(0xFFFDE68A),
                                                                            fontWeight: FontWeight.bold,
                                                                            fontSize: 10.5,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                )
                                                              : const Text('-', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                        ),
                                                        DataCell(
                                                          item.inflow > 0
                                                              ? Text(
                                                                  '+${formatQty(item.inflow, p.isiKarton)}',
                                                                  style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold),
                                                                )
                                                              : const Text('0', style: TextStyle(color: Color(0xFF64748B))),
                                                        ),
                                                        DataCell(
                                                          item.adjust != 0
                                                              ? Tooltip(
                                                                  message: 'Penyesuaian manual: ${item.adjust > 0 ? "+" : ""}${formatQty(item.adjust, p.isiKarton)}',
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                                    decoration: BoxDecoration(
                                                                      color: item.adjust > 0
                                                                          ? const Color(0xFF0369A1).withOpacity(0.3)
                                                                          : const Color(0xFF78350F).withOpacity(0.3),
                                                                      borderRadius: BorderRadius.circular(4),
                                                                      border: Border.all(
                                                                        color: item.adjust > 0 ? const Color(0xFF0284C7) : const Color(0xFFD97706),
                                                                      ),
                                                                    ),
                                                                    child: Text(
                                                                      item.adjust > 0
                                                                          ? '+${formatQty(item.adjust, p.isiKarton)}'
                                                                          : '-${formatQty(item.adjust.abs(), p.isiKarton)}',
                                                                      style: TextStyle(
                                                                        color: item.adjust > 0 ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24),
                                                                        fontWeight: FontWeight.bold,
                                                                        fontSize: 10.5,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                )
                                                              : const Text('-', style: TextStyle(color: Color(0xFF64748B))),
                                                        ),
                                                        DataCell(
                                                          item.outflow > 0
                                                              ? Text(
                                                                  '-${formatQty(item.outflow, p.isiKarton)}',
                                                                  style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold),
                                                                )
                                                              : const Text('0', style: TextStyle(color: Color(0xFF64748B))),
                                                        ),
                                                        DataCell(
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF0F172A),
                                                              borderRadius: BorderRadius.circular(4),
                                                              border: Border.all(color: const Color(0xFF0284C7)),
                                                            ),
                                                            child: Text(
                                                              formatQty(item.finalStock, p.isiKarton),
                                                              style: const TextStyle(
                                                                color: Color(0xFF38BDF8),
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
                                ),
                                const SizedBox(height: 6),

                                // Bottom Summary Totals Bar (Ultra compact)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Total: ${filteredItems.length} Produk',
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                      _buildPhysicalStockTotalBadge('Awal', '${totalInitial.toInt()} Pk', '${totalInitialCtn.toStringAsFixed(1)} Ctn', const Color(0xFFE2E8F0)),
                                      _buildPhysicalStockTotalBadge('Sblm In', '${totalStockBeforeIn.toInt()} Pk', '${totalStockBeforeInCtn.toStringAsFixed(1)} Ctn', const Color(0xFFFBBF24)),
                                      _buildPhysicalStockTotalBadge('Masuk (+In)', '+${totalInflow.toInt()} Pk', '+${totalInflowCtn.toStringAsFixed(1)} Ctn', const Color(0xFF34D399)),
                                      _buildPhysicalStockTotalBadge('Adjust', '${totalAdjust >= 0 ? "+" : ""}${totalAdjust.toInt()} Pk', '${totalAdjustCtn >= 0 ? "+" : ""}${totalAdjustCtn.toStringAsFixed(1)} Ctn', totalAdjust >= 0 ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24)),
                                      _buildPhysicalStockTotalBadge('Keluar (-Out)', '-${totalOutflow.toInt()} Pk', '-${totalOutflowCtn.toStringAsFixed(1)} Ctn', const Color(0xFFF87171)),
                                      _buildPhysicalStockTotalBadge('Stok Akhir', '${totalFinal.toInt()} Pk', '${totalFinalCtn.toStringAsFixed(1)} Ctn', const Color(0xFF38BDF8)),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.table_view_rounded, size: 14, color: Colors.white),
                  label: const Text('Export Excel (.xlsx)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: () {
                    _exportPhysicalStockDirect(
                      selectedYear: selectedYear,
                      selectedMonth: selectedMonth,
                      selectedWeek: selectedWeek,
                      unitMode: unitMode,
                      monthName: monthNames[selectedMonth - 1],
                      periodLabel: periodLabel,
                    );
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 14, color: Colors.white),
                  label: const Text('Cetak PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: () {
                    _printPhysicalStockDirect(
                      selectedYear: selectedYear,
                      selectedMonth: selectedMonth,
                      selectedWeek: selectedWeek,
                      unitMode: unitMode,
                      monthName: monthNames[selectedMonth - 1],
                      periodLabel: periodLabel,
                    );
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper to fetch data and export Excel
  Future<void> _exportPhysicalStockDirect({
    required int selectedYear,
    required int selectedMonth,
    required int selectedWeek,
    required String unitMode,
    required String monthName,
    required String periodLabel,
  }) async {
    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
      final firstDay = DateTime(selectedYear, selectedMonth, 1);
      final firstDayOffset = firstDay.weekday % 7;
      int getWeek(int day) => ((day - 1 + firstDayOffset) ~/ 7) + 1;

      final Map<int, List<int>> weekDaysMap = {};
      for (int d = 1; d <= daysInMonth; d++) {
        final w = getWeek(d);
        weekDaysMap.putIfAbsent(w, () => []).add(d);
      }
      final int maxWeek = weekDaysMap.keys.isEmpty ? 5 : weekDaysMap.keys.reduce((a, b) => a > b ? a : b);

      final DateTime startOfMonth = DateTime(selectedYear, selectedMonth, 1, 0, 0, 0);
      final DateTime endOfMonth = DateTime(selectedYear, selectedMonth, daysInMonth, 23, 59, 59, 999);
      final String formattedMonthYear = '${selectedMonth.toString().padLeft(2, '0')}-$selectedYear';

      final entriesSnap = await FirebaseFirestore.instance.collection('stock_entries').where('monthYear', isEqualTo: formattedMonthYear).get();
      final allEntries = entriesSnap.docs.map((d) => StockEntry.fromFirestore(d)).toList();

      final mutationsSnap = await FirebaseFirestore.instance.collection('stock_mutations')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();
      final allMutations = mutationsSnap.docs.map((d) => StockMutation.fromFirestore(d)).toList();

      final computedItems = _calculateChainedPhysicalStock(
        products: productProvider.products,
        allEntries: allEntries,
        allMutations: allMutations,
        selectedYear: selectedYear,
        selectedMonth: selectedMonth,
        selectedWeek: selectedWeek,
        maxWeek: maxWeek,
        weekDaysMap: weekDaysMap,
      );

      await _exportPhysicalStockToExcel(
        items: computedItems,
        monthName: monthName,
        year: selectedYear,
        periodLabel: periodLabel,
        unitMode: unitMode,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // Helper to fetch data and print PDF
  Future<void> _printPhysicalStockDirect({
    required int selectedYear,
    required int selectedMonth,
    required int selectedWeek,
    required String unitMode,
    required String monthName,
    required String periodLabel,
  }) async {
    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final daysInMonth = DateTime(selectedYear, selectedMonth + 1, 0).day;
      final firstDay = DateTime(selectedYear, selectedMonth, 1);
      final firstDayOffset = firstDay.weekday % 7;
      int getWeek(int day) => ((day - 1 + firstDayOffset) ~/ 7) + 1;

      final Map<int, List<int>> weekDaysMap = {};
      for (int d = 1; d <= daysInMonth; d++) {
        final w = getWeek(d);
        weekDaysMap.putIfAbsent(w, () => []).add(d);
      }
      final int maxWeek = weekDaysMap.keys.isEmpty ? 5 : weekDaysMap.keys.reduce((a, b) => a > b ? a : b);

      final DateTime startOfMonth = DateTime(selectedYear, selectedMonth, 1, 0, 0, 0);
      final DateTime endOfMonth = DateTime(selectedYear, selectedMonth, daysInMonth, 23, 59, 59, 999);
      final String formattedMonthYear = '${selectedMonth.toString().padLeft(2, '0')}-$selectedYear';

      final entriesSnap = await FirebaseFirestore.instance.collection('stock_entries').where('monthYear', isEqualTo: formattedMonthYear).get();
      final allEntries = entriesSnap.docs.map((d) => StockEntry.fromFirestore(d)).toList();

      final mutationsSnap = await FirebaseFirestore.instance.collection('stock_mutations')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();
      final allMutations = mutationsSnap.docs.map((d) => StockMutation.fromFirestore(d)).toList();

      final computedItems = _calculateChainedPhysicalStock(
        products: productProvider.products,
        allEntries: allEntries,
        allMutations: allMutations,
        selectedYear: selectedYear,
        selectedMonth: selectedMonth,
        selectedWeek: selectedWeek,
        maxWeek: maxWeek,
        weekDaysMap: weekDaysMap,
      );

      await _printPhysicalStockPdf(
        items: computedItems,
        monthName: monthName,
        year: selectedYear,
        periodLabel: periodLabel,
        unitMode: unitMode,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _exportPhysicalStockToExcel({
    required List<_PhysicalStockItem> items,
    required String monthName,
    required int year,
    required String periodLabel,
    required String unitMode,
  }) async {
    try {
      final sheetName = 'Stok Fisik $monthName $year';
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      final cellBorder = excel_pkg.Border(
        borderStyle: excel_pkg.BorderStyle.Thin,
        borderColorHex: excel_pkg.ExcelColor.fromHexString('#000000'),
      );

      final titleStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 13,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
      );

      final headerStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final centerDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final leftDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Left,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final boldCenterStyle = excel_pkg.CellStyle(
        bold: true,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      // Title Row
      sheetObject.merge(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 0),
      );
      var titleCell = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      titleCell.value = excel_pkg.TextCellValue('LAPORAN RIWAYAT STOK FISIK - ${monthName.toUpperCase()} $year');
      titleCell.cellStyle = titleStyle;

      // Subtitle Row
      sheetObject.merge(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: 1),
      );
      var subCell = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1));
      subCell.value = excel_pkg.TextCellValue('Periode: $periodLabel | Satuan Tampilan: $unitMode');
      subCell.cellStyle = excel_pkg.CellStyle(fontSize: 10, horizontalAlign: excel_pkg.HorizontalAlign.Center);

      // Headers Row
      final headers = [
        'No',
        'Kode Induk',
        'Nama Barang',
        'Isi/Ctn',
        'Stok Awal ($unitMode)',
        'Stok Sblm In (Kedatangan)',
        'Barang Masuk (+In)',
        'Adjust / Koreksi (±)',
        'Penjualan (-Out)',
        'Stok Akhir Fisik',
        'Satuan',
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3));
        cell.value = excel_pkg.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int curRow = 4;
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final p = item.product;
        final perBox = p.isiKarton > 0 ? p.isiKarton : 1;

        double initVal = unitMode == 'KARTON' ? item.initialStock / perBox : item.initialStock;
        double? beforeInVal = item.stockBeforeIn != null ? (unitMode == 'KARTON' ? item.stockBeforeIn! / perBox : item.stockBeforeIn!) : null;
        double inVal = unitMode == 'KARTON' ? item.inflow / perBox : item.inflow;
        double adjVal = unitMode == 'KARTON' ? item.adjust / perBox : item.adjust;
        double outVal = unitMode == 'KARTON' ? item.outflow / perBox : item.outflow;
        double finalVal = unitMode == 'KARTON' ? item.finalStock / perBox : item.finalStock;

        var c0 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow));
        c0.value = excel_pkg.IntCellValue(i + 1);
        c0.cellStyle = centerDataStyle;

        var c1 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow));
        c1.value = excel_pkg.TextCellValue(p.kodeInduk);
        c1.cellStyle = centerDataStyle;

        var c2 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow));
        c2.value = excel_pkg.TextCellValue(p.name);
        c2.cellStyle = leftDataStyle;

        var c3 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: curRow));
        c3.value = excel_pkg.TextCellValue('${p.isiKarton} Pack');
        c3.cellStyle = centerDataStyle;

        var c4 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: curRow));
        c4.value = excel_pkg.DoubleCellValue(double.parse(initVal.toStringAsFixed(1)));
        c4.cellStyle = centerDataStyle;

        var c5 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: curRow));
        c5.value = beforeInVal != null ? excel_pkg.DoubleCellValue(double.parse(beforeInVal.toStringAsFixed(1))) : excel_pkg.TextCellValue('-');
        c5.cellStyle = centerDataStyle;

        var c6 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: curRow));
        c6.value = excel_pkg.DoubleCellValue(double.parse(inVal.toStringAsFixed(1)));
        c6.cellStyle = centerDataStyle;

        var c7 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: curRow));
        c7.value = adjVal != 0 ? excel_pkg.DoubleCellValue(double.parse(adjVal.toStringAsFixed(1))) : excel_pkg.TextCellValue('-');
        c7.cellStyle = centerDataStyle;

        var c8 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: curRow));
        c8.value = excel_pkg.DoubleCellValue(double.parse(outVal.toStringAsFixed(1)));
        c8.cellStyle = centerDataStyle;

        var c9 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: curRow));
        c9.value = excel_pkg.DoubleCellValue(double.parse(finalVal.toStringAsFixed(1)));
        c9.cellStyle = boldCenterStyle;

        var c10 = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: curRow));
        c10.value = excel_pkg.TextCellValue(unitMode);
        c10.cellStyle = centerDataStyle;

        curRow++;
      }

      sheetObject.setColumnWidth(0, 6.0);
      sheetObject.setColumnWidth(1, 16.0);
      sheetObject.setColumnWidth(2, 36.0);
      sheetObject.setColumnWidth(3, 12.0);
      sheetObject.setColumnWidth(4, 14.0);
      sheetObject.setColumnWidth(5, 18.0);
      sheetObject.setColumnWidth(6, 14.0);
      sheetObject.setColumnWidth(7, 14.0);
      sheetObject.setColumnWidth(8, 14.0);
      sheetObject.setColumnWidth(9, 16.0);
      sheetObject.setColumnWidth(10, 10.0);

      final fileBytes = excel.encode();
      if (fileBytes != null) {
        final bytes = Uint8List.fromList(fileBytes);
        final fileName = 'Riwayat_Stok_Fisik_${monthName}_${year}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _printPhysicalStockPdf({
    required List<_PhysicalStockItem> items,
    required String monthName,
    required int year,
    required String periodLabel,
    required String unitMode,
  }) async {
    try {
      final doc = pw.Document();
      final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      final tableHeaders = [
        'No',
        'Kode',
        'Nama Produk',
        'Isi/Ctn',
        'Awal ($unitMode)',
        'Sblm In (Kedatangan)',
        '+In',
        'Adjust (±)',
        '-Out',
        'Akhir ($unitMode)',
      ];

      final tableData = <List<String>>[];
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final p = item.product;
        final perBox = p.isiKarton > 0 ? p.isiKarton : 1;

        double initVal = unitMode == 'KARTON' ? item.initialStock / perBox : item.initialStock;
        double? beforeInVal = item.stockBeforeIn != null ? (unitMode == 'KARTON' ? item.stockBeforeIn! / perBox : item.stockBeforeIn!) : null;
        double inVal = unitMode == 'KARTON' ? item.inflow / perBox : item.inflow;
        double adjVal = unitMode == 'KARTON' ? item.adjust / perBox : item.adjust;
        double outVal = unitMode == 'KARTON' ? item.outflow / perBox : item.outflow;
        double finalVal = unitMode == 'KARTON' ? item.finalStock / perBox : item.finalStock;

        tableData.add([
          '${i + 1}',
          p.kodeInduk,
          p.name,
          '${p.isiKarton}',
          unitMode == 'KARTON' ? initVal.toStringAsFixed(1) : '${initVal.toInt()}',
          beforeInVal != null ? (unitMode == 'KARTON' ? beforeInVal.toStringAsFixed(1) : '${beforeInVal.toInt()}') : '-',
          unitMode == 'KARTON' ? (inVal > 0 ? '+${inVal.toStringAsFixed(1)}' : '0') : (inVal > 0 ? '+${inVal.toInt()}' : '0'),
          adjVal != 0
              ? (unitMode == 'KARTON'
                  ? (adjVal > 0 ? '+${adjVal.toStringAsFixed(1)}' : adjVal.toStringAsFixed(1))
                  : (adjVal > 0 ? '+${adjVal.toInt()}' : '${adjVal.toInt()}'))
              : '-',
          unitMode == 'KARTON' ? (outVal > 0 ? '-${outVal.toStringAsFixed(1)}' : '0') : (outVal > 0 ? '-${outVal.toInt()}' : '0'),
          unitMode == 'KARTON' ? finalVal.toStringAsFixed(1) : '${finalVal.toInt()}',
        ]);
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context ctx) {
            return [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LAPORAN RIWAYAT STOK FISIK',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Bulan: ${monthName.toUpperCase()} $year | $periodLabel',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'Satuan Data: $unitMode',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('PT. PANGAN FROZEN SEJAHTERA', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Dicetak: $dateStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('Total Barang: ${items.length} item', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: tableHeaders,
                data: tableData,
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0F172A)),
                rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
                cellStyle: const pw.TextStyle(fontSize: 7.5),
                cellAlignment: pw.Alignment.center,
                cellAlignments: {
                  2: pw.Alignment.centerLeft,
                },
                columnWidths: {
                  0: const pw.FixedColumnWidth(22),
                  1: const pw.FixedColumnWidth(65),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FixedColumnWidth(35),
                  4: const pw.FixedColumnWidth(50),
                  5: const pw.FixedColumnWidth(60),
                  6: const pw.FixedColumnWidth(42),
                  7: const pw.FixedColumnWidth(45),
                  8: const pw.FixedColumnWidth(42),
                  9: const pw.FixedColumnWidth(50),
                },
              ),
            ];
          },
        ),
      );

      final fileName = 'Riwayat_Stok_Fisik_${monthName}_$year.pdf';
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: fileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}

class _PhysicalStockItem {
  final Product product;
  final double initialStock;
  final double? stockBeforeIn;
  final double inflow;
  final double adjust;
  final double outflow;
  final double finalStock;
  final bool hasIncomingInPeriod;
  final DateTime? incomingDate;
  final double salesBeforeIncoming;
  final double adjustBeforeIncoming;

  _PhysicalStockItem({
    required this.product,
    required this.initialStock,
    this.stockBeforeIn,
    required this.inflow,
    this.adjust = 0.0,
    required this.outflow,
    required this.finalStock,
    this.hasIncomingInPeriod = false,
    this.incomingDate,
    this.salesBeforeIncoming = 0.0,
    this.adjustBeforeIncoming = 0.0,
  });
}

