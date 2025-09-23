// screens/user_dashboard.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart' hide Position;
import '../services/attendance_service.dart';
import '../services/camera_service.dart';
import '../pages/camera_selfie_screen.dart';
import 'login.dart';
import 'attendance_history.dart';
import '../helpers/timezone_helper.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = false;
  Position? _currentPosition;

  // Data from services
  UserProfile? _userProfile;
  OrganizationMember? _organizationMember;
  List<AttendanceRecord> _todayAttendanceRecords = [];
  List<AttendanceRecord> _recentAttendanceRecords = [];
  MemberSchedule? _currentSchedule;
  AttendanceDevice? _attendanceDevice;

  // Theme color
  static const Color primaryColor = Color(0xFF009688);

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserData();
  }

  Future<void> _initializeServices() async {
    try {
      await CameraService.initializeCameras();
    } catch (e) {
      print('Error initializing services: $e');
      _showSnackBar('Error inisialisasi layanan: $e', isError: true);
    }
  }

  Future<void> _loadUserData() async {
  setState(() {
    _isLoading = true;
  });

  try {
    print('=== Starting _loadUserData ===');
    
    _userProfile = await _attendanceService.loadUserProfile();
    print('User profile loaded: ${_userProfile?.fullName}');
    
    if (_userProfile != null) {
      _organizationMember = await _attendanceService.loadOrganizationMember();
      print('Organization member loaded: ${_organizationMember?.id}');
      
      if (_organizationMember != null) {
        await _loadOrganizationData();
        print('Organization data loaded');
      } else {
        print('⚠️ No organization member found');
      }
    } else {
      print('❌ User profile is null');
    }
  } catch (e) {
    print('❌ Error in _loadUserData: $e');
    _showSnackBar('Error loading user data: $e', isError: true);
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}


  Future<void> _loadOrganizationData() async {
    if (_organizationMember == null) return;

    try {
      final futures = await Future.wait([
        _attendanceService.loadAttendanceDevice(_organizationMember!.organizationId),
        _attendanceService.loadTodayAttendanceRecords(_organizationMember!.id),
        _attendanceService.loadRecentAttendanceRecords(_organizationMember!.id),
        _attendanceService.loadCurrentSchedule(_organizationMember!.id),
        _attendanceService.getCurrentLocation(),
      ]);

      setState(() {
        _attendanceDevice = futures[0] as AttendanceDevice?;
        _todayAttendanceRecords = futures[1] as List<AttendanceRecord>;
        _recentAttendanceRecords = futures[2] as List<AttendanceRecord>;
        _currentSchedule = futures[3] as MemberSchedule?;
        _currentPosition = futures[4] as Position?;
      });
    } catch (e) {
      print('Error loading organization data: $e');
      if (e.toString().contains('location')) {
        _showSnackBar('Gagal mendapatkan lokasi. Pastikan GPS aktif.', isError: true);
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await _attendanceService.getCurrentLocation();
      setState(() {});
    } catch (e) {
      _showSnackBar('Gagal mendapatkan lokasi: $e', isError: true);
    }
  }

  bool _isWithinRadius() {
    if (_currentPosition == null || _attendanceDevice == null) return false;
    return _attendanceService.isWithinRadius(_currentPosition!, _attendanceDevice!);
  }

  bool _canCheckIn() {
    return _todayAttendanceRecords
        .where((record) => record.hasCheckedIn)
        .isEmpty;
  }

  bool _canCheckOut() {
    final hasCheckedIn = _todayAttendanceRecords
        .where((record) => record.hasCheckedIn)
        .isNotEmpty;
    final hasCheckedOut = _todayAttendanceRecords
        .where((record) => record.hasCheckedOut)
        .isNotEmpty;

    return hasCheckedIn && !hasCheckedOut;
  }

  Future<String?> _takeSelfie() async {
    if (!CameraService.isInitialized) {
      _showSnackBar('Kamera tidak tersedia', isError: true);
      return null;
    }

    final hasPermission = await CameraService.requestCameraPermission();
    if (!hasPermission) {
      _showSnackBar('Izin kamera diperlukan', isError: true);
      return null;
    }

    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => CameraSelfieScreen(cameras: CameraService.cameras),
        ),
      );
      return result;
    } catch (e) {
      _showSnackBar('Gagal mengambil foto: $e', isError: true);
      return null;
    }
  }

  Future<void> _performAttendance(String type) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Validation checks
      if (_organizationMember == null) {
        _showSnackBar(
          'Data member organisasi tidak ditemukan. Hubungi admin.',
          isError: true,
        );
        return;
      }

      if (_attendanceDevice == null || !_attendanceDevice!.hasValidCoordinates) {
        _showSnackBar(
          'Lokasi kantor belum dikonfigurasi. Hubungi administrator.',
          isError: true,
        );
        return;
      }

      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Lokasi tidak ditemukan. Pastikan GPS aktif.', isError: true);
        return;
      }

      if (!_isWithinRadius()) {
        final distance = _attendanceService.calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _attendanceDevice!.latitude,
          _attendanceDevice!.longitude,
        );
        
        _showSnackBar(
          distance != null
              ? 'Anda berada di luar radius kantor (${distance.toStringAsFixed(0)}m dari ${_attendanceDevice!.radiusMeters.toInt()}m)'
              : 'Tidak dapat menghitung jarak ke kantor',
          isError: true,
        );
        return;
      }

      // Take selfie
      String? imagePath = await _takeSelfie();
      if (imagePath == null) {
        _showSnackBar('Foto diperlukan untuk absensi', isError: true);
        return;
      }

      // Upload photo
      String? photoUrl = await _attendanceService.uploadPhoto(imagePath);
      if (photoUrl == null) {
        _showSnackBar('Gagal upload foto', isError: true);
        return;
      }

      // Perform attendance
      final success = await _attendanceService.performAttendance(
        type: type,
        organizationMemberId: _organizationMember!.id,
        currentPosition: _currentPosition!,
        photoUrl: photoUrl,
        device: _attendanceDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
      );

      if (success) {
        await _showSuccessAttendancePopup(type);
        await _loadOrganizationData();
      }

      // Clean up temporary file
      try {
        await File(imagePath).delete();
      } catch (e) {
        print('Gagal menghapus file sementara: $e');
      }

    } catch (e) {
      print('Error performing attendance: $e');
      _showSnackBar('Gagal melakukan absensi: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showSuccessAttendancePopup(String type) async {
    final isCheckIn = type == 'check_in';
    final jakartaTime = TimezoneHelper.nowInJakarta();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isCheckIn ? primaryColor : Colors.orange,
                  isCheckIn
                      ? primaryColor.withOpacity(0.8)
                      : Colors.orange.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with animation
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 800),
                        tween: Tween(begin: 0.0, end: 1.0),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isCheckIn ? Icons.login : Icons.logout,
                                size: 40,
                                color: isCheckIn ? primaryColor : Colors.orange,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${isCheckIn ? 'Check In' : 'Check Out'} Berhasil!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isCheckIn
                            ? 'Selamat bekerja hari ini!'
                            : 'Terima kasih atas kerja keras Anda!',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Details container
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        icon: Icons.access_time,
                        title: 'Waktu',
                        value: TimezoneHelper.formatJakartaTime(jakartaTime, 'HH:mm:ss'),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.calendar_today,
                        title: 'Tanggal',
                        value: TimezoneHelper.formatJakartaTime(jakartaTime, 'EEEE, dd MMMM yyyy'),
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.location_on,
                        title: 'Lokasi',
                        value: _attendanceDevice?.location ??
                               _organizationMember?.organization?.name ??
                               'Kantor',
                        subtitle: 'Dalam radius kantor ✓',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // OK Button
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: isCheckIn ? primaryColor : Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'OK, Mengerti',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: primaryColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _attendanceService.signOut();
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const Login()),
                );
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = _userProfile?.fullName ?? user?.email ?? 'User';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          "Dashboard - ${_organizationMember?.organization?.name ?? 'PT Universal Big Data'}",
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadUserData,
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
      body: _organizationMember == null
          ? _buildNotRegisteredView()
          : _buildMainContent(displayName, user),
    );
  }

  Widget _buildNotRegisteredView() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business, size: 64, color: primaryColor),
            const SizedBox(height: 16),
            const Text(
              'Belum Terdaftar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Anda belum terdaftar sebagai member organisasi. Sistem akan mencoba mendaftarkan Anda secara otomatis atau hubungi admin untuk bantuan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _loadUserData,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isLoading ? 'Memproses...' : 'Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(String displayName, User? user) {
    return RefreshIndicator(
      onRefresh: _loadUserData,
      color: primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildUserHeader(displayName, user),
            const SizedBox(height: 20),
            _buildLocationInfo(),
            const SizedBox(height: 16),
            _buildAttendanceStats(),
            const SizedBox(height: 20),
            _buildAttendanceButtonsCard(),
            _buildRecentAttendance(),
            _buildScheduleInfo(),
            _buildDeviceInfo(),
            _buildAttendanceRequirements(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader(String displayName, User? user) {
    return Container(
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
            backgroundImage: _userProfile?.profilePhotoUrl != null
                ? NetworkImage(_userProfile!.profilePhotoUrl!)
                : null,
            child: _userProfile?.profilePhotoUrl == null
                ? Icon(Icons.person, size: 50, color: primaryColor)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (_organizationMember != null) ...[
            const SizedBox(height: 4),
            Text(
              'ID: ${_organizationMember!.employeeId ?? 'N/A'}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '${_organizationMember!.department?.name ?? ''} - ${_organizationMember!.position?.title ?? ''}'
                  .replaceAll(' - ', ''),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            TimezoneHelper.formatJakartaTime(
              TimezoneHelper.nowInJakarta(),
              'EEEE, dd MMMM yyyy',
            ),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
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

    if (_attendanceDevice == null || !_attendanceDevice!.hasValidCoordinates) {
      return Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red.shade600, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lokasi kantor belum dikonfigurasi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Hubungi administrator untuk mengatur koordinat kantor pada perangkat absensi',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    double? distance = _attendanceService.calculateDistance(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _attendanceDevice!.latitude,
      _attendanceDevice!.longitude,
    );

    bool withinRadius = distance != null && distance <= _attendanceDevice!.radiusMeters;
    String locationName = _attendanceDevice!.location ??
        _organizationMember?.organization?.name ??
        'Kantor';

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: withinRadius
            ? primaryColor.withOpacity(0.1)
            : Colors.red.shade50,
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
                  withinRadius
                      ? 'Di dalam radius kantor'
                      : 'Di luar radius kantor',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: withinRadius ? primaryColor : Colors.red.shade800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  distance != null
                      ? 'Jarak: ${distance.toStringAsFixed(0)}m dari $locationName'
                      : 'Tidak dapat menghitung jarak',
                  style: TextStyle(
                    fontSize: 12,
                    color: withinRadius
                        ? primaryColor.withOpacity(0.8)
                        : Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Radius: ${_attendanceDevice!.radiusMeters.toInt()}m',
                  style: TextStyle(
                    fontSize: 11,
                    color: withinRadius
                        ? primaryColor.withOpacity(0.7)
                        : Colors.red.shade500,
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
    int checkInCount = 0;
    int checkOutCount = 0;
    String status = 'BELUM MASUK';

    if (_todayAttendanceRecords.isNotEmpty) {
      final record = _todayAttendanceRecords.first;
      if (record.hasCheckedIn) {
        checkInCount = 1;
        status = 'MASUK';
      }
      if (record.hasCheckedOut) {
        checkOutCount = 1;
        status = 'KELUAR';
      }
    }

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
                  '$checkInCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white30),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Check Out',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '$checkOutCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white30),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Status',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  status,
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

  Widget _buildAttendanceButtonsCard() {
    return Container(
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAttendanceButton('check_in', Icons.login, primaryColor),
          _buildAttendanceButton('check_out', Icons.logout, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildAttendanceButton(String type, IconData icon, Color color) {
    String label = type == 'check_in' ? 'Check In' : 'Check Out';
    bool canAttend = !_isLoading &&
        _currentPosition != null &&
        _attendanceDevice != null &&
        _attendanceDevice!.hasValidCoordinates &&
        _isWithinRadius() &&
        (type == 'check_in' ? _canCheckIn() : _canCheckOut());

    return Container(
      width: double.infinity,
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 8),
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
    if (_recentAttendanceRecords.isEmpty) {
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
          child: Text('Belum ada riwayat absensi', style: TextStyle(color: Colors.grey)),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AttendanceHistoryPage()),
                    );
                  },
                  icon: Icon(Icons.arrow_forward, size: 16, color: primaryColor),
                  label: Text('Lihat Semua', style: TextStyle(color: primaryColor, fontSize: 12)),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentAttendanceRecords.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = _recentAttendanceRecords[index];
              final hasCheckIn = record.hasCheckedIn;
              final hasCheckOut = record.hasCheckedOut;
              final attendanceDate = DateTime.parse(record.attendanceDate);

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: hasCheckIn && hasCheckOut
                      ? primaryColor
                      : hasCheckIn
                      ? Colors.orange
                      : Colors.grey,
                  child: Icon(
                    hasCheckIn && hasCheckOut
                        ? Icons.check_circle
                        : hasCheckIn
                        ? Icons.access_time
                        : Icons.pending,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                title: Text(
                  record.status.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(attendanceDate),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (hasCheckIn && hasCheckOut)
                      Text(
                        '${_formatTime(record.actualCheckIn)} - ${_formatTime(record.actualCheckOut)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      )
                    else if (hasCheckIn)
                      Text(
                        'Masuk: ${_formatTime(record.actualCheckIn)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                  ],
                ),
                trailing: Icon(
                  record.status == 'present' ? Icons.check_circle : Icons.warning,
                  color: record.status == 'present' ? primaryColor : Colors.orange,
                  size: 20,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    return DateFormat('HH:mm').format(dateTime);
  }

  Widget _buildScheduleInfo() {
    if (_currentSchedule == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Jadwal Kerja',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_currentSchedule!.shift != null) ...[
            Text('Shift: ${_currentSchedule!.shift!.name}', style: const TextStyle(fontSize: 12)),
            Text(
              'Waktu: ${_currentSchedule!.shift!.startTime} - ${_currentSchedule!.shift!.endTime}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_currentSchedule!.workSchedule != null)
            Text(
              'Jadwal: ${_currentSchedule!.workSchedule!.name}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo() {
    if (_attendanceDevice == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices_other, color: primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Informasi Device',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('• Device: ${_attendanceDevice!.deviceName}', style: const TextStyle(fontSize: 12)),
          Text('• Kode: ${_attendanceDevice!.deviceCode}', style: const TextStyle(fontSize: 12)),
          if (_attendanceDevice!.location != null)
            Text('• Lokasi: ${_attendanceDevice!.location}', style: const TextStyle(fontSize: 12)),
          if (_attendanceDevice!.hasValidCoordinates)
            Text(
              '• Koordinat: ${_attendanceDevice!.latitude!.toStringAsFixed(6)}, ${_attendanceDevice!.longitude!.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            )
          else
            const Text(
              '• Koordinat: Belum dikonfigurasi',
              style: TextStyle(fontSize: 11, color: Colors.red),
            ),
          Text(
            '• Radius: ${_attendanceDevice!.radiusMeters.toInt()}m',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRequirements() {
    return Container(
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
            '• Berada dalam radius kantor yang ditentukan\n• Siapkan kamera untuk foto selfie\n• Pastikan lokasi GPS aktif\n• Check in hanya bisa dilakukan sekali per hari\n• Check out hanya bisa setelah check in',
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}