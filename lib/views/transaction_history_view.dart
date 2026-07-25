import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../models/transaction.dart' as model_tr;
import '../models/product.dart';
import '../models/customer.dart';
import '../providers/transaction_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/auth_provider.dart';
import '../services/print_service.dart';
import '../services/import_service.dart';
import '../services/firebase_service.dart';
import 'package:printing/printing.dart';
import 'transaction_entry_view.dart';

class TransactionHistoryView extends StatefulWidget {
  const TransactionHistoryView({super.key});

  @override
  State<TransactionHistoryView> createState() => _TransactionHistoryViewState();
}

class _TransactionHistoryViewState extends State<TransactionHistoryView> {
  final _searchController = TextEditingController();
  String _searchQuery = "";
  String _statusFilter = "SEMUA"; // SEMUA, PAID, UNPAID, DIKIRIM, PENDING
  String _monthFilter = "SEMUA"; // SEMUA or "07-2026", "06-2026", etc.
  String _productFilter = "SEMUA"; // SEMUA or selected product name
  bool _showRightSummaryPanel = false;
  String _summaryProductSearch = "";

  // Pagination & Debounce State
  int _currentPage = 1;
  int _rowsPerPage = 25;
  Timer? _debounce;

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  List<String> _getMonthFilterOptions(List<model_tr.Transaction> transactions) {
    final Set<String> months = {};
    for (var tr in transactions) {
      final effectiveDate = tr.deliveryDate ?? tr.date;
      months.add(DateFormat('MM-yyyy').format(effectiveDate));
    }

    final now = DateTime.now();
    for (int y = now.year + 1; y >= 2025; y--) {
      for (int m = 12; m >= 1; m--) {
        if (y == 2025 && m < 4) continue; // Start from April 2025
        final mStr = m.toString().padLeft(2, '0');
        months.add('$mStr-$y');
      }
    }

    final list = months.toList();
    list.sort((a, b) {
      final partsA = a.split('-');
      final partsB = b.split('-');
      if (partsA.length == 2 && partsB.length == 2) {
        final yearA = int.tryParse(partsA[1]) ?? 0;
        final yearB = int.tryParse(partsB[1]) ?? 0;
        if (yearA != yearB) return yearB.compareTo(yearA);
        final monthA = int.tryParse(partsA[0]) ?? 0;
        final monthB = int.tryParse(partsB[0]) ?? 0;
        return monthB.compareTo(monthA);
      }
      return b.compareTo(a);
    });
    return ["SEMUA", ...list];
  }

  void _showSearchableProductFilterDialog(List<String> productNames) {
    showDialog(
      context: context,
      builder: (ctx) {
        String tempSearch = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredList = productNames.where((p) {
              if (tempSearch.isEmpty) return true;
              return p.toLowerCase().contains(tempSearch.toLowerCase().trim());
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.shopping_bag_rounded, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 8),
                  Text('Filter Nama Produk', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 420,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ketik nama produk...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          tempSearch = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(4),
                          children: [
                            ListTile(
                              dense: true,
                              selected: _productFilter == "SEMUA",
                              selectedTileColor: const Color(0xFF38BDF8).withOpacity(0.15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              leading: const Icon(Icons.apps_rounded, color: Color(0xFF38BDF8), size: 16),
                              title: const Text(
                                'SEMUA PRODUK',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onTap: () {
                                setState(() {
                                  _productFilter = "SEMUA";
                                  _currentPage = 1;
                                });
                                Navigator.pop(ctx);
                              },
                            ),
                            const Divider(color: Color(0xFF1E293B), height: 1),
                            ...filteredList.map((pName) {
                              final isSel = _productFilter.toLowerCase() == pName.toLowerCase();
                              return ListTile(
                                dense: true,
                                selected: isSel,
                                selectedTileColor: const Color(0xFF38BDF8).withOpacity(0.15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                title: Text(
                                  pName,
                                  style: TextStyle(
                                    color: isSel ? const Color(0xFF38BDF8) : Colors.white,
                                    fontSize: 12,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _productFilter = pName;
                                    _currentPage = 1;
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            }).toList(),
                          ],
                        ),
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
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importTransactionsFromExcel(String createdBy) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null) return;
      final bytes = result.files.single.bytes ??
          (result.files.single.path != null ? await File(result.files.single.path!).readAsBytes() : null);
      if (bytes == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
        ),
      );

      final importResult = await ImportService().importTransactions(bytes, createdBy);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      // Show result dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Hasil Import Transaksi', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Baris data: ${importResult.totalRows}', style: const TextStyle(color: Colors.white)),
                Text('Sukses (Invoice): ${importResult.successCount}', style: const TextStyle(color: Colors.greenAccent)),
                Text('Gagal: ${importResult.errorCount}', style: const TextStyle(color: Colors.redAccent)),
                if (importResult.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Rincian Error:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        importResult.errors.join('\n'),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimport: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showEditTransactionDialog(model_tr.Transaction tr) {
    final customers = Provider.of<CustomerProvider>(context, listen: false).customers;
    final products = Provider.of<ProductProvider>(context, listen: false).products;

    Customer? selectedCustomer;
    try {
      selectedCustomer = customers.firstWhere((c) => c.id == tr.customerId);
    } catch (_) {}

    DateTime deliveryDate = tr.deliveryDate ?? tr.date;
    final noteController = TextEditingController(text: tr.note);
    List<model_tr.TransactionItem> editedItems = List.from(tr.items);

    Product? selectedProduct;
    final qtyController = TextEditingController(text: '1');
    final discountController = TextEditingController(text: '0');
    final priceController = TextEditingController();
    bool isBonus = false;
    int? editingItemIndex;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double grandTotal = editedItems.fold(0.0, (sum, item) => sum + item.subtotal);

            void selectItemForEditing(int index) {
              final item = editedItems[index];
              Product? foundProduct;
              try {
                foundProduct = products.firstWhere((p) => p.id == item.productId);
              } catch (_) {
                foundProduct = Product(
                  id: item.productId,
                  name: item.productName,
                  sizeGrams: item.sizeGrams,
                  price: item.price,
                  stock: 0,
                  isiKarton: 0,
                );
              }

              setDialogState(() {
                editingItemIndex = index;
                selectedProduct = foundProduct;
                priceController.text = item.price.toStringAsFixed(0);
                qtyController.text = item.qty.toStringAsFixed(0);
                discountController.text = item.discountPercent.toStringAsFixed(1);
                isBonus = item.isBonus;
              });
            }

            void cancelItemEditing() {
              setDialogState(() {
                editingItemIndex = null;
                selectedProduct = null;
                qtyController.text = '1';
                discountController.text = '0';
                priceController.clear();
                isBonus = false;
              });
            }

            void addItem() {
              if (selectedProduct == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pilih produk terlebih dahulu!'), backgroundColor: Colors.orange),
                );
                return;
              }

              final qty = double.tryParse(qtyController.text) ?? 0.0;
              if (qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Qty harus lebih dari 0!'), backgroundColor: Colors.orange),
                );
                return;
              }

              final discount = double.tryParse(discountController.text) ?? 0.0;
              final customPrice = double.tryParse(priceController.text);
              final finalPrice = isBonus ? 0.0 : (customPrice ?? selectedProduct!.price);
              final subtotal = isBonus ? 0.0 : qty * finalPrice * (1 - discount / 100);

              if (editingItemIndex != null && editingItemIndex! < editedItems.length) {
                // Update existing item
                setDialogState(() {
                  editedItems[editingItemIndex!] = model_tr.TransactionItem(
                    productId: selectedProduct!.id,
                    productName: selectedProduct!.name,
                    price: finalPrice,
                    qty: qty,
                    discountPercent: isBonus ? 0 : discount,
                    subtotal: subtotal,
                    sizeGrams: selectedProduct!.sizeGrams,
                    isBonus: isBonus,
                  );
                  editingItemIndex = null;
                  selectedProduct = null;
                  qtyController.text = '1';
                  discountController.text = '0';
                  priceController.clear();
                  isBonus = false;
                });
                return;
              }

              final existingIndex = editedItems.indexWhere((item) => item.productId == selectedProduct!.id && item.isBonus == isBonus);
              if (existingIndex != -1) {
                final currentQty = editedItems[existingIndex].qty;
                final newQty = currentQty + qty;
                final newSubtotal = isBonus ? 0.0 : newQty * finalPrice * (1 - discount / 100);

                setDialogState(() {
                  editedItems[existingIndex] = model_tr.TransactionItem(
                    productId: selectedProduct!.id,
                    productName: selectedProduct!.name,
                    price: finalPrice,
                    qty: newQty,
                    discountPercent: isBonus ? 0 : discount,
                    subtotal: newSubtotal,
                    sizeGrams: selectedProduct!.sizeGrams,
                    isBonus: isBonus,
                  );
                });
              } else {
                if (editedItems.length >= 14) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      title: const Text('Batas Item Terpenuhi', style: TextStyle(color: Colors.white)),
                      content: const Text('Batas Maksimal 14 item produk berbeda per lembar invoice ( Continuous Form ) tercapai!', style: TextStyle(color: Color(0xFF94A3B8))),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
                        ),
                      ],
                    ),
                  );
                  return;
                }

                setDialogState(() {
                  editedItems.add(
                    model_tr.TransactionItem(
                      productId: selectedProduct!.id,
                      productName: selectedProduct!.name,
                      price: finalPrice,
                      qty: qty,
                      discountPercent: isBonus ? 0 : discount,
                      subtotal: subtotal,
                      sizeGrams: selectedProduct!.sizeGrams,
                      isBonus: isBonus,
                    ),
                  );
                });
              }

              // Clear product picker inputs
              cancelItemEditing();
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Edit Transaksi #${tr.invoiceNo}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 980,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Form Panel
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Data Transaksi:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 10),
                            SearchableCustomerField(
                              selectedCustomer: selectedCustomer,
                              customers: customers,
                              onSelected: (c) {
                                setDialogState(() {
                                  selectedCustomer = c;
                                });
                              },
                            ),
                            if (selectedCustomer != null) ...[
                              const SizedBox(height: 8),
                              _buildDetailRow('ID Customer', selectedCustomer!.id),
                              _buildDetailRow('Alamat', selectedCustomer!.address),
                              _buildDetailRow('Kota/Provinsi', '${selectedCustomer!.city}, ${selectedCustomer!.province}'),
                            ],
                            const SizedBox(height: 12),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Tanggal Pengiriman:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                              subtitle: Text(
                                DateFormat('dd MMMM yyyy').format(deliveryDate),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8), size: 18),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: deliveryDate,
                                  firstDate: DateTime(2025),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    deliveryDate = picked;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: noteController,
                              maxLines: 2,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: _buildInputDecoration(hint: 'Catatan / Keterangan...'),
                            ),
                            const SizedBox(height: 16),
                            const Divider(color: Color(0xFF334155)),
                            const SizedBox(height: 10),
                            const Text('Pilih & Tambah Produk:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 10),
                            SearchableProductField(
                              selectedProduct: selectedProduct,
                              products: products,
                              onSelected: (p) {
                                setDialogState(() {
                                  selectedProduct = p;
                                  if (p != null) {
                                    priceController.text = p.price.toStringAsFixed(0);
                                  } else {
                                    priceController.clear();
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedProduct != null
                                      ? 'Harga Master: ${_rupiahFormatter.format(selectedProduct!.price)}'
                                      : 'Harga Master: Rp 0',
                                  style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                Text(
                                  selectedProduct != null
                                      ? 'Stok: ${selectedProduct!.stock.toStringAsFixed(0)} pcs'
                                      : 'Stok: -',
                                  style: TextStyle(
                                    color: (selectedProduct != null && selectedProduct!.stock <= 0) ? Colors.redAccent : Colors.greenAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: _buildInputDecoration(hint: 'Harga Transaksi (Rp)', icon: Icons.payments_outlined),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: qtyController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: _buildInputDecoration(hint: 'Qty (Pcs)', icon: Icons.numbers),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: discountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: _buildInputDecoration(hint: 'Diskon %', icon: Icons.percent),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  isBonus = !isBonus;
                                  if (isBonus) {
                                    priceController.text = '0';
                                    discountController.text = '0';
                                  } else if (selectedProduct != null) {
                                    priceController.text = selectedProduct!.price.toStringAsFixed(0);
                                    discountController.text = '0';
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isBonus ? Colors.green.withOpacity(0.15) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isBonus ? Colors.greenAccent : const Color(0xFF334155),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isBonus ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                      color: isBonus ? Colors.greenAccent : const Color(0xFF64748B),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'BONUS (Gratis / Harga Rp 0)',
                                      style: TextStyle(
                                        color: isBonus ? Colors.greenAccent : const Color(0xFF94A3B8),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                             const SizedBox(height: 14),
                             if (editingItemIndex != null) ...[
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                 decoration: BoxDecoration(
                                   color: const Color(0xFF451A03),
                                   borderRadius: BorderRadius.circular(8),
                                   border: Border.all(color: Colors.amberAccent, width: 1.5),
                                 ),
                                 child: Row(
                                   children: [
                                     const Icon(Icons.edit_rounded, color: Colors.amberAccent, size: 18),
                                     const SizedBox(width: 8),
                                     Expanded(
                                       child: Text(
                                         'Sedang Mengedit Item #${editingItemIndex! + 1}',
                                         style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w900),
                                       ),
                                     ),
                                     InkWell(
                                       onTap: cancelItemEditing,
                                       child: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                         decoration: BoxDecoration(
                                           color: Colors.red[900],
                                           borderRadius: BorderRadius.circular(6),
                                           border: Border.all(color: Colors.redAccent),
                                         ),
                                         child: const Text(
                                           '✕ Batal Edit',
                                           style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                         ),
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                               const SizedBox(height: 8),
                             ],
                             ElevatedButton.icon(
                               onPressed: addItem,
                               icon: Icon(editingItemIndex != null ? Icons.save_rounded : Icons.add_rounded, size: 18, color: Colors.white),
                               label: Text(
                                 editingItemIndex != null
                                     ? 'Simpan Perubahan Item'
                                     : (isBonus ? 'Tambah Bonus ke Invoice' : 'Tambah ke Invoice'),
                                 style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
                               ),
                               style: ElevatedButton.styleFrom(
                                 minimumSize: const Size.fromHeight(44),
                                 backgroundColor: editingItemIndex != null
                                     ? const Color(0xFFD97706)
                                     : (isBonus ? Colors.green[700] : const Color(0xFF0284C7)),
                               ),
                             ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Right Table Panel
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Daftar Item:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                '${editedItems.length} / 14 Item',
                                style: TextStyle(
                                  color: editedItems.length >= 14 ? Colors.redAccent : const Color(0xFF38BDF8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: editedItems.isEmpty
                                  ? const Center(child: Text('Belum ada item', style: TextStyle(color: Color(0xFF64748B))))
                                  : SingleChildScrollView(
                                      child: Table(
                                        columnWidths: const {
                                          0: FlexColumnWidth(2.3),
                                          1: FlexColumnWidth(0.7),
                                          2: FlexColumnWidth(1.2),
                                          3: FlexColumnWidth(1.2),
                                          4: FlexColumnWidth(0.9),
                                        },
                                        children: [
                                          TableRow(
                                            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                                            children: [
                                              _buildTableCell('Nama Barang', isHeader: true),
                                              _buildTableCell('Qty', isHeader: true, align: TextAlign.center),
                                              _buildTableCell('Harga', isHeader: true, align: TextAlign.right),
                                              _buildTableCell('Subtotal', isHeader: true, align: TextAlign.right),
                                              _buildTableCell('Aksi', isHeader: true, align: TextAlign.center),
                                            ],
                                          ),
                                          ...editedItems.asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final item = entry.value;
                                            final isEditing = (editingItemIndex == index);

                                            return TableRow(
                                              decoration: BoxDecoration(
                                                color: isEditing ? Colors.amber.withOpacity(0.15) : null,
                                              ),
                                              children: [
                                                InkWell(
                                                  onTap: () => selectItemForEditing(index),
                                                  child: _buildTableCell('${item.productName}${item.isBonus ? " (BONUS)" : ""}\n(${item.weightKg.toStringAsFixed(2)} kg)'),
                                                ),
                                                InkWell(
                                                  onTap: () => selectItemForEditing(index),
                                                  child: _buildTableCell(item.qty.toStringAsFixed(0), align: TextAlign.center),
                                                ),
                                                InkWell(
                                                  onTap: () => selectItemForEditing(index),
                                                  child: _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price), align: TextAlign.right),
                                                ),
                                                InkWell(
                                                  onTap: () => selectItemForEditing(index),
                                                  child: _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal), align: TextAlign.right, isBold: true),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      IconButton(
                                                        icon: Icon(Icons.edit_outlined, color: isEditing ? Colors.amberAccent : Colors.cyanAccent, size: 16),
                                                        tooltip: 'Edit Item Ini',
                                                        onPressed: () => selectItemForEditing(index),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                                        tooltip: 'Hapus Item',
                                                        onPressed: () {
                                                          setDialogState(() {
                                                            if (editingItemIndex == index) {
                                                              cancelItemEditing();
                                                            } else if (editingItemIndex != null && editingItemIndex! > index) {
                                                              editingItemIndex = editingItemIndex! - 1;
                                                            }
                                                            editedItems.removeAt(index);
                                                          });
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL AKHIR:', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                _rupiahFormatter.format(grandTotal),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
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
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: selectedCustomer == null || editedItems.isEmpty
                      ? null
                      : () async {
                          try {
                            final updatedTransaction = model_tr.Transaction(
                              invoiceNo: tr.invoiceNo,
                              customerId: selectedCustomer!.id,
                              customerName: selectedCustomer!.customerName,
                              aliasName: selectedCustomer!.aliasName,
                              date: tr.date,
                              deliveryDate: deliveryDate,
                              city: selectedCustomer!.city,
                              province: selectedCustomer!.province,
                              country: selectedCustomer!.country,
                              items: editedItems,
                              grandTotal: grandTotal,
                              note: noteController.text.trim(),
                              status: tr.status,
                              statusTransfer: tr.statusTransfer,
                              transferDate: tr.transferDate,
                              erpSyncDate: tr.erpSyncDate,
                              createdBy: tr.createdBy,
                              createdAt: tr.createdAt,
                            );

                            await Provider.of<TransactionProvider>(context, listen: false).updateTransaction(updatedTransaction);

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Transaksi berhasil diperbarui.'), backgroundColor: Colors.teal),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal memperbarui: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        },
                  child: const Text('Simpan Perubahan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, String> _resolveCustomerDisplay(model_tr.Transaction tr, List<Customer> masterCustomers) {
    String storeName = tr.aliasName.trim();
    String ownerName = tr.customerName.trim();

    if (ownerName.isEmpty || ownerName.toUpperCase() == storeName.toUpperCase()) {
      Customer? matched;
      if (tr.customerId.isNotEmpty) {
        try {
          matched = masterCustomers.firstWhere((c) => c.id == tr.customerId);
        } catch (_) {}
      }
      if (matched == null && storeName.isNotEmpty) {
        try {
          matched = masterCustomers.firstWhere((c) => c.aliasName.trim().toUpperCase() == storeName.toUpperCase());
        } catch (_) {}
      }
      if (matched == null && storeName.isNotEmpty) {
        try {
          matched = masterCustomers.firstWhere((c) => c.customerName.trim().toUpperCase() == storeName.toUpperCase());
        } catch (_) {}
      }

      if (matched != null) {
        if (storeName.isEmpty && matched.aliasName.trim().isNotEmpty) {
          storeName = matched.aliasName.trim();
        }
        if (matched.customerName.trim().isNotEmpty && matched.customerName.trim().toUpperCase() != storeName.toUpperCase()) {
          ownerName = matched.customerName.trim();
        }
      }
    }

    final hasStore = storeName.isNotEmpty;
    final hasOwner = ownerName.isNotEmpty && ownerName.toUpperCase() != storeName.toUpperCase();

    final firstLine = hasStore ? storeName : (hasOwner ? ownerName : '-');
    final secondLine = (hasStore && hasOwner) ? '($ownerName)' : '';
    final fullDisplay = (hasStore && hasOwner) ? '$storeName ($ownerName)' : firstLine;

    return {
      'firstLine': firstLine,
      'secondLine': secondLine,
      'fullDisplay': fullDisplay,
    };
  }

  Future<void> _handlePrintOrDownloadPdf(model_tr.Transaction tr, {bool isDownload = false}) async {
    try {
      final masterCustomers = Provider.of<CustomerProvider>(context, listen: false).customers;
      Customer? c;
      try {
        c = masterCustomers.firstWhere((cust) => cust.id == tr.customerId);
      } catch (_) {}

      final toPrint = model_tr.Transaction(
        invoiceNo: tr.invoiceNo,
        customerId: tr.customerId,
        customerName: tr.customerName,
        aliasName: (c != null && c.aliasName.isNotEmpty) ? c.aliasName : tr.customerName,
        date: tr.date,
        deliveryDate: tr.deliveryDate,
        city: (c != null && c.city.isNotEmpty) ? c.city : tr.city,
        province: (c != null && c.province.isNotEmpty) ? c.province : tr.province,
        country: (c != null && c.country.isNotEmpty) ? c.country : tr.country,
        items: tr.items,
        grandTotal: tr.grandTotal,
        note: tr.note,
        status: tr.status,
        statusTransfer: tr.statusTransfer,
        transferDate: tr.transferDate,
        erpSyncDate: tr.erpSyncDate,
        createdBy: tr.createdBy,
        createdAt: tr.createdAt,
      );

      if (isDownload) {
        final pdf = await PrintService.buildInvoiceDocument(toPrint);
        final bytes = await pdf.save();
        final String filename = PrintService.generateInvoiceFilename(toPrint);
        
        await Printing.sharePdf(bytes: bytes, filename: filename);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF $filename berhasil di-download!'),
              backgroundColor: Colors.teal,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await PrintService.printInvoice(toPrint);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF Invoice #${toPrint.invoiceNo} siap dicetak!'),
              backgroundColor: Colors.teal,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak / download: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // Show detailed item list in dialog
  void _showDetailDialog(model_tr.Transaction tr) {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final isKacab = user?.isKacab ?? false;
    final masterCustomers = Provider.of<CustomerProvider>(context, listen: false).customers;
    final customerInfo = _resolveCustomerDisplay(tr, masterCustomers);
    final isMobile = MediaQuery.of(context).size.width < 600;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.all(isMobile ? 14 : 22),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Detail Invoice #${tr.invoiceNo}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          content: SizedBox(
            width: isMobile ? double.maxFinite : 900,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Information Header Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    children: [
                      if (isMobile) ...[
                        _buildDetailRow('Pelanggan:', customerInfo['fullDisplay']!),
                        const SizedBox(height: 6),
                        _buildDetailRow('Kota/Provinsi:', '${tr.city}, ${tr.province}'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('Status Kirim:', tr.status, isBadge: true)),
                            Expanded(child: _buildDetailRow('Status Bayar:', tr.statusTransfer, isBadge: true)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: Color(0xFF1E293B)),
                        const SizedBox(height: 6),
                        _buildDetailRow('Tgl Invoice:', DateFormat('dd-MM-yyyy').format(tr.date)),
                        const SizedBox(height: 6),
                        _buildDetailRow('Tgl Kirim:', (tr.status == 'DIKIRIM' && tr.deliveryDate != null) ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-'),
                        if (tr.statusTransfer == 'PAID' && tr.transferDate != null) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow('Tgl PAID:', DateFormat('dd-MM-yyyy').format(tr.transferDate!)),
                        ],
                        if (tr.erpSyncDate != null) ...[
                          const SizedBox(height: 6),
                          _buildDetailRow('Tgl ERP:', DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!)),
                        ],
                      ] else ...[
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('Pelanggan:', customerInfo['fullDisplay']!)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDetailRow('Kota/Provinsi:', '${tr.city}, ${tr.province}')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('Status Kirim:', tr.status, isBadge: true)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDetailRow('Status Bayar:', tr.statusTransfer, isBadge: true)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(color: Color(0xFF1E293B)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('Tgl Invoice:', DateFormat('dd-MM-yyyy').format(tr.date))),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDetailRow('Tgl Kirim:', (tr.status == 'DIKIRIM' && tr.deliveryDate != null) ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-')),
                          ],
                        ),
                        if ((tr.statusTransfer == 'PAID' && tr.transferDate != null) || tr.erpSyncDate != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (tr.statusTransfer == 'PAID' && tr.transferDate != null)
                                Expanded(child: _buildDetailRow('Tgl PAID:', DateFormat('dd-MM-yyyy').format(tr.transferDate!)))
                              else
                                const Spacer(),
                              const SizedBox(width: 16),
                              if (tr.erpSyncDate != null)
                                Expanded(child: _buildDetailRow('Tgl ERP:', DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!)))
                              else
                                const Spacer(),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                
                // Section Label with Item Counter Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Daftar Barang:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${tr.items.length} Item',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Table Container with Internal Scroll (ONLY THIS TABLE SCROLLS!)
                Flexible(
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(maxHeight: isMobile ? 260 : 320),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        padding: const EdgeInsets.only(bottom: 10),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                child: Table(
                                  columnWidths: isMobile
                                      ? const {
                                          0: FixedColumnWidth(210),
                                          1: FixedColumnWidth(55),
                                          2: FixedColumnWidth(95),
                                          3: FixedColumnWidth(105),
                                          4: FixedColumnWidth(65),
                                          5: FixedColumnWidth(100),
                                          6: FixedColumnWidth(130),
                                        }
                                      : const {
                                          0: FlexColumnWidth(2.6), // Nama Barang (Spacious)
                                          1: FlexColumnWidth(0.7), // Qty
                                          2: FlexColumnWidth(1.1), // Harga Unit
                                          3: FlexColumnWidth(1.2), // Total
                                          4: FlexColumnWidth(0.8), // Disc %
                                          5: FlexColumnWidth(1.1), // Disc Rp
                                          6: FlexColumnWidth(1.4), // Subtotal
                                        },
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                                      children: [
                                        _buildTableCell('Nama Barang', isHeader: true),
                                        _buildTableCell('Qty', isHeader: true, align: TextAlign.center),
                                        _buildTableCell('Harga Unit', isHeader: true, align: TextAlign.right),
                                        _buildTableCell('Total', isHeader: true, align: TextAlign.right),
                                        _buildTableCell('Disc (%)', isHeader: true, align: TextAlign.center),
                                        _buildTableCell('Disc (Rp)', isHeader: true, align: TextAlign.right),
                                        _buildTableCell('Subtotal', isHeader: true, align: TextAlign.right),
                                      ],
                                    ),
                                    ...tr.items.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final item = entry.value;
                                      final totalBeforeDisc = item.isBonus ? 0.0 : item.qty * item.price;
                                      final discRp = item.isBonus ? 0.0 : totalBeforeDisc * (item.discountPercent / 100);
                                      final isEven = index % 2 == 0;

                                      return TableRow(
                                        decoration: BoxDecoration(
                                          color: isEven ? Colors.transparent : Colors.white.withOpacity(0.02),
                                          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
                                        ),
                                        children: [
                                          _buildTableCell('${item.productName}${item.isBonus ? " (BONUS)" : ""}\n(${item.weightKg.toStringAsFixed(2)} kg)'),
                                          _buildTableCell(item.qty.toStringAsFixed(0), align: TextAlign.center),
                                          _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price), align: TextAlign.right),
                                          _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(totalBeforeDisc), align: TextAlign.right),
                                          _buildTableCell(item.isBonus ? '-' : (item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(1)}%' : '-'), align: TextAlign.center),
                                          _buildTableCell(item.isBonus ? '-' : (discRp > 0 ? _rupiahFormatter.format(discRp) : '-'), align: TextAlign.right),
                                          _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal), align: TextAlign.right, isBold: true),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Bottom Summary Footer (Catatan & Highlighted GRAND TOTAL) - PINNED AT BOTTOM!
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tr.note.isNotEmpty) ...[
                        const Row(
                          children: [
                            Icon(Icons.sticky_note_2_outlined, color: Color(0xFF38BDF8), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Catatan / Keterangan:',
                              style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                          ),
                          child: SelectableText(
                            tr.note,
                            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (tr.note.isEmpty)
                            const Text(
                              'Catatan: -',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontStyle: FontStyle.italic),
                            )
                          else
                            const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('GRAND TOTAL: ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(
                                _rupiahFormatter.format(tr.grandTotal),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (isMobile) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (!isKacab) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showEditTransactionDialog(tr);
                            },
                            icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
                            label: const Text('Edit Transaksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handlePrintOrDownloadPdf(tr, isDownload: true),
                          icon: const Icon(Icons.download_rounded, color: Colors.redAccent, size: 18),
                          label: const Text('Download PDF', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                          onPressed: () => _handlePrintOrDownloadPdf(tr, isDownload: false),
                          icon: const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                          label: const Text('Cetak / Print', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              )
            ] else ...[
              if (!isKacab) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showEditTransactionDialog(tr);
                  },
                  icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 18),
                  label: const Text('Edit Transaksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showMoveInvoiceItemsDialog(tr);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded, color: Colors.cyanAccent, size: 18),
                  label: const Text('Pindah / Gabung Item', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => _handlePrintOrDownloadPdf(tr, isDownload: true),
                icon: const Icon(Icons.download_rounded, color: Colors.redAccent, size: 18),
                label: const Text('Download PDF', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _handlePrintOrDownloadPdf(tr, isDownload: false),
                icon: const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                label: const Text('Cetak / Print', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showInsufficientStockWarningDialog(BuildContext context, String rawError) {
    final String cleanMessage = rawError.replaceAll("Exception: ", "").replaceAll("STOK_TIDAK_CUKUP:\n", "").trim();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'TIDAK BISA UPDATE STATUS PENGIRIMAN',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Stok fisik di Master Barang tidak mencukupi untuk melakukan pengiriman transaksi ini:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Text(
                  cleanMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Harap perbarui stok di menu Master Barang / Input Stok terlebih dahulu!',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // Update delivery status (DIKIRIM / PENDING) & delivery date dialog
  void _showUpdateDeliveryStatusDialog(model_tr.Transaction tr) {
    String currentDeliveryStatus = tr.status; // 'DIKIRIM', 'PENDING'
    DateTime currentDeliveryDate = tr.deliveryDate ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Update Status Pengiriman #${tr.invoiceNo}', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih Status Barang Delivered & Tanggal Dikirim:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: currentDeliveryStatus,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(hint: 'Status Pengiriman'),
                    items: const [
                      DropdownMenuItem(value: 'DIKIRIM', child: Text('DIKIRIM (Stok Berkurang)')),
                      DropdownMenuItem(value: 'PENDING', child: Text('PENDING (Belum Dikirim)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          currentDeliveryStatus = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tanggal Dikirim:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    subtitle: Text(
                      DateFormat('dd MMMM yyyy').format(currentDeliveryDate),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: currentDeliveryDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (pickedDate != null) {
                        setDialogState(() {
                          currentDeliveryDate = pickedDate;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentDeliveryStatus == 'DIKIRIM'
                                ? 'Status DIKIRIM akan otomatis mengurangi stok barang pada database produk.'
                                : 'Status PENDING mengembalikan stok barang ke database produk.',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () async {
                    try {
                      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
                      await trProvider.updateDeliveryStatus(tr.invoiceNo, currentDeliveryStatus, currentDeliveryDate);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Status pengiriman & stok berhasil diperbarui.'), backgroundColor: Colors.teal),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        String errStr = e.toString();
                        try {
                          final dyn = e as dynamic;
                          if (dyn.error != null) {
                            errStr += " ${dyn.error}";
                          }
                          if (dyn.message != null) {
                            errStr += " ${dyn.message}";
                          }
                        } catch (_) {}

                        if (errStr.contains("STOK_TIDAK_CUKUP")) {
                          _showInsufficientStockWarningDialog(context, errStr);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gagal mengupdate status: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Update payment transfer status dialog
  void _showUpdateStatusDialog(model_tr.Transaction tr) {
    String currentStatus = tr.statusTransfer;
    DateTime? currentTransferDate = tr.transferDate ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Update Pembayaran #${tr.invoiceNo}', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: currentStatus,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(hint: 'Status Transfer'),
                    items: const [
                      DropdownMenuItem(value: 'UNPAID', child: Text('UNPAID (Belum Bayar)')),
                      DropdownMenuItem(value: 'PAID', child: Text('PAID (Lunas)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          currentStatus = val;
                        });
                      }
                    },
                  ),
                  if (currentStatus == 'PAID') ...[
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tanggal Transfer / Dibayar:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      subtitle: Text(
                        DateFormat('dd MMMM yyyy HH:mm').format(currentTransferDate!),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: currentTransferDate ?? DateTime.now(),
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          if (context.mounted) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(currentTransferDate!),
                            );
                            if (pickedTime != null) {
                              setDialogState(() {
                                currentTransferDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            }
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () async {
                    final trProvider = Provider.of<TransactionProvider>(context, listen: false);
                    final dateVal = currentStatus == 'PAID' ? currentTransferDate : null;
                    
                    await trProvider.updatePaymentStatus(tr.invoiceNo, currentStatus, dateVal);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status pembayaran berhasil diperbarui.'), backgroundColor: Colors.teal),
                      );
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Update ERP sync date dialog
  void _showUpdateErpStatusDialog(model_tr.Transaction tr) {
    final String deliveryStatus = (tr.status ?? '').toUpperCase();
    final bool isSent = (deliveryStatus == 'DIKIRIM');

    if (!isSent) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 28),
              SizedBox(width: 10),
              Text('Tidak Bisa Update ERP', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transaksi #${tr.invoiceNo} belum berstatus DIKIRIM (Status saat ini: $deliveryStatus).',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                ),
                child: const Text(
                  'Aturan Sistem: Barang harus berstatus DIKIRIM (fisik barang sudah keluar gudang) terlebih dahulu sebelum dapat di-input / di-update ke Laporan ERP.',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    if (tr.status == 'DIPINDAH' || tr.items.isEmpty || tr.note.startsWith('DIPINDAH')) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.block_rounded, color: Colors.purpleAccent, size: 24),
              SizedBox(width: 8),
              Text('Status ERP Dikunci', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                ),
                child: const Text(
                  'Invoice ini berstatus DIPINDAH / digabung ke invoice lain, sehingga TIDAK DAPAT disinkronkan ke ERP.\n\nHanya Invoice Tujuan yang disinkronkan ke Laporan ERP.',
                  style: TextStyle(color: Colors.purpleAccent, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    bool hasSync = tr.erpSyncDate != null;
    DateTime? currentSyncDate = tr.erpSyncDate ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Update Status ERP #${tr.invoiceNo}', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<bool>(
                    value: hasSync,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(hint: 'Status Sync ERP'),
                    items: const [
                      DropdownMenuItem(value: false, child: Text('BELUM ERP (Kosong)')),
                      DropdownMenuItem(value: true, child: Text('SUDAH ERP (Masuk ERP)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          hasSync = val;
                        });
                      }
                    },
                  ),
                  if (hasSync) ...[
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tanggal Masuk ERP:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                      subtitle: Text(
                        DateFormat('dd MMMM yyyy HH:mm').format(currentSyncDate!),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: currentSyncDate ?? DateTime.now(),
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          if (context.mounted) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(currentSyncDate!),
                            );
                            if (pickedTime != null) {
                              setDialogState(() {
                                currentSyncDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            }
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  onPressed: () async {
                    final trProvider = Provider.of<TransactionProvider>(context, listen: false);
                    final dateVal = hasSync ? currentSyncDate : null;
                    
                    await trProvider.updateErpStatus(tr.invoiceNo, dateVal);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Status ERP berhasil diperbarui.'), backgroundColor: Colors.teal),
                      );
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Move or merge items from source invoice to target invoice
  void _showMoveInvoiceItemsDialog(model_tr.Transaction sourceTr) {
    final trProvider = Provider.of<TransactionProvider>(context, listen: false);
    final allTxs = trProvider.transactions;
    final otherTxs = allTxs.where((t) => t.invoiceNo.toString() != sourceTr.invoiceNo.toString()).toList();

    if (otherTxs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada invoice lain sebagai tujuan pemindahan.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final Set<int> selectedIndices = {};
    final Map<int, TextEditingController> qtyControllers = {};
    final Map<int, TextEditingController> discControllers = {};

    for (int i = 0; i < sourceTr.items.length; i++) {
      final item = sourceTr.items[i];
      qtyControllers[i] = TextEditingController(text: item.qty.toString());
      discControllers[i] = TextEditingController(text: item.discountPercent.toStringAsFixed(1));
    }

    model_tr.Transaction? selectedTargetTr = otherTxs.first;
    String targetSearchQuery = '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredTargets = otherTxs.where((t) {
              if (targetSearchQuery.trim().isEmpty) return true;
              final q = targetSearchQuery.toLowerCase();
              final invNo = '#${t.invoiceNo}'.toLowerCase();
              final cust = t.customerName.toLowerCase();
              final alias = t.aliasName.toLowerCase();
              return invNo.contains(q) || cust.contains(q) || alias.contains(q);
            }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Colors.cyanAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pindah / Gabung Item Invoice #${sourceTr.invoiceNo}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Asal Toko: ${sourceTr.aliasName.isNotEmpty ? sourceTr.aliasName : sourceTr.customerName}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Notice Banner
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.cyanAccent, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Fitur ini memindahkan rincian produk (Qty & Custom Diskon) ke Invoice Tujuan tanpa mempengaruhi stok gudang.',
                                style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 1: Item Selection
                      const Text(
                        '1. Pilih Produk & Atur Qty / Diskon Yang Dipindah:',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          children: List.generate(sourceTr.items.length, (index) {
                            final item = sourceTr.items[index];
                            final isChecked = selectedIndices.contains(index);

                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: index < sourceTr.items.length - 1
                                    ? const Border(bottom: BorderSide(color: Color(0xFF334155)))
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: isChecked,
                                        activeColor: Colors.cyanAccent,
                                        checkColor: Colors.black,
                                        onChanged: (val) {
                                          setDialogState(() {
                                            if (val == true) {
                                              selectedIndices.add(index);
                                            } else {
                                              selectedIndices.remove(index);
                                            }
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.productName,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              'Harga Satuan: ${_rupiahFormatter.format(item.price)} | Qty Invoice Asal: ${item.qty} Pcs',
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Inputs if item is checked
                                  if (isChecked) ...[
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 40.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: qtyControllers[index],
                                              keyboardType: TextInputType.number,
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              decoration: InputDecoration(
                                                labelText: 'Qty Dipindah (Pcs)',
                                                labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                                                isDense: true,
                                                filled: true,
                                                fillColor: const Color(0xFF1E293B),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextField(
                                              controller: discControllers[index],
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              decoration: InputDecoration(
                                                labelText: 'Custom Diskon (%)',
                                                labelStyle: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                                                isDense: true,
                                                filled: true,
                                                fillColor: const Color(0xFF1E293B),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Target Invoice Selection
                      const Text(
                        '2. Pilih No Invoice Tujuan (Target Merge):',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      // Target Search Field
                      TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Cari No Invoice Tujuan / Nama Toko / Alias...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF38BDF8), size: 18),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          setDialogState(() {
                            targetSearchQuery = val;
                          });
                        },
                      ),
                      const SizedBox(height: 8),

                      // Target Invoice Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<model_tr.Transaction>(
                            value: (selectedTargetTr != null && filteredTargets.contains(selectedTargetTr))
                                ? selectedTargetTr
                                : (filteredTargets.isNotEmpty ? filteredTargets.first : null),
                            dropdownColor: const Color(0xFF1E293B),
                            isExpanded: true,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            items: filteredTargets.map((tr) {
                              final alias = tr.aliasName.isNotEmpty ? tr.aliasName : tr.customerName;
                              return DropdownMenuItem<model_tr.Transaction>(
                                value: tr,
                                child: Text(
                                  '#${tr.invoiceNo} - $alias (${tr.city}) - Total: ${_rupiahFormatter.format(tr.grandTotal)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedTargetTr = val;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.swap_horiz_rounded, size: 18, color: Colors.black),
                  label: Text(
                    isSaving ? 'Memindahkan...' : 'Pindahkan Item Sekarang',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (selectedIndices.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Silakan pilih minimal 1 item untuk dipindahkan.'), backgroundColor: Colors.orangeAccent),
                            );
                            return;
                          }

                          final target = selectedTargetTr ?? (filteredTargets.isNotEmpty ? filteredTargets.first : null);
                          if (target == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Silakan pilih Invoice Tujuan terlebih dahulu.'), backgroundColor: Colors.orangeAccent),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          try {
                            final List<model_tr.TransactionItem> newSourceItems = List.from(sourceTr.items);
                            final List<model_tr.TransactionItem> newTargetItems = List.from(target.items);

                            // Process moving selected items
                            final List<int> sortedIndices = selectedIndices.toList()..sort((a, b) => b.compareTo(a));

                            for (int idx in sortedIndices) {
                              final origItem = sourceTr.items[idx];
                              final double moveQty = double.tryParse(qtyControllers[idx]?.text ?? '') ?? origItem.qty;
                              final double customDisc = double.tryParse(discControllers[idx]?.text ?? '') ?? origItem.discountPercent;

                              if (moveQty <= 0) continue;

                              final double validMoveQty = moveQty > origItem.qty ? origItem.qty : moveQty;
                              final double remainingQty = origItem.qty - validMoveQty;

                              if (remainingQty > 0) {
                                final double newSubtotal = remainingQty * origItem.price * (1 - origItem.discountPercent / 100);
                                newSourceItems[idx] = model_tr.TransactionItem(
                                  productId: origItem.productId,
                                  productName: origItem.productName,
                                  price: origItem.price,
                                  qty: remainingQty,
                                  discountPercent: origItem.discountPercent,
                                  subtotal: newSubtotal,
                                  sizeGrams: origItem.sizeGrams,
                                  isBonus: origItem.isBonus,
                                );
                              } else {
                                newSourceItems.removeAt(idx);
                              }

                              // Add item to target invoice with custom Qty & Custom Discount
                              final double targetItemSubtotal = validMoveQty * origItem.price * (1 - customDisc / 100);
                              newTargetItems.add(
                                model_tr.TransactionItem(
                                  productId: origItem.productId,
                                  productName: origItem.productName,
                                  price: origItem.price,
                                  qty: validMoveQty,
                                  discountPercent: customDisc,
                                  subtotal: targetItemSubtotal,
                                  sizeGrams: origItem.sizeGrams,
                                  isBonus: origItem.isBonus,
                                ),
                              );
                            }

                             // Recalculate Grand Totals
                            final double newSourceTotal = newSourceItems.fold(0.0, (sum, i) => sum + i.subtotal);
                            final double newTargetTotal = newTargetItems.fold(0.0, (sum, i) => sum + i.subtotal);

                            final bool allItemsMoved = newSourceItems.isEmpty;
                            final String newSourceStatus = allItemsMoved ? 'DIPINDAH' : sourceTr.status;
                            final String newSourceNote = allItemsMoved
                                ? 'DIPINDAH KE INVOICE #${target.invoiceNo}'
                                : (sourceTr.note.contains('Sebagian item dipindah')
                                    ? sourceTr.note
                                    : '${sourceTr.note} (Sebagian item dipindah ke Invoice #${target.invoiceNo})').trim();
                            final DateTime? newSourceErpSyncDate = allItemsMoved ? null : sourceTr.erpSyncDate;

                            final updatedSourceTr = model_tr.Transaction(
                              invoiceNo: sourceTr.invoiceNo,
                              customerId: sourceTr.customerId,
                              customerName: sourceTr.customerName,
                              aliasName: sourceTr.aliasName,
                              date: sourceTr.date,
                              deliveryDate: sourceTr.deliveryDate,
                              city: sourceTr.city,
                              province: sourceTr.province,
                              country: sourceTr.country,
                              items: newSourceItems,
                              grandTotal: newSourceTotal,
                              note: newSourceNote,
                              status: newSourceStatus,
                              statusTransfer: sourceTr.statusTransfer,
                              transferDate: sourceTr.transferDate,
                              erpSyncDate: newSourceErpSyncDate,
                              createdBy: sourceTr.createdBy,
                              createdAt: sourceTr.createdAt,
                            );

                            final updatedTargetTr = model_tr.Transaction(
                              invoiceNo: target.invoiceNo,
                              customerId: target.customerId,
                              customerName: target.customerName,
                              aliasName: target.aliasName,
                              date: target.date,
                              deliveryDate: target.deliveryDate,
                              city: target.city,
                              province: target.province,
                              country: target.country,
                              items: newTargetItems,
                              grandTotal: newTargetTotal,
                              note: target.note,
                              status: target.status,
                              statusTransfer: target.statusTransfer,
                              transferDate: target.transferDate,
                              erpSyncDate: target.erpSyncDate,
                              createdBy: target.createdBy,
                              createdAt: target.createdAt,
                            );

                            final FirebaseService dbService = FirebaseService();
                            await dbService.moveInvoiceItems(
                              sourceTr: updatedSourceTr,
                              targetTr: updatedTargetTr,
                            );

                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🎉 Berhasil memindahkan item dari Invoice #${sourceTr.invoiceNo} ke Invoice #${target.invoiceNo}!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal memindahkan item: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Print invoice with date options dialog
  void _showPrintDialog(model_tr.Transaction tr) {
    int selectedOption = 1; // 1 = Tanggal di Awal, 2 = Input Tanggal Kirim Baru
    DateTime chosenDate = tr.deliveryDate ?? tr.date;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Cetak Invoice #${tr.invoiceNo}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih opsi tanggal pengiriman untuk dicetak pada invoice PDF:',
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<int>(
                    title: Text(
                      'Gunakan Tanggal Awal (${tr.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-'})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    value: 1,
                    groupValue: selectedOption,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedOption = val;
                        });
                      }
                    },
                  ),
                  RadioListTile<int>(
                    title: const Text(
                      'Input Tanggal Kirim Baru',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    value: 2,
                    groupValue: selectedOption,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedOption = val;
                        });
                      }
                    },
                  ),
                  if (selectedOption == 2) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tanggal Kirim: ${DateFormat('dd MMMM yyyy').format(chosenDate)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: chosenDate,
                                firstDate: DateTime(2025),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  chosenDate = picked;
                                });
                              }
                            },
                            icon: const Icon(Icons.date_range_rounded, size: 14, color: Colors.white),
                            label: const Text('Pilih', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.white),
                  label: const Text('Cetak PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () async {
                    final trProvider = Provider.of<TransactionProvider>(context, listen: false);
                    Navigator.pop(context);
                    
                    try {
                      model_tr.Transaction toPrint = tr;

                      if (selectedOption == 2) {
                        // 1. Update the delivery date in the database
                        await trProvider.updateDeliveryDate(tr.invoiceNo, chosenDate);
                        
                        // 2. Build updated model to print with the new delivery date
                        toPrint = model_tr.Transaction(
                          invoiceNo: tr.invoiceNo,
                          customerId: tr.customerId,
                          customerName: tr.customerName,
                          aliasName: tr.aliasName,
                          date: tr.date,
                          deliveryDate: chosenDate,
                          city: tr.city,
                          province: tr.province,
                          country: tr.country,
                          items: tr.items,
                          grandTotal: tr.grandTotal,
                          note: tr.note,
                          status: tr.status,
                          statusTransfer: tr.statusTransfer,
                          transferDate: tr.transferDate,
                          erpSyncDate: tr.erpSyncDate,
                          createdBy: tr.createdBy,
                          createdAt: tr.createdAt,
                        );
                      }

                      // Trigger system print dialog (Microsoft Print to PDF)
                      await PrintService.printInvoice(toPrint);
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("PDF Invoice #${toPrint.invoiceNo} siap dicetak / disimpan!"),
                            backgroundColor: Colors.teal,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal mencetak: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteTransaction(dynamic invoiceNo) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('Hapus Transaksi #$invoiceNo?', style: const TextStyle(color: Colors.white)),
          content: const Text(
            'Apakah Anda yakin ingin menghapus transaksi ini? Tindakan ini tidak dapat dibatalkan.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                final trProvider = Provider.of<TransactionProvider>(context, listen: false);
                await trProvider.deleteTransaction(invoiceNo);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Transaksi #$invoiceNo berhasil dihapus.'), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: const Text('Hapus', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final trProvider = Provider.of<TransactionProvider>(context);
    final masterCustomers = Provider.of<CustomerProvider>(context).customers;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final createdBy = user?.uid ?? 'system';
    final isKacab = user?.isKacab ?? false;

    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final Set<String> allProductsSet = {};
    for (var p in productProvider.products) {
      if (p.name.trim().isNotEmpty) allProductsSet.add(p.name.trim());
    }
    for (var tr in trProvider.transactions) {
      for (var item in tr.items) {
        if (item.productName.trim().isNotEmpty) allProductsSet.add(item.productName.trim());
      }
    }
    final allProductsList = allProductsSet.toList()..sort();

    // Apply local queries, month filter, and status filter
    final filteredTransactions = trProvider.transactions.where((tr) {
      // 1. Month Filter
      if (_monthFilter != "SEMUA") {
        final effectiveDate = tr.deliveryDate ?? tr.date;
        final effectiveMonth = DateFormat('MM-yyyy').format(effectiveDate);
        if (effectiveMonth != _monthFilter) return false;
      }

      // 2. Status Filter
      if (_statusFilter != "SEMUA") {
        if (_statusFilter == "DIKIRIM" || _statusFilter == "PENDING") {
          if (tr.status != _statusFilter) return false;
        } else if (_statusFilter == "UNPAID" || _statusFilter == "PAID") {
          if (tr.statusTransfer != _statusFilter) return false;
        } else if (_statusFilter == "ERP_SYNC") {
          if (tr.erpSyncDate == null) return false;
        } else if (_statusFilter == "ERP_NOT_SYNC") {
          if (tr.erpSyncDate != null) return false;
        }
      }

      // 3. Product Filter
      if (_productFilter != "SEMUA") {
        final targetProd = _productFilter.toLowerCase().trim();
        final hasProduct = tr.items.any((item) {
          final pId = item.productId.toLowerCase().trim();
          final pName = item.productName.toLowerCase().trim();
          return pId == targetProd || pName == targetProd || pName.contains(targetProd);
        });
        if (!hasProduct) return false;
      }

      // 4. Text Search Query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final cleanQuery = query.replaceAll('#', '').trim();

        final invStr = tr.invoiceNo.toString().toLowerCase();
        final matchInvoice = invStr.contains(query) || (cleanQuery.isNotEmpty && invStr.contains(cleanQuery));
        final matchAlias = tr.aliasName.toLowerCase().contains(query);
        final matchCust = tr.customerName.toLowerCase().contains(query);
        final matchDisplay = '${tr.customerName} (${tr.aliasName})'.toLowerCase().contains(query) ||
                             '${tr.aliasName} (${tr.customerName})'.toLowerCase().contains(query);
        final matchNote = tr.note.toLowerCase().contains(query);
        final matchItems = tr.items.any((item) => 
          item.productName.toLowerCase().contains(query) || 
          item.productId.toLowerCase().contains(query)
        );
        final matchDate = DateFormat('dd-MM-yyyy').format(tr.date).contains(query) ||
            (tr.deliveryDate != null && DateFormat('dd-MM-yyyy').format(tr.deliveryDate!).contains(query)) ||
            (tr.transferDate != null && DateFormat('dd-MM-yyyy').format(tr.transferDate!).contains(query)) ||
            (tr.erpSyncDate != null && DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!).contains(query));

        return matchInvoice || matchAlias || matchCust || matchDisplay || matchNote || matchItems || matchDate;
      }

      return true;
    }).toList();

    // Calculate Barang summary for transactions matching active month, status & search filters
    final Map<String, Map<String, dynamic>> shippedProductsMap = {};
    double totalShippedQty = 0.0;
    double totalShippedKg = 0.0;
    double totalShippedRp = 0.0;

    final deliveredTransactionsInScope = filteredTransactions;

    for (var tr in deliveredTransactionsInScope) {
      for (var item in tr.items) {
        final key = item.productId.isNotEmpty ? item.productId : item.productName;
        if (!shippedProductsMap.containsKey(key)) {
          shippedProductsMap[key] = {
            'productId': item.productId,
            'productName': item.productName,
            'totalQty': 0.0,
            'totalKg': 0.0,
            'totalRp': 0.0,
            'invoiceCount': 0,
          };
        }
        shippedProductsMap[key]!['totalQty'] = (shippedProductsMap[key]!['totalQty'] as double) + item.qty;
        shippedProductsMap[key]!['totalKg'] = (shippedProductsMap[key]!['totalKg'] as double) + item.weightKg;
        shippedProductsMap[key]!['totalRp'] = (shippedProductsMap[key]!['totalRp'] as double) + item.subtotal;
        shippedProductsMap[key]!['invoiceCount'] = (shippedProductsMap[key]!['invoiceCount'] as int) + 1;

        totalShippedQty += item.qty;
        totalShippedKg += item.weightKg;
        totalShippedRp += item.subtotal;
      }
    }

    final shippedProductsList = shippedProductsMap.values.toList();
    shippedProductsList.sort((a, b) => (b['totalQty'] as double).compareTo(a['totalQty'] as double));

    // Sort by invoiceNo strictly descending (highest to lowest, e.g. #625, #624, #SA34, #SA1...)
    filteredTransactions.sort((a, b) {
      final aNum = int.tryParse(a.invoiceNo.replaceAll(RegExp(r'[^0-9]'), ''));
      final bNum = int.tryParse(b.invoiceNo.replaceAll(RegExp(r'[^0-9]'), ''));
      if (aNum != null && bNum != null && aNum != bNum) {
        return bNum.compareTo(aNum);
      }
      return b.invoiceNo.compareTo(a.invoiceNo);
    });

    // Calculate Pagination Slice
    final totalItems = filteredTransactions.length;
    final totalPages = (totalItems / _rowsPerPage).ceil().clamp(1, 99999);
    if (_currentPage > totalPages) {
      _currentPage = totalPages;
    }

    final startIndex = (_currentPage - 1) * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalItems);
    final paginatedTransactions = filteredTransactions.sublist(
      startIndex.clamp(0, totalItems),
      endIndex,
    );

    final isMobile = MediaQuery.of(context).size.width < 900;

    final searchField = TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Cari invoice, pelanggan, tanggal (dd-mm-yyyy), catatan...',
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 18),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (val) {
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () {
          setState(() {
            _searchQuery = val;
            _currentPage = 1;
          });
        });
      },
    );

    final filterRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Month / Periode Dropdown Filter
        Container(
          width: 175,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _monthFilter != "SEMUA" ? const Color(0xFF38BDF8) : Colors.transparent),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _monthFilter,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              items: _getMonthFilterOptions(trProvider.transactions).map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, color: m != "SEMUA" ? const Color(0xFF38BDF8) : const Color(0xFF64748B), size: 14),
                      const SizedBox(width: 6),
                      Text(m == "SEMUA" ? "SEMUA BULAN" : m),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _monthFilter = val;
                    _currentPage = 1;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Status Filter Dropdown
        Container(
          width: 190,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _statusFilter != "SEMUA" ? const Color(0xFF38BDF8) : Colors.transparent),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: const Color(0xFF1E293B),
              isExpanded: true,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: "SEMUA", child: Text("SEMUA STATUS", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "DIKIRIM", child: Text("KIRIM: DIKIRIM", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "PENDING", child: Text("KIRIM: PENDING", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "UNPAID", child: Text("BAYAR: UNPAID", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "PAID", child: Text("BAYAR: PAID", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "ERP_SYNC", child: Text("ERP: SUDAH SYNC", overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: "ERP_NOT_SYNC", child: Text("ERP: BELUM SYNC", overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _statusFilter = val;
                    _currentPage = 1;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Product Filter Selector (Searchable Dropdown)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSearchableProductFilterDialog(allProductsList),
          child: Container(
            width: 215,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _productFilter != "SEMUA" ? const Color(0xFF38BDF8) : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(Icons.shopping_bag_outlined, color: _productFilter != "SEMUA" ? const Color(0xFF38BDF8) : const Color(0xFF64748B), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _productFilter == "SEMUA" ? "SEMUA PRODUK" : _productFilter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _productFilter != "SEMUA" ? const Color(0xFF38BDF8) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_productFilter != "SEMUA")
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _productFilter = "SEMUA";
                        _currentPage = 1;
                      });
                    },
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                  )
                else
                  const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Toggle Barang Keluar Summary Button
        SizedBox(
          height: 44,
          width: 44,
          child: IconButton(
            tooltip: _showRightSummaryPanel ? 'Sembunyikan Total Barang Keluar' : 'Tampilkan Total Barang Keluar',
            style: IconButton.styleFrom(
              backgroundColor: _showRightSummaryPanel ? const Color(0xFF38BDF8).withOpacity(0.2) : const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              side: BorderSide(color: _showRightSummaryPanel ? const Color(0xFF38BDF8) : Colors.transparent),
            ),
            icon: Icon(
              Icons.inventory_2_rounded,
              color: _showRightSummaryPanel ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _showRightSummaryPanel = !_showRightSummaryPanel;
              });
            },
          ),
        ),
        if (!isKacab) ...[
          const SizedBox(width: 12),
          // Import Excel Button
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _importTransactionsFromExcel(createdBy),
              icon: const Icon(Icons.file_upload_rounded, color: Colors.white, size: 16),
              label: const Text('Import Excel', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[700],
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );

    final mainTableWidget = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
                      child: trProvider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filteredTransactions.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Tidak ada histori transaksi ditemukan.',
                                    style: TextStyle(color: Color(0xFF64748B)),
                                  ),
                                )
                              : Column(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            columnSpacing: 20,
                                            horizontalMargin: 16,
                                            headingRowHeight: 48,
                                            dataRowMinHeight: 60,
                                            dataRowMaxHeight: 66,
                                            headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                            headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
                                            columns: const [
                                              DataColumn(label: Text('INVOICE')),
                                              DataColumn(label: Text('TANGGAL')),
                                              DataColumn(label: Text('PELANGGAN')),
                                              DataColumn(label: Text('KOTA')),
                                              DataColumn(label: Text('TOTAL BERAT'), numeric: true),
                                              DataColumn(label: Text('GRAND TOTAL'), numeric: true),
                                              DataColumn(label: Center(child: Text('STATUS BARANG'))),
                                              DataColumn(label: Center(child: Text('STATUS BAYAR'))),
                                              DataColumn(label: Center(child: Text('STATUS ERP'))),
                                              DataColumn(label: Center(child: Text('AKSI'))),
                                            ],
                                            rows: paginatedTransactions.map((tr) {
                                              // Calculate total weight in kg across items
                                              final totalKg = tr.items.fold(0.0, (sum, item) => sum + item.weightKg);

                                              return DataRow(
                                                cells: [
                                                  DataCell(
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          '#${tr.invoiceNo}',
                                                          style: const TextStyle(
                                                            color: Color(0xFF38BDF8),
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                            decoration: TextDecoration.underline,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF38BDF8)),
                                                      ],
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF94A3B8)),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              DateFormat('dd-MM-yyyy').format(tr.date),
                                                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                            ),
                                                          ],
                                                        ),
                                                        if (tr.deliveryDate != null)
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.local_shipping_rounded, size: 10, color: Color(0xFF38BDF8)),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                'Kirim: ${DateFormat('dd-MM-yyyy').format(tr.deliveryDate!)}',
                                                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Builder(
                                                      builder: (context) {
                                                        final customerInfo = _resolveCustomerDisplay(tr, masterCustomers);
                                                        final firstLine = customerInfo['firstLine']!;
                                                        final secondLine = customerInfo['secondLine']!;

                                                        return Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              firstLine,
                                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            if (secondLine.isNotEmpty)
                                                              Text(
                                                                secondLine,
                                                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      tr.city.isNotEmpty ? tr.city.toUpperCase() : '-',
                                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      '${totalKg.toStringAsFixed(2)} Kg',
                                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Text(
                                                      _rupiahFormatter.format(tr.grandTotal),
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                    ),
                                                    onTap: () => _showDetailDialog(tr),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: tr.status == 'DIKIRIM'
                                                              ? Colors.greenAccent.withOpacity(0.15)
                                                              : (tr.status == 'DIPINDAH'
                                                                  ? Colors.purpleAccent.withOpacity(0.15)
                                                                  : Colors.orangeAccent.withOpacity(0.15)),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                            color: tr.status == 'DIKIRIM'
                                                                ? Colors.greenAccent
                                                                : (tr.status == 'DIPINDAH' ? Colors.purpleAccent : Colors.orangeAccent),
                                                            width: 0.5,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          tr.status,
                                                          style: TextStyle(
                                                            color: tr.status == 'DIKIRIM'
                                                                ? Colors.greenAccent
                                                                : (tr.status == 'DIPINDAH' ? Colors.purpleAccent : Colors.orangeAccent),
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: tr.statusTransfer == 'PAID'
                                                              ? Colors.tealAccent.withOpacity(0.15)
                                                              : Colors.redAccent.withOpacity(0.15),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                            color: tr.statusTransfer == 'PAID' ? Colors.tealAccent : Colors.redAccent,
                                                            width: 0.5,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          tr.statusTransfer,
                                                          style: TextStyle(
                                                            color: tr.statusTransfer == 'PAID' ? Colors.tealAccent : Colors.redAccent,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: InkWell(
                                                        onTap: () => _showUpdateErpStatusDialog(tr),
                                                        borderRadius: BorderRadius.circular(12),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: tr.status == 'DIPINDAH'
                                                                ? Colors.purpleAccent.withOpacity(0.15)
                                                                : (tr.erpSyncDate != null
                                                                    ? Colors.amberAccent.withOpacity(0.15)
                                                                    : Colors.white10),
                                                            borderRadius: BorderRadius.circular(12),
                                                            border: Border.all(
                                                              color: tr.status == 'DIPINDAH'
                                                                  ? Colors.purpleAccent
                                                                  : (tr.erpSyncDate != null ? Colors.amberAccent : Colors.white24),
                                                              width: 0.5,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            tr.status == 'DIPINDAH'
                                                                ? 'DIPINDAH'
                                                                : (tr.erpSyncDate != null
                                                                    ? DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!)
                                                                    : 'BELUM ERP'),
                                                            style: TextStyle(
                                                              color: tr.status == 'DIPINDAH'
                                                                  ? Colors.purpleAccent
                                                                  : (tr.erpSyncDate != null ? Colors.amberAccent : Colors.white54),
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    Center(
                                                      child: PopupMenuButton<String>(
                                                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 18),
                                                        color: const Color(0xFF1E293B),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                        onSelected: (action) {
                                                          if (action == 'detail') {
                                                            _showDetailDialog(tr);
                                                          } else if (action == 'move_items') {
                                                            _showMoveInvoiceItemsDialog(tr);
                                                          } else if (action == 'delivery') {
                                                            _showUpdateDeliveryStatusDialog(tr);
                                                          } else if (action == 'payment') {
                                                            _showUpdateStatusDialog(tr);
                                                          } else if (action == 'erp') {
                                                            _showUpdateErpStatusDialog(tr);
                                                          } else if (action == 'edit') {
                                                            _showEditTransactionDialog(tr);
                                                          } else if (action == 'print') {
                                                            _showPrintDialog(tr);
                                                          } else if (action == 'delete') {
                                                            _deleteTransaction(tr.invoiceNo);
                                                          }
                                                        },
                                                        itemBuilder: (ctx) => [
                                                          const PopupMenuItem(
                                                            value: 'detail',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.visibility_outlined, color: Colors.cyanAccent, size: 18),
                                                                SizedBox(width: 10),
                                                                Text('Lihat Rincian Item', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                              ],
                                                            ),
                                                          ),
                                                          const PopupMenuItem(
                                                            value: 'print',
                                                            child: Row(
                                                              children: [
                                                                Icon(Icons.print_rounded, color: Color(0xFF38BDF8), size: 18),
                                                                SizedBox(width: 10),
                                                                Text('Cetak Invoice PDF', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                              ],
                                                            ),
                                                          ),
                                                          if (!isKacab) ...[
                                                            const PopupMenuItem(
                                                              value: 'move_items',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.swap_horiz_rounded, color: Colors.cyanAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Pindah / Gabung Item Invoice', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'delivery',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.local_shipping_outlined, color: Colors.greenAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Update Status Barang', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'payment',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.payment_rounded, color: Colors.tealAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Update Status Bayar', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'erp',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.inventory_rounded, color: Colors.amberAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Update Status ERP', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuItem(
                                                              value: 'edit',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Edit Transaksi', style: TextStyle(color: Colors.white, fontSize: 13)),
                                                                ],
                                                              ),
                                                            ),
                                                            const PopupMenuDivider(height: 8),
                                                            const PopupMenuItem(
                                                              value: 'delete',
                                                              child: Row(
                                                                children: [
                                                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                                  SizedBox(width: 10),
                                                                  Text('Hapus Transaksi', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ),

                                     // Bottom Pagination Control Bar
                                     Container(
                                       decoration: BoxDecoration(
                                         color: const Color(0xFF0F172A),
                                         borderRadius: const BorderRadius.only(
                                           bottomLeft: Radius.circular(12),
                                           bottomRight: Radius.circular(12),
                                         ),
                                         border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                                       ),
                                       child: LayoutBuilder(
                                         builder: (context, constraints) {
                                           return SingleChildScrollView(
                                             scrollDirection: Axis.horizontal,
                                             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                             child: ConstrainedBox(
                                               constraints: BoxConstraints(
                                                 minWidth: (constraints.maxWidth - 40).clamp(0, 99999),
                                               ),
                                               child: Row(
                                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                 children: [
                                                   Text(
                                                     totalItems == 0
                                                         ? '0 transaksi'
                                                         : 'Menampilkan ${startIndex + 1}-${endIndex} dari ${NumberFormat.decimalPattern('id_ID').format(totalItems)} transaksi',
                                                     style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                                                   ),
                                                   const SizedBox(width: 24),
                                                   Row(
                                                     children: [
                                                       const Text('Tampilkan:', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                                       const SizedBox(width: 8),
                                                       DropdownButton<int>(
                                                         value: _rowsPerPage,
                                                         dropdownColor: const Color(0xFF1E293B),
                                                         style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                         underline: const SizedBox(),
                                                         items: const [10, 25, 50, 100].map((count) {
                                                           return DropdownMenuItem<int>(
                                                             value: count,
                                                             child: Text('$count / hal'),
                                                           );
                                                         }).toList(),
                                                         onChanged: (val) {
                                                           if (val != null) {
                                                             setState(() {
                                                               _rowsPerPage = val;
                                                               _currentPage = 1;
                                                             });
                                                           }
                                                         },
                                                       ),
                                                       const SizedBox(width: 16),
                                                       IconButton(
                                                         icon: const Icon(Icons.first_page_rounded, size: 20),
                                                         color: _currentPage > 1 ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                                                         onPressed: _currentPage > 1 ? () => setState(() => _currentPage = 1) : null,
                                                         tooltip: 'Halaman Pertama',
                                                       ),
                                                       IconButton(
                                                         icon: const Icon(Icons.chevron_left_rounded, size: 20),
                                                         color: _currentPage > 1 ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                                                         onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                                                         tooltip: 'Halaman Sebelumnya',
                                                       ),
                                                       Container(
                                                         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                         decoration: BoxDecoration(
                                                           color: const Color(0xFF1E293B),
                                                           borderRadius: BorderRadius.circular(8),
                                                           border: Border.all(color: Colors.white.withOpacity(0.1)),
                                                         ),
                                                         child: Text(
                                                           'Hal $_currentPage dari $totalPages',
                                                           style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                                         ),
                                                       ),
                                                       IconButton(
                                                         icon: const Icon(Icons.chevron_right_rounded, size: 20),
                                                         color: _currentPage < totalPages ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                                                         onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                                                         tooltip: 'Halaman Selanjutnya',
                                                       ),
                                                       IconButton(
                                                         icon: const Icon(Icons.last_page_rounded, size: 20),
                                                         color: _currentPage < totalPages ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                                                         onPressed: _currentPage < totalPages ? () => setState(() => _currentPage = totalPages) : null,
                                                         tooltip: 'Halaman Terakhir',
                                                       ),
                                                     ],
                                                   ),
                                                 ],
                                               ),
                                             ),
                                           );
                                         },
                                       ),
                                     ),
                                  ],
                                ),
    );

    final summaryPanelWidget = _buildShippedProductsPanel(
      shippedProductsList,
      totalShippedQty,
      totalShippedKg,
      totalShippedRp,
      deliveredTransactionsInScope.length,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 10.0 : 20.0),
        child: Column(
          children: [
            // Search Input, Month Filter, Status Dropdown & Action Buttons Header Row
            if (isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: filterRow,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: searchField,
                  ),
                  const SizedBox(width: 12),
                  filterRow,
                ],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: isMobile
                  ? Column(
                      children: [
                        Expanded(child: mainTableWidget),
                        if (_showRightSummaryPanel) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 320,
                            child: summaryPanelWidget,
                          ),
                        ],
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: mainTableWidget),
                        if (_showRightSummaryPanel) ...[
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: summaryPanelWidget),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget Panel Ringkasan Barang Keluar (DIKIRIM)
  Widget _buildShippedProductsPanel(
    List<Map<String, dynamic>> shippedProductsList,
    double totalShippedQty,
    double totalShippedKg,
    double totalShippedRp,
    int deliveredCount,
  ) {
    final filteredProducts = shippedProductsList.where((p) {
      if (_summaryProductSearch.isEmpty) return true;
      final q = _summaryProductSearch.toLowerCase().trim();
      final pName = (p['productName'] ?? '').toString().toLowerCase();
      final pId = (p['productId'] ?? '').toString().toLowerCase();
      return pName.contains(q) || pId.contains(q);
    }).toList();

    String panelTitle = _monthFilter == "SEMUA" ? 'Rincian Barang' : 'Rincian Barang ($_monthFilter)';
    if (_statusFilter != "SEMUA") {
      panelTitle += ' - $_statusFilter';
    }

    String panelSubtitle = 'Ringkasan Item Transaksi Tersaring';
    if (_productFilter != "SEMUA") {
      panelSubtitle = 'Produk: $_productFilter';
      if (_statusFilter != "SEMUA") {
        panelSubtitle += ' | Status: $_statusFilter';
      }
    } else if (_statusFilter != "SEMUA") {
      panelSubtitle = 'Ringkasan Item Status: $_statusFilter';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Title & Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            panelTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      panelSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                tooltip: 'Sembunyikan Panel',
                onPressed: () {
                  setState(() {
                    _showRightSummaryPanel = false;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Metric Cards Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL BARANG', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        '${NumberFormat.decimalPattern('id_ID').format(totalShippedQty.toInt())} Pcs',
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${totalShippedKg.toStringAsFixed(2)} Kg',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL NOMINAL', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        _rupiahFormatter.format(totalShippedRp),
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$deliveredCount Invoice',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Field for summary
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Cari produk dalam rincian...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 16),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            onChanged: (val) {
              setState(() {
                _summaryProductSearch = val;
              });
            },
          ),
          const SizedBox(height: 10),

          // Product List Breakdown
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: filteredProducts.isEmpty
                  ? const Center(
                      child: Text(
                        'Tidak ada barang ditemukan pada filter ini.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: filteredProducts.length,
                      separatorBuilder: (ctx, idx) => const Divider(color: Color(0xFF1E293B), height: 1),
                      itemBuilder: (ctx, idx) {
                        final p = filteredProducts[idx];
                        final name = (p['productName'] ?? p['productId']).toString();
                        final qty = (p['totalQty'] as double).toInt();
                        final kg = (p['totalKg'] as double).toStringAsFixed(2);
                        final rp = _rupiahFormatter.format(p['totalRp']);
                        final invCount = p['invoiceCount'];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: const Color(0xFF38BDF8).withOpacity(0.15),
                                child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '$invCount nota | $kg Kg',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${NumberFormat.decimalPattern('id_ID').format(qty)} pcs',
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    rp,
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Visual helper builders
  Widget _buildDetailRow(String label, String value, {bool isBadge = false}) {
    Color badgeColor = Colors.white;
    if (value == 'PAID' || value == 'DIKIRIM') {
      badgeColor = Colors.greenAccent;
    } else if (value == 'PENDING') {
      badgeColor = Colors.orangeAccent;
    } else {
      badgeColor = Colors.redAccent;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 85, child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold))),
        const SizedBox(width: 4),
        Expanded(
          child: isBadge
              ? UnconstrainedBox(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: badgeColor, width: 0.5),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              : Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, TextAlign align = TextAlign.left, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: isHeader ? const Color(0xFF94A3B8) : Colors.white,
          fontSize: isHeader ? 11 : 12,
          fontWeight: isHeader 
              ? FontWeight.bold 
              : (isBold ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF38BDF8), size: 18) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.0),
      ),
    );
  }
}
