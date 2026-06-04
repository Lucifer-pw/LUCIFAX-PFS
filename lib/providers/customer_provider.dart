import 'dart:async';
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/firebase_service.dart';

class CustomerProvider extends ChangeNotifier {
  final FirebaseService _dbService = FirebaseService();
  List<Customer> _customers = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  List<Customer> get customers => _customers;
  bool get isLoading => _isLoading;

  CustomerProvider() {
    _subscription = _dbService.streamCustomers().listen((customerList) {
      _customers = customerList;
      _isLoading = false;
      notifyListeners();
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
    super.dispose();
  }
}
