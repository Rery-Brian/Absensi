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
                      onPressed: () {
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
                  onPressed: signIn,
                  color: const Color(0xFF009688),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  padding: const EdgeInsets.all(16),
                  minWidth: MediaQuery.of(context).size.width,
                  child: const Text(
                    "Login",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Navigasi ke signup
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Belum punya akun?"),
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
  );
}
}