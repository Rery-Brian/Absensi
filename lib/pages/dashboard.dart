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
import '../services/device_service.dart';
import '../pages/device_selection_screen.dart';
import 'login.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => UserDashboardState();
}

class UserDashboardState extends State<UserDashboard> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  final GlobalKey<_DashboardContentState> _dashboardContentKey = GlobalKey<_DashboardContentState>();

  void refreshUserProfile() {
    debugPrint('UserDashboard: refreshUserProfile called');
    if (_dashboardContentKey.currentState != null) {
      _dashboardContentKey.currentState!.refreshUserProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _DashboardContent(key: _dashboardContentKey),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent({super.key});

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final AttendanceService _attendanceService = AttendanceService();
  final DeviceService _deviceService = DeviceService();
  bool _isLoading = false;
  bool _isRefreshing = false;
  Position? _currentPosition;

  UserProfile? _userProfile;
  OrganizationMember? _organizationMember;
  SimpleOrganization? _organization;
  AttendanceDevice? _selectedDevice;
  List<AttendanceRecord> _todayAttendanceRecords = [];
  List<AttendanceRecord> _recentAttendanceRecords = [];
  MemberSchedule? _currentSchedule;
  WorkScheduleDetails? _todayScheduleDetails;
  AttendanceStatus _currentStatus = AttendanceStatus.unknown;
  List<AttendanceAction> _availableActions = [];
  bool _needsDeviceSelection = false;

  final List<TimelineItem> _timelineItems = [];

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserData();
  }

  Future<void> refreshUserProfile() async {
    debugPrint('DashboardContent: refreshUserProfile called');
    try {
      final updatedProfile = await _attendanceService.loadUserProfile();
      if (updatedProfile != null && mounted) {
        setState(() {
          _userProfile = updatedProfile;
        });
        debugPrint('Profile photo updated: ${_userProfile?.profilePhotoUrl}');
      }
    } catch (e) {
      debugPrint('Failed to refresh user profile: $e');
    }
  }

  void triggerAttendanceHistoryRefresh() {
    debugPrint('Dashboard: Attendance completed - should refresh history');
    // This callback can be implemented if needed
  }

  Future<void> _initializeServices() async {
    try {
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
          await _checkDeviceSelection();
          if (!_needsDeviceSelection) {
            await _loadOrganizationData();
            await _loadScheduleData();
            await _updateAttendanceStatus();
            await _buildDynamicTimeline();
          }
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

  Future<void> _checkDeviceSelection() async {
    if (_organizationMember == null) return;

    try {
      // Check if device selection is required
      final selectionRequired = await _deviceService.isSelectionRequired(_organizationMember!.organizationId);
      
      if (selectionRequired) {
        // Check if user has already selected a device
        final selectedDevice = await _deviceService.loadSelectedDevice(_organizationMember!.organizationId);
        
        if (selectedDevice == null) {
          setState(() {
            _needsDeviceSelection = true;
          });
          return;
        }
      }

      // Load the selected device
      _selectedDevice = await _deviceService.loadSelectedDevice(_organizationMember!.organizationId);
      
      setState(() {
        _needsDeviceSelection = false;
      });
    } catch (e) {
      debugPrint('Error checking device selection: $e');
      _showSnackBar('Failed to check device configuration.', isError: true);
    }
  }

  Future<void> _navigateToDeviceSelection({bool isRequired = false}) async {
    if (_organizationMember == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          organizationId: _organizationMember!.organizationId,
          organizationName: _organization?.name ?? 'Organization',
          isRequired: isRequired,
        ),
      ),
    );

    if (result == true) {
      await _refreshData();
    }
  }

  Future<void> _loadOrganizationInfo() async {
    if (_organizationMember == null) return;

    try {
      // Handle both string and int organizationId
      dynamic orgIdValue;
      try {
        orgIdValue = int.parse(_organizationMember!.organizationId);
      } catch (e) {
        orgIdValue = _organizationMember!.organizationId;
      }

      final response = await Supabase.instance.client
          .from('organizations')
          .select('id, name, logo_url')
          .eq('id', orgIdValue)
          .single();

      if (response != null && mounted) {
        setState(() {
          _organization = SimpleOrganization(
            id: response['id'].toString(),
            name: response['name'] ?? 'Unknown Organization',
            logoUrl: response['logo_url'],
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
      _showSnackBar('Failed to load organization info: ${e.toString()}', isError: true);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      // Also refresh user profile during data refresh
      _userProfile = await _attendanceService.loadUserProfile();
      
      if (_organizationMember != null) {
        await _loadOrganizationInfo();
        await _checkDeviceSelection();
        
        if (!_needsDeviceSelection) {
          await _loadOrganizationData();
          await _loadScheduleData();
          await _updateAttendanceStatus();
          await _buildDynamicTimeline();
        }
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
        _attendanceService.loadTodayAttendanceRecords(_organizationMember!.id),
        _attendanceService.loadRecentAttendanceRecords(_organizationMember!.id),
        _attendanceService.loadCurrentSchedule(_organizationMember!.id),
        _attendanceService.getCurrentLocation(),
      ]);

      if (mounted) {
        setState(() {
          _todayAttendanceRecords = futures[0] as List<AttendanceRecord>;
          _recentAttendanceRecords = futures[1] as List<AttendanceRecord>;
          _currentSchedule = futures[2] as MemberSchedule?;
          _currentPosition = futures[3] as Position?;
        });
      }
    } catch (e) {
      debugPrint('Error loading organization data: $e');
      _showSnackBar('Failed to load organization data.', isError: true);
    }
  }

  Future<void> _loadScheduleData() async {
    if (_organizationMember == null) return;

    try {
      // Get current schedule first
      _currentSchedule = await _attendanceService.loadCurrentSchedule(_organizationMember!.id);
      
      if (_currentSchedule?.workScheduleId != null) {
        // If we have a work schedule, get today's details
        final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
        _todayScheduleDetails = await _attendanceService.loadWorkScheduleDetails(
          _currentSchedule!.workScheduleId!, 
          dayOfWeek
        );
        debugPrint('Loaded work schedule details: ${_todayScheduleDetails?.toJson()}');
      } else {
        debugPrint('No work schedule found, current schedule: ${_currentSchedule?.toJson()}');
      }

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

  String _formatTimeFromDatabase(String timeString) {
    try {
      // Use TimeHelper to parse and format the time properly
      final timeOfDay = TimeHelper.parseTimeString(timeString);
      return TimeHelper.formatTimeOfDay(timeOfDay);
    } catch (e) {
      debugPrint('Error formatting time from database "$timeString": $e');
      // Fallback: try basic string manipulation
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
          final minute = int.tryParse(parts[1])?.toString().padLeft(2, '0') ?? '00';
          return '$hour:$minute';
        }
      }
      return timeString; // Return original if all else fails
    }
  }

  Future<List<ScheduleItem>> _getScheduleItemsFromShift() async {
    List<ScheduleItem> items = [];
    
    try {
      dynamic shiftIdValue;
      try {
        shiftIdValue = int.parse(_currentSchedule!.shiftId!);
      } catch (e) {
        shiftIdValue = _currentSchedule!.shiftId!;
      }

      final shiftResponse = await Supabase.instance.client
          .from('shifts')
          .select('start_time, end_time, break_duration_minutes')
          .eq('id', shiftIdValue)
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
          
          items.add(ScheduleItem(
            time: TimeHelper.formatTimeOfDay(TimeHelper.minutesToTime(breakStartMinutes)),
            label: 'Break',
            type: AttendanceActionType.breakOut,
            subtitle: 'Take a break',
          ));
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
    }
    
    return items;
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
          statusDescription: _getStatusDescription(scheduleItem.type, status),
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

  String _getStatusDescription(AttendanceActionType type, TimelineStatus status) {
    switch (status) {
      case TimelineStatus.completed:
        return 'Completed';
      case TimelineStatus.active:
        return 'Available now';
      case TimelineStatus.upcoming:
        return 'Not yet available';
    }
  }

  bool _needsPhoto(String actionType) {
    // Only check-in requires photo, checkout doesn't
    return actionType == 'check_in';
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
      int memberId = int.parse(_organizationMember!.id);
      int? deviceId;

      // Use selected device if available
      if (_selectedDevice != null) {
        deviceId = int.tryParse(_selectedDevice!.id);
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

      if (_selectedDevice == null || !_selectedDevice!.hasValidCoordinates) {
        _showSnackBar('Device location not configured. Please select a valid device.', isError: true);
        return;
      }

      await _getCurrentLocation();
      if (_currentPosition == null) {
        _showSnackBar('Location not found. Ensure GPS is on.', isError: true);
        return;
      }

      // Use the attendance device radius check
      if (!_attendanceService.isWithinRadius(_currentPosition!, _selectedDevice!)) {
        final distance = _attendanceService.calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _selectedDevice!.latitude,
          _selectedDevice!.longitude,
        );
        
        _showSnackBar(
          distance != null
              ? 'You are outside device radius (${distance.toStringAsFixed(0)}m from ${_selectedDevice!.radiusMeters}m)'
              : 'Cannot calculate distance to device',
          isError: true,
        );
        return;
      }

      String? photoUrl;

      if (_needsPhoto(actionType)) {
        String? imagePath = await _takeSelfie();
        if (imagePath == null) {
          _showSnackBar('Photo required for check-in', isError: true);
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
        device: _selectedDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      if (success) {
        await _showSuccessAttendancePopup(actionType);
        await _refreshData();
        
        // Call the callback to trigger attendance history refresh
        triggerAttendanceHistoryRefresh();
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
    
    final orgTime = TimezoneHelper.nowInOrgTime();

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
                        TimezoneHelper.formatAttendanceDateTime(orgTime),
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

  String _getDisplayName() {
    final user = Supabase.instance.client.auth.currentUser;
    
    if (_userProfile?.displayName != null && _userProfile!.displayName!.isNotEmpty) {
      return _userProfile!.displayName!;
    }
    
    if (_userProfile?.fullName != null && _userProfile!.fullName!.isNotEmpty) {
      return _userProfile!.fullName!;
    }
    
    if (_userProfile?.firstName != null && _userProfile!.firstName!.isNotEmpty) {
      return _userProfile!.firstName!;
    }
    
    if (user?.email != null) {
      return user!.email!.split('@')[0];
    }
    
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();

    // Check for device selection requirement
    if (_needsDeviceSelection) {
      return _buildDeviceSelectionRequiredView();
    }

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

  Widget _buildDeviceSelectionRequiredView() {
    final displayName = _getDisplayName();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: RefreshIndicator(
        onRefresh: _refreshData,
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
                                const Text(
                                  'Device selection required',
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
                              color: primaryColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.devices, 
                              size: 40, 
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Select Your Device',
                            style: TextStyle(
                              fontSize: 22, 
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Please select your attendance device location before using the attendance system.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading ? null : () => _navigateToDeviceSelection(isRequired: true),
                                  icon: _isLoading 
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(Icons.devices),
                                  label: Text(_isLoading ? 'Loading...' : 'Select Device'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
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
      ),
    );
  }

  Widget _buildNotRegisteredView() {
    final displayName = _getDisplayName();

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
          const SizedBox(height: 100),
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
              // Device selector button
              if (_selectedDevice != null)
                GestureDetector(
                  onTap: () => _navigateToDeviceSelection(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.devices,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _selectedDevice!.deviceName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TimezoneHelper.formatOrgTime(
                    TimezoneHelper.nowInOrgTime(),
                    'EEEE, dd MMMM yyyy • HH:mm z'
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                if (_selectedDevice != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.devices_outlined,
                        size: 14,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _selectedDevice!.deviceName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_currentPosition != null && _selectedDevice!.hasValidCoordinates) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _attendanceService.isWithinRadius(_currentPosition!, _selectedDevice!)
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _attendanceService.isWithinRadius(_currentPosition!, _selectedDevice!)
                                ? 'In range'
                                : 'Out of range',
                            style: TextStyle(
                              fontSize: 10,
                              color: _attendanceService.isWithinRadius(_currentPosition!, _selectedDevice!)
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
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
              physics: const NeverScrollableScrollPhysics(),
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
                    // Status description instead of action button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getItemStatusColor(item.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.statusDescription,
                        style: TextStyle(
                          fontSize: 12,
                          color: _getItemStatusColor(item.status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
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

  Color _getItemStatusColor(TimelineStatus status) {
    switch (status) {
      case TimelineStatus.completed:
        return Colors.green.shade400;
      case TimelineStatus.active:
        return primaryColor;
      case TimelineStatus.upcoming:
        return Colors.grey.shade400;
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

// Helper classes
class TimelineItem {
  final String time;
  final String label;
  final String subtitle;
  final AttendanceActionType type;
  final TimelineStatus status;
  final String statusDescription;

  TimelineItem({
    required this.time,
    required this.label,
    required this.subtitle,
    required this.type,
    required this.status,
    required this.statusDescription,
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

class SimpleOrganization {
  final String id;
  final String name;
  final String? logoUrl;

  SimpleOrganization({
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