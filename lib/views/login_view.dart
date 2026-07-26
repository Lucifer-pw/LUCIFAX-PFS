import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../providers/auth_provider.dart';
import 'shell_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  String? _errorMessage;

  // Animation Controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  late AnimationController _orbController;
  late Animation<double> _orbAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Logo FIVA Breathing/Pulsating Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 14.0, end: 32.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 2. Entrance Slide & Fade-In Animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );

    // 3. Background Ambient Orbs Motion Animation
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    _orbAnimation = Tween<double>(begin: -15.0, end: 15.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOut),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    _orbController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _errorMessage = null;
    });

    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      try {
        await authProvider.signIn(
          _usernameController.text,
          _passwordController.text,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ShellView()),
          );
        }
      } on FirebaseAuthException catch (e) {
        String msg = "Username atau Password yang Anda masukkan salah.";
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          msg = "Password yang Anda masukkan salah. Silakan periksa kembali!";
        } else if (e.code == 'user-not-found') {
          msg = "Username / Akun tidak terdaftar di sistem!";
        } else if (e.code == 'too-many-requests') {
          msg = "Terlalu banyak percobaan login gagal. Silakan tunggu beberapa saat.";
        }

        if (mounted) {
          setState(() {
            _errorMessage = msg;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = authProvider.errorMessage ?? "Password atau Username salah. Silakan coba lagi!";
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0B132B), // Deep Cosmic Dark Slate
      body: Stack(
        children: [
          // Ambient Animated Glowing Orbs in Background
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return Stack(
                children: [
                  // Top Cyan Glowing Orb
                  Positioned(
                    top: -80 + _orbAnimation.value,
                    left: size.width * 0.2 + (_orbAnimation.value * 0.5),
                    child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00F2FE).withOpacity(0.12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withOpacity(0.18),
                            blurRadius: 100,
                            spreadRadius: 40,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Blue Glowing Orb
                  Positioned(
                    bottom: -100 - _orbAnimation.value,
                    right: size.width * 0.15 - (_orbAnimation.value * 0.5),
                    child: Container(
                      width: 380,
                      height: 380,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4FACFE).withOpacity(0.12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4FACFE).withOpacity(0.18),
                            blurRadius: 120,
                            spreadRadius: 50,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Main Login Interface Content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated FIVA Logo Container with Pulsating Glow
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 110,
                              height: 110,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(28.0),
                                border: Border.all(
                                  color: const Color(0xFF38BDF8).withOpacity(0.6),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0284C7).withOpacity(0.45),
                                    blurRadius: _glowAnimation.value,
                                    spreadRadius: 4.0,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.asset(
                                  'assets/images/logo_fiva.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      'icons/Icon-512.png',
                                      fit: BoxFit.contain,
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 18.0),

                      // Title Header
                      const Text(
                        'LUCIFAX PFS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'PT. Putra Fiva Sejahtera • Jawa Tengah',
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32.0),

                      // Login Card with Glassmorphic Styling
                      Container(
                        width: 430.0,
                        padding: const EdgeInsets.all(32.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.95), // Slate Grey Glass
                          borderRadius: BorderRadius.circular(22.0),
                          border: Border.all(
                            color: const Color(0xFF38BDF8).withOpacity(0.2),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 24.0,
                              offset: const Offset(0, 12),
                            )
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.lock_person_rounded, color: Color(0xFF38BDF8), size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'MASUK AKUN',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17.0,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24.0),

                              // Error Message Banner
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16.0),
                              ],

                              // Username Input Field
                              TextFormField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Username',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                  prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Username tidak boleh kosong';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16.0),

                              // Password Input Field
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscureText,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                  prefixIcon: const Icon(Icons.lock_outlined, color: Color(0xFF38BDF8), size: 20),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      color: const Color(0xFF64748B),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureText = !_obscureText;
                                      });
                                    },
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                    borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Password tidak boleh kosong';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 28.0),

                              // Animated Submit Button
                              ElevatedButton(
                                onPressed: authProvider.isLoading ? null : _handleSubmit,
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  elevation: 4,
                                ),
                                child: Ink(
                                  decoration: BoxDecoration(
                                    gradient: authProvider.isLoading
                                        ? null
                                        : const LinearGradient(
                                            colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                    color: authProvider.isLoading ? const Color(0xFF334155) : null,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Container(
                                    height: 48,
                                    alignment: Alignment.center,
                                    child: authProvider.isLoading
                                        ? const SizedBox(
                                            width: 24.0,
                                            height: 24.0,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'MASUK',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15.0,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
