import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/receivable_provider.dart';
import '../models/receivable.dart';

class ReceivableListView extends StatefulWidget {
  const ReceivableListView({super.key});

  @override
  State<ReceivableListView> createState() => _ReceivableListViewState();
}

class _ReceivableListViewState extends State<ReceivableListView> {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormatter = DateFormat('dd-MM-yyyy');
  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, UNPAID, PAID

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ReceivableProvider>(context, listen: false).fetchReceivables();
    });
  }

  void _showAddEditDialog([Receivable? item]) {
    final tokoController = TextEditingController(text: item?.toko ?? '');
    final noInvoiceController = TextEditingController(text: item?.noInvoice ?? '');
    final nominalController = TextEditingController(text: item != null ? item.nominal.toStringAsFixed(0) : '');
    final keteranganController = TextEditingController(text: item?.keterangan ?? '');
    DateTime selectedDate = item?.tglKirim ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            item == null ? 'Tambah Kartu Piutang' : 'Edit Piutang',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tokoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nama Toko / Outlet',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noInvoiceController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'No. Invoice / Nota',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nominalController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nominal Tagihan (Rp)',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Kirim:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
                  subtitle: Text(dateFormatter.format(selectedDate), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keteranganController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Keterangan',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final toko = tokoController.text.trim();
                final noInvoice = noInvoiceController.text.trim();
                final nominal = double.tryParse(nominalController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                final ket = keteranganController.text.trim();

                if (toko.isEmpty || noInvoice.isEmpty || nominal <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lengkapi nama toko, no invoice, dan nominal!')),
                  );
                  return;
                }

                final provider = Provider.of<ReceivableProvider>(context, listen: false);
                final newItem = Receivable(
                  id: item?.id ?? '',
                  toko: toko,
                  noInvoice: noInvoice,
                  tglKirim: selectedDate,
                  nominal: nominal,
                  keterangan: ket,
                  isLunas: item?.isLunas ?? false,
                );

                await provider.addReceivable(newItem);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ReceivableProvider>(context);
    final filtered = provider.receivables.where((r) {
      final matchesSearch = r.toko.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.noInvoice.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.keterangan.toLowerCase().contains(_searchQuery.toLowerCase());

      if (_statusFilter == 'UNPAID') return matchesSearch && !r.isLunas;
      if (_statusFilter == 'PAID') return matchesSearch && r.isLunas;
      return matchesSearch;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Summary Cards
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Kartu Piutang Toko',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Pencatatan Tagihan & Pelunasan Invoice Cabang',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add_rounded, color: Colors.black),
                label: const Text('Tambah Piutang', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Total Summary KPI Cards
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Total Belum Lunas',
                  value: currencyFormatter.format(provider.totalUnpaid),
                  icon: Icons.pending_actions_rounded,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildKpiCard(
                  title: 'Total Sudah Lunas',
                  value: currencyFormatter.format(provider.totalPaid),
                  icon: Icons.check_circle_outline_rounded,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildKpiCard(
                  title: 'Total Transaksi Piutang',
                  value: '${provider.receivables.length} Invoice',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Controls Bar (Search & Filter)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Cari Toko / No Invoice...',
                      hintStyle: TextStyle(color: Color(0xFF64748B)),
                      prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL', label: Text('Semua')),
                    ButtonSegment(value: 'UNPAID', label: Text('Belum Lunas')),
                    ButtonSegment(value: 'PAID', label: Text('Lunas')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (set) {
                    setState(() => _statusFilter = set.first);
                  },
                  style: ButtonStyle(
                    foregroundColor: MaterialStateProperty.resolveWith(
                      (states) => states.contains(MaterialState.selected) ? Colors.black : Colors.white,
                    ),
                    backgroundColor: MaterialStateProperty.resolveWith(
                      (states) => states.contains(MaterialState.selected) ? const Color(0xFF38BDF8) : Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Table
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('Tidak ada data piutang.', style: TextStyle(color: Color(0xFF94A3B8))))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: DataTable(
                            headingRowHeight: 48,
                            dataRowMaxHeight: 56,
                            columns: const [
                              DataColumn(label: Text('NO', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('TOKO / OUTLET', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('NO INVOICE', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('TGL KIRIM', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('NOMINAL', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('KETERANGAN', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('STATUS', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('AKSI', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold))),
                            ],
                            rows: List.generate(filtered.length, (idx) {
                              final item = filtered[idx];
                              return DataRow(
                                cells: [
                                  DataCell(Text('${idx + 1}', style: const TextStyle(color: Colors.white))),
                                  DataCell(Text(item.toko, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataCell(Text(item.noInvoice, style: const TextStyle(color: Color(0xFF38BDF8)))),
                                  DataCell(Text(dateFormatter.format(item.tglKirim), style: const TextStyle(color: Colors.white70))),
                                  DataCell(Text(currencyFormatter.format(item.nominal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  DataCell(Text(item.keterangan.isEmpty ? '-' : item.keterangan, style: const TextStyle(color: Colors.white60))),
                                  DataCell(
                                    InkWell(
                                      onTap: () => provider.toggleLunas(item.id, item.isLunas),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: item.isLunas ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: item.isLunas ? Colors.greenAccent : Colors.amberAccent),
                                        ),
                                        child: Text(
                                          item.isLunas ? 'LUNAS' : 'BELUM LUNAS',
                                          style: TextStyle(
                                            color: item.isLunas ? Colors.greenAccent : Colors.amberAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                                      onPressed: () => provider.deleteReceivable(item.id),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 4),
              Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
