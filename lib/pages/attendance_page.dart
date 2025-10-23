import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';
import '../helpers/localization_helper.dart';
import '../helpers/timezone_helper.dart';
import 'attendance_skeleton_widgets.dart';

class AttendancePage extends StatefulWidget {
  final VoidCallback? onAttendanceUpdated;

  const AttendancePage({super.key, this.onAttendanceUpdated});

  @override
  State<AttendancePage> createState() => AttendancePageState();
}

class AttendancePageState extends State<AttendancePage> with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color backgroundColor = Color(0xFF1F2937);

  final AttendanceService _attendanceService = AttendanceService();
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isInitialized = false;

  OrganizationMember? _organizationMember;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _organization;

  List<AttendanceRecord> _attendanceRecords = [];
  List<Map<String, dynamic>> _allAttendanceLogs = [];
  Map<DateTime, List<Map<String, dynamic>>> _attendanceByDate = {};
  
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late int _selectedMonth;
  late int _selectedYear;

  PerformanceMetrics _metrics = PerformanceMetrics.empty();
  int _totalCheckIns = 0;
  int _totalCheckOuts = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    final now = TimezoneHelper.nowInOrgTime();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _selectedDay = now;
    _focusedDay = now;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    
    try {
      if (!TimezoneHelper.isInitialized) {
        TimezoneHelper.initialize('UTC');
      }
      
      await _loadAllData();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    
    try {
      await _loadUserProfile();
      await _loadOrganizationData();
      
      _organizationMember = await _attendanceService.loadOrganizationMember();
      
      if (_organizationMember != null) {
        await _loadAttendanceRecords();
        await _loadAttendanceLogs();
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

  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .single();

        if (mounted) {
          _userProfile = response;
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    }
  }

  Future<void> _loadOrganizationData() async {
    if (!mounted) return;
    
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final memberResponse = await supabase
            .from('organization_members')
            .select('id, organization_id, employee_id, organizations!inner(id, name, logo_url, timezone)')
            .eq('user_id', user.id)
            .single();

        if (memberResponse != null && mounted) {
          _organization = memberResponse['organizations'];
          
          if (_organization?['timezone'] != null) {
            TimezoneHelper.initialize(_organization!['timezone']);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading organization data: $e');
    }
  }

  Future<void> _loadAttendanceRecords() async {
    if (_organizationMember == null) return;

    try {
      final startDate = DateTime(_selectedYear, 1, 1);
      final endDate = DateTime(_selectedYear, 12, 31, 23, 59, 59);

      final response = await supabase
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

  Future<void> _loadAttendanceLogs() async {
  if (_organizationMember == null) return;
  if (!mounted) return; // ✅ TAMBAHKAN INI

  try {
    final memberId = int.parse(_organizationMember!.id);
    
    final response = await supabase
        .from('attendance_logs')
        .select('*')
        .eq('organization_member_id', memberId)
        .order('event_time', ascending: false);

    if (!mounted) return; // ✅ CHECK SETELAH ASYNC

    _allAttendanceLogs = List<Map<String, dynamic>>.from(response);
    _processAttendanceLogs();
  } catch (e) {
    debugPrint('Error loading attendance logs: $e');
  }
}

  void _processAttendanceLogs() {
    final Map<DateTime, List<Map<String, dynamic>>> groupedData = {};
    int checkIns = 0;
    int checkOuts = 0;

    final Map<String, AttendanceRecord> recordsByDate = {};
    for (final record in _attendanceRecords) {
      final utcDate = DateTime.parse(record.attendanceDate);
      final orgDate = TimezoneHelper.toOrgTime(utcDate);
      final dateString = DateFormat('yyyy-MM-dd').format(orgDate);
      recordsByDate[dateString] = record;
    }

    for (final log in _allAttendanceLogs) {
      if (log['event_time'] != null) {
        final eventTime = DateTime.parse(log['event_time']);
        final orgTime = TimezoneHelper.toOrgTime(eventTime);
        final dateOnly = DateTime(orgTime.year, orgTime.month, orgTime.day);
        final dateString = DateFormat('yyyy-MM-dd').format(dateOnly);

        groupedData[dateOnly] ??= [];

        final matchingRecord = recordsByDate[dateString];
        
        if (log['event_type'] == 'check_in') {
          String? photoUrl = _extractPhotoFromLog(log);
          
          if (photoUrl == null && matchingRecord != null) {
            photoUrl = matchingRecord.checkInPhotoUrl;
          }
          
          groupedData[dateOnly]!.add({
            'type': 'check_in',
            'event_time': log['event_time'],
            'photo_url': photoUrl,
            'location': log['location'],
            'source': 'log',
            'log_id': log['id'],
            'method': log['method'],
            'device_id': log['device_id'],
            'is_verified': log['is_verified'],
            'status': matchingRecord?.status,
            'late_minutes': matchingRecord?.lateMinutes,
          });
          checkIns++;
          
        } else if (log['event_type'] == 'check_out') {
          String? photoUrl = _extractPhotoFromLog(log);
          
          if (photoUrl == null && matchingRecord != null) {
            photoUrl = matchingRecord.checkOutPhotoUrl;
          }
          
          groupedData[dateOnly]!.add({
            'type': 'check_out',
            'event_time': log['event_time'],
            'photo_url': photoUrl,
            'location': log['location'],
            'source': 'log',
            'log_id': log['id'],
            'method': log['method'],
            'device_id': log['device_id'],
            'is_verified': log['is_verified'],
            'status': matchingRecord?.status,
            'early_leave_minutes': matchingRecord?.earlyLeaveMinutes,
            'work_duration_minutes': matchingRecord?.workDurationMinutes,
          });
          checkOuts++;
        }
      }
    }

    for (final dateEvents in groupedData.values) {
      dateEvents.sort((a, b) {
        final timeA = DateTime.parse(a['event_time']);
        final timeB = DateTime.parse(b['event_time']);
        return timeA.compareTo(timeB);
      });
    }

    setState(() {
      _attendanceByDate = groupedData;
      _totalCheckIns = checkIns;
      _totalCheckOuts = checkOuts;
    });
  }

  String? _extractPhotoFromLog(Map<String, dynamic> log) {
    try {
      final location = log['location'];
      if (location is Map && location['photo_url'] != null) {
        return location['photo_url'].toString();
      }
    } catch (e) {
      debugPrint('Error extracting photo from log: $e');
    }
    return null;
  }

  void _calculateMetrics() {
    if (!mounted) return;
    final monthRecords = _attendanceRecords.where((r) {
      final utcDate = DateTime.parse(r.attendanceDate);
      final orgDate = TimezoneHelper.toOrgTime(utcDate);
      return orgDate.month == _selectedMonth && orgDate.year == _selectedYear;
    }).toList();

    final present = monthRecords.where((r) => r.status?.toLowerCase() == 'present').length;
    final absent = monthRecords.where((r) => r.status?.toLowerCase() == 'absent').length;
    final late = monthRecords.where((r) => r.lateMinutes != null && r.lateMinutes! > 0).length;

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

  Future<void> refreshData() async {
    debugPrint('Attendance: refreshData called');
    if (!mounted) return;
    await _loadAllData();
  }

  List<AttendanceRecord> _getMonthRecords() {
    return _attendanceRecords.where((r) {
      final utcDate = DateTime.parse(r.attendanceDate);
      final orgDate = TimezoneHelper.toOrgTime(utcDate);
      return orgDate.month == _selectedMonth && orgDate.year == _selectedYear;
    }).toList();
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _attendanceByDate[dateOnly] ?? [];
  }

  List<Map<String, dynamic>> _getSelectedDayEvents() {
    final dateOnly = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    return _attendanceByDate[dateOnly] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
  if (!mounted) return; // ✅ TAMBAHKAN INI
  
  setState(() {
    _selectedDay = selectedDay;
    _focusedDay = focusedDay;
  });
}

  String _getMonthName(int month) {
    final now = TimezoneHelper.nowInOrgTime();
    final locale = LocalizationHelper.currentLanguage;
    final format = DateFormat.MMMM(locale);
    return format.format(DateTime(now.year, month));
  }

  Future<void> _showMonthYearPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        int tempYear = _selectedYear;
        int tempMonth = _selectedMonth;
        
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
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
                  const SizedBox(height: 24),
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
                              monthName.length >= 3 ? monthName.substring(0, 3) : monthName,
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
                        if (!mounted) return;
                        setState(() {
                          _selectedMonth = tempMonth;
                          _selectedYear = tempYear;
                          _calculateMetrics();
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _isLoading) {
    return AttendanceSkeletonWidgets.buildFullPageSkeleton();
  }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        onRefresh: refreshData,
        color: primaryColor,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildMonthSelector()),
              SliverToBoxAdapter(child: _buildPerformanceSummary()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: primaryColor,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: primaryColor,
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(text: LocalizationHelper.getText('calendar_view')),
                      Tab(text: LocalizationHelper.getText('attendance_details')),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildCalendarTab(),
              _buildDetailsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final now = TimezoneHelper.nowInOrgTime();
    final locale = LocalizationHelper.currentLanguage;
    final dateFormat = DateFormat('EEEE, dd MMM yyyy', locale);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [backgroundColor, Color(0xFF374151)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildOrgLogo(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocalizationHelper.getText('report'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _organization?['name'] ?? LocalizationHelper.getText('unknown_organization'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            dateFormat.format(now),
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgLogo() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _organization?['logo_url'] != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _organization!['logo_url']!,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultLogo();
                },
              ),
            )
          : _buildDefaultLogo(),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.business,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
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

  Widget _buildPerformanceSummary() {
    final monthRecords = _getMonthRecords();
    final presentPercentage = monthRecords.isEmpty 
        ? 0.0 
        : (_metrics.present / monthRecords.length) * 100;
    final totalWorkHours = (_metrics.avgWorkMinutes * monthRecords.length) / 60;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
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
                          fontSize: 36,
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
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: presentPercentage / 100,
                          strokeWidth: 7,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const Icon(
                        Icons.trending_up,
                        color: Colors.white,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                  label: 'Work Hours',
                  value: totalWorkHours.toStringAsFixed(1),
                  subtitle: 'hours',
                  color: const Color(0xFF06B6D4),
                  icon: Icons.timer_outlined,
                ),
              ),
            ],
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
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
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
      padding: const EdgeInsets.all(14),
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
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
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

  Widget _buildCalendarTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildCalendarSection(),
          _buildDailyEvents(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildRecentRecords(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCalendarSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TableCalendar<Map<String, dynamic>>(
            locale: LocalizationHelper.currentLanguage == 'id' ? 'id_ID' : 'en_US',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (!mounted) return;
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              if (!mounted) return;
              setState(() {
                _focusedDay = focusedDay;
              });
            },
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              selectedDecoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: primaryColor.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
              markerDecoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              markerSize: 6,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonDecoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              formatButtonTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              titleTextStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDailyEvents() {
    final events = _getSelectedDayEvents();
    
    if (events.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_busy, color: Colors.grey.shade300, size: 48),
              const SizedBox(height: 12),
              Text(
                LocalizationHelper.getText('no_attendance_data'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                TimezoneHelper.formatOrgTime(_selectedDay, 'dd MMM yyyy'),
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.event_note,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocalizationHelper.getText('daily_events'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        TimezoneHelper.formatOrgTime(_selectedDay, 'EEE, dd MMM yyyy'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${events.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildEventListItem(events[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventListItem(Map<String, dynamic> event) {
    final eventTime = DateTime.parse(event['event_time']);
    final orgTime = TimezoneHelper.toOrgTime(eventTime);
    final eventColor = _getEventColor(event['type']);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: eventColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEventDetails(event),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        eventColor.withOpacity(0.8),
                        eventColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: eventColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildEventLeadingWidget(event, Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getEventLabel(event['type']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            TimezoneHelper.formatOrgTime(orgTime, 'HH:mm:ss'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            TimezoneHelper.currentTimeZone.name,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildEventStatusRow(event),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventLeadingWidget(Map<String, dynamic> event, Color iconColor) {
    if (event['photo_url'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: event['photo_url'],
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (context, url) => Icon(
            _getEventIcon(event['type']),
            color: iconColor,
            size: 22,
          ),
          errorWidget: (context, url, error) => Icon(
            _getEventIcon(event['type']),
            color: iconColor,
            size: 22,
          ),
        ),
      );
    }

    return Icon(
      _getEventIcon(event['type']),
      color: iconColor,
      size: 22,
    );
  }

  Widget _buildEventStatusRow(Map<String, dynamic> event) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (event['status'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _getStatusColor(event['status']).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _getStatusColor(event['status']).withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Text(
              event['status'].toString().toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                color: _getStatusColor(event['status']),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (event['late_minutes'] != null && event['late_minutes'] > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: warningColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: warningColor.withOpacity(0.5), width: 1),
            ),
            child: Text(
              '+${event['late_minutes']}m',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: warningColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentRecords() {
    final monthRecords = _getMonthRecords();

    if (monthRecords.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                LocalizationHelper.getText('no_records_found'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.list_alt, color: primaryColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    LocalizationHelper.getText('attendance_details'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${monthRecords.length}',
                    style: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: monthRecords.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade100,
            ),
            itemBuilder: (context, index) {
              final record = monthRecords[index];
              return _buildRecordItem(record);
            },
          ),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPresent 
                    ? [successColor, successColor]
                    : [errorColor, errorColor],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: (isPresent ? successColor : errorColor).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isPresent ? Icons.check_circle : Icons.cancel,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEE, dd MMM yyyy', locale).format(orgDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.login, size: 11, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(record.actualCheckIn),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.logout, size: 11, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(record.actualCheckOut),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLate)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: warningColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: warningColor.withOpacity(0.5), width: 1),
              ),
              child: Text(
                '+${record.lateMinutes}m',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: warningColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEventDetails(Map<String, dynamic> event) async {
    if (!mounted) return;
    
    final eventTime = DateTime.parse(event['event_time']);
    final orgTime = TimezoneHelper.toOrgTime(eventTime);

    String? deviceName;
    if (event['device_id'] != null) {
      try {
        final deviceResponse = await supabase
            .from('attendance_devices')
            .select('device_name')
            .eq('id', event['device_id'])
            .single();
        deviceName = deviceResponse['device_name'];
      } catch (e) {
        debugPrint('Error loading device name: $e');
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenSize = MediaQuery.of(context).size;
        final isLandscape = screenSize.width > screenSize.height;
        final maxWidth = screenSize.width * (isLandscape ? 0.7 : 0.9);
        final maxHeight = screenSize.height * 0.85;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _getEventColor(event['type']).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getEventIcon(event['type']),
                            color: _getEventColor(event['type']),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _getEventLabel(event['type']),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (event['photo_url'] != null) ...[
                      GestureDetector(
                        onTap: () => _showFullImage(context, event['photo_url']),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: event['photo_url'],
                            width: double.infinity,
                            height: 220,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: double.infinity,
                              height: 220,
                              color: Colors.grey[200],
                              child: const Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: double.infinity,
                              height: 220,
                              color: Colors.grey[200],
                              child: const Icon(Icons.error),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            Icons.calendar_today,
                            LocalizationHelper.getText('date'),
                            TimezoneHelper.formatOrgTime(orgTime, 'EEEE, dd MMMM yyyy'),
                          ),
                          _buildDetailRow(
                            Icons.access_time,
                            LocalizationHelper.getText('time'),
                            '${TimezoneHelper.formatOrgTime(orgTime, 'HH:mm:ss')} ${TimezoneHelper.currentTimeZone.name}',
                          ),
                          if (event['late_minutes'] != null && event['late_minutes'] > 0)
                            _buildDetailRow(
                              Icons.schedule,
                              LocalizationHelper.getText('late'),
                              '${event['late_minutes']} ${LocalizationHelper.getText('minutes')}',
                            ),
                          if (event['early_leave_minutes'] != null && event['early_leave_minutes'] > 0)
                            _buildDetailRow(
                              Icons.schedule,
                              LocalizationHelper.getText('early_leave'),
                              _formatEarlyLeave(event['early_leave_minutes']),
                            ),
                          if (event['work_duration_minutes'] != null)
                            _buildDetailRow(
                              Icons.work,
                              LocalizationHelper.getText('work_duration'),
                              '${(event['work_duration_minutes'] / 60).toStringAsFixed(1)} ${LocalizationHelper.getText('hours')}',
                            ),
                          if (deviceName != null)
                            _buildDetailRow(
                              Icons.devices,
                              LocalizationHelper.getText('location'),
                              deviceName,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFullImage(BuildContext context, String photoUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  errorWidget: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.error, color: Colors.white, size: 50),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEventLabel(String type) {
    switch (type) {
      case 'check_in':
        return LocalizationHelper.getText('check_in');
      case 'check_out':
        return LocalizationHelper.getText('check_out');
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }

  IconData _getEventIcon(String type) {
    switch (type) {
      case 'check_in':
        return Icons.login;
      case 'check_out':
        return Icons.logout;
      default:
        return Icons.event;
    }
  }

  Color _getEventColor(String type) {
    switch (type) {
      case 'check_in':
        return successColor;
      case 'check_out':
        return errorColor;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'present':
        return successColor;
      case 'absent':
        return errorColor;
      case 'late':
        return warningColor;
      case 'early_leave':
        return Colors.purple;
      default:
        return Colors.grey;
    }
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

  String _formatEarlyLeave(int minutes) {
    if (minutes > 60) {
      final hours = minutes / 60;
      return '${hours.toStringAsFixed(1)} ${LocalizationHelper.getText('hours')}';
    }
    return '$minutes ${LocalizationHelper.getText('minutes')}';
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
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
        child: _tabBar,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
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