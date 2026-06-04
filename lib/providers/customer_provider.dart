import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/customer.dart';
import '../services/firebase_service.dart';

class CustomerProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Customer> _customers = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;
  StreamSubscription? _authSubscription;

  List<Customer> get customers => _customers;
  bool get isLoading => _isLoading;

  CustomerProvider() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      _subscription?.cancel();
      if (user != null) {
        _isLoading = true;
        notifyListeners();
        _subscription = _dbService.streamCustomers().listen((customerList) {
          _customers = customerList;
          _isLoading = false;
          notifyListeners();
        }, onError: (error) {
          debugPrint("Customer stream error: $error");
        });
      } else {
        _customers = [];
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> saveCustomer(Customer customer) async {
    await _dbService.saveCustomer(customer);
  }

  Future<void> deleteCustomer(String id) async {
    await _dbService.deleteCustomer(id);
  }

  Future<String> getNextCustomerID(String city) async {
    return await _dbService.generateCustomerID(city);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
