import 'package:flutter/material.dart';
import 'package:absensiwajah/pages/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../helpers/flushbar_helper.dart';

final supabase = Supabase.instance.client;

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Theme colors matching dashboard and login
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      FlushbarHelper.showError(
        context,
        'Name, email, and password are required',
      );
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      FlushbarHelper.showError(
        context,
        'Invalid email format',
      );
      return;
    }

    if (password.length < 6) {
      FlushbarHelper.showError(
        context,
        'Password must be at least 6 characters',
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final AuthResponse res = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
        },
      );

      if (res.user != null) {
        _showSuccessDialog();
      } else {
        if (mounted) {
          FlushbarHelper.showError(
            context,
            'Failed to create account',
          );
        }
      }
    } catch (e) {
      String errorMessage = 'Registration failed: ';
      
      if (e.toString().contains('already registered')) {
        errorMessage += 'Email already registered';
      } else if (e.toString().contains('invalid email')) {
        errorMessage += 'Invalid email format';
      } else if (e.toString().contains('weak password')) {
        errorMessage += 'Password too weak';
      } else {
        errorMessage += e.toString();
      }

      if (mounted) {
        FlushbarHelper.showError(
          context,
          errorMessage,
          duration: const Duration(seconds: 5),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          size: 40,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Registration Successful!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your account has been created successfully',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _nameController.clear();
                      _emailController.clear();
                      _passwordController.clear();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const Login()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue to Login',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    
    final isSmallScreen = size.width < 360;

    double headerHeight = isLandscape 
        ? 180.0
        : (isSmallScreen ? size.height * 0.30 : size.height * 0.35);
    
    double logoSize = isLandscape ? 50 : (isSmallScreen ? 70 : 80);
    double titleFontSize = isLandscape ? 20 : (isSmallScreen ? 24 : 28);
    double subtitleFontSize = isLandscape ? 11 : (isSmallScreen ? 13 : 14);
    double cardTopOffset = isLandscape ? -15 : -20;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                height: headerHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      backgroundColor,
                      backgroundColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: isLandscape ? 10 : 20),
                    Container(
                      width: logoSize,
                      height: logoSize,
                      padding: EdgeInsets.all(logoSize * 0.2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Image(
                        image: AssetImage("images/logo.png"),
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: isLandscape ? 8 : 16),
                    Text(
                      "Absensi",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: titleFontSize,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: isLandscape ? 2 : 4),
                    Text(
                      "Create Your Account",
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Form card
              Transform.translate(
                offset: Offset(0, cardTopOffset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSignupForm(
                    isSmallScreen: isSmallScreen,
                    isLandscape: isLandscape,
                  ),
                ),
              ),
              
              if (isLandscape) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignupForm({
    required bool isSmallScreen,
    required bool isLandscape,
  }) {
    double welcomeFontSize = isLandscape ? 16 : (isSmallScreen ? 18 : 20);
    double labelFontSize = isLandscape ? 11 : (isSmallScreen ? 12 : 13);
    double hintFontSize = isLandscape ? 12 : (isSmallScreen ? 13 : 14);
    double buttonFontSize = isLandscape ? 13 : (isSmallScreen ? 14 : 15);
    double dividerFontSize = isLandscape ? 10 : (isSmallScreen ? 11 : 12);
    double cardPadding = isLandscape ? 14 : (isSmallScreen ? 16 : 20);
    
    double verticalSpacing = isLandscape ? 6 : (isSmallScreen ? 8 : 10);
    double sectionSpacing = isLandscape ? 8 : (isSmallScreen ? 12 : 15);
    double buttonVerticalPadding = isLandscape ? 8 : (isSmallScreen ? 10 : 12);

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Create Account",
            style: TextStyle(
              fontSize: welcomeFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isLandscape ? 2 : 4),
          Text(
            "Fill in your details to get started",
            style: TextStyle(
              fontSize: hintFontSize,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: sectionSpacing + (isLandscape ? 0 : 5)),
          
          // Name Field
          _buildTextField(
            controller: _nameController,
            label: "Full Name",
            hint: "Enter your full name",
            icon: Icons.person_outline,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
          ),
          SizedBox(height: verticalSpacing),
          
          // Email Field
          _buildTextField(
            controller: _emailController,
            label: "Email",
            hint: "Enter your email",
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
          ),
          SizedBox(height: verticalSpacing),
          
          // Password Field
          _buildTextField(
            controller: _passwordController,
            label: "Password",
            hint: "Enter your password (min. 6 chars)",
            icon: Icons.lock_outline,
            obscureText: _obscurePassword,
            labelFontSize: labelFontSize,
            hintFontSize: hintFontSize,
            isLandscape: isLandscape,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.grey.shade500,
                size: isLandscape ? 18 : 20,
              ),
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
            ),
          ),
          SizedBox(height: sectionSpacing),
          
          // Create Account Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: buttonVerticalPadding,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? SizedBox(
                      width: isLandscape ? 16 : 18,
                      height: isLandscape ? 16 : 18,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          
          // Loading indicator
          if (_isLoading) ...[
            SizedBox(height: verticalSpacing),
            Container(
              padding: EdgeInsets.all(isLandscape ? 6 : (isSmallScreen ? 8 : 10)),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: isLandscape ? 12 : 14,
                    height: isLandscape ? 12 : 14,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(width: isLandscape ? 8 : 10),
                  Expanded(
                    child: Text(
                      'Creating your account...',
                      style: TextStyle(
                        fontSize: dividerFontSize,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Login Link
          Padding(
            padding: EdgeInsets.only(top: isLandscape ? 4 : (isSmallScreen ? 8 : 0)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Already have an account? ",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: hintFontSize,
                  ),
                ),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const Login(),
                            ),
                          );
                        },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isLandscape ? 2 : 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    "Sign In",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                      fontSize: hintFontSize,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required double labelFontSize,
    required double hintFontSize,
    required bool isLandscape,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: isLandscape ? 4 : 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: !_isLoading,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: hintFontSize,
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            prefixIcon: Icon(
              icon,
              color: Colors.grey.shade500,
              size: isLandscape ? 18 : 20,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.grey.shade300,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: primaryColor,
                width: 2,
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 10 : 12,
              vertical: isLandscape ? 10 : 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}