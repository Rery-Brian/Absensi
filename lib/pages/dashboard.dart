import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final supabase = Supabase.instance.client;

  Future<void> _absen() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('attendance').insert({
        'user_id': user.id,
        'status': 'present',
        'latitude': 0.0, // nanti diganti lokasi asli
        'longitude': 0.0,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Absensi berhasil")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal absen: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("Dashboard - ${user?.email ?? 'User'}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          )
        ],
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _absen,
          child: const Text("Absen Sekarang"),
        ),
      ),
    );
  }
}
