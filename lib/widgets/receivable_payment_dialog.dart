import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/receivable.dart';
import '../providers/receivable_provider.dart';
import '../providers/customer_provider.dart';

Future<void> showReceivablePaymentDialog(
  BuildContext context, {
  required Receivable item,
  String? customerId,
  double depositBalance = 0.0,
}) async {
  final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFormatter = DateFormat('dd-MM-yyyy');

  DateTime chosenDate = DateTime.now();
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  String selectedMethod = 'Transfer BCA';
  bool useDeposit = false;
  double depositAmountToUse = 0.0;

  if (item.remainingAmount > 0) {
    amountController.text = item.remainingAmount.toStringAsFixed(0);
  }

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        final currentRemaining = item.remainingAmount;
        final double inputNominal = double.tryParse(amountController.text.replaceAll('.', '').replaceAll(',', '')) ?? 0.0;
        final double effectiveDepositDeduction = useDeposit ? depositAmountToUse : 0.0;
        final double totalPaymentEntered = inputNominal + effectiveDepositDeduction;
        final double overpayment = totalPaymentEntered > currentRemaining ? (totalPaymentEntered - currentRemaining) : 0.0;

        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_rounded, color: Color(0xFF38BDF8), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pembayaran #${item.noInvoice}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      item.toko,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (item.isLunas)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: const Text('LUNAS ✅', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Box: Total, Paid, Sisa
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Tagihan:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            Text(currencyFormatter.format(item.effectiveNominal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sudah Terbayar:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            Text(currencyFormatter.format(item.effectivePaidAmount), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const Divider(color: Color(0xFF334155), height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa Tagihan:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              currencyFormatter.format(currentRemaining),
                              style: TextStyle(
                                color: currentRemaining <= 0 ? Colors.greenAccent : Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Deposit Balance Banner (if customer has deposit)
                  if (depositBalance > 0 && customerId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.account_balance_wallet, color: Colors.purpleAccent, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Customer memiliki Saldo Deposit: ${currencyFormatter.format(depositBalance)}',
                                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              setDlgState(() {
                                useDeposit = !useDeposit;
                                if (useDeposit) {
                                  depositAmountToUse = depositBalance > currentRemaining ? currentRemaining : depositBalance;
                                  final leftover = currentRemaining - depositAmountToUse;
                                  amountController.text = leftover > 0 ? leftover.toStringAsFixed(0) : '0';
                                } else {
                                  depositAmountToUse = 0.0;
                                  amountController.text = currentRemaining.toStringAsFixed(0);
                                }
                              });
                            },
                            child: Row(
                              children: [
                                Checkbox(
                                  value: useDeposit,
                                  activeColor: Colors.purpleAccent,
                                  onChanged: (val) {
                                    setDlgState(() {
                                      useDeposit = val ?? false;
                                      if (useDeposit) {
                                        depositAmountToUse = depositBalance > currentRemaining ? currentRemaining : depositBalance;
                                        final leftover = currentRemaining - depositAmountToUse;
                                        amountController.text = leftover > 0 ? leftover.toStringAsFixed(0) : '0';
                                      } else {
                                        depositAmountToUse = 0.0;
                                        amountController.text = currentRemaining.toStringAsFixed(0);
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    'Gunakan Saldo Deposit (${currencyFormatter.format(useDeposit ? depositAmountToUse : (depositBalance > currentRemaining ? currentRemaining : depositBalance))})',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Input Form (Only if not fully paid OR if user wants to add payment)
                  if (currentRemaining > 0 || totalPaymentEntered > 0) ...[
                    const Text('Pencatatan Pembayaran Baru', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // Tanggal Pembayaran
                    const Text('Tanggal Pembayaran / Transfer:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    const SizedBox(height: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                    const SizedBox(height: 10),

                    // Metode Bayar
                    const Text('Metode Pembayaran:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedMethod,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'Transfer BCA', child: Text('Transfer BCA')),
                            DropdownMenuItem(value: 'Transfer Mandiri', child: Text('Transfer Mandiri')),
                            DropdownMenuItem(value: 'Transfer BRI', child: Text('Transfer BRI')),
                            DropdownMenuItem(value: 'Tunai / Cash', child: Text('Tunai / Cash')),
                            DropdownMenuItem(value: 'Giro / Cek', child: Text('Giro / Cek')),
                            DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya')),
                          ],
                          onChanged: (val) {
                            if (val != null) setDlgState(() => selectedMethod = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Nominal Bayar Input & Quick Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Nominal Pembayaran:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        if (currentRemaining > 0)
                          InkWell(
                            onTap: () {
                              setDlgState(() {
                                final needed = useDeposit ? (currentRemaining - depositAmountToUse) : currentRemaining;
                                amountController.text = needed > 0 ? needed.toStringAsFixed(0) : '0';
                              });
                            },
                            child: Text(
                              'Isi Sisa Tagihan (${currencyFormatter.format(useDeposit ? (currentRemaining - depositAmountToUse) : currentRemaining)})',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                      ),
                      onChanged: (_) => setDlgState(() {}),
                    ),

                    // Overpayment Alert
                    if (overpayment > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.tealAccent.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.tealAccent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Kelebihan ${currencyFormatter.format(overpayment)} akan otomatis ditambahkan ke Saldo Deposit customer!',
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Catatan
                    const Text('Catatan / Keterangan (Opsional):', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Misal: Cicilan ke-1, transfer Bpk Budi...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                      ),
                    ),
                  ],

                  // Riwayat Pembayaran (jika ada)
                  if (item.payments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Riwayat Pembayaran / Cicilan:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: item.payments.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                        itemBuilder: (context, pIdx) {
                          final p = item.payments[pIdx];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${dateFormatter.format(p.date)} (${p.paymentMethod})',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  currencyFormatter.format(p.amount),
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            subtitle: p.note.isNotEmpty
                                ? Text(p.note, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11))
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              tooltip: 'Hapus Catatan Pembayaran Ini',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: ctx,
                                  builder: (c) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E293B),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    title: const Text('Hapus Catatan Pembayaran?', style: TextStyle(color: Colors.white, fontSize: 14)),
                                    content: Text(
                                      'Nominal ${currencyFormatter.format(p.amount)} akan ditarik kembali dari status terbayar.',
                                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  final provider = Provider.of<ReceivableProvider>(context, listen: false);
                                  await provider.deletePaymentRecord(
                                    receivableId: item.id,
                                    noInvoice: item.noInvoice,
                                    paymentId: p.id,
                                  );
                                  Navigator.pop(ctx);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            // Tombol Reset ke Belum Lunas jika sudah lunas atau ada cicilan
            if (item.isLunas || item.payments.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.replay_rounded, size: 16, color: Colors.orangeAccent),
                label: const Text('Reset ke Belum Lunas', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: const Text('Reset ke Belum Lunas?', style: TextStyle(color: Colors.white, fontSize: 14)),
                      content: Text(
                        'Seluruh riwayat pembayaran invoice #${item.noInvoice} akan di-reset dan status menjadi BELUM LUNAS.',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Reset Sekarang', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final provider = Provider.of<ReceivableProvider>(context, listen: false);
                    await provider.markLunasWithDate(item.id, item.noInvoice, false, null);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Invoice #${item.noInvoice} berhasil di-reset ke BELUM LUNAS.'),
                        backgroundColor: Colors.orange[800],
                      ),
                    );
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            if (currentRemaining > 0 || totalPaymentEntered > 0)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                label: const Text('Simpan Pembayaran', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  if (totalPaymentEntered <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Nominal pembayaran belum diisi!'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  final provider = Provider.of<ReceivableProvider>(context, listen: false);

                  // 1. Process deposit payment if selected
                  if (useDeposit && depositAmountToUse > 0 && customerId != null) {
                    await provider.recordPayment(
                      receivableId: item.id,
                      noInvoice: item.noInvoice,
                      paymentAmount: depositAmountToUse,
                      paymentDate: chosenDate,
                      note: 'Potong Saldo Deposit: ${noteController.text.trim()}',
                      paymentMethod: 'Saldo Deposit',
                      customerId: customerId,
                    );
                    final custProv = Provider.of<CustomerProvider>(context, listen: false);
                    await custProv.updateCustomerDeposit(customerId, depositBalance - depositAmountToUse);
                  }

                  // 2. Process cash/transfer payment
                  if (inputNominal > 0) {
                    final double remainingAfterDeposit = currentRemaining - (useDeposit ? depositAmountToUse : 0.0);
                    final double payForReceivable = inputNominal > remainingAfterDeposit ? (remainingAfterDeposit > 0 ? remainingAfterDeposit : 0.0) : inputNominal;
                    final double overpaymentAmount = inputNominal > remainingAfterDeposit ? (inputNominal - (remainingAfterDeposit > 0 ? remainingAfterDeposit : 0.0)) : 0.0;

                    await provider.recordPayment(
                      receivableId: item.id,
                      noInvoice: item.noInvoice,
                      paymentAmount: payForReceivable,
                      paymentDate: chosenDate,
                      note: noteController.text.trim(),
                      paymentMethod: selectedMethod,
                      overpaymentToDeposit: overpaymentAmount,
                      customerId: customerId,
                    );

                    if (overpaymentAmount > 0 && customerId != null) {
                      final custProv = Provider.of<CustomerProvider>(context, listen: false);
                      final currentDep = (useDeposit ? (depositBalance - depositAmountToUse) : depositBalance);
                      await custProv.updateCustomerDeposit(customerId, currentDep + overpaymentAmount);
                    }
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Pembayaran invoice #${item.noInvoice} berhasil dicatat.'),
                      backgroundColor: Colors.teal,
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}
