import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart' as model_tr;
import '../models/transaction_return.dart';
import '../models/product.dart';
import '../providers/transaction_provider.dart';
import '../providers/product_provider.dart';
import '../providers/auth_provider.dart';

class ReturnTransactionDialog extends StatefulWidget {
  final model_tr.Transaction transaction;

  const ReturnTransactionDialog({
    super.key,
    required this.transaction,
  });

  @override
  State<ReturnTransactionDialog> createState() => _ReturnTransactionDialogState();
}

class _ReturnTransactionDialogState extends State<ReturnTransactionDialog> {
  final _currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  final Map<String, TextEditingController> _qtyBagusControllers = {};
  final Map<String, TextEditingController> _qtyRusakControllers = {};
  final Map<String, TextEditingController> _reasonControllers = {};

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.transaction.items) {
      _qtyBagusControllers[item.productId] = TextEditingController(text: '0');
      _qtyRusakControllers[item.productId] = TextEditingController(text: '0');
      _reasonControllers[item.productId] = TextEditingController(text: 'Barang Diretur');
    }
  }

  @override
  void dispose() {
    for (var controller in _qtyBagusControllers.values) {
      controller.dispose();
    }
    for (var controller in _qtyRusakControllers.values) {
      controller.dispose();
    }
    for (var controller in _reasonControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _getEffectiveUnitPrice(model_tr.TransactionItem item) {
    if (item.isBonus) return 0.0;
    return item.price * (1.0 - (item.discountPercent / 100.0));
  }

  double _calculateTotalReturnAmount() {
    double total = 0.0;
    for (var item in widget.transaction.items) {
      final qtyBagus = double.tryParse(_qtyBagusControllers[item.productId]?.text ?? '0') ?? 0.0;
      final qtyRusak = double.tryParse(_qtyRusakControllers[item.productId]?.text ?? '0') ?? 0.0;
      final totalQtyItem = qtyBagus + qtyRusak;

      if (totalQtyItem > 0) {
        final effPrice = _getEffectiveUnitPrice(item);
        total += totalQtyItem * effPrice;
      }
    }
    return total;
  }

  Future<void> _submitReturn() async {
    final List<ReturnItem> returnItems = [];
    double totalReturnAmount = 0.0;

    for (var item in widget.transaction.items) {
      final qtyBagus = double.tryParse(_qtyBagusControllers[item.productId]?.text.trim() ?? '0') ?? 0.0;
      final qtyRusak = double.tryParse(_qtyRusakControllers[item.productId]?.text.trim() ?? '0') ?? 0.0;
      final totalQtyItem = qtyBagus + qtyRusak;

      if (totalQtyItem > item.qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Total Qty retur untuk ${item.productName} (Bagus: ${qtyBagus.toInt()} + Rusak: ${qtyRusak.toInt()} = ${totalQtyItem.toInt()} pcs) tidak boleh melebihi qty awal (${item.qty.toInt()} pcs)!',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final effPrice = _getEffectiveUnitPrice(item);
      final baseReason = _reasonControllers[item.productId]?.text.trim() ?? 'Retur Produk';

      // Item Retur Kondisi BAGUS (Kembali ke Stok Master)
      if (qtyBagus > 0) {
        final subtotalBagus = qtyBagus * effPrice;
        totalReturnAmount += subtotalBagus;
        returnItems.add(
          ReturnItem(
            productId: item.productId,
            productName: item.productName,
            qtyReturned: qtyBagus,
            price: item.price,
            discountPercent: item.discountPercent,
            effectiveUnitPrice: effPrice,
            subtotalReturn: subtotalBagus,
            sizeGrams: item.sizeGrams,
            isBonus: item.isBonus,
            condition: 'BAGUS',
            reason: '$baseReason (Kondisi Bagus / Kembali Stok)',
          ),
        );
      }

      // Item Retur Kondisi RUSAK / BS (Afkir)
      if (qtyRusak > 0) {
        final subtotalRusak = qtyRusak * effPrice;
        totalReturnAmount += subtotalRusak;
        returnItems.add(
          ReturnItem(
            productId: item.productId,
            productName: item.productName,
            qtyReturned: qtyRusak,
            price: item.price,
            discountPercent: item.discountPercent,
            effectiveUnitPrice: effPrice,
            subtotalReturn: subtotalRusak,
            sizeGrams: item.sizeGrams,
            isBonus: item.isBonus,
            condition: 'RUSAK_BS',
            reason: '$baseReason (Kondisi Rusak / BS Afkir)',
          ),
        );
      }
    }

    if (returnItems.isEmpty || totalReturnAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan masukkan jumlah (Qty) barang yang diretur (minimal 1 item)!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final trProvider = Provider.of<TransactionProvider>(context, listen: false);
      final currentUser = authProvider.currentUser?.name ?? 'Admin';

      final retData = TransactionReturn(
        id: '',
        invoiceNo: widget.transaction.invoiceNo,
        customerId: widget.transaction.customerId,
        customerName: widget.transaction.customerName,
        aliasName: widget.transaction.aliasName,
        returnDate: DateTime.now(),
        items: returnItems,
        totalReturnAmount: totalReturnAmount,
        createdBy: currentUser,
        createdAt: DateTime.now(),
      );

      await trProvider.processTransactionReturn(retData);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Berhasil memproses retur untuk Nota #${widget.transaction.invoiceNo}. Potongan tagihan: ${_currencyFormatter.format(totalReturnAmount)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses retur: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.transaction;
    final productProvider = Provider.of<ProductProvider>(context);
    final products = productProvider.products;

    final totalReturnAmount = _calculateTotalReturnAmount();
    final remainingNetTotal = (tr.netGrandTotal - totalReturnAmount).clamp(0.0, double.infinity);

    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.all(20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.all(20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.assignment_return_rounded, color: Colors.amberAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Form Retur Produk Nota #${tr.invoiceNo}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Outlet: ${tr.aliasName} (${tr.customerName}) | Status: ${tr.status}',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 860,
        height: 560,
        child: Column(
          children: [
            // Status Banner Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL INVOICE ASAL', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(_currencyFormatter.format(tr.grandTotal), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('TOTAL POTONGAN RETUR', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(_currencyFormatter.format(totalReturnAmount), style: const TextStyle(color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('SISA TAGIHAN BERSIH', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(_currencyFormatter.format(remainingNetTotal), style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Table of items for returning
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tr.items.length,
                  separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E293B), height: 16),
                  itemBuilder: (context, index) {
                    final item = tr.items[index];
                    final effPrice = _getEffectiveUnitPrice(item);

                    // Fetch current master stock for this item
                    final Product? matchingProd = products.cast<Product?>().firstWhere(
                      (p) => p != null && (p.id.trim().toLowerCase() == item.productId.trim().toLowerCase() ||
                             p.name.trim().toLowerCase() == item.productName.trim().toLowerCase()),
                      orElse: () => null,
                    );
                    final double masterStock = matchingProd != null ? matchingProd.stock : 0.0;

                    final controllerBagus = _qtyBagusControllers[item.productId]!;
                    final controllerRusak = _qtyRusakControllers[item.productId]!;
                    final reasonController = _reasonControllers[item.productId]!;

                    final qtyBagus = double.tryParse(controllerBagus.text) ?? 0.0;
                    final qtyRusak = double.tryParse(controllerRusak.text) ?? 0.0;
                    final totalQtyItem = qtyBagus + qtyRusak;
                    final itemReturnSubtotal = totalQtyItem * effPrice;

                    final bool isOverflow = totalQtyItem > item.qty;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isOverflow
                              ? Colors.red
                              : (totalQtyItem > 0 ? Colors.amber.withOpacity(0.6) : Colors.transparent),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Item Title & Header Info Row
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    if (item.isBonus) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.purpleAccent, width: 0.8),
                                        ),
                                        child: const Text('BONUS FREE', style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Master Stock Badge + Qty Asal + Effective Price
                              Wrap(
                                spacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.inventory_2_rounded, color: Color(0xFF38BDF8), size: 12),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Stok Master: ${masterStock.toInt()} pcs',
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Qty Asal: ${item.qty.toInt()} pcs | Harga Bersih: ${_currencyFormatter.format(effPrice)}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (item.discountPercent > 0) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Diskon Item: ${item.discountPercent}% (Harga Normal: ${_currencyFormatter.format(item.price)})',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
                            ),
                          ],
                          const SizedBox(height: 10),

                          // Controls Row: Qty Bagus + Qty Rusak/BS + Alasan + Subtotal
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Input Qty Retur BAGUS
                              SizedBox(
                                width: 145,
                                child: TextField(
                                  controller: controllerBagus,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Qty BAGUS (Kembali)',
                                    labelStyle: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                                    prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 16),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Input Qty Retur RUSAK / BS
                              SizedBox(
                                width: 145,
                                child: TextField(
                                  controller: controllerRusak,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Qty RUSAK (Afkir)',
                                    labelStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
                                    prefixIcon: const Icon(Icons.report_problem_outlined, color: Colors.redAccent, size: 16),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Reason Text Input
                              Expanded(
                                child: TextField(
                                  controller: reasonController,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    labelText: 'Alasan Retur',
                                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    hintText: 'Misal: Kemasan rusak, kadaluarsa, dll',
                                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Subtotal Retur Item
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('SUBTOTAL RETUR', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
                                  Text(
                                    _currencyFormatter.format(itemReturnSubtotal),
                                    style: TextStyle(
                                      color: totalQtyItem > 0 ? Colors.amberAccent : Colors.white38,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
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
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSubmitting ? null : _submitReturn,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'Memproses...' : 'Simpan Retur Produk',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
