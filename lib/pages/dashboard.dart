import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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

  // Koordinat asli PT Universal Big Data Malang
  // Ruko Modern Kav A16-A17, Jl Loncat Indah, Tasikmadu, Lowokwaru, Malang
  static const double officeLatitude = -7.9207989;
  static const double officeLongitude = 112.6187022;
  static const double radiusInMeters = 100.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _getCurrentLocation();
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
    // gunakan util dari geolocator yang sederhana
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

  Future<String?> _takeSelfie() async {
    if (!_cameraInitialized || _cameras.isEmpty) {
      _showSnackBar('Kamera tidak tersedia', isError: true);
      return null;
    }

    // minta izin kamera
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

      // update lokasi
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

      // opsional: hapus file lokal buat bersihin storage sementara
      try {
        await File(imagePath).delete();
      } catch (e) {
        // ignore
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

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
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
        color: withinRadius ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: withinRadius ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                withinRadius ? Icons.location_on : Icons.location_off,
                color: withinRadius ? Colors.green.shade600 : Colors.red.shade600,
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
                        color: withinRadius ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ),
                    Text(
                      'Jarak: ${distance.toStringAsFixed(0)}m dari PT Universal Big Data',
                      style: TextStyle(
                        fontSize: 12,
                        color: withinRadius ? Colors.green.shade600 : Colors.red.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceButton(String type, IconData icon, Color color) {
    String label = type == 'check_in' ? 'Check In' : 'Check Out';
    bool canAttend = !_isLoading && _currentPosition != null && _isWithinRadius();

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

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Dashboard - PT Universal Big Data"),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getCurrentLocation,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (!mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header user
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
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
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.email ?? 'User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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
                  const SizedBox(height: 8),
                  Text(
                    'PT Universal Big Data',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildLocationInfo(),

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
                  const Text(
                    'Absensi Hari Ini',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _buildAttendanceButton('check_in', Icons.login, Colors.green),
                  _buildAttendanceButton('check_out', Icons.logout, Colors.orange),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade600, size: 30),
                  const SizedBox(height: 8),
                  const Text(
                    'Syarat Absensi:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Berada dalam radius 50 meter dari kantor\n• Siapkan kamera untuk foto selfie\n• Pastikan lokasi GPS aktif\n\nLokasi: Ruko Modern Kav A16-A17, Jl Loncat Indah, Tasikmadu, Lowokwaru, Malang',
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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // pilih kamera depan bila ada
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
        SnackBar(content: Text('Gagal mengambil foto: $e')),
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
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
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
          
          // Overlay guide untuk selfie
          Positioned(
            top: 100,
            left: 50,
            right: 50,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Posisikan wajah Anda di dalam frame\nuntuk absensi PT Universal Big Data',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isCapturing ? null : _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isCapturing ? Colors.grey : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: _isCapturing
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt, size: 40, color: Colors.black),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}