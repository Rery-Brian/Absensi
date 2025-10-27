import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';
import '../services/attendance_service.dart';

class BreakPage extends StatefulWidget {
  final int organizationMemberId;
  final int? deviceId;

  const BreakPage({
    super.key,
    required this.organizationMemberId,
    this.deviceId,
  });

  @override
  State<BreakPage> createState() => _BreakPageState();
}

class _BreakPageState extends State<BreakPage> with WidgetsBindingObserver {
  final AttendanceService _attendanceService = AttendanceService();
  Timer? _timer;
  Timer? _warningTimer;
  bool _isLoading = false;
  bool _isOnBreak = false;
  DateTime? _breakStartTime;
  DateTime? _scheduledBreakStart;
  DateTime? _scheduledBreakEnd;
  Duration _elapsedTime = Duration.zero;
  Duration _maxBreakDuration = const Duration(hours: 1);
  String _breakStartTimeText = '';
  int _totalBreakMinutesToday = 0;
  int _currentBreakMinutes = 0;
  List<Map<String, dynamic>> _todayBreakSessions = [];
  bool _showWarning = false;
  bool _hasExceeded = false;
  Position? _currentLocation;

  // Colors
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color backgroundColor = Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBreakData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _warningTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isOnBreak) {
      _updateElapsedTime();
    }
  }

  Future<void> _loadBreakData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        _loadTodayBreakSchedule(),
        _loadTodayBreakSessions(),
        _checkCurrentBreakStatus(),
      ]);

      if (_isOnBreak && _breakStartTime != null) {
        _startTimer();
      }
    } catch (e) {
      debugPrint('Error loading break data: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_load_break_data'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTodayBreakSchedule() async {
    try {
      final today = TimezoneHelper.nowInOrgTime();
      final dayOfWeek = today.weekday == 7 ? 0 : today.weekday;

      final scheduleResponse = await Supabase.instance.client
          .from('member_schedules')
          .select('''
            work_schedule_id,
            work_schedules!inner(
              work_schedule_details!inner(
                break_start,
                break_end,
                break_duration_minutes,
                day_of_week
              )
            )
          ''')
          .eq('organization_member_id', widget.organizationMemberId)
          .eq('is_active', true)
          .lte('effective_date', today.toIso8601String().split('T')[0])
          .order('effective_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (scheduleResponse != null && scheduleResponse['work_schedule_id'] != null) {
        final workScheduleDetails = scheduleResponse['work_schedules']['work_schedule_details'] as List;
        final todaySchedule = workScheduleDetails.firstWhere(
          (detail) => detail['day_of_week'] == dayOfWeek,
          orElse: () => null,
        );

        if (todaySchedule != null) {
          if (todaySchedule['break_start'] != null && todaySchedule['break_end'] != null) {
            _scheduledBreakStart = _parseTimeToDateTime(todaySchedule['break_start'], today);
            _scheduledBreakEnd = _parseTimeToDateTime(todaySchedule['break_end'], today);
          }
          
          if (todaySchedule['break_duration_minutes'] != null) {
            _maxBreakDuration = Duration(minutes: todaySchedule['break_duration_minutes']);
          } else if (_scheduledBreakStart != null && _scheduledBreakEnd != null) {
            _maxBreakDuration = _scheduledBreakEnd!.difference(_scheduledBreakStart!);
          }

          debugPrint('Break schedule loaded: ${todaySchedule['break_start']} - ${todaySchedule['break_end']} (${_maxBreakDuration.inMinutes} min)');
        }
      }

      if (_scheduledBreakStart == null || _scheduledBreakEnd == null) {
        final now = TimezoneHelper.nowInOrgTime();
        _scheduledBreakStart = DateTime(now.year, now.month, now.day, 12, 0);
        _scheduledBreakEnd = DateTime(now.year, now.month, now.day, 13, 0);
        _maxBreakDuration = const Duration(hours: 1);
        debugPrint('Using default break schedule: 12:00 - 13:00 (60 min)');
      }
    } catch (e) {
      debugPrint('Error loading break schedule: $e');
      final now = TimezoneHelper.nowInOrgTime();
      _scheduledBreakStart = DateTime(now.year, now.month, now.day, 12, 0);
      _scheduledBreakEnd = DateTime(now.year, now.month, now.day, 13, 0);
      _maxBreakDuration = const Duration(hours: 1);
    }
  }

  DateTime _parseTimeToDateTime(String timeString, DateTime referenceDate) {
    final parts = timeString.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(referenceDate.year, referenceDate.month, referenceDate.day, hour, minute);
  }

  Future<void> _loadTodayBreakSessions() async {
    try {
      final today = TimezoneHelper.nowInOrgTime();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      final logsResponse = await Supabase.instance.client
          .from('attendance_logs')
          .select('event_type, event_time')
          .eq('organization_member_id', widget.organizationMemberId)
          .gte('event_time', '${todayStr}T00:00:00Z')
          .lte('event_time', '${todayStr}T23:59:59Z')
          .inFilter('event_type', ['break_out', 'break_in'])
          .order('event_time', ascending: true);

      final logs = logsResponse as List;
      _todayBreakSessions.clear();
      _totalBreakMinutesToday = 0;

      DateTime? currentBreakStart;
      for (var log in logs) {
        if (log['event_type'] == 'break_out') {
          final utcTime = DateTime.parse(log['event_time']);
          currentBreakStart = TimezoneHelper.toOrgTime(utcTime);
        } else if (log['event_type'] == 'break_in' && currentBreakStart != null) {
          final utcTime = DateTime.parse(log['event_time']);
          final breakEnd = TimezoneHelper.toOrgTime(utcTime);
          
          final duration = breakEnd.difference(currentBreakStart).inMinutes;
          _totalBreakMinutesToday += duration;
          
          _todayBreakSessions.add({
            'start': currentBreakStart,
            'end': breakEnd,
            'duration': duration,
          });
          currentBreakStart = null;
        }
      }

      debugPrint('Total completed break minutes today: $_totalBreakMinutesToday');
      debugPrint('Break sessions: ${_todayBreakSessions.length}');
    } catch (e) {
      debugPrint('Error loading break sessions: $e');
    }
  }

  Future<void> _checkCurrentBreakStatus() async {
    try {
      final today = TimezoneHelper.nowInOrgTime();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      final logsResponse = await Supabase.instance.client
          .from('attendance_logs')
          .select('event_type, event_time')
          .eq('organization_member_id', widget.organizationMemberId)
          .gte('event_time', '${todayStr}T00:00:00Z')
          .lte('event_time', '${todayStr}T23:59:59Z')
          .inFilter('event_type', ['break_out', 'break_in'])
          .order('event_time', ascending: false)
          .limit(1);

      final logs = logsResponse as List;

      if (logs.isNotEmpty) {
        final lastLog = logs.first;

        if (lastLog['event_type'] == 'break_out') {
          _isOnBreak = true;
          
          final utcTime = DateTime.parse(lastLog['event_time']);
          _breakStartTime = TimezoneHelper.toOrgTime(utcTime);
          
          _breakStartTimeText = TimezoneHelper.formatOrgTime(_breakStartTime!, 'HH.mm');
          _updateElapsedTime();
          debugPrint('User is currently on break since: $_breakStartTimeText');
        } else {
          _isOnBreak = false;
          debugPrint('User is not on break');
        }
      }
    } catch (e) {
      debugPrint('Error checking break status: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_check_break_status'),
        );
      }
    }
  }

  void _updateElapsedTime() {
    if (_breakStartTime != null) {
      final now = TimezoneHelper.nowInOrgTime();
      _elapsedTime = now.difference(_breakStartTime!);
      _currentBreakMinutes = _elapsedTime.inMinutes;
      
      final warningThreshold = _maxBreakDuration.inMinutes - 5;
      _showWarning = _currentBreakMinutes >= warningThreshold && _currentBreakMinutes < _maxBreakDuration.inMinutes;
      _hasExceeded = _currentBreakMinutes > _maxBreakDuration.inMinutes;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      _updateElapsedTime();

      if (_showWarning && !_hasExceeded) {
        _scheduleWarningNotification();
      }

      setState(() {});
    });
  }

  void _scheduleWarningNotification() {
    _warningTimer?.cancel();
    _warningTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _showWarning && !_hasExceeded) {
        _showBreakWarningDialog();
      }
    });
  }

  bool _canStartBreak() {
    final now = TimezoneHelper.nowInOrgTime();
    
    if (_scheduledBreakStart != null) {
      final earliestStart = _scheduledBreakStart!.subtract(const Duration(minutes: 30));
      final latestStart = _scheduledBreakEnd!;
      
      if (now.isBefore(earliestStart) || now.isAfter(latestStart)) {
        return false;
      }
    }

    final remainingBreakMinutes = _maxBreakDuration.inMinutes - _totalBreakMinutesToday;
    if (remainingBreakMinutes <= 5) {
      return false;
    }

    return true;
  }

  String _getBreakStatusMessage() {
    if (_isOnBreak) {
      if (_hasExceeded) {
        return LocalizationHelper.getText('break_time_exceeded');
      } else if (_showWarning) {
        return LocalizationHelper.getText('break_time_almost_over');
      }
      return LocalizationHelper.getText('break_in_progress');
    }

    if (!_canStartBreak()) {
      final now = TimezoneHelper.nowInOrgTime();
      
      if (_scheduledBreakStart != null && now.isBefore(_scheduledBreakStart!.subtract(const Duration(minutes: 30)))) {
        return '${LocalizationHelper.getText('break_available_at')} ${DateFormat('HH.mm', 'id_ID').format(_scheduledBreakStart!)}';
      }
      
      final remainingBreakMinutes = _maxBreakDuration.inMinutes - _totalBreakMinutesToday;
      if (remainingBreakMinutes <= 5) {
        return LocalizationHelper.getText('daily_break_time_exhausted');
      }
      
      if (_scheduledBreakStart != null && now.isAfter(_scheduledBreakEnd!)) {
        return LocalizationHelper.getText('break_time_has_passed');
      }
    }

    return LocalizationHelper.getText('break_available');
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentLocation = await _attendanceService.getCurrentLocation();
      debugPrint('Location obtained for break: ${_currentLocation?.latitude}, ${_currentLocation?.longitude}');
    } catch (e) {
      debugPrint('Failed to get location for break: $e');
    }
  }

  Future<void> _startBreak() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _getCurrentLocation();
      
      final now = TimezoneHelper.nowInOrgTime();

      await Supabase.instance.client.from('attendance_logs').insert({
        'organization_member_id': widget.organizationMemberId,
        'event_type': 'break_out',
        'event_time': now.toUtc().toIso8601String(),
        'device_id': widget.deviceId,
        'method': 'mobile_app',
        'location': _currentLocation != null ? {
          'latitude': _currentLocation!.latitude,
          'longitude': _currentLocation!.longitude,
        } : null,
        'is_verified': true,
        'verification_method': 'manual',
      });

      _isOnBreak = true;
      _breakStartTime = now;
      _breakStartTimeText = TimezoneHelper.formatOrgTime(now, 'HH.mm');
      _elapsedTime = Duration.zero;
      _currentBreakMinutes = 0;
      _showWarning = false;
      _hasExceeded = false;

      _startTimer();
      
      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          LocalizationHelper.getText('break_started_successfully'),
        );
      }
      
      debugPrint('Break started at: $_breakStartTimeText');
    } catch (e) {
      debugPrint('Error starting break: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_start_break'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _endBreak() async {
    if (_breakStartTime == null) {
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('break_start_time_not_found'),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _getCurrentLocation();
      
      final now = TimezoneHelper.nowInOrgTime();
      final actualBreakDuration = now.difference(_breakStartTime!);
      
      final breakStartForSummary = _breakStartTime!;
      final breakEndForSummary = now;
      final durationForSummary = actualBreakDuration;
      final maxDurationForSummary = _maxBreakDuration;
      final totalBreakForSummary = _totalBreakMinutesToday;

      await Supabase.instance.client.from('attendance_logs').insert({
        'organization_member_id': widget.organizationMemberId,
        'event_type': 'break_in',
        'event_time': now.toUtc().toIso8601String(),
        'device_id': widget.deviceId,
        'method': 'mobile_app',
        'location': _currentLocation != null ? {
          'latitude': _currentLocation!.latitude,
          'longitude': _currentLocation!.longitude,
        } : null,
        'is_verified': true,
        'verification_method': 'manual',
      });

      debugPrint('Break-in log created successfully');

      try {
        await _attendanceService.updateBreakDuration(
          widget.organizationMemberId,
          actualBreakDuration.inMinutes
        );
        debugPrint('Break duration updated: ${actualBreakDuration.inMinutes} minutes');
      } catch (e) {
        debugPrint('Warning: Failed to update break duration: $e');
      }

      _timer?.cancel();
      _warningTimer?.cancel();

      if (mounted) {
        setState(() {
          _isOnBreak = false;
          _breakStartTime = null;
          _elapsedTime = Duration.zero;
          _currentBreakMinutes = 0;
          _showWarning = false;
          _hasExceeded = false;
          _isLoading = false;
        });
      }

      if (mounted) {
        await _showBreakSummary(
          breakStartForSummary,
          breakEndForSummary,
          durationForSummary,
          maxDurationForSummary,
          totalBreakForSummary,
        );
      }
      
      debugPrint('✓ Break ended successfully. Duration: ${actualBreakDuration.inMinutes}m');
    } catch (e) {
      debugPrint('❌ Error ending break: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_end_break')}: ${e.toString()}',
          duration: const Duration(seconds: 5),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showBreakWarningDialog() async {
    if (!mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: warningColor,
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                LocalizationHelper.getText('break_warning'),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: Text(
            LocalizationHelper.getText('break_warning_message'),
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                LocalizationHelper.getText('continue_break'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _endBreak();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
              child: Text(
                LocalizationHelper.getText('end_break_now'),
                style: TextStyle(color: warningColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBreakSummary(
    DateTime breakStartTime,
    DateTime breakEndTime,
    Duration actualDuration,
    Duration maxDuration,
    int previousBreakMinutes,
  ) async {
    if (!mounted) return;

    final wasExceeded = actualDuration.inMinutes > maxDuration.inMinutes;
    final summaryColor = wasExceeded ? warningColor : successColor;
    final totalTodayMinutes = previousBreakMinutes + actualDuration.inMinutes;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [backgroundColor, backgroundColor.withOpacity(0.95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: summaryColor, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: summaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      wasExceeded ? Icons.warning : Icons.coffee,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    wasExceeded 
                        ? LocalizationHelper.getText('break_completed_exceeded')
                        : LocalizationHelper.getText('break_summary'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow(
                          LocalizationHelper.getText('started'),
                          TimezoneHelper.formatOrgTime(breakStartTime, 'HH.mm'),
                        ),
                        _buildSummaryRow(
                          LocalizationHelper.getText('ended'),
                          TimezoneHelper.formatOrgTime(breakEndTime, 'HH.mm'),
                        ),
                        _buildSummaryRow(
                          LocalizationHelper.getText('duration'),
                          _formatDuration(actualDuration),
                        ),
                        _buildSummaryRow(
                          LocalizationHelper.getText('allowed'),
                          _formatDuration(maxDuration),
                        ),
                        if (wasExceeded)
                          _buildSummaryRow(
                            LocalizationHelper.getText('overtime'),
                            _formatDuration(Duration(minutes: actualDuration.inMinutes - maxDuration.inMinutes)),
                            isWarning: true,
                          ),
                        _buildSummaryRow(
                          LocalizationHelper.getText('total_today'),
                          _formatDuration(Duration(minutes: totalTodayMinutes)),
                        ),
                      ],
                    ),
                  ),
                  if (wasExceeded) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: warningColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: warningColor.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info, color: warningColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LocalizationHelper.getText('break_exceeded_notice'),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).pop(true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: summaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            LocalizationHelper.getText('back_to_dashboard'),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isWarning ? warningColor : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    if (duration.inHours > 0) {
      return "${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Color _getStatusColor() {
    if (_hasExceeded) return errorColor;
    if (_showWarning) return warningColor;
    if (_isOnBreak) return primaryColor;
    return successColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading && !_isOnBreak
                    ? const Center(child: CircularProgressIndicator(color: primaryColor))
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _buildBreakContent(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Text(
            LocalizationHelper.getText('break_time'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getStatusColor().withOpacity(0.5)),
            ),
            child: Text(
              _isOnBreak 
                  ? LocalizationHelper.getText('on_break_status')
                  : LocalizationHelper.getText('available'),
              style: TextStyle(
                color: _getStatusColor(),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: !_isOnBreak ? _buildStartBreakSection() : _buildActiveBreakSection(),
    );
  }

  Widget _buildStartBreakSection() {
    final canStart = _canStartBreak();
    final remainingBreakMinutes = _maxBreakDuration.inMinutes - _totalBreakMinutesToday;

    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: successColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: successColor.withOpacity(0.5), width: 2),
          ),
          child: const Icon(
            Icons.coffee,
            color: successColor,
            size: 60,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          LocalizationHelper.getText('break_schedule'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        if (_scheduledBreakStart != null && _scheduledBreakEnd != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${DateFormat('HH.mm', 'id_ID').format(_scheduledBreakStart!)} - ${DateFormat('HH.mm', 'id_ID').format(_scheduledBreakEnd!)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '${LocalizationHelper.getText('max_duration')}: ${_formatDuration(_maxBreakDuration)}',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        if (_totalBreakMinutesToday > 0) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${LocalizationHelper.getText('break_taken_today')}:',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      _formatDuration(Duration(minutes: _totalBreakMinutesToday)),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${LocalizationHelper.getText('remaining')}:',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      _formatDuration(Duration(minutes: remainingBreakMinutes)),
                      style: TextStyle(
                        color: remainingBreakMinutes <= 5 ? warningColor : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canStart && !_isLoading ? _startBreak : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canStart ? successColor : Colors.grey[700],
              disabledBackgroundColor: Colors.grey[800],
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: canStart ? 4 : 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    canStart 
                        ? LocalizationHelper.getText('start_break')
                        : LocalizationHelper.getText('not_available'),
                    style: TextStyle(
                      color: canStart ? Colors.white : Colors.grey[500],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                canStart ? Icons.info_outline : Icons.warning_outlined,
                color: canStart ? Colors.blue : warningColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getBreakStatusMessage(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        if (_todayBreakSessions.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildBreakSessionsHistory(),
        ],
      ],
    );
  }

  Widget _buildActiveBreakSection() {
    final progress = _currentBreakMinutes / _maxBreakDuration.inMinutes;
    final progressColor = _hasExceeded ? errorColor : _showWarning ? warningColor : primaryColor;

    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: progressColor.withOpacity(0.5),
              width: 3,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 8,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  backgroundColor: Colors.white.withOpacity(0.1),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(_elapsedTime),
                    style: TextStyle(
                      color: progressColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocalizationHelper.getText('elapsed'),
                    style: TextStyle(
                      color: progressColor.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${LocalizationHelper.getText('started_at')}:',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  Text(
                    TimezoneHelper.formatOrgTime(_breakStartTime!, 'HH.mm'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${LocalizationHelper.getText('maximum')}:',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    _formatDuration(_maxBreakDuration),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        if (_hasExceeded) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: errorColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: errorColor.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, color: errorColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    LocalizationHelper.getText('break_exceeded_alert'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_showWarning) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: warningColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: warningColor.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, color: warningColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    LocalizationHelper.getText('break_almost_over_notice'),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 32),
        
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _endBreak,
            style: ElevatedButton.styleFrom(
              backgroundColor: _hasExceeded ? errorColor : primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _hasExceeded 
                        ? LocalizationHelper.getText('end_break_overdue')
                        : LocalizationHelper.getText('end_break'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBreakSessionsHistory() {
    if (_todayBreakSessions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocalizationHelper.getText('todays_break_sessions'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _todayBreakSessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final session = _todayBreakSessions[index];
              final start = session['start'] as DateTime;
              final end = session['end'] as DateTime;
              final duration = session['duration'] as int;
              
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.coffee, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('HH.mm', 'id_ID').format(start),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const Text(
                          ' - ',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        Text(
                          DateFormat('HH.mm', 'id_ID').format(end),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                    Text(
                      '${duration}${LocalizationHelper.getText('minutes_short')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}