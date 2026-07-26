import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscureText = true;
  String? _errorMessage;

  // Focus mode state: 0 = none, 1 = username focused, 2 = password focused
  int _focusMode = 0;

  // Hero & School Fish Smooth Position & 3D Mirror Flip Physics
  double _heroCurrentX = -1.0;
  double _heroCurrentY = -1.0;
  List<Offset> _bgFishPos = [];
  List<int> _bgFishDirs = [];
  List<double> _bgFishScales = [];
  List<double> _nextTurnTimes = [];
  double _lastTimeSec = 0.0;

  // Animation Controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Ocean Ticker Controller for 60 FPS continuous rendering
  late AnimationController _oceanController;

  // Decoded Feeding Frenzy Fish Image Assets (5 species)
  List<ui.Image?> _fishImages = List.filled(5, null);
  static const List<String> _fishAssets = [
    'assets/images/fish_feeding_frenzy.png',
    'assets/images/shark_feeding_frenzy.png',
    'assets/images/baraccuda_feeding_frenzy.png',
    'assets/images/orca_feeding_frenzy.png',
    'assets/images/anglerfish_feeding_frenzy.png',
  ];

  @override
  void initState() {
    super.initState();
    _loadFishImage();

    _usernameFocusNode.addListener(_updateFocusMode);
    _passwordFocusNode.addListener(_updateFocusMode);

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

    // 3. Feeding Frenzy Ocean Render Loop (Continuous ticker)
    _oceanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _entranceController.forward();
  }

  void _updateFocusMode() {
    if (!mounted) return;
    setState(() {
      if (_usernameFocusNode.hasFocus) {
        _focusMode = 1; // Username: Approaching curiously
      } else if (_passwordFocusNode.hasFocus) {
        _focusMode = 2; // Password: Peeking from behind card
      } else {
        _focusMode = 0; // Default: Free swimming
      }
    });
  }

  Future<void> _loadFishImage() async {
    for (int i = 0; i < _fishAssets.length; i++) {
      try {
        final data = await rootBundle.load(_fishAssets[i]);
        final bytes = data.buffer.asUint8List();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _fishImages[i] = frame.image;
          });
        }
      } catch (e) {
        debugPrint("Error loading fish image ${_fishAssets[i]}: $e");
      }
    }
  }

  @override
  void dispose() {
    _usernameFocusNode.removeListener(_updateFocusMode);
    _passwordFocusNode.removeListener(_updateFocusMode);
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _pulseController.dispose();
    _entranceController.dispose();
    _oceanController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showErrorAlert(String message) {
    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    authProvider.clearError();

    // Validate empty fields
    if (username.isEmpty && password.isEmpty) {
      _showErrorAlert('Username dan Password tidak boleh kosong!');
      _formKey.currentState!.validate();
      return;
    }

    if (username.isEmpty) {
      _showErrorAlert('Username tidak boleh kosong!');
      _formKey.currentState!.validate();
      return;
    }

    if (password.isEmpty) {
      _showErrorAlert('Password tidak boleh kosong!');
      _formKey.currentState!.validate();
      return;
    }

    if (_formKey.currentState!.validate()) {
      try {
        await authProvider.signIn(username, password);

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ShellView()),
          );
        }
      } catch (e) {
        String msg = "Username atau Password yang Anda masukkan salah. Silakan periksa kembali!";
        final errStr = e.toString().toLowerCase();

        if (errStr.contains('wrong-password') || errStr.contains('invalid-credential') || errStr.contains('invalid_login_credentials')) {
          msg = "Password yang Anda masukkan salah. Silakan periksa kembali!";
        } else if (errStr.contains('user-not-found')) {
          msg = "Username / Akun tidak terdaftar di sistem!";
        } else if (errStr.contains('too-many-requests')) {
          msg = "Terlalu banyak percobaan login gagal. Silakan tunggu beberapa saat.";
        }

        if (mounted) {
          _showErrorAlert(msg);
        }
      }
    } else {
      _showErrorAlert('Silakan periksa kembali Username dan Password Anda!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF030F26), // Ocean Abyss Base
      body: Stack(
        children: [
          // 🌊 Animated Feeding Frenzy Underwater Background Canvas
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _oceanController,
              builder: (context, child) {
                final nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
                final dt = (_lastTimeSec == 0.0) ? 0.016 : (nowSec - _lastTimeSec).clamp(0.001, 0.1);
                _lastTimeSec = nowSec;

                final screenSize = MediaQuery.of(context).size;
                final width = screenSize.width;
                final height = screenSize.height;

                // Login card center coordinates
                final cardCenterX = width * 0.5;
                final cardCenterY = height * 0.52;

                double heroTargetX = 0;
                double heroTargetY = 0;

                // 1. Calculate Target Position & Smooth Movement for Hero Fish
                if (_focusMode == 1) {
                  // Username focused: approach left of login card
                  final cardLeftEdge = (cardCenterX - 215).clamp(20.0, width);
                  heroTargetX = cardLeftEdge - 45;
                  heroTargetY = height * 0.44;

                  if (_heroCurrentX < 0) {
                    _heroCurrentX = heroTargetX;
                    _heroCurrentY = heroTargetY;
                  } else {
                    final lerpFactor = 1.0 - exp(-dt * 4.2);
                    _heroCurrentX += (heroTargetX - _heroCurrentX) * lerpFactor;
                    _heroCurrentY += (heroTargetY - _heroCurrentY) * lerpFactor;
                  }
                } else if (_focusMode == 2) {
                  // Password focused: peek right of login card
                  final cardRightEdge = (cardCenterX + 215).clamp(20.0, width - 60);
                  if (_obscureText) {
                    heroTargetX = cardRightEdge + 35;
                    heroTargetY = height * 0.50;
                  } else {
                    heroTargetX = cardRightEdge + 75;
                    heroTargetY = height * 0.56;
                  }

                  if (_heroCurrentX < 0) {
                    _heroCurrentX = heroTargetX;
                    _heroCurrentY = heroTargetY;
                  } else {
                    final lerpFactor = 1.0 - exp(-dt * 4.2);
                    _heroCurrentX += (heroTargetX - _heroCurrentX) * lerpFactor;
                    _heroCurrentY += (heroTargetY - _heroCurrentY) * lerpFactor;
                  }
                } else {
                  // Unfocused ambient: swim continuously forward across screen (Zero rollback!)
                  if (_heroCurrentX < -150) {
                    _heroCurrentX = -180;
                    _heroCurrentY = height * 0.48;
                  }
                  _heroCurrentX += 60.0 * dt;
                  _heroCurrentY += ((height * 0.48) - _heroCurrentY) * (1.0 - exp(-dt * 3.0));

                  if (_heroCurrentX > width + 200) {
                    _heroCurrentX = -200; // Wrap off-screen instantly
                  }
                }

                // 2. Calculate Position & Movement for Background Fish School (Smooth 3D Mirror Flips)
                final bgCount = OceanFeedingFrenzyPainter._fishList.length;
                if (_bgFishPos.length != bgCount) {
                  _bgFishPos = List.generate(bgCount, (i) {
                    final f = OceanFeedingFrenzyPainter._fishList[i];
                    return Offset(f.initialXPercent * width, f.yPercent * height);
                  });
                  _bgFishDirs = List.generate(bgCount, (i) => OceanFeedingFrenzyPainter._fishList[i].direction);
                  _bgFishScales = List.generate(bgCount, (i) => OceanFeedingFrenzyPainter._fishList[i].direction == 1 ? -1.0 : 1.0);
                  _nextTurnTimes = List.generate(bgCount, (i) => nowSec + 5.0 + i * 2.2);
                }

                final newBgPos = <Offset>[];
                for (int i = 0; i < bgCount; i++) {
                  final f = OceanFeedingFrenzyPainter._fishList[i];
                  final currentPos = _bgFishPos[i];

                  if (_focusMode > 0) {
                    // Schooling: orbit around the login card when focused in a continuous circle
                    final angle = nowSec * (0.8 + i * 0.12) + i * (pi * 2 / bgCount);
                    final radiusX = 290.0 + (i % 3) * 35.0;
                    final radiusY = 190.0 + (i % 2) * 30.0;
                    final bgTargetX = cardCenterX + cos(angle) * radiusX;
                    final bgTargetY = cardCenterY + sin(angle) * radiusY;

                    final lerpSpeed = 2.2 + (i % 3) * 0.4;
                    final lerpF = 1.0 - exp(-dt * lerpSpeed);
                    final nextX = currentPos.dx + (bgTargetX - currentPos.dx) * lerpF;
                    final nextY = currentPos.dy + (bgTargetY - currentPos.dy) * lerpF;

                    final deltaX = nextX - currentPos.dx;
                    if (deltaX > 0.15) {
                      _bgFishDirs[i] = 1;
                    } else if (deltaX < -0.15) {
                      _bgFishDirs[i] = -1;
                    }

                    // Lerp scaleX for smooth 3D mirror flip
                    final targetScaleX = (_bgFishDirs[i] == 1) ? -1.0 : 1.0;
                    _bgFishScales[i] += (targetScaleX - _bgFishScales[i]) * (1.0 - exp(-dt * 8.0));

                    newBgPos.add(Offset(nextX, nextY));
                  } else {
                    // Organic Ambient Swimming with Smooth 3D Mirror Flips (No upside-down fish!)
                    final isNearRightEdge = currentPos.dx > width * 0.86 && _bgFishDirs[i] == 1;
                    final isNearLeftEdge = currentPos.dx < width * 0.14 && _bgFishDirs[i] == -1;
                    final isTimerDue = nowSec > _nextTurnTimes[i];

                    if (isNearRightEdge || isNearLeftEdge || isTimerDue) {
                      _bgFishDirs[i] = (_bgFishDirs[i] == 1) ? -1 : 1;
                      _nextTurnTimes[i] = nowSec + 7.0 + ((i * 3.1) % 9.0);
                    }

                    // Lerp scaleX for smooth 3D mirror flip
                    final targetScaleX = (_bgFishDirs[i] == 1) ? -1.0 : 1.0;
                    _bgFishScales[i] += (targetScaleX - _bgFishScales[i]) * (1.0 - exp(-dt * 6.0));

                    // Move along linear direction
                    final moveSpeed = f.speed * 1.15;
                    final vx = _bgFishDirs[i] * moveSpeed;
                    final vy = sin(nowSec * 2.2 + i * 1.5) * 5.0;

                    double nextX = currentPos.dx + vx * dt;
                    double nextY = currentPos.dy + vy * dt;

                    // Keep Y inside vertical screen bounds
                    final minY = height * 0.12;
                    final maxY = height * 0.88;
                    if (nextY < minY) nextY = minY;
                    if (nextY > maxY) nextY = maxY;

                    final margin = f.size * 3.5;
                    if (nextX > width + margin) {
                      nextX = -margin;
                      _bgFishDirs[i] = 1;
                      _bgFishScales[i] = -1.0;
                    } else if (nextX < -margin) {
                      nextX = width + margin;
                      _bgFishDirs[i] = -1;
                      _bgFishScales[i] = 1.0;
                    }

                    newBgPos.add(Offset(nextX, nextY));
                  }
                }
                _bgFishPos = newBgPos;

                return CustomPaint(
                  painter: OceanFeedingFrenzyPainter(
                    timeSec: nowSec,
                    fishImages: _fishImages,
                    focusMode: _focusMode,
                    isObscured: _obscureText,
                    heroX: _heroCurrentX,
                    heroY: _heroCurrentY,
                    bgFishPos: _bgFishPos,
                    bgFishScales: _bgFishScales,
                  ),
                );
              },
            ),
          ),

          // Main Login Interface Content Layer
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
                              width: 115,
                              height: 115,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A).withOpacity(0.9),
                                borderRadius: BorderRadius.circular(30.0),
                                border: Border.all(
                                  color: const Color(0xFF38BDF8).withOpacity(0.8),
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0284C7).withOpacity(0.55),
                                    blurRadius: _glowAnimation.value,
                                    spreadRadius: 4.0,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
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
                          fontSize: 30.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          shadows: [
                            Shadow(color: Color(0xFF0284C7), blurRadius: 16),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
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
                          color: const Color(0xFF0F172A).withOpacity(0.88), // Slate Ocean Glass
                          borderRadius: BorderRadius.circular(24.0),
                          border: Border.all(
                            color: const Color(0xFF38BDF8).withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0284C7).withOpacity(0.2),
                              blurRadius: 30.0,
                              spreadRadius: 2.0,
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20.0,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.waves_rounded, color: Color(0xFF38BDF8), size: 20),
                                  SizedBox(width: 8),
                                  Text(
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
                              Builder(
                                builder: (context) {
                                  final displayError = _errorMessage ?? authProvider.errorMessage;
                                  if (displayError == null || displayError.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.redAccent, width: 1.2),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              displayError,
                                              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              // Username Input Field
                              TextFormField(
                                controller: _usernameController,
                                focusNode: _usernameFocusNode,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                onChanged: (_) {
                                  if (_errorMessage != null || authProvider.errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                    authProvider.clearError();
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'Username',
                                  hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                  prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                                  filled: true,
                                  fillColor: const Color(0xFF030F26),
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
                                focusNode: _passwordFocusNode,
                                obscureText: _obscureText,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                onChanged: (_) {
                                  if (_errorMessage != null || authProvider.errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                    authProvider.clearError();
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
                                  fillColor: const Color(0xFF030F26),
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

/// 🎨 CustomPainter for high-performance Seamless Feeding Frenzy Animated Ocean
class OceanFeedingFrenzyPainter extends CustomPainter {
  final double timeSec; // Continuous epoch time in seconds
  final List<ui.Image?> fishImages; // 5 Decoded species PNGs
  final int focusMode; // 0 = none, 1 = username focused, 2 = password focused
  final bool isObscured; // true = password hidden, false = password shown
  final double heroX; // Smooth lerped X position
  final double heroY; // Smooth lerped Y position
  final List<Offset> bgFishPos; // Smooth lerped school fish positions
  final List<double> bgFishScales; // Smooth lerped scaleX (-1.0 for right, 1.0 for left)

  OceanFeedingFrenzyPainter({
    required this.timeSec,
    this.fishImages = const [],
    this.focusMode = 0,
    this.isObscured = true,
    this.heroX = 0.0,
    this.heroY = 0.0,
    this.bgFishPos = const [],
    this.bgFishScales = const [],
  });

  // Procedural background fish data with realistic sizes, speeds, and species
  // imageIndex: 0=fish, 1=shark, 2=baraccuda, 3=orca, 4=anglerfish
  static final List<_FishData> _fishList = [
    _FishData(yPercent: 0.14, speed: 45.0, size: 38, direction: 1, color: const Color(0xFF38BDF8), initialXPercent: 0.05, imageIndex: 0),
    _FishData(yPercent: 0.26, speed: 65.0, size: 95, direction: -1, color: const Color(0xFF64748B), initialXPercent: 0.85, imageIndex: 1), // Shark (LARGE!)
    _FishData(yPercent: 0.38, speed: 35.0, size: 62, direction: 1, color: const Color(0xFF10B981), initialXPercent: 0.35, imageIndex: 2), // Barracuda
    _FishData(yPercent: 0.72, speed: 75.0, size: 115, direction: -1, color: const Color(0xFF1E293B), initialXPercent: 0.70, imageIndex: 3), // Orca (HUGE!)
    _FishData(yPercent: 0.80, speed: 50.0, size: 48, direction: 1, color: const Color(0xFFA855F7), initialXPercent: 0.15, imageIndex: 4), // Anglerfish
    _FishData(yPercent: 0.86, speed: 60.0, size: 40, direction: -1, color: const Color(0xFF06B6D4), initialXPercent: 0.50, imageIndex: 0),
    _FishData(yPercent: 0.18, speed: 85.0, size: 60, direction: 1, color: const Color(0xFFF43F5E), initialXPercent: 0.60, imageIndex: 2), // Barracuda
  ];

  // Procedural bubbles
  static final List<_BubbleData> _bubbles = List.generate(40, (index) {
    final random = Random(index * 7);
    return _BubbleData(
      xPercent: random.nextDouble(),
      yOffsetPercent: random.nextDouble(),
      speed: 30.0 + random.nextDouble() * 50.0,
      radius: 2.0 + random.nextDouble() * 5.5,
      phaseShift: random.nextDouble() * pi * 2,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 1. Deep Ocean Background Gradient
    final bgGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFF041C44), // Top sunny water blue
        Color(0xFF03102C), // Mid deep ocean
        Color(0xFF010614), // Seabed abyss
      ],
    );
    final bgPaint = Paint()..shader = bgGradient.createShader(Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // 2. Underwater Sun Rays / Caustics
    final rayPaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.04)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final rayPath = Path();
      final rayX = (width * 0.15 * i) + sin(timeSec * 0.8 + i) * 25;
      rayPath.moveTo(rayX, 0);
      rayPath.lineTo(rayX + 80, 0);
      rayPath.lineTo(rayX + 180, height);
      rayPath.lineTo(rayX + 40, height);
      rayPath.close();
      canvas.drawPath(rayPath, rayPaint);
    }

    // 3. Swaying Seaweed at Seabed Bottom
    _drawSeaweed(canvas, size);

    // 4. Floating Animated Bubbles
    final bubblePaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final bubbleFill = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.09)
      ..style = PaintingStyle.fill;

    final totalBubbleTravel = height + 60.0;
    for (var b in _bubbles) {
      final rawY = (b.yOffsetPercent * height + timeSec * b.speed) % totalBubbleTravel;
      final floatY = height + 30.0 - rawY;
      final wobbleX = (b.xPercent * width) + sin(timeSec * 2.0 + b.phaseShift) * 14;

      canvas.drawCircle(Offset(wobbleX, floatY), b.radius, bubbleFill);
      canvas.drawCircle(Offset(wobbleX, floatY), b.radius, bubblePaint);
    }

    // 5. Swimming Background Fish School (Smooth 3D Mirror Flips)
    if (bgFishPos.isNotEmpty) {
      for (int i = 0; i < _fishList.length && i < bgFishPos.length; i++) {
        final f = _fishList[i];
        final pos = bgFishPos[i];
        final scaleX = (i < bgFishScales.length) ? bgFishScales[i] : (f.direction == 1 ? -1.0 : 1.0);
        final verticalBob = sin(timeSec * 2.5 + i * 2.0) * 4.0;
        final rot = focusMode > 0 ? sin(timeSec * 3.0 + i) * 0.06 : sin(timeSec * 2.0 + i) * 0.03;
        final img = (f.imageIndex < fishImages.length) ? fishImages[f.imageIndex] : null;
        _drawFish(canvas, pos, f.size, scaleX, f.color, verticalBob, rot, img, timeWagPhase: i * 1.5);
      }
    }

    // 6. 🌟 INTERACTIVE HERO FISH (Responds to Focus Events)
    _drawInteractiveHeroFish(canvas, size);
  }

  void _drawInteractiveHeroFish(Canvas canvas, Size size) {
    final heroSize = 60.0;
    final heroColor = const Color(0xFF38BDF8);

    // Use smoothly lerped base coordinates (no instant blinking!)
    final posX = heroX + sin(timeSec * 2.5) * 8;
    final posY = heroY;

    double scaleX = -1.0;
    double rotation = 0.0;
    double verticalBob = sin(timeSec * 3.5) * 5.0;

    if (focusMode == 1) {
      // Username focused: Approaching curiously from left facing right
      scaleX = -1.0;
      rotation = sin(timeSec * 4.0) * 0.12;

      // Curious bubbles near fish head
      final bubblePaint = Paint()
        ..color = const Color(0xFF38BDF8).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (int i = 0; i < 3; i++) {
        final bY = posY - 25 - (i * 14) - sin(timeSec * 4.0 + i) * 6;
        final bX = posX + 25 + sin(timeSec * 3.0 + i) * 8;
        canvas.drawCircle(Offset(bX, bY), 3.0 + i, bubblePaint);
      }
    } else if (focusMode == 2) {
      // Password focused: Peeking right of Login Card facing left
      scaleX = 1.0;
      if (isObscured) {
        rotation = -0.18 + sin(timeSec * 3.0) * 0.08;
      } else {
        rotation = 0.45 + sin(timeSec * 8.0) * 0.15;

        // Burst of surprised bubbles
        final bubblePaint = Paint()
          ..color = Colors.amberAccent.withOpacity(0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        for (int i = 0; i < 5; i++) {
          final bY = posY - 30 - (i * 12) - sin(timeSec * 8.0 + i) * 8;
          final bX = posX - 15 + sin(timeSec * 7.0 + i) * 12;
          canvas.drawCircle(Offset(bX, bY), 2.5 + i * 1.2, bubblePaint);
        }
      }
    } else {
      // Unfocused ambient
      scaleX = -1.0;
      rotation = 0.0;
    }

    final heroImg = fishImages.isNotEmpty ? fishImages[0] : null;
    _drawFish(canvas, Offset(posX, posY), heroSize, scaleX, heroColor, verticalBob, rotation, heroImg, timeWagPhase: 0.0);
  }

  void _drawSeaweed(Canvas canvas, Size size) {
    final seaweedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final colors = [
      const Color(0xFF10B981).withOpacity(0.35),
      const Color(0xFF059669).withOpacity(0.25),
      const Color(0xFF047857).withOpacity(0.4),
    ];

    for (int i = 0; i < 8; i++) {
      final baseX = size.width * (0.05 + i * 0.13);
      final height = 120.0 + sin(i * 1.5) * 40.0;

      seaweedPaint.color = colors[i % colors.length];
      seaweedPaint.strokeWidth = 6.0 + (i % 3);

      final path = Path();
      path.moveTo(baseX, size.height);

      final sway = sin(timeSec * 1.2 + i) * 20.0;
      path.cubicTo(
        baseX + sway * 0.5,
        size.height - height * 0.33,
        baseX - sway,
        size.height - height * 0.66,
        baseX + sway * 1.2,
        size.height - height,
      );

      canvas.drawPath(path, seaweedPaint);
    }
  }

  void _drawFish(Canvas canvas, Offset center, double size, double scaleX, Color color, double verticalBob, double rotation, ui.Image? img, {double timeWagPhase = 0.0}) {
    canvas.save();
    canvas.translate(center.dx, center.dy + verticalBob);

    if (rotation != 0.0) {
      canvas.rotate(rotation);
    }

    // 🪞 Smooth Horizontal 3D Mirror Flip (-1.0 = facing right, 1.0 = facing left)
    // Fish ALWAYS stays upright (dorsal fin UP, belly DOWN)!
    canvas.scale(scaleX, 1.0);

    // 🐟 Realist Tail Wagging Oscillation (Dynamic Skew & Pitch transform)
    final tailWag = sin(timeSec * 8.0 + timeWagPhase) * 0.08;
    canvas.skew(0.0, tailWag);

    if (img != null) {
      final rect = Rect.fromCenter(center: Offset.zero, width: size * 2.8, height: size * 2.2);

      // Ambient glow behind fish
      final shadowPaint = Paint()
        ..color = color.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawOval(rect.deflate(size * 0.3), shadowPaint);

      paintImage(
        canvas: canvas,
        rect: rect,
        image: img,
        fit: BoxFit.contain,
      );
    } else {
      // Fallback vector fish if image is still loading
      final fishPaint = Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.fill;

      final bodyPath = Path();
      bodyPath.moveTo(-size * 1.2, 0);
      bodyPath.cubicTo(-size * 0.5, -size * 0.65, size * 0.4, -size * 0.5, size * 0.8, 0);
      bodyPath.cubicTo(size * 0.4, size * 0.5, -size * 0.5, size * 0.65, -size * 1.2, 0);
      bodyPath.close();

      canvas.drawPath(bodyPath, fishPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant OceanFeedingFrenzyPainter oldDelegate) {
    return oldDelegate.timeSec != timeSec ||
        oldDelegate.fishImages != fishImages ||
        oldDelegate.focusMode != focusMode ||
        oldDelegate.isObscured != isObscured;
  }
}

class _FishData {
  final double yPercent;
  final double speed;
  final double size;
  final int direction; // 1 for right, -1 for left
  final Color color;
  final double initialXPercent;
  final int imageIndex; // 0=fish, 1=shark, 2=barracuda, 3=orca, 4=anglerfish

  _FishData({
    required this.yPercent,
    required this.speed,
    required this.size,
    required this.direction,
    required this.color,
    required this.initialXPercent,
    this.imageIndex = 0,
  });
}

class _BubbleData {
  final double xPercent;
  final double yOffsetPercent;
  final double speed;
  final double radius;
  final double phaseShift;

  _BubbleData({
    required this.xPercent,
    required this.yOffsetPercent,
    required this.speed,
    required this.radius,
    required this.phaseShift,
  });
}
