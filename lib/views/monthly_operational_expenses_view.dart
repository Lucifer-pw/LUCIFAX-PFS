import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class MonthlyOperationalExpensesView extends StatefulWidget {
  const MonthlyOperationalExpensesView({super.key});

  @override
  State<MonthlyOperationalExpensesView> createState() => _MonthlyOperationalExpensesViewState();
}

class _MonthlyOperationalExpensesViewState extends State<MonthlyOperationalExpensesView> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 2,
  );
  final NumberFormat _amountFormat = NumberFormat('#,##0.00', 'id_ID');

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Local state for items
  List<Map<String, dynamic>> _operationalItems = [];
  List<Map<String, dynamic>> _ofCountryItems = [];

  List<Map<String, dynamic>> get _filteredOperationalItems {
    if (_searchQuery.isEmpty) return _operationalItems;
    return _operationalItems.where((item) {
      final title = item['title'].toString().toLowerCase();
      return title.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredOfCountryItems {
    if (_searchQuery.isEmpty) return _ofCountryItems;
    return _ofCountryItems.where((item) {
      final title = item['title'].toString().toLowerCase();
      return title.contains(_searchQuery);
    }).toList();
  }

  final List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _loadExpenseData();
  }

  String get _periodDocId => '${_selectedYear}_$_selectedMonth';
  String get _monthYearTitle => '${_monthNames[_selectedMonth - 1].toUpperCase()} $_selectedYear';

  Future<DateTime?> _showMonthYearPicker(BuildContext context, int currentMonth, int currentYear) async {
    int tempYear = currentYear;

    return showDialog<DateTime>(
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
                    final isSelected = currentMonth == mIndex && currentYear == tempYear;
                    final isCurrent = mIndex == DateTime.now().month && tempYear == DateTime.now().year;

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx, DateTime(tempYear, mIndex, 1));
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
                          _monthNames[idx],
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

  /// Initial default data matching the user's template for July 2026
  List<Map<String, dynamic>> get _defaultOperationalItems => [
    {'title': 'Biaya Listrik', 'amount': 1230881.0},
    {'title': 'BBM Luarkota Magelang,Semarang dan Tarif Tol', 'amount': 349000.0},
    {'title': 'BBM Luarkota Blora', 'amount': 186690.0},
    {'title': 'Biaya Perbaikan Mobil Suzuki Carry "B 9136 KCI"', 'amount': 2977500.0},
    {'title': 'Biaya Pindah Ban Belakang mobil Grandmax "B 1153 KRP" (dibalik)', 'amount': 50000.0},
    {'title': 'Biaya Pengiriman dokumen', 'amount': 25000.0},
    {'title': 'BBM Luarkota Wonosobo dan Yogyakarta', 'amount': 283350.0},
    {'title': 'BBM Luarkota Boyolali dan Pekalongan dan Tarif Tol', 'amount': 264000.0},
    {'title': 'BBM Luarkota Klaten dan Sragen', 'amount': 200000.0},
    {'title': 'BBM Luarkota Wonosobo Semarang Pekalongan dan Tarif Tol', 'amount': 919500.0},
    {'title': 'BBM Luarkota Yogyakarta', 'amount': 100000.0},
    {'title': 'BBM Luarkota Batang Kendal Pekalongan Comal dan Tarif Tol', 'amount': 285470.0},
    {'title': 'Biaya Pembelian bahan baku sampling gimmick untuk hadiah dalam rangka HUT "Hana Makmur Purbalingga"', 'amount': 490000.0},
    {'title': 'Biaya Operasional SMD Purbalingga Kirim ke Banjarnegara', 'amount': 370000.0},
    {'title': 'Biaya Operasional Sistem,upgrade server dan Maintenance', 'amount': 200000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen LG FF ( 167 karton)', 'amount': 50000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen KK FF ( 40 karton)', 'amount': 12000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen MMM FF ( 30 karton)', 'amount': 4000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen AFM FF ( 136 karton)', 'amount': 40000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen AW FF ( 167 karton)', 'amount': 50000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen Mister Sosis ( 36 karton)', 'amount': 11000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen SJJ ( 58 karton)', 'amount': 18000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen GRIYA FF ( 30 karton)', 'amount': 9000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen PARIS FF ( 135 karton)', 'amount': 10000.0},
    {'title': 'Biaya Bongkar Barang Pengiriman di Agen WAYAHE FF ( 10 karton)', 'amount': 5000.0},
  ];

  List<Map<String, dynamic>> get _defaultOfCountryItems => [
    {'title': 'Magelang,Semarang', 'amount': 100000.0},
    {'title': 'Blora', 'amount': 100000.0},
    {'title': 'Wonosobo Yogyakarta', 'amount': 100000.0},
    {'title': 'Pekalongan Boyolali', 'amount': 100000.0},
    {'title': 'Wonosobo,Pekalongan,Semarang', 'amount': 100000.0},
  ];

  Future<void> _loadExpenseData() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _db.collection('monthly_operational_expenses').doc(_periodDocId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final ops = List<Map<String, dynamic>>.from(data['operationalItems'] ?? []);
        final ofc = List<Map<String, dynamic>>.from(data['ofCountryItems'] ?? []);
        setState(() {
          _operationalItems = ops;
          _ofCountryItems = ofc;
        });
      } else {
        if (_selectedYear == 2026 && _selectedMonth == 7) {
          setState(() {
            _operationalItems = List.from(_defaultOperationalItems);
            _ofCountryItems = List.from(_defaultOfCountryItems);
          });
          await _saveExpenseDataSilently();
        } else {
          setState(() {
            _operationalItems = [];
            _ofCountryItems = [];
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading monthly expenses: $e");
      setState(() {
        _operationalItems = [];
        _ofCountryItems = [];
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveExpenseDataSilently() async {
    try {
      await _db.collection('monthly_operational_expenses').doc(_periodDocId).set({
        'year': _selectedYear,
        'month': _selectedMonth,
        'periodName': _monthYearTitle,
        'operationalItems': _operationalItems,
        'ofCountryItems': _ofCountryItems,
        'totalOperational': _totalOperational,
        'totalOfCountry': _totalOfCountry,
        'grandTotal': _grandTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving monthly expenses to Firestore: $e");
    }
  }

  double get _totalOperational {
    double sum = 0;
    for (var item in _operationalItems) {
      sum += (item['amount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  double get _totalOfCountry {
    double sum = 0;
    for (var item in _ofCountryItems) {
      sum += (item['amount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  double get _grandTotal => _totalOperational + _totalOfCountry;

  // -------------------------------------------------------------------
  // MODAL DIALOGS FOR EDITING & ADDING ITEMS WITH CATEGORY DROPDOWN
  // -------------------------------------------------------------------
  void _showItemDialog({
    required bool isOfCountry,
    Map<String, dynamic>? existingItem,
    int? index,
  }) {
    final titleController = TextEditingController(text: existingItem?['title'] ?? '');
    final amountController = TextEditingController(
      text: existingItem != null ? (existingItem['amount'] as num).toInt().toString() : '',
    );
    String selectedCategory = isOfCountry ? 'Pilihan Wilayah' : 'Pilih Kategori (Opsional)';

    final List<String> categoriesOps = [
      'Pilih Kategori (Opsional)',
      'BBM Luarkota',
      'Biaya Listrik',
      'Biaya Perbaikan Mobil',
      'Biaya Bongkar Barang',
      'Biaya Pengiriman Dokumen',
      'Biaya Operasional',
      'Lainnya / Manual',
    ];

    final List<String> categoriesOfCountry = [
      'Pilihan Wilayah',
      'Magelang,Semarang',
      'Blora',
      'Wonosobo Yogyakarta',
      'Pekalongan Boyolali',
      'Wonosobo,Pekalongan,Semarang',
      'Lainnya / Manual',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Icon(
                  existingItem != null ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 10),
                Text(
                  existingItem != null
                      ? (isOfCountry ? 'Edit Biaya Of Country' : 'Edit Biaya Operasional')
                      : (isOfCountry ? 'Tambah Biaya Of Country' : 'Tambah Biaya Operasional'),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Dropdown Selection
                const Text('Kategori Biaya:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0284C7)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: (isOfCountry ? categoriesOfCountry : categoriesOps).contains(selectedCategory)
                          ? selectedCategory
                          : (isOfCountry ? categoriesOfCountry.first : categoriesOps.first),
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
                      items: (isOfCountry ? categoriesOfCountry : categoriesOps).map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setDialogState(() {
                          selectedCategory = val;
                          if (!isOfCountry) {
                            if (val == 'BBM Luarkota') {
                              titleController.text = 'BBM Luarkota ';
                            } else if (val == 'Biaya Listrik') {
                              titleController.text = 'Biaya Listrik';
                            } else if (val == 'Biaya Perbaikan Mobil') {
                              titleController.text = 'Biaya Perbaikan Mobil ';
                            } else if (val == 'Biaya Bongkar Barang') {
                              titleController.text = 'Biaya Bongkar Barang Pengiriman di Agen ';
                            } else if (val == 'Biaya Pengiriman Dokumen') {
                              titleController.text = 'Biaya Pengiriman dokumen';
                            } else if (val == 'Biaya Operasional') {
                              titleController.text = 'Biaya Operasional ';
                            }
                          } else {
                            if (val != 'Pilihan Wilayah' && val != 'Lainnya / Manual') {
                              titleController.text = val;
                            }
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Keterangan / Title Text Field
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: isOfCountry ? 'Kota / Wilayah Luarkota' : 'Keterangan Biaya Operasional',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),

                // Amount Text Field
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Jumlah Biaya (Rp)',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    prefixText: 'Rp ',
                    prefixStyle: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final titleStr = titleController.text.trim();
                  final amountVal = double.tryParse(amountController.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
                  if (titleStr.isEmpty || amountVal <= 0) return;

                  setState(() {
                    final newItem = {'title': titleStr, 'amount': amountVal};
                    if (isOfCountry) {
                      if (index != null && index < _ofCountryItems.length) {
                        _ofCountryItems[index] = newItem;
                      } else {
                        _ofCountryItems.add(newItem);
                      }
                    } else {
                      if (index != null && index < _operationalItems.length) {
                        _operationalItems[index] = newItem;
                      } else {
                        _operationalItems.add(newItem);
                      }
                    }
                  });

                  _saveExpenseDataSilently();
                  Navigator.pop(ctx);
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteItem(bool isOfCountry, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Hapus Item Biaya?', style: TextStyle(color: Colors.white)),
        content: const Text('Apakah Anda yakin ingin menghapus item pengeluaran ini?', style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() {
                if (isOfCountry) {
                  _ofCountryItems.removeAt(index);
                } else {
                  _operationalItems.removeAt(index);
                }
              });
              _saveExpenseDataSilently();
              Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // CARI BERDASARKAN BULAN & TAHUN
  // -------------------------------------------------------------------
  void _showMonthYearSearchDialog() {
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Row(
                children: [
                  Icon(Icons.search_rounded, color: Color(0xFF38BDF8)),
                  SizedBox(width: 10),
                  Text('Cari Periode Bulan & Tahun', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pilih Bulan:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: tempMonth,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        items: List.generate(12, (i) {
                          return DropdownMenuItem(
                            value: i + 1,
                            child: Text(_monthNames[i]),
                          );
                        }),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempMonth = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Pilih Tahun:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0284C7)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: tempYear,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        items: [2024, 2025, 2026, 2027, 2028, 2029, 2030].map((y) {
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempYear = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedMonth = tempMonth;
                      _selectedYear = tempYear;
                    });
                    _loadExpenseData();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Tampilkan Data'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------
  // IMPORT EXCEL (.xlsx)
  // -------------------------------------------------------------------
  Future<void> _importFromExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal membaca file Excel yang dipilih (bytes kosong).')),
          );
        }
        return;
      }

      final sanitizedBytes = _sanitizeExcelBytes(bytes);

      excel_pkg.Excel? excel;
      try {
        excel = excel_pkg.Excel.decodeBytes(sanitizedBytes);
      } catch (e) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 26),
                  SizedBox(width: 10),
                  Text('Format File Excel Perlu Diperbarui', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'File Excel yang Anda pilih menggunakan format lama (.xls) atau struktur spreadsheet khusus yang tidak didukung parser otomatis.\n\n'
                '💡 Solusi Mudah (Hanya 5 Detik):\n'
                '1. Buka file Excel tersebut di Microsoft Excel / Google Sheets.\n'
                '2. Klik File ➔ Save As (Simpan Sebagai).\n'
                '3. Pilih jenis file: Excel Workbook (*.xlsx).\n'
                '4. Coba impor kembali file .xlsx yang baru disimpan tersebut.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Mengerti', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (excel == null || excel.tables.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File Excel tidak memiliki tabel/sheet yang dapat dibaca.')),
          );
        }
        return;
      }

      int totalMonthsImported = 0;
      List<String> allSheetNames = [];
      try {
        allSheetNames = excel.tables.keys.toList();
      } catch (_) {}

      for (var table in allSheetNames) {
        excel_pkg.Sheet? sheet;
        try {
          sheet = excel.tables[table];
        } catch (_) {
          continue;
        }
        if (sheet == null) continue;

        // Detect month and year from sheet name (e.g., "Maret 2025")
        int targetMonth = _detectMonthFromName(table) ?? _selectedMonth;
        int targetYear = _detectYearFromName(table) ?? _selectedYear;

        bool isParsingOfCountry = false;
        List<Map<String, dynamic>> currentOps = [];
        List<Map<String, dynamic>> currentOfCountry = [];

        for (var row in sheet.rows) {
          if (row.isEmpty) continue;

          List<String> rowTexts = [];
          for (var cell in row) {
            if (cell == null) {
              rowTexts.add('');
              continue;
            }
            String valStr = '';
            try {
              final val = cell.value;
              if (val != null) {
                valStr = val.toString().trim();
              }
            } catch (_) {
              valStr = '';
            }
            rowTexts.add(valStr);
          }

          final joinedRow = rowTexts.join(' ').toLowerCase();
          if (joinedRow.trim().isEmpty) continue;

          if (joinedRow.contains('laporan') ||
              joinedRow.contains('total grandtotal') ||
              joinedRow.contains('biaya operasional bulan') ||
              joinedRow.contains('subtotal') ||
              joinedRow.contains('keterangan biaya operasional')) {
            continue;
          }

          // Extract Title and Amount from cells
          String title = '';
          double amount = 0;

          for (int c = 0; c < rowTexts.length; c++) {
            final text = rowTexts[c];
            if (text.isEmpty) continue;
            final lower = text.toLowerCase();

            // Skip row numbers (like 1, 2, 3 in Column A) or 'rp' or header words
            if (c == 0 && RegExp(r'^\d+$').hasMatch(text)) continue;
            if (lower == 'rp' || lower == 'no' || lower == 'jumlah' || lower == 'jumlah (rp)' || lower == 'total') continue;

            double parsed = _parseAmountString(text);
            if (parsed > 0 && amount == 0) {
              amount = parsed;
            } else if (title.isEmpty && !RegExp(r'^\d+$').hasMatch(text) && !lower.startsWith('total')) {
              title = text;
            }
          }

          // Header check: contains 'of country' AND amount == 0 (section header has no amount)
          if ((joinedRow.contains('biaya of country') || joinedRow.contains('of country')) && amount == 0) {
            isParsingOfCountry = true;
            continue;
          }

          if (title.isNotEmpty && amount > 0) {
            if (isParsingOfCountry) {
              currentOfCountry.add({'title': title, 'amount': amount});
            } else {
              currentOps.add({'title': title, 'amount': amount});
            }
          }
        }

        if (currentOps.isNotEmpty || currentOfCountry.isNotEmpty) {
          final docId = '${targetYear}_${targetMonth}';
          double totalOps = currentOps.fold(0.0, (sum, i) => sum + (i['amount'] as double? ?? 0.0));
          double totalOfC = currentOfCountry.fold(0.0, (sum, i) => sum + (i['amount'] as double? ?? 0.0));
          final periodTitle = '${_monthNames[targetMonth - 1].toUpperCase()} $targetYear';

          await _db.collection('monthly_operational_expenses').doc(docId).set({
            'year': targetYear,
            'month': targetMonth,
            'periodName': periodTitle,
            'operationalItems': currentOps,
            'ofCountryItems': currentOfCountry,
            'totalOperational': totalOps,
            'totalOfCountry': totalOfC,
            'grandTotal': totalOps + totalOfC,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': 'LUCIFAX (DEV)',
          }, SetOptions(merge: true));

          totalMonthsImported++;
        }
      }

      await _loadExpenseData();

      if (mounted) {
        if (totalMonthsImported > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(
                'Berhasil mengimpor data $totalMonthsImported bulan dari file Excel ke database!',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada data biaya yang dapat diimpor dari file Excel ini.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor file Excel: $e')),
        );
      }
    }
  }

  int? _detectMonthFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('jan')) return 1;
    if (lower.contains('feb')) return 2;
    if (lower.contains('mar')) return 3;
    if (lower.contains('apr')) return 4;
    if (lower.contains('mei') || lower.contains('may')) return 5;
    if (lower.contains('jun')) return 6;
    if (lower.contains('jul')) return 7;
    if (lower.contains('agu') || lower.contains('aug')) return 8;
    if (lower.contains('sep')) return 9;
    if (lower.contains('okt') || lower.contains('oct')) return 10;
    if (lower.contains('nov')) return 11;
    if (lower.contains('des') || lower.contains('dec')) return 12;
    return null;
  }

  int? _detectYearFromName(String name) {
    final match = RegExp(r'20\d{2}').firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  double _parseAmountString(String input) {
    if (input.isEmpty) return 0;
    try {
      final clean = input
          .replaceAll('Rp', '')
          .replaceAll('rp', '')
          .replaceAll(' ', '')
          .replaceAll('.', '')
          .replaceAll(',00', '')
          .replaceAll(',', '.');
      return double.tryParse(clean) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  List<int> _sanitizeExcelBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (final f in archive.files) {
        if (f.name == 'xl/sharedStrings.xml') {
          final rawBytes = f.content as List<int>;
          String content = utf8.decode(rawBytes);

          // 1. Strip <rPr>...</rPr> rich text formatting tags
          content = content.replaceAll(RegExp(r'<rPr>.*?</rPr>', dotAll: true), '');

          // 2. Make every <si> tag uniquely distinct by appending an index comment
          // to prevent excel package's duplicate-deduplication _list index shift bug!
          int siIndex = 0;
          final siRegExp = RegExp(r'<si>(.*?)</si>', dotAll: true);
          final cleanedContent = content.replaceAllMapped(siRegExp, (match) {
            final inner = match.group(1) ?? '';
            final tMatches = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner);
            final text = tMatches.map((m) => m.group(1) ?? '').join('');
            final idx = siIndex++;
            return '<si><t xml:space="preserve">$text</t><!-- uid_$idx --></si>';
          });

          final updatedBytes = utf8.encode(cleanedContent);
          newArchive.addFile(ArchiveFile(f.name, updatedBytes.length, updatedBytes));
        } else {
          newArchive.addFile(f);
        }
      }

      final encoder = ZipEncoder();
      final reEncoded = encoder.encode(newArchive);
      if (reEncoded != null) {
        return reEncoded;
      }
    } catch (e) {
      debugPrint("Sanitize Excel bytes exception: $e");
    }
    return bytes;
  }

  void _confirmResetToDefault() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Reset ke Template Default?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Tindakan ini akan mengembalikan daftar Biaya Operasional periode ini ke template standar.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              setState(() {
                _operationalItems = List.from(_defaultOperationalItems);
                _ofCountryItems = List.from(_defaultOfCountryItems);
              });
              _saveExpenseDataSilently();
              Navigator.pop(ctx);
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // EXPORT EXCEL (.xlsx)
  // -------------------------------------------------------------------
  Future<void> _exportToExcel() async {
    try {
      final sheetName = 'BO BULAN $_monthYearTitle';
      var excel = excel_pkg.Excel.createExcel();
      excel_pkg.Sheet sheetObject = excel[sheetName];
      excel.setDefaultSheet(sheetName);

      final cellBorder = excel_pkg.Border(
        borderStyle: excel_pkg.BorderStyle.Thin,
        borderColorHex: excel_pkg.ExcelColor.fromHexString('#000000'),
      );

      final titleStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 12,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
      );

      final headerStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final centerDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Center,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final leftDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Left,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final rightDataStyle = excel_pkg.CellStyle(
        horizontalAlign: excel_pkg.HorizontalAlign.Right,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      final boldFooterStyle = excel_pkg.CellStyle(
        bold: true,
        fontSize: 10,
        horizontalAlign: excel_pkg.HorizontalAlign.Right,
        verticalAlign: excel_pkg.VerticalAlign.Center,
        topBorder: cellBorder,
        bottomBorder: cellBorder,
        leftBorder: cellBorder,
        rightBorder: cellBorder,
      );

      // Row 0: Title
      var cTitle = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
      cTitle.value = excel_pkg.TextCellValue('BIAYA OPERASIONAL BULAN $_monthYearTitle');
      cTitle.cellStyle = titleStyle;
      sheetObject.merge(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0),
      );

      // Row 2: Table 1 Header
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = excel_pkg.TextCellValue('No');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).cellStyle = headerStyle;

      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = excel_pkg.TextCellValue('BIAYA OPERASIONAL BULAN $_monthYearTitle');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).cellStyle = headerStyle;

      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = excel_pkg.TextCellValue('Jumlah');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).cellStyle = headerStyle;

      int curRow = 3;
      for (int i = 0; i < _operationalItems.length; i++) {
        final item = _operationalItems[i];
        final val = (item['amount'] as num).toDouble();

        var cNo = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow));
        cNo.value = excel_pkg.IntCellValue(i + 1);
        cNo.cellStyle = centerDataStyle;

        var cTitleItem = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow));
        cTitleItem.value = excel_pkg.TextCellValue(item['title'].toString());
        cTitleItem.cellStyle = leftDataStyle;

        var cAmt = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow));
        cAmt.value = excel_pkg.TextCellValue(_currency.format(val));
        cAmt.cellStyle = rightDataStyle;

        curRow++;
      }

      curRow++;

      // Table 2 Header: Biaya Of country
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow)).value = excel_pkg.TextCellValue('No');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow)).cellStyle = headerStyle;

      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow)).value = excel_pkg.TextCellValue('Biaya Of country');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow)).cellStyle = headerStyle;

      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow)).value = excel_pkg.TextCellValue('Jumlah');
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow)).cellStyle = headerStyle;

      curRow++;
      for (int i = 0; i < _ofCountryItems.length; i++) {
        final item = _ofCountryItems[i];
        final val = (item['amount'] as num).toDouble();

        var cNo = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow));
        cNo.value = excel_pkg.IntCellValue(i + 1);
        cNo.cellStyle = centerDataStyle;

        var cTitleItem = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow));
        cTitleItem.value = excel_pkg.TextCellValue(item['title'].toString());
        cTitleItem.cellStyle = leftDataStyle;

        var cAmt = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow));
        cAmt.value = excel_pkg.TextCellValue(_currency.format(val));
        cAmt.cellStyle = rightDataStyle;

        curRow++;
      }

      // Grand Total Row
      sheetObject.merge(
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow),
        excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow),
      );

      var cLabelGrand = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: curRow));
      cLabelGrand.value = excel_pkg.TextCellValue('TOTAL GRANDTOTAL (SEMUA)');
      cLabelGrand.cellStyle = boldFooterStyle;
      sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: curRow)).cellStyle = boldFooterStyle;

      var cValGrand = sheetObject.cell(excel_pkg.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: curRow));
      cValGrand.value = excel_pkg.TextCellValue(_currency.format(_grandTotal));
      cValGrand.cellStyle = boldFooterStyle;

      // Set Column Widths
      sheetObject.setColumnWidth(0, 8.0);
      sheetObject.setColumnWidth(1, 65.0);
      sheetObject.setColumnWidth(2, 25.0);

      List<int>? fileBytes = excel.encode();
      if (fileBytes != null) {
        final bytes = Uint8List.fromList(fileBytes);
        final fileName = 'BIAYA OPERASIONAL BULAN $_monthYearTitle.xlsx';

        await Printing.sharePdf(bytes: bytes, filename: fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal export Excel (.xlsx): $e')),
        );
      }
    }
  }

  // -------------------------------------------------------------------
  // CETAK PDF
  // -------------------------------------------------------------------
  Future<void> _printPdf() async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              // Header Document
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LAPORAN BIAYA OPERASIONAL BULANAN',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Cabang: JAWA TENGAH | Periode: $_monthYearTitle',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('LUCIFAX', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 10),

              // Table 1: Biaya Operasional Rutin
              pw.Text(
                'BIAYA OPERASIONAL BULAN $_monthYearTitle',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
              ),
              pw.SizedBox(height: 6),

              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                headerHeight: 22,
                cellHeight: 18,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                },
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                },
                headers: ['NO', 'KETERANGAN BIAYA OPERASIONAL', 'JUMLAH (RP)'],
                columnWidths: {
                  0: const pw.FixedColumnWidth(25),
                  1: const pw.FlexColumnWidth(5.8),
                  2: const pw.FlexColumnWidth(1.2),
                },
                data: [
                  ...List.generate(_operationalItems.length, (i) {
                    final item = _operationalItems[i];
                    final amount = (item['amount'] as num).toDouble();
                    return [
                      '${i + 1}',
                      item['title'].toString(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Rp', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text(_amountFormat.format(amount), style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ];
                  }),
                  [
                    '',
                    'TOTAL BIAYA OPERASIONAL',
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Rp', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        pw.Text(_amountFormat.format(_totalOperational), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
              pw.SizedBox(height: 14),

              // Table 2: Biaya Of Country
              pw.Text(
                'BIAYA OF COUNTRY / UANG MAKAN LUARKOTA',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
              ),
              pw.SizedBox(height: 6),

              pw.TableHelper.fromTextArray(
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                headerHeight: 22,
                cellHeight: 18,
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                },
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                },
                headers: ['NO', 'KOTA / WILAYAH LUARKOTA', 'JUMLAH (RP)'],
                columnWidths: {
                  0: const pw.FixedColumnWidth(25),
                  1: const pw.FlexColumnWidth(5.8),
                  2: const pw.FlexColumnWidth(1.2),
                },
                data: [
                  ...List.generate(_ofCountryItems.length, (i) {
                    final item = _ofCountryItems[i];
                    final amount = (item['amount'] as num).toDouble();
                    return [
                      '${i + 1}',
                      item['title'].toString(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Rp', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text(_amountFormat.format(amount), style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ];
                  }),
                  [
                    '',
                    'TOTAL BIAYA OF COUNTRY',
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Rp', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        pw.Text(_amountFormat.format(_totalOfCountry), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ],
              ),
              pw.SizedBox(height: 16),

              // Grand Total Highlight Box (Styled with professional corporate blue tint & sharp border)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.blue900, width: 1.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TOTAL GRANDTOTAL (SEMUA)',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
                    ),
                    pw.Row(
                      children: [
                        pw.Text('Rp ', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Text(_amountFormat.format(_grandTotal), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
            ];
          },
        ),
      );

      final fileName = 'BIAYA OPERASIONAL BULAN $_monthYearTitle.pdf';
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(label: 'BIAYA OPERASIONAL BULAN $_monthYearTitle'),
      );
      final pdfBytes = await doc.save();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isKacab = authProvider.currentUser?.role.toLowerCase() == 'kacab';
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row (Static Top Header)
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.request_quote_rounded, color: Color(0xFF38BDF8), size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'BIAYA OPERASIONAL BULANAN',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cabang: JAWA TENGAH | Periode: $_monthYearTitle',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Month & Year Picker Button
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await _showMonthYearPicker(context, _selectedMonth, _selectedYear);
                              if (picked != null) {
                                setState(() {
                                  _selectedMonth = picked.month;
                                  _selectedYear = picked.year;
                                });
                                _loadExpenseData();
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF0284C7)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Bulan: ${_monthNames[_selectedMonth - 1]} $_selectedYear',
                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8), size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Overflow Menu Button
                        PopupMenuButton<String>(
                          tooltip: 'Menu Opsi',
                          offset: const Offset(0, 40),
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF0284C7)),
                            ),
                            child: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 16),
                          ),
                          onSelected: (val) {
                            if (val == 'search') {
                              _showMonthYearSearchDialog();
                            } else if (val == 'excel') {
                              _exportToExcel();
                            } else if (val == 'pdf') {
                              _printPdf();
                            } else if (val == 'import') {
                              _importFromExcel();
                            } else if (val == 'reset') {
                              _confirmResetToDefault();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'search',
                              child: Row(
                                children: [
                                  Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                                  SizedBox(width: 10),
                                  Text('Cari berdasarkan Bulan & Tahun', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            const PopupMenuItem(
                              value: 'excel',
                              child: Row(
                                children: [
                                  Icon(Icons.table_view_rounded, color: Color(0xFF10B981), size: 18),
                                  SizedBox(width: 10),
                                  Text('Download Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'pdf',
                              child: Row(
                                children: [
                                  Icon(Icons.print_rounded, color: Color(0xFF0284C7), size: 18),
                                  SizedBox(width: 10),
                                  Text('Download PDF', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            if (!isKacab) ...[
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'import',
                                child: Row(
                                  children: [
                                    Icon(Icons.file_upload_outlined, color: Colors.amberAccent, size: 18),
                                    SizedBox(width: 10),
                                    Text('Import Excel (.xlsx)', style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Row(
                                  children: [
                                    Icon(Icons.restart_alt_rounded, color: Colors.redAccent, size: 18),
                                    SizedBox(width: 10),
                                    Text('Reset ke Template Default', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.request_quote_rounded, color: Color(0xFF38BDF8), size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'BIAYA OPERASIONAL BULANAN (BO BULANAN)',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cabang: JAWA TENGAH | Periode: $_monthYearTitle',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),

                    // Month Selector, Year Selector & Titik 3 Overflow Menu
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Month & Year Picker Button
                        InkWell(
                          onTap: () async {
                            final picked = await _showMonthYearPicker(context, _selectedMonth, _selectedYear);
                            if (picked != null) {
                              setState(() {
                                _selectedMonth = picked.month;
                                _selectedYear = picked.year;
                              });
                              _loadExpenseData();
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF0284C7)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Bulan: ${_monthNames[_selectedMonth - 1]} $_selectedYear',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8), size: 18),
                              ],
                            ),
                          ),
                        ),

                        // FITUR TITIK 3 (OVERFLOW ACTIONS MENU)
                        PopupMenuButton<String>(
                          tooltip: 'Menu Opsi Titik 3 (Cari & Download)',
                          offset: const Offset(0, 40),
                          color: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF0284C7)),
                            ),
                            child: const Icon(Icons.more_vert_rounded, color: Color(0xFF38BDF8), size: 18),
                          ),
                          onSelected: (val) {
                            if (val == 'search') {
                              _showMonthYearSearchDialog();
                            } else if (val == 'excel') {
                              _exportToExcel();
                            } else if (val == 'pdf') {
                              _printPdf();
                            } else if (val == 'import') {
                              _importFromExcel();
                            } else if (val == 'reset') {
                              _confirmResetToDefault();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'search',
                              child: Row(
                                children: [
                                  Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                                  SizedBox(width: 10),
                                  Text('Cari berdasarkan Bulan & Tahun', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            const PopupMenuItem(
                              value: 'excel',
                              child: Row(
                                children: [
                                  Icon(Icons.table_view_rounded, color: Color(0xFF10B981), size: 18),
                                  SizedBox(width: 10),
                                  Text('Download Excel (.xlsx)', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'pdf',
                              child: Row(
                                children: [
                                  Icon(Icons.print_rounded, color: Color(0xFF0284C7), size: 18),
                                  SizedBox(width: 10),
                                  Text('Download PDF', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            if (!isKacab) ...[
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'import',
                                child: Row(
                                  children: [
                                    Icon(Icons.file_upload_outlined, color: Colors.amberAccent, size: 18),
                                    SizedBox(width: 10),
                                    Text('Import Excel (.xlsx)', style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Row(
                                  children: [
                                    Icon(Icons.restart_alt_rounded, color: Colors.redAccent, size: 18),
                                    SizedBox(width: 10),
                                    Text('Reset ke Template Default', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
          SizedBox(height: isMobile ? 8 : 10),

          // KPI Cards (Responsive Stack on Mobile, Row on Desktop)
          isMobile
              ? Column(
                  children: [
                    _buildKpiCard(
                      title: 'TOTAL BIAYA OPERASIONAL',
                      value: _currency.format(_totalOperational),
                      subtitle: '${_operationalItems.length} Item Pengeluaran',
                      icon: Icons.receipt_rounded,
                      color: const Color(0xFF38BDF8),
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 6),
                    _buildKpiCard(
                      title: 'TOTAL BIAYA OF COUNTRY',
                      value: _currency.format(_totalOfCountry),
                      subtitle: '${_ofCountryItems.length} Lokasi Luarkota',
                      icon: Icons.commute_rounded,
                      color: Colors.amberAccent,
                      isMobile: isMobile,
                    ),
                    const SizedBox(height: 6),
                    _buildKpiCard(
                      title: 'TOTAL GRANDTOTAL (SEMUA)',
                      value: _currency.format(_grandTotal),
                      subtitle: 'Total Tagihan Bulan $_monthYearTitle',
                      icon: Icons.monetization_on_rounded,
                      color: Colors.greenAccent,
                      isMobile: isMobile,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        title: 'TOTAL BIAYA OPERASIONAL',
                        value: _currency.format(_totalOperational),
                        subtitle: '${_operationalItems.length} Item Pengeluaran',
                        icon: Icons.receipt_rounded,
                        color: const Color(0xFF38BDF8),
                        isMobile: isMobile,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'TOTAL BIAYA OF COUNTRY',
                        value: _currency.format(_totalOfCountry),
                        subtitle: '${_ofCountryItems.length} Lokasi Luarkota',
                        icon: Icons.commute_rounded,
                        color: Colors.amberAccent,
                        isMobile: isMobile,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiCard(
                        title: 'TOTAL GRANDTOTAL (SEMUA)',
                        value: _currency.format(_grandTotal),
                        subtitle: 'Total Tagihan Bulan $_monthYearTitle',
                        icon: Icons.monetization_on_rounded,
                        color: Colors.greenAccent,
                        isMobile: isMobile,
                      ),
                    ),
                  ],
                ),
          SizedBox(height: isMobile ? 8 : 12),

          // MAIN BODY SECTION: ALL FITS IN ONE SINGLE SCREEN VIEW!
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // TABLE 1 SECTION HEADER & LIVE SEARCH BAR
                      isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '1. BIAYA OPERASIONAL BULAN $_monthYearTitle',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF0284C7)),
                                        ),
                                        child: TextField(
                                          controller: _searchController,
                                          style: const TextStyle(color: Colors.white, fontSize: 11),
                                          decoration: InputDecoration(
                                            hintText: 'Cari nama biaya / rute...',
                                            hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 16),
                                            suffixIcon: _searchQuery.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 14),
                                                    onPressed: () {
                                                      setState(() {
                                                        _searchController.clear();
                                                        _searchQuery = '';
                                                      });
                                                    },
                                                  )
                                                : null,
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                          onChanged: (val) {
                                            setState(() => _searchQuery = val.trim().toLowerCase());
                                          },
                                        ),
                                      ),
                                    ),
                                    if (!isKacab) ...[
                                      const SizedBox(width: 6),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E293B),
                                          foregroundColor: const Color(0xFF38BDF8),
                                          side: const BorderSide(color: Color(0xFF0284C7)),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () => _showItemDialog(isOfCountry: false),
                                        icon: const Icon(Icons.add_rounded, size: 14),
                                        label: const Text('+ Item', style: TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '1. BIAYA OPERASIONAL BULAN $_monthYearTitle',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),

                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    // Live Search Input Box
                                    Container(
                                      width: 220,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF0284C7)),
                                      ),
                                      child: TextField(
                                        controller: _searchController,
                                        style: const TextStyle(color: Colors.white, fontSize: 11),
                                        decoration: InputDecoration(
                                          hintText: 'Cari nama biaya / rute...',
                                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 16),
                                          suffixIcon: _searchQuery.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 14),
                                                  onPressed: () {
                                                    setState(() {
                                                      _searchController.clear();
                                                      _searchQuery = '';
                                                    });
                                                  },
                                                )
                                              : null,
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        ),
                                        onChanged: (val) {
                                          setState(() => _searchQuery = val.trim().toLowerCase());
                                        },
                                      ),
                                    ),
                                    if (!isKacab)
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E293B),
                                          foregroundColor: const Color(0xFF38BDF8),
                                          side: const BorderSide(color: Color(0xFF0284C7)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () => _showItemDialog(isOfCountry: false),
                                        icon: const Icon(Icons.add_rounded, size: 14),
                                        label: const Text('Tambah Item Biaya', style: TextStyle(fontSize: 11)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                      const SizedBox(height: 6),

                      // TABLE 1 CONTAINER WITH INNER SCROLLABLE DATA LIST
                      Expanded(
                        flex: 5,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              // Fixed Table Header
                              Container(
                                height: 36,
                                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(width: isMobile ? 26 : 40, child: Text('NO', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11))),
                                    Expanded(child: Text('KETERANGAN BIAYA OPERASIONAL', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: isMobile ? 110 : 160, child: Text('JUMLAH (RP)', style: TextStyle(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), textAlign: TextAlign.right)),
                                    if (!isKacab)
                                      SizedBox(width: isMobile ? 36 : 60, child: Text('AKSI', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: Colors.white10),

                              // Inner Scrollable List Body for Table 1
                              Expanded(
                                child: _filteredOperationalItems.isEmpty
                                    ? const Center(
                                        child: Text('Tidak ada item biaya operasional yang cocok.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                      )
                                    : ListView.builder(
                                        itemCount: _filteredOperationalItems.length,
                                        itemBuilder: (context, idx) {
                                          final item = _filteredOperationalItems[idx];
                                          final val = (item['amount'] as num).toDouble();
                                          final originalIdx = _operationalItems.indexOf(item);

                                          return Container(
                                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02),
                                              border: const Border(bottom: BorderSide(color: Colors.white10)),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: isMobile ? 26 : 40,
                                                  child: Text('${idx + 1}', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12)),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    item['title'].toString(),
                                                    style: TextStyle(color: Colors.white, fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: isMobile ? 110 : 160,
                                                  child: Text(
                                                    _currency.format(val),
                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12),
                                                    textAlign: TextAlign.right,
                                                  ),
                                                ),
                                                if (!isKacab)
                                                  SizedBox(
                                                    width: isMobile ? 36 : 60,
                                                    child: Center(
                                                      child: PopupMenuButton<String>(
                                                        tooltip: 'Aksi Item',
                                                        color: const Color(0xFF0F172A),
                                                        padding: EdgeInsets.zero,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(10),
                                                          side: const BorderSide(color: Color(0xFF334155)),
                                                        ),
                                                        icon: Icon(Icons.more_vert_rounded, color: const Color(0xFF38BDF8), size: isMobile ? 16 : 18),
                                                        onSelected: (actionVal) {
                                                          if (actionVal == 'edit') {
                                                            _showItemDialog(isOfCountry: false, existingItem: item, index: originalIdx >= 0 ? originalIdx : idx);
                                                          } else if (actionVal == 'delete') {
                                                            _deleteItem(false, originalIdx >= 0 ? originalIdx : idx);
                                                          }
                                                        },
                                                        itemBuilder: (context) => [
                                                          const PopupMenuItem(
                                                            value: 'edit',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 16),
                                                                SizedBox(width: 8),
                                                                Text('Edit Item', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                                                SizedBox(width: 8),
                                                                Text('Hapus Item', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
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
                      ),
                      const SizedBox(height: 12),

                      // TABLE 2 SECTION HEADER (BIAYA OF COUNTRY)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '2. BIAYA OF COUNTRY / UANG MAKAN LUARKOTA',
                              style: TextStyle(color: Colors.white, fontSize: isMobile ? 11 : 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isKacab)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E293B),
                                foregroundColor: Colors.amberAccent,
                                side: const BorderSide(color: Colors.amberAccent),
                                padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () => _showItemDialog(isOfCountry: true),
                              icon: const Icon(Icons.add_rounded, size: 14),
                              label: Text(isMobile ? '+ Of Country' : 'Tambah Biaya Of Country', style: TextStyle(fontSize: isMobile ? 10 : 11)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // TABLE 2 CONTAINER
                      Expanded(
                        flex: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              // Fixed Table Header
                              Container(
                                height: 36,
                                padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F172A),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(width: isMobile ? 26 : 40, child: Text('NO', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11))),
                                    Expanded(child: Text('KOTA / WILAYAH LUARKOTA', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: isMobile ? 110 : 160, child: Text('JUMLAH (RP)', style: TextStyle(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), textAlign: TextAlign.right)),
                                    if (!isKacab)
                                      SizedBox(width: isMobile ? 36 : 60, child: Text('AKSI', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 11), textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: Colors.white10),

                              // Inner List for Table 2
                              Expanded(
                                child: _filteredOfCountryItems.isEmpty
                                    ? const Center(
                                        child: Text('Tidak ada item biaya of country yang cocok.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                      )
                                    : ListView.builder(
                                        itemCount: _filteredOfCountryItems.length,
                                        itemBuilder: (context, idx) {
                                          final item = _filteredOfCountryItems[idx];
                                          final val = (item['amount'] as num).toDouble();
                                          final originalIdx = _ofCountryItems.indexOf(item);

                                          return Container(
                                            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: idx % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02),
                                              border: const Border(bottom: BorderSide(color: Colors.white10)),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: isMobile ? 26 : 40,
                                                  child: Text('${idx + 1}', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12)),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    item['title'].toString(),
                                                    style: TextStyle(color: Colors.white, fontSize: isMobile ? 11 : 12, fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: isMobile ? 110 : 160,
                                                  child: Text(
                                                    _currency.format(val),
                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12),
                                                    textAlign: TextAlign.right,
                                                  ),
                                                ),
                                                if (!isKacab)
                                                  SizedBox(
                                                    width: isMobile ? 36 : 60,
                                                    child: Center(
                                                      child: PopupMenuButton<String>(
                                                        tooltip: 'Aksi Item',
                                                        color: const Color(0xFF0F172A),
                                                        padding: EdgeInsets.zero,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(10),
                                                          side: const BorderSide(color: Color(0xFF334155)),
                                                        ),
                                                        icon: Icon(Icons.more_vert_rounded, color: const Color(0xFF38BDF8), size: isMobile ? 16 : 18),
                                                        onSelected: (actionVal) {
                                                          if (actionVal == 'edit') {
                                                            _showItemDialog(isOfCountry: true, existingItem: item, index: originalIdx >= 0 ? originalIdx : idx);
                                                          } else if (actionVal == 'delete') {
                                                            _deleteItem(true, originalIdx >= 0 ? originalIdx : idx);
                                                          }
                                                        },
                                                        itemBuilder: (context) => [
                                                          const PopupMenuItem(
                                                            value: 'edit',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 16),
                                                                SizedBox(width: 8),
                                                                Text('Edit Item', style: TextStyle(color: Colors.white, fontSize: 12)),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem(
                                                            value: 'delete',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                                                SizedBox(width: 8),
                                                                Text('Hapus Item', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
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
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),

          // GRAND TOTAL BANNER AT BOTTOM (FIT DI DASAR 1 LAYAR PENGGUNA)
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 8 : 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isMobile ? 'GRANDTOTAL SEMUA' : 'TOTAL GRANDTOTAL (SEMUA BIAYA OPERASIONAL)',
                          style: TextStyle(color: Colors.white, fontSize: isMobile ? 10 : 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _currency.format(_grandTotal),
                  style: TextStyle(color: Colors.greenAccent, fontSize: isMobile ? 13 : 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: isMobile ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 7 : 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: isMobile ? 18 : 22),
          ),
          SizedBox(width: isMobile ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontSize: isMobile ? 9 : 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: Colors.white, fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isMobile ? 9 : 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
