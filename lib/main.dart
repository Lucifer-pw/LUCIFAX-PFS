import 'dart:ui';
import 'package:flutter/foundation.dart';
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
import 'providers/role_permissions_provider.dart';
import 'views/login_view.dart';
import 'views/shell_view.dart';

final globalErrorNotifier = ValueNotifier<String?>(null);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress unhandled Web async Future exceptions and capture error details
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("Caught unhandled async error: $error\n$stack");
    globalErrorNotifier.value = "Async Exception: $error\n\nStack:\n$stack";
    return true;
  };

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    globalErrorNotifier.value = "Framework Exception: ${details.exception}\n\nStack:\n${details.stack}";
  };
  
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
        ChangeNotifierProvider(create: (_) => RolePermissionsProvider()),
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
      title: 'Lucifax - PFS Jateng',
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
      
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<String?>(
              valueListenable: globalErrorNotifier,
              builder: (context, errorMsg, _) {
                if (errorMsg == null) return const SizedBox.shrink();
                return Material(
                  color: Colors.black.withOpacity(0.85),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent, width: 2),
                      ),
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
                              const SizedBox(width: 12),
                              const Text(
                                'DIAGNOSIS ERROR SISTEM',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                                onPressed: () => globalErrorNotifier.value = null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Salin detail di bawah ini untuk dilaporkan:',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(maxHeight: 300),
                            width: double.infinity,
                            child: SingleChildScrollView(
                              child: SelectableText(
                                errorMsg,
                                style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                                onPressed: () => globalErrorNotifier.value = null,
                                child: const Text('Tutup', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      
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
