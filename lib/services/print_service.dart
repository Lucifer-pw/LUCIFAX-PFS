import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart' as model_tr;
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
                  border: pw.Border.all(color: PdfColors.black, width: 1),
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
                    left: pw.BorderSide(color: PdfColors.black, width: 1),
                    right: pw.BorderSide(color: PdfColors.black, width: 1),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1),
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
                border: pw.TableBorder.all(color: PdfColors.black, width: 1),
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
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
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
              pw.SizedBox(height: 6),

              // 4. BOTTOM SECTION: GRAND TOTAL BOX & SIGNATURES
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Signature Left: Diterima Oleh (with Note above it if present)
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
                              fontSize: 10,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                        ],
                        pw.Text(
                          'Diterima Oleh,',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                        ),
                        pw.SizedBox(height: 35),
                      ],
                    ),
                  ),

                  // Right Block: Grand Total Box & Signatures (Pengirim & Hormat Kami)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      // GRAND TOTAL BOX
                      pw.Container(
                        width: 220,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black, width: 1),
                        ),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 4,
                              child: pw.Container(
                                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(right: pw.BorderSide(color: PdfColors.black, width: 1)),
                                ),
                                child: pw.Text(
                                  'GRAND TOTAL',
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            ),
                            pw.Expanded(
                              flex: 5,
                              child: pw.Container(
                                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                                child: pw.Text(
                                  _rupiahFormatter.format(transaction.grandTotal),
                                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 8),

                      // Signatures Row: Pengirim & Hormat Kami
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

  // Opens direct browser/system print dialog with "Microsoft Print to PDF" target
  static Future<void> printInvoice(model_tr.Transaction transaction) async {
    final pdf = await buildInvoiceDocument(transaction);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Invoice_${transaction.invoiceNo}.pdf',
    );
  }

  // Save PDF file locally for device file system or layout
  static Future<File?> generateInvoicePdf(model_tr.Transaction transaction) async {
    final pdf = await buildInvoiceDocument(transaction);

    final String cleanCustomer = transaction.customerName.replaceAll(' ', '_');
    final String dateStr = DateFormat('yyyyMMdd').format(transaction.date);
    final String filename = "Invoice_${transaction.invoiceNo}_${cleanCustomer}_$dateStr.pdf";

    if (kIsWeb) {
      try {
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
}
