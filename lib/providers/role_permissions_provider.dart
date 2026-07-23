import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RolePermissionsProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _subscription;

  // Default permissions map for KACAB
  Map<String, bool> _kacabPermissions = {
    'transaction_entry': false,
    'transaction_history': true, // Default ON for Kacab
    'master_product': false,
    'master_customer': false,
    'stock_input': false,
    'erp_matrix': false,
    'receivable_list': false,
    'ranking_kacab': false,
    'attendance': false,
    'dashboard': false,
  };

  bool _isLoading = true;

  Map<String, bool> get kacabPermissions => _kacabPermissions;
  bool get isLoading => _isLoading;

  RolePermissionsProvider() {
    _initStream();
  }

  void _initStream() {
    _subscription = _db
        .collection('settings')
        .doc('role_permissions')
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final Map<String, dynamic>? kacabMap = data['kacab'] as Map<String, dynamic>?;
        if (kacabMap != null) {
          final Map<String, bool> updated = Map.from(_kacabPermissions);
          kacabMap.forEach((key, val) {
            if (val is bool) {
              updated[key] = val;
            }
          });
          _kacabPermissions = updated;
        }
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint("Error listening to role permissions: $e");
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> updateKacabPermission(String featureKey, bool isEnabled) async {
    _kacabPermissions[featureKey] = isEnabled;
    notifyListeners();

    try {
      await _db.collection('settings').doc('role_permissions').set({
        'kacab': {
          featureKey: isEnabled,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving role permission: $e");
    }
  }

  Future<void> setAllKacabPermissions(bool isEnabled) async {
    final Map<String, bool> updated = {};
    for (var key in _kacabPermissions.keys) {
      updated[key] = isEnabled;
    }
    _kacabPermissions = updated;
    notifyListeners();

    try {
      await _db.collection('settings').doc('role_permissions').set({
        'kacab': updated,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error setting all role permissions: $e");
    }
  }

  Future<void> resetKacabToDefault() async {
    final Map<String, bool> defaultMap = {
      'transaction_entry': false,
      'transaction_history': true,
      'master_product': false,
      'master_customer': false,
      'stock_input': false,
      'erp_matrix': false,
      'receivable_list': false,
      'ranking_kacab': false,
      'attendance': false,
      'dashboard': false,
    };
    _kacabPermissions = defaultMap;
    notifyListeners();

    try {
      await _db.collection('settings').doc('role_permissions').set({
        'kacab': defaultMap,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error resetting role permissions: $e");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
