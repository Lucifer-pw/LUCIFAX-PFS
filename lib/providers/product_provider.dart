import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/firebase_service.dart';

class ProductProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  List<Product> _products = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;

  ProductProvider() {
    _subscription = _dbService.streamProducts().listen((productList) {
      _products = productList;
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> saveProduct(Product product) async {
    await _dbService.saveProduct(product);
  }

  Future<void> deleteProduct(String id) async {
    await _dbService.deleteProduct(id);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
