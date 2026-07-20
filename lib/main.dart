import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/update_provider.dart';
import 'providers/receivable_provider.dart';
import 'providers/stock_provider.dart';
import 'providers/attendance_provider.dart';
import 'views/login_view.dart';
import 'views/shell_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase with generated platform options
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint("Firebase initialization warning: $e");
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => CustomerProvider()),
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
          ChangeNotifierProvider(create: (_) => ReceivableProvider()),
          ChangeNotifierProvider(create: (_) => StockProvider()),
          ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ],
        child: const CashierApp(),
      ),
    );
  }

  class CashierApp extends StatelessWidget {
    const CashierApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'FIVA SOLO Cashier',
        debugShowCheckedModeBanner: false,
        
        // Premium Slate-Dark Design System Theme
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF0284C7),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF38BDF8),
            onPrimary: Colors.white,
            secondary: Color(0xFF0284C7),
            surface: Color(0xFF1E293B),
            background: Color(0xFF0F172A),
          ),
        
        // Premium Typography and component styles
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      
      // Root Session Resolver
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              ),
            );
          }
          if (auth.isAuthenticated) {
            return const ShellView();
          }
          return const LoginView();
        },
      ),
    );
  }
}
