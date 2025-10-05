// attendance_history_page.dart - Updated with localization

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/localization_helper.dart';
import 'login.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final VoidCallback? onAttendanceUpdated;

  const AttendanceHistoryPage({super.key, this.onAttendanceUpdated});

  @override
  State<AttendanceHistoryPage> createState() => AttendanceHistoryPageState();
}

class AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  final supabase = Supabase.instance.client;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  // State variables
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _organizationMember;
  Map<String, dynamic>? _organization;
  List<Map<String, dynamic>> _allAttendanceRecords = [];
  List<Map<String, dynamic>> _filteredData = [];
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _attendanceByDate = {};
  bool _isLoading = true;
  bool _isInitialized = false;
  int _totalCheckIns = 0;
  int _totalCheckOuts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initializeData() async {
    if (!mounted) return;
    
    try {
      if (!TimezoneHelper.isInitialized) {
        TimezoneHelper.initialize('UTC');
      }
      
      final now = TimezoneHelper.nowInOrgTime();
      
      if (mounted) {
        setState(() {
          _selectedDay = now;
          _focusedDay = now;
        });
      }
      
      await _loadAllData();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing data: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
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

    try {
      await _loadUserProfile();
      await _loadOrganizationData();
      await _loadAllAttendanceData();
    } catch (e) {
      debugPrint('Error loading all data: $e');
    }
  }

  Future<void> refreshData() async {
    debugPrint('AttendanceHistory: refreshData called from external source');
    if (!mounted) return;
    await _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadAllData();
    } catch (e) {
      debugPrint('Error refreshing data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
          _organizationMember = memberResponse;
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

  Future<void> _loadAllAttendanceData() async {
    if (!mounted) return;
    
    try {
      if (_organizationMember == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final memberId = _organizationMember!['id'];
      
      final logsData = await _loadAttendanceLogs(memberId);
      final recordsData = await _loadAttendanceRecords(memberId);
      
      if (mounted) {
        _processAndSetAttendanceData(logsData, recordsData);
      }

    } catch (e) {
      debugPrint('Error loading attendance data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceLogs(int memberId) async {
    try {
      final response = await supabase
          .from('attendance_logs')
          .select('*')
          .eq('organization_member_id', memberId)
          .order('event_time', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading attendance logs: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceRecords(int memberId) async {
    try {
      final response = await supabase
          .from('attendance_records')
          .select('''
            id,
            attendance_date,
            actual_check_in,
            actual_check_out,
            check_in_photo_url,
            check_out_photo_url,
            work_duration_minutes,
            late_minutes,
            early_leave_minutes,
            status,
            check_in_location,
            check_out_location,
            created_at
          ''')
          .eq('organization_member_id', memberId)
          .order('attendance_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading attendance records: $e');
      return [];
    }
  }

  void _processAndSetAttendanceData(
    List<Map<String, dynamic>> logs,
    List<Map<String, dynamic>> records,
  ) {
    if (!mounted) return;

    final processedData = _processAttendanceDataFromLogs(logs, records);
    
    setState(() {
      _allAttendanceRecords = records;
      _attendanceByDate = processedData['attendanceByDate'];
      _totalCheckIns = processedData['totalCheckIns'];
      _totalCheckOuts = processedData['totalCheckOuts'];
      _isLoading = false;
    });
    
    _updateFilteredData();
  }

  Map<String, dynamic> _processAttendanceDataFromLogs(
    List<Map<String, dynamic>> logs,
    List<Map<String, dynamic>> records,
  ) {
    final Map<DateTime, List<Map<String, dynamic>>> groupedData = {};
    int checkIns = 0;
    int checkOuts = 0;

    final Map<String, Map<String, dynamic>> recordsByDate = {};
    for (final record in records) {
      if (record['attendance_date'] != null) {
        recordsByDate[record['attendance_date']] = record;
      }
    }

    final Map<String, List<Map<String, dynamic>>> logsByDate = {};
    for (final log in logs) {
      if (log['event_time'] != null) {
        final eventTime = DateTime.parse(log['event_time']);
        final orgTime = TimezoneHelper.toOrgTime(eventTime);
        final dateString = DateFormat('yyyy-MM-dd').format(orgTime);
        
        logsByDate[dateString] ??= [];
        logsByDate[dateString]!.add(log);
      }
    }

    for (final log in logs) {
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
            photoUrl = matchingRecord['check_in_photo_url'];
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
            'status': matchingRecord?['status'],
            'late_minutes': matchingRecord?['late_minutes'],
          });
          checkIns++;
          
        } else if (log['event_type'] == 'check_out') {
          String? photoUrl = _extractPhotoFromLog(log);
          
          if (photoUrl == null && matchingRecord != null) {
            photoUrl = matchingRecord['check_out_photo_url'];
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
            'status': matchingRecord?['status'],
            'early_leave_minutes': matchingRecord?['early_leave_minutes'],
            'work_duration_minutes': matchingRecord?['work_duration_minutes'],
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

    return {
      'attendanceByDate': groupedData,
      'totalCheckIns': checkIns,
      'totalCheckOuts': checkOuts,
    };
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

  void _updateFilteredData() {
    if (!mounted) return;
    
    final dateOnly = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final newFilteredData = _attendanceByDate[dateOnly] ?? <Map<String, dynamic>>[];
    
    setState(() {
      _filteredData = newFilteredData;
    });
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!mounted) return;
    
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    
    _updateFilteredData();
  }

  void _onFormatChanged(CalendarFormat format) {
    if (!mounted || _calendarFormat == format) return;
    
    setState(() {
      _calendarFormat = format;
    });
  }

  void _onPageChanged(DateTime focusedDay) {
    if (!mounted) return;
    
    setState(() {
      _focusedDay = focusedDay;
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _attendanceByDate[dateOnly] ?? [];
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
        final maxWidth = screenSize.width * (isLandscape ? 0.7 : 0.85);
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
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getEventIcon(event['type']),
                          color: _getEventColor(event['type']),
                          size: 24,
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
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (event['photo_url'] != null) ...[
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final photoSize = constraints.maxWidth > 300 
                              ? 250.0 
                              : constraints.maxWidth * 0.8;
                          
                          return GestureDetector(
                            onTap: () => _showFullImage(context, event['photo_url']),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: event['photo_url'],
                                width: photoSize,
                                height: photoSize,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: photoSize,
                                  height: photoSize,
                                  color: Colors.grey[200],
                                  child: const Center(child: CircularProgressIndicator()),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: photoSize,
                                  height: photoSize,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.error),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(Icons.calendar_today, LocalizationHelper.getText('date'),
                              TimezoneHelper.formatOrgTime(orgTime, 'EEEE, dd MMMM yyyy')),
                          _buildDetailRow(Icons.access_time, LocalizationHelper.getText('time'),
                              '${TimezoneHelper.formatOrgTime(orgTime, 'HH:mm:ss')} ${TimezoneHelper.currentTimeZone.name}'),
                          if (event['late_minutes'] != null && event['late_minutes'] > 0)
                            _buildDetailRow(Icons.schedule, LocalizationHelper.getText('late'),
                                '${event['late_minutes']} ${LocalizationHelper.getText('minutes')}'),
                          if (event['early_leave_minutes'] != null && event['early_leave_minutes'] > 0)
                            _buildDetailRow(Icons.schedule, LocalizationHelper.getText('early_leave'),
                                _formatEarlyLeave(event['early_leave_minutes'])),
                          if (event['work_duration_minutes'] != null)
                            _buildDetailRow(Icons.work, LocalizationHelper.getText('work_duration'),
                                '${(event['work_duration_minutes'] / 60).toStringAsFixed(1)} ${LocalizationHelper.getText('hours')}'),
                          if (deviceName != null)
                            _buildDetailRow(Icons.devices, LocalizationHelper.getText('location'), deviceName),
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

  String _formatEarlyLeave(int minutes) {
    if (minutes > 60) {
      final hours = minutes / 60;
      return '${hours.toStringAsFixed(1)} ${LocalizationHelper.getText('hours')}';
    }
    return '$minutes ${LocalizationHelper.getText('minutes')}';
  }

  void _showFullImage(BuildContext context, String photoUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: photoUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(),
                errorWidget: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.error, color: Colors.white, size: 50),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
              ),
              child: Text(LocalizationHelper.getText('close')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
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
        return Colors.green;
      case 'check_out':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.grey;
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'early_leave':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                LocalizationHelper.getText('loading'),
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: RefreshIndicator(
        onRefresh: refreshData,
        color: primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildHeader(),
              _buildStatsCard(),
              _buildCalendarCard(),
              _buildSelectedDayEvents(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                    _buildOrgLogo(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LocalizationHelper.getText('attendance_history'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _organization?['name'] ?? LocalizationHelper.getText('unknown_organization'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }

  Widget _buildOrgLogo() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: _organization?['logo_url'] != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _organization!['logo_url']!,
                width: 32,
                height: 32,
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
  }

  Widget _buildStatsCard() {
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
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  LocalizationHelper.getText('attendance_summary'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    LocalizationHelper.getText('check_ins'), 
                    _totalCheckIns.toString(), 
                    Colors.green
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    LocalizationHelper.getText('check_outs'), 
                    _totalCheckOuts.toString(), 
                    Colors.red
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    LocalizationHelper.getText('records'), 
                    _allAttendanceRecords.length.toString(), 
                    Colors.blue
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  LocalizationHelper.getText('calendar_view'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
            onFormatChanged: _onFormatChanged,
            onPageChanged: _onPageChanged,
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
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSelectedDayEvents() {
    if (_filteredData.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.grey.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.12),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: primaryColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withOpacity(0.1),
                  primaryColor.withOpacity(0.05),
                ],
              ),
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
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.event_note,
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
                        LocalizationHelper.getText('daily_events'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        TimezoneHelper.formatOrgTime(_selectedDay, 'EEE, dd MMM yyyy'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredData.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredData.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildEventListItem(_filteredData[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(30),
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
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.event_busy, color: Colors.grey, size: 48),
            const SizedBox(height: 12),
            Text(
              '${LocalizationHelper.getText('no_attendance_data')} ${TimezoneHelper.formatOrgTime(_selectedDay, 'dd MMM yyyy')}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: eventColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: eventColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showEventDetails(event),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        eventColor.withOpacity(0.8),
                        eventColor,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getEventLabel(event['type']),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (event['photo_url'] != null || event['location'] != null)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.info_outline,
                                color: primaryColor,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            TimezoneHelper.formatOrgTime(orgTime, 'HH:mm:ss'),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            TimezoneHelper.currentTimeZone.name,
                            style: TextStyle(
                              fontSize: 11,
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
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: event['photo_url'],
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          placeholder: (context, url) => Icon(
            _getEventIcon(event['type']),
            color: iconColor,
            size: 24,
          ),
          errorWidget: (context, url, error) => Icon(
            _getEventIcon(event['type']),
            color: iconColor,
            size: 24,
          ),
        ),
      );
    }

    return Icon(
      _getEventIcon(event['type']),
      color: iconColor,
      size: 24,
    );
  }

  Widget _buildEventStatusRow(Map<String, dynamic> event) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade400,
                Colors.blue.shade600,
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            LocalizationHelper.getText('record'),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (event['status'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getStatusColor(event['status']).withOpacity(0.8),
                  _getStatusColor(event['status']),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor(event['status']).withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              event['status'].toString().toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}