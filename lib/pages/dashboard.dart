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
import '../pages/break_page.dart'; 
import 'login.dart';
import 'attendance_history.dart';
import 'profile.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _currentIndex = 0;
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  final List<BottomNavigationBarItem> _bottomNavItems = [
    const BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'Home',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.history_outlined),
      activeIcon: Icon(Icons.history),
      label: 'History',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _DashboardContent(),
          const AttendanceHistoryPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              selectedItemColor: primaryColor,
              unselectedItemColor: Colors.grey.shade400,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              iconSize: 24,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
              items: _bottomNavItems,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _isLoading = false;
  bool _isRefreshing = false;
  Position? _currentPosition;

  UserProfile? _userProfile;
  OrganizationMember? _organizationMember;
  Organization? _organization;
  List<AttendanceRecord> _todayAttendanceRecords = [];
  List<AttendanceRecord> _recentAttendanceRecords = [];
  MemberSchedule? _currentSchedule;
  AttendanceDevice? _attendanceDevice;
  WorkScheduleDetails? _todayScheduleDetails;
  AttendanceStatus _currentStatus = AttendanceStatus.unknown;
  List<AttendanceAction> _availableActions = [];

  final List<TimelineItem> _timelineItems = [];

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

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
      debugPrint('Error initializing services: $e');
      _showSnackBar('Failed to initialize services. Please restart the app.', isError: true);
    }
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _userProfile = await _attendanceService.loadUserProfile();
      
      if (_userProfile != null) {
        _organizationMember = await _attendanceService.loadOrganizationMember();
        
        if (_organizationMember != null) {
          await _loadOrganizationInfo();
          await _loadOrganizationData();
          await _loadScheduleData();
          await _updateAttendanceStatus();
          await _buildDynamicTimeline();
        } else {
          _showSnackBar('No organization found. Contact admin.', isError: true);
        }
      } else {
        _showSnackBar('No user profile found. Please login again.', isError: true);
      }
    } catch (e) {
      debugPrint('Error in _loadUserData: $e');
      _showSnackBar('Failed to load user data. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOrganizationInfo() async {
    if (_organizationMember == null) return;

    try {
      final response = await Supabase.instance.client
          .from('organizations')
          .select('id, name, logo_url')
          .eq('id', _organizationMember!.organizationId)
          .single();

      if (response != null && mounted) {
        setState(() {
          _organization = Organization(
            id: response['id'],
            name: response['name'] ?? 'Unknown Organization',
            logoUrl: response['logo_url'],
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
      _showSnackBar('Failed to load organization info.', isError: true);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      if (_organizationMember != null) {
        await _loadOrganizationInfo();
        await _loadOrganizationData();
        await _loadScheduleData();
        await _updateAttendanceStatus();
        await _buildDynamicTimeline();
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      _showSnackBar('Failed to refresh data. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
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

      if (mounted) {
        setState(() {
          _attendanceDevice = futures[0] as AttendanceDevice?;
          _todayAttendanceRecords = futures[1] as List<AttendanceRecord>;
          _recentAttendanceRecords = futures[2] as List<AttendanceRecord>;
          _currentSchedule = futures[3] as MemberSchedule?;
          _currentPosition = futures[4] as Position?;
        });
      }
    } catch (e) {
      debugPrint('Error loading organization data: $e');
      _showSnackBar('Failed to load organization data.', isError: true);
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
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading schedule details: $e');
      _showSnackBar('Failed to load schedule details.', isError: true);
    }
  }

  Future<void> _updateAttendanceStatus() async {
    if (_organizationMember == null) return;

    try {
      _currentStatus = await _attendanceService.getCurrentAttendanceStatus(_organizationMember!.id);
      _availableActions = await _attendanceService.getAvailableActions(_organizationMember!.id);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error updating attendance status: $e');
      _showSnackBar('Failed to update attendance status.', isError: true);
    }
  }

  Future<List<ScheduleItem>> _getScheduleItemsFromDatabase() async {
    List<ScheduleItem> items = [];
    
    try {
      if (_todayScheduleDetails != null && _todayScheduleDetails!.isWorkingDay) {
        
        if (_todayScheduleDetails!.startTime != null) {
          items.add(ScheduleItem(
            time: _formatTimeFromDatabase(_todayScheduleDetails!.startTime!),
            label: 'Check In',
            type: AttendanceActionType.checkIn,
            subtitle: 'Start work day',
          ));
        }
        
        if (_todayScheduleDetails!.breakStart != null) {
          items.add(ScheduleItem(
            time: _formatTimeFromDatabase(_todayScheduleDetails!.breakStart!),
            label: 'Break',
            type: AttendanceActionType.breakOut,
            subtitle: 'Take a break',
          ));
        }
        
        // Removed resume work item as per instructions
        
        if (_todayScheduleDetails!.endTime != null) {
          items.add(ScheduleItem(
            time: _formatTimeFromDatabase(_todayScheduleDetails!.endTime!),
            label: 'Check Out',
            type: AttendanceActionType.checkOut,
            subtitle: 'End work day',
          ));
        }
        
      } else {
        if (_currentSchedule?.shiftId != null) {
          items = await _getScheduleItemsFromShift();
        } else {
          debugPrint('No work schedule found for today');
          return [];
        }
      }
      
    } catch (e) {
      debugPrint('Error getting schedule items from database: $e');
      _showSnackBar('Failed to load schedule items.', isError: true);
    }
    
    return items;
  }

  Future<List<ScheduleItem>> _getScheduleItemsFromShift() async {
    List<ScheduleItem> items = [];
    
    try {
      final shiftResponse = await Supabase.instance.client
          .from('shifts')
          .select('start_time, end_time, break_duration_minutes')
          .eq('id', _currentSchedule!.shiftId!)
          .single();
      
      if (shiftResponse != null) {
        items.add(ScheduleItem(
          time: _formatTimeFromDatabase(shiftResponse['start_time']),
          label: 'Check In',
          type: AttendanceActionType.checkIn,
          subtitle: 'Start work day',
        ));
        
        if (shiftResponse['break_duration_minutes'] != null && 
            shiftResponse['break_duration_minutes'] > 0) {
          
          final startTime = TimeHelper.parseTimeString(_formatTimeFromDatabase(shiftResponse['start_time']));
          final endTime = TimeHelper.parseTimeString(_formatTimeFromDatabase(shiftResponse['end_time']));
          
          final totalMinutes = TimeHelper.timeToMinutes(endTime) - TimeHelper.timeToMinutes(startTime);
          final breakStartMinutes = TimeHelper.timeToMinutes(startTime) + (totalMinutes ~/ 2);
          final breakEndMinutes = breakStartMinutes + (shiftResponse['break_duration_minutes'] as int);
          
          items.add(ScheduleItem(
            time: TimeHelper.formatTimeOfDay(TimeHelper.minutesToTime(breakStartMinutes)),
            label: 'Break',
            type: AttendanceActionType.breakOut,
            subtitle: 'Take a break',
          ));
          
          // Removed resume item
        }
        
        items.add(ScheduleItem(
          time: _formatTimeFromDatabase(shiftResponse['end_time']),
          label: 'Check Out',
          type: AttendanceActionType.checkOut,
          subtitle: 'End work day',
        ));
      }
      
    } catch (e) {
      debugPrint('Error getting schedule from shift: $e');
      _showSnackBar('Failed to load shift schedule.', isError: true);
    }
    
    return items;
  }

  String _formatTimeFromDatabase(String timeString) {
    try {
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          return '${parts[0]}:${parts[1]}';
        }
      }
      return timeString;
    } catch (e) {
      debugPrint('Error formatting time from database: $e');
      return timeString;
    }
  }

  Future<void> _buildDynamicTimeline() async {
    _timelineItems.clear();
    
    try {
      final scheduleItems = await _getScheduleItemsFromDatabase();
      
      if (scheduleItems.isEmpty) {
        debugPrint('No schedule items found for today');
        if (mounted) {
          setState(() {});
        }
        return;
      }
      
      final currentTime = TimeHelper.getCurrentTime();

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
      
      if (mounted) {
        setState(() {});
      }
      
    } catch (e) {
      debugPrint('Error building dynamic timeline: $e');
      _showSnackBar('Failed to build timeline.', isError: true);
      if (mounted) {
        setState(() {});
      }
    }
  }

  TimelineStatus _getItemStatus(ScheduleItem item, TimeOfDay scheduleTime, TimeOfDay currentTime) {
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
        break;
    }

    final currentMinutes = TimeHelper.timeToMinutes(currentTime);
    final scheduleMinutes = TimeHelper.timeToMinutes(scheduleTime);
    
    if (currentMinutes >= scheduleMinutes - 15 && currentMinutes <= scheduleMinutes + 15) {
      return TimelineStatus.active;
    }

    return TimelineStatus.upcoming;
  }

  AttendanceAction? _getActionForItem(ScheduleItem item, TimelineStatus status) {
    final actionType = _getActionTypeString(item.type);
    try {
      return _availableActions.firstWhere((action) => action.type == actionType);
    } catch (e) {
      return AttendanceAction(
        type: actionType,
        label: item.label,
        isEnabled: false,
        reason: 'Not available now',
      );
    }
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

  bool _needsPhoto(String actionType) {
    return actionType == 'check_in' || actionType == 'check_out';
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

  Future<void> _navigateToBreakPage() async {
    if (_organizationMember == null) {
      _showSnackBar('Organization member data not found. Contact admin.', isError: true);
      return;
    }

    try {
      int memberId = int.parse(_organizationMember!.id as String);
      int? deviceId;
      if (_attendanceDevice?.id != null) {
        deviceId = int.parse(_attendanceDevice!.id as String);
      }

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => BreakPage(
            organizationMemberId: memberId,
            deviceId: deviceId,
          ),
        ),
      );

      if (result == true || mounted) {
        await _refreshData();
      }
    } catch (e) {
      debugPrint('Error navigating to break page: $e');
      _showSnackBar('Failed to open break page.', isError: true);
    }
  }

  Future<void> _performAttendance(String actionType) async {
    if (!mounted) return;
    
    if (actionType == 'break_out') {
      await _navigateToBreakPage();
      return;
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      if (_organizationMember == null) {
        _showSnackBar('Organization member data not found. Contact admin.', isError: true);
        return;
      }

      if (_attendanceDevice == null || !_attendanceDevice!.hasValidCoordinates) {
        _showSnackBar('Office location not configured. Contact admin.', isError: true);
        return;
      }

      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Location not found. Ensure GPS is on.', isError: true);
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
              ? 'You are outside office radius (${distance.toStringAsFixed(0)}m from ${_attendanceDevice!.radiusMeters.toInt()}m)'
              : 'Cannot calculate distance to office',
          isError: true,
        );
        return;
      }

      String? photoUrl;

      if (_needsPhoto(actionType)) {
        String? imagePath = await _takeSelfie();
        if (imagePath == null) {
          _showSnackBar('Photo required for ${actionType == 'check_in' ? 'check-in' : 'check-out'}', isError: true);
          return;
        }

        photoUrl = await _attendanceService.uploadPhoto(imagePath);
        if (photoUrl == null) {
          _showSnackBar('Failed to upload photo.', isError: true);
          return;
        }

        try {
          await File(imagePath).delete();
        } catch (e) {
          debugPrint('Failed to delete temporary file: $e');
        }
      }

      final success = await _attendanceService.performAttendance(
        type: actionType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: _currentPosition!,
        photoUrl: photoUrl ?? '',
        device: _attendanceDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      if (success) {
        await _showSuccessAttendancePopup(actionType);
        await _refreshData();
      }

    } catch (e) {
      debugPrint('Error performing attendance: $e');
      _showSnackBar('Failed to perform attendance: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await _attendanceService.getCurrentLocation();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      _showSnackBar('Failed to get location: $e', isError: true);
    }
  }

  bool _isWithinRadius() {
    if (_currentPosition == null || _attendanceDevice == null) return false;
    return _attendanceService.isWithinRadius(_currentPosition!, _attendanceDevice!);
  }

  Future<String?> _takeSelfie() async {
    if (!CameraService.isInitialized) {
      _showSnackBar('Camera not available.', isError: true);
      return null;
    }

    final hasPermission = await CameraService.requestCameraPermission();
    if (!hasPermission) {
      _showSnackBar('Camera permission required.', isError: true);
      return null;
    }

    try {
      if (!mounted) return null;
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => CameraSelfieScreen(cameras: CameraService.cameras),
        ),
      );
      return result;
    } catch (e) {
      _showSnackBar('Failed to take photo: $e', isError: true);
      return null;
    }
  }

  Future<void> _showSuccessAttendancePopup(String type) async {
    if (!mounted) return;
    
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
                colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
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
                              color: Colors.black.withValues(alpha: 0.2),
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
                        'Attendance Successful!',
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
          : RefreshIndicator(
              onRefresh: _refreshData,
              color: primaryColor,
              backgroundColor: Colors.white,
              child: _buildMainContent(displayName),
            ),
    );
  }

  Widget _buildNotRegisteredView() {
    final user = Supabase.instance.client.auth.currentUser;
    final displayName = _userProfile?.fullName ?? user?.email?.split('@')[0] ?? 'User';

    return RefreshIndicator(
      onRefresh: _loadUserData,
      color: primaryColor,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [backgroundColor, backgroundColor.withValues(alpha: 0.8)],
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
                              const Text(
                                'Account Setup Required',
                                style: TextStyle(
                                  color: Colors.orange,
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
              ),
              
              Expanded(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.business_outlined, 
                            size: 40, 
                            color: Colors.orange.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Organization Setup Required',
                          style: TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'You need to be registered as a member of an organization to use this attendance system.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Contact your HR administrator to get added to your organization.',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _loadUserData,
                                icon: _isLoading 
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                        ),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(_isLoading ? 'Checking...' : 'Check Again'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(color: primaryColor),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(String displayName) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildHeader(displayName),
          _buildStatusCard(),
          _buildOverviewCard(),
          _buildTimelineCard(),
          const SizedBox(height: 100), // Extra space for bottom navigation
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
          colors: [backgroundColor, backgroundColor.withValues(alpha: 0.8)],
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
              Expanded(
                child: Row(
                  children: [
                    if (_organization?.logoUrl != null)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _organization!.logoUrl!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.business,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.business,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _organization?.name ?? 'Unknown Organization',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
              color: Colors.black.withValues(alpha: 0.1),
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
                if (_isRefreshing) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                ],
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
                    onPressed: action.isEnabled && !_isLoading ? () => _performAttendance(action.type) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: action.isEnabled ? primaryColor : Colors.grey.shade300,
                      foregroundColor: action.isEnabled ? Colors.white : Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading && action.isEnabled
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            action.label,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                  );
                }).toList(),
              ),
            ],
            if (_currentStatus == AttendanceStatus.working) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _navigateToBreakPage,
                  icon: const Icon(Icons.coffee, size: 18),
                  label: const Text('Take Break'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('Presence', '${_getPresenceDays()}', Colors.green),
              _buildStatItem('Absence', '${_getAbsenceDays()}', Colors.red),
              _buildStatItem('Lateness', _getLateness(), Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
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
            color: Colors.black.withValues(alpha: 0.05),
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
          if (_timelineItems.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No schedule available for today',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _timelineItems.length,
              itemBuilder: (context, index) {
                return _buildTimelineItem(_timelineItems[index]);
              },
            ),
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

    if (action.type == 'break_out') {
      return ElevatedButton(
        onPressed: _isLoading ? null : _navigateToBreakPage,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 0),
        ),
        child: _isLoading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                action.label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
      );
    }

    return ElevatedButton(
      onPressed: _isLoading ? null : () => _performAttendance(action.type),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(0, 0),
      ),
      child: _isLoading
          ? SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(
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

class Organization {
  final int id;
  final String name;
  final String? logoUrl;

  Organization({
    required this.id,
    required this.name,
    this.logoUrl,
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