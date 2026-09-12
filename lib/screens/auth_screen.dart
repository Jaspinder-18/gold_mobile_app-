import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Login Form Controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _loginObscurePassword = true;
  bool _isLoggingIn = false;
  String? _loginError;

  // Register Form Controllers
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();
  bool _regObscurePassword = true;
  bool _regObscureConfirmPassword = true;
  bool _isRegistering = false;
  String? _regError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: const HomeScreen(),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;

    if (email.isEmpty) {
      setState(() => _loginError = 'Please enter your email address.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _loginError = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });

    final res = await AuthService().login(email: email, password: password);

    if (mounted) {
      setState(() => _isLoggingIn = false);
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Welcome back, ${AuthService().currentUser?.fullName ?? 'Trader'}! Devices Synced.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        _navigateToHome();
      } else {
        setState(() => _loginError = res['error']?.toString() ?? 'Login failed. Please verify credentials.');
      }
    }
  }

  Future<void> _handleRegister() async {
    final name = _regNameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text;
    final confirmPassword = _regConfirmPasswordController.text;

    if (name.isEmpty) {
      setState(() => _regError = 'Please enter your full name.');
      return;
    }
    if (email.isEmpty) {
      setState(() => _regError = 'Please enter your email address.');
      return;
    }
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      setState(() => _regError = 'Please enter a valid email format.');
      return;
    }
    if (password.length < 6) {
      setState(() => _regError = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _regError = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isRegistering = true;
      _regError = null;
    });

    final res = await AuthService().register(
      fullName: name,
      email: email,
      password: password,
      confirmPassword: confirmPassword,
    );

    if (mounted) {
      setState(() => _isRegistering = false);
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Account created successfully! Welcome, $name.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        _navigateToHome();
      } else {
        setState(() => _regError = res['error']?.toString() ?? 'Registration failed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070A12),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. APP BRANDING HEADER
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: const Icon(Icons.show_chart, color: Color(0xFFF59E0B), size: 36),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ALERT TERMINAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Multi-Asset Market Watch & Instant Alarm System',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),

                // 2. TAB TOGGLE (SIGN IN / REGISTER)
                Container(
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.0),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'SIGN IN'),
                      Tab(text: 'REGISTER'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 3. TAB CONTENT
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLoginTab(),
                      _buildRegisterTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loginError != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_loginError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        _buildTextField(
          controller: _loginEmailController,
          label: 'Email Address',
          hint: 'trader@example.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        _buildTextField(
          controller: _loginPasswordController,
          label: 'Password',
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscureText: _loginObscurePassword,
          suffixIcon: IconButton(
            icon: Icon(_loginObscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _loginObscurePassword = !_loginObscurePassword),
          ),
        ),
        const SizedBox(height: 20),

        SizedBox(
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            onPressed: _isLoggingIn ? null : _handleLogin,
            child: _isLoggingIn
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text(
                    'SIGN IN TO TERMINAL',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.8),
                  ),
          ),
        ),
        const SizedBox(height: 8),

        // Forgot / Reset Password Button
        Center(
          child: TextButton(
            onPressed: _showResetPasswordDialog,
            child: const Text(
              'Forgot Password? Reset Here',
              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '📱 Your device will automatically pair with your account for 24/7 push notifications & loud price touch alarms.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.4),
        ),
      ],
    );
  }

  void _showResetPasswordDialog() {
    final emailCtrl = TextEditingController(text: _loginEmailController.text.trim());
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? dialogError;
    bool isResetting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_reset, color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Text(
                'Reset Password',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dialogError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: Text(dialogError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: emailCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Account Email',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'New Password (min 6 chars)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isResetting
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      final pass = newPassCtrl.text;
                      final conf = confirmPassCtrl.text;
                      if (email.isEmpty || pass.isEmpty) {
                        setDialogState(() => dialogError = 'Please fill all fields.');
                        return;
                      }
                      if (pass.length < 6) {
                        setDialogState(() => dialogError = 'Password must be at least 6 characters.');
                        return;
                      }
                      if (pass != conf) {
                        setDialogState(() => dialogError = 'Passwords do not match.');
                        return;
                      }

                      setDialogState(() {
                        isResetting = true;
                        dialogError = null;
                      });

                      final res = await AuthService().resetPassword(
                        email: email,
                        newPassword: pass,
                        confirmPassword: conf,
                      );

                      if (ctx.mounted) {
                        setDialogState(() => isResetting = false);
                        if (res['success'] == true) {
                          Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF10B981),
                                content: Text('✓ Password reset successfully! Logged in.'),
                              ),
                            );
                            _navigateToHome();
                          }
                        } else {
                          setDialogState(() => dialogError = res['error']?.toString() ?? 'Reset failed.');
                        }
                      }
                    },
              child: isResetting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('RESET & LOGIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_regError != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_regError!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        _buildTextField(
          controller: _regNameController,
          label: 'Full Name',
          hint: 'Alex Rivera',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 10),

        _buildTextField(
          controller: _regEmailController,
          label: 'Email Address',
          hint: 'trader@example.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 10),

        _buildTextField(
          controller: _regPasswordController,
          label: 'Password',
          hint: 'Min. 6 characters',
          icon: Icons.lock_outline,
          obscureText: _regObscurePassword,
          suffixIcon: IconButton(
            icon: Icon(_regObscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _regObscurePassword = !_regObscurePassword),
          ),
        ),
        const SizedBox(height: 10),

        _buildTextField(
          controller: _regConfirmPasswordController,
          label: 'Confirm Password',
          hint: 'Re-enter password',
          icon: Icons.lock_reset,
          obscureText: _regObscureConfirmPassword,
          suffixIcon: IconButton(
            icon: Icon(_regObscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
            onPressed: () => setState(() => _regObscureConfirmPassword = !_regObscureConfirmPassword),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            onPressed: _isRegistering ? null : _handleRegister,
            child: _isRegistering
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text(
                    'CREATE ACCOUNT & REGISTER DEVICE',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
        ),
        const SizedBox(height: 4),
        Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              prefixIcon: Icon(icon, color: const Color(0xFFF59E0B), size: 18),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
