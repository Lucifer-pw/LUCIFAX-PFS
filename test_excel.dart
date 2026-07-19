import 'package:excel/excel.dart';

void main() {
  var excel = Excel.createExcel();
  var sheet = excel['Sheet1'];
  var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
  cell.value = TextCellValue('test');
  print('Excel library compiled successfully!');
}
