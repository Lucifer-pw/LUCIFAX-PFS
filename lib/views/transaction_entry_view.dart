import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/product_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/print_service.dart';

class TransactionEntryView extends StatefulWidget {
  const TransactionEntryView({super.key});

  @override
  State<TransactionEntryView> createState() => _TransactionEntryViewState();
}

class _TransactionEntryViewState extends State<TransactionEntryView> {
  Customer? _selectedCustomer;
  Product? _selectedProduct;
  final _qtyController = TextEditingController(text: '1');
  final _discountController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void dispose() {
    _qtyController.dispose();
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _addItemToCart(TransactionProvider trProvider) {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih barang terlebih dahulu!'), backgroundColor: Colors.orange),
      );
      return;
    }

    final qty = double.tryParse(_qtyController.text) ?? 0.0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jumlah Qty harus lebih dari 0!'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Check if adding exceeds current product stock (optional, let's warn if stock is 0 or less, but allow if needed)
    if (_selectedProduct!.stock < qty) {
      // Just a warning
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Peringatan: Stok ${_selectedProduct!.name} tidak mencukupi (Tersedia: ${_selectedProduct!.stock})'),
          backgroundColor: Colors.amber[700],
        ),
      );
    }

    final disc = double.tryParse(_discountController.text) ?? 0.0;

    try {
      trProvider.addToCart(_selectedProduct!, qty, disc);
      // Reset inputs
      setState(() {
        _selectedProduct = null;
        _qtyController.text = '1';
        _discountController.text = '0';
      });
    } catch (e) {
      // 10-item limit exceeded!
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Batas Item Terpenuhi', style: TextStyle(color: Colors.white)),
          content: Text(e.toString().replaceAll('Exception: ', ''), style: const TextStyle(color: Color(0xFF94A3B8))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _submitAndPrint(TransactionProvider trProvider, String createdBy) async {
    try {
      trProvider.setNote(_noteController.text);
      
      // Save to Firebase and get transaction object directly
      final savedTransaction = await trProvider.submitTransaction(createdBy);

      // Generate local PDF and download
      final pdfFile = await PrintService.generateInvoicePdf(savedTransaction);
      
      _noteController.clear();
      setState(() {
        _selectedCustomer = null;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent),
                SizedBox(width: 12),
                Text('Transaksi Berhasil', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice #${savedTransaction.invoiceNo} berhasil disimpan!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('PDF berhasil dibuat dan diunduh di: \n${pdfFile.path}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              ],
            ),
            actions: [
              // Button to generate and print raw ESC/P text file
              ElevatedButton.icon(
                onPressed: () async {
                  final rawFile = await PrintService.saveEscPRawFile(savedTransaction);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("File raw ESC/P disimpan di: ${rawFile.path}"),
                        backgroundColor: Colors.teal,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('Simpan Raw ESC/P (LX300)', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0369A1)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _submitOnly(TransactionProvider trProvider, String createdBy) async {
    try {
      trProvider.setNote(_noteController.text);
      
      // Save to Firebase only
      final savedTransaction = await trProvider.submitTransaction(createdBy);
 
      _noteController.clear();
      setState(() {
        _selectedCustomer = null;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent),
                SizedBox(width: 12),
                Text('Transaksi Disimpan', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text('Invoice #${savedTransaction.invoiceNo} berhasil disimpan ke database (PO disimpan).', style: const TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup', style: TextStyle(color: Color(0xFF38BDF8))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerProvider = Provider.of<CustomerProvider>(context);
    final productProvider = Provider.of<ProductProvider>(context);
    final trProvider = Provider.of<TransactionProvider>(context);
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser!;

    final isDesktop = MediaQuery.of(context).size.width > 1000;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Flex(
        direction: isDesktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Panel: Form Input
          Expanded(
            flex: isDesktop ? 2 : 0,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Customer Card Info
                  _buildFormSection(
                    title: 'Data Pelanggan',
                    icon: Icons.person_search_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Search Combobox
                        DropdownButtonFormField<Customer>(
                          value: _selectedCustomer,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white),
                          decoration: _buildInputDecoration(hint: 'Pilih Pelanggan'),
                          items: customerProvider.customers.map((c) {
                            return DropdownMenuItem<Customer>(
                              value: c,
                              child: Text('${c.aliasName} (${c.customerName})'),
                            );
                          }).toList(),
                          onChanged: (customer) {
                            setState(() {
                              _selectedCustomer = customer;
                            });
                            if (customer != null) {
                              trProvider.setCustomer(
                                customer.id,
                                customer.customerName,
                                customer.aliasName,
                                customer.city,
                                customer.province,
                                customer.country,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Auto-filled client info
                        if (_selectedCustomer != null) ...[
                          _buildDetailRow('ID Customer', _selectedCustomer!.id),
                          _buildDetailRow('Alamat', _selectedCustomer!.address),
                          _buildDetailRow('Kota/Provinsi', '${_selectedCustomer!.city}, ${_selectedCustomer!.province}'),
                          const SizedBox(height: 12),
                        ],
                        
                        // Date Picker Input
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Tanggal Pengiriman:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          subtitle: Text(
                            DateFormat('dd MMMM yyyy').format(trProvider.deliveryDate),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: trProvider.deliveryDate,
                              firstDate: DateTime(2025),
                              lastDate: DateTime(2030),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: const ColorScheme.dark(
                                      primary: Color(0xFF38BDF8),
                                      onPrimary: Colors.white,
                                      surface: Color(0xFF1E293B),
                                      onSurface: Colors.white,
                                    ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              trProvider.setDeliveryDate(picked);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Product Adder Form
                  _buildFormSection(
                    title: 'Pilih & Tambah Barang',
                    icon: Icons.add_shopping_cart_rounded,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Search Combobox
                        DropdownButtonFormField<Product>(
                          value: _selectedProduct,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white),
                          decoration: _buildInputDecoration(hint: 'Cari Produk'),
                          items: productProvider.products.map((p) {
                            return DropdownMenuItem<Product>(
                              value: p,
                              child: Text(p.name),
                            );
                          }).toList(),
                          onChanged: (product) {
                            setState(() {
                              _selectedProduct = product;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        if (_selectedProduct != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Harga: ${_rupiahFormatter.format(_selectedProduct!.price)}',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Stok: ${_selectedProduct!.stock.toStringAsFixed(0)} pcs',
                                style: TextStyle(
                                  color: _selectedProduct!.stock <= 0 ? Colors.redAccent : Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Qty and Discount Inputs
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _qtyController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(color: Colors.white),
                                decoration: _buildInputDecoration(hint: 'Qty (Pcs)', icon: Icons.numbers),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _discountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.white),
                                decoration: _buildInputDecoration(hint: 'Diskon %', icon: Icons.percent),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Add to Cart Button
                        ElevatedButton.icon(
                          onPressed: () => _addItemToCart(trProvider),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Tambah ke Invoice'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: const Color(0xFF0284C7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (isDesktop) const SizedBox(width: 24),
          if (!isDesktop) const SizedBox(height: 24),

          // Right Panel: Invoice Cart View
          Expanded(
            flex: isDesktop ? 3 : 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cart Title / Constraints Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Rincian Cetak Invoice',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      // Continuous form limit badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: trProvider.cartItems.length >= 10 
                              ? Colors.redAccent.withOpacity(0.2) 
                              : const Color(0xFF0369A1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: trProvider.cartItems.length >= 10 ? Colors.redAccent : const Color(0xFF38BDF8),
                          ),
                        ),
                        child: Text(
                          'Kertas: ${trProvider.cartItems.length} / 10 Item',
                          style: TextStyle(
                            color: trProvider.cartItems.length >= 10 ? Colors.redAccent : const Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    ],
                  ),
                ),

                // Table of items
                Container(
                  color: const Color(0xFF1E293B),
                  constraints: const BoxConstraints(minHeight: 250, maxHeight: 400),
                  child: trProvider.cartItems.isEmpty
                      ? const Center(
                          child: Text(
                            'Transaksi kosong. Tambah barang terlebih dahulu.',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            horizontalMargin: 12,
                            columnSpacing: 10,
                            headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                            columns: const [
                              DataColumn(label: Text('Produk')),
                              DataColumn(label: Text('Qty'), numeric: true),
                              DataColumn(label: Text('Harga'), numeric: true),
                              DataColumn(label: Text('Disc'), numeric: true),
                              DataColumn(label: Text('Subtotal'), numeric: true),
                              DataColumn(label: Text('')),
                            ],
                            rows: trProvider.cartItems.map((item) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(item.productName, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                        Text('${item.weightKg.toStringAsFixed(2)} Kg', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(item.qty.toStringAsFixed(0), style: const TextStyle(color: Colors.white))),
                                  DataCell(Text(_rupiahFormatter.format(item.price), style: const TextStyle(color: Colors.white, fontSize: 12))),
                                  DataCell(Text(item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(1)}%' : '-', style: const TextStyle(color: Colors.white))),
                                  DataCell(Text(_rupiahFormatter.format(item.subtotal), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                      onPressed: () => trProvider.removeFromCart(item.productId),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),

                // Note & Submit Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Notes Input field
                      TextFormField(
                        controller: _noteController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white),
                        decoration: _buildInputDecoration(hint: 'Masukkan Catatan / Keterangan...', icon: Icons.notes_rounded),
                      ),
                      const SizedBox(height: 20),

                      // Grand total display
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'GRAND TOTAL:',
                            style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            _rupiahFormatter.format(trProvider.grandTotal),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: trProvider.cartItems.isEmpty || _selectedCustomer == null
                                  ? null
                                  : () => _submitOnly(trProvider, user.uid),
                              icon: const Icon(Icons.save_rounded, color: Colors.white),
                              label: const Text('Simpan Saja', style: TextStyle(color: Colors.white, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: Colors.teal[600],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: trProvider.cartItems.isEmpty || _selectedCustomer == null
                                  ? null
                                  : () => _submitAndPrint(trProvider, user.uid),
                              icon: const Icon(Icons.print_rounded, color: Colors.white),
                              label: const Text('Simpan & Cetak', style: TextStyle(color: Colors.white, fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFF0284C7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Builder for form input cards
  Widget _buildFormSection({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // Helper for text alignment rows
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // InputDecoration standard styling
  InputDecoration _buildInputDecoration({required String hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF64748B), size: 18) : null,
      filled: true,
      fillColor: const Color(0xFF0F172A),
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
