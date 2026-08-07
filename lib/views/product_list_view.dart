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
import '../models/stock_mutation.dart';
import '../providers/product_provider.dart';
import '../services/firebase_service.dart';
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
                        if (localProduct.id != id) {
                          await Provider.of<ProductProvider>(context, listen: false).deleteProduct(localProduct.id);
                        }
                        final updated = Product(
                          id: id,
                          kodeInduk: kodeInduk,
                          name: name,
                          price: price,
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
        c4.value = excel_pkg.TextCellValue('${p.isiKarton} Pcs');
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
        final fileName = 'Master_Barang_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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
  // CETAK PDF
  // -------------------------------------------------------------------
  Future<void> _printProductsPdf(List<Product> products) async {
    try {
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
                    '${p.isiKarton} Pcs',
                    totalKartonStr,
                    '${p.sizeGrams.toStringAsFixed(0)} G',
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      final fileName = 'Master_Barang_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
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
                                    DataColumn(label: Text('TOTAL KARTON'), numeric: true),
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
  // SINGLE PRODUCT STOCK MUTATION DIALOG
  // ==========================================

  void _showStockMutationHistory(Product product) {
    final firebaseService = FirebaseService();
    String dialogSearchQuery = '';
    DateTime? selectedDate = DateTime.now(); // Default: TODAY

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isToday = selectedDate != null &&
                selectedDate!.year == DateTime.now().year &&
                selectedDate!.month == DateTime.now().month &&
                selectedDate!.day == DateTime.now().day;

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

                  // Filter Row: Search Text + Single Calendar Date Picker
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

                      // Single Date Picker Button
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
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
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: selectedDate != null ? const Color(0xFF0284C7).withOpacity(0.3) : const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedDate != null ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                selectedDate == null
                                    ? 'Semua Tanggal'
                                    : isToday
                                        ? 'Hari Ini (${DateFormat('dd/MM/yy').format(selectedDate!)})'
                                        : DateFormat('dd/MM/yyyy').format(selectedDate!),
                                style: TextStyle(
                                  color: selectedDate != null ? Colors.white : const Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (selectedDate != null) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      selectedDate = null;
                                    });
                                  },
                                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              content: Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 768;
                  return SizedBox(
                    width: isMobile ? double.maxFinite : 980,
                    height: 440,
                    child: StreamBuilder<List<StockMutation>>(
                      stream: firebaseService.streamStockMutations(product.kodeInduk, date: selectedDate),
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
                                SizedBox(height: 12),
                                Text(
                                  selectedDate != null
                                      ? 'Belum ada mutasi stok pada ${DateFormat('dd/MM/yyyy').format(selectedDate!)}.'
                                      : 'Belum ada riwayat mutasi stok.',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }

                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 880),
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
                                columns: const [
                                  DataColumn(label: Text('NO')),
                                  DataColumn(label: Text('TANGGAL')),
                                  DataColumn(label: Text('ISI PER KARTON'), numeric: true),
                                  DataColumn(label: Text('JENIS')),
                                  DataColumn(label: Text('QTY'), numeric: true),
                                  DataColumn(label: Text('TOTAL KARTON'), numeric: true),
                                  DataColumn(label: Text('STOK'), numeric: true),
                                  DataColumn(label: Text('REFERENSI')),
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
                                        product.isiKarton > 0 ? '${product.isiKarton} Pcs' : '-',
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
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
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
    DateTime? selectedDate = DateTime.now(); // Default: TODAY to save Firestore reads!

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isToday = selectedDate != null &&
                selectedDate!.year == DateTime.now().year &&
                selectedDate!.month == DateTime.now().month &&
                selectedDate!.day == DateTime.now().day;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
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
                        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF38BDF8), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Riwayat Mutasi Stok / Stock Out (Semua Barang)',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pencatatan semua barang keluar, masuk, retur, dan penyesuaian stok terpusat.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Filter Row: Search Input + Single Date Picker + Type Filter
                  Builder(
                    builder: (context) {
                      final isMobile = MediaQuery.of(context).size.width < 768;
                      return Wrap(
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

                          // Single Date Picker Button (Defaults to TODAY)
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now(),
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
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: selectedDate != null ? const Color(0xFF0284C7).withOpacity(0.3) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedDate != null ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedDate == null
                                        ? 'Semua Tanggal'
                                        : isToday
                                            ? 'Hari Ini (${DateFormat('dd/MM/yy').format(selectedDate!)})'
                                            : DateFormat('dd/MM/yyyy').format(selectedDate!),
                                    style: TextStyle(
                                      color: selectedDate != null ? Colors.white : const Color(0xFF94A3B8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (selectedDate != null) ...[
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedDate = null;
                                        });
                                      },
                                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 14),
                                    ),
                                  ],
                                ],
                              ),
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
                        ],
                      );
                    },
                  ),
                ],
              ),
              content: Builder(
                builder: (context) {
                  final isMobile = MediaQuery.of(context).size.width < 768;
                  return SizedBox(
                    width: isMobile ? double.maxFinite : 1240,
                    height: isMobile ? MediaQuery.of(context).size.height * 0.55 : 480,
                    child: StreamBuilder<List<StockMutation>>(
                  stream: firebaseService.streamAllStockMutations(date: selectedDate),
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
                              selectedDate != null
                                  ? 'Belum ada riwayat mutasi stok pada ${DateFormat('dd/MM/yyyy').format(selectedDate!)}.'
                                  : 'Tidak ada riwayat mutasi stok ditemukan.',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }

                    // Summary Stats
                    double totalKeluar = 0;
                    double totalMasuk = 0;
                    for (var m in mutations) {
                      if (m.qty < 0) {
                        totalKeluar += m.qty.abs();
                      } else {
                        totalMasuk += m.qty;
                      }
                    }

                    final productProvider = Provider.of<ProductProvider>(context, listen: false);
                    final prodMap = {for (var p in productProvider.products) p.kodeInduk: p};

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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Ditemukan: ${mutations.length} Mutasi ${selectedDate != null ? "(${DateFormat('dd/MM/yy').format(selectedDate!)})" : ""}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Total Stock Out: -${totalKeluar.toStringAsFixed(0)} pcs',
                                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Total Stock In: +${totalMasuk.toStringAsFixed(0)} pcs',
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
                                constraints: const BoxConstraints(minWidth: 1120),
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
                                  columns: const [
                                    DataColumn(label: Text('NO')),
                                    DataColumn(label: Text('TANGGAL')),
                                    DataColumn(label: Text('KODE INDUK')),
                                    DataColumn(label: Text('NAMA BARANG')),
                                    DataColumn(label: Text('ISI PER KARTON'), numeric: true),
                                    DataColumn(label: Text('JENIS')),
                                    DataColumn(label: Text('QTY'), numeric: true),
                                    DataColumn(label: Text('TOTAL KARTON'), numeric: true),
                                    DataColumn(label: Text('STOK'), numeric: true),
                                    DataColumn(label: Text('REFERENSI')),
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
                                          isiKarton > 0 ? '$isiKarton Pcs' : '-',
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
}
