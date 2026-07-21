import 'package:excel/excel.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/customer.dart';
import 'firebase_service.dart';

class ImportResult {
  final int totalRows;
  final int successCount;
  final int errorCount;
  final List<String> errors;

  ImportResult({
    required this.totalRows,
    required this.successCount,
    required this.errorCount,
    required this.errors,
  });
}

class ImportService {
  final FirebaseService _dbService = FirebaseService();

  List<int> _extractFileBytes(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      return content;
    } else if (content is InputStream) {
      return content.toUint8List();
    } else if (content is Uint8List) {
      return content;
    } else if (content != null) {
      try {
        return List<int>.from(content as dynamic);
      } catch (_) {}
    }
    return [];
  }

  // Clean custom numFmtId < 164 in styles.xml to avoid Excel package decode exceptions
  Uint8List _cleanExcelBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (var file in archive) {
        final rawBytes = _extractFileBytes(file);
        if (file.name.endsWith('styles.xml') && rawBytes.isNotEmpty) {
          final String content = String.fromCharCodes(rawBytes);
          final String cleanedContent = content.replaceAll(RegExp(r'<numFmts[^>]*>[\s\S]*?<\/numFmts>'), '');
          final bytesData = cleanedContent.codeUnits;
          newArchive.addFile(ArchiveFile(file.name, bytesData.length, bytesData));
        } else if (rawBytes.isNotEmpty) {
          newArchive.addFile(ArchiveFile(file.name, rawBytes.length, rawBytes));
        }
      }

      final encoder = ZipEncoder();
      final newBytes = encoder.encode(newArchive);
      if (newBytes != null) {
        return Uint8List.fromList(newBytes);
      }
    } catch (e) {
      debugPrint("Error cleaning Excel bytes: $e");
    }
    return bytes;
  }

  Excel _decodeExcelSafely(Uint8List bytes) {
    try {
      final cleaned = _cleanExcelBytes(bytes);
      return Excel.decodeBytes(cleaned);
    } catch (e) {
      debugPrint("Cleaned decode failed, fallback to raw decode: $e");
      return Excel.decodeBytes(bytes);
    }
  }

  // Helper to safely read cell value as String
  String _cellStr(Sheet sheet, int row, int col) {
    try {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      return cell.value?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  // Helper to safely read cell value as double
  double _cellDouble(Sheet sheet, int row, int col) {
    try {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      if (cell.value == null) return 0.0;
      if (cell.value is double) return cell.value as double;
      if (cell.value is int) return (cell.value as int).toDouble();
      final str = cell.value.toString().replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '.').trim();
      return double.tryParse(str) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // Helper to safely read cell value as int
  int _cellInt(Sheet sheet, int row, int col) {
    try {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      if (cell.value == null) return 0;
      if (cell.value is int) return cell.value as int;
      if (cell.value is double) return (cell.value as double).toInt();
      return int.tryParse(cell.value.toString().replaceAll(',', '').trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // Helper to parse date cell with multiple formats (Excel serial, ISO, dd-MM-yyyy HH:mm, yyyy-MM-dd)
  DateTime? _parseDateCell(Sheet sheet, int row, int col) {
    if (col == -1) return null;
    final dateStr = _cellStr(sheet, row, col).trim();
    if (dateStr.isEmpty || dateStr == '-' || dateStr == '0') return null;

    try {
      final numDate = double.tryParse(dateStr);
      if (numDate != null && numDate > 30000 && numDate < 60000) {
        return DateTime(1899, 12, 30).add(Duration(days: numDate.toInt()));
      }
      return DateTime.parse(dateStr);
    } catch (_) {
      final parts = dateStr.split(RegExp(r'[\s-/:]+'));
      if (parts.length >= 3) {
        int first = int.tryParse(parts[0]) ?? 1;
        int second = int.tryParse(parts[1]) ?? 1;
        int third = int.tryParse(parts[2]) ?? DateTime.now().year;

        int year, month, day;
        if (first > 1000) {
          // Format YYYY-MM-DD
          year = first;
          month = second;
          day = third;
        } else if (third > 1000) {
          // Format DD-MM-YYYY
          day = first;
          month = second;
          year = third;
        } else {
          day = first;
          month = second;
          year = 2000 + third;
        }

        final hour = parts.length > 3 ? (int.tryParse(parts[3]) ?? 0) : 0;
        final minute = parts.length > 4 ? (int.tryParse(parts[4]) ?? 0) : 0;
        return DateTime(year, month.clamp(1, 12), day.clamp(1, 31), hour.clamp(0, 23), minute.clamp(0, 59));
      }
    }
    return null;
  }

  // Find sheet tab containing specific header keywords across multi-sheet workbooks
  Sheet? _findSheetWithHeaders(Excel excel, List<String> requiredHeaders) {
    for (var tableName in excel.tables.keys) {
      final sheet = excel.tables[tableName];
      if (sheet == null || sheet.maxRows == 0) continue;

      int searchLimit = sheet.maxRows < 20 ? sheet.maxRows : 20;
      for (int r = 0; r < searchLimit; r++) {
        for (int c = 0; c < sheet.maxColumns; c++) {
          final val = _cellStr(sheet, r, c).toUpperCase();
          for (final req in requiredHeaders) {
            if (val.contains(req.toUpperCase())) {
              return sheet; // Found the matching sheet tab!
            }
          }
        }
      }
    }
    // Fallback to first sheet if no sheet tab matched
    return excel.tables.isNotEmpty ? excel.tables[excel.tables.keys.first] : null;
  }

  // Find header row by searching the first 20 rows
  int _findHeaderRow(Sheet sheet, List<String> possibleNames) {
    if (sheet.maxRows == 0) return 0;
    int searchLimit = sheet.maxRows < 20 ? sheet.maxRows : 20;
    for (int r = 0; r < searchLimit; r++) {
      for (int c = 0; c < sheet.maxColumns; c++) {
        final val = _cellStr(sheet, r, c).toUpperCase();
        for (final name in possibleNames) {
          if (val.contains(name.toUpperCase())) {
            return r;
          }
        }
      }
    }
    return 0;
  }

  // Find column index by header name in specific header row
  int _findColumnInRow(Sheet sheet, int headerRow, List<String> possibleNames) {
    if (sheet.maxRows <= headerRow) return -1;
    for (int col = 0; col < sheet.maxColumns; col++) {
      final headerVal = _cellStr(sheet, headerRow, col).toUpperCase();
      for (final name in possibleNames) {
        if (headerVal.contains(name.toUpperCase())) {
          return col;
        }
      }
    }
    return -1;
  }

  // Legacy wrapper for single search
  int _findColumn(Sheet sheet, List<String> possibleNames) {
    final headerRow = _findHeaderRow(sheet, possibleNames);
    return _findColumnInRow(sheet, headerRow, possibleNames);
  }

  // ============================================
  // IMPORT PRODUCTS
  // Kolom VBA: KODE_INDUK, NAMA_BARANG, Harga, Stok, ISI/KARTON
  // ============================================
  Future<ImportResult> importProducts(Uint8List bytes) async {
    final excel = _decodeExcelSafely(bytes);
    final sheet = _findSheetWithHeaders(excel, ['KODE_INDUK', 'KODE INDUK', 'KODE', 'ID', 'NAMA_BARANG', 'NAMA BARANG', 'PRODUK']);

    if (sheet == null) {
      return ImportResult(totalRows: 0, successCount: 0, errorCount: 1, errors: ['File Excel kosong atau tidak valid.']);
    }

    final headerRow = _findHeaderRow(sheet, ['KODE_INDUK', 'KODE INDUK', 'KODE', 'ID', 'NAMA_BARANG', 'NAMA BARANG', 'PRODUK']);

    // Find columns
    final colKode = _findColumnInRow(sheet, headerRow, ['KODE_INDUK', 'KODE INDUK', 'KODE', 'ID']);
    final colNama = _findColumnInRow(sheet, headerRow, ['NAMA_BARANG', 'NAMA BARANG', 'NAMA', 'PRODUK']);
    final colHarga = _findColumnInRow(sheet, headerRow, ['HARGA', 'PRICE']);
    final colStok = _findColumnInRow(sheet, headerRow, ['STOK', 'STOCK', 'QTY']);
    final colIsi = _findColumnInRow(sheet, headerRow, ['ISI/KARTON', 'ISI KARTON', 'ISI', 'KARTON', 'PCS/CTN']);

    if (colKode == -1 || colNama == -1) {
      return ImportResult(
        totalRows: 0,
        successCount: 0,
        errorCount: 1,
        errors: ['Kolom KODE_INDUK atau NAMA_BARANG tidak ditemukan di file Excel. Pastikan header sesuai.'],
      );
    }

    int success = 0;
    int errors = 0;
    List<String> errorList = [];
    final totalRows = sheet.maxRows - headerRow - 1;

    for (int row = headerRow + 1; row < sheet.maxRows; row++) {
      try {
        final id = _cellStr(sheet, row, colKode);
        final name = _cellStr(sheet, row, colNama);
        final price = colHarga != -1 ? _cellDouble(sheet, row, colHarga) : 0.0;
        final stock = colStok != -1 ? _cellDouble(sheet, row, colStok) : 0.0;
        final pcsPerCtn = colIsi != -1 ? _cellDouble(sheet, row, colIsi).toInt() : 1;

        if (id.isEmpty && name.isEmpty) continue; // skip empty row

        final sizeGrams = Product.parseSizeFromName(name);

        final product = Product(
          id: id.isNotEmpty ? id : name.toLowerCase().replaceAll(' ', '_'),
          name: name,
          price: price,
          stock: stock,
          isiKarton: pcsPerCtn > 0 ? pcsPerCtn : 1,
          sizeGrams: sizeGrams,
        );

        await _dbService.saveProduct(product);
        success++;
      } catch (e) {
        errors++;
        errorList.add('Baris ${row + 1}: $e');
        debugPrint('Import product error at row $row: $e');
      }
    }

    return ImportResult(totalRows: totalRows, successCount: success, errorCount: errors, errors: errorList);
  }

  // ============================================
  // IMPORT CUSTOMERS
  // Kolom VBA: No, ID CUST, CUSTOMER, NAMA PELANGGAN, ALAMAT, Provinsi, NEGARA, PHONE, No KTP, Detail
  // ============================================
  Future<ImportResult> importCustomers(Uint8List bytes) async {
    final excel = _decodeExcelSafely(bytes);
    final sheet = _findSheetWithHeaders(excel, ['ID CUST', 'ID_CUST', 'ID CUSTOMER', 'IDCUST', 'ID PELANGGAN', 'NAMA PELANGGAN', 'PELANGGAN', 'CUSTOMER']);

    if (sheet == null) {
      return ImportResult(totalRows: 0, successCount: 0, errorCount: 1, errors: ['File Excel kosong atau tidak valid.']);
    }

    final headerRow = _findHeaderRow(sheet, ['ID CUST', 'ID_CUST', 'ID CUSTOMER', 'IDCUST', 'ID PELANGGAN', 'NAMA PELANGGAN', 'PELANGGAN', 'CUSTOMER']);

    // Find columns
    final colIdCust = _findColumnInRow(sheet, headerRow, ['ID CUST', 'ID_CUST', 'ID CUSTOMER', 'IDCUST', 'ID PELANGGAN']);
    final colCustomer = _findColumnInRow(sheet, headerRow, ['CUSTOMER']);
    final colNamaPelanggan = _findColumnInRow(sheet, headerRow, ['NAMA PELANGGAN', 'NAMA_PELANGGAN', 'PELANGGAN']);
    final colAlamat = _findColumnInRow(sheet, headerRow, ['ALAMAT', 'CITY', 'KOTA']);
    final colProvinsi = _findColumnInRow(sheet, headerRow, ['PROVINSI', 'PROVINCE']);
    final colNegara = _findColumnInRow(sheet, headerRow, ['NEGARA', 'COUNTRY']);
    final colPhone = _findColumnInRow(sheet, headerRow, ['PHONE', 'TELP', 'HP', 'NO HP']);
    final colKtp = _findColumnInRow(sheet, headerRow, ['NO KTP', 'KTP', 'NIK']);

    if (colIdCust == -1 && colNamaPelanggan == -1 && colCustomer == -1) {
      return ImportResult(
        totalRows: 0,
        successCount: 0,
        errorCount: 1,
        errors: ['Kolom ID CUST atau NAMA PELANGGAN tidak ditemukan di file Excel.'],
      );
    }

    int success = 0;
    int errors = 0;
    List<String> errorList = [];
    final totalRows = sheet.maxRows - headerRow - 1;

    for (int row = headerRow + 1; row < sheet.maxRows; row++) {
      try {
        final idCust = colIdCust != -1 ? _cellStr(sheet, row, colIdCust) : '';
        final customerName = colCustomer != -1 ? _cellStr(sheet, row, colCustomer) : '';
        final aliasName = colNamaPelanggan != -1 ? _cellStr(sheet, row, colNamaPelanggan) : customerName;

        if (idCust.isEmpty && customerName.isEmpty && aliasName.isEmpty) continue;

        final customer = Customer(
          id: idCust.isNotEmpty ? idCust : aliasName.toLowerCase().replaceAll(' ', '_'),
          customerName: customerName.isNotEmpty ? customerName : aliasName,
          aliasName: aliasName.isNotEmpty ? aliasName : customerName,
          address: colAlamat != -1 ? _cellStr(sheet, row, colAlamat) : '',
          city: colAlamat != -1 ? _cellStr(sheet, row, colAlamat) : '',
          province: colProvinsi != -1 ? _cellStr(sheet, row, colProvinsi) : '',
          country: colNegara != -1 ? _cellStr(sheet, row, colNegara) : 'INDONESIA',
          phone: colPhone != -1 ? _cellStr(sheet, row, colPhone) : '',
          ktpNumber: colKtp != -1 ? _cellStr(sheet, row, colKtp) : '',
        );

        await _dbService.saveCustomer(customer);
        success++;
      } catch (e) {
        errors++;
        errorList.add('Baris ${row + 1}: $e');
        debugPrint('Import customer error at row $row: $e');
      }
    }

    return ImportResult(totalRows: totalRows, successCount: success, errorCount: errors, errors: errorList);
  }

  // ============================================
  // IMPORT TRANSACTIONS (bulk from VBA export)
  // ============================================
  Future<ImportResult> importTransactions(Uint8List bytes, String createdBy) async {
    final excel = _decodeExcelSafely(bytes);
    final sheet = _findSheetWithHeaders(excel, [
      'NO INVOICE', 'INVOICE', 'NO_INVOICE', 'NOINVOICE', 'NO TRANSAKSI', 'NO_TRANSAKSI', 'NO. TRANSAKSI'
    ]);

    if (sheet == null) {
      return ImportResult(totalRows: 0, successCount: 0, errorCount: 1, errors: ['File Excel kosong atau tidak memiliki lembar transaksi.']);
    }

    final headerRow = _findHeaderRow(sheet, [
      'NO INVOICE', 'INVOICE', 'NO_INVOICE', 'NOINVOICE', 'NO TRANSAKSI', 'NO_TRANSAKSI', 'NO. TRANSAKSI'
    ]);

    final colInvoice = _findColumnInRow(sheet, headerRow, ['NO INVOICE', 'INVOICE', 'NO_INVOICE', 'NOINVOICE', 'NO TRANSAKSI', 'NO_TRANSAKSI', 'NO. TRANSAKSI']);
    final colCustId = _findColumnInRow(sheet, headerRow, ['ID PELANGGAN', 'ID CUST', 'ID_CUST', 'CUSTOMER ID', 'ID_PELANGGAN']);
    final colCustName = _findColumnInRow(sheet, headerRow, ['CUSTOMER', 'NAMA CUSTOMER']);
    final colAlias = _findColumnInRow(sheet, headerRow, ['NAMA PELANGGAN', 'ALIAS', 'PELANGGAN']);
    final colCity = _findColumnInRow(sheet, headerRow, ['KOTA', 'CITY']);
    final colProvince = _findColumnInRow(sheet, headerRow, ['PROVINSI', 'PROVINCE']);
    final colProduct = _findColumnInRow(sheet, headerRow, ['NAMA BARANG', 'PRODUK', 'PRODUCT', 'BARANG']);
    final colProductId = _findColumnInRow(sheet, headerRow, ['KODE_INDUK', 'KODE INDUK', 'KODE BARANG']);
    final colQty = _findColumnInRow(sheet, headerRow, ['QTY', 'JUMLAH']);
    final colHarga = _findColumnInRow(sheet, headerRow, ['HARGA', 'PRICE']);

    // Separate Diskon Rp vs Dalam %
    final colDiscRp = _findColumnInRow(sheet, headerRow, ['DISKON RP', 'DISCOUNT RP', 'DISC RP']);
    final colDiscPct = _findColumnInRow(sheet, headerRow, ['DALAM %', 'DISKON %', 'DISCOUNT %', 'DISC %', '%']);

    // Separate SubTotal vs Grand Total
    final colSubtotal = _findColumnInRow(sheet, headerRow, ['SUBTOTAL', 'SUB TOTAL']);
    final colTotal = _findColumnInRow(sheet, headerRow, ['GRAND TOTAL', 'TOTAL PENJUALAN']);

    // Dates & Statuses
    final colDate = _findColumnInRow(sheet, headerRow, ['TANGGAL', 'DATE']);
    final colDeliveryDate = _findColumnInRow(sheet, headerRow, ['TANGGAL DIKIRIM', 'TGL DIKIRIM', 'TGL KIRIM', 'TANGGAL KIRIM']);
    final colNote = _findColumnInRow(sheet, headerRow, ['CATATAN NOTA', 'CATATAN', 'NOTE', 'KETERANGAN']);
    final colStatusBarang = _findColumnInRow(sheet, headerRow, ['STATUS BARANG', 'STATUS KIRIM', 'STATUS PENGIRIMAN', 'STATUS']);
    final colStatusTransfer = _findColumnInRow(sheet, headerRow, ['STATUS TRANSFER BAYAR', 'STATUS TRANSFER', 'STATUS BAYAR', 'STATUS BAYAR/TRANSFER']);
    final colTransferDate = _findColumnInRow(sheet, headerRow, ['TANGGAL TRANSFER', 'TGL TRANSFER']);
    final colErpDate = _findColumnInRow(sheet, headerRow, [
      'STATUS ERP', 'TANGGAL ERP', 'TGL ERP', 'STATUS_ERP', 'TGL_ERP', 'TANGGAL_ERP', 'ERP', 'PROSES ERP', 'SYNC ERP', 'TGL SYNC ERP', 'TANGGAL SYNC ERP', 'INPUT ERP'
    ]);

    if (colInvoice == -1) {
      return ImportResult(
        totalRows: 0, successCount: 0, errorCount: 1,
        errors: ['Kolom NO INVOICE tidak ditemukan di file Excel.'],
      );
    }

    int success = 0;
    int errors = 0;
    List<String> errorList = [];
    final totalRows = sheet.maxRows - headerRow - 1;

    // Group rows by invoice number (one invoice may have multiple item rows)
    Map<String, List<int>> invoiceRows = {};
    for (int row = headerRow + 1; row < sheet.maxRows; row++) {
      final invNo = _cellStr(sheet, row, colInvoice);
      if (invNo.isEmpty) continue;
      invoiceRows.putIfAbsent(invNo, () => []).add(row);
    }

    for (final entry in invoiceRows.entries) {
      try {
        final invNoStr = entry.key.trim();
        final rows = entry.value;
        final firstRow = rows.first;
        if (invNoStr.isEmpty) {
          errors++;
          errorList.add('Baris ${firstRow + 1}: Nomor invoice kosong.');
          continue;
        }
        final docId = invNoStr;

        // Build items from all rows with same invoice
        List<Map<String, dynamic>> items = [];

        for (final row in rows) {
          final productName = colProduct != -1 ? _cellStr(sheet, row, colProduct) : '';
          final productId = colProductId != -1 ? _cellStr(sheet, row, colProductId) : productName;
          final qty = colQty != -1 ? _cellDouble(sheet, row, colQty) : 0.0;
          final harga = colHarga != -1 ? _cellDouble(sheet, row, colHarga) : 0.0;
          final grossTotal = qty * harga;

          double discRp = colDiscRp != -1 ? _cellDouble(sheet, row, colDiscRp) : 0.0;
          double discPct = colDiscPct != -1 ? _cellDouble(sheet, row, colDiscPct) : 0.0;

          // Convert/recalculate between Rp and % for exact consistency
          if (discPct > 0) {
            discRp = grossTotal * (discPct / 100.0);
          } else if (discRp > 0 && grossTotal > 0) {
            discPct = (discRp / grossTotal) * 100.0;
          }

          // Subtotal = Gross Total - Discount Amount (rounded to nearest Rupiah integer)
          double subtotal = (grossTotal - discRp).roundToDouble();
          if (subtotal < 0) subtotal = 0.0;

          if (productName.isNotEmpty && qty > 0) {
            final sizeGrams = Product.parseSizeFromName(productName);
            items.add({
              'productId': productId,
              'productName': productName,
              'price': harga,
              'qty': qty,
              'discountPercent': discPct,
              'subtotal': subtotal,
              'sizeGrams': sizeGrams,
              'weightKg': (qty * sizeGrams) / 1000.0,
            });
          }
        }

        if (items.isEmpty) {
          errors++;
          errorList.add('Invoice $invNoStr: Tidak ada item valid.');
          continue;
        }

        // Grand Total is ALWAYS the exact sum of all item subtotals in this invoice
        final grandTotal = items.fold(0.0, (sum, item) => sum + (item['subtotal'] as double)).roundToDouble();

        // Parse dates & ERP Status
        final trDate = _parseDateCell(sheet, firstRow, colDate) ?? DateTime.now();
        final deliveryDate = _parseDateCell(sheet, firstRow, colDeliveryDate) ?? trDate;
        final transferDate = _parseDateCell(sheet, firstRow, colTransferDate);
        
        DateTime? erpSyncDate = _parseDateCell(sheet, firstRow, colErpDate);
        if (erpSyncDate == null && colErpDate != -1) {
          final rawErpText = _cellStr(sheet, firstRow, colErpDate).toUpperCase().trim();
          if (rawErpText.isNotEmpty &&
              (rawErpText.contains('SUDAH') ||
               rawErpText.contains('ERP') ||
               rawErpText.contains('YA') ||
               rawErpText.contains('YES') ||
               rawErpText.contains('DONE') ||
               rawErpText.contains('SYNC') ||
               rawErpText == 'S' ||
               rawErpText == '1')) {
            erpSyncDate = deliveryDate;
          }
        }

        // Status Kirim / Status Barang
        String status = 'PENDING';
        if (colStatusBarang != -1) {
          final rawStatus = _cellStr(sheet, firstRow, colStatusBarang).toUpperCase();
          if (rawStatus.contains('KIRIM') || rawStatus.contains('DIKIRIM') || rawStatus.contains('SELESAI') || rawStatus.contains('SENT') || rawStatus.contains('DONE')) {
            status = 'DIKIRIM';
          }
        }

        // Status Bayar / Transfer
        String statusTransfer = 'UNPAID';
        if (colStatusTransfer != -1) {
          final rawStatusTransfer = _cellStr(sheet, firstRow, colStatusTransfer).toUpperCase();
          if (rawStatusTransfer.contains('PAID') || rawStatusTransfer.contains('LUNAS') || rawStatusTransfer.contains('TRANSFER') || rawStatusTransfer.contains('SUDAH')) {
            statusTransfer = 'PAID';
          }
        }

        await _dbService.importTransaction(
          invoiceNo: docId,
          customerId: colCustId != -1 ? _cellStr(sheet, firstRow, colCustId) : '',
          customerName: colCustName != -1 ? _cellStr(sheet, firstRow, colCustName) : '',
          aliasName: colAlias != -1 ? _cellStr(sheet, firstRow, colAlias) : '',
          date: trDate,
          deliveryDate: deliveryDate,
          city: colCity != -1 ? _cellStr(sheet, firstRow, colCity) : '',
          province: colProvince != -1 ? _cellStr(sheet, firstRow, colProvince) : '',
          country: 'INDONESIA',
          items: items,
          grandTotal: grandTotal,
          note: colNote != -1 ? _cellStr(sheet, firstRow, colNote) : '',
          status: status,
          statusTransfer: statusTransfer,
          transferDate: transferDate,
          erpSyncDate: erpSyncDate,
          createdBy: createdBy,
        );
        success++;
      } catch (e) {
        errors++;
        errorList.add('Invoice ${entry.key}: $e');
      }
    }

    return ImportResult(totalRows: totalRows, successCount: success, errorCount: errors, errors: errorList);
  }
}
