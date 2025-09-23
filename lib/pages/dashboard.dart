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
import '../helpers/time_helper.dart';

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
  WorkScheduleDetails? _todayScheduleDetails;
  AttendanceStatus _currentStatus = AttendanceStatus.unknown;
  List<AttendanceAction> _availableActions = [];

  // Timeline data structure for dynamic actions
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
      TimezoneHelper.initialize();
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
          await _loadScheduleData();
          await _updateAttendanceStatus();
          _buildDynamicTimeline();
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

  Future<void> _loadScheduleData() async {
    if (_organizationMember == null || _currentSchedule?.workScheduleId == null) return;

    try {
      final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
      _todayScheduleDetails = await _attendanceService.loadWorkScheduleDetails(
        _currentSchedule!.workScheduleId!, 
        dayOfWeek
      );
      setState(() {});
    } catch (e) {
      print('Error loading schedule details: $e');
    }
  }

  Future<void> _updateAttendanceStatus() async {
    if (_organizationMember == null) return;

    try {
      _currentStatus = await _attendanceService.getCurrentAttendanceStatus(_organizationMember!.id);
      _availableActions = await _attendanceService.getAvailableActions(_organizationMember!.id);
      setState(() {});
    } catch (e) {
      print('Error updating attendance status: $e');
    }
  }

  void _buildDynamicTimeline() {
    _timelineItems.clear();
    
    // Get base schedule times
    final scheduleItems = _getScheduleItems();
    final currentTime = TimeHelper.getCurrentTime();

    // Build timeline based on schedule and current status
    for (var scheduleItem in scheduleItems) {
      final scheduleTime = TimeHelper.parseTimeString(scheduleItem.time);
      final status = _getItemStatus(scheduleItem, scheduleTime, currentTime);
      
      _timelineItems.add(TimelineItem(
        time: scheduleItem.time,
        label: scheduleItem.label,
        subtitle: scheduleItem.subtitle,
        type: scheduleItem.type,
        status: status,
        action: _getActionForItem(scheduleItem, status),
      ));
    }
  }

  List<ScheduleItem> _getScheduleItems() {
    // Use actual schedule if available, otherwise use default
    if (_todayScheduleDetails != null) {
      return [
        ScheduleItem(
          time: _todayScheduleDetails!.startTime ?? '09:00',
          label: 'Check In',
          type: AttendanceActionType.checkIn,
          subtitle: 'Start work day',
        ),
        if (_todayScheduleDetails!.breakStart != null)
          ScheduleItem(
            time: _todayScheduleDetails!.breakStart!,
            label: 'Break',
            type: AttendanceActionType.breakOut,
            subtitle: 'Take a break',
          ),
        if (_todayScheduleDetails!.breakEnd != null)
          ScheduleItem(
            time: _todayScheduleDetails!.breakEnd!,
            label: 'Resume',
            type: AttendanceActionType.breakIn,
            subtitle: 'Resume work',
          ),
        ScheduleItem(
          time: _todayScheduleDetails!.endTime ?? '17:00',
          label: 'Check Out',
          type: AttendanceActionType.checkOut,
          subtitle: 'End work day',
        ),
      ];
    }

    // Default schedule
    return [
      ScheduleItem(
        time: '09:00',
        label: 'Check In',
        type: AttendanceActionType.checkIn,
        subtitle: 'Start work day',
      ),
      ScheduleItem(
        time: '12:00',
        label: 'Break',
        type: AttendanceActionType.breakOut,
        subtitle: 'Lunch break',
      ),
      ScheduleItem(
        time: '13:00',
        label: 'Resume',
        type: AttendanceActionType.breakIn,
        subtitle: 'Resume work',
      ),
      ScheduleItem(
        time: '17:00',
        label: 'Check Out',
        type: AttendanceActionType.checkOut,
        subtitle: 'End work day',
      ),
    ];
  }

  TimelineStatus _getItemStatus(ScheduleItem item, TimeOfDay scheduleTime, TimeOfDay currentTime) {
    // Check against actual attendance records and logs
    switch (item.type) {
      case AttendanceActionType.checkIn:
        if (_todayAttendanceRecords.isNotEmpty && _todayAttendanceRecords.first.hasCheckedIn) {
          return TimelineStatus.completed;
        }
        break;
      case AttendanceActionType.checkOut:
        if (_todayAttendanceRecords.isNotEmpty && _todayAttendanceRecords.first.hasCheckedOut) {
          return TimelineStatus.completed;
        }
        break;
      case AttendanceActionType.breakOut:
      case AttendanceActionType.breakIn:
        // These would need to check logs for completion
        break;
    }

    // Check if currently active (within 30 minutes window)
    final currentMinutes = TimeHelper.timeToMinutes(currentTime);
    final scheduleMinutes = TimeHelper.timeToMinutes(scheduleTime);
    
    if (currentMinutes >= scheduleMinutes - 15 && currentMinutes <= scheduleMinutes + 15) {
      return TimelineStatus.active;
    }

    return TimelineStatus.upcoming;
  }

  AttendanceAction? _getActionForItem(ScheduleItem item, TimelineStatus status) {
    // Find matching action from available actions
    final actionType = _getActionTypeString(item.type);
    return _availableActions.firstWhere(
      (action) => action.type == actionType,
      orElse: () => AttendanceAction(
        type: actionType,
        label: item.label,
        isEnabled: false,
        reason: 'Not available now',
      ),
    );
  }

  String _getActionTypeString(AttendanceActionType type) {
    switch (type) {
      case AttendanceActionType.checkIn:
        return 'check_in';
      case AttendanceActionType.checkOut:
        return 'check_out';
      case AttendanceActionType.breakOut:
        return 'break_out';
      case AttendanceActionType.breakIn:
        return 'break_in';
    }
  }

  int _getPresenceDays() {
    return _recentAttendanceRecords.where((r) => r.status == 'present').length;
  }

  int _getAbsenceDays() {
    return _recentAttendanceRecords.where((r) => r.status == 'absent').length;
  }

  String _getLateness() {
    final totalLateMinutes = _recentAttendanceRecords
        .where((r) => r.lateMinutes != null)
        .map((r) => r.lateMinutes!)
        .fold(0, (sum, minutes) => sum + minutes);
    return TimeHelper.formatDuration(totalLateMinutes);
  }

  String _getCurrentStatusText() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return 'Ready to start';
      case AttendanceStatus.working:
        return 'Currently working';
      case AttendanceStatus.onBreak:
        return 'On break';
      case AttendanceStatus.checkedOut:
        return 'Work completed';
      case AttendanceStatus.unknown:
        return 'Status unknown';
    }
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return Colors.orange;
      case AttendanceStatus.working:
        return Colors.green;
      case AttendanceStatus.onBreak:
        return Colors.blue;
      case AttendanceStatus.checkedOut:
        return Colors.grey;
      case AttendanceStatus.unknown:
        return Colors.red;
    }
  }

  Future<void> _performAttendance(String actionType) async {
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

      // Perform attendance
      final success = await _attendanceService.performAttendance(
        type: actionType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: _currentPosition!,
        photoUrl: photoUrl,
        device: _attendanceDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      if (success) {
        await _showSuccessAttendancePopup(actionType);
        await _loadOrganizationData();
        await _updateAttendanceStatus();
        _buildDynamicTimeline();
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
                      const SizedBox(height: 8),
                      Text(
                        _getAttendanceTypeLabel(type),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        TimezoneHelper.formatAttendanceDateTime(jakartaTime),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
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

  String _getAttendanceTypeLabel(String type) {
    switch (type) {
      case 'check_in':
        return 'Check-in completed';
      case 'check_out':
        return 'Check-out completed';
      case 'break_out':
        return 'Break started';
      case 'break_in':
        return 'Work resumed';
      default:
        return 'Attendance recorded';
    }
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
          _buildStatusCard(),
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
                      'Hello, $displayName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _getCurrentStatusText(),
                      style: TextStyle(
                        color: _getStatusColor(),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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

  Widget _buildStatusCard() {
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
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _getCurrentStatusText(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              TimezoneHelper.formatJakartaTime(DateTime.now(), 'EEEE, dd MMMM yyyy • HH:mm WIB'),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            if (_availableActions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableActions.take(2).map((action) {
                  return ElevatedButton(
                    onPressed: action.isEnabled ? () => _performAttendance(action.type) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: action.isEnabled ? primaryColor : Colors.grey.shade300,
                      foregroundColor: action.isEnabled ? Colors.white : Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      action.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
              Text(
                DateFormat('MMM yyyy').format(DateTime.now()),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem('Presence', '${_getPresenceDays()}', Colors.green),
              ),
              Expanded(
                child: _buildStatItem('Absence', '${_getAbsenceDays()}', Colors.red),
              ),
              Expanded(
                child: _buildStatItem('Lateness', _getLateness(), Colors.orange),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Schedule',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          ..._timelineItems.map((item) => _buildTimelineItem(item)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(TimelineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getItemStatusColor(item.status),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getItemIcon(item.type),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item.action != null)
                      _buildActionButton(item),
                  ],
                ),
                const SizedBox(height: 4),
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
    final action = item.action!;
    
    if (!action.isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          action.reason ?? 'Not available',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: () => _performAttendance(action.type),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(0, 0),
      ),
      child: Text(
        action.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _getItemStatusColor(TimelineStatus status) {
    switch (status) {
      case TimelineStatus.completed:
        return Colors.green.shade400;
      case TimelineStatus.active:
        return primaryColor;
      case TimelineStatus.upcoming:
        return Colors.grey.shade200;
    }
  }

  IconData _getItemIcon(AttendanceActionType type) {
    switch (type) {
      case AttendanceActionType.checkIn:
        return Icons.login;
      case AttendanceActionType.checkOut:
        return Icons.logout;
      case AttendanceActionType.breakOut:
        return Icons.coffee;
      case AttendanceActionType.breakIn:
        return Icons.work;
    }
  }
}

// ================== DATA CLASSES ==================

class TimelineItem {
  final String time;
  final String label;
  final String subtitle;
  final AttendanceActionType type;
  final TimelineStatus status;
  final AttendanceAction? action;

  TimelineItem({
    required this.time,
    required this.label,
    required this.subtitle,
    required this.type,
    required this.status,
    this.action,
  });
}

class ScheduleItem {
  final String time;
  final String label;
  final AttendanceActionType type;
  final String subtitle;

  ScheduleItem({
    required this.time,
    required this.label,
    required this.type,
    required this.subtitle,
  });
}

enum AttendanceActionType {
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