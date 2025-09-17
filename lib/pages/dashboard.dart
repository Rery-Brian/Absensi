import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'attendance_history.dart'; // Import halaman riwayat

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  Position? _currentPosition;
  late List<CameraDescription> _cameras;
  bool _cameraInitialized = false;
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _todayAttendance = [];
  List<Map<String, dynamic>> _recentAttendance = [];

  // Theme color
  static const Color primaryColor = Color(0xFF009688);
  
  // Koordinat PT Universal Big Data Malang
  static const double officeLatitude = -7.9207989;
  static const double officeLongitude = 112.6187022;
  static const double radiusInMeters = 100.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getCurrentLocation();
    _loadUserProfile();
    _loadTodayAttendance();
    _loadRecentAttendance();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      setState(() {
        _cameraInitialized = true;
      });
    } catch (e) {
      print('Error initializing camera: $e');
      _showSnackBar('Error inisialisasi kamera: $e', isError: true);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single();
        
        setState(() {
          _userProfile = response;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  Future<void> _loadTodayAttendance() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final response = await supabase
            .from('attendance')
            .select()
            .eq('user_id', user.id)
            .gte('created_at', '${today}T00:00:00')
            .lt('created_at', '${today}T23:59:59')
            .order('created_at');
        
        setState(() {
          _todayAttendance = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error loading today attendance: $e');
    }
  }

  Future<void> _loadRecentAttendance() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('attendance')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(5);
        
        setState(() {
          _recentAttendance = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error loading recent attendance: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Layanan lokasi tidak aktif', isError: true);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Izin lokasi ditolak', isError: true);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Lokasi ditolak permanen, buka setelan', isError: true);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      _showSnackBar('Gagal mendapatkan lokasi: $e', isError: true);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  bool _isWithinRadius() {
    if (_currentPosition == null) return false;
    double distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      officeLatitude,
      officeLongitude,
    );
    return distance <= radiusInMeters;
  }

  bool _canCheckIn() {
    return _todayAttendance.where((a) => a['type'] == 'check_in').isEmpty;
  }

  bool _canCheckOut() {
    final checkIns = _todayAttendance.where((a) => a['type'] == 'check_in');
    final checkOuts = _todayAttendance.where((a) => a['type'] == 'check_out');
    return checkIns.isNotEmpty && checkOuts.length < checkIns.length;
  }

  Future<String?> _takeSelfie() async {
    if (!_cameraInitialized || _cameras.isEmpty) {
      _showSnackBar('Kamera tidak tersedia', isError: true);
      return null;
    }

    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      _showSnackBar('Izin kamera diperlukan', isError: true);
      return null;
    }

    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => CameraSelfieScreen(cameras: _cameras),
        ),
      );
      return result;
    } catch (e) {
      _showSnackBar('Gagal mengambil foto: $e', isError: true);
      return null;
    }
  }

  Future<String?> _uploadPhoto(String imagePath) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;

      final fileName = '${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(imagePath);
      
      await supabase.storage
          .from('attendance_photos')
          .upload(fileName, file);

      final publicUrl = supabase.storage
          .from('attendance_photos')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      _showSnackBar('Gagal upload foto: $e', isError: true);
      return null;
    }
  }

  Future<void> _performAttendance(String type) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnackBar('User tidak ditemukan', isError: true);
        return;
      }

      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Lokasi tidak ditemukan', isError: true);
        return;
      }

      bool withinRadius = _isWithinRadius();
      double distance = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        officeLatitude,
        officeLongitude,
      );

      if (!withinRadius) {
        _showSnackBar(
          'Anda berada di luar radius kantor (${distance.toStringAsFixed(0)}m)',
          isError: true,
        );
        return;
      }

      String? imagePath = await _takeSelfie();
      if (imagePath == null) {
        _showSnackBar('Foto diperlukan untuk absensi', isError: true);
        return;
      }

      String? photoUrl = await _uploadPhoto(imagePath);
      if (photoUrl == null) {
        _showSnackBar('Gagal upload foto', isError: true);
        return;
      }

      await supabase.from('attendance').insert({
        'user_id': user.id,
        'type': type,
        'photo_url': photoUrl,
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'is_within_radius': withinRadius,
      });

      _showSnackBar('${type == "check_in" ? "Check In" : "Check Out"} berhasil!');

      // Refresh data
      await _loadTodayAttendance();
      await _loadRecentAttendance();

      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Gagal menghapus file sementara: $e');
      }
    } catch (e) {
      _showSnackBar('Gagal melakukan absensi: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showLogoutConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.logout, color: primaryColor),
              const SizedBox(width: 8),
              const Text('Konfirmasi Logout'),
            ],
          ),
          content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                Navigator.of(context).pop();
                await supabase.auth.signOut();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Widget _buildLocationInfo() {
    if (_currentPosition == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.location_searching, color: Colors.orange.shade600),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Mencari lokasi...',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ],
        ),
      );
    }

    double distance = _calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      officeLatitude,
      officeLongitude,
    );
    
    bool withinRadius = distance <= radiusInMeters;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: withinRadius ? primaryColor.withOpacity(0.1) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: withinRadius ? primaryColor : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            withinRadius ? Icons.location_on : Icons.location_off,
            color: withinRadius ? primaryColor : Colors.red.shade600,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  withinRadius ? 'Di dalam radius kantor' : 'Di luar radius kantor',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: withinRadius ? primaryColor : Colors.red.shade800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jarak: ${distance.toStringAsFixed(0)}m dari PT Universal Big Data',
                  style: TextStyle(
                    fontSize: 12,
                    color: withinRadius ? primaryColor.withOpacity(0.8) : Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceStats() {
    final checkIns = _todayAttendance.where((a) => a['type'] == 'check_in').length;
    final checkOuts = _todayAttendance.where((a) => a['type'] == 'check_out').length;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Check In',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '$checkIns',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white30,
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Check Out',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '$checkOuts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white30,
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Status',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  checkIns > checkOuts ? 'MASUK' : 'KELUAR',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceButton(String type, IconData icon, Color color) {
    String label = type == 'check_in' ? 'Check In' : 'Check Out';
    bool canAttend = !_isLoading && 
        _currentPosition != null && 
        _isWithinRadius() &&
        (type == 'check_in' ? _canCheckIn() : _canCheckOut());

    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: canAttend ? () => _performAttendance(type) : null,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon, size: 24),
        label: Text(
          _isLoading ? 'Memproses...' : label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: canAttend ? color : Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: canAttend ? 4 : 0,
        ),
      ),
    );
  }

  Widget _buildRecentAttendance() {
    if (_recentAttendance.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'Belum ada riwayat absensi',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.history, color: primaryColor),
                const SizedBox(width: 8),
                const Text(
                  'Riwayat Absensi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AttendanceHistoryPage(),
                      ),
                    );
                  },
                  icon: Icon(Icons.arrow_forward, size: 16, color: primaryColor),
                  label: Text(
                    'Lihat Semua',
                    style: TextStyle(color: primaryColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentAttendance.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final attendance = _recentAttendance[index];
              final isCheckIn = attendance['type'] == 'check_in';
              final date = DateTime.parse(attendance['created_at']);
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isCheckIn ? primaryColor : Colors.orange,
                  child: Icon(
                    isCheckIn ? Icons.login : Icons.logout,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                title: Text(
                  isCheckIn ? 'Check In' : 'Check Out',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  DateFormat('dd MMM yyyy, HH:mm WIB', 'id_ID').format(date),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Icon(
                  attendance['is_within_radius'] ? Icons.check_circle : Icons.error,
                  color: attendance['is_within_radius'] ? primaryColor : Colors.red,
                  size: 20,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Dashboard - PT Universal Big Data"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _getCurrentLocation();
              await _loadTodayAttendance();
              await _loadRecentAttendance();
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Riwayat Absensi',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AttendanceHistoryPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _showLogoutConfirmation,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _getCurrentLocation();
          await _loadUserProfile();
          await _loadTodayAttendance();
          await _loadRecentAttendance();
        },
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header user
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.person,
                        size: 50,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _userProfile?['name'] ?? user?.email ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildLocationInfo(),

              const SizedBox(height: 16),
              
              _buildAttendanceStats(),

              const SizedBox(height: 20),

              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time, color: primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Absensi Hari Ini',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildAttendanceButton('check_in', Icons.login, primaryColor),
                    _buildAttendanceButton('check_out', Icons.logout, Colors.orange),
                  ],
                ),
              ),

              _buildRecentAttendance(),

              const SizedBox(height: 20),

              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: primaryColor, size: 30),
                    const SizedBox(height: 8),
                    Text(
                      'Syarat Absensi:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• Berada dalam radius 100 meter dari kantor\n• Siapkan kamera untuk foto selfie\n• Pastikan lokasi GPS aktif\n• Check in hanya bisa dilakukan sekali per hari\n• Check out hanya bisa setelah check in\n\nLokasi: Ruko Modern Kav A16-A17, Jl Loncat Indah, Tasikmadu, Lowokwaru, Malang',
                      textAlign: TextAlign.left,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraSelfieScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraSelfieScreen({super.key, required this.cameras});

  @override
  State<CameraSelfieScreen> createState() => _CameraSelfieScreenState();
}

class _CameraSelfieScreenState extends State<CameraSelfieScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;
  static const Color primaryColor = Color(0xFF009688);

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      CameraDescription camera = widget.cameras.first;
      for (var cam in widget.cameras) {
        if (cam.lensDirection == CameraLensDirection.front) {
          camera = cam;
          break;
        }
      }

      _controller = CameraController(camera, ResolutionPreset.medium);
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing selfie camera: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      Navigator.pop(context, photo.path);
    } catch (e) {
      print('Error take picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ambil Selfie untuk Absensi'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_controller!)),
          
          // Overlay guide
          Positioned(
            top: 80,
            left: 30,
            right: 30,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.face, color: primaryColor, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Posisikan wajah Anda di dalam frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'untuk absensi PT Universal Big Data',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Face detection frame
          Positioned(
            top: 200,
            left: 50,
            right: 50,
            child: Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: primaryColor, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: primaryColor.withOpacity(0.5), width: 2),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          
          // Camera button
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(Icons.close, size: 30, color: Colors.white),
                  ),
                ),
                
                // Take photo button
                GestureDetector(
                  onTap: _isCapturing ? null : _takePicture,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isCapturing ? Colors.grey : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: primaryColor, width: 4),
                    ),
                    child: _isCapturing
                        ? CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          )
                        : Icon(Icons.camera_alt, size: 40, color: primaryColor),
                  ),
                ),
                
                // Switch camera button (if available)
                GestureDetector(
                  onTap: widget.cameras.length > 1 ? () {
                    // Switch camera logic could be implemented here
                  } : null,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: widget.cameras.length > 1 
                          ? primaryColor.withOpacity(0.8) 
                          : Colors.grey.withOpacity(0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(Icons.flip_camera_ios, size: 30, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          
          // Instructions at bottom
          Positioned(
            bottom: 140,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pastikan wajah terlihat jelas dan dalam pencahayaan yang baik',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
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