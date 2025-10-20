import 'package:absensiwajah/pages/login.dart';
import 'package:absensiwajah/pages/main_dashboard.dart';
import 'package:absensiwajah/pages/join_organization_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/localization_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://oxkuxwkehinhyxfsauqe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im94a3V4d2tlaGluaHl4ZnNhdXFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5NDYxOTMsImV4cCI6MjA3MzUyMjE5M30.g3BjGtZCSFxnBDwMWkaM2mEcnCkoDL92fvTP_gUgR20',
  );
  
  await initializeDateFormatting('id_ID', null);
  await LocalizationHelper.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Absensi Wajah',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
    _navigateToNextScreen();
  }

  Future<void> _checkMembershipAndNavigate() async {
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;

    // Jika belum login, langsung ke Login
    if (session == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const Login()),
      );
      return;
    }

    // Jika sudah login, cek apakah sudah join organization
    try {
      final userId = session.user.id;
      
      // Cek apakah user sudah menjadi member di organization manapun
      final memberResponse = await Supabase.instance.client
          .from('organization_members')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (!mounted) return;

      // Jika sudah ada organization, langsung ke Dashboard
      if (memberResponse != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainDashboard()),
        );
      } else {
        // Jika belum join organization, ke halaman Join Organization
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const JoinOrganizationScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error checking organization membership: $e');
      if (!mounted) return;
      
      // Jika error, asumsikan belum join organization
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const JoinOrganizationScreen()),
      );
    }
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 3));
    await _checkMembershipAndNavigate();
    
    // Setup auth state listener untuk detect logout atau session change
    if (mounted) {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        
        final AuthChangeEvent event = data.event;
        
        // Jika user logout atau token invalid
        if (event == AuthChangeEvent.signedOut || event == AuthChangeEvent.tokenRefreshed) {
          _checkMembershipAndNavigate();
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.teal.shade400,
              Colors.teal.shade700,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.face_rounded,
                      size: 70,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Absensi Wajah',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sistem Absensi Modern',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 50),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withOpacity(0.8),
                      ),
                      strokeWidth: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}