import 'dart:async';
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
  
  // Loading states - lebih granular
  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  bool _isLocationUpdating = false;
  
  // Data cache
  Position? _currentPosition;
  Position? _gpsPosition;
  double? _distanceToDevice;
  bool? _isWithinRadius;
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
  Map<String, dynamic>? _breakInfo;
  final List<TimelineItem> _timelineItems = [];

  // Timers
  Timer? _debounceTimer;
  Timer? _periodicLocationTimer;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const double minGpsAccuracy = 20.0;
  static const int maxGpsRetries = 2;
  static const Duration gpsRetryDelay = Duration(seconds: 3);
  static const Duration locationUpdateInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserData();
    _startPeriodicLocationUpdates();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _periodicLocationTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicLocationUpdates() {
    _periodicLocationTimer = Timer.periodic(locationUpdateInterval, (timer) async {
      if (mounted && !_isLocationUpdating && _selectedDevice != null) {
        await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
      }
    });
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
  }

  Future<void> _initializeServices() async {
    try {
      await CameraService.initializeCameras();
    } catch (e) {
      debugPrint('Error initializing services: $e');
      _showSnackBar('Failed to initialize services. Please restart the app.', isError: true);
    }
  }

  // 🔥 OPTIMIZED: Load data secara parallel dengan prioritas
  Future<void> _loadUserData() async {
    setState(() {
      _isInitialLoading = true;
    });

    try {
      // Priority 1: Load user profile & organization member (parallel)
      final criticalData = await Future.wait([
        _attendanceService.loadUserProfile(),
        _attendanceService.loadOrganizationMember(),
      ]);

      _userProfile = criticalData[0] as UserProfile?;
      _organizationMember = criticalData[1] as OrganizationMember?;

      if (_userProfile == null || _organizationMember == null) {
        _showSnackBar('No user profile or organization found. Contact admin.', isError: true);
        setState(() => _isInitialLoading = false);
        return;
      }

      // Priority 2: Load organization info & check device (parallel)
      await Future.wait([
        _loadOrganizationInfo(),
        _checkDeviceSelection(),
      ]);

      if (_needsDeviceSelection) {
        setState(() => _isInitialLoading = false);
        return;
      }

      // Priority 3: Show UI first, then load secondary data
      setState(() => _isInitialLoading = false);

      // Priority 4: Load secondary data in background
      _loadSecondaryDataInBackground();

    } catch (e) {
      debugPrint('Error in _loadUserData: $e');
      _showSnackBar('Failed to load user data. Please try again.', isError: true);
      setState(() => _isInitialLoading = false);
    }
  }

  // 🔥 NEW: Load data sekunder di background
  Future<void> _loadSecondaryDataInBackground() async {
    if (_organizationMember == null) return;

    try {
      // Load schedule data first
      await _loadScheduleData();
      
      // Then load other data in parallel
      await Future.wait([
        _loadOrganizationData(),
        _loadBreakInfo(),
      ]);

      // Finally, update status and timeline
      await _updateAttendanceStatus();
      await _buildDynamicTimeline();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading secondary data: $e');
    }
  }

  Future<void> _loadBreakInfo() async {
    if (_organizationMember == null) return;

    try {
      _breakInfo = await _attendanceService.getTodayBreakInfo(_organizationMember!.id);
      debugPrint('Break info loaded: $_breakInfo');
    } catch (e) {
      debugPrint('Error loading break info: $e');
    }
  }

  Future<void> _checkDeviceSelection() async {
    if (_organizationMember == null) return;

    try {
      final selectionRequired = await _deviceService.isSelectionRequired(_organizationMember!.organizationId);

      if (selectionRequired) {
        final selectedDevice = await _deviceService.loadSelectedDevice(_organizationMember!.organizationId);

        if (selectedDevice == null) {
          setState(() {
            _needsDeviceSelection = true;
            _selectedDevice = null;
            _currentPosition = null;
            _gpsPosition = null;
            _distanceToDevice = null;
            _isWithinRadius = null;
          });
          return;
        }
      }

      final loadedDevice = await _deviceService.loadSelectedDevice(_organizationMember!.organizationId);
      _selectedDevice = loadedDevice;

      if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
        _currentPosition = Position(
          longitude: _selectedDevice!.longitude!,
          latitude: _selectedDevice!.latitude!,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

      // Load GPS di background
      unawaited(_updateGpsPositionAndDistance(debounce: false, retryCount: 0));

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

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          organizationId: _organizationMember!.organizationId,
          organizationName: _organization?.name ?? 'Organization',
          isRequired: isRequired,
        ),
      ),
    );

    if (result != null && result['success'] == true) {
      final newSelectedDevice = result['selectedDevice'] as AttendanceDevice?;
      final deviceChanged = result['deviceChanged'] as bool? ?? false;

      setState(() {
        _currentPosition = null;
        _gpsPosition = null;
        _distanceToDevice = null;
        _isWithinRadius = null;
        _selectedDevice = newSelectedDevice;
      });

      if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
        setState(() {
          _currentPosition = Position(
            longitude: _selectedDevice!.longitude!,
            latitude: _selectedDevice!.latitude!,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
        });
      }

      setState(() {
        _needsDeviceSelection = false;
      });
      
      await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
      
      if (deviceChanged || isRequired) {
        await _forceDataReload();
      }
      
      if (deviceChanged) {
        _showSnackBar('Device changed to ${_selectedDevice?.deviceName ?? "Unknown"}');
      }
    }
  }

  // 🔥 OPTIMIZED: Reload data dengan priority
  Future<void> _forceDataReload() async {
    debugPrint('Forcing complete data reload...');
    
    setState(() {
      _isInitialLoading = true;
      _todayAttendanceRecords.clear();
      _recentAttendanceRecords.clear();
      _currentSchedule = null;
      _todayScheduleDetails = null;
      _currentStatus = AttendanceStatus.unknown;
      _availableActions.clear();
      _timelineItems.clear();
      _breakInfo = null;
    });

    try {
      // Load schedule first
      await _loadScheduleData();
      
      // Then load rest in parallel
      await Future.wait([
        _loadOrganizationData(),
        _loadBreakInfo(),
      ]);
      
      await _updateAttendanceStatus();
      await _buildDynamicTimeline();
      
      debugPrint('Force data reload completed');
    } catch (e) {
      debugPrint('Error in force data reload: $e');
      _showSnackBar('Failed to reload data: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<void> _updateGpsPositionAndDistance({bool debounce = true, int retryCount = 0}) async {
    if (_isLocationUpdating) return;
    setState(() {
      _isLocationUpdating = true;
    });

    if (debounce) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () async {
        await _performGpsUpdate(retryCount);
      });
    } else {
      await _performGpsUpdate(retryCount);
    }
  }

  Future<void> _performGpsUpdate(int retryCount) async {
    try {
      final position = await _attendanceService.getCurrentLocation();
      
      if (position.accuracy <= minGpsAccuracy) {
        debugPrint('✓ GPS location acquired: accuracy ${position.accuracy.toStringAsFixed(1)}m');
        setState(() {
          _gpsPosition = position;
          if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
            _distanceToDevice = Geolocator.distanceBetween(
              _gpsPosition!.latitude,
              _gpsPosition!.longitude,
              _selectedDevice!.latitude!,
              _selectedDevice!.longitude!,
            );
            _isWithinRadius = _attendanceService.isWithinRadius(_gpsPosition!, _selectedDevice!);
          } else {
            _distanceToDevice = null;
            _isWithinRadius = null;
          }
          _isLocationUpdating = false;
        });
      } else {
        debugPrint('⚠ GPS accuracy: ${position.accuracy.toStringAsFixed(1)}m');
        
        if (retryCount < maxGpsRetries) {
          await Future.delayed(gpsRetryDelay);
          await _performGpsUpdate(retryCount + 1);
        } else {
          setState(() {
            _gpsPosition = position;
            if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
              _distanceToDevice = Geolocator.distanceBetween(
                _gpsPosition!.latitude,
                _gpsPosition!.longitude,
                _selectedDevice!.latitude!,
                _selectedDevice!.longitude!,
              );
              _isWithinRadius = _attendanceService.isWithinRadius(_gpsPosition!, _selectedDevice!);
            } else {
              _distanceToDevice = null;
              _isWithinRadius = null;
            }
            _isLocationUpdating = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to update GPS position: $e');
      if (retryCount < maxGpsRetries) {
        await Future.delayed(gpsRetryDelay);
        await _performGpsUpdate(retryCount + 1);
      } else {
        setState(() {
          _distanceToDevice = null;
          _isWithinRadius = null;
          _isLocationUpdating = false;
        });
        _showSnackBar('Unable to get precise location. Please try again in an open area.', isError: true);
      }
    }
  }

  Future<void> _loadOrganizationInfo() async {
    if (_organizationMember == null) return;

    try {
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
    }
  }

  // 🔥 OPTIMIZED: Refresh dengan cache-first strategy
  Future<void> _refreshData() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      // Refresh profile
      _userProfile = await _attendanceService.loadUserProfile();

      if (_organizationMember != null) {
        // Check device changes
        await _checkDeviceSelection();

        if (!_needsDeviceSelection) {
          // Load data in parallel
          await Future.wait([
            _loadOrganizationData(),
            _loadScheduleData(),
            _loadBreakInfo(),
          ]);
          
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

  // 🔥 OPTIMIZED: Load attendance records in parallel
  Future<void> _loadOrganizationData() async {
    if (_organizationMember == null) return;

    try {
      final results = await Future.wait([
        _attendanceService.loadTodayAttendanceRecords(_organizationMember!.id),
        _attendanceService.loadRecentAttendanceRecords(_organizationMember!.id),
      ]);

      if (mounted) {
        setState(() {
          _todayAttendanceRecords = results[0] as List<AttendanceRecord>;
          _recentAttendanceRecords = results[1] as List<AttendanceRecord>;
        });
      }
    } catch (e) {
      debugPrint('Error loading organization data: $e');
    }
  }

  Future<void> _loadScheduleData() async {
    if (_organizationMember == null) return;

    try {
      _currentSchedule = await _attendanceService.loadCurrentSchedule(_organizationMember!.id);

      if (_currentSchedule?.workScheduleId != null) {
        final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
        _todayScheduleDetails = await _attendanceService.loadWorkScheduleDetails(
          _currentSchedule!.workScheduleId!,
          dayOfWeek,
        );
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading schedule details: $e');
    }
  }

  Future<void> _updateAttendanceStatus() async {
    if (_organizationMember == null) return;

    try {
      final results = await Future.wait([
        _attendanceService.getCurrentAttendanceStatus(_organizationMember!.id),
        _attendanceService.getAvailableActions(_organizationMember!.id),
      ]);

      _currentStatus = results[0] as AttendanceStatus;
      _availableActions = results[1] as List<AttendanceAction>;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error updating attendance status: $e');
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
        }
      }
    } catch (e) {
      debugPrint('Error getting schedule items: $e');
    }

    return items;
  }

  String _formatTimeFromDatabase(String timeString) {
    try {
      final timeOfDay = TimeHelper.parseTimeString(timeString);
      return TimeHelper.formatTimeOfDay(timeOfDay);
    } catch (e) {
      debugPrint('Error formatting time "$timeString": $e');
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour = int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
          final minute = int.tryParse(parts[1])?.toString().padLeft(2, '0') ?? '00';
          return '$hour:$minute';
        }
      }
      return timeString;
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
        if (mounted) setState(() {});
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

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error building timeline: $e');
      if (mounted) setState(() {});
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
      // Cek apakah pernah check-in hari ini
      final hasCheckedInToday = _todayAttendanceRecords.isNotEmpty;
      return hasCheckedInToday ? 'Ready to check in again' : 'Ready to start';
    case AttendanceStatus.working:
      return 'Currently working';
    case AttendanceStatus.onBreak:
      return 'On break';
    case AttendanceStatus.checkedOut:
      return 'Ready to check in again'; // ✅ Ubah pesan
    case AttendanceStatus.unknown:
      return 'Waiting for status...';
  }
}

  Color _getStatusColor() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return warningColor;
      case AttendanceStatus.working:
        return successColor;
      case AttendanceStatus.onBreak:
        return primaryColor;
      case AttendanceStatus.checkedOut:
        return Colors.grey;
      case AttendanceStatus.unknown:
        return errorColor;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return Icons.schedule;
      case AttendanceStatus.working:
        return Icons.work_outline;
      case AttendanceStatus.onBreak:
        return Icons.coffee_outlined;
      case AttendanceStatus.checkedOut:
        return Icons.check_circle_outline;
      case AttendanceStatus.unknown:
        return Icons.help_outline;
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

    // Show confirmation modal for checkout
    if (actionType == 'check_out') {
      final confirmed = await _showCheckoutConfirmation();
      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _isInitialLoading = true;
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

      // Use existing GPS position if available and recent (within 1 minute)
      final now = DateTime.now();
      final gpsAge = _gpsPosition != null 
          ? now.difference(_gpsPosition!.timestamp).inSeconds 
          : 999;

      if (_gpsPosition == null || gpsAge > 60) {
        await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
      }

      if (_gpsPosition == null) {
        _showSnackBar('Location not found. Ensure GPS is on.', isError: true);
        return;
      }

      if (!_attendanceService.isWithinRadius(_gpsPosition!, _selectedDevice!)) {
        final distance = _distanceToDevice;
        _showSnackBar(
          distance != null
              ? 'You are outside device radius (${distance.toStringAsFixed(0)}m from ${_selectedDevice!.radiusMeters}m)'
              : 'Cannot calculate distance to device',
          isError: true,
        );
        return;
      }

      if (_selectedDevice!.hasValidCoordinates) {
        _currentPosition = Position(
          longitude: _selectedDevice!.longitude!,
          latitude: _selectedDevice!.latitude!,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }

      String? photoUrl;
      String? imagePath;

      if (actionType == 'check_in') {
        imagePath = await _takeSelfie();
        if (imagePath == null) {
          _showSnackBar('Photo required for check-in', isError: true);
          return;
        }

        // Show uploading indicator
        if (mounted) {
          _showSnackBar('Uploading photo...');
        }

        // Start upload in parallel with showing UI feedback
        final uploadFuture = _attendanceService.uploadPhoto(imagePath);
        
        // Continue with attendance process
        photoUrl = await uploadFuture;
        
        if (photoUrl == null) {
          _showSnackBar('Failed to upload photo.', isError: true);
          return;
        }

        // Delete temp file asynchronously
        if (imagePath != null) {
          File(imagePath).delete().catchError((e) {
            debugPrint('Failed to delete temporary file: $e');
          });
        }
      }

      // Perform attendance with optimistic UI
      final attendanceFuture = _attendanceService.performAttendance(
        type: actionType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: _currentPosition!,
        photoUrl: photoUrl ?? '',
        device: _selectedDevice,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      final success = await attendanceFuture;

      if (success) {
        // Show success immediately
        if (mounted) {
          await _showSuccessAttendancePopup(actionType);
        }
        
        // Refresh data in background
        unawaited(_refreshData());
        triggerAttendanceHistoryRefresh();
      }
    } catch (e) {
      debugPrint('Error performing attendance: $e');
      _showSnackBar('Failed to perform attendance: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
        });
      }
    }
  }

  Future<bool?> _showCheckoutConfirmation() async {
    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.logout,
                    color: warningColor,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Confirm Check-out',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Are you sure you want to check out? This will end your work session for today.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Yes, Check Out',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
        backgroundColor: isError ? errorColor : primaryColor,
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

  String _formatDistance(double? distanceInMeters) {
    if (distanceInMeters == null) return 'Unknown distance';
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()}m away';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km away';
    }
  }

Widget _buildDeviceInfoChip() {
  if (_selectedDevice == null) {
    return GestureDetector(
      onTap: () => _navigateToDeviceSelection(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.warning, color: Colors.orange, size: 16),
            SizedBox(width: 4),
            Text(
              'No Device',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, color: Colors.orange, size: 16),
          ],
        ),
      ),
    );
  }

  // Ambil nama device saja (hilangkan "Organization - " kalau ada)
  String deviceName = _selectedDevice!.deviceName;
  if (deviceName.contains(" - ")) {
    deviceName = deviceName.split(" - ").last;
  }

  return GestureDetector(
  onTap: () => _navigateToDeviceSelection(),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.location_on, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            deviceName.length > 10 
              ? deviceName.substring(0, 10) + '…' 
              : deviceName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
      ],
    ),
  ),
);

}


  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();

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
                                  return Icon(Icons.business, color: primaryColor, size: 20);
                                },
                              ),
                            ),
                          )
                        else
                          Icon(Icons.business, color: primaryColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _organization?.name ?? 'Organization',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                                'Device Setup Required',
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
                          color: Colors.black.withOpacity(0.1),
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
                            Icons.location_on,
                            size: 40,
                            color: Colors.orange.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Attendance Device Required',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Please select an attendance device to continue using the attendance system.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isInitialLoading ? null : () => _navigateToDeviceSelection(isRequired: true),
                            icon: _isInitialLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.location_on),
                            label: Text(_isInitialLoading ? 'Loading...' : 'Select Location'),
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
                  ),
                ),
              ),
            ],
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
                          color: Colors.black.withOpacity(0.1),
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
                                onPressed: _isInitialLoading ? null : _loadUserData,
                                icon: _isInitialLoading
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                        ),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(_isInitialLoading ? 'Checking...' : 'Check Again'),
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
          if (_breakInfo != null && _breakInfo!['is_currently_on_break'] == true) 
            _buildBreakInfoCard(),
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
              _buildDeviceInfoChip(),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getStatusColor().withOpacity(0.1),
              _getStatusColor().withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _getStatusColor().withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _getStatusColor().withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getStatusColor(),
                          _getStatusColor().withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor().withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getStatusIcon(),
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getCurrentStatusText(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              TimezoneHelper.formatOrgTime(
                                TimezoneHelper.nowInOrgTime(),
                                'HH:mm',
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isRefreshing)
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
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            TimezoneHelper.formatOrgTime(
                              TimezoneHelper.nowInOrgTime(),
                              'EEEE, dd MMMM yyyy',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedDevice != null) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedDevice!.deviceName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (_selectedDevice!.hasValidCoordinates && _gpsPosition != null && _isWithinRadius != null)
                                  ? (_isWithinRadius! ? successColor.withOpacity(0.15) : warningColor.withOpacity(0.15))
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (_selectedDevice!.hasValidCoordinates && _gpsPosition != null && _isWithinRadius != null)
                                      ? (_isWithinRadius! ? Icons.check_circle : Icons.location_off)
                                      : Icons.location_searching,
                                  size: 12,
                                  color: (_selectedDevice!.hasValidCoordinates && _gpsPosition != null && _isWithinRadius != null)
                                      ? (_isWithinRadius! ? successColor : warningColor)
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (_selectedDevice!.hasValidCoordinates && _gpsPosition != null && _isWithinRadius != null)
                                      ? (_isWithinRadius! ? _formatDistance(_distanceToDevice) : 'Out of range')
                                      : 'Locating...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: (_selectedDevice!.hasValidCoordinates && _gpsPosition != null && _isWithinRadius != null)
                                        ? (_isWithinRadius! ? successColor : warningColor)
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_availableActions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: _availableActions.take(2).map((action) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: _availableActions.indexOf(action) == 0 ? 8 : 0,
                          left: _availableActions.indexOf(action) == 1 ? 8 : 0,
                        ),
                        child: ElevatedButton(
                          onPressed: action.isEnabled && !_isInitialLoading && (_isWithinRadius ?? false)
                              ? () => _performAttendance(action.type)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: action.isEnabled && (_isWithinRadius ?? false)
                                ? primaryColor
                                : Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: action.isEnabled && (_isWithinRadius ?? false) ? 4 : 0,
                            shadowColor: primaryColor.withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isInitialLoading && action.isEnabled
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  action.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakInfoCard() {
    if (_breakInfo == null) return const SizedBox.shrink();

    final isOnBreak = _breakInfo!['is_currently_on_break'] == true;
    final totalBreakMinutes = _breakInfo!['total_break_minutes'] as int? ?? 0;
    final breakSessions = _breakInfo!['break_sessions'] as List? ?? [];

    if (!isOnBreak && breakSessions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            children: [
              Icon(
                isOnBreak ? Icons.coffee : Icons.schedule,
                color: isOnBreak ? primaryColor : successColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isOnBreak ? 'Currently on Break' : 'Today\'s Breaks',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (totalBreakMinutes > 0) ...[
            Text(
              'Total break time: ${(totalBreakMinutes ~/ 60)}h ${totalBreakMinutes % 60}m',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (breakSessions.isNotEmpty) ...[
            Text(
              '${breakSessions.length} break session${breakSessions.length > 1 ? 's' : ''} today',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
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
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  DateFormat('MMM yyyy').format(DateTime.now()),
                  style: TextStyle(
                    fontSize: 13,
                    color: primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildStatItem('Presence', '${_getPresenceDays()}', successColor, Icons.check_circle_outline),
              Container(
                width: 1,
                height: 50,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              _buildStatItem('Absence', '${_getAbsenceDays()}', errorColor, Icons.cancel_outlined),
              Container(
                width: 1,
                height: 50,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              _buildStatItem('Lateness', _getLateness(), warningColor, Icons.access_time),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Schedule',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
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
              padding: EdgeInsets.zero,
              itemCount: _timelineItems.length,
              itemBuilder: (context, index) {
                return _buildTimelineItem(_timelineItems[index], index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(TimelineItem item, int index) {
    return Padding(
      padding: EdgeInsets.only(
        top: index == 0 ? 0 : 12,
        bottom: index == _timelineItems.length - 1 ? 0 : 0,
      ),
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
              color: item.status == TimelineStatus.active
                  ? Colors.white
                  : item.status == TimelineStatus.completed
                      ? Colors.white
                      : Colors.grey,
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
        return successColor;
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

// Helper function untuk unawaited futures
void unawaited(Future<void> future) {
  // Intentionally ignore the future
}

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