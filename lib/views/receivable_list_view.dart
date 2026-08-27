import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/receivable_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/receivable.dart';
import '../models/customer.dart';
import '../services/print_service.dart';

class CustomerGroup {
  final String customerName;
  final String city;
  final List<Receivable> items;

  CustomerGroup({
    required this.customerName,
    required this.city,
    required this.items,
  });

  double get totalNominal => items.fold(0.0, (acc, r) => acc + r.nominal);
  int get unpaidCount => items.where((r) => !r.isLunas).length;
  int get paidCount => items.where((r) => r.isLunas).length;
}

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
  String _selectedCustomerFilter = 'ALL'; // 'ALL' or specific customer name (e.g. 'AW FF')
  final Set<String> _expandedCustomers = {}; // Track expanded customer cards

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ReceivableProvider>(context, listen: false).fetchReceivables();
    });
  }

  // ============================================================
  // DIALOG TAMBAH / EDIT KARTU PIUTANG
  // ============================================================
  void _showAddEditPiutangDialog([Receivable? item]) {
    final noInvoiceController = TextEditingController(text: item?.noInvoice ?? '');
    final tokoController = TextEditingController(text: item?.toko ?? '');
    final kotaController = TextEditingController(text: item?.kota ?? '');
    final nominalController = TextEditingController(text: item != null && item.nominal > 0 ? item.nominal.toStringAsFixed(0) : '');
    final keteranganController = TextEditingController(text: item?.keterangan ?? '');
    final customerFocusNode = FocusNode();
    DateTime? selectedDate = item?.tglKirim;

    bool isSearching = false;
    String? searchMessage;
    bool searchSuccess = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
          final allCustomers = customerProvider.customers;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(
                  item == null ? Icons.add_card_rounded : Icons.edit_note_rounded,
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 10),
                Text(
                  item == null ? 'Tambah Kartu Piutang' : 'Edit Kartu Piutang',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Cari No. Invoice
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pencarian Otomatis Invoice',
                            style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Masukkan No Invoice untuk mengisi data otomatis dari database, atau isi manual di bawah.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: noInvoiceController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Cari No Invoice (contoh: 594)...',
                                    hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    filled: true,
                                    fillColor: Color(0xFF1E293B),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(color: Color(0xFF475569)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                      borderSide: BorderSide(color: Color(0xFF38BDF8)),
                                    ),
                                  ),
                                  onSubmitted: (_) async {
                                    await _searchInvoice(
                                      noInvoiceController.text,
                                      setDialogState,
                                      tokoController,
                                      kotaController,
                                      nominalController,
                                      (dt) => selectedDate = dt,
                                      (msg, ok) {
                                        searchMessage = msg;
                                        searchSuccess = ok;
                                      },
                                      (loading) => isSearching = loading,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF38BDF8),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: isSearching
                                    ? null
                                    : () async {
                                        await _searchInvoice(
                                          noInvoiceController.text,
                                          setDialogState,
                                          tokoController,
                                          kotaController,
                                          nominalController,
                                          (dt) => selectedDate = dt,
                                          (msg, ok) {
                                            searchMessage = msg;
                                            searchSuccess = ok;
                                          },
                                          (loading) => isSearching = loading,
                                        );
                                      },
                                icon: isSearching
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : const Icon(Icons.search_rounded, size: 18),
                                label: const Text('Cari', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ],
                          ),
                          if (searchMessage != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: searchSuccess ? Colors.green.withOpacity(0.15) : Colors.amber.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: searchSuccess ? Colors.greenAccent.withOpacity(0.4) : Colors.amberAccent.withOpacity(0.4)),
                              ),
                              child: Text(
                                searchMessage!,
                                style: TextStyle(color: searchSuccess ? Colors.greenAccent : Colors.amberAccent, fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Form Input Manual / Multi-Customer Selection
                    const Text(
                      'Data Toko / Customer & Piutang',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),

                    // Customer Selection / Input (RawAutocomplete using tokoController)
                    RawAutocomplete<Customer>(
                      textEditingController: tokoController,
                      focusNode: customerFocusNode,
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return allCustomers.take(8);
                        }
                        return allCustomers.where((Customer c) {
                          final query = textEditingValue.text.toLowerCase();
                          return c.aliasName.toLowerCase().contains(query) ||
                              c.customerName.toLowerCase().contains(query) ||
                              c.city.toLowerCase().contains(query);
                        });
                      },
                      displayStringForOption: (Customer option) => option.aliasName.isNotEmpty ? option.aliasName : option.customerName,
                      onSelected: (Customer selection) {
                        tokoController.text = selection.aliasName.isNotEmpty ? selection.aliasName : selection.customerName;
                        if (selection.city.isNotEmpty) {
                          kotaController.text = selection.city;
                        }
                        setDialogState(() {});
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Nama Toko / Customer',
                            hintText: 'Pilih atau ketik nama toko/customer...',
                            labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                            hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                            prefixIcon: Icon(Icons.storefront_rounded, color: Color(0xFF38BDF8), size: 20),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8,
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 200),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: options.length,
                                separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                                itemBuilder: (BuildContext context, int index) {
                                  final Customer option = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    title: Text(option.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      '${option.city}${option.address.isNotEmpty ? " • ${option.address}" : ""}',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    ),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // Kota Field
                    TextField(
                      controller: kotaController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Kota / Kabupaten',
                        hintText: 'Contoh: SEMARANG, WONOSOBO, KUDUS...',
                        labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                        hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        prefixIcon: Icon(Icons.location_city_rounded, color: Color(0xFF38BDF8), size: 20),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Nominal Tagihan Field
                    TextField(
                      controller: nominalController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'Nominal Tagihan (Rp)',
                        labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(Icons.payments_rounded, color: Color(0xFF38BDF8), size: 20),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tanggal Kirim Field
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedDate = picked;
                                  });
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8), size: 20),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Tanggal Kirim', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                        Text(
                                          selectedDate != null ? dateFormatter.format(selectedDate!) : 'Belum Ditentukan (-)',
                                          style: TextStyle(
                                            color: selectedDate != null ? Colors.white : const Color(0xFF94A3B8),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF94A3B8)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (selectedDate != null) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Kosongkan Tanggal Kirim (-)',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () {
                                  setDialogState(() {
                                    selectedDate = null;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF475569), height: 1),
                    const SizedBox(height: 12),

                    // Keterangan Field
                    TextField(
                      controller: keteranganController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Keterangan (Opsional)',
                        labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                        prefixIcon: Icon(Icons.notes_rounded, color: Color(0xFF38BDF8), size: 20),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF475569))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                      ),
                    ),
                  ],
                ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final toko = tokoController.text.trim();
                  final noInvoice = noInvoiceController.text.trim();
                  final kota = kotaController.text.trim();
                  final nominal = double.tryParse(nominalController.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
                  final ket = keteranganController.text.trim();

                  if (toko.isEmpty || noInvoice.isEmpty || nominal <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lengkapi No Invoice, Nama Customer/Toko, dan Nominal Tagihan!'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }

                  final provider = Provider.of<ReceivableProvider>(context, listen: false);
                  final newItem = Receivable(
                    id: item?.id ?? '',
                    toko: toko,
                    kota: kota,
                    noInvoice: noInvoice,
                    tglKirim: selectedDate,
                    nominal: nominal,
                    keterangan: ket,
                    isLunas: item?.isLunas ?? false,
                  );

                  bool ok = false;
                  if (item == null) {
                    ok = await provider.addReceivable(newItem);
                  } else {
                    await FirebaseFirestore.instance.collection('receivables').doc(item.id).update(newItem.toFirestore());
                    await provider.fetchReceivables();
                    ok = true;
                  }

                  if (ok && mounted) Navigator.pop(ctx);
                },
                child: Text(
                  item == null ? 'Simpan Piutang' : 'Update',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper search invoice in Firestore & in-memory transactions (Smart Case-Insensitive)
  Future<void> _searchInvoice(
    String invoiceNoRaw,
    StateSetter setDialogState,
    TextEditingController tokoCtrl,
    TextEditingController kotaCtrl,
    TextEditingController nominalCtrl,
    Function(DateTime?) onDateSet,
    Function(String, bool) onResult,
    Function(bool) onLoading,
  ) async {
    final cleanInput = invoiceNoRaw.replaceAll('#', '').trim();
    if (cleanInput.isEmpty) return;

    setDialogState(() => onLoading(true));

    try {
      Map<String, dynamic>? data;
      String matchedInvoiceNo = cleanInput;

      // 1. Try local TransactionProvider in memory first (fast & case-insensitive)
      try {
        final trProvider = Provider.of<TransactionProvider>(context, listen: false);
        final match = trProvider.transactions.where((t) {
          final tInv = t.invoiceNo.toString().replaceAll('#', '').trim().toLowerCase();
          return tInv == cleanInput.toLowerCase() ||
                 tInv.replaceAll(' ', '') == cleanInput.toLowerCase().replaceAll(' ', '');
        }).firstOrNull;

        if (match != null) {
          data = match.toMap();
          matchedInvoiceNo = match.invoiceNo.toString().replaceAll('#', '');
        }
      } catch (_) {}

      // 2. If not found in memory, query Firestore with variations
      if (data == null) {
        final variations = [
          cleanInput,
          cleanInput.toUpperCase(),
          cleanInput.toLowerCase(),
          cleanInput.replaceAll(' ', '').toUpperCase(),
        ];

        for (var queryVar in variations) {
          final snapshot = await FirebaseFirestore.instance
              .collection('transactions')
              .where('invoiceNo', isEqualTo: queryVar)
              .limit(1)
              .get();

          if (snapshot.docs.isNotEmpty) {
            data = snapshot.docs.first.data();
            matchedInvoiceNo = snapshot.docs.first.id;
            break;
          }

          final docSnap = await FirebaseFirestore.instance.collection('transactions').doc(queryVar).get();
          if (docSnap.exists) {
            data = docSnap.data();
            matchedInvoiceNo = docSnap.id;
            break;
          }
        }
      }

      if (data != null) {
        final String customerName = data['aliasName'] ?? data['customerName'] ?? '';
        final String city = data['city'] ?? '';
        final double grandTotal = (data['grandTotal'] is num) ? (data['grandTotal'] as num).toDouble() : 0.0;
        final double returnAmount = (data['returnAmount'] is num) ? (data['returnAmount'] as num).toDouble() : 0.0;
        final double effectiveNominal = (grandTotal - returnAmount).clamp(0.0, double.infinity);

        DateTime delivDate = DateTime.now();
        if (data['deliveryDate'] != null && data['deliveryDate'] is Timestamp) {
          delivDate = (data['deliveryDate'] as Timestamp).toDate();
        } else if (data['date'] != null && data['date'] is Timestamp) {
          delivDate = (data['date'] as Timestamp).toDate();
        }

        setDialogState(() {
          if (customerName.isNotEmpty) tokoCtrl.text = customerName;
          if (city.isNotEmpty) kotaCtrl.text = city;
          if (effectiveNominal > 0) nominalCtrl.text = effectiveNominal.toStringAsFixed(0);
          onDateSet(delivDate);
          onResult('Invoice #$matchedInvoiceNo ditemukan! Data Toko, Kota, & Nominal berhasil diisi.', true);
        });
      } else {
        setDialogState(() {
          onResult('Invoice "$cleanInput" tidak ditemukan di database. Anda tetap dapat mengisi data secara manual.', false);
        });
      }
    } catch (e) {
      setDialogState(() {
        onResult('Gagal mencari invoice: $e', false);
      });
    } finally {
      setDialogState(() => onLoading(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ReceivableProvider>(context);

    // Get list of unique customer names for filter dropdown
    final uniqueCustomers = provider.receivables
        .map((r) => r.toko.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Raw filtered items by search & status & dropdown customer filter
    final filteredRaw = provider.receivables.where((r) {
      final query = _searchQuery.toLowerCase();
      final matchesSearch = r.toko.toLowerCase().contains(query) ||
          r.kota.toLowerCase().contains(query) ||
          r.noInvoice.toLowerCase().contains(query) ||
          r.keterangan.toLowerCase().contains(query);

      final matchesCustomer = _selectedCustomerFilter == 'ALL' ||
          r.toko.trim().toLowerCase() == _selectedCustomerFilter.toLowerCase();

      if (_statusFilter == 'UNPAID') return matchesSearch && matchesCustomer && !r.isLunas;
      if (_statusFilter == 'PAID') return matchesSearch && matchesCustomer && r.isLunas;
      return matchesSearch && matchesCustomer;
    }).toList();

    // Grouping by Customer / Toko Name
    final Map<String, List<Receivable>> groupedMap = {};
    for (var item in filteredRaw) {
      final key = item.toko.trim().isNotEmpty ? item.toko.trim() : 'TANPA NAMA TOKO';
      groupedMap.putIfAbsent(key, () => []).add(item);
    }

    final customerGroups = groupedMap.entries.map((entry) {
      final name = entry.key;
      final items = List<Receivable>.from(entry.value)
        ..sort((a, b) {
          if (a.tglKirim == null && b.tglKirim == null) return 0;
          if (a.tglKirim == null) return 1;
          if (b.tglKirim == null) return -1;
          return a.tglKirim!.compareTo(b.tglKirim!);
        });
      final city = items.firstWhere((r) => r.kota.isNotEmpty, orElse: () => items.first).kota;
      return CustomerGroup(customerName: name, city: city, items: items);
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12.0 : 20.0, vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Top Action Buttons
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kartu Piutang Toko',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Pencatatan Tagihan & Pelunasan Invoice Cabang',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              if (filteredRaw.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Tidak ada data piutang untuk di-download!'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              final custName = _selectedCustomerFilter == 'ALL' ? '' : _selectedCustomerFilter;
                              final city = filteredRaw.firstWhere((r) => r.kota.isNotEmpty, orElse: () => filteredRaw.first).kota;
                              await PrintService.downloadKartuPiutangPdf(
                                customerName: custName,
                                city: city,
                                items: filteredRaw,
                              );
                              if (mounted) {
                                final fname = PrintService.generateKartuPiutangFilename(customerName: custName);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('PDF $fname berhasil di-download!'), backgroundColor: Colors.teal),
                                );
                              }
                            },
                            icon: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
                            label: const Text(
                              'Download PDF',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              if (filteredRaw.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Tidak ada data piutang untuk dicetak!'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              final custName = _selectedCustomerFilter == 'ALL' ? '' : _selectedCustomerFilter;
                              final city = filteredRaw.firstWhere((r) => r.kota.isNotEmpty, orElse: () => filteredRaw.first).kota;
                              PrintService.printKartuPiutang(
                                customerName: custName,
                                city: city,
                                items: filteredRaw,
                              );
                            },
                            icon: const Icon(Icons.print_rounded, color: Colors.black, size: 16),
                            label: const Text(
                              'Cetak',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF38BDF8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showAddEditPiutangDialog(),
                            icon: const Icon(Icons.add_rounded, color: Colors.black, size: 18),
                            label: const Text('Tambah', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
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
                      children: const [
                        Text(
                          'Kartu Piutang Toko',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Pencatatan Tagihan & Pelunasan Invoice Cabang',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            if (filteredRaw.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tidak ada data piutang untuk di-download!'), backgroundColor: Colors.redAccent),
                              );
                              return;
                            }
                            final custName = _selectedCustomerFilter == 'ALL' ? '' : _selectedCustomerFilter;
                            final city = filteredRaw.firstWhere((r) => r.kota.isNotEmpty, orElse: () => filteredRaw.first).kota;
                            await PrintService.downloadKartuPiutangPdf(
                              customerName: custName,
                              city: city,
                              items: filteredRaw,
                            );
                            if (mounted) {
                              final fname = PrintService.generateKartuPiutangFilename(customerName: custName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('PDF $fname berhasil di-download!'), backgroundColor: Colors.teal),
                              );
                            }
                          },
                          icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                          label: Text(
                            _selectedCustomerFilter == 'ALL'
                                ? 'Download Semua Piutang'
                                : 'Download Piutang ($_selectedCustomerFilter)',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (filteredRaw.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tidak ada data piutang untuk dicetak!'), backgroundColor: Colors.redAccent),
                              );
                              return;
                            }
                            final custName = _selectedCustomerFilter == 'ALL' ? '' : _selectedCustomerFilter;
                            final city = filteredRaw.firstWhere((r) => r.kota.isNotEmpty, orElse: () => filteredRaw.first).kota;
                            PrintService.printKartuPiutang(
                              customerName: custName,
                              city: city,
                              items: filteredRaw,
                            );
                          },
                          icon: const Icon(Icons.print_rounded, color: Colors.black, size: 18),
                          label: Text(
                            _selectedCustomerFilter == 'ALL'
                                ? 'Cetak Semua Piutang'
                                : 'Cetak Piutang ($_selectedCustomerFilter)',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _showAddEditPiutangDialog(),
                          icon: const Icon(Icons.add_rounded, color: Colors.black),
                          label: const Text('Tambah Piutang', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
          const SizedBox(height: 12),

          // Total Summary KPI Cards (Scrollable on mobile)
          isMobile
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: _buildKpiCard(
                          title: 'Total Belum Lunas',
                          value: currencyFormatter.format(provider.totalUnpaid),
                          icon: Icons.pending_actions_rounded,
                          color: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 180,
                        child: _buildKpiCard(
                          title: 'Total Sudah Lunas',
                          value: currencyFormatter.format(provider.totalPaid),
                          icon: Icons.check_circle_outline_rounded,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 200,
                        child: _buildKpiCard(
                          title: 'Total Customer & Invoice',
                          value: '${customerGroups.length} Toko (${provider.receivables.length} Inv)',
                          icon: Icons.storefront_rounded,
                          color: const Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
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
                        title: 'Total Customer & Invoice',
                        value: '${customerGroups.length} Customer (${provider.receivables.length} Invoice)',
                        icon: Icons.storefront_rounded,
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 12),

          // Controls Bar (Search, Customer Filter, Status Filter)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Cari Toko / Kota / No Invoice...',
                          hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.filter_alt_rounded, color: Color(0xFF38BDF8), size: 16),
                                  const SizedBox(width: 6),
                                  DropdownButton<String>(
                                    value: _selectedCustomerFilter,
                                    underline: const SizedBox(),
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                    items: [
                                      const DropdownMenuItem(value: 'ALL', child: Text('Semua Customer / Toko')),
                                      ...uniqueCustomers.map((cust) {
                                        return DropdownMenuItem(value: cust, child: Text(cust));
                                      }),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedCustomerFilter = val);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'ALL', label: Text('Semua', style: TextStyle(fontSize: 11))),
                                ButtonSegment(value: 'UNPAID', label: Text('Belum Lunas', style: TextStyle(fontSize: 11))),
                                ButtonSegment(value: 'PAID', label: Text('Lunas', style: TextStyle(fontSize: 11))),
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
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Cari Toko / Kota / No Invoice...',
                            hintStyle: TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.filter_alt_rounded, color: Color(0xFF38BDF8), size: 18),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _selectedCustomerFilter,
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              items: [
                                const DropdownMenuItem(value: 'ALL', child: Text('Semua Customer / Toko')),
                                ...uniqueCustomers.map((cust) {
                                  return DropdownMenuItem(value: cust, child: Text(cust));
                                }),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedCustomerFilter = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
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
          const SizedBox(height: 10),

          // GROUPED CUSTOMER CARDS (Accordion / Expandable View)
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : customerGroups.isEmpty
                    ? const Center(child: Text('Tidak ada data piutang.', style: TextStyle(color: Color(0xFF94A3B8))))
                    : ListView.builder(
                        itemCount: customerGroups.length,
                        itemBuilder: (context, groupIdx) {
                          final group = customerGroups[groupIdx];
                          final isExpanded = _expandedCustomers.contains(group.customerName) || customerGroups.length == 1;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isExpanded ? const Color(0xFF38BDF8).withOpacity(0.5) : Colors.white.withOpacity(0.08),
                                width: isExpanded ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                // ==============================================
                                // CUSTOMER CARD HEADER (Ringkasan Customer)
                                // ==============================================
                                InkWell(
                                  borderRadius: isExpanded
                                      ? const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14))
                                      : BorderRadius.circular(14),
                                  onTap: () {
                                    setState(() {
                                      if (_expandedCustomers.contains(group.customerName)) {
                                        _expandedCustomers.remove(group.customerName);
                                      } else {
                                        _expandedCustomers.add(group.customerName);
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 10),
                                    child: Row(
                                      children: [
                                        // Customer Icon & Name & City
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF38BDF8).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.storefront_rounded, color: Color(0xFF38BDF8), size: 18),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    group.customerName,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                  if (group.city.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF334155),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        group.city.toUpperCase(),
                                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF38BDF8).withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      '${group.items.length} Inv',
                                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  if (group.unpaidCount > 0)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        '${group.unpaidCount} Belum Lunas',
                                                        style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  if (group.paidCount > 0)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.green.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        '${group.paidCount} Lunas',
                                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Total Amount & Buttons
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                const Text('Total Piutang:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                                                Text(
                                                  currencyFormatter.format(group.totalNominal),
                                                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.download_rounded, color: Colors.greenAccent, size: 20),
                                              tooltip: 'Download PDF Kartu Piutang ${group.customerName}',
                                              onPressed: () async {
                                                await PrintService.downloadKartuPiutangPdf(
                                                  customerName: group.customerName,
                                                  city: group.city,
                                                  items: group.items,
                                                );
                                                if (mounted) {
                                                  final fname = PrintService.generateKartuPiutangFilename(customerName: group.customerName);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('PDF $fname berhasil di-download!'), backgroundColor: Colors.teal),
                                                  );
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              icon: const Icon(Icons.print_rounded, color: Color(0xFF38BDF8), size: 20),
                                              tooltip: 'Cetak Kartu Piutang ${group.customerName}',
                                              onPressed: () {
                                                PrintService.printKartuPiutang(
                                                  customerName: group.customerName,
                                                  city: group.city,
                                                  items: group.items,
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                              color: const Color(0xFF94A3B8),
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // ==============================================
                                // EXPANDED DETAIL: KARTU PIUTANG UNTUK CUSTOMER INI
                                // ==============================================
                                if (isExpanded) ...[
                                  const Divider(color: Color(0xFF334155), height: 1),

                                  // KOP SURAT HEADER PER CUSTOMER
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                    color: const Color(0xFF0F172A),
                                    child: Column(
                                      children: [
                                        // Logo + Company Name
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/fiva_logo.png',
                                              width: 32,
                                              height: 32,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF38BDF8).withOpacity(0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.store_rounded, color: Color(0xFF38BDF8), size: 18),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'FIVA SOLO FOOD & MEAT SUPPLY',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                letterSpacing: 1.1,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // Title: KARTU PIUTANG - CUSTOMER NAME
                                        Container(
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'KARTU PIUTANG - ${group.customerName.toUpperCase()}${group.city.isNotEmpty ? " (${group.city.toUpperCase()})" : ""}',
                                            style: const TextStyle(
                                              color: Color(0xFF38BDF8),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // INVOICE TABLE FOR THIS CUSTOMER
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowHeight: 36,
                                      dataRowMaxHeight: 42,
                                      columnSpacing: isMobile ? 14 : 24,
                                      columns: const [
                                        DataColumn(label: Text('NO', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('NO INVOICE', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('TANGGAL KIRIM', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('NOMINAL', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('STATUS ERP', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('STATUS BAYAR', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                        DataColumn(label: Text('AKSI', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12))),
                                      ],
                                      rows: List.generate(group.items.length, (idx) {
                                        final item = group.items[idx];
                                        return DataRow(
                                          cells: [
                                            DataCell(Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 13))),
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(item.noInvoice, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13)),
                                                  if (item.isLocked) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: Colors.amberAccent, width: 0.8),
                                                      ),
                                                      child: const Text('LOCK 🔒', style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            DataCell(Text(item.tglKirim != null ? dateFormatter.format(item.tglKirim!) : '—', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                                            DataCell(Text(currencyFormatter.format(item.nominal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                            DataCell(
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: item.erpSyncDate != null ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFF64748B).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: item.erpSyncDate != null ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFF64748B).withOpacity(0.4),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      item.erpSyncDate != null ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                                                      size: 13,
                                                      color: item.erpSyncDate != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      item.erpSyncDate != null ? 'ERP: ${dateFormatter.format(item.erpSyncDate!)}' : 'Belum ERP',
                                                      style: TextStyle(
                                                        color: item.erpSyncDate != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              InkWell(
                                                onTap: () => _handleToggleLunas(context, provider, item),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: item.isLunas ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: item.isLunas ? Colors.greenAccent : Colors.redAccent),
                                                  ),
                                                  child: Text(
                                                    item.isLunas ? 'LUNAS' : 'BELUM LUNAS',
                                                    style: TextStyle(
                                                      color: item.isLunas ? Colors.greenAccent : Colors.redAccent,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
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
                                                    _showAddEditPiutangDialog(item);
                                                  } else if (value == 'delete') {
                                                    _confirmDeletePiutang(context, provider, item);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: const [
                                                        Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Edit Piutang', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: const [
                                                        Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Hapus Piutang', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  ),

                                  // FOOTER GRAND TOTAL UNTUK CUSTOMER INI
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: isMobile ? 10 : 16),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0F172A),
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: Radius.circular(14),
                                        bottomRight: Radius.circular(14),
                                      ),
                                    ),
                                    child: isMobile
                                        ? Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'GRAND TOTAL (${group.customerName.toUpperCase()}) :',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11,
                                                        letterSpacing: 0.5,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      currencyFormatter.format(group.totalNominal),
                                                      style: const TextStyle(
                                                        color: Color(0xFF38BDF8),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.teal,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      ),
                                                      onPressed: () async {
                                                        await PrintService.downloadKartuPiutangPdf(
                                                          customerName: group.customerName,
                                                          city: group.city,
                                                          items: group.items,
                                                        );
                                                        if (mounted) {
                                                          final fname = PrintService.generateKartuPiutangFilename(customerName: group.customerName);
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(content: Text('PDF $fname berhasil di-download!'), backgroundColor: Colors.teal),
                                                          );
                                                        }
                                                      },
                                                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 15),
                                                      label: const Text(
                                                        'Download PDF',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF38BDF8),
                                                        foregroundColor: Colors.black,
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                      ),
                                                      onPressed: () {
                                                        PrintService.printKartuPiutang(
                                                          customerName: group.customerName,
                                                          city: group.city,
                                                          items: group.items,
                                                        );
                                                      },
                                                      icon: const Icon(Icons.print_rounded, color: Colors.black, size: 15),
                                                      label: const Text(
                                                        'Cetak',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.teal,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    onPressed: () async {
                                                      await PrintService.downloadKartuPiutangPdf(
                                                        customerName: group.customerName,
                                                        city: group.city,
                                                        items: group.items,
                                                      );
                                                      if (mounted) {
                                                        final fname = PrintService.generateKartuPiutangFilename(customerName: group.customerName);
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text('PDF $fname berhasil di-download!'), backgroundColor: Colors.teal),
                                                        );
                                                      }
                                                    },
                                                    icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                                                    label: Text(
                                                      'Download PDF (${group.customerName})',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  ElevatedButton.icon(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF38BDF8),
                                                      foregroundColor: Colors.black,
                                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    onPressed: () {
                                                      PrintService.printKartuPiutang(
                                                        customerName: group.customerName,
                                                        city: group.city,
                                                        items: group.items,
                                                      );
                                                    },
                                                    icon: const Icon(Icons.print_rounded, color: Colors.black, size: 18),
                                                    label: Text(
                                                      'Cetak Kartu (${group.customerName})',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    'GRAND TOTAL (${group.customerName.toUpperCase()}) :',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      currencyFormatter.format(group.totalNominal),
                                                      style: const TextStyle(
                                                        color: Color(0xFF38BDF8),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleToggleLunas(BuildContext context, ReceivableProvider provider, Receivable item) async {
    if (!item.isLunas) {
      DateTime chosenDate = DateTime.now();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pelunasan Invoice #${item.noInvoice}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Toko: ${item.toko}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Nominal Tagihan: ${currencyFormatter.format(item.nominal)}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tanggal Pelunasan / Transfer:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: chosenDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDlgState(() => chosenDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateFormatter.format(chosenDate),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Tandai Lunas ✅', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      );

      if (confirmed == true) {
        await provider.markLunasWithDate(item.id, item.noInvoice, true, chosenDate);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invoice #${item.noInvoice} berhasil ditandai LUNAS.'),
              backgroundColor: Colors.teal,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Kembalikan ke Belum Lunas?', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text(
            'Status invoice #${item.noInvoice} (${item.toko}) akan diubah kembali menjadi BELUM LUNAS (UNPAID).',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, Kembalikan ke UNPAID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await provider.markLunasWithDate(item.id, item.noInvoice, false, null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invoice #${item.noInvoice} dikembalikan ke status BELUM LUNAS.'),
              backgroundColor: Colors.orange[800],
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _confirmDeletePiutang(BuildContext context, ReceivableProvider provider, Receivable item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Piutang', style: TextStyle(color: Colors.white)),
        content: Text(
          'Apakah Anda yakin ingin menghapus piutang invoice "${item.noInvoice}" (${item.toko})?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await provider.deleteReceivable(item.id);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
