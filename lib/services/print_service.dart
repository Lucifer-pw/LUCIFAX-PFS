import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart' as model_tr;
import '../models/receivable.dart';
import 'logo_base64.dart';

class PrintService {
  // Format currency to Rupiah
  static final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  // Generate PDF tailored for Letter Portrait (8.5 x 11 inches) matching exact user screenshot & layout
  static Future<pw.Document> buildInvoiceDocument(model_tr.Transaction transaction) async {
    final pdf = pw.Document();

    // Letter Portrait page format (8.5" x 11" / 21.59 cm x 27.94 cm)
    const pageFormat = PdfPageFormat.letter;

    // Decode base64 Fiva circular logo image
    final logoBytes = base64Decode(fivaLogoBase64);
    final logoImage = pw.MemoryImage(logoBytes);

    final String delivDateStr = transaction.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(transaction.deliveryDate!) : '-';

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. TOP HEADER BOX (Solid 1px Black Border Box)
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 2),
                ),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left Column: Original Fiva Logo Image & Company Address
                    pw.Expanded(
                      flex: 6,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Real Circular Fiva Logo Image (Transparent background)
                          pw.ClipOval(
                            child: pw.Image(
                              logoImage,
                              width: 54,
                              height: 54,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'FIVA SOLO FOOD & MEAT SUPPLY',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412, Tel: 021-8484308',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                                pw.Text(
                                  'Fax: 021-84972237',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),

                    // Right Column: Invoice Metadata Fields
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildHeaderField('No Invoice', transaction.invoiceNo.toString()),
                          _buildHeaderField('Kepada', transaction.aliasName),
                          _buildHeaderField('Tanggal Pengiriman', delivDateStr),
                          _buildHeaderField('Alamat', '${transaction.city}, ${transaction.province}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SECTION TITLE BAR: INVOICE (Solid 1px Black Border Box)
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.black, width: 2),
                    right: pw.BorderSide(color: PdfColors.black, width: 2),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 2),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'INVOICE',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),

              // 3. TABLE GRID (FULL SOLID 1px BLACK BORDER MATCHING TEMPLATE WITH STATIC COLUMN WIDTHS)
              pw.Table(
                border: const pw.TableBorder(
                  top: pw.BorderSide(color: PdfColors.black, width: 2),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 2),
                  left: pw.BorderSide(color: PdfColors.black, width: 2),
                  right: pw.BorderSide(color: PdfColors.black, width: 2),
                  horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(255), // NAMA BARANG
                  1: pw.FixedColumnWidth(55),  // QTY
                  2: pw.FixedColumnWidth(85),  // HARGA
                  3: pw.FixedColumnWidth(75),  // DISKON
                  4: pw.FixedColumnWidth(102), // SUB TOTAL
                },
                children: [
                  // Table Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border(
                        bottom: pw.BorderSide(color: PdfColors.black, width: 2),
                      ),
                    ),
                    children: [
                      _buildCell('NAMA BARANG', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('QTY', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('HARGA', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('DISKON', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('SUB TOTAL', isHeader: true, align: pw.TextAlign.center),
                    ],
                  ),

                  // Data Rows
                  ...transaction.items.map((item) {
                    final displayName = item.isBonus 
                        ? '${item.productName} (BONUS)' 
                        : item.productName;
                    return pw.TableRow(
                      children: [
                        _buildCell(displayName),
                        _buildCell(item.qty.toStringAsFixed(0), align: pw.TextAlign.center),
                        _buildCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price), align: pw.TextAlign.right),
                        _buildCell(
                          item.isBonus ? '-' : (item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(2)}%' : '0,00%'),
                          align: pw.TextAlign.center,
                        ),
                        _buildCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal), align: pw.TextAlign.right),
                      ],
                    );
                  }),

                  // Padding Empty Rows to ensure uniform 14-row grid layout
                  ...List.generate((14 - transaction.items.length).clamp(0, 14), (_) {
                    return pw.TableRow(
                      children: [
                        _buildCell(' '),
                        _buildCell(' '),
                        _buildCell(' '),
                        _buildCell(' '),
                        _buildCell(' '),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 6), // Small gap between table and bottom section

              // 4. BOTTOM SECTION: Left (Note + Diterima Oleh) | Right (Grand Total + Signatures)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // LEFT COLUMN: Note (if present) + Diterima Oleh
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (transaction.note.isNotEmpty) ...[
                          pw.Text(
                            transaction.note,
                            style: pw.TextStyle(
                              color: PdfColors.red,
                              fontWeight: pw.FontWeight.bold,
                              fontStyle: pw.FontStyle.italic,
                              fontSize: 9,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                        ],
                        pw.Text(
                          'Diterima Oleh,',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                        ),
                        pw.SizedBox(height: 35),
                      ],
                    ),
                  ),

                  // RIGHT COLUMN: Grand Total Box + Pengirim & Hormat Kami
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      // Grand Total Box
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black, width: 2),
                        ),
                        child: pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.Container(
                              width: 110,
                              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                              ),
                              child: pw.Text(
                                'GRAND TOTAL',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.Container(
                              width: 102, // Matches SUB TOTAL column width
                              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                              child: pw.Text(
                                _rupiahFormatter.format(transaction.grandTotal),
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 8),

                      // Signatures: Pengirim & Hormat Kami
                      pw.Row(
                        children: [
                          pw.Column(
                            children: [
                              pw.Text(
                                'Pengirim',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                              ),
                              pw.SizedBox(height: 25),
                              pw.Text(
                                'Setiawan',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                          pw.SizedBox(width: 40),
                          pw.Column(
                            children: [
                              pw.Text(
                                'Hormat Kami,',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                              ),
                              pw.SizedBox(height: 25),
                              pw.Text(
                                'Setiawan',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Generates PDF download filename according to exact user pattern:
  // {no_invoice}_{AliasToko}_{Kota}_{Diskon% if present}_{tanggalkirim YYYYMMDD}.pdf
  // Example: 628_HANA_MAKMUR_PURBALINGGA_17,50%_20260721.pdf
  static String generateInvoiceFilename(model_tr.Transaction transaction) {
    // 1. Invoice No
    final String invNo = transaction.invoiceNo.toString();

    // 2. Alias Toko (or customerName fallback if aliasName is empty)
    String alias = transaction.aliasName.trim();
    if (alias.isEmpty) {
      alias = transaction.customerName.trim();
    }
    alias = alias.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (alias.isEmpty) alias = 'PELANGGAN';

    // 3. Kota
    String city = transaction.city.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (city.isEmpty) city = 'KOTA';

    // 4. Check for Discount % across items
    double maxDisc = 0.0;
    for (var item in transaction.items) {
      if (!item.isBonus && item.discountPercent > maxDisc) {
        maxDisc = item.discountPercent;
      }
    }
    String discPart = '';
    if (maxDisc > 0) {
      String formattedDisc = maxDisc.toStringAsFixed(maxDisc % 1 == 0 ? 0 : 2).replaceAll('.', ',');
      discPart = '_${formattedDisc}%';
    }

    // 5. Tanggal Kirim (deliveryDate ?? date)
    final DateTime targetDate = transaction.deliveryDate ?? transaction.date;
    final String dateStr = DateFormat('yyyyMMdd').format(targetDate);

    return '${invNo}_${alias}_${city}${discPart}_$dateStr.pdf';
  }

  // Opens direct browser/system print dialog with "Microsoft Print to PDF" target
  static Future<void> printInvoice(model_tr.Transaction transaction) async {
    final pdf = await buildInvoiceDocument(transaction);
    final filename = generateInvoiceFilename(transaction);
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: filename.replaceAll('.pdf', '')),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: filename,
    );
  }

  // Save PDF file locally for device file system or layout
  static Future<File?> generateInvoicePdf(model_tr.Transaction transaction) async {
    final pdf = await buildInvoiceDocument(transaction);
    final filename = generateInvoiceFilename(transaction);

    if (kIsWeb) {
      try {
        SystemChrome.setApplicationSwitcherDescription(
          ApplicationSwitcherDescription(label: filename.replaceAll('.pdf', '')),
        );
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
          name: filename,
        );
      } catch (e) {
        debugPrint("Print layout exception on web: $e");
      }
      return null;
    }

    final Directory outputDirectory = await _getOutputDirectory();
    final File file = File("${outputDirectory.path}/$filename");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  // Helper builder for header metadata fields
  static pw.Widget _buildHeaderField(String label, String value) {
    final cleanLabel = label.replaceAll(':', '').trim();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 105,
            child: pw.Text(
              cleanLabel,
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text(
            ':',
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  // Helper builder for PDF table grid cells
  static pw.Widget _buildCell(String text, {bool isHeader = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      height: 15.6,
      alignment: align == pw.TextAlign.left
          ? pw.Alignment.centerLeft
          : (align == pw.TextAlign.right ? pw.Alignment.centerRight : pw.Alignment.center),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // Save the raw text to document directory for local ESC/P printing utility
  static Future<File?> saveEscPRawFile(model_tr.Transaction transaction) async {
    final text = generateEscPRawText(transaction);
    final filename = "raw_invoice_${transaction.invoiceNo}.txt";

    if (kIsWeb) {
      try {
        final bytes = Uint8List.fromList(text.codeUnits);
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } catch (e) {
        debugPrint("Share raw ESC/P exception on web: $e");
      }
      return null;
    }

    final Directory outputDirectory = await _getOutputDirectory();
    final file = File("${outputDirectory.path}/$filename");
    await file.writeAsString(text);
    return file;
  }

  // Generate plain text with ESC/P control characters
  static String generateEscPRawText(model_tr.Transaction transaction) {
    final buffer = StringBuffer();
    
    const escInit = '\x1b@';
    const escSI = '\x0f';
    const escNormal = '\x12';
    const escBoldOn = '\x1bE';
    const escBoldOff = '\x1bF';
    const ff = '\x0c';

    final delivStr = transaction.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(transaction.deliveryDate!) : '-';

    buffer.write(escInit);
    buffer.write(escSI);

    buffer.writeln('${escBoldOn}FIVA SOLO FOOD & MEAT SUPPLY$escBoldOff');
    buffer.writeln("JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412");
    buffer.writeln("Tel: 021-8484308   Fax: 021-84972237");
    buffer.writeln("=" * 80);
    buffer.writeln("No Invoice : ${transaction.invoiceNo.toString().padRight(25)} Tanggal Kirim : $delivStr");
    buffer.writeln("Kepada     : ${transaction.customerName.padRight(25)} Alamat        : ${transaction.city}");
    buffer.writeln("-" * 80);

    final String thName = "NAMA BARANG".padRight(35);
    final String thQty = "QTY".padLeft(6);
    final String thPrice = "HARGA".padLeft(12);
    final String thDisc = "DISKON".padLeft(10);
    final String thSub = "SUB TOTAL".padLeft(15);
    buffer.writeln("$thName$thQty$thPrice$thDisc$thSub");
    buffer.writeln("-" * 80);

    for (var item in transaction.items) {
      final rawName = item.isBonus 
          ? '${item.productName} (BONUS)' 
          : item.productName;
      final name = rawName.length > 33 
          ? rawName.substring(0, 33) 
          : rawName;
      final qty = item.qty.toStringAsFixed(0);
      final price = item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price);
      final disc = item.isBonus ? '-' : (item.discountPercent > 0 ? "${item.discountPercent.toStringAsFixed(1)}%" : "0.00%");
      final sub = item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal);

      final String colName = name.padRight(35);
      final String colQty = qty.padLeft(6);
      final String colPrice = price.padLeft(12);
      final String colDisc = disc.padLeft(10);
      final String colSub = sub.padLeft(15);
      buffer.writeln("$colName$colQty$colPrice$colDisc$colSub");
    }

    final remainingRows = (14 - transaction.items.length).clamp(0, 14);
    for (var i = 0; i < remainingRows; i++) {
      buffer.writeln("");
    }

    buffer.writeln("-" * 80);

    final note = transaction.note.length > 35 
        ? transaction.note.substring(0, 35) 
        : transaction.note;
    final total = _rupiahFormatter.format(transaction.grandTotal);
    
    final String padTotalLabel = "GRAND TOTAL:".padLeft(17);
    final String padTotalVal = total.padLeft(15);
    buffer.writeln("Catatan: ${note.padRight(35)}$padTotalLabel$padTotalVal");
    buffer.writeln("=" * 80);

    buffer.write(escNormal);
    buffer.write(ff);
    
    return buffer.toString();
  }

  // Helper method to resolve target directory based on platform
  static Future<Directory> _getOutputDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Output directory is not supported on web.');
    }
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) {
        return dir;
      }
      return await getApplicationDocumentsDirectory();
    } else if (Platform.isWindows) {
      final dir = await getDownloadsDirectory();
      return dir ?? await getApplicationDocumentsDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  // ============================================================
  // KARTU PIUTANG PDF BUILDER & METHODS
  // ============================================================
  static String _getIndonesianMonthYear(DateTime dt) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final monthName = months[dt.month - 1];
    return '$monthName ${dt.year}';
  }

  static String generateKartuPiutangFilename({
    required String customerName,
    DateTime? periodDate,
  }) {
    final targetDate = periodDate ?? DateTime.now();
    final periodStr = _getIndonesianMonthYear(targetDate);
    final cleanCust = customerName.trim();
    if (cleanCust.isNotEmpty && cleanCust.toUpperCase() != 'ALL' && cleanCust.toUpperCase() != 'SEMUA') {
      return 'Kartu Piutang $cleanCust Periode $periodStr.pdf';
    } else {
      return 'Kartu Piutang Semua Toko Periode $periodStr.pdf';
    }
  }

  static Future<pw.Document> buildKartuPiutangDocument({
    required String customerName,
    required String city,
    required List<Receivable> items,
  }) async {
    final pdf = pw.Document();
    const pageFormat = PdfPageFormat.letter;

    final logoBytes = base64Decode(fivaLogoBase64);
    final logoImage = pw.MemoryImage(logoBytes);
    final double grandTotal = items.fold(0.0, (acc, r) => acc + r.nominal);
    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. TOP HEADER BOX (Solid 2px Black Border Box)
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 2),
                ),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left Column: Logo & Company Address
                    pw.Expanded(
                      flex: 6,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.ClipOval(
                            child: pw.Image(logoImage, width: 54, height: 54),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'FIVA SOLO FOOD & MEAT SUPPLY',
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412, Tel: 021-8484308',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                                pw.Text(
                                  'Fax: 021-84972237',
                                  style: const pw.TextStyle(fontSize: 8.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    // Right Column: Customer / Agen & Date Info
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          _buildHeaderField('Customer / Agen', customerName.isNotEmpty ? customerName : 'SEMUA AGEN'),
                          _buildHeaderField('Alamat / Kota', city.isNotEmpty ? city : '-'),
                          _buildHeaderField('Tanggal Cetak', dateStr),
                          _buildHeaderField('Total Invoice', '${items.length} Invoice'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. SECTION TITLE BAR: KARTU PIUTANG
              pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.black, width: 2),
                    right: pw.BorderSide(color: PdfColors.black, width: 2),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 2),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'KARTU PIUTANG',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5),
                ),
              ),

              // 3. TABLE GRID (Thick outer borders, thin inner lines)
              pw.Table(
                border: const pw.TableBorder(
                  top: pw.BorderSide(color: PdfColors.black, width: 2),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 2),
                  left: pw.BorderSide(color: PdfColors.black, width: 2),
                  right: pw.BorderSide(color: PdfColors.black, width: 2),
                  horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.5),
                ),
                columnWidths: const {
                  0: pw.FixedColumnWidth(30),  // NO
                  1: pw.FixedColumnWidth(110), // NO INVOICE
                  2: pw.FixedColumnWidth(160), // CUSTOMER / TOKO
                  3: pw.FixedColumnWidth(90),  // KOTA
                  4: pw.FixedColumnWidth(80),  // TGL KIRIM
                  5: pw.FixedColumnWidth(100), // NOMINAL
                },
                children: [
                  // Table Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 2)),
                    ),
                    children: [
                      _buildCell('NO', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('NO INVOICE', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('CUSTOMER / TOKO', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('KOTA', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('TGL KIRIM', isHeader: true, align: pw.TextAlign.center),
                      _buildCell('NOMINAL', isHeader: true, align: pw.TextAlign.center),
                    ],
                  ),
                  // Data Rows
                  ...List.generate(items.length, (index) {
                    final rec = items[index];
                    return pw.TableRow(
                      children: [
                        _buildCell('${index + 1}', align: pw.TextAlign.center),
                        _buildCell(rec.noInvoice, align: pw.TextAlign.center),
                        _buildCell(rec.toko),
                        _buildCell(rec.kota.isEmpty ? '-' : rec.kota, align: pw.TextAlign.center),
                        _buildCell(rec.tglKirim != null ? DateFormat('dd-MM-yyyy').format(rec.tglKirim!) : '-', align: pw.TextAlign.center),
                        _buildCell(_rupiahFormatter.format(rec.nominal), align: pw.TextAlign.right),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 12),

              // 4. BOTTOM SECTION: Grand Total Box (right-aligned)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 2),
                  ),
                  child: pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Container(
                        width: 110,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                        ),
                        child: pw.Text(
                          'GRAND TOTAL',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        width: 110,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: pw.Text(
                          _rupiahFormatter.format(grandTotal),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 12),

              // 5. SIGNATURE SECTION: Diterima Oleh (left) | Hormat Kami (right) - ALIGNED
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Diterima Oleh,', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.SizedBox(height: 40),
                        pw.Text('( .................................... )', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Hormat Kami,', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.SizedBox(height: 40),
                        pw.Text('( PT PUTRA FIVA SEJAHTERA )', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Opens direct browser/system print dialog with generated filename
  static Future<void> printKartuPiutang({
    required String customerName,
    required String city,
    required List<Receivable> items,
    DateTime? periodDate,
  }) async {
    final pdf = await buildKartuPiutangDocument(
      customerName: customerName,
      city: city,
      items: items,
    );
    final filename = generateKartuPiutangFilename(
      customerName: customerName,
      periodDate: periodDate,
    );

    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: filename.replaceAll('.pdf', '')),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: filename,
    );
  }

  // Downloads PDF directly to user's device
  static Future<void> downloadKartuPiutangPdf({
    required String customerName,
    required String city,
    required List<Receivable> items,
    DateTime? periodDate,
  }) async {
    final pdf = await buildKartuPiutangDocument(
      customerName: customerName,
      city: city,
      items: items,
    );
    final filename = generateKartuPiutangFilename(
      customerName: customerName,
      periodDate: periodDate,
    );
    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
