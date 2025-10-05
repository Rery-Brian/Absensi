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
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => UserDashboardState();
}

class UserDashboardState extends State<UserDashboard> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  final GlobalKey<_DashboardContentState> _dashboardContentKey =
      GlobalKey<_DashboardContentState>();

  void refreshUserProfile() {
    debugPrint('UserDashboard: refreshUserProfile called');
    if (_dashboardContentKey.currentState != null) {
      _dashboardContentKey.currentState!.refreshUserProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _DashboardContent(key: _dashboardContentKey));
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

  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  bool _isLocationUpdating = false;
  bool _isLoading = false;
  
  bool _requiresGpsValidation = true;
  Map<String, String> _workLocationDetails = {
    'type': 'unknown',
    'location': '',
    'city': ''
  };
  bool _isLoadingLocationInfo = false;


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

  Timer? _breakIndicatorTimer;
  Offset _indicatorPosition = const Offset(20, 100);
  bool _isDragging = false;

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
    _startBreakMonitoring();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _periodicLocationTimer?.cancel();
    _breakIndicatorTimer?.cancel();
    super.dispose();
  }

  void _startBreakMonitoring() {
    _breakIndicatorTimer?.cancel();
    _breakIndicatorTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (mounted) {
        if (_breakInfo != null &&
            _breakInfo!['is_currently_on_break'] == true) {
          setState(() {});
        }

        if (timer.tick % 30 == 0) {
          try {
            await _loadBreakInfo();
            if (mounted) setState(() {});
          } catch (e) {
            debugPrint('Error monitoring break: $e');
          }
        }
      }
    });
  }

  void _startPeriodicLocationUpdates() {
    _periodicLocationTimer = Timer.periodic(locationUpdateInterval, (
      timer,
    ) async {
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
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_initialize_services'),
        );
      }
    }
  }

 Future<void> _loadUserData() async {
    setState(() => _isInitialLoading = true);

    try {
      final criticalData = await Future.wait([
        _attendanceService.loadUserProfile(),
        _attendanceService.loadOrganizationMember(),
      ]);

      _userProfile = criticalData[0] as UserProfile?;
      _organizationMember = criticalData[1] as OrganizationMember?;

      if (_userProfile == null || _organizationMember == null) {
        if (mounted) {
          FlushbarHelper.showError(
            context,
            LocalizationHelper.getText('no_user_profile_found'),
          );
        }
        setState(() => _isInitialLoading = false);
        return;
      }

      await Future.wait([_loadOrganizationInfo(), _checkDeviceSelection()]);

      if (_needsDeviceSelection) {
        setState(() => _isInitialLoading = false);
        return;
      }

      setState(() => _isInitialLoading = false);
      _loadSecondaryDataInBackground();
    } catch (e) {
      debugPrint('Error in _loadUserData: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_load_user_data'),
        );
      }
      setState(() => _isInitialLoading = false);
    }
  }


   Future<void> _loadSecondaryDataInBackground() async {
    if (_organizationMember == null) return;

    try {
      await _loadScheduleData();
      
      await Future.wait([
        _loadOrganizationData(),
        _loadBreakInfo(),
        _loadLocationInfo(), // ✅ Tambahkan ini
      ]);

      await _updateAttendanceStatus();
      await _buildDynamicTimeline();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading secondary data: $e');
    }
  }

    Future<void> _loadLocationInfo() async {
    if (_organizationMember == null || _isLoadingLocationInfo) return;
    
    setState(() => _isLoadingLocationInfo = true);
    
    try {
      final requiresGps = await _attendanceService.requiresGpsValidation(_organizationMember!.id);
      final locationDetails = await _attendanceService.getWorkLocationDetails(_organizationMember!.id);
      
      if (mounted) {
        setState(() {
          _requiresGpsValidation = requiresGps;
          _workLocationDetails = locationDetails;
        });
      }
    } catch (e) {
      debugPrint('Error loading location info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocationInfo = false);
      }
    }
  }

  Future<void> _loadBreakInfo() async {
    if (_organizationMember == null) return;

    try {
      _breakInfo = await _attendanceService.getTodayBreakInfo(
        _organizationMember!.id,
      );
      debugPrint('Break info loaded: $_breakInfo');
    } catch (e) {
      debugPrint('Error loading break info: $e');
    }
  }

  Future<void> _checkDeviceSelection() async {
    if (_organizationMember == null) return;

    try {
      final selectionRequired = await _deviceService.isSelectionRequired(
        _organizationMember!.organizationId,
      );

      if (selectionRequired) {
        final selectedDevice = await _deviceService.loadSelectedDevice(
          _organizationMember!.organizationId,
        );

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

      final loadedDevice = await _deviceService.loadSelectedDevice(
        _organizationMember!.organizationId,
      );
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

      unawaited(_updateGpsPositionAndDistance(debounce: false, retryCount: 0));

      setState(() => _needsDeviceSelection = false);
    } catch (e) {
      debugPrint('Error checking location selection: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_check_location'),
        );
      }
    }
  }

  Future<void> _navigateToDeviceSelection({bool isRequired = false}) async {
    if (_organizationMember == null) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          organizationId: _organizationMember!.organizationId,
          organizationName: _organization?.name ?? LocalizationHelper.getText('organization'),
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

      setState(() => _needsDeviceSelection = false);

      await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);

      if (deviceChanged || isRequired) {
        await _forceDataReload();
      }

      if (deviceChanged && mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${LocalizationHelper.getText('location_changed_to')} ${_selectedDevice?.deviceName ?? LocalizationHelper.getText('unknown_device')}',
        );
      }
    }
  }

    Future<void> _forceDataReload() async {
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
      _requiresGpsValidation = true;
      _workLocationDetails = {
        'type': 'unknown',
        'location': '',
        'city': ''
      };
    });

    try {
      await _loadScheduleData();
      await Future.wait([
        _loadOrganizationData(), 
        _loadBreakInfo(),
        _loadLocationInfo(),
      ]);
      await _updateAttendanceStatus();
      await _buildDynamicTimeline();
    } catch (e) {
      debugPrint('Error in force data reload: $e');
      if (mounted) {
        FlushbarHelper.showError(context, '${LocalizationHelper.getText('failed_to_reload_data')}: $e');
      }
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _updateGpsPositionAndDistance({
    bool debounce = true,
    int retryCount = 0,
  }) async {
    if (_isLocationUpdating) return;
    setState(() => _isLocationUpdating = true);

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
        setState(() {
          _gpsPosition = position;
          if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
            _distanceToDevice = Geolocator.distanceBetween(
              _gpsPosition!.latitude,
              _gpsPosition!.longitude,
              _selectedDevice!.latitude!,
              _selectedDevice!.longitude!,
            );
            _isWithinRadius = _attendanceService.isWithinRadius(
              _gpsPosition!,
              _selectedDevice!,
            );
          }
          _isLocationUpdating = false;
        });
      } else if (retryCount < maxGpsRetries) {
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
            _isWithinRadius = _attendanceService.isWithinRadius(
              _gpsPosition!,
              _selectedDevice!,
            );
          }
          _isLocationUpdating = false;
        });
      }
    } catch (e) {
      if (retryCount < maxGpsRetries) {
        await Future.delayed(gpsRetryDelay);
        await _performGpsUpdate(retryCount + 1);
      } else {
        setState(() {
          _distanceToDevice = null;
          _isWithinRadius = null;
          _isLocationUpdating = false;
        });
        if (mounted) {
          FlushbarHelper.showError(context, LocalizationHelper.getText('unable_to_get_precise_location'));
        }
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

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);

    try {
      _userProfile = await _attendanceService.loadUserProfile();

      if (_organizationMember != null) {
        await _checkDeviceSelection();

        if (!_needsDeviceSelection) {
          await Future.wait([
            _loadOrganizationData(),
            _loadScheduleData(),
            _loadBreakInfo(),
            _loadLocationInfo(),
          ]);
          
          await _updateAttendanceStatus();
          await _buildDynamicTimeline();
        }
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        FlushbarHelper.showError(context, LocalizationHelper.getText('failed_to_refresh_data'));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

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
      _currentSchedule = await _attendanceService.loadCurrentSchedule(
        _organizationMember!.id,
      );

      if (_currentSchedule?.workScheduleId != null) {
        final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
        _todayScheduleDetails = await _attendanceService
            .loadWorkScheduleDetails(
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
      if (_todayScheduleDetails != null &&
          _todayScheduleDetails!.isWorkingDay) {
        if (_todayScheduleDetails!.startTime != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.startTime!),
              label: LocalizationHelper.getText('check_in'),
              type: AttendanceActionType.checkIn,
              subtitle: LocalizationHelper.getText('start_work_day'),
            ),
          );
        }

        if (_todayScheduleDetails!.breakStart != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.breakStart!),
              label: LocalizationHelper.getText('break'),
              type: AttendanceActionType.breakOut,
              subtitle: LocalizationHelper.getText('take_a_break'),
            ),
          );
        }

        if (_todayScheduleDetails!.endTime != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.endTime!),
              label: LocalizationHelper.getText('check_out'),
              type: AttendanceActionType.checkOut,
              subtitle: LocalizationHelper.getText('end_work_day'),
            ),
          );
        }
      } else if (_currentSchedule?.shiftId != null) {
        items = await _getScheduleItemsFromShift();
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
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour =
              int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
          final minute =
              int.tryParse(parts[1])?.toString().padLeft(2, '0') ?? '00';
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
        items.add(
          ScheduleItem(
            time: _formatTimeFromDatabase(shiftResponse['start_time']),
            label: LocalizationHelper.getText('check_in'),
            type: AttendanceActionType.checkIn,
            subtitle: LocalizationHelper.getText('start_work_day'),
          ),
        );

        if (shiftResponse['break_duration_minutes'] != null &&
            shiftResponse['break_duration_minutes'] > 0) {
          final startTime = TimeHelper.parseTimeString(
            _formatTimeFromDatabase(shiftResponse['start_time']),
          );
          final endTime = TimeHelper.parseTimeString(
            _formatTimeFromDatabase(shiftResponse['end_time']),
          );

          final totalMinutes =
              TimeHelper.timeToMinutes(endTime) -
              TimeHelper.timeToMinutes(startTime);
          final breakStartMinutes =
              TimeHelper.timeToMinutes(startTime) + (totalMinutes ~/ 2);

          items.add(
            ScheduleItem(
              time: TimeHelper.formatTimeOfDay(
                TimeHelper.minutesToTime(breakStartMinutes),
              ),
              label: LocalizationHelper.getText('break'),
              type: AttendanceActionType.breakOut,
              subtitle: LocalizationHelper.getText('take_a_break'),
            ),
          );
        }

        items.add(
          ScheduleItem(
            time: _formatTimeFromDatabase(shiftResponse['end_time']),
            label: LocalizationHelper.getText('check_out'),
            type: AttendanceActionType.checkOut,
            subtitle: LocalizationHelper.getText('end_work_day'),
          ),
        );
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

        _timelineItems.add(
          TimelineItem(
            time: scheduleItem.time,
            label: scheduleItem.label,
            subtitle: scheduleItem.subtitle,
            type: scheduleItem.type,
            status: status,
            statusDescription: _getStatusDescription(scheduleItem.type, status),
          ),
        );
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error building timeline: $e');
      if (mounted) setState(() {});
    }
  }

  TimelineStatus _getItemStatus(
    ScheduleItem item,
    TimeOfDay scheduleTime,
    TimeOfDay currentTime,
  ) {
    switch (item.type) {
      case AttendanceActionType.checkIn:
        if (_todayAttendanceRecords.isNotEmpty &&
            _todayAttendanceRecords.first.hasCheckedIn) {
          return TimelineStatus.completed;
        }
        break;
      case AttendanceActionType.checkOut:
        if (_todayAttendanceRecords.isNotEmpty &&
            _todayAttendanceRecords.first.hasCheckedOut) {
          return TimelineStatus.completed;
        }
        break;
      case AttendanceActionType.breakOut:
      case AttendanceActionType.breakIn:
        break;
    }

    final currentMinutes = TimeHelper.timeToMinutes(currentTime);
    final scheduleMinutes = TimeHelper.timeToMinutes(scheduleTime);

    if (currentMinutes >= scheduleMinutes - 15 &&
        currentMinutes <= scheduleMinutes + 15) {
      return TimelineStatus.active;
    }

    return TimelineStatus.upcoming;
  }

  String _getStatusDescription(
    AttendanceActionType type,
    TimelineStatus status,
  ) {
    switch (status) {
      case TimelineStatus.completed:
        return LocalizationHelper.getText('completed');
      case TimelineStatus.active:
        return LocalizationHelper.getText('available_now');
      case TimelineStatus.upcoming:
        return LocalizationHelper.getText('not_yet_available');
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
        final hasCheckedInToday = _todayAttendanceRecords.isNotEmpty;
        return hasCheckedInToday
            ? LocalizationHelper.getText('ready_to_check_in_again')
            : LocalizationHelper.getText('ready_to_start');
      case AttendanceStatus.working:
        return LocalizationHelper.getText('currently_working');
      case AttendanceStatus.onBreak:
        return LocalizationHelper.getText('on_break');
      case AttendanceStatus.checkedOut:
        return LocalizationHelper.getText('ready_to_check_in_again');
      case AttendanceStatus.unknown:
        return LocalizationHelper.getText('waiting_for_status');
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
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('organization_member_not_found'),
        );
      }
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
          builder: (context) => BreakPage(organizationMemberId: memberId, deviceId: deviceId),
        ),
      );

      if (result == true || mounted) {
        await _refreshData();
      }
    } catch (e) {
      debugPrint('Error navigating to break page: $e');
      if (mounted) {
        FlushbarHelper.showError(context, LocalizationHelper.getText('failed_to_open_break_page'));
      }
    }
  }

 Future<void> _handleStopBreak() async {
    if (_organizationMember == null || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_breakInfo == null || _breakInfo!['break_start_time'] == null) {
        throw Exception(LocalizationHelper.getText('break_start_time_not_found'));
      }

      final now = TimezoneHelper.nowInOrgTime();
      final utcBreakStart = DateTime.parse(_breakInfo!['break_start_time']);
      final breakStartTime = TimezoneHelper.toOrgTime(utcBreakStart);
      final actualBreakDuration = now.difference(breakStartTime);

      if (actualBreakDuration.isNegative) {
        throw Exception(LocalizationHelper.getText('invalid_break_duration'));
      }

      final memberId = int.tryParse(_organizationMember!.id);
      final deviceId = _selectedDevice != null ? int.tryParse(_selectedDevice!.id) : null;

      if (memberId == null) {
        throw Exception(LocalizationHelper.getText('invalid_member_id'));
      }

      await Supabase.instance.client.from('attendance_logs').insert({
        'organization_member_id': memberId,
        'event_type': 'break_in',
        'event_time': now.toUtc().toIso8601String(),
        'device_id': deviceId,
        'method': 'mobile_app',
        'is_verified': true,
        'verification_method': 'manual',
      });

      await _attendanceService.updateBreakDuration(
        memberId,
        actualBreakDuration.inMinutes,
      );

      setState(() {
        _breakInfo = null;
      });

      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${LocalizationHelper.getText('break_ended_duration')}: ${_formatDuration(actualBreakDuration)}',
        );
      }

      await _refreshData();
    } catch (e) {
      debugPrint('Error ending break: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_end_break')}: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  Future<void> _performAttendance(String actionType) async {
    if (!mounted) return;

    if (actionType == 'break_out') {
      await _navigateToBreakPage();
      return;
    }

    if (actionType == 'check_out') {
      final confirmed = await _showCheckoutConfirmation();
      if (confirmed != true) return;
    }

    setState(() => _isInitialLoading = true);

    try {
      if (_organizationMember == null) {
        if (mounted) {
          FlushbarHelper.showError(context, LocalizationHelper.getText('configuration_error'));
        }
        return;
      }

      // Check apakah butuh validasi GPS berdasarkan work_location
      final requiresGps = await _attendanceService.requiresGpsValidation(
        _organizationMember!.id,
      );
      final locationDetails = await _attendanceService.getWorkLocationDetails(
        _organizationMember!.id,
      );

      debugPrint('=== Attendance Check ===');
      debugPrint('Work Location: ${locationDetails['location']}');
      debugPrint('Type: ${locationDetails['type']}');
      debugPrint('Requires GPS: $requiresGps');

      Position? positionToUse;

      if (requiresGps) {
        // OFFICE WORKER - Harus pakai GPS dan dalam radius
        debugPrint(LocalizationHelper.getText('office_worker_mode'));

        if (_selectedDevice == null || !_selectedDevice!.hasValidCoordinates) {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.getText('attendance_location_not_configured'),
            );
          }
          return;
        }

        final now = DateTime.now();
        final gpsAge = _gpsPosition != null
            ? now.difference(_gpsPosition!.timestamp).inSeconds
            : 999;

        // Update GPS jika belum ada atau sudah lama (>60 detik)
        if (_gpsPosition == null || gpsAge > 60) {
          if (mounted) {
            FlushbarHelper.showInfo(context, LocalizationHelper.getText('getting_your_location'));
          }
          await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
        }

        // Cek lagi setelah update
        if (_gpsPosition == null) {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.getText('unable_to_get_location_gps'),
            );
          }
          return;
        }

        // Validasi radius
        final isWithinRadius = _attendanceService.isWithinRadius(
          _gpsPosition!,
          _selectedDevice!,
        );

        debugPrint('GPS Position: ${_gpsPosition!.latitude}, ${_gpsPosition!.longitude}');
        debugPrint('Device Position: ${_selectedDevice!.latitude}, ${_selectedDevice!.longitude}');
        debugPrint('Distance: ${_distanceToDevice}m');
        debugPrint('Within Radius: $isWithinRadius');

        if (!isWithinRadius) {
          if (mounted) {
            final distance = _formatDistance(_distanceToDevice);
            FlushbarHelper.showError(
              context,
              '${LocalizationHelper.getText('you_are_away_from')} $distance ${_selectedDevice!.deviceName}. ${LocalizationHelper.getText('please_move_closer')}',
            );
          }
          return;
        }

        positionToUse = _gpsPosition;
        debugPrint('✓ GPS validated - ${LocalizationHelper.getText('within_radius')} ${_selectedDevice!.radiusMeters}m');
      } else {
        // FIELD WORKER - Tidak perlu validasi GPS/radius
        debugPrint(LocalizationHelper.getText('field_worker_mode'));

        // Coba ambil GPS untuk logging (opsional), tapi tidak wajib
        try {
          positionToUse = await _attendanceService.getCurrentLocation().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('GPS timeout for field worker - using fallback position');
              return Position(
                longitude: 0.0,
                latitude: 0.0,
                timestamp: DateTime.now(),
                accuracy: 999.0,
                altitude: 0.0,
                heading: 0.0,
                speed: 0.0,
                speedAccuracy: 0.0,
                altitudeAccuracy: 0.0,
                headingAccuracy: 0.0,
              );
            },
          );
          debugPrint('✓ GPS obtained for field worker: ${positionToUse.latitude}, ${positionToUse.longitude}');
        } catch (e) {
          debugPrint('Could not get GPS for field worker (not required): $e');
          // Gunakan posisi dummy untuk field worker
          positionToUse = Position(
            longitude: 0.0,
            latitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 999.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          debugPrint('✓ Using fallback position for field worker');
        }
      }

      // Ambil foto untuk check-in
      String? photoUrl;
      if (actionType == 'check_in') {
        final imagePath = await _takeSelfie();
        if (imagePath == null) {
          if (mounted) {
            FlushbarHelper.showError(context, LocalizationHelper.getText('photo_required_check_in'));
          }
          return;
        }

        if (mounted) {
          FlushbarHelper.showInfo(context, LocalizationHelper.getText('uploading_photo'));
        }

        photoUrl = await _attendanceService.uploadPhoto(imagePath);

        if (photoUrl == null) {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.getText('failed_upload_photo'),
            );
          }
          return;
        }

        File(imagePath).delete().catchError(
          (e) => debugPrint('Failed to delete temp file: $e'),
        );
        debugPrint('✓ Photo uploaded successfully');
      }

      // Simpan attendance record
      debugPrint('Saving attendance: $actionType');
      final success = await _attendanceService.performAttendance(
        type: actionType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: positionToUse!,
        photoUrl: photoUrl ?? '',
        device: requiresGps ? _selectedDevice : null,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      if (success) {
        debugPrint('✓ Attendance saved successfully');
        if (mounted) await _showSuccessAttendancePopup(actionType);

        await _loadBreakInfo();
        unawaited(_refreshData());
        triggerAttendanceHistoryRefresh();
      }
    } catch (e) {
      debugPrint('❌ Error performing attendance: $e');
      if (mounted) {
        String errorMessage = LocalizationHelper.getText('failed_to_perform_attendance');

        if (e.toString().contains('Location')) {
          errorMessage = '${LocalizationHelper.getText('location_error')}: ${e.toString()}';
        } else if (e.toString().contains('schedule')) {
          errorMessage = '${LocalizationHelper.getText('schedule_error')}: ${e.toString()}';
        } else {
          errorMessage = e.toString();
        }

        FlushbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
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
                  child: Icon(Icons.logout, color: warningColor, size: 30),
                ),
                const SizedBox(height: 20),
                Text(
                  LocalizationHelper.getText('confirm_check_out'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  LocalizationHelper.getText('end_work_session'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                        child: Text(
                          LocalizationHelper.getText('cancel'),
                          style: const TextStyle(
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
                        child: Text(
                          LocalizationHelper.getText('yes_check_out'),
                          style: const TextStyle(
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
      if (mounted) {
        FlushbarHelper.showError(context, LocalizationHelper.getText('camera_not_available'));
      }
      return null;
    }

    final hasPermission = await CameraService.requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        FlushbarHelper.showError(context, LocalizationHelper.getText('camera_permission_required'));
      }
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
      if (mounted) {
        FlushbarHelper.showError(context, '${LocalizationHelper.getText('failed_to_take_photo')}: $e');
      }
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

              return SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width * (isLandscape ? 0.6 : 0.85),
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
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
                        padding: EdgeInsets.symmetric(
                          vertical: isLandscape ? 15 : 30,
                          horizontal: 20,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: isLandscape ? 60 : 80,
                              height: isLandscape ? 60 : 80,
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
                                size: isLandscape ? 30 : 40,
                                color: primaryColor,
                              ),
                            ),
                            SizedBox(height: isLandscape ? 12 : 20),
                            Text(
                              LocalizationHelper.getText('attendance_successful'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isLandscape ? 20 : 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isLandscape ? 4 : 8),
                            Text(
                              _getAttendanceTypeLabel(type),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: isLandscape ? 14 : 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: isLandscape ? 4 : 8),
                            Text(
                              TimezoneHelper.formatAttendanceDateTime(orgTime),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: isLandscape ? 12 : 14,
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
                            padding: EdgeInsets.symmetric(
                              vertical: isLandscape ? 12 : 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            LocalizationHelper.getText('ok'),
                            style: TextStyle(
                              fontSize: isLandscape ? 14 : 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: isLandscape ? 15 : 20),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _getAttendanceTypeLabel(String type) {
    switch (type) {
      case 'check_in':
        return LocalizationHelper.getText('check_in_completed');
      case 'check_out':
        return LocalizationHelper.getText('check_out_completed');
      case 'break_out':
        return LocalizationHelper.getText('break_started');
      case 'break_in':
        return LocalizationHelper.getText('work_resumed');
      default:
        return LocalizationHelper.getText('attendance_recorded');
    }
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
    return LocalizationHelper.getText('user');
  }


 String _formatDistance(double? distanceInMeters) {
    if (distanceInMeters == null) return LocalizationHelper.getText('unknown_distance');
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()}${LocalizationHelper.getText('meters_away')}';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}${LocalizationHelper.getText('km_away')}';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    if (duration.inHours > 0) {
      return "${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Duration _getBreakElapsedTime() {
    if (_breakInfo == null ||
        _breakInfo!['is_currently_on_break'] != true ||
        _breakInfo!['break_start_time'] == null) {
      return Duration.zero;
    }

    try {
      final utcBreakStart = DateTime.parse(_breakInfo!['break_start_time']);
      final breakStartTime = TimezoneHelper.toOrgTime(utcBreakStart);
      final now = TimezoneHelper.nowInOrgTime();
      final elapsed = now.difference(breakStartTime);

      return elapsed.isNegative ? Duration.zero : elapsed;
    } catch (e) {
      debugPrint('Error calculating break elapsed time: $e');
      debugPrint('Break info: $_breakInfo');
      return Duration.zero;
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
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Text(
                LocalizationHelper.getText('no_location'),
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, color: Colors.orange, size: 16),
            ],
          ),
        ),
      );
    }

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
                deviceName.length > 10 ? deviceName.substring(0, 10) + '…' : deviceName,
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


  Widget _buildBreakIndicator() {
    if (_breakInfo == null || _breakInfo!['is_currently_on_break'] != true) {
      return const SizedBox.shrink();
    }

    final elapsedTime = _getBreakElapsedTime();
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _indicatorPosition.dx,
      top: _indicatorPosition.dy,
      child: GestureDetector(
        onPanStart: (details) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            double newX = _indicatorPosition.dx + details.delta.dx;
            double newY = _indicatorPosition.dy + details.delta.dy;

            newX = newX.clamp(0.0, screenSize.width - 180);
            newY = newY.clamp(50.0, screenSize.height - 200);

            _indicatorPosition = Offset(newX, newY);
          });
        },
        onPanEnd: (details) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 160,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withOpacity(0.9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDragging ? 0.3 : 0.2),
                blurRadius: _isDragging ? 20 : 15,
                offset: Offset(0, _isDragging ? 8 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _navigateToBreakPage(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.coffee,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            LocalizationHelper.getText('on_break_indicator'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _formatDuration(elapsedTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _isLoading ? null : () => _handleStopBreak(),
                          child: Center(
                            child: _isLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: primaryColor,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    LocalizationHelper.getText('stop_break'),
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _refreshData,
                  color: primaryColor,
                  backgroundColor: Colors.white,
                  child: _buildMainContent(displayName),
                ),
                _buildBreakIndicator(),
              ],
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
                                  return Icon(
                                    Icons.business,
                                    color: primaryColor,
                                    size: 20,
                                  );
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
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 28,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${LocalizationHelper.getText('hello')}, $displayName",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Text(
                                'Location Setup Required',
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
                          'Attendance Location Required',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Please select an attendance location to continue using the attendance system.',
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
                            onPressed: _isInitialLoading
                                ? null
                                : () => _navigateToDeviceSelection(
                                    isRequired: true,
                                  ),
                            icon: _isInitialLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.location_on),
                            label: Text(
                              _isInitialLoading
                                  ? 'Loading...'
                                  : 'Select Location',
                            ),
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
                        Icon(Icons.apps, color: primaryColor, size: 28),
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
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 28,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${LocalizationHelper.getText('hello')}, $displayName",
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
                                onPressed: _isInitialLoading
                                    ? null
                                    : _loadUserData,
                                icon: _isInitialLoading
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                primaryColor,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.refresh),
                                label: Text(
                                  _isInitialLoading
                                      ? LocalizationHelper.getText('checking')
                                      : LocalizationHelper.getText(
                                          'check_again',
                                        ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  side: BorderSide(color: primaryColor),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
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
                      child: Text(
                        _organization?.name ?? 'Unknown Organization',
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
              ),
              // ✅ Tambahkan badge work location di sini
              Row(
                children: [
                  _buildDeviceInfoChip(),
                  const SizedBox(width: 8),
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
                      "${LocalizationHelper.getText('hello')}, $displayName",
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
  final isOnBreak = _breakInfo != null && _breakInfo!['is_currently_on_break'] == true;
  final filteredActions = isOnBreak
      ? _availableActions.where((action) => action.type != 'break_out').toList()
      : _availableActions;

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
        border: Border.all(color: _getStatusColor().withOpacity(0.3), width: 1.5),
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
                      colors: [_getStatusColor(), _getStatusColor().withOpacity(0.8)],
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
                  child: Icon(_getStatusIcon(), color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getCurrentStatusText(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            TimezoneHelper.formatOrgTime(TimezoneHelper.nowInOrgTime(), 'HH:mm'),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
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
                      Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          TimezoneHelper.formatOrgTime(TimezoneHelper.nowInOrgTime(), 'EEEE, dd MMMM yyyy'),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedDevice != null) ...[
                    const SizedBox(height: 8),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    _isLoadingLocationInfo
                        ? const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : !_requiresGpsValidation
                            ? Row(
                                children: [
                                  Icon(Icons.explore, size: 14, color: successColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _workLocationDetails['city']?.isNotEmpty == true
                                          ? '${LocalizationHelper.getText('field_work_in')} ${_workLocationDetails['city']} - ${LocalizationHelper.getText('gps_not_required')}'
                                          : LocalizationHelper.getText('field_work_gps_not_required'),
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: successColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, size: 12, color: successColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          LocalizationHelper.getText('ready'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: successColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedDevice!.deviceName,
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
                                              ? (_isWithinRadius! ? _formatDistance(_distanceToDevice) : LocalizationHelper.getText('out_of_range'))
                                              : LocalizationHelper.getText('locating'),
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
                  ] else ...[
                    const SizedBox(height: 8),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.warning, size: 14, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            LocalizationHelper.getText('no_attendance_location_selected'),
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _navigateToDeviceSelection(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, size: 12, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(
                                  LocalizationHelper.getText('select_location'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (filteredActions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: filteredActions.take(2).map((action) {
                        bool shouldEnable = action.isEnabled && !_isInitialLoading;

                        if (_requiresGpsValidation) {
                          shouldEnable = shouldEnable && (_isWithinRadius ?? false);
                        }

                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: filteredActions.indexOf(action) == 0 ? 8 : 0,
                              left: filteredActions.indexOf(action) == 1 ? 8 : 0,
                            ),
                            child: ElevatedButton(
                              onPressed: shouldEnable ? () => _performAttendance(action.type) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: shouldEnable ? primaryColor : Colors.grey.shade300,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: shouldEnable ? 4 : 0,
                                shadowColor: primaryColor.withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isInitialLoading && action.isEnabled
                                  ? const SizedBox(
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
          ],
        ),
      ),
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
              Text(
                LocalizationHelper.getText('overview'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
              _buildStatItem(
                LocalizationHelper.getText('presence'),
                '${_getPresenceDays()}',
                successColor,
                Icons.check_circle_outline,
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              _buildStatItem(
                LocalizationHelper.getText('absence'),
                '${_getAbsenceDays()}',
                errorColor,
                Icons.cancel_outlined,
              ),
              Container(
                width: 1,
                height: 50,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              _buildStatItem(
                LocalizationHelper.getText('lateness'),
                _getLateness(),
                warningColor,
                Icons.access_time,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
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
              child: Icon(icon, color: color, size: 24),
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
          Text(
            LocalizationHelper.getText('todays_schedule'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          if (_timelineItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20), // ini masih boleh const
                child: Text(
                  LocalizationHelper.getText('no_schedule_available'),
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getItemStatusColor(
                          item.status,
                        ).withOpacity(0.1),
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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

void unawaited(Future<void> future) {}

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

  SimpleOrganization({required this.id, required this.name, this.logoUrl});
}

enum AttendanceActionType { checkIn, checkOut, breakOut, breakIn }

enum TimelineStatus { completed, active, upcoming }
