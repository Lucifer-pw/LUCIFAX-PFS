import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
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
  final _kartonController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _customerTextController = TextEditingController();
  final _productTextController = TextEditingController();

  final _customerFocusNode = FocusNode();
  final _deliveryDateFocusNode = FocusNode();
  final _invoiceTypeFocusNode = FocusNode();
  final _productFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();
  final _kartonFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();
  final _discountFocusNode = FocusNode();
  final _addButtonFocusNode = FocusNode();

  bool _isBonus = false;
  bool _isSaving = false;
  bool _isUpdatingFromKarton = false;
  bool _isUpdatingFromQty = false;
  String _idempotencyKey = const Uuid().v4();

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _customerFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _kartonController.dispose();
    _discountController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    _customerTextController.dispose();
    _productTextController.dispose();

    _customerFocusNode.dispose();
    _deliveryDateFocusNode.dispose();
    _invoiceTypeFocusNode.dispose();
    _productFocusNode.dispose();
    _priceFocusNode.dispose();
    _kartonFocusNode.dispose();
    _qtyFocusNode.dispose();
    _discountFocusNode.dispose();
    _addButtonFocusNode.dispose();

    super.dispose();
  }

  void _onKartonChanged(String value) {
    if (_isUpdatingFromQty) return;
    final isiKarton = _selectedProduct?.isiKarton ?? 0;
    if (isiKarton <= 0) return;
    _isUpdatingFromKarton = true;
    final karton = double.tryParse(value) ?? 0;
    final qty = (karton * isiKarton).round();
    _qtyController.text = qty > 0 ? qty.toString() : '';
    _isUpdatingFromKarton = false;
  }

  void _onQtyChanged(String value) {
    if (_isUpdatingFromKarton) return;
    final isiKarton = _selectedProduct?.isiKarton ?? 0;
    if (isiKarton <= 0) return;
    _isUpdatingFromQty = true;
    final qty = double.tryParse(value) ?? 0;
    final karton = qty / isiKarton;
    _kartonController.text = karton > 0 ? karton.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '') : '';
    _isUpdatingFromQty = false;
  }

  Future<void> _openDatePicker(TransactionProvider trProvider) async {
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
        _kartonController.clear();
        _discountController.text = '0';
        _priceController.clear();
        _isBonus = false;
      });
      _productFocusNode.requestFocus();
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
    if (_isSaving) return; // Prevent double-click
    setState(() => _isSaving = true);
    try {
      trProvider.setNote(_noteController.text);
      
      // Save to Firebase with idempotency key
      final savedTransaction = await trProvider.submitTransaction(createdBy, idempotencyKey: _idempotencyKey);

      // Generate local PDF and download
      final pdfFile = await PrintService.generateInvoicePdf(savedTransaction);
      
      _noteController.clear();
      _customerTextController.clear();
      _productTextController.clear();
      setState(() {
        _selectedCustomer = null;
        _selectedProduct = null;
        _isSaving = false;
        _idempotencyKey = const Uuid().v4(); // Regenerate for next invoice
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
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _submitOnly(TransactionProvider trProvider, String createdBy) async {
    if (_isSaving) return; // Prevent double-click
    setState(() => _isSaving = true);
    try {
      trProvider.setNote(_noteController.text);
      
      // Save to Firebase with idempotency key
      final savedTransaction = await trProvider.submitTransaction(createdBy, idempotencyKey: _idempotencyKey);
 
      _noteController.clear();
      _customerTextController.clear();
      _productTextController.clear();
      setState(() {
        _selectedCustomer = null;
        _selectedProduct = null;
        _isSaving = false;
        _idempotencyKey = const Uuid().v4(); // Regenerate for next invoice
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
        setState(() => _isSaving = false);
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
    final isMobile = MediaQuery.of(context).size.width < 768;

    final prodMap = {for (var p in productProvider.products) p.name.toLowerCase().trim(): p};
    final prodCodeMap = {for (var p in productProvider.products) p.kodeInduk.toLowerCase().trim(): p};
    final prodIdMap = {for (var p in productProvider.products) p.id: p};

    double grandTotalKarton = 0.0;
    for (var item in trProvider.cartItems) {
      Product? product = prodMap[item.productName.toLowerCase().trim()] ??
          prodCodeMap[item.productId.toLowerCase().trim()] ??
          prodIdMap[item.productId];
      final isiKarton = product?.isiKarton ?? 0;
      if (isiKarton > 0 && item.qty > 0) {
        grandTotalKarton += (item.qty / isiKarton);
      }
    }
    final grandTotalKartonStr = (grandTotalKarton % 1 == 0
            ? grandTotalKarton.toInt().toString()
            : grandTotalKarton.toStringAsFixed(1)) +
        ' Ktn';

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
                focusNode: _customerFocusNode,
                onNextFocus: () => _productFocusNode.requestFocus(),
                onNextTabFocus: () => _deliveryDateFocusNode.requestFocus(),
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
              
              // Date Picker Input with Keyboard Focus
              Focus(
                focusNode: _deliveryDateFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
                    _openDatePicker(trProvider);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.tab) {
                    if (HardwareKeyboard.instance.isShiftPressed) {
                      _customerFocusNode.requestFocus();
                    } else {
                      _invoiceTypeFocusNode.requestFocus();
                    }
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: hasFocus ? const Color(0xFF0284C7).withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: hasFocus ? const Color(0xFF38BDF8) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        title: const Text('Tanggal Pengiriman:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                        subtitle: Text(
                          DateFormat('dd MMMM yyyy').format(trProvider.deliveryDate),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        trailing: const Icon(Icons.calendar_today_rounded, color: Color(0xFF38BDF8)),
                        onTap: () => _openDatePicker(trProvider),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // Invoice Type & Numbering Option Dropdown (PO vs SA) with Keyboard Focus
              Focus(
                focusNode: _invoiceTypeFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    final newType = trProvider.invoiceType == 'PO' ? 'SA' : 'PO';
                    trProvider.setInvoiceType(newType);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.tab) {
                    if (HardwareKeyboard.instance.isShiftPressed) {
                      _deliveryDateFocusNode.requestFocus();
                    } else {
                      _productFocusNode.requestFocus();
                    }
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    _productFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasFocus ? const Color(0xFF38BDF8) : const Color(0xFF38BDF8).withOpacity(0.2),
                          width: hasFocus ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, color: Color(0xFF38BDF8), size: 18),
                              const SizedBox(width: 8),
                              const Text('Jenis Invoice:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: trProvider.invoiceType,
                                    dropdownColor: const Color(0xFF1E293B),
                                    isExpanded: true,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'PO',
                                        child: Row(
                                          children: [
                                            Icon(Icons.shopping_bag_rounded, color: Colors.greenAccent, size: 16),
                                            SizedBox(width: 6),
                                            Text('PO (Penjualan)'),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'SA',
                                        child: Row(
                                          children: [
                                            Icon(Icons.card_giftcard_rounded, color: Colors.amberAccent, size: 16),
                                            SizedBox(width: 6),
                                            Text('SA (Sample / Bonus)'),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        trProvider.setInvoiceType(val);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                    if (trProvider.invoiceType == 'SA') ...[
                      const SizedBox(height: 10),
                      FutureBuilder<String>(
                        future: trProvider.peekNextInvoiceNo(),
                        builder: (context, snapshot) {
                          final autoSaNo = snapshot.data ?? 'SA55';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Counter Otomatis Berikutnya: $autoSaNo',
                                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              TextFormField(
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'No. Invoice SA (Default Otomatis: $autoSaNo)',
                                  labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                                  hintText: 'Kosongkan untuk otomatis ($autoSaNo), atau ketik nomor manual',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF38BDF8))),
                                ),
                                onChanged: (val) {
                                  trProvider.setInvoiceType('SA', customSaNo: val);
                                },
                              ),
                            ],
                          );
                        },
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
                focusNode: _productFocusNode,
                onPrevFocus: () => _invoiceTypeFocusNode.requestFocus(),
                onNextFocus: () {
                  if (_selectedProduct != null && _selectedProduct!.isiKarton > 0) {
                    _kartonFocusNode.requestFocus();
                  } else {
                    _qtyFocusNode.requestFocus();
                  }
                },
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
                  focusNode: _priceFocusNode,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  onFieldSubmitted: (_) {
                    if (_selectedProduct != null && _selectedProduct!.isiKarton > 0) {
                      _kartonFocusNode.requestFocus();
                    } else {
                      _qtyFocusNode.requestFocus();
                    }
                  },
                  decoration: _buildInputDecoration(hint: 'Harga Transaksi (Rp)', icon: Icons.payments_outlined),
                ),
                const SizedBox(height: 16),
              ],

              // Karton, Qty and Discount Inputs
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _kartonController,
                      focusNode: _kartonFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      enabled: _selectedProduct != null && (_selectedProduct!.isiKarton) > 0,
                      onChanged: _onKartonChanged,
                      onFieldSubmitted: (_) => _qtyFocusNode.requestFocus(),
                      decoration: _buildInputDecoration(
                        hint: _selectedProduct != null && _selectedProduct!.isiKarton > 0
                            ? 'Karton (1 = ${_selectedProduct!.isiKarton} Pack)'
                            : 'Karton',
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _qtyController,
                      focusNode: _qtyFocusNode,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      onChanged: _onQtyChanged,
                      onFieldSubmitted: (_) => _addItemToCart(trProvider),
                      decoration: _buildInputDecoration(hint: 'Qty (Pack)', icon: Icons.numbers),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      focusNode: _discountFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      onFieldSubmitted: (_) => _addItemToCart(trProvider),
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

              // Add to Cart Button with Keyboard Focus
              Focus(
                focusNode: _addButtonFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
                    _addItemToCart(trProvider);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.tab && HardwareKeyboard.instance.isShiftPressed) {
                    _discountFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: hasFocus
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF38BDF8).withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _addItemToCart(trProvider),
                        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                        label: Text(
                          _isBonus ? 'Tambah Bonus ke Invoice' : 'Tambah ke Invoice',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _isBonus ? Colors.green[700] : const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    );
                  },
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
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 12),
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
                  color: trProvider.cartItems.length >= 14 
                      ? Colors.redAccent.withOpacity(0.2) 
                      : const Color(0xFF0369A1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: trProvider.cartItems.length >= 14 ? Colors.redAccent : const Color(0xFF38BDF8),
                  ),
                ),
                child: Text(
                  'Kertas: ${trProvider.cartItems.length} / 14 Item',
                  style: TextStyle(
                    color: trProvider.cartItems.length >= 14 ? Colors.redAccent : const Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
        ),

        // Table of items with responsive horizontal scroll
        Container(
          color: const Color(0xFF1E293B),
          constraints: BoxConstraints(minHeight: isMobile ? 160 : 220, maxHeight: 400),
          child: trProvider.cartItems.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'Transaksi kosong. Tambah barang terlebih dahulu.',
                      style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          horizontalMargin: isMobile ? 10 : 14,
                          columnSpacing: isMobile ? 12 : 16,
                          headingTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
                          columns: const [
                            DataColumn(label: Text('Produk')),
                            DataColumn(label: Text('Qty'), numeric: true),
                            DataColumn(label: Text('Total Karton'), numeric: true),
                            DataColumn(label: Text('Harga'), numeric: true),
                            DataColumn(label: Text('Disc'), numeric: true),
                            DataColumn(label: Text('Subtotal'), numeric: true),
                            DataColumn(label: Text('')),
                          ],
                          rows: trProvider.cartItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;

                            Product? product = prodMap[item.productName.toLowerCase().trim()] ??
                                prodCodeMap[item.productId.toLowerCase().trim()] ??
                                prodIdMap[item.productId];
                            final isiKarton = product?.isiKarton ?? 0;
                            final totalKarton = (isiKarton > 0 && item.qty > 0) ? (item.qty / isiKarton) : 0.0;
                            final totalKartonStr = (isiKarton > 0 && item.qty > 0)
                                ? ((totalKarton % 1 == 0 ? totalKarton.toInt().toString() : totalKarton.toStringAsFixed(1)) + ' Ktn')
                                : '-';

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
                                            child: Text(
                                              item.productName,
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
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
                                DataCell(Text(item.qty.toStringAsFixed(0), style: const TextStyle(color: Colors.white, fontSize: 12))),
                                DataCell(Text(
                                  totalKartonStr,
                                  style: TextStyle(
                                    color: totalKarton > 0 ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                                    fontSize: 12,
                                    fontWeight: totalKarton > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                )),
                                DataCell(Text(
                                  item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.price),
                                  style: TextStyle(color: item.isBonus ? Colors.greenAccent : Colors.white, fontSize: 12),
                                )),
                                DataCell(Text(
                                  item.isBonus ? '-' : (item.discountPercent > 0 ? '${item.discountPercent.toStringAsFixed(1)}%' : '-'),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                )),
                                DataCell(Text(
                                  item.isBonus ? 'Rp 0' : _rupiahFormatter.format(item.subtotal),
                                  style: TextStyle(color: item.isBonus ? Colors.greenAccent : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                )),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                    onPressed: () => trProvider.removeFromCart(item.productId, index: idx),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        // Note & Submit Card
        Container(
          padding: EdgeInsets.all(isMobile ? 14 : 20),
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
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _buildInputDecoration(hint: 'Masukkan Catatan / Keterangan...', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 14),

              // Grand total highlight card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GrandTotal Karton:',
                          style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                          ),
                          child: Text(
                            grandTotalKartonStr,
                            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Color(0xFF1E293B), height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'GRAND TOTAL:',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          _rupiahFormatter.format(trProvider.grandTotal),
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: trProvider.cartItems.isEmpty || _selectedCustomer == null || _isSaving
                          ? null
                          : () async => await _submitOnly(trProvider, user.uid),
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                      label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Saja (Ctrl + S)', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _isSaving ? Colors.teal[800] : Colors.teal[600],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: trProvider.cartItems.isEmpty || _selectedCustomer == null || _isSaving
                          ? null
                          : () async => await _submitAndPrint(trProvider, user.uid),
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.print_rounded, color: Colors.white, size: 18),
                      label: Text(_isSaving ? 'Menyimpan...' : 'Simpan & Cetak (Ctrl + Enter)', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: _isSaving ? const Color(0xFF015B8C) : const Color(0xFF0284C7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
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

    final mainContent = isDesktop
        ? Padding(
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
          )
        : SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
            child: Column(
              children: [
                leftPanel,
                SizedBox(height: isMobile ? 16 : 24),
                rightPanel,
              ],
            ),
          );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (trProvider.cartItems.isNotEmpty && _selectedCustomer != null && !_isSaving) {
            _submitAndPrint(trProvider, user.uid);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (trProvider.cartItems.isNotEmpty && _selectedCustomer != null && !_isSaving) {
            _submitOnly(trProvider, user.uid);
          }
        },
      },
      child: Focus(
        autofocus: false,
        child: mainContent,
      ),
    );
  }

  // Builder for form input cards
  Widget _buildFormSection({required String title, required IconData icon, required Widget child}) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return Container(
      padding: EdgeInsets.all(isMobile ? 14.0 : 20.0),
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
  final FocusNode? focusNode;
  final VoidCallback? onNextFocus;
  final VoidCallback? onNextTabFocus;

  const SearchableCustomerField({
    super.key,
    required this.selectedCustomer,
    required this.customers,
    required this.onSelected,
    this.focusNode,
    this.onNextFocus,
    this.onNextTabFocus,
  });

  @override
  State<SearchableCustomerField> createState() => _SearchableCustomerFieldState();
}

class _SearchableCustomerFieldState extends State<SearchableCustomerField> {
  final TextEditingController _controller = TextEditingController();
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Customer> _filteredCustomers = [];
  int _highlightedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _filteredCustomers = widget.customers;
    if (widget.selectedCustomer != null) {
      _controller.text = '${widget.selectedCustomer!.aliasName} (${widget.selectedCustomer!.customerName})';
    }

    _focusNode.onKeyEvent = _onKeyEvent;

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            _hideOverlay();
          }
        }).catchError((_) {});
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_overlayEntry == null || !_overlayEntry!.mounted) {
        _showOverlay();
      } else if (_filteredCustomers.isNotEmpty) {
        setState(() {
          _highlightedIndex = (_highlightedIndex + 1).clamp(0, _filteredCustomers.length - 1);
        });
        _scrollToIndex(_highlightedIndex);
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_overlayEntry != null && _overlayEntry!.mounted && _filteredCustomers.isNotEmpty) {
        setState(() {
          _highlightedIndex = (_highlightedIndex - 1).clamp(0, _filteredCustomers.length - 1);
        });
        _scrollToIndex(_highlightedIndex);
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_overlayEntry != null &&
          _overlayEntry!.mounted &&
          _filteredCustomers.isNotEmpty &&
          _highlightedIndex >= 0 &&
          _highlightedIndex < _filteredCustomers.length) {
        final c = _filteredCustomers[_highlightedIndex];
        _selectCustomer(c);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      _hideOverlay();
      if (!HardwareKeyboard.instance.isShiftPressed) {
        if (widget.onNextTabFocus != null) {
          widget.onNextTabFocus!();
          return KeyEventResult.handled;
        } else if (widget.onNextFocus != null) {
          widget.onNextFocus!();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_overlayEntry != null && _overlayEntry!.mounted) {
        _hideOverlay();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 48.0;
    final targetOffset = index * itemHeight;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    final clampedOffset = targetOffset.clamp(minScroll, maxScroll);
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _selectCustomer(Customer c) {
    _controller.text = c.displayName;
    widget.onSelected(c);
    _hideOverlay();
    if (widget.onNextFocus != null) {
      widget.onNextFocus!();
    } else {
      _focusNode.unfocus();
    }
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
    _scrollController.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _filter(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      _highlightedIndex = 0;
      if (cleanQuery.isEmpty) {
        _filteredCustomers = widget.customers;
      } else {
        _filteredCustomers = widget.customers.where((c) {
          final alias = c.aliasName.toLowerCase();
          final name = c.customerName.toLowerCase();
          final display = c.displayName.toLowerCase();
          final city = c.city.toLowerCase();
          final id = c.id.toLowerCase();
          return alias.contains(cleanQuery) ||
                 name.contains(cleanQuery) ||
                 display.contains(cleanQuery) ||
                 city.contains(cleanQuery) ||
                 id.contains(cleanQuery);
        }).toList();
      }
    });
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      try {
        _overlayEntry!.markNeedsBuild();
      } catch (_) {}
    }
  }

  void _showOverlay() {
    _hideOverlay();
    if (!mounted) return;
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
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final c = _filteredCustomers[index];
                        final isHighlighted = index == _highlightedIndex;
                        return Container(
                          color: isHighlighted ? const Color(0xFF0284C7).withOpacity(0.35) : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            title: Text(
                              c.displayName,
                              style: TextStyle(
                                color: isHighlighted ? const Color(0xFF38BDF8) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'ID: ${c.id} • ${c.city}, ${c.province}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                            trailing: isHighlighted
                                ? const Icon(Icons.arrow_right_rounded, color: Color(0xFF38BDF8), size: 24)
                                : null,
                            onTap: () => _selectCustomer(c),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );

    try {
      Overlay.of(context).insert(_overlayEntry!);
    } catch (_) {}
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      try {
        if (_overlayEntry!.mounted) {
          _overlayEntry?.remove();
        }
      } catch (_) {}
      _overlayEntry = null;
    }
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
  final FocusNode? focusNode;
  final VoidCallback? onNextFocus;
  final VoidCallback? onPrevFocus;

  const SearchableProductField({
    super.key,
    required this.selectedProduct,
    required this.products,
    required this.onSelected,
    this.focusNode,
    this.onNextFocus,
    this.onPrevFocus,
  });

  @override
  State<SearchableProductField> createState() => _SearchableProductFieldState();
}

class _SearchableProductFieldState extends State<SearchableProductField> {
  final TextEditingController _controller = TextEditingController();
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<Product> _filteredProducts = [];
  int _highlightedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  final _rupiahFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _filteredProducts = widget.products;
    if (widget.selectedProduct != null) {
      _controller.text = widget.selectedProduct!.name;
    }

    _focusNode.onKeyEvent = _onKeyEvent;

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_focusNode.hasFocus) {
            _hideOverlay();
          }
        }).catchError((_) {});
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_overlayEntry == null || !_overlayEntry!.mounted) {
        _showOverlay();
      } else if (_filteredProducts.isNotEmpty) {
        setState(() {
          _highlightedIndex = (_highlightedIndex + 1).clamp(0, _filteredProducts.length - 1);
        });
        _scrollToIndex(_highlightedIndex);
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_overlayEntry != null && _overlayEntry!.mounted && _filteredProducts.isNotEmpty) {
        setState(() {
          _highlightedIndex = (_highlightedIndex - 1).clamp(0, _filteredProducts.length - 1);
        });
        _scrollToIndex(_highlightedIndex);
        _overlayEntry?.markNeedsBuild();
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_overlayEntry != null &&
          _overlayEntry!.mounted &&
          _filteredProducts.isNotEmpty &&
          _highlightedIndex >= 0 &&
          _highlightedIndex < _filteredProducts.length) {
        final p = _filteredProducts[_highlightedIndex];
        _selectProduct(p);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.tab) {
      _hideOverlay();
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (widget.onPrevFocus != null) {
          widget.onPrevFocus!();
          return KeyEventResult.handled;
        }
      } else {
        if (widget.onNextFocus != null) {
          widget.onNextFocus!();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_overlayEntry != null && _overlayEntry!.mounted) {
        _hideOverlay();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 48.0;
    final targetOffset = index * itemHeight;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final minScroll = _scrollController.position.minScrollExtent;
    final clampedOffset = targetOffset.clamp(minScroll, maxScroll);
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _selectProduct(Product p) {
    _controller.text = p.name;
    widget.onSelected(p);
    _hideOverlay();
    if (widget.onNextFocus != null) {
      widget.onNextFocus!();
    } else {
      _focusNode.unfocus();
    }
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
    _scrollController.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _filter(String query) {
    final cleanQuery = query.trim().toLowerCase();
    setState(() {
      _highlightedIndex = 0;
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
    if (_overlayEntry != null && _overlayEntry!.mounted) {
      try {
        _overlayEntry!.markNeedsBuild();
      } catch (_) {}
    }
  }

  void _showOverlay() {
    _hideOverlay();
    if (!mounted) return;
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
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = _filteredProducts[index];
                        final isHighlighted = index == _highlightedIndex;
                        return Container(
                          color: isHighlighted ? const Color(0xFF0284C7).withOpacity(0.35) : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            title: Text(
                              p.name,
                              style: TextStyle(
                                color: isHighlighted ? const Color(0xFF38BDF8) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              'Harga: ${_rupiahFormatter.format(p.price)} • Stok: ${p.stock.toStringAsFixed(0)} pcs',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                            trailing: isHighlighted
                                ? const Icon(Icons.arrow_right_rounded, color: Color(0xFF38BDF8), size: 24)
                                : null,
                            onTap: () => _selectProduct(p),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );

    try {
      Overlay.of(context).insert(_overlayEntry!);
    } catch (_) {}
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      try {
        if (_overlayEntry!.mounted) {
          _overlayEntry?.remove();
        }
      } catch (_) {}
      _overlayEntry = null;
    }
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
