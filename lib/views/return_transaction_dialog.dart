import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart' as model_tr;
import '../models/transaction_return.dart';
import '../providers/transaction_provider.dart';
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

  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _reasonControllers = {};
  final Map<String, String> _conditionMap = {};

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.transaction.items) {
      _qtyControllers[item.productId] = TextEditingController(text: '0');
      _reasonControllers[item.productId] = TextEditingController(text: 'Barang Diretur');
      _conditionMap[item.productId] = 'BAGUS';
    }
  }

  @override
  void dispose() {
    for (var controller in _qtyControllers.values) {
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
      final qtyText = _qtyControllers[item.productId]?.text ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;
      if (qty > 0) {
        final effPrice = _getEffectiveUnitPrice(item);
        total += qty * effPrice;
      }
    }
    return total;
  }

  Future<void> _submitReturn() async {
    final List<ReturnItem> returnItems = [];
    double totalReturnAmount = 0.0;

    for (var item in widget.transaction.items) {
      final qtyText = _qtyControllers[item.productId]?.text.trim() ?? '0';
      final qty = double.tryParse(qtyText) ?? 0.0;

      if (qty > item.qty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Qty retur untuk ${item.productName} tidak boleh melebihi qty awal (${item.qty.toInt()} pcs)!'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (qty > 0) {
        final effPrice = _getEffectiveUnitPrice(item);
        final subtotal = qty * effPrice;
        final condition = _conditionMap[item.productId] ?? 'BAGUS';
        final reason = _reasonControllers[item.productId]?.text.trim() ?? 'Retur Produk';

        totalReturnAmount += subtotal;
        returnItems.add(
          ReturnItem(
            productId: item.productId,
            productName: item.productName,
            qtyReturned: qty,
            price: item.price,
            discountPercent: item.discountPercent,
            effectiveUnitPrice: effPrice,
            subtotalReturn: subtotal,
            sizeGrams: item.sizeGrams,
            isBonus: item.isBonus,
            condition: condition,
            reason: reason,
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
        width: 800,
        height: 520,
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
                    final controller = _qtyControllers[item.productId]!;
                    final reasonController = _reasonControllers[item.productId]!;
                    final currentQty = double.tryParse(controller.text) ?? 0.0;
                    final itemReturnSubtotal = currentQty * effPrice;

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: currentQty > 0 ? Colors.amber.withOpacity(0.5) : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Item Title & Price Row
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
                              Text(
                                'Qty Asal: ${item.qty.toInt()} pcs | Harga Bersih: ${_currencyFormatter.format(effPrice)}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
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

                          // Controls Row: Qty Retur Input + Condition Dropdown + Reason
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Qty Input
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: controller,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'Qty Retur (pcs)',
                                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  onChanged: (val) {
                                    setState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Condition Selector
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _conditionMap[item.productId] ?? 'BAGUS',
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'BAGUS',
                                        child: Row(
                                          children: [
                                            Icon(Icons.inventory_rounded, color: Colors.greenAccent, size: 14),
                                            SizedBox(width: 6),
                                            Text('BAGUS (Stok Kembali)', style: TextStyle(color: Colors.greenAccent)),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'RUSAK_BS',
                                        child: Row(
                                          children: [
                                            Icon(Icons.report_problem_rounded, color: Colors.redAccent, size: 14),
                                            SizedBox(width: 6),
                                            Text('RUSAK/BS (Afkir)', style: TextStyle(color: Colors.redAccent)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _conditionMap[item.productId] = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Reason Text Input
                              Expanded(
                                child: TextField(
                                  controller: reasonController,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  decoration: InputDecoration(
                                    labelText: 'Alasan Retur',
                                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                    hintText: 'Misal: Rusak kemasan, basi, dll',
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
                                      color: currentQty > 0 ? Colors.amberAccent : Colors.white38,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
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
