import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import '../models/staff.dart';
import '../models/attendance_record.dart';
import '../providers/attendance_provider.dart';
import '../services/attendance_pdf_service.dart';

class AttendanceView extends StatefulWidget {
  const AttendanceView({super.key});

  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Generate Month-Year Options from 04-2025 up to 12-2030
  List<String> _getMonthYearOptions(AttendanceProvider attProvider) {
    final Set<String> optionsSet = {};

    // Range from 2030 down to April 2025
    for (int year = 2030; year >= 2025; year--) {
      final startMonth = (year == 2025) ? 4 : 1;
      const endMonth = 12;
      for (int month = endMonth; month >= startMonth; month--) {
        optionsSet.add('${month.toString().padLeft(2, '0')}-$year');
      }
    }

    if (attProvider.selectedMonthYear.isNotEmpty) {
      optionsSet.add(attProvider.selectedMonthYear);
    }
    for (var rec in attProvider.attendanceList) {
      if (rec.monthYear.isNotEmpty) {
        optionsSet.add(rec.monthYear);
      }
    }

    final list = optionsSet.toList();
    list.sort((a, b) {
      final pA = a.split('-');
      final pB = b.split('-');
      if (pA.length == 2 && pB.length == 2) {
        final yA = int.tryParse(pA[1]) ?? 0;
        final yB = int.tryParse(pB[1]) ?? 0;
        if (yA != yB) return yB.compareTo(yA);
        final mA = int.tryParse(pA[0]) ?? 0;
        final mB = int.tryParse(pB[0]) ?? 0;
        return mB.compareTo(mA);
      }
      return b.compareTo(a);
    });

    return list;
  }

  String _formatMonthYearTitle(String monthYearStr) {
    if (monthYearStr.isEmpty) return '';
    try {
      final parts = monthYearStr.split('-');
      if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final y = int.parse(parts[1]);
        final dt = DateTime(y, m, 1);
        final monthName = DateFormat('MMMM', 'id_ID').format(dt);
        return '$monthName Tahun $y';
      }
    } catch (_) {}
    return monthYearStr;
  }

  @override
  Widget build(BuildContext context) {
    final attProvider = Provider.of<AttendanceProvider>(context);
    final monthOptions = _getMonthYearOptions(attProvider);

    // Ensure selected monthYear is valid
    if (!monthOptions.contains(attProvider.selectedMonthYear) && monthOptions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        attProvider.setMonthYear(monthOptions.first);
      });
    }

    final filteredRecords = attProvider.attendanceList.where((rec) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return rec.staffName.toLowerCase().contains(q) || rec.location.toLowerCase().contains(q);
    }).toList();

    // Calculate Summary Metrics
    final totalStaff = filteredRecords.length;
    final totalHk = filteredRecords.fold(0.0, (sum, r) => sum + r.hk);
    final totalOff = filteredRecords.fold(0.0, (sum, r) => sum + r.off);
    final totalSakit = filteredRecords.fold(0.0, (sum, r) => sum + r.sakit);
    final totalIjin = filteredRecords.fold(0.0, (sum, r) => sum + r.ijin);
    final totalEstimasi = filteredRecords.fold(0.0, (sum, r) => sum + r.estimasi);
    final grandTotalHk = filteredRecords.fold(0.0, (sum, r) => sum + r.totalHk);

    final titleMonthYearName = _formatMonthYearTitle(attProvider.selectedMonthYear);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Controls Bar
            Row(
              children: [
                const Icon(Icons.assignment_ind_rounded, color: Color(0xFF38BDF8), size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rekap Absensi Pegawai',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Cabang Jawa Tengah (Awal Bulan s.d. Tanggal 20)',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),

                // Month Picker Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: monthOptions.contains(attProvider.selectedMonthYear)
                          ? attProvider.selectedMonthYear
                          : (monthOptions.isNotEmpty ? monthOptions.first : null),
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      items: monthOptions.map((my) {
                        return DropdownMenuItem<String>(
                          value: my,
                          child: Text(_formatMonthYearTitle(my)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          attProvider.setMonthYear(val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Button Kelola Staff
                ElevatedButton.icon(
                  onPressed: () => _showManageStaffDialog(context, attProvider),
                  icon: const Icon(Icons.people_alt_rounded, size: 18, color: Colors.white),
                  label: const Text('Kelola Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 10),

                // Button Input Absensi
                ElevatedButton.icon(
                  onPressed: () => _showInputAttendanceDialog(context, attProvider, null),
                  icon: const Icon(Icons.add_task_rounded, size: 18, color: Colors.white),
                  label: const Text('Input Absensi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 10),

                // Button Import CSV/Excel
                ElevatedButton.icon(
                  onPressed: () => _handleImportCsvExcel(context, attProvider),
                  icon: const Icon(Icons.file_upload_rounded, size: 18, color: Colors.white),
                  label: const Text('Import CSV/Excel', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF334155),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 10),

                // Button Kirim WA / PDF
                ElevatedButton.icon(
                  onPressed: () => _showSendWaPdfDialog(context, attProvider, filteredRecords, titleMonthYearName),
                  icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  label: const Text('Kirim WA / PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Summary Metric Cards Row
            Row(
              children: [
                _buildMetricCard('Total Pegawai', '$totalStaff Orang', Icons.people_outline_rounded, const Color(0xFF38BDF8)),
                const SizedBox(width: 12),
                _buildMetricCard('Total HK (1-20)', _formatNum(totalHk), Icons.calendar_month_rounded, Colors.greenAccent),
                const SizedBox(width: 12),
                _buildMetricCard('Total Off / Sakit / Ijin', '${_formatNum(totalOff)} / ${_formatNum(totalSakit)} / ${_formatNum(totalIjin)}', Icons.event_busy_rounded, Colors.amberAccent),
                const SizedBox(width: 12),
                _buildMetricCard('Total Estimasi (21-Akhir)', _formatNum(totalEstimasi), Icons.published_with_changes_rounded, Colors.orangeAccent),
                const SizedBox(width: 12),
                _buildMetricCard('Grand Total HK', _formatNum(grandTotalHk), Icons.verified_rounded, const Color(0xFF38BDF8)),
              ],
            ),
            const SizedBox(height: 18),

            // Search Bar
            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cari berdasarkan Nama Pegawai atau Tempat/Cabang...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
            const SizedBox(height: 16),

            // Rekap Table Card
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Column(
                  children: [
                    // Banner Title Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Rekap Absensi Pegawai Cabang Jawa Tengah Awal Bulan sampai tanggal 20 $titleMonthYearName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    // Table Body
                    Expanded(
                      child: attProvider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filteredRecords.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Belum ada data absensi pegawai untuk bulan ini.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      columnSpacing: 35,
                                      horizontalMargin: 20,
                                      headingRowColor: MaterialStateProperty.all(const Color(0xFF1E293B)),
                                      dataRowMinHeight: 52,
                                      dataRowMaxHeight: 52,
                                      headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 13),
                                      columns: const [
                                        DataColumn(label: Text('Nama')),
                                        DataColumn(label: Text('Tempat')),
                                        DataColumn(label: Center(child: Text('HK'))),
                                        DataColumn(label: Center(child: Text('Off'))),
                                        DataColumn(label: Center(child: Text('Sakit'))),
                                        DataColumn(label: Center(child: Text('Ijin'))),
                                        DataColumn(label: Center(child: Text('Estimasi'))),
                                        DataColumn(label: Center(child: Text('Total HK'))),
                                        DataColumn(label: Center(child: Text('Aksi'))),
                                      ],
                                      rows: filteredRecords.map((rec) {
                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(
                                                rec.staffName,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                rec.location,
                                                style: const TextStyle(color: Color(0xFF94A3B8)),
                                              ),
                                            ),
                                            DataCell(Center(child: Text(_formatNum(rec.hk), style: const TextStyle(color: Colors.white)))),
                                            DataCell(Center(child: Text(_formatNum(rec.off), style: TextStyle(color: rec.off > 0 ? Colors.amberAccent : const Color(0xFF64748B))))),
                                            DataCell(Center(child: Text(_formatNum(rec.sakit), style: TextStyle(color: rec.sakit > 0 ? Colors.redAccent : const Color(0xFF64748B))))),
                                            DataCell(Center(child: Text(_formatNum(rec.ijin), style: TextStyle(color: rec.ijin > 0 ? Colors.orangeAccent : const Color(0xFF64748B))))),
                                            DataCell(Center(child: Text(_formatNum(rec.estimasi), style: const TextStyle(color: Colors.tealAccent)))),
                                            DataCell(
                                              Center(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0284C7).withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                                                  ),
                                                  child: Text(
                                                    _formatNum(rec.totalHk),
                                                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 18),
                                                    tooltip: 'Edit Absensi',
                                                    onPressed: () => _showInputAttendanceDialog(context, attProvider, rec),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                    tooltip: 'Hapus Record',
                                                    onPressed: () => _confirmDeleteAttendance(context, attProvider, rec),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNum(double val) {
    if (val == 0) return '-';
    if (val == val.roundToDouble()) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Dialog Master Staff CRUD
  void _showManageStaffDialog(BuildContext context, AttendanceProvider attProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Kelola Master Pegawai (Staff)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 600,
            height: 450,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddEditStaffForm(context, attProvider, null),
                    icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                    label: const Text('Tambah Pegawai', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: attProvider.staffList.isEmpty
                      ? const Center(child: Text('Belum ada pegawai terdaftar.', style: TextStyle(color: Color(0xFF64748B))))
                      : ListView.separated(
                          itemCount: attProvider.staffList.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (context, idx) {
                            final staff = attProvider.staffList[idx];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFF0F172A),
                                child: Icon(Icons.person_rounded, color: Color(0xFF38BDF8), size: 20),
                              ),
                              title: Text(staff.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text(staff.location, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 20),
                                    onPressed: () => _showAddEditStaffForm(context, attProvider, staff),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                    onPressed: () async {
                                      await attProvider.deleteStaff(staff.id);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        );
      },
    );
  }

  void _showAddEditStaffForm(BuildContext context, AttendanceProvider attProvider, Staff? existingStaff) {
    final nameCtrl = TextEditingController(text: existingStaff?.name ?? '');
    final locationCtrl = TextEditingController(text: existingStaff?.location ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(existingStaff == null ? 'Tambah Pegawai Baru' : 'Edit Pegawai', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Nama Pegawai', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: locationCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Tempat / Cabang (Contoh: Solo-Jateng)', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final staff = Staff(
                  id: existingStaff?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text.trim(),
                  location: locationCtrl.text.trim(),
                  createdAt: existingStaff?.createdAt ?? DateTime.now(),
                );
                await attProvider.saveStaff(staff);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  // Dialog Input / Edit Absensi
  void _showInputAttendanceDialog(BuildContext context, AttendanceProvider attProvider, AttendanceRecord? existingRecord) {
    Staff? selectedStaff;
    if (existingRecord != null) {
      selectedStaff = attProvider.staffList.firstWhere(
        (s) => s.id == existingRecord.staffId,
        orElse: () => Staff(id: existingRecord.staffId, name: existingRecord.staffName, location: existingRecord.location, createdAt: DateTime.now()),
      );
    }

    final hkCtrl = TextEditingController(text: existingRecord != null ? _formatNum(existingRecord.hk) : '0');
    final offCtrl = TextEditingController(text: existingRecord != null ? _formatNum(existingRecord.off) : '0');
    final sakitCtrl = TextEditingController(text: existingRecord != null ? _formatNum(existingRecord.sakit) : '0');
    final ijinCtrl = TextEditingController(text: existingRecord != null ? _formatNum(existingRecord.ijin) : '0');
    final estimasiCtrl = TextEditingController(text: existingRecord != null ? _formatNum(existingRecord.estimasi) : '0');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double hkVal = double.tryParse(hkCtrl.text) ?? 0.0;
            double estVal = double.tryParse(estimasiCtrl.text) ?? 0.0;
            double totalHkCalc = hkVal + estVal;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                existingRecord == null ? 'Input Absensi (${attProvider.selectedMonthYear})' : 'Edit Absensi (${existingRecord.staffName})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Select Staff Dropdown
                      if (existingRecord == null) ...[
                        const Text('Pilih Pegawai:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<Staff>(
                          value: selectedStaff,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: attProvider.staffList.map((s) {
                            return DropdownMenuItem<Staff>(
                              value: s,
                              child: Text('${s.name} (${s.location})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedStaff = val;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Number Inputs
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: hkCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'HK (Tgl 1-20)', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: estimasiCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'Estimasi (Tgl 21-Akhir)', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: offCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'Off', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: sakitCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'Sakit', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: ijinCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(labelText: 'Ijin', labelStyle: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Calculated Total HK:', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                            Text(
                              _formatNum(totalHkCalc),
                              style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[700]),
                  onPressed: selectedStaff == null && existingRecord == null
                      ? null
                      : () async {
                          final sId = existingRecord?.staffId ?? selectedStaff!.id;
                          final sName = existingRecord?.staffName ?? selectedStaff!.name;
                          final sLoc = existingRecord?.location ?? selectedStaff!.location;

                          final rec = AttendanceRecord(
                            id: existingRecord?.id ?? '${attProvider.selectedMonthYear}_$sId',
                            monthYear: attProvider.selectedMonthYear,
                            staffId: sId,
                            staffName: sName,
                            location: sLoc,
                            hk: double.tryParse(hkCtrl.text) ?? 0.0,
                            off: double.tryParse(offCtrl.text) ?? 0.0,
                            sakit: double.tryParse(sakitCtrl.text) ?? 0.0,
                            ijin: double.tryParse(ijinCtrl.text) ?? 0.0,
                            estimasi: double.tryParse(estimasiCtrl.text) ?? 0.0,
                            totalHk: totalHkCalc,
                            updatedAt: DateTime.now(),
                          );

                          await attProvider.saveAttendanceRecord(rec);
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('Simpan Record'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Import CSV / Excel File Handler (Supports Multi-File Import with Auto-Detected Month & Year)
  Future<void> _handleImportCsvExcel(BuildContext context, AttendanceProvider attProvider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
      );

      int totalImportedRecords = 0;
      int processedFiles = 0;

      for (var file in result.files) {
        final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
        if (bytes != null) {
          final count = await attProvider.importAttendanceFromFile(bytes, file.name.toLowerCase());
          totalImportedRecords += count;
          processedFiles++;
        }
      }

      if (context.mounted) {
        Navigator.pop(context); // close spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil mengimpor $processedFiles file ($totalImportedRecords data absensi)! Bulan & Tahun terdeteksi otomatis.'),
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close spinner if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // Dialog Kirim PDF Ke WhatsApp HRD
  void _showSendWaPdfDialog(
    BuildContext context,
    AttendanceProvider attProvider,
    List<AttendanceRecord> records,
    String titleMonthYearName,
  ) {
    final phoneCtrl = TextEditingController(text: attProvider.hrdPhone);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.send_rounded, color: Colors.greenAccent),
              SizedBox(width: 8),
              Text('Cetak PDF & Kirim WA HRD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Masukkan Nomor WhatsApp HRD (misal: Bu Lia):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Contoh: 081234567890 / 6281234567890',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    prefixIcon: const Icon(Icons.phone_android_rounded, color: Colors.greenAccent),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.greenAccent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sistem akan otomatis mendownload PDF Rekap Absensi dan membuka WhatsApp dengan format pesan pengantar.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
              label: const Text('Download PDF', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () async {
                final pdfBytes = await AttendancePdfService.generateAttendancePdf(
                  monthYearName: titleMonthYearName,
                  records: records,
                );
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'Rekap_Absensi_Jateng_${attProvider.selectedMonthYear}.pdf',
                );
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: const Text('Buka WA & Kirim', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () async {
                final inputPhone = phoneCtrl.text.trim();
                if (inputPhone.isNotEmpty) {
                  attProvider.setHrdPhone(inputPhone);
                }

                // Download PDF
                final pdfBytes = await AttendancePdfService.generateAttendancePdf(
                  monthYearName: titleMonthYearName,
                  records: records,
                );
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'Rekap_Absensi_Jateng_${attProvider.selectedMonthYear}.pdf',
                );

                // Open WhatsApp Link
                final message = Uri.encodeComponent(
                  "Halo Bu Lia (HRD),\n\nBerikut Rekap Absensi Pegawai Cabang Jawa Tengah Awal Bulan sampai Tanggal 20 $titleMonthYearName.\nFile PDF Rekap Absensi telah di-download & siap dilampirkan.\n\nTerima Kasih.\n(Lucifax PFS)",
                );
                final waUrl = Uri.parse("https://wa.me/${attProvider.hrdPhone}?text=$message");
                if (await canLaunchUrl(waUrl)) {
                  await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                }

                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAttendance(BuildContext context, AttendanceProvider attProvider, AttendanceRecord rec) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Hapus Absensi', style: TextStyle(color: Colors.white)),
        content: Text('Apakah Anda yakin ingin menghapus data absensi ${rec.staffName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await attProvider.deleteAttendanceRecord(rec.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}
