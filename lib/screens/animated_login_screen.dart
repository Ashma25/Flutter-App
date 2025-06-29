import 'dart:math';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dashboard_page.dart';
import 'forgot_password_screen.dart';

class AnimatedLoginScreen extends StatefulWidget {
  const AnimatedLoginScreen({super.key});

  @override
  State<AnimatedLoginScreen> createState() => _AnimatedLoginScreenState();
}

class _AnimatedLoginScreenState extends State<AnimatedLoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String errorMessage = '';
  bool isLoading = false;
  bool _obscurePassword = true;

  // Password validation rules
  bool hasMinLength = false;
  bool hasUpperCase = false;
  bool hasLowerCase = false;
  bool hasNumbers = false;
  bool hasSpecialChar = false;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _passwordController.addListener(_validatePassword);
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );

    _opacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _waveAnimation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  void _validatePassword() {
    final password = _passwordController.text;
    setState(() {
      hasMinLength = password.length >= 8;
      hasUpperCase = password.contains(RegExp(r'[A-Z]'));
      hasLowerCase = password.contains(RegExp(r'[a-z]'));
      hasNumbers = password.contains(RegExp(r'[0-9]'));
      hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isValidPassword() {
    return hasMinLength &&
        hasUpperCase &&
        hasLowerCase &&
        hasNumbers &&
        hasSpecialChar;
  }

  Future<void> _login() async {
    setState(() {
      errorMessage = '';
      isLoading = true;
    });

    try {
      final emailInput = _emailController.text.trim();
      final passwordInput = _passwordController.text.trim();

      if (emailInput.isEmpty || passwordInput.isEmpty) {
        setState(() {
          errorMessage = "Please enter both email and password.";
          isLoading = false;
        });
        return;
      }

      if (!_isValidEmail(emailInput)) {
        setState(() {
          errorMessage = "Please enter a valid email address.";
          isLoading = false;
        });
        return;
      }

      if (!_isValidPassword()) {
        setState(() {
          errorMessage = "Password does not meet the requirements.";
          isLoading = false;
        });
        return;
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: emailInput)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          errorMessage = "User not found.";
          isLoading = false;
        });
        return;
      }

      final userDoc = querySnapshot.docs.first;
      final userData = userDoc.data();

      if (userData['password'] != passwordInput) {
        setState(() {
          errorMessage = "Incorrect password.";
          isLoading = false;
        });
        return;
      }

      // Set isLoggedIn to true in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .update({'isLoggedIn': true});

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DashboardPage(email: emailInput)),
        );
      }
    } catch (e) {
      setState(() {
        errorMessage = "Login failed: ${e.toString()}";
        isLoading = false;
      });
    }
  }

  void _showForgotPasswordDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: Color(0xFF1976D2), // Buttons, highlights
      onPrimary: Colors.white, // Button text
      surface: Color(0xFFF5F7FA), // Background
      onSurface: Color(0xFF2E2E2E), // General text
      secondary: Color(0xFF64B5F6), // Accent
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: AnimatedBuilder(
        animation: _waveAnimation,
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Animated wave background
              CustomPaint(
                size: MediaQuery.of(context).size,
                painter: AnimatedWaveBackgroundPainter(
                  _waveAnimation.value,
                  colorScheme,
                ),
              ),

              // Glassmorphic floating card login form
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: FadeTransition(
                        opacity: _opacityAnimation,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              width: 400,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 40,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.22),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.10),
                                    blurRadius: 36,
                                    offset: const Offset(0, 16),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Logo circle
                                  Center(
                                    child: Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: [
                                            colorScheme.primary,
                                            colorScheme.secondary,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.08,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.business_center_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 28),

                                  // Welcome text
                                  Text(
                                    'Welcome Back',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 36),

                                  // Email field
                                  _buildGlassTextField(
                                    controller: _emailController,
                                    hintText: 'Email',
                                    icon: Icons.email_outlined,
                                    obscure: false,
                                    colorScheme: colorScheme,
                                  ),
                                  const SizedBox(height: 18),

                                  // Password field with toggle visibility
                                  _buildGlassTextField(
                                    controller: _passwordController,
                                    hintText: 'Password',
                                    icon: Icons.lock_outline,
                                    obscure: _obscurePassword,
                                    toggleObscure: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    colorScheme: colorScheme,
                                  ),
                                  const SizedBox(height: 22),

                                  // Login button with gradient background and loading spinner
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          colorScheme.primary,
                                          colorScheme.secondary,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.10),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: AnimatedScale(
                                      scale: isLoading ? 0.97 : 1.0,
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      child: SizedBox(
                                        height: 48,
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: isLoading ? null : _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(22),
                                            ),
                                          ),
                                          child: isLoading
                                              ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child:
                                            CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                              : Text(
                                            "Log In",
                                            style: TextStyle(
                                              fontFamily: 'Montserrat',
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                              color:
                                              colorScheme.onPrimary,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Forgot Password button
                                  Center(
                                    child: TextButton(
                                      onPressed: _showForgotPasswordDialog,
                                      style: TextButton.styleFrom(
                                        foregroundColor: colorScheme.primary,
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          fontFamily: 'Montserrat',
                                        ),
                                      ),
                                      child: const Text("Forgot Password?"),
                                    ),
                                  ),

                                  // Error message box
                                  if (errorMessage.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.red[50],
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.red[200]!,
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          errorMessage,
                                          style: TextStyle(
                                            color: Colors.red[700],
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Widget for building styled glassmorphic TextFields
  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required bool obscure,
    required ColorScheme colorScheme,
    VoidCallback? toggleObscure,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(
          fontSize: 15,
          color: colorScheme.onSurface,
          fontFamily: 'Montserrat',
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: colorScheme.primary, size: 22),
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[500],
            fontSize: 15,
            fontFamily: 'Montserrat',
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          suffixIcon: toggleObscure != null
              ? IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[400],
            ),
            onPressed: toggleObscure,
          )
              : null,
        ),
      ),
    );
  }
}

// Animated wave background painter
class AnimatedWaveBackgroundPainter extends CustomPainter {
  final double wavePhase;
  final ColorScheme colorScheme;

  AnimatedWaveBackgroundPainter(this.wavePhase, this.colorScheme);

  @override
  void paint(Canvas canvas, Size size) {
    final List<Color> waveColors = [
      colorScheme.primary.withOpacity(0.18),
      colorScheme.secondary.withOpacity(0.13),
      colorScheme.primary.withOpacity(0.10),
    ];

    for (int i = 0; i < 3; i++) {
      final path = Path();
      final amplitude = 18.0 + i * 10;
      final frequency = 1.5 + i * 0.5;
      final yOffset = size.height * (0.65 + i * 0.08);

      path.moveTo(0, yOffset);
      for (double x = 0; x <= size.width; x += 1) {
        final y = amplitude *
            sin((x / size.width * 2 * pi * frequency) + wavePhase + i) +
            yOffset;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final paint = Paint()..color = waveColors[i];
      canvas.drawPath(path, paint);
    }

    // Subtle gradient overlay
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      colors: [
        colorScheme.surface,
        colorScheme.primary.withOpacity(0.7),
        colorScheme.secondary.withOpacity(0.5),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant AnimatedWaveBackgroundPainter oldDelegate) {
    return oldDelegate.wavePhase != wavePhase;
  }
}

Future<void> setIsLoggedInForAllUsers(bool value) async {
  final users = await FirebaseFirestore.instance.collection('users').get();
  for (final doc in users.docs) {
    await doc.reference.update({'isLoggedIn': value});
  }
  print('All users updated!');
}

Future<void> logout(BuildContext context, String email) async {
  // Find the user doc by email
  final query = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: email)
      .limit(1)
      .get();
  if (query.docs.isNotEmpty) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(query.docs.first.id)
        .update({'isLoggedIn': false});
  }
  // Then navigate to login screen
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const AnimatedLoginScreen()),
        (route) => false,
  );
}
