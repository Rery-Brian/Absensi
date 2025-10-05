  import 'package:absensiwajah/pages/login.dart';
  import 'package:absensiwajah/pages/main_dashboard.dart'; // pakai MainDashboard
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
      final session = Supabase.instance.client.auth.currentSession;

      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Absensi Wajah',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        // 🔑 Kalau sudah login -> MainDashboard, kalau belum -> Login
        home: session != null ? const MainDashboard() : const Login(),
      );
    }
  }