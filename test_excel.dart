import 'package:excel/excel.dart';
import 'package:archive/archive.dart';

void main() {
  final archive = Archive();
  final xml = '<styleSheet><numFmts count="1"><numFmt numFmtId="7" formatCode="General"/></numFmts></styleSheet>';
  archive.addFile(ArchiveFile('xl/styles.xml', xml.codeUnits.length, xml.codeUnits));

  final newArchive = Archive();
  for (var file in archive) {
    dynamic content = file.content;
    List<int> rawBytes = content is List<int> ? content : (content as InputStream).toUint8List();
    if (file.name.endsWith('styles.xml')) {
      final str = String.fromCharCodes(rawBytes);
      final cleaned = str.replaceAll(RegExp(r'<numFmts[^>]*>[\s\S]*?<\/numFmts>'), '');
      newArchive.addFile(ArchiveFile(file.name, cleaned.codeUnits.length, cleaned.codeUnits));
    }
  }

  final encoder = ZipEncoder();
  final bytes = encoder.encode(newArchive)!;
  print("Encoded new zip length: ${bytes.length}");
}
