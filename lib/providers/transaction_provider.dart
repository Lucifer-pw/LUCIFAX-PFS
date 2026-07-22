import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';
import '../models/transaction.dart' as model_tr;
import '../services/firebase_service.dart';

class TransactionProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<model_tr.Transaction> _transactions = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;
  StreamSubscription? _authSubscription;

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
  String _invoiceType = 'PO'; // 'PO' or 'SA'
  String _customSaNo = '';

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
  String get invoiceType => _invoiceType;
  String get customSaNo => _customSaNo;

  void setInvoiceType(String type, {String? customSaNo}) {
    _invoiceType = type;
    if (customSaNo != null) _customSaNo = customSaNo;
    notifyListeners();
  }

  Future<String> peekNextInvoiceNo() async {
    return await _dbService.peekNextInvoiceNo(type: _invoiceType);
  }

  double get grandTotal {
    return _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  TransactionProvider() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        _isLoading = true;
        notifyListeners();
        _subscription = _dbService.streamTransactions().listen((trList) {
          _transactions = trList;
          _isLoading = false;
          notifyListeners();
        }, onError: (error) {
          debugPrint("Transaction stream error: $error");
        });
      } else {
        _transactions = [];
        _isLoading = false;
        notifyListeners();
      }
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

  // Active Cart Methods with 14-Item Constraint!
  void addToCart(Product product, double qty, double discountPercent, {double? customPrice, bool isBonus = false}) {
    if (isBonus) {
      // Bonus items always add as a new separate line with price = 0
      if (_cartItems.length >= 14) {
        throw Exception("Batas Maksimal 14 item produk berbeda per lembar invoice ( Continuous Form ) tercapai!");
      }
      _cartItems.add(
        model_tr.TransactionItem(
          productId: product.id,
          productName: product.name,
          price: 0,
          qty: qty,
          discountPercent: 0,
          subtotal: 0,
          sizeGrams: product.sizeGrams,
          isBonus: true,
        ),
      );
    } else {
      // Check if product already exists in cart (non-bonus) to update qty
      final existingIndex = _cartItems.indexWhere((item) => item.productId == product.id && !item.isBonus);
      final finalPrice = customPrice ?? product.price;

      if (existingIndex != -1) {
        // Update existing item
        final currentQty = _cartItems[existingIndex].qty;
        final newQty = currentQty + qty;
        final subtotal = newQty * finalPrice * (1 - discountPercent / 100);

        _cartItems[existingIndex] = model_tr.TransactionItem(
          productId: product.id,
          productName: product.name,
          price: finalPrice,
          qty: newQty,
          discountPercent: discountPercent,
          subtotal: subtotal,
          sizeGrams: product.sizeGrams,
        );
      } else {
        // Enforce the 14-item limit constraint
        if (_cartItems.length >= 14) {
          throw Exception("Batas Maksimal 14 item produk berbeda per lembar invoice ( Continuous Form ) tercapai!");
        }

        final subtotal = qty * finalPrice * (1 - discountPercent / 100);
        _cartItems.add(
          model_tr.TransactionItem(
            productId: product.id,
            productName: product.name,
            price: finalPrice,
            qty: qty,
            discountPercent: discountPercent,
            subtotal: subtotal,
            sizeGrams: product.sizeGrams,
          ),
        );
      }
    }
    notifyListeners();
  }

  void removeFromCart(String productId, {int? index}) {
    if (index != null && index >= 0 && index < _cartItems.length) {
      _cartItems.removeAt(index);
    } else {
      _cartItems.removeWhere((item) => item.productId == productId);
    }
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

  // Save current cart transaction and return the Transaction object
  Future<model_tr.Transaction> submitTransaction(String createdBy) async {
    if (_selectedCustomerId == null) {
      throw Exception("Silakan pilih Nama Pelanggan terlebih dahulu!");
    }
    if (_cartItems.isEmpty) {
      throw Exception("Tabel transaksi masih kosong!");
    }

    final savedTr = await _dbService.createTransaction(
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
      invoiceType: _invoiceType,
      customSaNo: _customSaNo,
    );

    clearCart();
    return savedTr;
  }

  Future<void> updatePaymentStatus(dynamic invoiceNo, String status, DateTime? transferDate) async {
    await _dbService.updateTransactionTransferStatus(invoiceNo, status, transferDate);
  }

  Future<void> updateDeliveryStatus(dynamic invoiceNo, String status, DateTime? deliveryDate) async {
    await _dbService.updateTransactionDeliveryStatus(invoiceNo, status, deliveryDate);
    notifyListeners();
  }

  Future<void> updateDeliveryDate(dynamic invoiceNo, DateTime deliveryDate) async {
    await _dbService.updateTransactionDeliveryDate(invoiceNo, deliveryDate);
  }

  Future<void> updateErpStatus(dynamic invoiceNo, DateTime? erpSyncDate) async {
    await _dbService.updateTransactionErpStatus(invoiceNo, erpSyncDate);
    notifyListeners();
  }

  Future<void> updateTransaction(model_tr.Transaction updatedTr) async {
    await _dbService.updateTransaction(updatedTr);
    notifyListeners();
  }

  Future<void> deleteTransaction(dynamic invoiceNo) async {
    await _dbService.deleteTransaction(invoiceNo);
    notifyListeners();
  }

  // Fetch ERP Summaries for reports
  Future<List<Map<String, dynamic>>> getMonthlyErpSummary(String monthYear) async {
    return await _dbService.getErpSummaries(monthYear);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
