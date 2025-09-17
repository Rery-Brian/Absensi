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
    url: 'https://gzicdonompgsowiermqj.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd6aWNkb25vbXBnc293aWVybXFqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5OTMwNjcsImV4cCI6MjA3MzU2OTA2N30.qVMAeTGed6Xc43Er_UvbyBxJrN4l5R46mlbJpq4U25I',
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