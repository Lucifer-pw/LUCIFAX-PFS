import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart' as model_tr;

class PrintService {
  // Format currency to Rupiah
  static final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  // Generate PDF tailored for 9.5" x 5.5" Continuous Form (684 x 396 points)
  static Future<File> generateInvoicePdf(model_tr.Transaction transaction) async {
    final pdf = pw.Document();

    // 9.5 x 5.5 inches in points
    const customWidth = 9.5 * PdfPageFormat.inch;
    const customHeight = 5.5 * PdfPageFormat.inch;
    const pageFormat = PdfPageFormat(customWidth, customHeight,
        marginLeft: 20, marginRight: 20, marginTop: 15, marginBottom: 15);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'FIVA SOLO FOOD & MEAT SUPPLY',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                      ),
                      pw.Text(
                        'JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        'Tel: 021-8484308   Fax: 021-84972237',
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ],
                  ),
                  pw.Text(
                    'INVOICE',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              
              // Invoice metadata
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildHeaderRow('No Invoice:', transaction.invoiceNo.toString()),
                        _buildHeaderRow('Kepada:', transaction.customerName),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildHeaderRow('Tgl Kirim:', DateFormat('dd-MM-yyyy').format(transaction.deliveryDate)),
                        _buildHeaderRow('Alamat:', transaction.city),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.5), // Nama Barang
                  1: const pw.FlexColumnWidth(0.8), // Qty
                  2: const pw.FlexColumnWidth(1.2), // Harga
                  3: const pw.FlexColumnWidth(0.8), // Diskon
                  4: const pw.FlexColumnWidth(1.5), // Subtotal
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableCell('NAMA BARANG', isHeader: true),
                      _buildTableCell('QTY', isHeader: true, align: pw.TextAlign.center),
                      _buildTableCell('HARGA', isHeader: true, align: pw.TextAlign.right),
                      _buildTableCell('DISKON', isHeader: true, align: pw.TextAlign.center),
                      _buildTableCell('SUB TOTAL', isHeader: true, align: pw.TextAlign.right),
                    ],
                  ),
                  // Table rows
                  ...transaction.items.map((item) {
                    return pw.TableRow(
                      children: [
                        _buildTableCell(item.productName),
                        _buildTableCell(item.qty.toStringAsFixed(0), align: pw.TextAlign.center),
                        _buildTableCell(_rupiahFormatter.format(item.price), align: pw.TextAlign.right),
                        _buildTableCell(
                          item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(2)}%' : '0,00%',
                          align: pw.TextAlign.center,
                        ),
                        _buildTableCell(_rupiahFormatter.format(item.subtotal), align: pw.TextAlign.right),
                      ],
                    );
                  }),
                  // Padding empty rows to maintain fixed height layout if items < 10
                  ...List.generate(10 - transaction.items.length, (_) {
                    return pw.TableRow(
                      children: [
                        _buildTableCell(''),
                        _buildTableCell('', align: pw.TextAlign.center),
                        _buildTableCell('', align: pw.TextAlign.right),
                        _buildTableCell('', align: pw.TextAlign.center),
                        _buildTableCell('', align: pw.TextAlign.right),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 6),

              // Bottom Section (Note and Grand Total)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey, width: 0.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Keterangan / Catatan:', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 2),
                          pw.Text(transaction.note.isNotEmpty ? transaction.note : '-', style: const pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('GRAND TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text(
                          _rupiahFormatter.format(transaction.grandTotal),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                        ),
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

    // Save locally on the user's device (e.g. Downloads directory)
    final Directory outputDirectory = await _getOutputDirectory();

    final String path = outputDirectory!.path;
    final String cleanCustomer = transaction.customerName.replaceAll(' ', '_');
    final String cleanCity = transaction.city.replaceAll(' ', '_');
    final String dateStr = DateFormat('yyyyMMdd').format(transaction.date);
    
    final String filename = "${transaction.invoiceNo}_${cleanCustomer}_${cleanCity}_$dateStr.pdf";
    final File file = File("$path/$filename");
    
    await file.writeAsBytes(await pdf.save());
    debugPrint("PDF saved successfully to: ${file.path}");
    return file;
  }

  // Helper builder for PDF headers
  static pw.Widget _buildHeaderRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }

  // Helper builder for PDF table cells
  static pw.Widget _buildTableCell(String text, {bool isHeader = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.5 : 7,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // Generate plain text with ESC/P control characters for Epson dot-matrix printers
  static String generateEscPRawText(model_tr.Transaction transaction) {
    final buffer = StringBuffer();
    
    // ESC/P Commands
    const escInit = '\x1b@';      // Initialize printer
    const escSI = '\x0f';        // Select condensed font (17 CPI)
    const escNormal = '\x12';    // Select normal font (10 CPI)
    const escBoldOn = '\x1bE';    // Bold on
    const escBoldOff = '\x1bF';   // Bold off
    const ff = '\x0c';            // Form Feed (Page Eject)

    final delivStr = DateFormat('dd-MM-yyyy').format(transaction.deliveryDate);

    buffer.write(escInit);
    buffer.write(escSI); // Set to condensed font so we can fit more characters (up to 137 cols on half-page width)

    // Invoice Header
    buffer.writeln('${escBoldOn}FIVA SOLO FOOD & MEAT SUPPLY$escBoldOff');
    buffer.writeln("JL. Pembangunan II No. 27 Jatibening I, Pondok Gede, Bekasi 17412");
    buffer.writeln("Tel: 021-8484308   Fax: 021-84972237");
    buffer.writeln("=" * 80);
    buffer.writeln("No Invoice : ${transaction.invoiceNo.toString().padRight(25)} Tanggal Kirim : $delivStr");
    buffer.writeln("Kepada     : ${transaction.customerName.padRight(25)} Alamat        : ${transaction.city}");
    buffer.writeln("-" * 80);

    // Table Header
    // Column widths: Nama Barang (35), Qty (6), Harga (12), Diskon (10), Subtotal (15) = 78 chars
    final String thName = "NAMA BARANG".padRight(35);
    final String thQty = "QTY".padLeft(6);
    final String thPrice = "HARGA".padLeft(12);
    final String thDisc = "DISKON".padLeft(10);
    final String thSub = "SUB TOTAL".padLeft(15);
    buffer.writeln("$thName$thQty$thPrice$thDisc$thSub");
    buffer.writeln("-" * 80);

    // Write Items (Up to 10 rows)
    for (var item in transaction.items) {
      final name = item.productName.length > 33 
          ? item.productName.substring(0, 33) 
          : item.productName;
      final qty = item.qty.toStringAsFixed(0);
      final price = _rupiahFormatter.format(item.price);
      final disc = item.discountPercent > 0 ? "${item.discountPercent.toStringAsFixed(1)}%" : "0.00%";
      final sub = _rupiahFormatter.format(item.subtotal);

      final String colName = name.padRight(35);
      final String colQty = qty.padLeft(6);
      final String colPrice = price.padLeft(12);
      final String colDisc = disc.padLeft(10);
      final String colSub = sub.padLeft(15);
      buffer.writeln("$colName$colQty$colPrice$colDisc$colSub");
    }

    // Fill remaining table lines with empty spaces so layout is uniform
    final remainingRows = 10 - transaction.items.length;
    for (var i = 0; i < remainingRows; i++) {
      buffer.writeln("");
    }

    buffer.writeln("-" * 80);

    // Notes and Grand Total Row
    final note = transaction.note.length > 35 
        ? transaction.note.substring(0, 35) 
        : transaction.note;
    final total = _rupiahFormatter.format(transaction.grandTotal);
    
    final String padTotalLabel = "GRAND TOTAL:".padLeft(17);
    final String padTotalVal = total.padLeft(15);
    buffer.writeln("Catatan: ${note.padRight(35)}$padTotalLabel$padTotalVal");
    buffer.writeln("=" * 80);

    buffer.write(escNormal); // Restore normal font
    buffer.write(ff);        // Form feed to align paper to next tear sheet automatically
    
    return buffer.toString();
  }

  // Save the raw text to document directory for local printing utility
  static Future<File> saveEscPRawFile(model_tr.Transaction transaction) async {
    final text = generateEscPRawText(transaction);
    final Directory outputDirectory = await _getOutputDirectory();
    final filename = "raw_invoice_${transaction.invoiceNo}.txt";
    final file = File("${outputDirectory.path}/$filename");
    await file.writeAsString(text);
    return file;
  }

  // Helper method to resolve target directory based on platform
  static Future<Directory> _getOutputDirectory() async {
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
