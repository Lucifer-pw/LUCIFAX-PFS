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

  // Clean custom numFmtId < 164 in styles.xml to avoid Excel package decode exceptions
  Uint8List _cleanExcelBytes(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (var file in archive) {
        if (file.name.endsWith('styles.xml')) {
          final String content = String.fromCharCodes(file.content as List<int>);
          final regex = RegExp(r'numFmtId="([0-9]+)"');
          final String cleanedContent = content.replaceAllMapped(regex, (match) {
            final int id = int.tryParse(match.group(1) ?? '') ?? 0;
            if (id > 0 && id < 164) {
              return 'numFmtId="0"';
            }
            return match.group(0)!;
          });
          final bytesData = cleanedContent.codeUnits;
          newArchive.addFile(ArchiveFile(file.name, bytesData.length, bytesData));
        } else {
          newArchive.addFile(file);
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

  // Find column index by header name (case-insensitive, partial match)
  int _findColumn(Sheet sheet, List<String> possibleNames) {
    if (sheet.maxRows == 0) return -1;
    for (int col = 0; col < sheet.maxColumns; col++) {
      final headerVal = _cellStr(sheet, 0, col).toUpperCase();
      for (final name in possibleNames) {
        if (headerVal.contains(name.toUpperCase())) {
          return col;
        }
      }
    }
    return -1;
  }

  // ============================================
  // IMPORT PRODUCTS
  // Kolom VBA: KODE_INDUK, NAMA_BARANG, Harga, Stok, ISI/KARTON
  // ============================================
  Future<ImportResult> importProducts(Uint8List bytes) async {
    final excel = _decodeExcelSafely(bytes);
    final sheet = excel.tables[excel.tables.keys.first]!;

    // Find columns
    final colKode = _findColumn(sheet, ['KODE_INDUK', 'KODE INDUK', 'KODE', 'ID']);
    final colNama = _findColumn(sheet, ['NAMA_BARANG', 'NAMA BARANG', 'NAMA', 'PRODUK']);
    final colHarga = _findColumn(sheet, ['HARGA', 'PRICE']);
    final colStok = _findColumn(sheet, ['STOK', 'STOCK', 'QTY']);
    final colIsi = _findColumn(sheet, ['ISI/KARTON', 'ISI KARTON', 'ISI', 'KARTON', 'PCS/CTN']);

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
    final totalRows = sheet.maxRows - 1; // Exclude header

    for (int row = 1; row < sheet.maxRows; row++) {
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
    final sheet = excel.tables[excel.tables.keys.first]!;

    // Find columns
    final colIdCust = _findColumn(sheet, ['ID CUST', 'ID_CUST', 'ID CUSTOMER', 'IDCUST', 'ID PELANGGAN']);
    final colCustomer = _findColumn(sheet, ['CUSTOMER']);
    final colNamaPelanggan = _findColumn(sheet, ['NAMA PELANGGAN', 'NAMA_PELANGGAN', 'PELANGGAN']);
    final colAlamat = _findColumn(sheet, ['ALAMAT', 'CITY', 'KOTA']);
    final colProvinsi = _findColumn(sheet, ['PROVINSI', 'PROVINCE']);
    final colNegara = _findColumn(sheet, ['NEGARA', 'COUNTRY']);
    final colPhone = _findColumn(sheet, ['PHONE', 'TELP', 'HP', 'NO HP']);
    final colKtp = _findColumn(sheet, ['NO KTP', 'KTP', 'NIK']);

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
    final totalRows = sheet.maxRows - 1;

    for (int row = 1; row < sheet.maxRows; row++) {
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
    final sheet = excel.tables[excel.tables.keys.first]!;

    final colInvoice = _findColumn(sheet, ['NO INVOICE', 'INVOICE', 'NO_INVOICE', 'NOINVOICE', 'NO TRANSAKSI', 'NO_TRANSAKSI', 'NO. TRANSAKSI']);
    final colCustId = _findColumn(sheet, ['ID CUST', 'ID_CUST', 'CUSTOMER ID', 'ID PELANGGAN', 'ID_PELANGGAN']);
    final colCustName = _findColumn(sheet, ['CUSTOMER', 'NAMA CUSTOMER']);
    final colAlias = _findColumn(sheet, ['NAMA PELANGGAN', 'ALIAS', 'PELANGGAN']);
    final colCity = _findColumn(sheet, ['KOTA', 'CITY']);
    final colProvince = _findColumn(sheet, ['PROVINSI', 'PROVINCE']);
    final colProduct = _findColumn(sheet, ['NAMA BARANG', 'PRODUK', 'PRODUCT', 'BARANG']);
    final colProductId = _findColumn(sheet, ['KODE_INDUK', 'KODE INDUK', 'KODE BARANG']);
    final colQty = _findColumn(sheet, ['QTY', 'JUMLAH']);
    final colHarga = _findColumn(sheet, ['HARGA', 'PRICE']);
    final colDiscount = _findColumn(sheet, ['DISKON', 'DISCOUNT', 'DISC', '%']);
    final colSubtotal = _findColumn(sheet, ['SUBTOTAL', 'SUB TOTAL', 'TOTAL']);
    final colTotal = _findColumn(sheet, ['GRAND TOTAL', 'TOTAL']);
    final colDate = _findColumn(sheet, ['TANGGAL', 'DATE', 'TGL KIRIM', 'TANGGAL KIRIM']);
    final colNote = _findColumn(sheet, ['CATATAN', 'NOTE', 'KETERANGAN']);

    if (colInvoice == -1) {
      return ImportResult(
        totalRows: 0, successCount: 0, errorCount: 1,
        errors: ['Kolom NO INVOICE tidak ditemukan di file Excel.'],
      );
    }

    int success = 0;
    int errors = 0;
    List<String> errorList = [];
    final totalRows = sheet.maxRows - 1;

    // Group rows by invoice number (one invoice may have multiple item rows)
    Map<String, List<int>> invoiceRows = {};
    for (int row = 1; row < sheet.maxRows; row++) {
      final invNo = _cellStr(sheet, row, colInvoice);
      if (invNo.isEmpty) continue;
      invoiceRows.putIfAbsent(invNo, () => []).add(row);
    }

    for (final entry in invoiceRows.entries) {
      try {
        final invNoStr = entry.key;
        final rows = entry.value;
        final firstRow = rows.first;
        final invoiceNo = int.tryParse(invNoStr) ?? 0;
        if (invoiceNo <= 0) {
          errors++;
          errorList.add('Invoice "$invNoStr": Nomor invoice tidak valid.');
          continue;
        }

        // Build items from all rows with same invoice
        List<Map<String, dynamic>> items = [];
        double grandTotal = 0;

        for (final row in rows) {
          final productName = colProduct != -1 ? _cellStr(sheet, row, colProduct) : '';
          final productId = colProductId != -1 ? _cellStr(sheet, row, colProductId) : productName;
          final qty = colQty != -1 ? _cellDouble(sheet, row, colQty) : 0;
          final harga = colHarga != -1 ? _cellDouble(sheet, row, colHarga) : 0;
          final disc = colDiscount != -1 ? _cellDouble(sheet, row, colDiscount) : 0;
          final subtotal = colSubtotal != -1 ? _cellDouble(sheet, row, colSubtotal) : (qty * harga * (1 - disc / 100));

          if (productName.isNotEmpty && qty > 0) {
            final sizeGrams = Product.parseSizeFromName(productName);
            items.add({
              'productId': productId,
              'productName': productName,
              'price': harga,
              'qty': qty,
              'discountPercent': disc,
              'subtotal': subtotal,
              'sizeGrams': sizeGrams,
              'weightKg': (qty * sizeGrams) / 1000.0,
            });
            grandTotal += subtotal;
          }
        }

        if (items.isEmpty) {
          errors++;
          errorList.add('Invoice $invNoStr: Tidak ada item valid.');
          continue;
        }

        // Get total from column if available
        if (colTotal != -1) {
          final totalFromSheet = _cellDouble(sheet, firstRow, colTotal);
          if (totalFromSheet > 0) grandTotal = totalFromSheet;
        }

        // Parse delivery date
        DateTime deliveryDate = DateTime.now();
        if (colDate != -1) {
          final dateStr = _cellStr(sheet, firstRow, colDate);
          if (dateStr.isNotEmpty) {
            // Try multiple date formats
            try {
              deliveryDate = DateTime.parse(dateStr);
            } catch (_) {
              // Try dd-MM-yyyy or dd/MM/yyyy
              final parts = dateStr.split(RegExp(r'[-/]'));
              if (parts.length == 3) {
                deliveryDate = DateTime(
                  int.tryParse(parts[2]) ?? DateTime.now().year,
                  int.tryParse(parts[1]) ?? 1,
                  int.tryParse(parts[0]) ?? 1,
                );
              }
            }
          }
        }

        await _dbService.importTransaction(
          invoiceNo: invoiceNo,
          customerId: colCustId != -1 ? _cellStr(sheet, firstRow, colCustId) : '',
          customerName: colCustName != -1 ? _cellStr(sheet, firstRow, colCustName) : '',
          aliasName: colAlias != -1 ? _cellStr(sheet, firstRow, colAlias) : '',
          deliveryDate: deliveryDate,
          city: colCity != -1 ? _cellStr(sheet, firstRow, colCity) : '',
          province: colProvince != -1 ? _cellStr(sheet, firstRow, colProvince) : '',
          country: 'INDONESIA',
          items: items,
          grandTotal: grandTotal,
          note: colNote != -1 ? _cellStr(sheet, firstRow, colNote) : '',
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
