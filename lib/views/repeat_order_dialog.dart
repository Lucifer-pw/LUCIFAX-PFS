import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../models/transaction.dart' as model_tr;

enum RoStatusFilter {
  all,
  sudahRo,
  delayWarning, // 14 - 30 hari
  dormanCritical, // > 30 hari
  allDelay, // delay + dorman
}

class CustomerRoAnalysis {
  final Customer customer;
  final DateTime? lastOrderDate;
  final int? daysSinceLastOrder;
  final int orderCountThisMonth;
  final double grandTotalThisMonth;
  final List<model_tr.Transaction> monthTransactions;
  final model_tr.Transaction? lastTransaction;

  CustomerRoAnalysis({
    required this.customer,
    this.lastOrderDate,
    this.daysSinceLastOrder,
    required this.orderCountThisMonth,
    required this.grandTotalThisMonth,
    required this.monthTransactions,
    this.lastTransaction,
  });

  bool get isSudahRo => orderCountThisMonth > 0;
  bool get isDelayWarning => !isSudahRo && daysSinceLastOrder != null && daysSinceLastOrder! >= 14 && daysSinceLastOrder! <= 30;
  bool get isDormanCritical => !isSudahRo && daysSinceLastOrder != null && daysSinceLastOrder! > 30;
  bool get isActiveRecent => !isSudahRo && daysSinceLastOrder != null && daysSinceLastOrder! < 14;
  bool get isNeverOrdered => lastOrderDate == null;

  String get statusBadgeLabel {
    if (isSudahRo) return 'SUDAH RO (${orderCountThisMonth}x)';
    if (isDelayWarning) return 'DELAY ($daysSinceLastOrder Hari)';
    if (isDormanCritical) return 'DORMAN ($daysSinceLastOrder Hari)';
    if (isActiveRecent) return 'AKTIF ($daysSinceLastOrder Hari)';
    return 'BELUM ORDER';
  }

  Color get statusBadgeColor {
    if (isSudahRo) return const Color(0xFF10B981); // Emerald Green
    if (isDelayWarning) return const Color(0xFFF59E0B); // Amber Yellow
    if (isDormanCritical) return const Color(0xFFEF4444); // Crimson Red
    if (isActiveRecent) return const Color(0xFF0284C7); // Sky Blue
    return const Color(0xFF64748B); // Slate Grey
  }
}

class RepeatOrderDialog extends StatefulWidget {
  final List<model_tr.Transaction> allTransactions;
  final List<Customer> allCustomers;
  final String initialMonthFilter;

  const RepeatOrderDialog({
    super.key,
    required this.allTransactions,
    required this.allCustomers,
    required this.initialMonthFilter,
  });

  static Future<void> show(
    BuildContext context, {
    required List<model_tr.Transaction> allTransactions,
    required List<Customer> allCustomers,
    required String initialMonthFilter,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RepeatOrderDialog(
        allTransactions: allTransactions,
        allCustomers: allCustomers,
        initialMonthFilter: initialMonthFilter,
      ),
    );
  }

  @override
  State<RepeatOrderDialog> createState() => _RepeatOrderDialogState();
}

class _RepeatOrderDialogState extends State<RepeatOrderDialog> {
  late String _selectedMonth;
  late List<String> _availableMonths;
  RoStatusFilter _activeFilter = RoStatusFilter.all;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initAvailableMonths();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initAvailableMonths() {
    final monthSet = <String>{};
    for (final tr in widget.allTransactions) {
      final key = DateFormat('MM-yyyy').format(tr.date);
      monthSet.add(key);
    }

    final sorted = monthSet.toList()..sort((a, b) {
      try {
        final da = DateFormat('MM-yyyy').parse(a);
        final db = DateFormat('MM-yyyy').parse(b);
        return db.compareTo(da);
      } catch (_) {
        return b.compareTo(a);
      }
    });

    _availableMonths = sorted;

    if (widget.initialMonthFilter != 'SEMUA' && _availableMonths.contains(widget.initialMonthFilter)) {
      _selectedMonth = widget.initialMonthFilter;
    } else if (_availableMonths.isNotEmpty) {
      _selectedMonth = _availableMonths.first;
    } else {
      _selectedMonth = DateFormat('MM-yyyy').format(DateTime.now());
      _availableMonths = [_selectedMonth];
    }
  }

  String _cleanPhone(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    }
    return digits;
  }

  Future<void> _openWhatsAppFollowUp(Customer cust, CustomerRoAnalysis analysis) async {
    final rawPhone = cust.phone.trim();
    final formatted = _cleanPhone(rawPhone);

    if (formatted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nomor WhatsApp untuk ${cust.displayName} belum tercatat di data pelanggan!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final storeName = cust.aliasName.trim().isNotEmpty ? cust.aliasName.trim() : cust.customerName.trim();
    String msg = 'Assalamu\'alaikum / Halo Toko $storeName! 👋\n\n'
        'Kami dari PT. Putra Fiva Sejahtera ingin menanyakan kabar dan stok produk frozen food di toko Kakak. '
        'Apakah ada persediaan barang yang perlu kami siapkan untuk jadwal pengiriman berikutnya?\n\n'
        'Jika ada kebutuhan stok, silakan kirimkan list ordernya di sini ya. Terima kasih banyak! 😊';

    final waAppUrl = 'whatsapp://send?phone=$formatted&text=${Uri.encodeComponent(msg)}';
    try {
      final uri = Uri.parse(waAppUrl);
      await launchUrl(uri, webOnlyWindowName: '_self');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuka WhatsApp: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<CustomerRoAnalysis> _calculateAnalysis() {
    DateTime? targetMonthDate;
    try {
      targetMonthDate = DateFormat('MM-yyyy').parse(_selectedMonth);
    } catch (_) {
      targetMonthDate = DateTime.now();
    }
    final targetMonth = targetMonthDate.month;
    final targetYear = targetMonthDate.year;

    // Kelompokkan seluruh transaksi berdasarkan customer
    final transactionsByCust = <String, List<model_tr.Transaction>>{};

    for (final tr in widget.allTransactions) {
      final keyId = tr.customerId.trim().toUpperCase();
      final keyName = tr.customerName.trim().toUpperCase();
      final keyAlias = tr.aliasName.trim().toUpperCase();

      final keysToMap = <String>{};
      if (keyId.isNotEmpty) keysToMap.add(keyId);
      if (keyName.isNotEmpty) keysToMap.add(keyName);
      if (keyAlias.isNotEmpty) keysToMap.add(keyAlias);

      for (final k in keysToMap) {
        if (!transactionsByCust.containsKey(k)) {
          transactionsByCust[k] = [];
        }
        transactionsByCust[k]!.add(tr);
      }
    }

    final now = DateTime.now();
    final results = <CustomerRoAnalysis>[];

    for (final cust in widget.allCustomers) {
      // Ambil transaksi milik customer ini
      final cId = cust.id.trim().toUpperCase();
      final cName = cust.customerName.trim().toUpperCase();
      final cAlias = cust.aliasName.trim().toUpperCase();

      final seenTrIds = <String>{};
      final custTrs = <model_tr.Transaction>[];

      for (final k in [cId, cName, cAlias]) {
        if (k.isNotEmpty && transactionsByCust.containsKey(k)) {
          for (final t in transactionsByCust[k]!) {
            if (!seenTrIds.contains(t.invoiceNo)) {
              seenTrIds.add(t.invoiceNo);
              custTrs.add(t);
            }
          }
        }
      }

      // Urutkan transaksi dari paling baru
      custTrs.sort((a, b) => b.date.compareTo(a.date));

      final lastTr = custTrs.isNotEmpty ? custTrs.first : null;
      final lastDate = lastTr?.date;
      final daysDiff = lastDate != null ? now.difference(lastDate).inDays : null;

      // Filter transaksi di bulan yang dipilih
      final monthTrs = custTrs.where((t) {
        return t.date.month == targetMonth && t.date.year == targetYear;
      }).toList();

      final grandTotalThisMonth = monthTrs.fold<double>(0.0, (sum, t) => sum + t.grandTotal);

      results.add(CustomerRoAnalysis(
        customer: cust,
        lastOrderDate: lastDate,
        daysSinceLastOrder: daysDiff,
        orderCountThisMonth: monthTrs.length,
        grandTotalThisMonth: grandTotalThisMonth,
        monthTransactions: monthTrs,
        lastTransaction: lastTr,
      ));
    }

    // Urutkan prioritas:
    // 1. Yang Dorman Critical & Delay Warning di atas (jika butuh follow-up)
    // 2. Kemudian yang Sudah RO
    results.sort((a, b) {
      // Jika mode filter adalah delay, urutkan dari hari terlama tidak order
      if (_activeFilter == RoStatusFilter.allDelay || _activeFilter == RoStatusFilter.delayWarning || _activeFilter == RoStatusFilter.dormanCritical) {
        final da = a.daysSinceLastOrder ?? 99999;
        final db = b.daysSinceLastOrder ?? 99999;
        return db.compareTo(da); // Paling lama di atas
      }

      // Jika filter sudah RO, urutkan dari omset terbesar
      if (_activeFilter == RoStatusFilter.sudahRo) {
        return b.grandTotalThisMonth.compareTo(a.grandTotalThisMonth);
      }

      // Default: Toko yang delay & butuh perhatian ditaruh lebih atas
      final scoreA = a.isDormanCritical ? 3 : (a.isDelayWarning ? 2 : (a.isSudahRo ? 0 : 1));
      final scoreB = b.isDormanCritical ? 3 : (b.isDelayWarning ? 2 : (b.isSudahRo ? 0 : 1));
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);

      return (b.daysSinceLastOrder ?? 0).compareTo(a.daysSinceLastOrder ?? 0);
    });

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final allAnalysis = _calculateAnalysis();

    // Hitung KPI ringkasan
    final totalCustomers = allAnalysis.length;
    final sudahRoCount = allAnalysis.where((a) => a.isSudahRo).length;
    final delayWarningCount = allAnalysis.where((a) => a.isDelayWarning).length;
    final dormanCount = allAnalysis.where((a) => a.isDormanCritical).length;
    final totalDelayCount = delayWarningCount + dormanCount;
    final totalOmsetThisMonth = allAnalysis.fold<double>(0.0, (sum, a) => sum + a.grandTotalThisMonth);
    final roPercentage = totalCustomers > 0 ? (sudahRoCount / totalCustomers * 100).toStringAsFixed(1) : '0';

    // Filter sesuai tab & search query
    final filtered = allAnalysis.where((item) {
      // Filter status
      switch (_activeFilter) {
        case RoStatusFilter.sudahRo:
          if (!item.isSudahRo) return false;
          break;
        case RoStatusFilter.delayWarning:
          if (!item.isDelayWarning) return false;
          break;
        case RoStatusFilter.dormanCritical:
          if (!item.isDormanCritical) return false;
          break;
        case RoStatusFilter.allDelay:
          if (!item.isDelayWarning && !item.isDormanCritical) return false;
          break;
        case RoStatusFilter.all:
          break;
      }

      // Filter search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final c = item.customer;
        final matchName = c.customerName.toLowerCase().contains(q);
        final matchAlias = c.aliasName.toLowerCase().contains(q);
        final matchCity = c.city.toLowerCase().contains(q);
        if (!matchName && !matchAlias && !matchCity) return false;
      }

      return true;
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 1100,
        height: 750,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER BAR
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.published_with_changes_rounded, color: Color(0xFFF59E0B), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Daftar RO',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Periode: $_selectedMonth',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Monitoring Pelanggan Repeat Order & Deteksi Dini Customer Delay / Dorman',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Pilih Bulan Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedMonth,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                      icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFF38BDF8), size: 18),
                      items: _availableMonths.map((m) {
                        return DropdownMenuItem<String>(
                          value: m,
                          child: Text('Bulan $m'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedMonth = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                  tooltip: 'Tutup',
                ),
              ],
            ),
            const SizedBox(height: 18),

            // KPI CARDS ROW
            Row(
              children: [
                _buildKpiCard('Total Pelanggan', '$totalCustomers Toko', Icons.storefront_rounded, const Color(0xFF38BDF8)),
                const SizedBox(width: 12),
                _buildKpiCard('Sudah RO ($roPercentage%)', '$sudahRoCount Toko', Icons.check_circle_rounded, const Color(0xFF10B981)),
                const SizedBox(width: 12),
                _buildKpiCard('Delay RO (14-30 Hari)', '$delayWarningCount Toko', Icons.warning_amber_rounded, const Color(0xFFF59E0B)),
                const SizedBox(width: 12),
                _buildKpiCard('Dorman (>30 Hari)', '$dormanCount Toko', Icons.cancel_rounded, const Color(0xFFEF4444)),
                const SizedBox(width: 12),
                _buildKpiCard('Omset Bulan Ini', 'Rp ${NumberFormat('#,###', 'id-ID').format(totalOmsetThisMonth)}', Icons.monetization_on_rounded, const Color(0xFFA855F7)),
              ],
            ),
            const SizedBox(height: 16),

            // FILTER TABS & SEARCH
            Row(
              children: [
                _buildFilterChip('Semua ($totalCustomers)', RoStatusFilter.all),
                const SizedBox(width: 8),
                _buildFilterChip('Sudah RO ($sudahRoCount)', RoStatusFilter.sudahRo, badgeColor: const Color(0xFF10B981)),
                const SizedBox(width: 8),
                _buildFilterChip('Semua Delay ($totalDelayCount)', RoStatusFilter.allDelay, badgeColor: const Color(0xFFF97316)),
                const SizedBox(width: 8),
                _buildFilterChip('Delay 14-30 Hari ($delayWarningCount)', RoStatusFilter.delayWarning, badgeColor: const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                _buildFilterChip('Dorman >30 Hari ($dormanCount)', RoStatusFilter.dormanCritical, badgeColor: const Color(0xFFEF4444)),
                const Spacer(),
                SizedBox(
                  width: 250,
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Cari toko / kota...',
                      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 14),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // MAIN TABLE
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada data pelanggan yang cocok dengan filter.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (ctx, idx) {
                            final item = filtered[idx];
                            final cust = item.customer;
                            final lastDateStr = item.lastOrderDate != null ? DateFormat('dd-MM-yyyy').format(item.lastOrderDate!) : '-';
                            final daysStr = item.daysSinceLastOrder != null ? '${item.daysSinceLastOrder} hari lalu' : 'Belum pernah';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              color: idx.isEven ? Colors.transparent : const Color(0xFF0F172A).withOpacity(0.3),
                              child: Row(
                                children: [
                                  // No.
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${idx + 1}',
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),

                                  // Pelanggan & Kota
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cust.displayName,
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on_rounded, color: Color(0xFF94A3B8), size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              cust.city.isNotEmpty ? cust.city : 'Jawa Tengah',
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                            ),
                                            if (cust.phone.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              const Text('•', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                              const SizedBox(width: 8),
                                              Text(
                                                cust.phone,
                                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status RO Badge
                                  SizedBox(
                                    width: 170,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: item.statusBadgeColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: item.statusBadgeColor.withOpacity(0.4)),
                                        ),
                                        child: Text(
                                          item.statusBadgeLabel,
                                          style: TextStyle(
                                            color: item.statusBadgeColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Order Terakhir
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lastDateStr,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          daysStr,
                                          style: TextStyle(
                                            color: item.isDormanCritical
                                                ? const Color(0xFFEF4444)
                                                : (item.isDelayWarning ? const Color(0xFFF59E0B) : const Color(0xFF64748B)),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Order Bulan Ini
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.isSudahRo
                                              ? 'Rp ${NumberFormat('#,###', 'id-ID').format(item.grandTotalThisMonth)}'
                                              : 'Rp 0',
                                          style: TextStyle(
                                            color: item.isSudahRo ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.isSudahRo ? '${item.orderCountThisMonth}x Transaksi' : 'Belum order bulan ini',
                                          style: TextStyle(
                                            color: item.isSudahRo ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Aksi WhatsApp Follow Up
                                  SizedBox(
                                    width: 140,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openWhatsAppFollowUp(cust, item),
                                      icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 14),
                                      label: const Text('Chat WA', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF25D366),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, RoStatusFilter filter, {Color? badgeColor}) {
    final isSelected = _activeFilter == filter;
    final activeColor = badgeColor ?? const Color(0xFF38BDF8);

    return InkWell(
      onTap: () => setState(() => _activeFilter = filter),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFF334155),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
