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
        return '20 $monthName $y';
      }
    } catch (_) {}
    return monthYearStr;
  }

  Future<String?> _showMonthYearPicker(BuildContext context, String currentMonthYear) async {
    final now = DateTime.now();
    int tempYear = now.year;
    int tempMonth = now.month;

    if (currentMonthYear.isNotEmpty && currentMonthYear.contains("-")) {
      final parts = currentMonthYear.split("-");
      tempMonth = int.tryParse(parts[0]) ?? now.month;
      tempYear = int.tryParse(parts[1]) ?? now.year;
    }

    final months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setPickerState(() {
                        tempYear--;
                      });
                    },
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$tempYear',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () {
                      setPickerState(() {
                        tempYear++;
                      });
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, idx) {
                    final mIndex = idx + 1;
                    final mString = mIndex.toString().padLeft(2, '0');
                    final val = '$mString-$tempYear';
                    final isSelected = currentMonthYear == val;
                    final isCurrent = mIndex == now.month && tempYear == now.year;

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx, val);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0284C7)
                              : (isCurrent ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF38BDF8)
                                : (isCurrent ? const Color(0xFF38BDF8).withOpacity(0.6) : const Color(0xFF334155)),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          months[idx],
                          style: TextStyle(
                            color: isSelected ? Colors.white : (isCurrent ? const Color(0xFF38BDF8) : Colors.white70),
                            fontWeight: isSelected || isCurrent ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            );
          },
        );
      },
    );
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
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Controls Bar
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment_ind_rounded, color: Color(0xFF38BDF8), size: 24),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Rekap Absensi Pegawai',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cabang Jawa Tengah (Awal Bulan s.d. Tanggal 20)',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await _showMonthYearPicker(context, attProvider.selectedMonthYear);
                                if (picked != null) {
                                  attProvider.setMonthYear(picked);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatMonthYearTitle(attProvider.selectedMonthYear),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8), size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF0284C7)),
                            ),
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 22),
                              tooltip: 'Menu Fitur Absensi Pegawai',
                              color: const Color(0xFF0F172A),
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                              ),
                              onSelected: (val) {
                                if (val == 'staff') {
                                  _showManageStaffDialog(context, attProvider);
                                } else if (val == 'input') {
                                  _showInputAttendanceDialog(context, attProvider, null);
                                } else if (val == 'import') {
                                  _handleImportCsvExcel(context, attProvider);
                                } else if (val == 'send') {
                                  _showSendWaPdfDialog(context, attProvider, filteredRecords, titleMonthYearName);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'staff',
                                  child: Row(
                                    children: [
                                      Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8), size: 20),
                                      SizedBox(width: 12),
                                      Text('Kelola Master Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'input',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add_task_rounded, color: Colors.tealAccent, size: 20),
                                      SizedBox(width: 12),
                                      Text('Input Absensi Pegawai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 1),
                                const PopupMenuItem(
                                  value: 'import',
                                  child: Row(
                                    children: [
                                      Icon(Icons.file_upload_rounded, color: Color(0xFF38BDF8), size: 20),
                                      SizedBox(width: 12),
                                      Text('Import CSV / Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'send',
                                  child: Row(
                                    children: [
                                      Icon(Icons.send_rounded, color: Color(0xFF4ADE80), size: 20),
                                      SizedBox(width: 12),
                                      Text('Kirim Laporan WA / PDF', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
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
                      InkWell(
                        onTap: () async {
                          final picked = await _showMonthYearPicker(context, attProvider.selectedMonthYear);
                          if (picked != null) {
                            attProvider.setMonthYear(picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _formatMonthYearTitle(attProvider.selectedMonthYear),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8), size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF0284C7)),
                        ),
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 24),
                          tooltip: 'Menu Fitur Absensi Pegawai',
                          color: const Color(0xFF0F172A),
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                          ),
                          onSelected: (val) {
                            if (val == 'staff') {
                              _showManageStaffDialog(context, attProvider);
                            } else if (val == 'input') {
                              _showInputAttendanceDialog(context, attProvider, null);
                            } else if (val == 'import') {
                              _handleImportCsvExcel(context, attProvider);
                            } else if (val == 'send') {
                              _showSendWaPdfDialog(context, attProvider, filteredRecords, titleMonthYearName);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'staff',
                              child: Row(
                                children: [
                                  Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 12),
                                  Text('Kelola Master Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'input',
                              child: Row(
                                children: [
                                  Icon(Icons.add_task_rounded, color: Colors.tealAccent, size: 20),
                                  SizedBox(width: 12),
                                  Text('Input Absensi Pegawai', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            const PopupMenuItem(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.file_upload_rounded, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 12),
                                  Text('Import CSV / Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'send',
                              child: Row(
                                children: [
                                  Icon(Icons.send_rounded, color: Color(0xFF4ADE80), size: 20),
                                  SizedBox(width: 12),
                                  Text('Kirim Laporan WA / PDF', style: TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 18),

            // Summary Metric Cards Row
            isMobile
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(width: 170, child: _buildMetricCardContent('Total Pegawai', '$totalStaff Orang', Icons.people_outline_rounded, const Color(0xFF38BDF8))),
                        const SizedBox(width: 10),
                        SizedBox(width: 170, child: _buildMetricCardContent('Total HK (1-20)', _formatNum(totalHk), Icons.calendar_month_rounded, Colors.greenAccent)),
                        const SizedBox(width: 10),
                        SizedBox(width: 220, child: _buildMetricCardContent('Off / Sakit / Ijin', '${_formatNum(totalOff)} / ${_formatNum(totalSakit)} / ${_formatNum(totalIjin)}', Icons.event_busy_rounded, Colors.amberAccent)),
                        const SizedBox(width: 10),
                        SizedBox(width: 200, child: _buildMetricCardContent('Total Estimasi', _formatNum(totalEstimasi), Icons.published_with_changes_rounded, Colors.orangeAccent)),
                        const SizedBox(width: 10),
                        SizedBox(width: 170, child: _buildMetricCardContent('Grand Total HK', _formatNum(grandTotalHk), Icons.verified_rounded, const Color(0xFF38BDF8))),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(child: _buildMetricCardContent('Total Pegawai', '$totalStaff Orang', Icons.people_outline_rounded, const Color(0xFF38BDF8))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricCardContent('Total HK (1-20)', _formatNum(totalHk), Icons.calendar_month_rounded, Colors.greenAccent)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricCardContent('Total Off / Sakit / Ijin', '${_formatNum(totalOff)} / ${_formatNum(totalSakit)} / ${_formatNum(totalIjin)}', Icons.event_busy_rounded, Colors.amberAccent)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricCardContent('Total Estimasi (21-Akhir)', _formatNum(totalEstimasi), Icons.published_with_changes_rounded, Colors.orangeAccent)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricCardContent('Grand Total HK', _formatNum(grandTotalHk), Icons.verified_rounded, const Color(0xFF38BDF8))),
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
                        'Rekap Absensi Pegawai Cabang Jawa Tengah Awal Bulan sampai tanggal $titleMonthYearName',
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
                                              PopupMenuButton<String>(
                                                icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                                                color: const Color(0xFF1E293B),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                onSelected: (value) {
                                                  if (value == 'edit') {
                                                    _showInputAttendanceDialog(context, attProvider, rec);
                                                  } else if (value == 'delete') {
                                                    _confirmDeleteAttendance(context, attProvider, rec);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: const [
                                                        Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Edit Absensi', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: const [
                                                        Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Hapus Record', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                                      ],
                                                    ),
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

  Widget _buildMetricCardContent(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Dialog Master Staff CRUD
  void _showManageStaffDialog(BuildContext context, AttendanceProvider attProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer<AttendanceProvider>(
          builder: (context, provider, child) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.badge_rounded, color: Color(0xFF38BDF8)),
                  SizedBox(width: 10),
                  Text('Kelola Master Pegawai (Staff)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 450,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddEditStaffForm(context, provider, null),
                        icon: const Icon(Icons.person_add_rounded, size: 16, color: Colors.white),
                        label: const Text('Tambah Pegawai Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: provider.staffList.isEmpty
                          ? const Center(
                              child: Text('Belum ada pegawai terdaftar.', style: TextStyle(color: Color(0xFF64748B))),
                            )
                          : ListView.separated(
                              itemCount: provider.staffList.length,
                              separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                              itemBuilder: (context, idx) {
                                final staff = provider.staffList[idx];
                                return ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF0F172A),
                                    child: Icon(Icons.person_rounded, color: Color(0xFF38BDF8), size: 20),
                                  ),
                                  title: Text(staff.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  subtitle: Text(staff.location, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                                    tooltip: 'Pilihan Aksi Staff',
                                    color: const Color(0xFF0F172A),
                                    elevation: 8,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: const BorderSide(color: Color(0xFF334155)),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showAddEditStaffForm(context, provider, staff);
                                      } else if (value == 'delete') {
                                        _confirmDeleteStaff(context, provider, staff);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 18),
                                            SizedBox(width: 10),
                                            Text('Edit Data Staff', style: TextStyle(color: Colors.white, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                            SizedBox(width: 10),
                                            Text('Hapus Staff', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                          ],
                                        ),
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
                  child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteStaff(BuildContext context, AttendanceProvider attProvider, Staff staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Hapus Pegawai?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${staff.name}" (${staff.location}) dari Master Pegawai?',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await attProvider.deleteStaff(staff.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Staff "${staff.name}" telah dihapus.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddEditStaffForm(BuildContext context, AttendanceProvider attProvider, Staff? existingStaff) {
    final nameCtrl = TextEditingController(text: existingStaff?.name ?? '');
    final locationCtrl = TextEditingController(text: existingStaff?.location ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            existingStaff == null ? 'Tambah Pegawai Baru' : 'Edit Data Pegawai',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nama Pegawai',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: locationCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Tempat / Cabang (Contoh: Solo-Jateng)',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final nameStr = nameCtrl.text.trim();
                final locStr = locationCtrl.text.trim();
                if (nameStr.isEmpty) return;

                final staff = Staff(
                  id: existingStaff?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameStr,
                  location: locStr.isEmpty ? 'Jawa Tengah' : locStr,
                  createdAt: existingStaff?.createdAt ?? DateTime.now(),
                );

                Navigator.pop(ctx);
                await attProvider.saveStaff(staff);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF10B981),
                      content: Text(existingStaff == null ? 'Berhasil menambah pegawai "$nameStr"!' : 'Berhasil memperbarui data pegawai "$nameStr"!'),
                    ),
                  );
                }
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nomor WhatsApp HRD (Tersimpan Otomatis):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneCtrl,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: 'Contoh: 081234567890 / 6281234567890',
                          hintStyle: const TextStyle(color: Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.phone_android_rounded, color: Colors.greenAccent),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                        onChanged: (val) {
                          if (val.trim().isNotEmpty) {
                            attProvider.setHrdPhone(val.trim());
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (phoneCtrl.text.trim().isNotEmpty) {
                          attProvider.setHrdPhone(phoneCtrl.text.trim());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nomor WA HRD berhasil disimpan!'), backgroundColor: Colors.teal),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                      label: const Text('Simpan', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.greenAccent, size: 18),
                          SizedBox(width: 8),
                          Text('Petunjuk Pengiriman Lampiran PDF:', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1. Klik "Buka WA & Kirim", file PDF Rekap Absensi akan otomatis di-download ke laptop/HP Anda.\n'
                        '2. Setelah WhatsApp Web terbuka di chat Bu Lia, klik icon Lampiran (📎 Klip) dan pilih file PDF yang baru di-download tadi.',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11, height: 1.4),
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
              label: const Text('Buka WA & Kirim', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () async {
                final inputPhone = phoneCtrl.text.trim();
                if (inputPhone.isNotEmpty) {
                  attProvider.setHrdPhone(inputPhone);
                }

                // Download PDF automatically
                final pdfBytes = await AttendancePdfService.generateAttendancePdf(
                  monthYearName: titleMonthYearName,
                  records: records,
                );
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: 'Rekap_Absensi_Jateng_${attProvider.selectedMonthYear}.pdf',
                );

                // Open WhatsApp Link
                final targetPhone = attProvider.hrdPhone.isNotEmpty ? attProvider.hrdPhone : inputPhone;
                final message = Uri.encodeComponent(
                  "Permisi Bu Lia (HRD),\n\nBerikut Rekap Absensi Pegawai Cabang Jawa Tengah Awal Bulan sampai Tanggal $titleMonthYearName.\nFile PDF Rekap Absensi telah di-download & siap dilampirkan.\n\nTerima Kasih.\n(Lucifax PFS)",
                );
                final waUrl = Uri.parse("https://wa.me/$targetPhone?text=$message");
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
