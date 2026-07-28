import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;
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
  DateTime? _selectedDate;
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

  Map<String, double> _calculateProductStats(dynamic prod, Map<int, double> wMap, List<dynamic> allProducts) {
    final String ownId = prod.id.toString().trim().toLowerCase();
    final String ownName = prod.name.toString().trim().toLowerCase();

    // Collect all product IDs and names that share the exact same kodeInduk as prod
    final String currentKodeInduk = (prod.kodeInduk != null && prod.kodeInduk.toString().trim().isNotEmpty)
        ? prod.kodeInduk.toString().trim().toLowerCase()
        : ownId;

    final siblingProducts = allProducts.where((p) {
      final k = (p.kodeInduk != null && p.kodeInduk.toString().trim().isNotEmpty)
          ? p.kodeInduk.toString().trim().toLowerCase()
          : p.id.toString().trim().toLowerCase();
      return k == currentKodeInduk;
    }).toList();

    // Determine if this prod is the main (primary) representative for this kodeInduk group.
    // If prod name contains '(mbg)', or if it is the first sibling in the list, it acts as the primary group item.
    final bool isPrimaryGroupItem = (siblingProducts.isNotEmpty && siblingProducts.first.id == prod.id) ||
                                    ownName.contains('(mbg)');

    final Set<String> groupIds = {};
    final Set<String> groupNames = {};
    final Set<String> groupKodeInduk = {currentKodeInduk};

    for (var p in siblingProducts) {
      groupIds.add(p.id.toString().trim().toLowerCase());
      groupNames.add(p.name.toString().trim().toLowerCase());
      if (p.kodeInduk != null && p.kodeInduk.toString().trim().isNotEmpty) {
        groupKodeInduk.add(p.kodeInduk.toString().trim().toLowerCase());
      }
    }

    final factor = _showPcs ? 1.0 : (prod.sizeGrams / 1000.0);
    final initialStockVal = _initialStocks[prod.id] ?? 0.0;
    final stockBefore = initialStockVal * factor;

    double ownTotalPenjualan = 0.0;
    double ownSampleBonus = 0.0;
    double groupTotalKeluar = 0.0;

    for (var r in _erpRecords) {
      if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
        continue;
      }
      final invoices = r['invoices'] as List<dynamic>?;
      if (invoices != null && invoices.isNotEmpty) {
        for (var inv in invoices) {
          final invNoStr = (inv['invoiceNo'] ?? '').toString().toUpperCase();
          final isSampleInvoice = invNoStr.startsWith('SA') || invNoStr.contains('SAMPLE') || invNoStr.contains('BONUS');

          final items = inv['items'] as List<dynamic>?;
          if (items != null) {
            for (var item in items) {
              if (item is! Map) continue;
              final itemMap = Map<String, dynamic>.from(item);
              final itemPId = (itemMap['productId'] ?? '').toString().trim().toLowerCase();
              final itemPName = (itemMap['productName'] ?? '').toString().trim().toLowerCase();
              final itemKodeInduk = (itemMap['kodeInduk'] ?? itemMap['kode_Induk'] ?? '').toString().trim().toLowerCase();

              final isExactMatch = (itemPId.isNotEmpty && (itemPId == ownId || itemPId == ownName)) ||
                                   (itemPName.isNotEmpty && (itemPName == ownName || itemPName == ownId));

              final isKodeIndukMatch = (itemKodeInduk.isNotEmpty && groupKodeInduk.contains(itemKodeInduk)) ||
                                       (itemPId.isNotEmpty && (groupIds.contains(itemPId) || groupKodeInduk.contains(itemPId))) ||
                                       (itemPName.isNotEmpty && groupNames.contains(itemPName));

              final isGroupMatch = isExactMatch || isKodeIndukMatch;

              // Primary group item consolidates all sales matching its kodeInduk group
              final isOwnMatch = isExactMatch || (isPrimaryGroupItem && isKodeIndukMatch);

              final qty = (itemMap['qty'] ?? 0.0).toDouble();
              final weightKg = (itemMap['weightKg'] ?? 0.0).toDouble();
              final isBonusItem = itemMap['isBonus'] == true;
              final val = _showPcs ? qty : weightKg;

              if (isOwnMatch) {
                if (isSampleInvoice || isBonusItem) {
                  ownSampleBonus += val;
                } else {
                  ownTotalPenjualan += val;
                }
              }

              if (isGroupMatch) {
                groupTotalKeluar += val;
              }
            }
          }
        }
      } else {
        final prodSales = r['products'] as Map<String, dynamic>?;
        if (prodSales != null) {
          ownTotalPenjualan += _getProductSoldQty(prodSales, prod.id, _showPcs, prod.sizeGrams);
          for (var p in siblingProducts) {
            groupTotalKeluar += _getProductSoldQty(prodSales, p.id, _showPcs, p.sizeGrams);
          }
        }
      }
    }

    final m1 = (wMap[1] ?? 0.0) * factor;
    final m2 = (wMap[2] ?? 0.0) * factor;
    final m3 = (wMap[3] ?? 0.0) * factor;
    final m4 = (wMap[4] ?? 0.0) * factor;
    final m5 = (wMap[5] ?? 0.0) * factor;
    final totalMasuk = m1 + m2 + m3 + m4 + m5;

    final stockAkhir = stockBefore + totalMasuk - groupTotalKeluar;

    return {
      'totalPenjualan': ownTotalPenjualan,
      'stockBefore': stockBefore,
      'sampleBonus': ownSampleBonus,
      'totalKeluar': groupTotalKeluar,
      'm1': m1,
      'm2': m2,
      'm3': m3,
      'm4': m4,
      'm5': m5,
      'totalMasuk': totalMasuk,
      'stockAkhir': stockAkhir,
    };
  }

  Map<int, double> _getGroupWeeklyMap(dynamic prod, Map weeklyMap, List<dynamic> allProducts) {
    final String ownId = prod.id.toString().trim().toLowerCase();
    final String currentKodeInduk = (prod.kodeInduk != null && prod.kodeInduk.toString().trim().isNotEmpty)
        ? prod.kodeInduk.toString().trim().toLowerCase()
        : ownId;

    final siblingProducts = allProducts.where((p) {
      final k = (p.kodeInduk != null && p.kodeInduk.toString().trim().isNotEmpty)
          ? p.kodeInduk.toString().trim().toLowerCase()
          : p.id.toString().trim().toLowerCase();
      return k == currentKodeInduk;
    }).toList();

    final Map<int, double> groupWMap = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
    for (var p in siblingProducts) {
      final pWMap = weeklyMap[p.id];
      if (pWMap != null) {
        for (int w = 1; w <= 5; w++) {
          groupWMap[w] = (groupWMap[w] ?? 0.0) + (pWMap[w] ?? 0.0);
        }
      }
    }
    return groupWMap;
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
                  'Stok Awal',
                  'Total Penjualan',
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
                  final wMap = _getGroupWeeklyMap(prod, weeklyMap, products);
                  final stats = _calculateProductStats(prod, wMap, products);

                  final fmt = _showPcs ? 0 : 2;

                  return [
                    prod.name,
                    stats['stockBefore']!.toStringAsFixed(fmt),
                    stats['totalPenjualan']!.toStringAsFixed(fmt),
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

  ExcelColor? _getProductRowColor(String prodName) {
    final upper = prodName.toUpperCase().trim();
    if (upper.contains('KORNET AYAM LOYANG')) {
      return ExcelColor.fromHexString('#3B82F6'); // 1. Biru
    } else if (upper.contains('ROLLADE AYAM')) {
      return ExcelColor.fromHexString('#15803D'); // 2. Hijau Tua
    } else if (upper.contains('ROLLADE SAPI')) {
      return ExcelColor.fromHexString('#84CC16'); // 3. Hijau Lime
    } else if (upper.contains('BRS COKLAT 13S')) {
      return ExcelColor.fromHexString('#EF4444'); // 4. Merah
    } else if (upper.contains('BRS COKLAT 24S')) {
      return ExcelColor.fromHexString('#F97316'); // 5. Orange
    } else if (upper.contains('BRS COKLAT 7S')) {
      return ExcelColor.fromHexString('#EAB308'); // 6. Kuning
    } else if (upper.contains('BRS MERAH 24') || upper.contains('BRS MERAH 24S')) {
      return ExcelColor.fromHexString('#9333EA'); // 7. Ungu
    }
    return null;
  }

  /// Export Laporan ERP ke Format File Excel (.xlsx) 2 Sheet (Matriks Stok & Rincian Invoice)
  Future<void> _exportToExcelErp() async {
    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final stockProvider = Provider.of<StockProvider>(context, listen: false);
      final products = productProvider.products;
      final weeklyMap = stockProvider.getWeeklySummary(_selectedMonthYear);

      var excel = Excel.createExcel();

      // --- SHEET 1: Matriks Stok ERP ---
      String sheet1Name = 'Matriks Stok ERP';
      Sheet sheet1 = excel[sheet1Name];
      excel.setDefaultSheet(sheet1Name);

      // Extract active customers from _erpRecords
      List<Map<String, dynamic>> customerList = [];
      for (var r in _erpRecords) {
        if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
          continue;
        }
        customerList.add(r);
      }

      // Title Banner Row 0
      var titleCell = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      titleCell.value = TextCellValue('LAPORAN MATRIKS STOK ERP & OUTLET — PERIODE: $_selectedMonthYear');
      titleCell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
      );

      // Header Columns Row 1
      int colIdx = 0;
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('NO');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('NAMA PRODUK / ITEM');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('STOK AWAL');

      // Outlet Sales Header Columns (1 Column Per Customer)
      for (var cust in customerList) {
        final custAlias = cust['customerName'] ?? cust['aliasName'] ?? 'Outlet';
        sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue(custAlias.toString().toUpperCase());
      }

      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('TOTAL PENJUALAN');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('SAMPLE / BONUS');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('TOTAL KELUAR');

      // Influx Header Columns
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('INFLUX M1');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('INFLUX M2');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('INFLUX M3');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('INFLUX M4');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('INFLUX M5');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('TOTAL MASUK');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('STOK AKHIR');
      sheet1.cell(CellIndex.indexByColumnRow(columnIndex: colIdx++, rowIndex: 1)).value = TextCellValue('SATUAN');

      // Header styling (Row 1)
      for (int c = 0; c < colIdx; c++) {
        var hCell = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
        hCell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#1E293B'),
          fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
          horizontalAlign: c == 1 ? HorizontalAlign.Left : HorizontalAlign.Center,
        );
      }

      // Populate Data Rows starting at rowIndex = 2
      for (int i = 0; i < products.length; i++) {
        final prod = products[i];
        final wMap = _getGroupWeeklyMap(prod, weeklyMap, products);
        final stats = _calculateProductStats(prod, wMap, products);

        final bgExcelColor = _getProductRowColor(prod.name);
        final hexUpper = bgExcelColor?.colorHex.toUpperCase() ?? '';
        final isDarkBg = bgExcelColor != null &&
            hexUpper != '#84CC16' &&
            hexUpper != '#EAB308';
        final fontExcelColor = bgExcelColor != null
            ? (isDarkBg ? ExcelColor.fromHexString('#FFFFFF') : ExcelColor.fromHexString('#000000'))
            : null;

        CellStyle rowStyle = CellStyle(
          backgroundColorHex: bgExcelColor ?? ExcelColor.none,
          fontColorHex: fontExcelColor ?? ExcelColor.black,
          bold: bgExcelColor != null,
        );

        int cIdx = 0;

        // NO
        var cNo = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cNo.value = IntCellValue(i + 1);
        cNo.cellStyle = rowStyle;

        // NAMA PRODUK
        var cName = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cName.value = TextCellValue(prod.name);
        cName.cellStyle = rowStyle;

        // STOK AWAL
        var cStokAwal = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cStokAwal.value = DoubleCellValue(stats['stockBefore'] ?? 0.0);
        cStokAwal.cellStyle = rowStyle;

        // Sales Per Customer Outlet
        for (var cust in customerList) {
          final custProducts = cust['products'] as Map<String, dynamic>? ?? {};
          final soldQty = _getProductSoldQty(custProducts, prod.id, _showPcs, prod.sizeGrams);
          var cCust = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
          cCust.value = DoubleCellValue(soldQty);
          cCust.cellStyle = rowStyle;
        }

        // TOTAL PENJUALAN
        var cTotJual = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cTotJual.value = DoubleCellValue(stats['totalPenjualan'] ?? 0.0);
        cTotJual.cellStyle = rowStyle;

        // SAMPLE / BONUS
        var cSample = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cSample.value = DoubleCellValue(stats['sampleBonus'] ?? 0.0);
        cSample.cellStyle = rowStyle;

        // TOTAL KELUAR
        var cTotKeluar = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cTotKeluar.value = DoubleCellValue(stats['totalKeluar'] ?? 0.0);
        cTotKeluar.cellStyle = rowStyle;

        // INFLUX M1-M5
        var cM1 = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cM1.value = DoubleCellValue(stats['m1'] ?? 0.0);
        cM1.cellStyle = rowStyle;

        var cM2 = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cM2.value = DoubleCellValue(stats['m2'] ?? 0.0);
        cM2.cellStyle = rowStyle;

        var cM3 = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cM3.value = DoubleCellValue(stats['m3'] ?? 0.0);
        cM3.cellStyle = rowStyle;

        var cM4 = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cM4.value = DoubleCellValue(stats['m4'] ?? 0.0);
        cM4.cellStyle = rowStyle;

        var cM5 = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cM5.value = DoubleCellValue(stats['m5'] ?? 0.0);
        cM5.cellStyle = rowStyle;

        // TOTAL MASUK
        var cTotMasuk = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cTotMasuk.value = DoubleCellValue(stats['totalMasuk'] ?? 0.0);
        cTotMasuk.cellStyle = rowStyle;

        // STOK AKHIR
        var cStokAkhir = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cStokAkhir.value = DoubleCellValue(stats['stockAkhir'] ?? 0.0);
        cStokAkhir.cellStyle = rowStyle;

        // SATUAN
        var cSatuan = sheet1.cell(CellIndex.indexByColumnRow(columnIndex: cIdx++, rowIndex: i + 2));
        cSatuan.value = TextCellValue(_showPcs ? 'Pcs' : 'Kg');
        cSatuan.cellStyle = rowStyle;
      }

      // --- SHEET 2: Rincian Invoice ERP ---
      String sheet2Name = 'Rincian Invoice ERP';
      Sheet sheet2 = excel[sheet2Name];

      sheet2.appendRow([
        TextCellValue('NO'),
        TextCellValue('NO. INVOICE / PO'),
        TextCellValue('PELANGGAN / OUTLET'),
        TextCellValue('TGL INVOICE ERP'),
        TextCellValue('DETAIL ITEM & QTY'),
        TextCellValue('TOTAL QTY'),
        TextCellValue('GRAND TOTAL (RP)'),
      ]);

      int rowNo = 1;
      for (var r in _erpRecords) {
        if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
          continue;
        }
        final customerName = r['customerName'] ?? 'Unknown Customer';
        final invoices = r['invoices'] as List<dynamic>? ?? [];

        for (var inv in invoices) {
          DateTime? erpInputDate;
          if (inv['erpSyncDate'] != null && inv['erpSyncDate'] is Timestamp) {
            erpInputDate = (inv['erpSyncDate'] as Timestamp).toDate();
          } else if (inv['date'] != null && inv['date'] is Timestamp) {
            erpInputDate = (inv['date'] as Timestamp).toDate();
          }

          if (_selectedDate != null && erpInputDate != null) {
            if (erpInputDate.year != _selectedDate!.year ||
                erpInputDate.month != _selectedDate!.month ||
                erpInputDate.day != _selectedDate!.day) {
              continue;
            }
          }

          final invoiceNo = inv['invoiceNo']?.toString() ?? '-';
          final grandTotal = (inv['grandTotal'] ?? 0.0).toDouble();
          final items = inv['items'] as List<dynamic>? ?? [];

          double totalQty = 0;
          List<String> itemStrings = [];
          for (var item in items) {
            final pName = item['productName'] ?? item['productId'] ?? '';
            final q = (item['qty'] ?? 0.0).toDouble();
            totalQty += q;
            itemStrings.add('$pName (${q.toStringAsFixed(0)} pcs)');
          }

          final dateStr = erpInputDate != null ? dateFormatter.format(erpInputDate) : '-';

          sheet2.appendRow([
            IntCellValue(rowNo++),
            TextCellValue(invoiceNo),
            TextCellValue(customerName.toString()),
            TextCellValue(dateStr),
            TextCellValue(itemStrings.join(', ')),
            DoubleCellValue(totalQty),
            DoubleCellValue(grandTotal),
          ]);
        }
      }

      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        final bytes = Uint8List.fromList(fileBytes);
        final fileName = 'Laporan_ERP_Stok_$_selectedMonthYear.xlsx'.replaceAll(' ', '_');

        await Printing.sharePdf(bytes: bytes, filename: fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Berhasil mengekspor Excel: $fileName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor Excel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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

  String _getPreviousMonthYear(String currentMonthYear) {
    final parts = currentMonthYear.split('-');
    if (parts.length != 2) return currentMonthYear;
    int month = int.tryParse(parts[0]) ?? 1;
    int year = int.tryParse(parts[1]) ?? 2026;

    if (month == 1) {
      month = 12;
      year -= 1;
    } else {
      month -= 1;
    }

    final mStr = month.toString().padLeft(2, '0');
    return '$mStr-$year';
  }

  Future<Map<String, double>> _calculatePrevMonthStockAkhir(String prevMonthYear) async {
    final trProvider = Provider.of<TransactionProvider>(context, listen: false);
    final stockProvider = Provider.of<StockProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final products = productProvider.products;

    final prevErpRecords = await trProvider.getMonthlyErpSummary(prevMonthYear);
    final prevInitialStocks = await stockProvider.fetchInitialStocks(prevMonthYear);
    final prevWeeklyMap = stockProvider.getWeeklySummary(prevMonthYear);

    final Map<String, double> prevStockAkhirMap = {};

    for (var prod in products) {
      final String ownId = prod.id.toString().trim().toLowerCase();

      final String currentKodeInduk = prod.kodeInduk.trim().isNotEmpty
          ? prod.kodeInduk.trim().toLowerCase()
          : ownId;

      final siblingProducts = products.where((p) {
        final k = p.kodeInduk.trim().isNotEmpty
            ? p.kodeInduk.trim().toLowerCase()
            : p.id.trim().toLowerCase();
        return k == currentKodeInduk;
      }).toList();

      final Set<String> groupIds = {};
      final Set<String> groupNames = {};

      for (var p in siblingProducts) {
        groupIds.add(p.id.trim().toLowerCase());
        groupNames.add(p.name.trim().toLowerCase());
      }

      final initialStockVal = prevInitialStocks[prod.id] ?? 0.0;
      final stockBeforePcs = initialStockVal; // in Pcs

      double groupTotalKeluarPcs = 0.0;

      for (var r in prevErpRecords) {
        final invoices = r['invoices'] as List<dynamic>?;
        if (invoices != null && invoices.isNotEmpty) {
          for (var inv in invoices) {
            final items = inv['items'] as List<dynamic>?;
            if (items != null) {
              for (var item in items) {
                if (item is! Map) continue;
                final itemMap = Map<String, dynamic>.from(item);
                final itemPId = (itemMap['productId'] ?? '').toString().trim().toLowerCase();
                final itemPName = (itemMap['productName'] ?? '').toString().trim().toLowerCase();

                final isGroupMatch = (itemPId.isNotEmpty && groupIds.contains(itemPId)) ||
                                     (itemPName.isNotEmpty && groupNames.contains(itemPName));

                if (isGroupMatch) {
                  final qty = (itemMap['qty'] ?? 0.0).toDouble();
                  groupTotalKeluarPcs += qty;
                }
              }
            }
          }
        } else {
          final prodSales = r['products'] as Map<String, dynamic>?;
          if (prodSales != null) {
            for (var p in siblingProducts) {
              groupTotalKeluarPcs += _getProductSoldQty(prodSales, p.id, true, p.sizeGrams);
            }
          }
        }
      }

      final wMap = _getGroupWeeklyMap(prod, prevWeeklyMap, products);
      final m1 = wMap[1] ?? 0.0;
      final m2 = wMap[2] ?? 0.0;
      final m3 = wMap[3] ?? 0.0;
      final m4 = wMap[4] ?? 0.0;
      final m5 = wMap[5] ?? 0.0;
      final totalMasukPcs = m1 + m2 + m3 + m4 + m5;

      final stockAkhirPcs = stockBeforePcs + totalMasukPcs - groupTotalKeluarPcs;
      prevStockAkhirMap[prod.id] = stockAkhirPcs;
    }

    return prevStockAkhirMap;
  }

  Future<void> _copyPrevMonthStockAkhir() async {
    final prevMonth = _getPreviousMonthYear(_selectedMonthYear);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: const [
            Icon(Icons.history_toggle_off_rounded, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text('Salin Stok Akhir Bulan Lalu', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menyalin Stok Akhir bulan $prevMonth sebagai Stok Awal bulan $_selectedMonthYear?',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Salin Stok Awal'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loadingErp = true);
      try {
        final stockProvider = Provider.of<StockProvider>(context, listen: false);
        final prevStocks = await _calculatePrevMonthStockAkhir(prevMonth);
        await stockProvider.saveInitialStocks(_selectedMonthYear, prevStocks);
        await _loadErpData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stok awal bulan $_selectedMonthYear berhasil di-update dari Stok Akhir bulan $prevMonth!'),
              backgroundColor: Colors.teal,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyalin stok akhir: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        setState(() => _loadingErp = false);
      }
    }
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

                    // Auto-fill buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final prevMonth = _getPreviousMonthYear(_selectedMonthYear);
                            final prevStocks = await _calculatePrevMonthStockAkhir(prevMonth);
                            for (var prod in products) {
                              final val = prevStocks[prod.id] ?? 0.0;
                              controllers[prod.id]!.text = val.toStringAsFixed(0);
                            }
                            setDialogState(() {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Stok awal diisi dari Stok Akhir bulan $prevMonth!'), backgroundColor: Colors.teal),
                              );
                            }
                          },
                          icon: const Icon(Icons.history_toggle_off_rounded, size: 16),
                          label: Text('Salin Stok Akhir (${_getPreviousMonthYear(_selectedMonthYear)})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                            side: const BorderSide(color: Colors.greenAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
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
                                        Wrap(
                                          spacing: 6,
                                          children: [
                                            Text('Master: ${prod.stock.toStringAsFixed(0)} pcs', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                            if (prod.kodeInduk.isNotEmpty && prod.kodeInduk != prod.id)
                                              Text('• Induk: ${prod.kodeInduk}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
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
                                      onChanged: (val) {
                                        final currentKode = prod.kodeInduk.trim().isNotEmpty
                                            ? prod.kodeInduk.trim().toLowerCase()
                                            : prod.id.trim().toLowerCase();

                                        for (var p in products) {
                                          final pKode = p.kodeInduk.trim().isNotEmpty
                                              ? p.kodeInduk.trim().toLowerCase()
                                              : p.id.trim().toLowerCase();
                                          if (pKode == currentKode && p.id != prod.id) {
                                            controllers[p.id]?.text = val;
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

  Widget _buildDatePickerFilter() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final parts = _selectedMonthYear.split('-');
        int initYear = now.year;
        int initMonth = now.month;
        if (parts.length == 2) {
          initMonth = int.tryParse(parts[0]) ?? now.month;
          initYear = int.tryParse(parts[1]) ?? now.year;
        }
        final initialDate = _selectedDate ?? DateTime(initYear, initMonth, DateTime.now().day <= 28 ? DateTime.now().day : 1);
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          helpText: 'PILIH TANGGAL INPUT MENU ERP',
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFF38BDF8),
                  onPrimary: Colors.black,
                  surface: Color(0xFF1E293B),
                  onSurface: Colors.white,
                ),
                dialogBackgroundColor: const Color(0xFF0F172A),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          final newMonthYear = DateFormat('MM-yyyy').format(picked);
          setState(() {
            _selectedDate = picked;
            if (_selectedMonthYear != newMonthYear) {
              _selectedMonthYear = newMonthYear;
              _loadErpData();
            }
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _selectedDate != null ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _selectedDate != null ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, color: _selectedDate != null ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8), size: 15),
            const SizedBox(width: 6),
            Text(
              _selectedDate != null ? 'Tgl ERP: ${DateFormat('dd-MM-yyyy').format(_selectedDate!)}' : 'Tgl ERP: Semua',
              style: TextStyle(
                color: _selectedDate != null ? const Color(0xFF38BDF8) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (_selectedDate != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() => _selectedDate = null),
                child: const Icon(Icons.cancel_rounded, color: Colors.amberAccent, size: 16),
              ),
            ] else ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 18),
            ],
          ],
        ),
      ),
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
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Monitoring Pergerakan Stok Awal, Influx Masuk Mingguan (M1-M5), & Saldo Akhir',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
              // 3-Dots Popup Menu Button for ERP Actions
              PopupMenuButton<String>(
                tooltip: 'Menu Fitur ERP',
                color: const Color(0xFF1E293B),
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Aksi ERP',
                        style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                onSelected: (val) {
                  if (val == 'set_initial') _showSetInitialStockDialog();
                  if (val == 'copy_prev') _copyPrevMonthStockAkhir();
                  if (val == 'refresh') {
                    productProvider.fetchProducts();
                    _loadErpData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data berhasil di-refresh!'), backgroundColor: Colors.teal),
                    );
                  }
                  if (val == 'print_pdf') _printPdfErp();
                  if (val == 'export_excel') _exportToExcelErp();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String>(
                    value: 'set_initial',
                    child: Row(
                      children: [
                        Icon(Icons.edit_note_rounded, color: Color(0xFF38BDF8), size: 18),
                        SizedBox(width: 10),
                        Text('Set Stok Awal Bulan', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'copy_prev',
                    child: Row(
                      children: [
                        Icon(Icons.history_toggle_off_rounded, color: Colors.greenAccent, size: 18),
                        SizedBox(width: 10),
                        Text('Salin Stok Akhir Bulan Lalu', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, color: Colors.amberAccent, size: 18),
                        SizedBox(width: 10),
                        Text('Refresh Data', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  const PopupMenuItem<String>(
                    value: 'export_excel',
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_rounded, color: Colors.greenAccent, size: 18),
                        SizedBox(width: 10),
                        Text('Export Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'print_pdf',
                    child: Row(
                      children: [
                        Icon(Icons.print_rounded, color: Color(0xFF38BDF8), size: 18),
                        SizedBox(width: 10),
                        Text('Cetak ERP PDF', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Control Bar: Periode, Date Filter, Customer Filter, Pcs/Kg Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 6),
                const Text('Periode:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(width: 6),
                DropdownButton<String>(
                  value: _selectedMonthYear,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                const SizedBox(width: 12),

                // Specific Date Filter (Calendar Picker)
                _buildDatePickerFilter(),
                const SizedBox(width: 14),

                const Icon(Icons.store_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 6),
                const Text('Outlet/Customer:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(width: 6),
                SearchableCustomerFilter(
                  selectedCustomer: _selectedCustomer,
                  customers: customerProvider.customers,
                  onSelected: (val) => setState(() => _selectedCustomer = val),
                ),
                const SizedBox(width: 14),

                // Product Search
                SizedBox(
                  width: 170,
                  child: TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Cari barang...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 16),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const Spacer(),

                // Toggle Pcs vs Kg
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          backgroundColor: _showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('PCS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() => _showPcs = false),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          backgroundColor: !_showPcs ? const Color(0xFF0284C7) : Colors.transparent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('KG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tab selector: Stok Matrix vs Detail Invoice
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _activeTab == 0 ? const Color(0xFF0284C7) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_chart_rounded, size: 16, color: _activeTab == 0 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text('Stok Matrix', style: TextStyle(
                            color: _activeTab == 0 ? Colors.white : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold, fontSize: 12.5,
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
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _activeTab == 1 ? const Color(0xFF0284C7) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 16, color: _activeTab == 1 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text('Detail Invoice ERP', style: TextStyle(
                            color: _activeTab == 1 ? Colors.white : const Color(0xFF64748B),
                            fontWeight: FontWeight.bold, fontSize: 12.5,
                          )),
                          if (_erpRecords.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _activeTab == 1 ? Colors.white.withOpacity(0.2) : const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_getTotalInvoiceCount()}',
                                style: TextStyle(color: _activeTab == 1 ? Colors.white : const Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 10),

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
      if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
        continue;
      }
      final invoices = r['invoices'] as List<dynamic>?;
      if (invoices == null) continue;
      for (var inv in invoices) {
        if (inv is! Map) continue;
        if (_selectedDate != null) {
          final Timestamp? erpTs = inv['erpSyncDate'] as Timestamp? ?? inv['date'] as Timestamp?;
          final erpDate = erpTs?.toDate();
          if (erpDate == null) continue;
          if (erpDate.year != _selectedDate!.year ||
              erpDate.month != _selectedDate!.month ||
              erpDate.day != _selectedDate!.day) {
            continue;
          }
        }
        count++;
      }
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
                        label: Tooltip(message: 'Stok Awal Bulan', child: Text('STOK AWAL', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      DataColumn(
                        label: Tooltip(message: 'Total Penjualan', child: Text('TOT. JUAL', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
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
                      final wMap = _getGroupWeeklyMap(prod, weeklyMap, products);
                      final stats = _calculateProductStats(prod, wMap, products);

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
                          DataCell(Text(stockBefore.toStringAsFixed(fmt), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                          DataCell(Text(totalPenjualan.toStringAsFixed(fmt), style: TextStyle(color: totalPenjualan > 0 ? const Color(0xFF38BDF8) : Colors.white70, fontWeight: totalPenjualan > 0 ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
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

  int _safeParseInvoiceInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is num) return val.toInt();
    final str = val.toString();
    final digits = RegExp(r'\d+').stringMatch(str);
    if (digits != null) {
      return int.tryParse(digits) ?? 0;
    }
    return 0;
  }

  Widget _buildInvoiceDetailTab() {
    final productProvider = Provider.of<ProductProvider>(context);

    if (_loadingErp) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter ERP records by selected customer & selected date
    final List<Map<String, dynamic>> filteredRecords = [];

    for (var r in _erpRecords) {
      if (_selectedCustomer != null && r['customerId'] != _selectedCustomer!.id) {
        continue;
      }

      final invoices = List<dynamic>.from(r['invoices'] ?? []);
      final List<Map<String, dynamic>> matchingInvoices = [];

      for (var inv in invoices) {
        if (inv is! Map) continue;
        final invMap = Map<String, dynamic>.from(inv);
        final Timestamp? erpTs = invMap['erpSyncDate'] as Timestamp? ?? invMap['date'] as Timestamp?;
        final invErpDate = erpTs?.toDate();

        if (_selectedDate != null) {
          if (invErpDate == null) continue;
          if (invErpDate.year != _selectedDate!.year ||
              invErpDate.month != _selectedDate!.month ||
              invErpDate.day != _selectedDate!.day) {
            continue;
          }
        }
        matchingInvoices.add(invMap);
      }

      if (matchingInvoices.isNotEmpty) {
        double custIncome = 0.0;
        final Map<String, Map<String, double>> custProducts = {};

        for (var inv in matchingInvoices) {
          custIncome += (inv['grandTotal'] ?? 0.0).toDouble();
          final items = List<dynamic>.from(inv['items'] ?? []);
          for (var item in items) {
            if (item is! Map) continue;
            final itemMap = Map<String, dynamic>.from(item);
            final productId = (itemMap['productId'] ?? '').toString();
            final qty = ((itemMap['qty'] ?? 0.0) as num).toDouble();
            final weightKg = ((itemMap['weightKg'] ?? 0.0) as num).toDouble();

            if (!custProducts.containsKey(productId)) {
              custProducts[productId] = {'pcs': 0.0, 'kg': 0.0};
            }
            custProducts[productId]!['pcs'] = custProducts[productId]!['pcs']! + qty;
            custProducts[productId]!['kg'] = custProducts[productId]!['kg']! + weightKg;
          }
        }

        final recCopy = Map<String, dynamic>.from(r);
        recCopy['invoices'] = matchingInvoices;
        recCopy['totalIncome'] = custIncome;
        recCopy['products'] = custProducts;
        filteredRecords.add(recCopy);
      }
    }

    if (filteredRecords.isEmpty) {
      final String emptySubtext = _selectedDate != null
          ? 'pada tanggal ${DateFormat('dd-MM-yyyy').format(_selectedDate!)}'
          : 'pada periode $_selectedMonthYear';

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
                'Belum ada invoice yang masuk ERP\n$emptySubtext',
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
    filteredRecords.sort((a, b) => (a['customerName'] ?? '').toString().compareTo((b['customerName'] ?? '').toString()));

    // Calculate Summary stats for Detail Invoice ERP tab
    double grandTotalIncome = 0.0;
    double grandTotalWeightKg = 0.0;

    for (var record in filteredRecords) {
      grandTotalIncome += (record['totalIncome'] ?? 0.0).toDouble();
      final invoices = List<dynamic>.from(record['invoices'] ?? []);
      for (var inv in invoices) {
        if (inv is! Map) continue;
        final items = List<dynamic>.from(inv['items'] ?? []);
        for (var item in items) {
          if (item is! Map) continue;
          final itemMap = Map<String, dynamic>.from(item);
          grandTotalWeightKg += ((itemMap['weightKg'] ?? 0.0) as num).toDouble();
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.attach_money_rounded, color: Colors.greenAccent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Income ERP', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          currencyFormatter.format(grandTotalIncome),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.scale_rounded, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Berat ERP (Kg)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${grandTotalWeightKg.toStringAsFixed(2)} Kg',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Scrollbar(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: filteredRecords.length,
                itemBuilder: (context, index) {
            final record = filteredRecords[index];
            final customerName = record['customerName'] ?? 'Unknown';
            final totalIncome = (record['totalIncome'] ?? 0.0).toDouble();
            final invoices = List<dynamic>.from(record['invoices'] ?? []);
            final productsMap = Map<String, dynamic>.from(record['products'] ?? {});

            // Sort invoices by invoiceNo safely without unsafe type casting
            invoices.sort((a, b) {
              if (a is! Map || b is! Map) return 0;
              final invA = a['invoiceNo'];
              final invB = b['invoiceNo'];
              final numA = _safeParseInvoiceInt(invA);
              final numB = _safeParseInvoiceInt(invB);
              if (numA != numB) return numA.compareTo(numB);
              return invA.toString().compareTo(invB.toString());
            });

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  leading: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        customerName.isNotEmpty ? customerName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                  title: Text(
                    customerName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  subtitle: Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${invoices.length} Invoice',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          currencyFormatter.format(totalIncome),
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
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
                                final pcs = ((prodData['pcs'] ?? 0.0) as num).toDouble();
                                final kg = ((prodData['kg'] ?? 0.0) as num).toDouble();
                                final displayVal = _showPcs ? pcs.toStringAsFixed(0) : kg.toStringAsFixed(2);
                                final unit = _showPcs ? 'pcs' : 'kg';

                                String productName = entry.key;
                                try {
                                  final matched = productProvider.products.firstWhere(
                                    (p) => p.id == entry.key || p.name == entry.key,
                                  );
                                  productName = matched.name;
                                } catch (_) {}

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF334155)),
                                  ),
                                  child: Text(
                                    '$productName: $displayVal $unit',
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
                      if (inv is! Map) return const SizedBox();
                      final invNo = inv['invoiceNo'] ?? 0;
                      final invItems = List<dynamic>.from(inv['items'] ?? []);
                      final calculatedInvTotal = invItems.fold(0.0, (sum, it) {
                        if (it is! Map) return sum;
                        final itemMap = Map<String, dynamic>.from(it);
                        final isBonus = itemMap['isBonus'] == true;
                        final sub = ((itemMap['subtotal'] ?? 0.0) as num).toDouble().roundToDouble();
                        return sum + (isBonus ? 0.0 : sub);
                      });
                      final invTotal = calculatedInvTotal > 0 ? calculatedInvTotal : ((inv['grandTotal'] ?? 0.0) as num).toDouble().roundToDouble();
                      DateTime? invDate;
                      DateTime? erpInputDate;
                      try {
                        if (inv['date'] != null && inv['date'] is Timestamp) {
                          invDate = (inv['date'] as Timestamp).toDate();
                        }
                        if (inv['erpSyncDate'] != null && inv['erpSyncDate'] is Timestamp) {
                          erpInputDate = (inv['erpSyncDate'] as Timestamp).toDate();
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
                                const SizedBox(width: 10),
                                if (invDate != null)
                                  Text(
                                    dateFormatter.format(invDate),
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  ),
                                if (erpInputDate != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF38BDF8).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'Tgl ERP: ${dateFormatter.format(erpInputDate)}',
                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
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

class SearchableCustomerFilter extends StatefulWidget {
  final Customer? selectedCustomer;
  final List<Customer> customers;
  final ValueChanged<Customer?> onSelected;

  const SearchableCustomerFilter({
    super.key,
    required this.selectedCustomer,
    required this.customers,
    required this.onSelected,
  });

  @override
  State<SearchableCustomerFilter> createState() => _SearchableCustomerFilterState();
}

class _SearchableCustomerFilterState extends State<SearchableCustomerFilter> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Customer> _filteredCustomers = [];

  @override
  void initState() {
    super.initState();
    _filteredCustomers = List.from(widget.customers)..sort((a, b) => a.displayName.compareTo(b.displayName));
    if (widget.selectedCustomer != null) {
      _controller.text = widget.selectedCustomer!.displayName;
    }

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            _hideOverlay();
          }
        }).catchError((_) {});
      }
    });
  }

  @override
  void didUpdateWidget(SearchableCustomerFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCustomer == null && oldWidget.selectedCustomer != null) {
      _controller.clear();
      _filteredCustomers = List.from(widget.customers)..sort((a, b) => a.displayName.compareTo(b.displayName));
    } else if (widget.selectedCustomer != null && widget.selectedCustomer != oldWidget.selectedCustomer) {
      _controller.text = widget.selectedCustomer!.displayName;
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      if (cleanQuery.isEmpty) {
        _filteredCustomers = List.from(widget.customers)..sort((a, b) => a.displayName.compareTo(b.displayName));
      } else {
        _filteredCustomers = widget.customers.where((c) {
          final alias = c.aliasName.toLowerCase();
          final name = c.customerName.toLowerCase();
          final display = c.displayName.toLowerCase();
          final city = c.city.toLowerCase();
          return alias.contains(cleanQuery) ||
                 name.contains(cleanQuery) ||
                 display.contains(cleanQuery) ||
                 city.contains(cleanQuery);
        }).toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
      }
    });
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      try {
        _overlayEntry!.markNeedsBuild();
      } catch (_) {}
    }
  }

  void _showOverlay() {
    _hideOverlay();
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width.clamp(320.0, 500.0),
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 6.0),
          child: Material(
            elevation: 8.0,
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    dense: true,
                    title: const Text('-- Semua Customer --', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                    onTap: () {
                      _controller.clear();
                      widget.onSelected(null);
                      _focusNode.unfocus();
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFF334155)),
                  Expanded(
                    child: _filteredCustomers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('Customer tidak ditemukan', style: TextStyle(color: Color(0xFF94A3B8))),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: _filteredCustomers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF334155)),
                            itemBuilder: (context, index) {
                              final c = _filteredCustomers[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  c.displayName,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${c.city}, ${c.province}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                                onTap: () {
                                  _controller.text = c.displayName;
                                  widget.onSelected(c);
                                  _focusNode.unfocus();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      Overlay.of(context).insert(_overlayEntry!);
    } catch (_) {}
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      try {
        if (_overlayEntry!.mounted) {
          _overlayEntry?.remove();
        }
      } catch (_) {}
      _overlayEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: '-- Semua Customer --',
            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5)),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 18),
                    onPressed: () {
                      _controller.clear();
                      widget.onSelected(null);
                      _filter('');
                    },
                  )
                : Icon(
                    _focusNode.hasFocus ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                    color: const Color(0xFF38BDF8),
                    size: 24,
                  ),
          ),
          onChanged: (val) {
            if (val.isEmpty) {
              widget.onSelected(null);
            }
            _filter(val);
          },
        ),
      ),
    );
  }
}
