import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/operational_invoice.dart';

class OperationalInvoicePdfService {
  static final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String _terbilang(double number) {
    final int n = number.toInt();
    if (n == 0) return 'Nol Rupiah';

    final units = ['', 'Satu', 'Dua', 'Tiga', 'Empat', 'Lima', 'Enam', 'Tujuh', 'Delapan', 'Sembilan', 'Sepuluh', 'Sebelas'];

    String convert(int num) {
      if (num < 12) return units[num];
      if (num < 20) return '${convert(num - 10)} Belas';
      if (num < 100) return '${convert(num ~/ 10)} Puluh ${convert(num % 10)}'.trim();
      if (num < 200) return 'Seratus ${convert(num - 100)}'.trim();
      if (num < 1000) return '${convert(num ~/ 100)} Ratus ${convert(num % 100)}'.trim();
      if (num < 2000) return 'Seribu ${convert(num - 1000)}'.trim();
      if (num < 1000000) return '${convert(num ~/ 1000)} Ribu ${convert(num % 1000)}'.trim();
      if (num < 1000000000) return '${convert(num ~/ 1000000)} Juta ${convert(num % 1000000)}'.trim();
      return num.toString();
    }

    return '${convert(n)} Rupiah';
  }

  static Future<Uint8List> generatePdf(OperationalInvoice invoice) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final darkNavy = PdfColor.fromHex('#0F172A');
    final primaryCyan = PdfColor.fromHex('#0284C7');
    final textDark = PdfColor.fromHex('#1E293B');
    final textGray = PdfColor.fromHex('#64748B');
    final lightBg = PdfColor.fromHex('#F8FAFC');
    final borderGray = PdfColor.fromHex('#CBD5E1');

    final String terbilangText = _terbilang(invoice.amount);
    final bool isPaid = invoice.status.toUpperCase() == 'LUNAS';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // ==========================================
                  // 1. KOP SURAT RESMI TAGIHAN DEVELOPER
                  // ==========================================
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PT PUTRA FIVA SEJAHTERA',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 16,
                              color: darkNavy,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'KANTOR CABANG JAWA TENGAH',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 10,
                              color: primaryCyan,
                              letterSpacing: 0.8,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Sistem Pengadaan & Layanan Teknologi Informasi (LUCIFAX PFS)',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 8.5,
                              color: textGray,
                            ),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: darkNavy, width: 1),
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              'INVOICE OPERASIONAL',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 9.5,
                                color: darkNavy,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Ref No: #${invoice.invoiceNo}',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 10),

                  // Double Border Line (Kop Line)
                  pw.Container(height: 2, color: darkNavy),
                  pw.SizedBox(height: 1),
                  pw.Container(height: 0.5, color: textGray),

                  pw.SizedBox(height: 14),

                  // ==========================================
                  // 2. JUDUL DOKUMEN TAGIHAN OPERASIONAL
                  // ==========================================
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'INVOICE TAGIHAN BIAYA OPERASIONAL & MAINTENANCE',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 11.5,
                          color: darkNavy,
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: isPaid ? PdfColor.fromHex('#DCFCE7') : PdfColor.fromHex('#FEF3C7'),
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(
                            color: isPaid ? PdfColor.fromHex('#16A34A') : PdfColor.fromHex('#D97706'),
                            width: 0.8,
                          ),
                        ),
                        child: pw.Text(
                          'STATUS: ${invoice.status.toUpperCase()}',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 8.5,
                            color: isPaid ? PdfColor.fromHex('#15803D') : PdfColor.fromHex('#B45309'),
                          ),
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 12),

                  // ==========================================
                  // 3. INFORMASI DETAIL METADATA
                  // ==========================================
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: lightBg,
                      border: pw.Border.all(color: borderGray, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _buildGridRow('Tanggal Tagihan', DateFormat('dd MMMM yyyy, HH:mm').format(invoice.date), fontBold, fontRegular),
                              _buildGridRow('Penyedia Layanan', 'LUCIFAX (DEV)', fontBold, fontRegular),
                              _buildGridRow('Kategori Operasional', invoice.category, fontBold, fontRegular),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 16),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _buildGridRow('Nomor Transaksi', '#${invoice.invoiceNo}', fontBold, fontRegular),
                              _buildGridRow('Metode Pembayaran', invoice.paymentMethod, fontBold, fontRegular),
                              _buildGridRow('Ditujukan Kepada', 'Kepala Cabang Jawa Tengah (Joko Setiawan)', fontBold, fontRegular),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 16),

                  // ==========================================
                  // 4. TABEL RINCIAN BIAYA & TERBILANG
                  // ==========================================
                  pw.Text(
                    'RINCIAN TAGIHAN & KETERANGAN BIAYA:',
                    style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: darkNavy),
                  ),
                  pw.SizedBox(height: 6),

                  pw.Table(
                    border: pw.TableBorder.all(color: borderGray, width: 0.8),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(30),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(1.2),
                      3: const pw.FlexColumnWidth(1.3),
                    },
                    children: [
                      // Table Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: darkNavy),
                        children: [
                          _buildTableCell('NO', fontBold, PdfColors.white, align: pw.Alignment.center, isHeader: true),
                          _buildTableCell('DESKRIPSI OPERASIONAL / MAINTENANCE', fontBold, PdfColors.white, isHeader: true),
                          _buildTableCell('KATEGORI', fontBold, PdfColors.white, isHeader: true),
                          _buildTableCell('JUMLAH (RP)', fontBold, PdfColors.white, align: pw.Alignment.centerRight, isHeader: true),
                        ],
                      ),
                      // Table Data Rows
                      ...List.generate(invoice.items.length, (idx) {
                        final item = invoice.items[idx];
                        return pw.TableRow(
                          children: [
                            _buildTableCell('${idx + 1}', fontRegular, textDark, align: pw.Alignment.center),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    item.title,
                                    style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: textDark),
                                  ),
                                  if (item.note.isNotEmpty) ...[
                                    pw.SizedBox(height: 4),
                                    pw.Text(
                                      item.note,
                                      style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _buildTableCell(item.category, fontRegular, textDark),
                            _buildTableCell(currencyFormatter.format(item.amount), fontBold, textDark, align: pw.Alignment.centerRight),
                          ],
                        );
                      }),
                      // Summary Total Row
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: lightBg),
                        children: [
                          pw.SizedBox(),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Row(
                              children: [
                                pw.Text('TERBILANG: ', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textGray)),
                                pw.Expanded(
                                  child: pw.Text(
                                    '"$terbilangText"',
                                    style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: darkNavy, fontStyle: pw.FontStyle.italic),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildTableCell('TOTAL NETTO', fontBold, darkNavy, align: pw.Alignment.centerRight),
                          _buildTableCell(currencyFormatter.format(invoice.amount), fontBold, primaryCyan, align: pw.Alignment.centerRight),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 32),

                  // ==========================================
                  // 5. TANDA TANGAN 2 PIHAK (KACAB JATENG & DEVELOPER)
                  // ==========================================
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSignatureBox('Mengetahui / Menyetujui,', '( Kepala Cabang Jawa Tengah )', 'Joko Setiawan', fontBold, fontRegular, textDark, textGray),
                      _buildSignatureBox('Penyedia Layanan,', '( Developer )', 'LUCIFAX (DEV)', fontBold, fontRegular, textDark, textGray),
                    ],
                  ),

                  pw.Spacer(),

                  // ==========================================
                  // 6. FOOTER RESMI
                  // ==========================================
                  pw.Container(
                    padding: const pw.EdgeInsets.only(top: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: borderGray, width: 0.8)),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'LUCIFAX PFS Enterprise System • Invoice Tagihan Biaya Operasional Developer kepada Kepala Cabang Jawa Tengah',
                        style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildGridRow(String label, String value, pw.Font fontBold, pw.Font fontRegular) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 105,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: PdfColor.fromHex('#64748B')),
            ),
          ),
          pw.Text(': ', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColor.fromHex('#64748B'))),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColor.fromHex('#0F172A')),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    pw.Font font,
    PdfColor color, {
    pw.Alignment align = pw.Alignment.centerLeft,
    bool isHeader = false,
  }) {
    return pw.Container(
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: isHeader ? 8.5 : 9,
          color: color,
        ),
      ),
    );
  }

  static pw.Widget _buildSignatureBox(
    String title,
    String role,
    String name,
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor textDark,
    PdfColor textGray,
  ) {
    return pw.Container(
      width: 200,
      child: pw.Column(
        children: [
          pw.Text(title, style: pw.TextStyle(font: fontRegular, fontSize: 9, color: textGray)),
          pw.Text(role, style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray)),
          pw.SizedBox(height: 46),
          pw.Container(height: 0.8, color: textDark),
          pw.SizedBox(height: 4),
          pw.Text(name, style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: textDark)),
        ],
      ),
    );
  }

  // ==========================================
  // FORMAT 2: RESI BUKTI BAYAR E-WALLET (DANA - GOOGLE CLOUD STYLE)
  // ==========================================
  static Future<Uint8List> generateDanaStylePdf(OperationalInvoice invoice) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final primaryBlue = PdfColor.fromHex('#118EEA');
    final lightBg = PdfColor.fromHex('#F1F5F9');
    final cardBg = PdfColor.fromHex('#FFFFFF');
    final textDark = PdfColor.fromHex('#0F172A');
    final textGray = PdfColor.fromHex('#64748B');
    final greenSuccess = PdfColor.fromHex('#10B981');
    final boxBlueBg = PdfColor.fromHex('#F0F9FF');

    final String formattedAmount = currencyFormatter.format(invoice.amount).replaceAll(' ', '');

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(320, 620, marginAll: 0),
        build: (pw.Context context) {
          return pw.Container(
            color: lightBg,
            child: pw.Column(
              children: [
                // Top Navigation Blue Bar
                pw.Container(
                  height: 48,
                  color: primaryBlue,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16),
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Row(
                    children: [
                      pw.Text('<  ', style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.white)),
                      pw.Text('Detail Transaksi', style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.white)),
                    ],
                  ),
                ),

                // Main White Card Receipt
                pw.Container(
                  margin: const pw.EdgeInsets.all(12),
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: cardBg,
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Google Logo & Watermark Area
                      pw.Center(
                        child: pw.Column(
                          children: [
                            // Circular Badge with 'G' Logo
                            pw.Container(
                              width: 58,
                              height: 58,
                              decoration: pw.BoxDecoration(
                                shape: pw.BoxShape.circle,
                                color: PdfColors.white,
                                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1.5),
                              ),
                              alignment: pw.Alignment.center,
                              child: pw.Text(
                                'G',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 34,
                                  color: PdfColor.fromHex('#4285F4'),
                                ),
                              ),
                            ),
                            pw.SizedBox(height: 10),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  DateFormat('dd MMM yyyy • HH:mm').format(invoice.date),
                                  style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray),
                                ),
                                pw.Text(
                                  'ID DANA 0813****0511',
                                  style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 10),
                            pw.Row(
                              children: [
                                pw.Container(
                                  width: 12,
                                  height: 12,
                                  decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: greenSuccess),
                                  alignment: pw.Alignment.center,
                                  child: pw.Text('✓', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
                                ),
                                pw.SizedBox(width: 6),
                                pw.Text(
                                  'Transaksi berhasil',
                                  style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: textGray),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 6),
                            pw.Align(
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'Google',
                                    style: pw.TextStyle(font: fontBold, fontSize: 13, color: textDark),
                                  ),
                                  pw.Text(
                                    invoice.title.isNotEmpty ? invoice.title : 'Google Cloud',
                                    style: pw.TextStyle(font: fontRegular, fontSize: 10.5, color: textGray),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      pw.SizedBox(height: 12),

                      // Total Bayar Box
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: pw.BoxDecoration(
                          color: boxBlueBg,
                          borderRadius: pw.BorderRadius.circular(6),
                          border: pw.Border.all(color: PdfColor.fromHex('#BAE6FD'), width: 0.8),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Total Bayar', style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: textDark)),
                            pw.Text(formattedAmount, style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: textDark)),
                          ],
                        ),
                      ),

                      pw.SizedBox(height: 12),

                      // Details List
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Harga', style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: textGray)),
                          pw.Text(formattedAmount, style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: textDark)),
                        ],
                      ),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Metode Pembayaran', style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: textGray)),
                          pw.Text(invoice.paymentMethod.isNotEmpty ? invoice.paymentMethod : 'Saldo DANA', style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: textDark)),
                        ],
                      ),

                      pw.SizedBox(height: 10),
                      pw.Container(height: 0.5, color: PdfColor.fromHex('#E2E8F0')),
                      pw.SizedBox(height: 8),

                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Detail Transaksi', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: textDark)),
                          pw.Text('v', style: pw.TextStyle(font: fontRegular, fontSize: 9, color: textGray)),
                        ],
                      ),
                      if (invoice.note.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(invoice.note, style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textGray)),
                      ],
                    ],
                  ),
                ),

                // Bottom Protection Banner Card
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 12),
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: primaryBlue,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Aman Pakai DANA 100%', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.white)),
                          pw.SizedBox(height: 2),
                          pw.Text('Jaminan Uang Kembali • DANA PROTECTION', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: PdfColors.white)),
                        ],
                      ),
                      pw.Text('🛡️', style: pw.TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ==========================================
  // FORMAT 3: FAKTUR PAJAK DJP / GOOGLE CLOUD STYLE (OPSI 2)
  // ==========================================
  static Future<Uint8List> generateFakturPajakStylePdf(OperationalInvoice invoice) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final textDark = PdfColor.fromHex('#000000');
    final textGray = PdfColor.fromHex('#4B5563');

    final String formattedAmount = currencyFormatter.format(invoice.amount).replaceAll('Rp ', '');
    // Standard tax calculation for reference: DPP = Amount / 1.11, PPN = Amount - DPP
    final double dpp = (invoice.amount / 1.11).roundToDouble();
    final double ppn = invoice.amount - dpp;
    final String formattedDpp = currencyFormatter.format(dpp).replaceAll('Rp ', '');
    final String formattedPpn = currencyFormatter.format(ppn).replaceAll('Rp ', '');
    final String formattedDate = DateFormat('dd MMMM yyyy').format(invoice.date);

    final String cleanInvoiceNo = invoice.invoiceNo.replaceAll(RegExp(r'[^0-9]'), '');
    final String serialNo = cleanInvoiceNo.length >= 16 
        ? cleanInvoiceNo.substring(0, 16) 
        : '040026${cleanInvoiceNo.padRight(10, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Center(
                  child: pw.Text(
                    'Faktur Pajak',
                    style: pw.TextStyle(font: fontBold, fontSize: 18, color: textDark),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Nama: GOOGLE CLOUD INDONESIA / LUCIFAX (DEV)', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                      pw.Text('Alamat: GEDUNG PACIFIC CENTURY PLACE LT.45 JL JENDERAL SUDIRMAN KAV.52-53, KOTA ADM. JAKARTA SELATAN #086234355501200000000', style: pw.TextStyle(font: fontRegular, fontSize: 7.5)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                // Main Bordered Table Box
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Section 1: Kode & Nomor Seri
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        child: pw.Text(
                          'Kode dan Nomor Seri Faktur Pajak: $serialNo',
                          style: pw.TextStyle(font: fontBold, fontSize: 9.5),
                        ),
                      ),

                      // Section 2: Pengusaha Kena Pajak
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#F3F4F6'),
                          border: const pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        child: pw.Text('Pengusaha Kena Pajak:', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Nama : GOOGLE CLOUD INDONESIA / LUCIFAX (DEV)', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                            pw.Text('Alamat : GEDUNG PACIFIC CENTURY PLACE LT.45 JL JENDERAL SUDIRMAN KAV.52-53, RT 000, RW 000, SENAYAN, KEBAYORAN BARU, KOTA ADM. JAKARTA SELATAN, DKI JAKARTA 12190', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
                            pw.Text('NPWP : 0862343555012000', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                          ],
                        ),
                      ),

                      // Section 3: Pembeli Barang Kena Pajak
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#F3F4F6'),
                          border: const pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        child: pw.Text('Pembeli Barang Kena Pajak / Penerima Jasa Kena Pajak:', style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Nama : PT Putra Fiva Sejahtera (Cabang Jawa Tengah) - Joko Setiawan', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                            pw.Text('Alamat : Jl. MT Haryono No.27, Manahan, Kec. Banjarsari, Kota Surakarta, Jawa Tengah 57139, Indonesia', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
                            pw.Text('NPWP : 000000000000000', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                            pw.Text('NIK : -', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                          ],
                        ),
                      ),

                      // Section 4: Items Table
                      pw.Table(
                        border: const pw.TableBorder(
                          horizontalInside: pw.BorderSide(color: PdfColors.black, width: 0.8),
                          verticalInside: pw.BorderSide(color: PdfColors.black, width: 0.8),
                          bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                        ),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(28),
                          1: const pw.FixedColumnWidth(55),
                          2: const pw.FlexColumnWidth(3),
                          3: const pw.FlexColumnWidth(1.4),
                        },
                        children: [
                          // Table Header
                          pw.TableRow(
                            children: [
                              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('No.', style: pw.TextStyle(font: fontBold, fontSize: 8))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Kode Barang / Jasa', style: pw.TextStyle(font: fontBold, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Nama Barang Kena Pajak / Jasa Kena Pajak', style: pw.TextStyle(font: fontBold, fontSize: 8))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), alignment: pw.Alignment.center, child: pw.Text('Harga Jual / Penggantian / Uang Muka / Termin (Rp)', style: pw.TextStyle(font: fontBold, fontSize: 7.5), textAlign: pw.TextAlign.center)),
                            ],
                          ),
                          // Row Items
                          ...List.generate(invoice.items.length, (idx) {
                            final item = invoice.items[idx];
                            final formattedItemAmount = currencyFormatter.format(item.amount).replaceAll('Rp ', '');
                            return pw.TableRow(
                              children: [
                                pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.topCenter, child: pw.Text('${idx + 1}', style: pw.TextStyle(font: fontRegular, fontSize: 8.5))),
                                pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.topCenter, child: pw.Text('17020${idx + 9}', style: pw.TextStyle(font: fontRegular, fontSize: 8.5))),
                                pw.Container(
                                  padding: const pw.EdgeInsets.all(6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(item.title.isNotEmpty ? item.title : 'Google Cloud / Maintenance Server', style: pw.TextStyle(font: fontBold, fontSize: 8.5)),
                                      pw.SizedBox(height: 2),
                                      pw.Text('Rp $formattedItemAmount x 1,00 ${item.category}', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
                                      pw.Text('Potongan Harga = Rp 0,00', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
                                      pw.Text('PPnBM (0,00%) = Rp 0,00', style: pw.TextStyle(font: fontRegular, fontSize: 8)),
                                      if (item.note.isNotEmpty) ...[
                                        pw.SizedBox(height: 2),
                                        pw.Text('Catatan: ${item.note}', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray)),
                                      ],
                                    ],
                                  ),
                                ),
                                pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.topRight, child: pw.Text(formattedItemAmount, style: pw.TextStyle(font: fontRegular, fontSize: 8.5))),
                              ],
                            );
                          }),
                        ],
                      ),

                      // Section 5: Summary Rows
                      _buildFakturSummaryRow('Harga Jual / Penggantian / Uang Muka / Termin', formattedAmount, fontRegular, fontBold),
                      _buildFakturSummaryRow('Dikurangi Potongan Harga', '0,00', fontRegular, fontBold),
                      _buildFakturSummaryRow('Dikurangi Uang Muka yang telah diterima', '0,00', fontRegular, fontBold),
                      _buildFakturSummaryRow('Dasar Pengenaan Pajak', formattedDpp, fontRegular, fontBold),
                      _buildFakturSummaryRow('Jumlah PPN (Pajak Pertambahan Nilai)', formattedPpn, fontRegular, fontBold),
                      _buildFakturSummaryRow('Jumlah PPnBM (Pajak Penjualan atas Barang Mewah)', '0,00', fontRegular, fontBold),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                // Legal Disclaimer
                pw.Text(
                  'Sesuai dengan ketentuan yang berlaku, Direktorat Jenderal Pajak mengatur bahwa Faktur Pajak ini telah ditandatangani secara elektronik sehingga tidak diperlukan tanda tangan basah pada Faktur Pajak ini.',
                  style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textDark),
                ),

                pw.SizedBox(height: 14),

                // Signature & QR Area
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    // Left QR Code (Verification Barcode)
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: 'https://efaktur.pajak.go.id/verifikasi?noseri=$serialNo&npwp=0862343555012000&nilai=$formattedAmount',
                      width: 70,
                      height: 70,
                    ),

                    // Right E-Signature Box
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('KOTA ADM. JAKARTA SELATAN, $formattedDate', style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
                        pw.SizedBox(height: 4),
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: 'Ditandatangani secara elektronik oleh RIZAL AWAB / LUCIFAX DEV pada $formattedDate',
                          width: 50,
                          height: 50,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Ditandatangani secara elektronik', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textGray)),
                        pw.Text('LUCIFAX (DEV) / RIZAL AWAB', style: pw.TextStyle(font: fontBold, fontSize: 8.5)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildFakturSummaryRow(String label, String value, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(label, style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
          ),
          pw.SizedBox(
            width: 110,
            child: pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 8.5), textAlign: pw.TextAlign.right),
          ),
        ],
      ),
    );
  }
}
