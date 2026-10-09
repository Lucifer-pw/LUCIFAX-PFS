import 'dart:typed_data';
import 'package:printing/printing.dart';

Future<void> downloadFileBytes({
  required Uint8List bytes,
  required String fileName,
  String mimeType = 'application/octet-stream',
}) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
