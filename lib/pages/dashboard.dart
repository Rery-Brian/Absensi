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

  // Timeline data structure for multiple check-ins/check-outs
  List<TimelineItem> _timelineItems = [];

  // Theme colors
  static const Color primaryColor = Color(0xFF6366F1); // Purple
  static const Color secondaryColor = Color(0xFFEC4899); // Pink
  static const Color backgroundColor = Color(0xFF1F2937); // Dark gray

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
          _buildTimelineItems();
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

  void _buildTimelineItems() {
    _timelineItems.clear();
    
    final now = DateTime.now();
    final currentTime = TimeOfDay.now();
    
    // Define schedule based on UBIG working hours with prayer breaks
    final schedules = [
      ScheduleItem(
        time: '09:38',
        label: 'Check In',
        type: TimelineItemType.checkIn,
        subtitle: 'Morning arrival',
      ),
      ScheduleItem(
        time: '12:00',
        label: 'Dzuhur Break',
        type: TimelineItemType.breakOut,
        subtitle: 'Prayer & lunch break',
      ),
      ScheduleItem(
        time: '13:00',
        label: 'After Break',
        type: TimelineItemType.breakIn,
        subtitle: 'Resume work',
      ),
      ScheduleItem(
        time: '15:00',
        label: 'Ashar Break',
        type: TimelineItemType.breakOut,
        subtitle: 'Prayer break',
      ),
      ScheduleItem(
        time: '15:30',
        label: 'After Break',
        type: TimelineItemType.breakIn,
        subtitle: 'Resume work',
      ),
      ScheduleItem(
        time: '17:00',
        label: 'Check Out',
        type: TimelineItemType.checkOut,
        subtitle: 'End of work day',
      ),
    ];

    for (var schedule in schedules) {
      final scheduleTime = _parseTime(schedule.time);
      TimelineStatus status;
      
      // Check if this schedule item has been completed today
      bool isCompleted = _isScheduleCompleted(schedule, scheduleTime);
      bool isActive = _isScheduleActive(schedule, scheduleTime, currentTime);
      
      if (isCompleted) {
        status = TimelineStatus.completed;
      } else if (isActive) {
        status = TimelineStatus.active;
      } else {
        status = TimelineStatus.upcoming;
      }

      _timelineItems.add(TimelineItem(
        time: schedule.time,
        label: schedule.label,
        subtitle: schedule.subtitle,
        type: schedule.type,
        status: status,
      ));
    }
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  bool _isScheduleCompleted(ScheduleItem schedule, TimeOfDay scheduleTime) {
    // This would check against actual attendance records
    // For now, simplified logic based on current time
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final scheduleMinutes = scheduleTime.hour * 60 + scheduleTime.minute;
    
    // If current time is past schedule time, consider it completed
    // In real implementation, check against attendance records
    return nowMinutes > scheduleMinutes;
  }

  bool _isScheduleActive(ScheduleItem schedule, TimeOfDay scheduleTime, TimeOfDay currentTime) {
    final nowMinutes = currentTime.hour * 60 + currentTime.minute;
    final scheduleMinutes = scheduleTime.hour * 60 + scheduleTime.minute;
    
    // Active if within 30 minutes window
    return (nowMinutes >= scheduleMinutes - 15) && (nowMinutes <= scheduleMinutes + 15);
  }

  int _getPresenceDays() {
    // Calculate from recent attendance records
    return _recentAttendanceRecords.where((r) => r.status == 'present').length;
  }

  int _getAbsenceDays() {
    // Calculate from recent attendance records
    return _recentAttendanceRecords.where((r) => r.status == 'absent').length;
  }

  String _getLateness() {
    // Calculate total lateness from records
    return '1.5h'; // Placeholder
  }

  Future<void> _performAttendance(TimelineItemType type) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Validation checks
      if (_organizationMember == null) {
        _showSnackBar('Data member organisasi tidak ditemukan. Hubungi admin.', isError: true);
        return;
      }

      if (_attendanceDevice == null || !_attendanceDevice!.hasValidCoordinates) {
        _showSnackBar('Lokasi kantor belum dikonfigurasi. Hubungi administrator.', isError: true);
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

      // Convert timeline type to string
      String attendanceType = _getAttendanceTypeString(type);

      // Perform attendance
      final success = await _attendanceService.performAttendance(
        type: attendanceType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: _currentPosition!,
        photoUrl: photoUrl,
        device: _attendanceDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
      );

      if (success) {
        await _showSuccessAttendancePopup(attendanceType);
        await _loadOrganizationData();
        _buildTimelineItems();
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

  String _getAttendanceTypeString(TimelineItemType type) {
    switch (type) {
      case TimelineItemType.checkIn:
        return 'check_in';
      case TimelineItemType.checkOut:
        return 'check_out';
      case TimelineItemType.breakOut:
        return 'break_out';
      case TimelineItemType.breakIn:
        return 'break_in';
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

  Future<void> _showSuccessAttendancePopup(String type) async {
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
                colors: [primaryColor, primaryColor.withOpacity(0.8)],
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
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  child: Column(
                    children: [
                      Container(
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
                          Icons.check_circle,
                          size: 40,
                          color: primaryColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Absensi Berhasil!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  Future<void> _showLogoutConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Konfirmasi Logout'),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = _userProfile?.fullName ?? user?.email?.split('@')[0] ?? 'User';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _organizationMember == null
          ? _buildNotRegisteredView()
          : _buildMainContent(displayName),
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
              'Anda belum terdaftar sebagai member organisasi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _loadUserData,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(_isLoading ? 'Loading...' : 'Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(String displayName) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(displayName),
          _buildOverviewCard(),
          _buildTimelineCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader(String displayName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                Icons.apps,
                color: primaryColor,
                size: 28,
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AttendanceHistoryPage()),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: _showLogoutConfirmation,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.orange.shade400,
                backgroundImage: _userProfile?.profilePhotoUrl != null
                    ? NetworkImage(_userProfile!.profilePhotoUrl!)
                    : null,
                child: _userProfile?.profilePhotoUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 28)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Morning, $displayName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      "Let's be productive today!",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
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

  Widget _buildOverviewCard() {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Text(
                    DateFormat('MMM yyyy').format(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Presence',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getPresenceDays()}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Absence',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getAbsenceDays()}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'Lateness',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getLateness(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              DateFormat('EEEE dd MMMM yyyy').format(DateTime.now()),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          ..._timelineItems.map((item) => _buildTimelineItem(item)),
          const Divider(height: 30),
          _buildOvertimeItem(),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(TimelineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getStatusColor(item.status),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getStatusIcon(item.type),
              color: item.status == TimelineStatus.active ? Colors.white : 
                     item.status == TimelineStatus.completed ? Colors.white : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.time,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    _buildActionButton(item),
                  ],
                ),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(TimelineItem item) {
    if (item.status == TimelineStatus.completed && item.type == TimelineItemType.checkIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Last Check-in',
          style: TextStyle(
            fontSize: 12,
            color: Colors.orange.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    
    if (item.status == TimelineStatus.active) {
      return ElevatedButton.icon(
        onPressed: () => _performAttendance(item.type),
        icon: Icon(_getStatusIcon(item.type), size: 16),
        label: Text(item.label),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    
    if (item.type == TimelineItemType.checkOut) {
      return ElevatedButton.icon(
        onPressed: item.status == TimelineStatus.upcoming ? null : () => _performAttendance(item.type),
        icon: const Icon(Icons.logout, size: 16),
        label: Text(item.label),
        style: ElevatedButton.styleFrom(
          backgroundColor: item.status == TimelineStatus.upcoming ? Colors.grey.shade200 : Colors.red.shade400,
          foregroundColor: item.status == TimelineStatus.upcoming ? Colors.grey : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    
    return Text(
      item.label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildOvertimeItem() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.access_time,
            color: Colors.grey,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overtime',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                'Less 10 Plus Minimum',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(TimelineStatus status) {
    switch (status) {
      case TimelineStatus.completed:
        return Colors.green.shade400;
      case TimelineStatus.active:
        return primaryColor;
      case TimelineStatus.upcoming:
        return Colors.grey.shade200;
    }
  }

  IconData _getStatusIcon(TimelineItemType type) {
    switch (type) {
      case TimelineItemType.checkIn:
        return Icons.login;
      case TimelineItemType.checkOut:
        return Icons.logout;
      case TimelineItemType.breakOut:
        return Icons.coffee;
      case TimelineItemType.breakIn:
        return Icons.work;
    }
  }
}

// Data classes for timeline
class TimelineItem {
  final String time;
  final String label;
  final String subtitle;
  final TimelineItemType type;
  final TimelineStatus status;

  TimelineItem({
    required this.time,
    required this.label,
    required this.subtitle,
    required this.type,
    required this.status,
  });
}

class ScheduleItem {
  final String time;
  final String label;
  final TimelineItemType type;
  final String subtitle;

  ScheduleItem({
    required this.time,
    required this.label,
    required this.type,
    required this.subtitle,
  });
}

enum TimelineItemType {
  checkIn,
  checkOut,
  breakOut,
  breakIn,
}

enum TimelineStatus {
  completed,
  active,
  upcoming,
}
