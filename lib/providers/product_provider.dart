import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product.dart';
import '../services/firebase_service.dart';

class ProductProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Product> _products = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;
  StreamSubscription? _authSubscription;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;

  ProductProvider() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        _isLoading = true;
        notifyListeners();
        _subscription = _dbService.streamProducts().listen((productList) {
          final Map<String, double> kodeIndukStockMap = {};
          for (var p in productList) {
            if (p.kodeInduk.isNotEmpty) {
              final key = p.kodeInduk;
              final currentMax = kodeIndukStockMap[key] ?? 0.0;
              if (p.stock > currentMax) {
                kodeIndukStockMap[key] = p.stock;
              }
            }
          }

          final List<Product> syncedList = [];
          for (var p in productList) {
            if (p.kodeInduk.isNotEmpty && kodeIndukStockMap.containsKey(p.kodeInduk)) {
              syncedList.add(p.copyWith(stock: kodeIndukStockMap[p.kodeInduk]));
            } else {
              syncedList.add(p);
            }
          }

          _products = syncedList;
          _isLoading = false;
          notifyListeners();

          _dbService.syncAllKodeIndukStocksToFirestore(kodeIndukStockMap);
        }, onError: (error) {
          debugPrint("Product stream error: $error");
        });
      } else {
        _products = [];
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> fetchProducts() async {
    notifyListeners();
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
    _authSubscription?.cancel();
    super.dispose();
  }
}
