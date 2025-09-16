import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'signup.dart'; // pastikan file ini ada
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

  void signIn() async {
  try {
    final res = await supabase.auth.signInWithPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    final user = res.user;
    if (user != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', user.email!);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login berhasil'),
          duration: Duration(seconds: 2),
        ),
      );

      // Navigasi ke halaman Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => UserDashboard()),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login gagal: Email atau password salah'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Login gagal: ${e.toString()}')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffe6e6e6),
      body: Stack(
        alignment: Alignment.topLeft,
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.35,
            decoration: BoxDecoration(
              color: const Color(0xff3a57e8),
              border: Border.all(color: const Color(0x4d9e9e9e), width: 1),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 100, 20, 20),
            height: MediaQuery.of(context).size.height * 0.67,
            decoration: BoxDecoration(
              color: const Color(0xffffffff),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: const Color(0x4d9e9e9e), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Image.asset(
                    "images/LogoApp.png",
                    height: 93,
                    width: 221,
                    fit: BoxFit.cover,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "SMK UBIG MALANG",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      color: Color(0xff385cef),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: "Email",
                      filled: true,
                      fillColor: const Color(0xffdfdfdf),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: "Password",
                      filled: true,
                      fillColor: const Color(0xffd6d6d6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: const Color(0xff212435),
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  MaterialButton(
                    onPressed: signIn,
                    color: const Color(0xff3a57e8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    padding: const EdgeInsets.all(16),
                    minWidth: MediaQuery.of(context).size.width,
                    height: 53,
                    child: const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                 Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Sudah punya akun?"),
                TextButton(
                  onPressed: () {
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
