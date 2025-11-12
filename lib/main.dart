import 'package:absensiwajah/pages/login.dart';
import 'package:absensiwajah/pages/main_dashboard.dart';
import 'package:absensiwajah/pages/join_organization_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lottie/lottie.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'helpers/localization_helper.dart';
import 'helpers/cache_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://oxkuxwkehinhyxfsauqe.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im94a3V4d2tlaGluaHl4ZnNhdXFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5NDYxOTMsImV4cCI6MjA3MzUyMjE5M30.g3BjGtZCSFxnBDwMWkaM2mEcnCkoDL92fvTP_gUgR20',
  );
  
  await initializeDateFormatting('id_ID', null);
  await LocalizationHelper.initialize();
  
  // ✅ OPTIMIZATION: Initialize cache helper
  CacheHelper().initialize();
  
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

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  Future<void> _checkMembershipAndNavigate() async {
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const Login()),
      );
      return;
    }

    try {
      final userId = session.user.id;
      
      final memberResponse = await Supabase.instance.client
          .from('organization_members')
          .select('id')
          .eq('user_id', userId)
          .eq('is_active', true)
          .maybeSingle();

      if (!mounted) return;

      if (memberResponse != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainDashboard()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const JoinOrganizationScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error checking organization membership: $e');
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const JoinOrganizationScreen()),
      );
    }
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 2));
    await _checkMembershipAndNavigate();
    
    if (mounted) {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        
        final AuthChangeEvent event = data.event;
        
        if (event == AuthChangeEvent.signedOut || event == AuthChangeEvent.tokenRefreshed) {
          _checkMembershipAndNavigate();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Splash animation
            Lottie.asset(
              'assets/lottie/clock_time.json',
              width: 200,
              height: 200,
              fit: BoxFit.contain,
            ),
            
            const SizedBox(height: 24),
            
            // App name
            const Text(
              'ABSENSI',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}