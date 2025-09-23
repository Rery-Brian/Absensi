import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'signup.dart';
import 'dashboard.dart';

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
      final result = await supabase.rpc('add_user_to_organization', params: {
        'p_user_id': userId,
        'p_employee_id': null, // Will auto-generate
        'p_organization_code': 'COMPANY001',
        'p_department_code': 'IT',
        'p_position_code': 'STAFF',
      });

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
        final registrationSuccess = await _autoRegisterUserToOrganization(response.user!.id);
        
        if (!registrationSuccess) {
          print('Warning: Auto-registration failed, but continuing to dashboard');
          // Bisa tetap lanjut ke dashboard atau tampilkan peringatan
          _showDialog(
            title: "Info",
            message: "Login berhasil, tetapi pendaftaran organisasi gagal. Hubungi admin jika diperlukan.",
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
          MaterialPageRoute(builder: (context) => const UserDashboard()),
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
        final registrationSuccess = await _autoRegisterUserToOrganization(user.id);
        
        if (!registrationSuccess) {
          print('Warning: Auto-registration failed, but continuing to dashboard');
          // Tetap lanjut ke dashboard tapi beri peringatan
          _showDialog(
            title: "Info",
            message: "Login berhasil, tetapi pendaftaran organisasi gagal. Hubungi admin jika diperlukan.",
            isSuccess: true,
          );
        }

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', user.email!);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserDashboard()),
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
      _showDialog(
        title: "Error", 
        message: e.toString(), 
        isSuccess: false
      );
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
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.error,
                color: isSuccess ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title, 
                  style: const TextStyle(fontWeight: FontWeight.bold)
                ),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff1f1f1),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header dengan logo dan judul
            Container(
              alignment: Alignment.center,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height * 0.4,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(60.0),
                ),
              ),
              child: Column(
                children: const [
                  SizedBox(height: 44),
                  Image(
                    image: AssetImage("images/logo.png"),
                    height: 150,
                    width: 150,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Absensi",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 26,
                      color: Color(0xFF009688),
                    ),
                  ),
                ],
              ),
            ),

            // Form login
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
              child: Column(
                children: [
                  // Email
                  TextField(
                    controller: _emailController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: "Email",
                      filled: true,
                      fillColor: Color(0xffd9d9d9),
                      prefixIcon: Icon(Icons.mail, color: Colors.black),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      hintText: "Password",
                      filled: true,
                      fillColor: const Color(0xffd9d9d9),
                      prefixIcon: const Icon(Icons.lock, color: Colors.black),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.black,
                        ),
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12.0)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tombol Login
                  MaterialButton(
                    onPressed: _isLoading ? null : signIn,
                    color: const Color(0xFF009688),
                    disabledColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    padding: const EdgeInsets.all(16),
                    minWidth: MediaQuery.of(context).size.width,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Login",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Divider
                  Row(
                    children: const [
                      Expanded(child: Divider(thickness: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "atau",
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(thickness: 1)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Tombol Login dengan Google
                  MaterialButton(
                    onPressed: _isLoading ? null : _nativeGoogleSignIn,
                    color: Colors.white,
                    disabledColor: Colors.grey[200],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: const BorderSide(color: Colors.grey, width: 1),
                    ),
                    padding: const EdgeInsets.all(16),
                    minWidth: MediaQuery.of(context).size.width,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Google logo
                        Image.network(
                          'https://developers.google.com/identity/images/g-logo.png',
                          height: 20,
                          width: 20,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.g_mobiledata,
                              size: 20,
                              color: Colors.red,
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isLoading ? "Memproses..." : "Masuk dengan Google",
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_isLoading) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF009688).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF009688).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: const [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF009688),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Sedang memproses login dan mendaftarkan ke organisasi...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF009688),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Navigasi ke signup
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Belum punya akun?"),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => Signup()),
                          );
                        },
                  child: const Text(
                    "Daftar Disini!",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xff3a57e8),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}