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

class TransactionHistoryView extends StatefulWidget {
  const TransactionHistoryView({super.key});

  @override
  State<TransactionHistoryView> createState() => _TransactionHistoryViewState();
}

class _TransactionHistoryViewState extends State<TransactionHistoryView> {
  final _searchController = TextEditingController();
  String _searchQuery = "";
  String _statusFilter = "SEMUA"; // SEMUA, PAID, UNPAID

  // Pagination & Debounce State
  int _currentPage = 1;
  int _rowsPerPage = 25;
  Timer? _debounce;

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

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

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double grandTotal = editedItems.fold(0.0, (sum, item) => sum + item.subtotal);

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

              final existingIndex = editedItems.indexWhere((item) => item.productId == selectedProduct!.id);
              if (existingIndex != -1) {
                final currentQty = editedItems[existingIndex].qty;
                final newQty = currentQty + qty;
                final subtotal = newQty * selectedProduct!.price * (1 - discount / 100);

                setDialogState(() {
                  editedItems[existingIndex] = model_tr.TransactionItem(
                    productId: selectedProduct!.id,
                    productName: selectedProduct!.name,
                    price: selectedProduct!.price,
                    qty: newQty,
                    discountPercent: discount,
                    subtotal: subtotal,
                    sizeGrams: selectedProduct!.sizeGrams,
                  );
                });
              } else {
                if (editedItems.length >= 10) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      title: const Text('Batas Item Terpenuhi', style: TextStyle(color: Colors.white)),
                      content: const Text('Batas Maksimal 10 item produk berbeda per lembar invoice ( Continuous Form ) tercapai!', style: TextStyle(color: Color(0xFF94A3B8))),
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

                final subtotal = qty * selectedProduct!.price * (1 - discount / 100);
                setDialogState(() {
                  editedItems.add(
                    model_tr.TransactionItem(
                      productId: selectedProduct!.id,
                      productName: selectedProduct!.name,
                      price: selectedProduct!.price,
                      qty: qty,
                      discountPercent: discount,
                      subtotal: subtotal,
                      sizeGrams: selectedProduct!.sizeGrams,
                    ),
                  );
                });
              }

              // Clear product picker inputs
              setDialogState(() {
                selectedProduct = null;
                qtyController.text = '1';
                discountController.text = '0';
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text('Edit Transaksi #${tr.invoiceNo}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 950,
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
                            DropdownButtonFormField<Customer>(
                              value: selectedCustomer,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: _buildInputDecoration(hint: 'Pilih Pelanggan'),
                              items: customers.map((c) {
                                return DropdownMenuItem<Customer>(
                                  value: c,
                                  child: Text('${c.aliasName} (${c.customerName})', style: const TextStyle(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setDialogState(() {
                                  selectedCustomer = val;
                                });
                              },
                            ),
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
                            const Text('Tambah Produk:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<Product>(
                              value: selectedProduct,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: _buildInputDecoration(hint: 'Pilih Produk'),
                              items: products.map((p) {
                                return DropdownMenuItem<Product>(
                                  value: p,
                                  child: Text(p.name, style: const TextStyle(fontSize: 12)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setDialogState(() {
                                  selectedProduct = val;
                                });
                              },
                            ),
                            if (selectedProduct != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Harga: ${_rupiahFormatter.format(selectedProduct!.price)} | Stok: ${selectedProduct!.stock.toStringAsFixed(0)}',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: qtyController,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: _buildInputDecoration(hint: 'Qty (Pcs)'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: discountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                    decoration: _buildInputDecoration(hint: 'Disc %'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: addItem,
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Tambah Produk', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(40),
                                backgroundColor: const Color(0xFF0284C7),
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
                                '${editedItems.length} / 10 Item',
                                style: TextStyle(
                                  color: editedItems.length >= 10 ? Colors.redAccent : const Color(0xFF38BDF8),
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
                                          0: FlexColumnWidth(2.5),
                                          1: FlexColumnWidth(0.8),
                                          2: FlexColumnWidth(1.2),
                                          3: FlexColumnWidth(1.2),
                                          4: FlexColumnWidth(0.6),
                                        },
                                        children: [
                                          TableRow(
                                            decoration: const BoxDecoration(color: Color(0xFF1E293B)),
                                            children: [
                                              _buildTableCell('Nama Barang', isHeader: true),
                                              _buildTableCell('Qty', isHeader: true, align: TextAlign.center),
                                              _buildTableCell('Harga', isHeader: true, align: TextAlign.right),
                                              _buildTableCell('Subtotal', isHeader: true, align: TextAlign.right),
                                              _buildTableCell('', isHeader: true),
                                            ],
                                          ),
                                          ...editedItems.map((item) => TableRow(
                                                children: [
                                                  _buildTableCell('${item.productName}${item.isBonus ? " (BONUS)" : ""}\n(${item.weightKg.toStringAsFixed(2)} kg)'),
                                                  _buildTableCell(item.qty.toStringAsFixed(0), align: TextAlign.center),
                                                  _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price), align: TextAlign.right),
                                                  _buildTableCell(item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal), align: TextAlign.right, isBold: true),
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                                      onPressed: () {
                                                        setDialogState(() {
                                                          editedItems.removeWhere((i) => i.productId == item.productId);
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              )),
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
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
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

  // Show detailed item list in dialog
  void _showDetailDialog(model_tr.Transaction tr) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Detail Invoice #${tr.invoiceNo}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          content: SizedBox(
            width: 800,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info rows
                Row(
                  children: [
                    Expanded(child: _buildDetailRow('Pelanggan:', '${tr.aliasName} (${tr.customerName})')),
                    Expanded(child: _buildDetailRow('Kota/Provinsi:', '${tr.city}, ${tr.province}')),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildDetailRow('Status Kirim:', tr.status, isBadge: true)),
                    Expanded(child: _buildDetailRow('Status Bayar:', tr.statusTransfer, isBadge: true)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Rincian Tanggal:', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildDetailRow('Tgl Invoice:', DateFormat('dd-MM-yyyy HH:mm').format(tr.date))),
                    Expanded(child: _buildDetailRow('Tgl Kirim:', tr.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-')),
                  ],
                ),
                if ((tr.statusTransfer == 'PAID' && tr.transferDate != null) || tr.erpSyncDate != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (tr.statusTransfer == 'PAID' && tr.transferDate != null)
                        Expanded(child: _buildDetailRow('Tgl PAID:', DateFormat('dd-MM-yyyy HH:mm').format(tr.transferDate!)))
                      else
                        const Spacer(),
                      if (tr.erpSyncDate != null)
                        Expanded(child: _buildDetailRow('Tgl ERP:', DateFormat('dd-MM-yyyy HH:mm').format(tr.erpSyncDate!)))
                      else
                        const Spacer(),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155)),
                const SizedBox(height: 8),
                const Text('Daftar Barang:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                
                // Items Table
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(2.2),
                          1: FlexColumnWidth(0.6),
                          2: FlexColumnWidth(1.2),
                          3: FlexColumnWidth(1.2),
                          4: FlexColumnWidth(0.8),
                          5: FlexColumnWidth(1.2),
                          6: FlexColumnWidth(1.3),
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
                          ...tr.items.map((item) {
                            final totalBeforeDisc = item.isBonus ? 0.0 : item.qty * item.price;
                            final discRp = item.isBonus ? 0.0 : totalBeforeDisc * (item.discountPercent / 100);
                            return TableRow(
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
                  ),
                ),
                
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF334155)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Catatan: ${tr.note.isNotEmpty ? tr.note : "-"}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    Text(
                      'GRAND TOTAL: ${_rupiahFormatter.format(tr.grandTotal)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
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
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal mengupdate status: $e'), backgroundColor: Colors.redAccent),
                        );
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
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
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
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
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
              title: Text('Cetak Invoice #${tr.invoiceNo}', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih opsi tanggal pengiriman untuk dicetak pada invoice PDF:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<int>(
                    title: Text(
                      'Gunakan Tanggal Awal (${tr.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-'})',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
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
                      style: const TextStyle(color: Colors.white, fontSize: 14),
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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                            icon: const Icon(Icons.date_range_rounded, size: 14),
                            label: const Text('Pilih', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155)),
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
                  child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                  label: const Text('Cetak PDF'),
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

  @override
  Widget build(BuildContext context) {
    final trProvider = Provider.of<TransactionProvider>(context);
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    final createdBy = user?.uid ?? 'system';

    // Apply local queries and filter status
    final filteredTransactions = trProvider.transactions.where((tr) {
      // 1. Status Filter
      if (_statusFilter != "SEMUA") {
        if (_statusFilter == "DIKIRIM" || _statusFilter == "PENDING") {
          if (tr.status != _statusFilter) return false;
        } else {
          if (tr.statusTransfer != _statusFilter) return false;
        }
      }

      // 2. Text Search Query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchInvoice = tr.invoiceNo.toString().contains(query);
        final matchAlias = tr.aliasName.toLowerCase().contains(query);
        final matchCust = tr.customerName.toLowerCase().contains(query);
        final matchNote = tr.note.toLowerCase().contains(query);
        final matchDate = DateFormat('dd-MM-yyyy').format(tr.date).contains(query) ||
            (tr.deliveryDate != null && DateFormat('dd-MM-yyyy').format(tr.deliveryDate!).contains(query)) ||
            (tr.transferDate != null && DateFormat('dd-MM-yyyy').format(tr.transferDate!).contains(query)) ||
            (tr.erpSyncDate != null && DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!).contains(query));

        return matchInvoice || matchAlias || matchCust || matchNote || matchDate;
      }

      return true;
    }).toList();

    // Sort by invoiceNo strictly descending (highest to lowest, e.g. #624, #623, #622...)
    filteredTransactions.sort((a, b) => b.invoiceNo.compareTo(a.invoiceNo));

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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Search Input and Status Dropdown Header Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Cari invoice berdasarkan nomor, nama pelanggan, tanggal (dd-mm-yyyy), catatan...',
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
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        setState(() {
                          _searchQuery = val;
                          _currentPage = 1;
                        });
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: "SEMUA", child: Text("SEMUA STATUS")),
                        DropdownMenuItem(value: "DIKIRIM", child: Text("STATUS BARANG: DIKIRIM")),
                        DropdownMenuItem(value: "PENDING", child: Text("STATUS BARANG: PENDING")),
                        DropdownMenuItem(value: "UNPAID", child: Text("STATUS BAYAR: UNPAID")),
                        DropdownMenuItem(value: "PAID", child: Text("STATUS BAYAR: PAID")),
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
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _importTransactionsFromExcel(createdBy),
                  icon: const Icon(Icons.file_upload_rounded, color: Colors.white),
                  label: const Text('Import Excel', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // History DataTable list with Pagination
            Expanded(
              child: Container(
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
                                      headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                      dataRowMinHeight: 56,
                                      dataRowMaxHeight: 56,
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
                                              Text('#${tr.invoiceNo}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                                              onTap: () => _showDetailDialog(tr),
                                            ),
                                            DataCell(
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    // Tanggal Invoice (Received)
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.receipt_long_rounded, color: Color(0xFF94A3B8), size: 10),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          DateFormat('dd-MM-yyyy').format(tr.date),
                                                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    // Tanggal Kirim
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.local_shipping_rounded, color: Color(0xFF38BDF8), size: 10),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Kirim: ${tr.deliveryDate != null ? DateFormat('dd-MM-yyyy').format(tr.deliveryDate!) : '-'}',
                                                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                                                        ),
                                                      ],
                                                    ),
                                                    if (tr.statusTransfer == 'PAID' && tr.transferDate != null) ...[
                                                      const SizedBox(height: 2),
                                                      // Tanggal PAID
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 10),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'Paid: ${DateFormat('dd-MM-yyyy').format(tr.transferDate!)}',
                                                            style: const TextStyle(color: Colors.greenAccent, fontSize: 9),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              onTap: () => _showDetailDialog(tr),
                                            ),
                                            DataCell(
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(tr.aliasName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  Text(tr.customerName, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                                                ],
                                              ),
                                              onTap: () => _showDetailDialog(tr),
                                            ),
                                            DataCell(Text(tr.city, style: const TextStyle(color: Colors.white))),
                                            DataCell(Text('${totalKg.toStringAsFixed(2)} Kg', style: const TextStyle(color: Colors.white))),
                                            DataCell(Text(_rupiahFormatter.format(tr.grandTotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                            
                                            // Status Kirim Badge
                                            DataCell(
                                              Center(
                                                child: InkWell(
                                                  onTap: () => _showUpdateDeliveryStatusDialog(tr),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: tr.status == 'DIKIRIM' 
                                                          ? Colors.greenAccent.withOpacity(0.15) 
                                                          : Colors.orangeAccent.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: tr.status == 'DIKIRIM' ? Colors.greenAccent : Colors.orangeAccent,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      tr.status,
                                                      style: TextStyle(
                                                        color: tr.status == 'DIKIRIM' ? Colors.greenAccent : Colors.orangeAccent,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Status Bayar Badge
                                            DataCell(
                                              Center(
                                                child: InkWell(
                                                  onTap: () => _showUpdateStatusDialog(tr),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: tr.statusTransfer == 'PAID' 
                                                          ? Colors.greenAccent.withOpacity(0.15) 
                                                          : Colors.redAccent.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: tr.statusTransfer == 'PAID' ? Colors.greenAccent : Colors.redAccent,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      tr.statusTransfer,
                                                      style: TextStyle(
                                                        color: tr.statusTransfer == 'PAID' ? Colors.greenAccent : Colors.redAccent,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Status ERP Badge
                                            DataCell(
                                              Center(
                                                child: InkWell(
                                                  onTap: () => _showUpdateErpStatusDialog(tr),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: tr.erpSyncDate != null 
                                                          ? Colors.amberAccent.withOpacity(0.15) 
                                                          : Colors.grey.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: tr.erpSyncDate != null ? Colors.amberAccent : Colors.grey,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      tr.erpSyncDate != null 
                                                          ? DateFormat('dd-MM-yyyy').format(tr.erpSyncDate!) 
                                                          : 'BELUM ERP',
                                                      style: TextStyle(
                                                        color: tr.erpSyncDate != null ? Colors.amberAccent : Colors.grey,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Actions Buttons
                                            DataCell(
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.list_alt_rounded, color: Colors.amberAccent, size: 20),
                                                    tooltip: 'Lihat Detail Rincian',
                                                    onPressed: () => _showDetailDialog(tr),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.local_shipping_rounded, color: Color(0xFF38BDF8), size: 20),
                                                    tooltip: 'Update Status Pengiriman (DIKIRIM/PENDING)',
                                                    onPressed: () => _showUpdateDeliveryStatusDialog(tr),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.payment_rounded, color: Colors.tealAccent, size: 20),
                                                    tooltip: 'Update Status Pembayaran (PAID/UNPAID)',
                                                    onPressed: () => _showUpdateStatusDialog(tr),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.inventory_rounded, color: Colors.amberAccent, size: 20),
                                                    tooltip: 'Update Status ERP (Masuk ERP / Tanggal ERP)',
                                                    onPressed: () => _showUpdateErpStatusDialog(tr),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.edit_outlined, color: Colors.orangeAccent, size: 20),
                                                    tooltip: 'Edit Transaksi',
                                                    onPressed: () => _showEditTransactionDialog(tr),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                                    tooltip: 'Hapus Transaksi',
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          backgroundColor: const Color(0xFF1E293B),
                                                          title: const Text('Hapus Transaksi', style: TextStyle(color: Colors.white)),
                                                          content: Text('Apakah Anda yakin ingin menghapus Transaksi #${tr.invoiceNo} untuk ${tr.aliasName}? Data transaksi ini akan dihapus dari histori.', style: const TextStyle(color: Color(0xFF94A3B8))),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context),
                                                              child: const Text('Batal', style: TextStyle(color: Color(0xFF64748B))),
                                                            ),
                                                            ElevatedButton(
                                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                              onPressed: () async {
                                                                try {
                                                                  await trProvider.deleteTransaction(tr.invoiceNo);
                                                                  if (context.mounted) {
                                                                    Navigator.pop(context);
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      const SnackBar(content: Text('Transaksi berhasil dihapus.'), backgroundColor: Colors.teal),
                                                                    );
                                                                  }
                                                                } catch (e) {
                                                                  if (context.mounted) {
                                                                    Navigator.pop(context);
                                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                                      SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.redAccent),
                                                                    );
                                                                  }
                                                                }
                                                              },
                                                              child: const Text('Hapus'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.print_rounded, color: Color(0xFF38BDF8), size: 20),
                                                    tooltip: 'Cetak Invoice PDF',
                                                    onPressed: () => _showPrintDialog(tr),
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

                              // Bottom Pagination Control Bar
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      totalItems == 0
                                          ? '0 transaksi'
                                          : 'Menampilkan ${startIndex + 1}-${endIndex} dari ${NumberFormat.decimalPattern('id_ID').format(totalItems)} transaksi',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
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
                                        const SizedBox(width: 24),
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
                            ],
                          ),
              ),
            ),
          ],
        ),
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

  InputDecoration _buildInputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide.none,
      ),
    );
  }
}
