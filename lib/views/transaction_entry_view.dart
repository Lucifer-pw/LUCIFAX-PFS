import 'package:flutter/foundation.dart';
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
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _customerTextController = TextEditingController();
  final _productTextController = TextEditingController();
  bool _isBonus = false;

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void dispose() {
    _qtyController.dispose();
    _discountController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    _customerTextController.dispose();
    _productTextController.dispose();
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
    final customPrice = double.tryParse(_priceController.text);

    try {
      trProvider.addToCart(_selectedProduct!, qty, disc, customPrice: _isBonus ? 0 : customPrice, isBonus: _isBonus);
      // Reset inputs
      setState(() {
        _selectedProduct = null;
        _productTextController.clear();
        _qtyController.text = '1';
        _discountController.text = '0';
        _priceController.clear();
        _isBonus = false;
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
      _customerTextController.clear();
      _productTextController.clear();
      setState(() {
        _selectedCustomer = null;
        _selectedProduct = null;
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
                Text(
                  kIsWeb 
                      ? 'PDF berhasil dibuat dan diunduh otomatis.'
                      : 'PDF berhasil dibuat dan disimpan di: \n${pdfFile?.path ?? ""}', 
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)
                ),
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
                        content: Text(
                          kIsWeb
                              ? "File raw ESC/P berhasil diunduh!"
                              : "File raw ESC/P disimpan di: ${rawFile?.path ?? ''}"
                        ),
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
      _customerTextController.clear();
      _productTextController.clear();
      setState(() {
        _selectedCustomer = null;
        _selectedProduct = null;
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

    final leftPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Customer Card Info
        _buildFormSection(
          title: 'Data Pelanggan',
          icon: Icons.person_search_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Searchable & Typeable Customer Combobox
              SearchableCustomerField(
                selectedCustomer: _selectedCustomer,
                customers: customerProvider.customers,
                onSelected: (customer) {
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
              // Searchable & Typeable Product Combobox
              SearchableProductField(
                selectedProduct: _selectedProduct,
                products: productProvider.products,
                onSelected: (product) {
                  setState(() {
                    _selectedProduct = product;
                    if (product != null) {
                      _priceController.text = product.price.toStringAsFixed(0);
                    } else {
                      _priceController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              
              if (_selectedProduct != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Harga Master: ${_rupiahFormatter.format(_selectedProduct!.price)}',
                      style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      'Stok: ${_selectedProduct!.stock.toStringAsFixed(0)} pcs',
                      style: TextStyle(
                        color: _selectedProduct!.stock <= 0 ? Colors.redAccent : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration(hint: 'Harga Transaksi (Rp)', icon: Icons.payments_outlined),
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
              const SizedBox(height: 12),

              // Bonus Checkbox
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isBonus = !_isBonus;
                    if (_isBonus) {
                      _priceController.text = '0';
                      _discountController.text = '0';
                    } else if (_selectedProduct != null) {
                      _priceController.text = _selectedProduct!.price.toStringAsFixed(0);
                      _discountController.text = '0';
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isBonus ? Colors.green.withOpacity(0.15) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isBonus ? Colors.greenAccent : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isBonus ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        color: _isBonus ? Colors.greenAccent : const Color(0xFF64748B),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'BONUS (Gratis / Harga Rp 0)',
                        style: TextStyle(
                          color: _isBonus ? Colors.greenAccent : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (_isBonus) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'AKTIF',
                            style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Add to Cart Button
              ElevatedButton.icon(
                onPressed: () => _addItemToCart(trProvider),
                icon: const Icon(Icons.add_rounded),
                label: Text(_isBonus ? 'Tambah Bonus ke Invoice' : 'Tambah ke Invoice'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: _isBonus ? Colors.green[700] : const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final rightPanel = Column(
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
                    rows: trProvider.cartItems.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(item.productName, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
                                    ),
                                    if (item.isBonus) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                                        ),
                                        child: const Text('BONUS', style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                                Text('${item.weightKg.toStringAsFixed(2)} Kg', style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                              ],
                            ),
                          ),
                          DataCell(Text(item.qty.toStringAsFixed(0), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(
                            item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price),
                            style: TextStyle(color: item.isBonus ? Colors.greenAccent : Colors.white, fontSize: 12),
                          )),
                          DataCell(Text(item.isBonus ? '-' : (item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(1)}%' : '-'), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(
                            item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal),
                            style: TextStyle(color: item.isBonus ? Colors.greenAccent : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          )),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              onPressed: () => trProvider.removeFromCart(item.productId, index: idx),
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
              const SizedBox(height: 20),
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
    );

    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: SingleChildScrollView(child: leftPanel),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: SingleChildScrollView(child: rightPanel),
            ),
          ],
        ),
      );
    } else {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            leftPanel,
            const SizedBox(height: 24),
            rightPanel,
          ],
        ),
      );
    }
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

class SearchableCustomerField extends StatefulWidget {
  final Customer? selectedCustomer;
  final List<Customer> customers;
  final ValueChanged<Customer?> onSelected;

  const SearchableCustomerField({
    super.key,
    required this.selectedCustomer,
    required this.customers,
    required this.onSelected,
  });

  @override
  State<SearchableCustomerField> createState() => _SearchableCustomerFieldState();
}

class _SearchableCustomerFieldState extends State<SearchableCustomerField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Customer> _filteredCustomers = [];

  @override
  void initState() {
    super.initState();
    _filteredCustomers = widget.customers;
    if (widget.selectedCustomer != null) {
      _controller.text = '${widget.selectedCustomer!.aliasName} (${widget.selectedCustomer!.customerName})';
    }

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            _hideOverlay();
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(SearchableCustomerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCustomer == null && oldWidget.selectedCustomer != null) {
      _controller.clear();
      _filteredCustomers = widget.customers;
    } else if (widget.selectedCustomer != null && widget.selectedCustomer != oldWidget.selectedCustomer) {
      _controller.text = '${widget.selectedCustomer!.aliasName} (${widget.selectedCustomer!.customerName})';
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      if (cleanQuery.isEmpty) {
        _filteredCustomers = widget.customers;
      } else {
        _filteredCustomers = widget.customers.where((c) {
          final alias = c.aliasName.toLowerCase();
          final name = c.customerName.toLowerCase();
          final city = c.city.toLowerCase();
          final id = c.id.toLowerCase();
          return alias.contains(cleanQuery) ||
                 name.contains(cleanQuery) ||
                 city.contains(cleanQuery) ||
                 id.contains(cleanQuery);
        }).toList();
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _showOverlay() {
    _hideOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 6.0),
          child: Material(
            elevation: 8.0,
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
              ),
              child: _filteredCustomers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Pelanggan tidak ditemukan', style: TextStyle(color: Color(0xFF94A3B8))),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final c = _filteredCustomers[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${c.aliasName} (${c.customerName})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            'ID: ${c.id} • ${c.city}, ${c.province}',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          onTap: () {
                            _controller.text = '${c.aliasName} (${c.customerName})';
                            widget.onSelected(c);
                            _focusNode.unfocus();
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Pilih / Ketik Nama Pelanggan...',
          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
          suffixIcon: IconButton(
            icon: Icon(
              _focusNode.hasFocus ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              color: const Color(0xFF38BDF8),
              size: 28,
            ),
            onPressed: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else {
                _focusNode.requestFocus();
              }
            },
          ),
        ),
        onChanged: (val) {
          widget.onSelected(null);
          _filter(val);
        },
      ),
    );
  }
}

class SearchableProductField extends StatefulWidget {
  final Product? selectedProduct;
  final List<Product> products;
  final ValueChanged<Product?> onSelected;

  const SearchableProductField({
    super.key,
    required this.selectedProduct,
    required this.products,
    required this.onSelected,
  });

  @override
  State<SearchableProductField> createState() => _SearchableProductFieldState();
}

class _SearchableProductFieldState extends State<SearchableProductField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Product> _filteredProducts = [];

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
    if (widget.selectedProduct != null) {
      _controller.text = widget.selectedProduct!.name;
    }

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            _hideOverlay();
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(SearchableProductField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedProduct == null && oldWidget.selectedProduct != null) {
      _controller.clear();
      _filteredProducts = widget.products;
    } else if (widget.selectedProduct != null && widget.selectedProduct != oldWidget.selectedProduct) {
      _controller.text = widget.selectedProduct!.name;
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      if (cleanQuery.isEmpty) {
        _filteredProducts = widget.products;
      } else {
        _filteredProducts = widget.products.where((p) {
          final name = p.name.toLowerCase();
          final id = p.id.toLowerCase();
          return name.contains(cleanQuery) || id.contains(cleanQuery);
        }).toList();
      }
    });
    _overlayEntry?.markNeedsBuild();
  }

  void _showOverlay() {
    _hideOverlay();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0.0, size.height + 6.0),
          child: Material(
            elevation: 8.0,
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 250),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
              ),
              child: _filteredProducts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Produk tidak ditemukan', style: TextStyle(color: Color(0xFF94A3B8))),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = _filteredProducts[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            p.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            'Harga: ${_rupiahFormatter.format(p.price)} • Stok: ${p.stock.toStringAsFixed(0)} pcs',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          onTap: () {
                            _controller.text = p.name;
                            widget.onSelected(p);
                            _focusNode.unfocus();
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Cari Produk...',
          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
          suffixIcon: IconButton(
            icon: Icon(
              _focusNode.hasFocus ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
              color: const Color(0xFF38BDF8),
              size: 28,
            ),
            onPressed: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else {
                _focusNode.requestFocus();
              }
            },
          ),
        ),
        onChanged: (val) {
          widget.onSelected(null);
          _filter(val);
        },
      ),
    );
  }
}
