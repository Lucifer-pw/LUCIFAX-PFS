import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/transaction.dart' as model_tr;
import '../services/firebase_service.dart';

class TransactionProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  List<model_tr.Transaction> _transactions = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  // Active cashier cart state
  final List<model_tr.TransactionItem> _cartItems = [];
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedAliasName;
  String? _selectedCity;
  String? _selectedProvince;
  String? _selectedCountry;
  String _note = "";
  DateTime _deliveryDate = DateTime.now();

  List<model_tr.Transaction> get transactions => _transactions;
  bool get isLoading => _isLoading;

  List<model_tr.TransactionItem> get cartItems => _cartItems;
  String? get selectedCustomerId => _selectedCustomerId;
  String? get selectedCustomerName => _selectedCustomerName;
  String? get selectedAliasName => _selectedAliasName;
  String? get selectedCity => _selectedCity;
  String? get selectedProvince => _selectedProvince;
  String? get selectedCountry => _selectedCountry;
  String get note => _note;
  DateTime get deliveryDate => _deliveryDate;

  double get grandTotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  TransactionProvider() {
    _subscription = _dbService.streamTransactions().listen((trList) {
      _transactions = trList;
      _isLoading = false;
      notifyListeners();
    });
  }

  // Set selected customer details for current cart
  void setCustomer(
    String id,
    String name,
    String alias,
    String city,
    String province,
    String country,
  ) {
    _selectedCustomerId = id;
    _selectedCustomerName = name;
    _selectedAliasName = alias;
    _selectedCity = city;
    _selectedProvince = province;
    _selectedCountry = country;
    notifyListeners();
  }

  void setDeliveryDate(DateTime date) {
    _deliveryDate = date;
    notifyListeners();
  }

  void setNote(String noteText) {
    _note = noteText;
  }

  // Active Cart Methods with 10-Item Constraint!
  void addToCart(Product product, double qty, double discountPercent) {
    // Check if product already exists in cart to update qty
    final existingIndex = _cartItems.indexWhere((item) => item.productId == product.id);

    if (existingIndex != -1) {
      // Update existing item
      final currentQty = _cartItems[existingIndex].qty;
      final newQty = currentQty + qty;
      final subtotal = newQty * product.price * (1 - discountPercent / 100);

      _cartItems[existingIndex] = model_tr.TransactionItem(
        productId: product.id,
        productName: product.name,
        price: product.price,
        qty: newQty,
        discountPercent: discountPercent,
        subtotal: subtotal,
        sizeGrams: product.sizeGrams,
      );
    } else {
      // Enforce the 10-item limit constraint
      if (_cartItems.length >= 10) {
        throw Exception("Batas Maksimal 10 item produk berbeda per lembar invoice ( Continuous Form ) tercapai!");
      }

      final subtotal = qty * product.price * (1 - discountPercent / 100);
      _cartItems.add(
        model_tr.TransactionItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          qty: qty,
          discountPercent: discountPercent,
          subtotal: subtotal,
          sizeGrams: product.sizeGrams,
        ),
      );
    }
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _cartItems.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    _selectedCustomerId = null;
    _selectedCustomerName = null;
    _selectedAliasName = null;
    _selectedCity = null;
    _selectedProvince = null;
    _selectedCountry = null;
    _note = "";
    _deliveryDate = DateTime.now();
    notifyListeners();
  }

  // Save current cart transaction
  Future<int> submitTransaction(String createdBy) async {
    if (_selectedCustomerId == null) {
      throw Exception("Silakan pilih Nama Pelanggan terlebih dahulu!");
    }
    if (_cartItems.isEmpty) {
      throw Exception("Tabel transaksi masih kosong!");
    }

    final invoiceNo = await _dbService.createTransaction(
      customerId: _selectedCustomerId!,
      customerName: _selectedCustomerName!,
      aliasName: _selectedAliasName!,
      deliveryDate: _deliveryDate,
      city: _selectedCity!,
      province: _selectedProvince!,
      country: _selectedCountry!,
      items: _cartItems,
      grandTotal: grandTotal,
      note: _note,
      createdBy: createdBy,
    );

    clearCart();
    return invoiceNo;
  }

  Future<void> updatePaymentStatus(int invoiceNo, String status, DateTime? transferDate) async {
    await _dbService.updateTransactionTransferStatus(invoiceNo, status, transferDate);
  }

  // Fetch ERP Summaries for reports
  Future<List<Map<String, dynamic>>> getMonthlyErpSummary(String monthYear) async {
    return await _dbService.getErpSummaries(monthYear);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
