import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../helpers/timezone_helper.dart';
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

class _BreakPageState extends State<BreakPage> {
  final AttendanceService _attendanceService = AttendanceService();
  Timer? _timer;
  bool _isLoading = false;
  bool _isOnBreak = false;
  DateTime? _breakStartTime;
  DateTime? _scheduledBreakStart;
  DateTime? _scheduledBreakEnd;
  Duration _remainingTime = Duration.zero;
  Duration _totalBreakDuration = Duration.zero;
  String _breakStartTimeText = '';

  @override
  void initState() {
    super.initState();
    _loadBreakData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBreakData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadTodayBreakSchedule();
      await _checkCurrentBreakStatus();

      if (_isOnBreak && _breakStartTime != null) {
        _calculateRemainingTime();
        _startTimer();
      }
    } catch (e) {
      debugPrint('Error loading break data: $e');
      _showSnackBar('Failed to load break data. Please try again.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTodayBreakSchedule() async {
    try {
      final today = TimezoneHelper.nowInOrgTime();
      final dayOfWeek = today.weekday == 7 ? 0 : today.weekday;

      final memberResponse = await Supabase.instance.client
          .from('organization_members')
          .select('organization_id')
          .eq('id', widget.organizationMemberId)
          .single();

      final scheduleResponse = await Supabase.instance.client
          .from('member_schedules')
          .select('''
            work_schedule_id,
            shift_id,
            work_schedules!inner(
              id,
              work_schedule_details!inner(
                break_start,
                break_end,
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

        if (todaySchedule != null &&
            todaySchedule['break_start'] != null &&
            todaySchedule['break_end'] != null) {
          final breakStartStr = todaySchedule['break_start'] as String;
          final breakEndStr = todaySchedule['break_end'] as String;

          _scheduledBreakStart = _parseTimeToDateTime(breakStartStr, today);
          _scheduledBreakEnd = _parseTimeToDateTime(breakEndStr, today);
          _totalBreakDuration = _scheduledBreakEnd!.difference(_scheduledBreakStart!);

          debugPrint('Break schedule: $breakStartStr - $breakEndStr');
        }
      }

      if (_scheduledBreakStart == null || _scheduledBreakEnd == null) {
        final now = TimezoneHelper.nowInOrgTime();
        _scheduledBreakStart = DateTime(now.year, now.month, now.day, 12, 0);
        _scheduledBreakEnd = DateTime(now.year, now.month, now.day, 13, 0);
        _totalBreakDuration = Duration(hours: 1);
        debugPrint('Using default break schedule: 12:00 - 13:00');
      }
    } catch (e) {
      debugPrint('Error loading break schedule: $e');
      final now = TimezoneHelper.nowInOrgTime();
      _scheduledBreakStart = DateTime(now.year, now.month, now.day, 12, 0);
      _scheduledBreakEnd = DateTime(now.year, now.month, now.day, 13, 0);
      _totalBreakDuration = Duration(hours: 1);
    }
  }

  DateTime _parseTimeToDateTime(String timeStr, DateTime baseDate) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
  }

  Future<void> _checkCurrentBreakStatus() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(TimezoneHelper.nowInOrgTime());

      final logsResponse = await Supabase.instance.client
          .from('attendance_logs')
          .select('event_type, event_time')
          .eq('organization_member_id', widget.organizationMemberId)
          .gte('event_time', '${today}T00:00:00')
          .lte('event_time', '${today}T23:59:59')
          .inFilter('event_type', ['break_out', 'break_in'])
          .order('event_time', ascending: true);

      final logs = logsResponse as List;

      if (logs.isNotEmpty) {
        final lastLog = logs.last;

        if (lastLog['event_type'] == 'break_out') {
          _isOnBreak = true;
          _breakStartTime = DateTime.parse(lastLog['event_time']);
          _breakStartTimeText = DateFormat('HH:mm').format(_breakStartTime!);
          debugPrint('User is on break since: $_breakStartTimeText');
        } else if (lastLog['event_type'] == 'break_in') {
          _isOnBreak = false;
          debugPrint('Break has ended');
        }
      }
    } catch (e) {
      debugPrint('Error checking break status: $e');
      _showSnackBar('Failed to check break status. Please try again.', isError: true);
    }
  }

  void _calculateRemainingTime() {
    if (_scheduledBreakEnd == null) return;

    final now = TimezoneHelper.nowInOrgTime();
    if (now.isBefore(_scheduledBreakEnd!)) {
      _remainingTime = _scheduledBreakEnd!.difference(now);
    } else {
      _remainingTime = Duration.zero;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (!mounted) return;

      _calculateRemainingTime();

      if (_remainingTime.inSeconds <= 0) {
        _timer?.cancel();
        if (_isOnBreak) {
          _autoEndBreak();
        }
      }

      setState(() {});
    });
  }

  Future<void> _startBreak() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final now = TimezoneHelper.nowInOrgTime();

      await Supabase.instance.client
          .from('attendance_logs')
          .insert({
        'organization_member_id': widget.organizationMemberId,
        'event_type': 'break_out',
        'event_time': now.toIso8601String(),
        'device_id': widget.deviceId,
        'method': 'mobile_app',
        'location': null,
        'is_verified': true,
        'verification_method': 'manual',
      });

      _isOnBreak = true;
      _breakStartTime = now;
      _breakStartTimeText = DateFormat('HH:mm').format(now);

      if (now.isBefore(_scheduledBreakEnd!)) {
        _remainingTime = _scheduledBreakEnd!.difference(now);
      } else {
        _remainingTime = Duration.zero;
      }

      _startTimer();

      _showSnackBar('Break started successfully');
    } catch (e) {
      debugPrint('Error starting break: $e');
      _showSnackBar('Failed to start break. Please try again.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _endBreak({bool isAutoEnd = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final now = TimezoneHelper.nowInOrgTime();

      await Supabase.instance.client
          .from('attendance_logs')
          .insert({
        'organization_member_id': widget.organizationMemberId,
        'event_type': 'break_in',
        'event_time': now.toIso8601String(),
        'device_id': widget.deviceId,
        'method': 'mobile_app',
        'location': null,
        'is_verified': true,
        'verification_method': isAutoEnd ? 'auto' : 'manual',
      });

      _timer?.cancel();
      _isOnBreak = false;

      if (_breakStartTime != null) {
        final actualBreakDuration = now.difference(_breakStartTime!);
        await _attendanceService.updateBreakDuration(widget.organizationMemberId, actualBreakDuration.inMinutes);
        await _showBreakSummary(actualBreakDuration, now);
      }

      if (!isAutoEnd) {
        _showSnackBar('Break ended successfully');
      }
    } catch (e) {
      debugPrint('Error ending break: $e');
      _showSnackBar('Failed to end break. Please try again.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _autoEndBreak() async {
    await _endBreak(isAutoEnd: true);
    _showSnackBar('Break time is over. Break ended automatically.');
  }

  Future<void> _showBreakSummary(Duration actualDuration, DateTime endTime) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.coffee,
                    color: Colors.blue,
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Break Summary',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Started at: $_breakStartTimeText',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ended at: ${DateFormat('HH:mm').format(endTime)}',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Duration: ${_formatDuration(actualDuration)}',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Back to Dashboard',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.grey[900]!],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: Colors.blue),
                )
              : Column(
                  children: [
                    _buildAppBar(),
                    Expanded(child: _buildBreakContent()),
                    _buildRedLine(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Spacer(),
          Text(
            'Break Time',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBreakContent() {
    return Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!_isOnBreak) ...[
            _buildStartBreakSection(),
          ] else ...[
            _buildActiveBreakSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildStartBreakSection() {
    final now = TimezoneHelper.nowInOrgTime();
    final canStartBreak = _scheduledBreakStart != null &&
        now.isAfter(_scheduledBreakStart!.subtract(Duration(minutes: 15)));

    return Column(
      children: [
        Icon(
          Icons.coffee,
          color: Colors.blue,
          size: 80,
        ),
        SizedBox(height: 32),
        Text(
          'Break Schedule',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 8),
        if (_scheduledBreakStart != null && _scheduledBreakEnd != null)
          Text(
            '${DateFormat('HH:mm').format(_scheduledBreakStart!)} - ${DateFormat('HH:mm').format(_scheduledBreakEnd!)}',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        SizedBox(height: 8),
        Text(
          'Duration: ${_formatDuration(_totalBreakDuration)}',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 48),
        ElevatedButton(
          onPressed: canStartBreak && !_isLoading ? _startBreak : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            disabledBackgroundColor: Colors.grey[800],
            padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
          child: Text(
            canStartBreak ? 'Start Break' : 'Not Available Yet',
            style: TextStyle(
              color: canStartBreak ? Colors.white : Colors.grey[500],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (!canStartBreak && _scheduledBreakStart != null) ...[
          SizedBox(height: 16),
          Text(
            'Break available at ${DateFormat('HH:mm').format(_scheduledBreakStart!)}',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActiveBreakSection() {
    return Column(
      children: [
        Icon(
          Icons.timer,
          color: Colors.blue,
          size: 80,
        ),
        SizedBox(height: 32),
        Text(
          'Start break at',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 8),
        Text(
          _breakStartTimeText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 48),
        Text(
          'Time Remaining',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 16),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            _formatDuration(_remainingTime),
            style: TextStyle(
              color: _remainingTime.inSeconds > 0 ? Colors.blue : Colors.red,
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(height: 64),
        _buildSlideToEndBreak(),
      ],
    );
  }

  Widget _buildSlideToEndBreak() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              'Slide to end break',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SlideToConfirm(
            onConfirm: () => _endBreak(),
            enabled: !_isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildRedLine() {
    return Container(
      width: double.infinity,
      height: 2,
      color: Colors.red,
    );
  }
}

class SlideToConfirm extends StatefulWidget {
  final VoidCallback onConfirm;
  final bool enabled;

  const SlideToConfirm({
    super.key,
    required this.onConfirm,
    this.enabled = true,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with TickerProviderStateMixin {
  double _dragPosition = 0;
  double _maxDrag = 0;
  bool _isDragging = false;
  bool _isConfirmed = false;

  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled || _isConfirmed) return;
    _isDragging = true;
    _pulseController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _isConfirmed) return;

    setState(() {
      _dragPosition += details.delta.dx;
      _dragPosition = _dragPosition.clamp(0, _maxDrag);
    });

    if (_dragPosition >= _maxDrag * 0.9) {
      _confirmSlide();
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || _isConfirmed) return;

    _isDragging = false;
    if (_dragPosition < _maxDrag * 0.9) {
      _slideController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _dragPosition = 0;
          });
          _pulseController.repeat(reverse: true);
        }
      });
    }
  }

  void _confirmSlide() {
    if (_isConfirmed) return;

    setState(() {
      _isConfirmed = true;
      _dragPosition = _maxDrag;
    });

    _pulseController.stop();
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - 60;

        return GestureDetector(
          onPanStart: _handleDragStart,
          onPanUpdate: _handleDragUpdate,
          onPanEnd: _handleDragEnd,
          child: Container(
            width: constraints.maxWidth,
            height: 60,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: _isDragging ? Duration.zero : Duration(milliseconds: 300),
                  left: _dragPosition,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isDragging ? 1.0 : _pulseAnimation.value,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: _isConfirmed ? Colors.green : Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isConfirmed ? Icons.check : Icons.arrow_forward,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}