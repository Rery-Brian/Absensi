import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup.dart';
import 'dashboard.dart';
import 'main_dashboard.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

final supabase = Supabase.instance.client;

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Theme colors matching dashboard
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  // Function untuk auto-register user ke organisasi
  Future<bool> _autoRegisterUserToOrganization(String userId) async {
    try {
      print('Checking if user is already registered to organization...');

      final existingMember = await supabase
          .from('organization_members')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (existingMember != null) {
        print('User already registered to organization');
        return true;
      }

      print('Auto-registering user to organization...');

      final result = await supabase.rpc(
        'add_user_to_organization',
        params: {
          'p_user_id': userId,
          'p_employee_id': null,
          'p_organization_code': 'COMPANY001',
          'p_department_code': 'IT',
          'p_position_code': 'STAFF',
        },
      );

      if (result != null) {
        print('User auto-registered successfully with member ID: $result');
        return true;
      } else {
        print('Auto-registration returned null');
        return false;
      }
    } catch (e) {
      print('Auto-registration failed: $e');
      return false;
    }
  }

  Future<void> _nativeGoogleSignIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      const webClientId =
          '210380129521-4qnge4hlqjphmjahj79d4tv5h67gjc5s.apps.googleusercontent.com';

      const androidClientId =
          '210380129521-9qcqse1mqa96aqo6liereotg82bquv8d.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        clientId: androidClientId,
        scopes: ['email', 'profile'],
      );

      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null) {
        throw Exception('No ID Token found.');
      }

      print('Google User: ${googleUser.email}');

      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (response.user != null) {
        print('Google login successful, user ID: ${response.user!.id}');

        final registrationSuccess = await _autoRegisterUserToOrganization(
          response.user!.id,
        );

        if (!registrationSuccess) {
          print(
            'Warning: Auto-registration failed, but continuing to dashboard',
          );
          _showDialog(
            title: "Info",
            message:
                "Login berhasil, tetapi pendaftaran organisasi gagal. Hubungi admin jika diperlukan.",
            isSuccess: true,
          );
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', response.user!.email!);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MainDashboard(),
          ),
        );
      } else {
        throw Exception('Login gagal: User null dari Supabase');
      }
    } catch (e) {
      print('Google Sign-in Error: $e');
      if (!mounted) return;
      _showDialog(
        title: "Error Google Sign-in",
        message: "Gagal login dengan Google: ${e.toString()}",
        isSuccess: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void signIn() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = res.user;
      if (user != null) {
        print('Email login successful, user ID: ${user.id}');

        final registrationSuccess = await _autoRegisterUserToOrganization(
          user.id,
        );

        if (!registrationSuccess) {
          print(
            'Warning: Auto-registration failed, but continuing to dashboard',
          );
          _showDialog(
            title: "Info",
            message:
                "Login berhasil, tetapi pendaftaran organisasi gagal. Hubungi admin jika diperlukan.",
            isSuccess: true,
          );
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', user.email!);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MainDashboard(),
          ),
        );
      } else {
        if (!mounted) return;
        _showDialog(
          title: "Login Gagal",
          message: "Email atau password salah.",
          isSuccess: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showDialog(title: "Error", message: e.toString(), isSuccess: false);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showDialog({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    
    // Responsive sizing
    final isSmallScreen = size.width < 360;

    // Dynamic values - landscape lebih kecil
    double headerHeight = isLandscape 
        ? 180.0  // Fixed height untuk landscape
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
              // Header dengan gradient dan logo
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
                    // Logo dengan background circle
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
                    // Title
                    Text(
                      "Absensi",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: titleFontSize,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: isLandscape ? 2 : 4),
                    // Subtitle
                    Text(
                      "Smart Attendance System",
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Form login card dengan negative margin
              Transform.translate(
                offset: Offset(0, cardTopOffset),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLoginForm(
                    isSmallScreen: isSmallScreen,
                    isLandscape: isLandscape,
                  ),
                ),
              ),
              
              // Extra padding di bawah untuk landscape
              if (isLandscape) const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm({
    required bool isSmallScreen,
    required bool isLandscape,
  }) {
    // Responsive font sizes - lebih kecil di landscape
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
            "Welcome Back",
            style: TextStyle(
              fontSize: welcomeFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isLandscape ? 2 : 4),
          Text(
            "Sign in to continue",
            style: TextStyle(
              fontSize: hintFontSize,
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: sectionSpacing + (isLandscape ? 2 : 5)),
          
          // Google Sign In Button - DIPINDAH KE ATAS
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _nativeGoogleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                disabledBackgroundColor: Colors.grey.shade100,
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1.5,
                ),
                padding: EdgeInsets.symmetric(
                  vertical: buttonVerticalPadding + 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    'https://cdn.freebiesupply.com/logos/large/2x/google-g-2015-logo-png-transparent.png',
                    height: isLandscape ? 18 : 20,
                    width: isLandscape ? 18 : 20,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: isLandscape ? 18 : 20,
                        height: isLandscape ? 18 : 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          image: const DecorationImage(
                            image: NetworkImage(
                              'https://upload.wikimedia.org/wikipedia/commons/5/53/Google_%22G%22_Logo.svg',
                            ),
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(width: isLandscape ? 10 : 12),
                  Text(
                    _isLoading ? "Processing..." : "Continue with Google",
                    style: TextStyle(
                      fontSize: buttonFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: sectionSpacing),
          
          // Divider
          Row(
            children: [
              Expanded(
                child: Divider(
                  thickness: 1,
                  color: Colors.grey.shade300,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 12),
                child: Text(
                  "or sign in with email",
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: dividerFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  thickness: 1,
                  color: Colors.grey.shade300,
                ),
              ),
            ],
          ),
          SizedBox(height: sectionSpacing),
          
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
            hint: "Enter your password",
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
          
          // Sign In Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : signIn,
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
                elevation: 2,
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
                      "Sign In",
                      style: TextStyle(
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          
          // Loading indicator
          if (_isLoading) ...[
            SizedBox(height: verticalSpacing + 2),
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
                      'Processing login...',
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
          
          // Sign Up Link
          Padding(
            padding: EdgeInsets.only(top: isLandscape ? 6 : (isSmallScreen ? 10 : 12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
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
                              builder: (_) => Signup(),
                            ),
                          );
                        },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isLandscape ? 2 : 4),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    "Sign Up",
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
}