import 'dart:async';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import '../models/staff.dart';
import '../models/attendance_record.dart';
import '../services/firebase_service.dart';

class AttendanceProvider extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();

  List<Staff> _staffList = [];
  List<AttendanceRecord> _attendanceList = [];
  bool _isLoading = false;
  String _selectedMonthYear = ''; // Format: MM-yyyy e.g. "05-2026"
  String _hrdPhone = '6281234567890'; // Default HRD WA Number

  StreamSubscription? _staffSub;
  StreamSubscription? _attendanceSub;

  List<Staff> get staffList => _staffList;
  List<AttendanceRecord> get attendanceList => _attendanceList;
  bool get isLoading => _isLoading;
  String get selectedMonthYear => _selectedMonthYear;
  String get hrdPhone => _hrdPhone;

  AttendanceProvider() {
    // Default to current month e.g. "05-2026"
    final now = DateTime.now();
    _selectedMonthYear = '${now.month.toString().padLeft(2, '0')}-${now.year}';
    _initStreams();
  }

  void _initStreams() {
    _staffSub = _firebaseService.streamStaff().listen((list) {
      _staffList = list;
      notifyListeners();
    });

    _subscribeAttendance();
  }

  void setMonthYear(String monthYear) {
    if (_selectedMonthYear != monthYear) {
      _selectedMonthYear = monthYear;
      _subscribeAttendance();
      notifyListeners();
    }
  }

  void setHrdPhone(String phone) {
    _hrdPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!_hrdPhone.startsWith('62') && _hrdPhone.startsWith('0')) {
      _hrdPhone = '62${_hrdPhone.substring(1)}';
    }
    notifyListeners();
  }

  void _subscribeAttendance() {
    _attendanceSub?.cancel();
    if (_selectedMonthYear.isEmpty) return;

    _attendanceSub = _firebaseService
        .streamAttendanceByMonthYear(_selectedMonthYear)
        .listen((list) {
      _attendanceList = list;
      notifyListeners();
    });
  }

  // Master Staff CRUD
  Future<void> saveStaff(Staff staff) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseService.saveStaff(staff);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteStaff(String staffId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseService.deleteStaff(staffId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Attendance CRUD
  Future<void> saveAttendanceRecord(AttendanceRecord record) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseService.saveAttendanceRecord(record);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteAttendanceRecord(String id) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _firebaseService.deleteAttendanceRecord(id);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Import CSV / Excel File Importer
  Future<int> importAttendanceFromFile(List<int> bytes, String fileName) async {
    _isLoading = true;
    notifyListeners();

    int importedCount = 0;
    try {
      if (fileName.endsWith('.csv')) {
        importedCount = await _importCsv(bytes);
      } else {
        importedCount = await _importExcel(bytes);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return importedCount;
  }

  Future<int> _importCsv(List<int> bytes) async {
    final content = String.fromCharCodes(bytes);
    final lines = content.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isEmpty) return 0;

    int count = 0;
    // Find header index
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('nama') && line.contains('tempat')) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex == -1) headerIndex = 0;

    for (int i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = line.split(RegExp(r',|;|\t'));
      if (cols.length < 2) continue;

      final name = cols[0].trim();
      if (name.isEmpty || name.toLowerCase().contains('rekap absensi')) continue;

      final location = cols.length > 1 ? cols[1].trim() : '-';
      final hk = cols.length > 2 ? (_parseDouble(cols[2])) : 0.0;
      final off = cols.length > 3 ? (_parseDouble(cols[3])) : 0.0;
      final sakit = cols.length > 4 ? (_parseDouble(cols[4])) : 0.0;
      final ijin = cols.length > 5 ? (_parseDouble(cols[5])) : 0.0;
      final estimasi = cols.length > 6 ? (_parseDouble(cols[6])) : 0.0;
      final totalHk = cols.length > 7 ? (_parseDouble(cols[7])) : (hk + estimasi);

      await _processImportedRow(name, location, hk, off, sakit, ijin, estimasi, totalHk);
      count++;
    }
    return count;
  }

  Future<int> _importExcel(List<int> bytes) async {
    final excel = Excel.decodeBytes(bytes);
    int count = 0;

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;

      int headerRowIndex = -1;
      for (int i = 0; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        final rowStr = row.map((c) => c?.value?.toString().toLowerCase() ?? '').join(' ');
        if (rowStr.contains('nama') && rowStr.contains('tempat')) {
          headerRowIndex = i;
          break;
        }
      }

      if (headerRowIndex == -1) headerRowIndex = 0;

      for (int i = headerRowIndex + 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        final name = row[0]?.value?.toString().trim() ?? '';
        if (name.isEmpty || name.toLowerCase().contains('rekap absensi')) continue;

        final location = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '-') : '-';
        final hk = row.length > 2 ? _parseExcelVal(row[2]?.value) : 0.0;
        final off = row.length > 3 ? _parseExcelVal(row[3]?.value) : 0.0;
        final sakit = row.length > 4 ? _parseExcelVal(row[4]?.value) : 0.0;
        final ijin = row.length > 5 ? _parseExcelVal(row[5]?.value) : 0.0;
        final estimasi = row.length > 6 ? _parseExcelVal(row[6]?.value) : 0.0;
        final totalHk = row.length > 7 ? _parseExcelVal(row[7]?.value) : (hk + estimasi);

        await _processImportedRow(name, location, hk, off, sakit, ijin, estimasi, totalHk);
        count++;
      }
    }
    return count;
  }

  Future<void> _processImportedRow(
    String name,
    String location,
    double hk,
    double off,
    double sakit,
    double ijin,
    double estimasi,
    double totalHk,
  ) async {
    // Find or create Staff
    Staff? staff = _staffList.firstWhere(
      (s) => s.name.trim().toLowerCase() == name.trim().toLowerCase(),
      orElse: () => Staff(id: '', name: '', location: '', createdAt: DateTime.now()),
    );

    String staffId = staff.id;
    if (staffId.isEmpty) {
      staffId = DateTime.now().millisecondsSinceEpoch.toString();
      staff = Staff(
        id: staffId,
        name: name,
        location: location,
        createdAt: DateTime.now(),
      );
      await _firebaseService.saveStaff(staff);
    }

    final recordId = '${_selectedMonthYear}_$staffId';
    final rec = AttendanceRecord(
      id: recordId,
      monthYear: _selectedMonthYear,
      staffId: staffId,
      staffName: name,
      location: location,
      hk: hk,
      off: off,
      sakit: sakit,
      ijin: ijin,
      estimasi: estimasi,
      totalHk: totalHk > 0 ? totalHk : (hk + estimasi),
      updatedAt: DateTime.now(),
    );

    await _firebaseService.saveAttendanceRecord(rec);
  }

  double _parseDouble(String val) {
    final sanitized = val.replaceAll('-', '0').trim();
    return double.tryParse(sanitized) ?? 0.0;
  }

  double _parseExcelVal(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return _parseDouble(val.toString());
  }

  @override
  void dispose() {
    _staffSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }
}
