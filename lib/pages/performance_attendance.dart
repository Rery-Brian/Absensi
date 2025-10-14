import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';
import '../helpers/localization_helper.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class AttendancePerformancePage extends StatefulWidget {
  const AttendancePerformancePage({super.key});

  @override
  State<AttendancePerformancePage> createState() =>
      _AttendancePerformancePageState();
}

class _AttendancePerformancePageState extends State<AttendancePerformancePage> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color accentColor = Color(0xFF22D3EE);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color backgroundColor = Color(0xFF1F2937);

  final AttendanceService _attendanceService = AttendanceService();

  bool _isLoading = true;
  List<AttendanceRecord> _attendanceRecords = [];
  OrganizationMember? _organizationMember;
  late int _selectedMonth;
  late int _selectedYear;

  PerformanceMetrics _metrics = PerformanceMetrics.empty();

  @override
  void initState() {
    super.initState();
    final today = TimezoneHelper.nowInOrgTime();
    _selectedMonth = today.month;
    _selectedYear = today.year;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _organizationMember = await _attendanceService.loadOrganizationMember();

      if (_organizationMember != null) {
        await _loadAttendanceRecords();
        _calculateMetrics();
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _loadAttendanceRecords() async {
    if (_organizationMember == null) return;

    try {
      final startDate = DateTime(_selectedYear, 1, 1);
      final endDate = DateTime(_selectedYear, 12, 31);

      final response = await Supabase.instance.client
          .from('attendance_records')
          .select()
          .eq('organization_member_id', int.parse(_organizationMember!.id))
          .gte('attendance_date', startDate.toIso8601String())
          .lte('attendance_date', endDate.toIso8601String())
          .order('attendance_date', ascending: false);

      if (response != null) {
        _attendanceRecords = (response as List)
            .map((r) => AttendanceRecord.fromJson(r))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading attendance records: $e');
    }
  }

  void _calculateMetrics() {
    final monthRecords = _attendanceRecords.where((r) {
      final date = DateTime.parse(r.attendanceDate);
      return date.month == _selectedMonth && date.year == _selectedYear;
    }).toList();

    final present =
        monthRecords.where((r) => r.status?.toLowerCase() == 'present').length;
    final absent =
        monthRecords.where((r) => r.status?.toLowerCase() == 'absent').length;
    final late = monthRecords
        .where((r) => r.lateMinutes != null && r.lateMinutes! > 0)
        .length;
    final early = monthRecords
        .where((r) => r.earlyLeaveMinutes != null && r.earlyLeaveMinutes! > 0)
        .length;

    final totalLateMinutes = monthRecords
        .where((r) => r.lateMinutes != null)
        .fold<int>(0, (sum, r) => sum + (r.lateMinutes ?? 0));

    final totalEarlyMinutes = monthRecords
        .where((r) => r.earlyLeaveMinutes != null)
        .fold<int>(0, (sum, r) => sum + (r.earlyLeaveMinutes ?? 0));

    final avgWorkMinutes = monthRecords.isEmpty
        ? 0
        : monthRecords
                .where((r) => r.workDurationMinutes != null)
                .fold<int>(0, (sum, r) => sum + (r.workDurationMinutes ?? 0)) ~/
            (monthRecords.length);

    _metrics = PerformanceMetrics(
      present: present,
      absent: absent,
      late: late,
      early: early,
      totalLateMinutes: totalLateMinutes,
      totalEarlyMinutes: totalEarlyMinutes,
      avgWorkMinutes: avgWorkMinutes,
      totalRecords: monthRecords.length,
      workDays: monthRecords.length,
    );
  }

  String _getMonthName(int month) {
    final locale = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final format = DateFormat.MMMM(locale);
    return format.format(DateTime(2025, month));
  }

  List<AttendanceRecord> _getMonthRecords() {
    return _attendanceRecords.where((r) {
      final date = DateTime.parse(r.attendanceDate);
      return date.month == _selectedMonth && date.year == _selectedYear;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final today = TimezoneHelper.nowInOrgTime();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryColor),
            )
          : Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildHeader(today),
                      _buildMonthSelector(),
                      _buildMetricsCards(),
                      _buildAttendanceChart(),
                      _buildDetailedList(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(DateTime today) {
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
          Text(
            LocalizationHelper.getText('attendance_performance'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LocalizationHelper.getText('monitor_attendance_stats'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            DateFormat('EEEE, dd MMM yyyy').format(today),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedMonth == 1) {
                  _selectedMonth = 12;
                  _selectedYear--;
                } else {
                  _selectedMonth--;
                }
                _calculateMetrics();
              });
            },
            icon: const Icon(Icons.chevron_left, color: primaryColor),
          ),
          Expanded(
            child: Text(
              '${_getMonthName(_selectedMonth)} $_selectedYear',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedMonth == 12) {
                  _selectedMonth = 1;
                  _selectedYear++;
                } else {
                  _selectedMonth++;
                }
                _calculateMetrics();
              });
            },
            icon: const Icon(Icons.chevron_right, color: primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsCards() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('present'),
                  value: _metrics.present.toString(),
                  color: successColor,
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('absent'),
                  value: _metrics.absent.toString(),
                  color: errorColor,
                  icon: Icons.cancel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('late'),
                  value: _metrics.late.toString(),
                  color: warningColor,
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('early_leave'),
                  value: _metrics.early.toString(),
                  color: accentColor,
                  icon: Icons.logout,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('avg_work_hours'),
                  value: '${(_metrics.avgWorkMinutes / 60).toStringAsFixed(1)}h',
                  color: primaryColor,
                  icon: Icons.work_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('total_minutes_late'),
                  value: _formatMinutesToHours(_metrics.totalLateMinutes),
                  color: Colors.deepOrange,
                  icon: Icons.timer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceChart() {
    final monthRecords = _getMonthRecords();
    if (monthRecords.isEmpty) {
      return _emptyBox(LocalizationHelper.getText('no_records_month'));
    }

    final presentCount =
        monthRecords.where((r) => r.status?.toLowerCase() == 'present').length;
    final absentCount =
        monthRecords.where((r) => r.status?.toLowerCase() == 'absent').length;

    final presentPercentage =
        monthRecords.isEmpty ? 0.0 : (presentCount / monthRecords.length) * 100;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: _boxDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocalizationHelper.getText('attendance_rate'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: presentPercentage / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(successColor),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${presentPercentage.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      LocalizationHelper.getText('present_label'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildChartLegend(LocalizationHelper.getText('present_label'),
                  presentCount, successColor),
              _buildChartLegend(LocalizationHelper.getText('absent_label'),
                  absentCount, errorColor),
              _buildChartLegend(LocalizationHelper.getText('total_days'),
                  monthRecords.length, primaryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartLegend(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 8),
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedList() {
    final monthRecords = _getMonthRecords();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: _boxDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocalizationHelper.getText('attendance_details'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          if (monthRecords.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  LocalizationHelper.getText('no_records_found'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: monthRecords.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final record = monthRecords[index];
                return _buildAttendanceDetailItem(record);
              },
            ),
        ],
      ),
    );
  }

  BoxDecoration _boxDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Widget _emptyBox(String text) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: _boxDeco(),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildAttendanceDetailItem(AttendanceRecord record) {
    final date = DateTime.parse(record.attendanceDate);
    final isPresent = record.status?.toLowerCase() == 'present';
    final isLate = record.lateMinutes != null && record.lateMinutes! > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  isPresent ? successColor.withOpacity(0.15) : errorColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPresent ? Icons.check_circle : Icons.cancel,
              color: isPresent ? successColor : errorColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, dd MMMM').format(date),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (record.actualCheckIn != null)
                      Text(
                        'In: ${_formatTime(record.actualCheckIn)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (record.actualCheckOut != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        'Out: ${_formatTime(record.actualCheckOut)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isLate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${record.lateMinutes}m late',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: warningColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    return DateFormat('HH:mm').format(dateTime);
  }

  String _formatMinutesToHours(int minutes) {
    if (minutes == 0) return '0h';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

class PerformanceMetrics {
  final int present;
  final int absent;
  final int late;
  final int early;
  final int totalLateMinutes;
  final int totalEarlyMinutes;
  final int avgWorkMinutes;
  final int totalRecords;
  final int workDays;

  PerformanceMetrics({
    required this.present,
    required this.absent,
    required this.late,
    required this.early,
    required this.totalLateMinutes,
    required this.totalEarlyMinutes,
    required this.avgWorkMinutes,
    required this.totalRecords,
    required this.workDays,
  });

  factory PerformanceMetrics.empty() {
    return PerformanceMetrics(
      present: 0,
      absent: 0,
      late: 0,
      early: 0,
      totalLateMinutes: 0,
      totalEarlyMinutes: 0,
      avgWorkMinutes: 0,
      totalRecords: 0,
      workDays: 0,
    );
  }
}
