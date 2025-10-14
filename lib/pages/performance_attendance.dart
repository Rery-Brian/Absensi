import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';
import '../helpers/localization_helper.dart';
import '../helpers/timezone_helper.dart';

class AttendancePerformancePage extends StatefulWidget {
  const AttendancePerformancePage({super.key});

  @override
  State<AttendancePerformancePage> createState() =>
      _AttendancePerformancePageState();
}

class _AttendancePerformancePageState extends State<AttendancePerformancePage> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);

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
    final now = TimezoneHelper.nowInOrgTime();
    _selectedMonth = now.month;
    _selectedYear = now.year;
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
      final endDate = DateTime(_selectedYear, 12, 31, 23, 59, 59);

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
      final utcDate = DateTime.parse(r.attendanceDate);
      final orgDate = TimezoneHelper.toOrgTime(utcDate);
      return orgDate.month == _selectedMonth && orgDate.year == _selectedYear;
    }).toList();

    final present =
        monthRecords.where((r) => r.status?.toLowerCase() == 'present').length;
    final absent =
        monthRecords.where((r) => r.status?.toLowerCase() == 'absent').length;
    final late = monthRecords
        .where((r) => r.lateMinutes != null && r.lateMinutes! > 0)
        .length;

    final totalLateMinutes = monthRecords
        .where((r) => r.lateMinutes != null)
        .fold<int>(0, (sum, r) => sum + (r.lateMinutes ?? 0));

    final avgWorkMinutes = monthRecords.isEmpty
        ? 0
        : monthRecords
                .where((r) => r.workDurationMinutes != null)
                .fold<int>(0, (sum, r) => sum + (r.workDurationMinutes ?? 0)) ~/
            monthRecords.length;

    _metrics = PerformanceMetrics(
      present: present,
      absent: absent,
      late: late,
      totalLateMinutes: totalLateMinutes,
      avgWorkMinutes: avgWorkMinutes,
      totalRecords: monthRecords.length,
    );
  }

  String _getMonthName(int month) {
    final now = TimezoneHelper.nowInOrgTime();
    final locale = LocalizationHelper.currentLanguage;
    final format = DateFormat.MMMM(locale);
    return format.format(DateTime(now.year, month));
  }

  List<AttendanceRecord> _getMonthRecords() {
    return _attendanceRecords.where((r) {
      final utcDate = DateTime.parse(r.attendanceDate);
      final orgDate = TimezoneHelper.toOrgTime(utcDate);
      return orgDate.month == _selectedMonth && orgDate.year == _selectedYear;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimezoneHelper.nowInOrgTime();
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryColor),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildHeader(now),
                    _buildMonthSelector(),
                    _buildSummaryCard(),
                    _buildMetricsGrid(),
                    _buildRecentRecords(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(DateTime now) {
    final locale = LocalizationHelper.currentLanguage;
    final dateFormat = DateFormat('EEEE, dd MMM yyyy', locale);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F2937), Color(0xFF374151)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
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
            dateFormat.format(now),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _showMonthYearPicker,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, color: primaryColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  '${_getMonthName(_selectedMonth)} $_selectedYear',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMonthYearPicker() async {
    final now = TimezoneHelper.nowInOrgTime();
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setStateDialog(() => tempYear--),
                        icon: const Icon(Icons.chevron_left, color: primaryColor),
                      ),
                      Text(
                        tempYear.toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setStateDialog(() => tempYear++),
                        icon: const Icon(Icons.chevron_right, color: primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final isSelected = month == tempMonth;
                      final monthName = _getMonthName(month);
                      
                      return InkWell(
                        onTap: () => setStateDialog(() => tempMonth = month),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? primaryColor : Colors.grey.shade300,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              monthName.substring(0, 3),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedMonth = tempMonth;
                          _selectedYear = tempYear;
                          _calculateMetrics();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        LocalizationHelper.getText('apply'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard() {
    final monthRecords = _getMonthRecords();
    final presentPercentage = monthRecords.isEmpty 
        ? 0.0 
        : (_metrics.present / monthRecords.length) * 100;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationHelper.getText('attendance_rate'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${presentPercentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildSummaryItem(
                      LocalizationHelper.getText('present_label'),
                      _metrics.present.toString(),
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryItem(
                      LocalizationHelper.getText('absent_label'),
                      _metrics.absent.toString(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: presentPercentage / 100,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Icon(
                  Icons.trending_up,
                  color: Colors.white,
                  size: 36,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid() {
    final monthRecords = _getMonthRecords();
    final totalWorkHours = (_metrics.avgWorkMinutes * monthRecords.length) / 60;
    final attendanceRate = monthRecords.isEmpty 
        ? 0.0 
        : (_metrics.present / monthRecords.length) * 100;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('late'),
                  value: _metrics.late.toString(),
                  subtitle: _formatMinutesToHours(_metrics.totalLateMinutes),
                  color: warningColor,
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: LocalizationHelper.getText('avg_work_hours'),
                  value: (_metrics.avgWorkMinutes / 60).toStringAsFixed(1),
                  subtitle: LocalizationHelper.getText('hours'),
                  color: primaryColor,
                  icon: Icons.work_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  label: 'Total Work Hours',
                  value: totalWorkHours.toStringAsFixed(1),
                  subtitle: 'hours',
                  color: const Color(0xFF06B6D4),
                  icon: Icons.timer_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  label: 'Working Days',
                  value: monthRecords.length.toString(),
                  subtitle: 'days',
                  color: const Color(0xFF8B5CF6),
                  icon: Icons.calendar_today,
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
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecords() {
    final monthRecords = _getMonthRecords();
    final recentRecords = monthRecords.take(10).toList();

    if (recentRecords.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                LocalizationHelper.getText('no_records_found'),
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              LocalizationHelper.getText('attendance_details'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentRecords.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade100,
            ),
            itemBuilder: (context, index) {
              final record = recentRecords[index];
              return _buildRecordItem(record);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRecordItem(AttendanceRecord record) {
    final utcDate = DateTime.parse(record.attendanceDate);
    final orgDate = TimezoneHelper.toOrgTime(utcDate);
    final isPresent = record.status?.toLowerCase() == 'present';
    final isLate = record.lateMinutes != null && record.lateMinutes! > 0;
    final locale = LocalizationHelper.currentLanguage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPresent 
                  ? successColor.withOpacity(0.1) 
                  : errorColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPresent ? Icons.check_circle : Icons.cancel,
              color: isPresent ? successColor : errorColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEE, dd MMM', locale).format(orgDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(record.actualCheckIn)} - ${_formatTime(record.actualCheckOut)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (isLate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+${record.lateMinutes}m',
                style: const TextStyle(
                  fontSize: 11,
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
    final orgTime = TimezoneHelper.toOrgTime(dateTime);
    return DateFormat('HH:mm').format(orgTime);
  }

  String _formatMinutesToHours(int minutes) {
    if (minutes == 0) return '0m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

class PerformanceMetrics {
  final int present;
  final int absent;
  final int late;
  final int totalLateMinutes;
  final int avgWorkMinutes;
  final int totalRecords;

  PerformanceMetrics({
    required this.present,
    required this.absent,
    required this.late,
    required this.totalLateMinutes,
    required this.avgWorkMinutes,
    required this.totalRecords,
  });

  factory PerformanceMetrics.empty() {
    return PerformanceMetrics(
      present: 0,
      absent: 0,
      late: 0,
      totalLateMinutes: 0,
      avgWorkMinutes: 0,
      totalRecords: 0,
    );
  }
}