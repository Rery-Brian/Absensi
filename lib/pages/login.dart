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

      // Cek apakah user sudah terdaftar di organisasi
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

      // Call PostgreSQL function untuk auto-register
      final result = await supabase.rpc(
        'add_user_to_organization',
        params: {
          'p_user_id': userId,
          'p_employee_id': null, // Will auto-generate
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

      await googleSignIn.signOut(); // Clear previous session

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

      // Sign in ke Supabase dengan ID token
      final response = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (response.user != null) {
        print('Google login successful, user ID: ${response.user!.id}');

        // Auto-register user ke organisasi
        final registrationSuccess = await _autoRegisterUserToOrganization(
          response.user!.id,
        );

        if (!registrationSuccess) {
          print(
            'Warning: Auto-registration failed, but continuing to dashboard',
          );
          // Bisa tetap lanjut ke dashboard atau tampilkan peringatan
          _showDialog(
            title: "Info",
            message:
                "Login berhasil, tetapi pendaftaran organisasi gagal. Hubungi admin jika diperlukan.",
            isSuccess: true,
          );
        }

        // Simpan email user ke SharedPreferences
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', response.user!.email!);

        if (!mounted) return;

        // Navigasi ke dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MainDashboard(),
          ), // Use MainDashboard for bottom navigation
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

        // Auto-register user ke organisasi
        final registrationSuccess = await _autoRegisterUserToOrganization(
          user.id,
        );

        if (!registrationSuccess) {
          print(
            'Warning: Auto-registration failed, but continuing to dashboard',
          );
          // Tetap lanjut ke dashboard tapi beri peringatan
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
          ), // Use MainDashboard for bottom navigation
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SafeArea(
        child: Column(
          children: [
            // Header dengan gradient dan logo - lebih kecil
            Container(
              width: double.infinity,
              height: screenHeight * 0.35, // Dikurangi dari 0.45
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
                  const SizedBox(height: 20), // Dikurangi dari 60
                  // Logo dengan background circle - lebih kecil
                  Container(
                    width: 80, // Dikurangi dari 120
                    height: 80, // Dikurangi dari 120
                    padding: const EdgeInsets.all(16), // Dikurangi dari 20
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Image(
                      image: AssetImage("images/logo.png"),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16), // Dikurangi dari 24
                  // Title
                  const Text(
                    "Absensi",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 28, // Dikurangi dari 32
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4), // Dikurangi dari 8
                  // Subtitle
                  Text(
                    "Smart Attendance System",
                    style: TextStyle(
                      fontSize: 14, // Dikurangi dari 16
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            // Expanded untuk mengisi sisa ruang
            Expanded(
              child: Stack(
                clipBehavior: Clip.none, // Memungkinkan card melewati batas
                children: [
                  // Form login card - lebih kecil dan positioning yang fixed
                  Positioned(
                    top: -20, // Dikurangi dari -30
                    left: 16, // Dikurangi margin
                    right: 16, // Dikurangi margin
                    child: Container(
                      padding: const EdgeInsets.all(20), // Dikurangi dari 28
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          16,
                        ), // Dikurangi dari 20
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 15, // Dikurangi dari 20
                            offset: const Offset(0, 8), // Dikurangi dari 10
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Welcome Back",
                            style: TextStyle(
                              fontSize: 20, // Dikurangi dari 24
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4), // Dikurangi dari 8
                          Text(
                            "Sign in to continue",
                            style: TextStyle(
                              fontSize: 14, // Dikurangi dari 16
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 20), // Dikurangi dari 32
                          // Email TextField - lebih kompak
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Email",
                                style: TextStyle(
                                  fontSize: 13, // Dikurangi dari 14
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6), // Dikurangi dari 8
                              TextField(
                                controller: _emailController,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: "Enter your email",
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: Icon(
                                    Icons.mail_outline,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ), // Dikurangi dari 12
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, // Dikurangi dari 16
                                    vertical: 12, // Dikurangi dari 16
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10), // Dikurangi dari 20
                          // Password TextField - lebih kompak
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Password",
                                style: TextStyle(
                                  fontSize: 13, // Dikurangi dari 14
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6), // Dikurangi dari 8
                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  hintText: "Enter your password",
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 14,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.grey.shade500,
                                      size: 20,
                                    ),
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                  ),
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
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15), // Dikurangi dari 20
                          // Login Button - lebih kompak
SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: _isLoading ? null : signIn,
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade300,
      disabledForegroundColor: Colors.white, // ✅ tetap putih saat disabled
      padding: const EdgeInsets.symmetric(
        vertical: 12,
      ), // lebih kecil
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      elevation: 0,
    ),
    child: _isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white,
              ),
            ),
          )
        : const Text(
            "Sign In",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
  ),
),

const SizedBox(height: 12), // lebih kompak
// Divider - lebih kompak
Row(
  children: [
    Expanded(
      child: Divider(
        thickness: 1,
        color: Colors.grey.shade300,
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        "or continue with",
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12,
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

const SizedBox(height: 8), // lebih kompak
// Google Sign In Button - lebih kompak
SizedBox(
  width: double.infinity,
  child: OutlinedButton(
    onPressed: _isLoading ? null : _nativeGoogleSignIn,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.black87,
      disabledForegroundColor: Colors.black87, // ✅ tetap hitam saat disabled
      side: BorderSide(color: Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(
        vertical: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.network(
          'https://cdn.freebiesupply.com/logos/large/2x/google-g-2015-logo-png-transparent.png',
          height: 18,
          width: 18,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 18,
              height: 18,
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
        const SizedBox(width: 10),
        Text(
          _isLoading ? "Processing..." : "Continue with Google",
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  ),
),

                          // Loading indicator - lebih kompak
                          if (_isLoading) ...[
                            const SizedBox(height: 10), // Dikurangi dari 20
                            Container(
                              padding: const EdgeInsets.all(
                                10,
                              ), // Dikurangi dari 16
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  10,
                                ), // Dikurangi dari 12
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14, // Dikurangi dari 16
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        primaryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ), // Dikurangi dari 12
                                  const Expanded(
                                    child: Text(
                                      'Processing login...',
                                      style: TextStyle(
                                        fontSize: 12, // Dikurangi dari 14
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Sign Up Link - fixed di bawah
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 0,
                              top: 0,
                            ), // Dikurangi dari 40
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14, // Dikurangi dari 15
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
                                  child: const Text(
                                    "Sign Up",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                      fontSize: 14, // Dikurangi dari 15
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}