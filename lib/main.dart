import 'package:absensiwajah/pages/login.dart';
import 'package:absensiwajah/helpers/timezone_helper.dart'; // Tambahkan import ini
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone sebelum Supabase
  TimezoneHelper.initialize();

  await Supabase.initialize(
    url: 'https://mgidfodeiedfyaczqjng.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1naWRmb2RlaWVkZnlhY3pxam5nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTgyNTEyNjcsImV4cCI6MjA3MzgyNzI2N30.yAhh8dXILji3OZqXdBHaZJmoJ4z316U-jfCNhMDi7c8',
  );

  await initializeDateFormatting('id_ID', null);
  runApp(MyApp());
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
      home: Login(),
    );
  }
}