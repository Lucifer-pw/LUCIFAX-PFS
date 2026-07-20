import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/attendance_record.dart';

class AttendancePdfService {
  static Future<Uint8List> generateAttendancePdf({
    required String monthYearName, // e.g. "Mei Tahun 2026"
    required List<AttendanceRecord> records,
  }) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Title
              pw.Text(
                'Rekap Absensi Pegawai Cabang Jawa Tengah Awal Bulan sampai tanggal 20 $monthYearName',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),

              // Rekap Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.5), // Nama
                  1: pw.FlexColumnWidth(2.5), // Tempat
                  2: pw.FlexColumnWidth(1.0), // HK
                  3: pw.FlexColumnWidth(1.0), // Off
                  4: pw.FlexColumnWidth(1.0), // Sakit
                  5: pw.FlexColumnWidth(1.0), // Ijin
                  6: pw.FlexColumnWidth(1.2), // Estimasi
                  7: pw.FlexColumnWidth(1.2), // Total HK
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _buildHeaderCell('Nama', fontBold),
                      _buildHeaderCell('Tempat', fontBold),
                      _buildHeaderCell('HK', fontBold),
                      _buildHeaderCell('Off', fontBold),
                      _buildHeaderCell('Sakit', fontBold),
                      _buildHeaderCell('Ijin', fontBold),
                      _buildHeaderCell('Estimasi', fontBold),
                      _buildHeaderCell('Total HK', fontBold),
                    ],
                  ),

                  // Data Rows
                  ...records.map((rec) {
                    return pw.TableRow(
                      children: [
                        _buildDataCell(rec.staffName, fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(rec.location, fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.hk), fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.off), fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.sakit), fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.ijin), fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.estimasi), fontRegular, align: pw.TextAlign.center),
                        _buildDataCell(_formatValue(rec.totalHk), fontBold, align: pw.TextAlign.center),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),

              // Signature / Footer
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Lucifax PFS - Jawa Tengah', style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700)),
                  pw.Text('Tanggal Cetak: ${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}', style: pw.TextStyle(font: fontRegular, fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static String _formatValue(double val) {
    if (val == 0) return '-';
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  static pw.Widget _buildHeaderCell(String title, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title,
        style: pw.TextStyle(font: font, fontSize: 10, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _buildDataCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 9),
        textAlign: align,
      ),
    );
  }
}
