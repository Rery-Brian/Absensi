import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../helpers/timezone_helper.dart';
import 'login.dart';

class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key});

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  final supabase = Supabase.instance.client;
  
  // Theme colors matching dashboard
  static const Color primaryColor = Color(0xFF6366F1); // Purple
  static const Color backgroundColor = Color(0xFF1F2937); // Dark gray
  
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _organizationMember;
  Map<String, dynamic>? _organization;
  List<Map<String, dynamic>> _allAttendanceRecords = [];
  List<Map<String, dynamic>> _filteredData = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _attendanceByDate = {};
  bool _isLoading = true;
  int _totalCheckIns = 0;
  int _totalCheckOuts = 0;
  
  @override
  void initState() {
    super.initState();
    _selectedDay = TimezoneHelper.nowInJakarta();
    _focusedDay = _selectedDay!;
    _loadUserProfile();
    _loadOrganizationData();
    _loadAllAttendanceData();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .single();
        
        setState(() {
          _userProfile = response;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  Future<void> _loadOrganizationData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // Load organization member data
        final memberResponse = await supabase
            .from('organization_members')
            .select('id, organization_id, employee_id, organizations!inner(id, name, logo_url)')
            .eq('user_id', user.id)
            .single();
        
        if (memberResponse != null) {
          setState(() {
            _organizationMember = memberResponse;
            _organization = memberResponse['organizations'];
          });
        }
      }
    } catch (e) {
      print('Error loading organization data: $e');
    }
  }

  Future<void> _loadAllAttendanceData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_organizationMember == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final memberId = _organizationMember!['id'];
      
      // Load only attendance records
      final records = await _loadAttendanceRecords(memberId);
      
      // Process attendance data
      _processAttendanceData(records);
      
    } catch (e) {
      print('Error loading attendance data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
      print('Error loading attendance records: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceLogs(int memberId) async {
    // This method is removed since we only want records
    return [];
  }

  void _processAttendanceData(List<Map<String, dynamic>> records) {
    final Map<DateTime, List<Map<String, dynamic>>> groupedData = {};
    int checkIns = 0;
    int checkOuts = 0;
    
    // Process only attendance records
    for (final record in records) {
      if (record['attendance_date'] != null) {
        final date = DateTime.parse(record['attendance_date']);
        final jakartaDate = TimezoneHelper.toJakartaTime(date);
        final dateOnly = DateTime(jakartaDate.year, jakartaDate.month, jakartaDate.day);
        
        if (groupedData[dateOnly] == null) {
          groupedData[dateOnly] = [];
        }
        
        // Add check-in event if exists
        if (record['actual_check_in'] != null) {
          groupedData[dateOnly]!.add({
            'type': 'check_in',
            'event_time': record['actual_check_in'],
            'photo_url': record['check_in_photo_url'],
            'location': record['check_in_location'],
            'source': 'record',
            'record_id': record['id'],
            'status': record['status'],
            'late_minutes': record['late_minutes'],
            'work_duration_minutes': record['work_duration_minutes'],
          });
          checkIns++;
        }
        
        // Add check-out event if exists
        if (record['actual_check_out'] != null) {
          groupedData[dateOnly]!.add({
            'type': 'check_out',
            'event_time': record['actual_check_out'],
            'photo_url': record['check_out_photo_url'],
            'location': record['check_out_location'],
            'source': 'record',
            'record_id': record['id'],
            'status': record['status'],
            'early_leave_minutes': record['early_leave_minutes'],
            'work_duration_minutes': record['work_duration_minutes'],
          });
          checkOuts++;
        }
      }
    }
    
    // Sort events by time for each date
    for (final dateEvents in groupedData.values) {
      dateEvents.sort((a, b) {
        final timeA = DateTime.parse(a['event_time']);
        final timeB = DateTime.parse(b['event_time']);
        return timeA.compareTo(timeB);
      });
    }
    
    setState(() {
      _allAttendanceRecords = records;
      _attendanceByDate = groupedData;
      _totalCheckIns = checkIns;
      _totalCheckOuts = checkOuts;
      _filterAttendanceByDate(_selectedDay!);
    });
  }

  void _filterAttendanceByDate(DateTime selectedDate) {
    final dateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    setState(() {
      _filteredData = _attendanceByDate[dateOnly] ?? [];
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _attendanceByDate[dateOnly] ?? [];
  }

  Future<void> _showEventDetails(Map<String, dynamic> event) async {
    final eventTime = DateTime.parse(event['event_time']);
    final jakartaTime = TimezoneHelper.toJakartaTime(eventTime);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
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
                    Text(
                      _getEventLabel(event['type']),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Show photo if available
                if (event['photo_url'] != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: event['photo_url'],
                      width: 250,
                      height: 250,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 250,
                        height: 250,
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 250,
                        height: 250,
                        color: Colors.grey[200],
                        child: const Icon(Icons.error),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Event details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.calendar_today, 'Date', 
                          TimezoneHelper.formatJakartaTime(jakartaTime, 'EEEE, dd MMMM yyyy')),
                      _buildDetailRow(Icons.access_time, 'Time', 
                          TimezoneHelper.formatJakartaTime(jakartaTime, 'HH:mm:ss') + ' WIB'),
                      if (event['method'] != null)
                        _buildDetailRow(Icons.fingerprint, 'Method', event['method']),
                      if (event['late_minutes'] != null && event['late_minutes'] > 0)
                        _buildDetailRow(Icons.schedule, 'Late', 
                            '${event['late_minutes']} minutes'),
                      if (event['early_leave_minutes'] != null && event['early_leave_minutes'] > 0)
                        _buildDetailRow(Icons.schedule, 'Early Leave', 
                            '${event['early_leave_minutes']} minutes'),
                      if (event['work_duration_minutes'] != null)
                        _buildDetailRow(Icons.work, 'Work Duration', 
                            '${(event['work_duration_minutes'] / 60).toStringAsFixed(1)} hours'),
                      _buildLocationRow(event['location']),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _buildLocationRow(dynamic location) {
    if (location == null) return Container();
    
    String locationText = 'Unknown';
    bool isWithinRadius = true;
    
    if (location is Map) {
      if (location['latitude'] != null && location['longitude'] != null) {
        locationText = '${location['latitude']?.toString().substring(0, 8)}, ${location['longitude']?.toString().substring(0, 8)}';
      }
      isWithinRadius = location['is_within_radius'] ?? true;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isWithinRadius ? Icons.location_on : Icons.location_off,
            size: 16,
            color: isWithinRadius ? primaryColor : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            'Location: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              isWithinRadius ? 'Within office radius' : 'Outside office radius',
              style: TextStyle(
                color: isWithinRadius ? primaryColor : Colors.red,
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
        return 'Check In';
      case 'check_out':
        return 'Check Out';
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

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showLogoutConfirmation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.logout, color: primaryColor),
              const SizedBox(width: 8),
              const Text('Konfirmasi Logout'),
            ],
          ),
          content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _logout();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadUserProfile();
                await _loadOrganizationData();
                await _loadAllAttendanceData();
              },
              color: primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildStatsCard(),
                    _buildCalendarCard(),
                    _buildSelectedDayEvents(),
                    const SizedBox(height: 20),
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
              // Organization info
              Expanded(
                child: Row(
                  children: [
                    if (_organization?['logo_url'] != null)
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
                            _organization!['logo_url']!,
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
                        _organization?['name'] ?? 'Unknown Organization',
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
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () async {
                      await _loadUserProfile();
                      await _loadOrganizationData();
                      await _loadAllAttendanceData();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
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
                backgroundImage: _userProfile?['profile_photo_url'] != null
                    ? NetworkImage(_userProfile!['profile_photo_url']!)
                    : null,
                child: _userProfile?['profile_photo_url'] == null
                    ? const Icon(Icons.person, color: Colors.white, size: 28)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userProfile?['display_name'] ?? 
                      '${_userProfile?['first_name'] ?? ''} ${_userProfile?['last_name'] ?? ''}'.trim() ??
                      supabase.auth.currentUser?.email?.split('@')[0] ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'Attendance History',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
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
                const Text(
                  'Attendance Summary',
                  style: TextStyle(
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
                  child: _buildStatItem('Check Ins', '$_totalCheckIns', Colors.green),
                ),
                Expanded(
                  child: _buildStatItem('Check Outs', '$_totalCheckOuts', Colors.red),
                ),
                Expanded(
                  child: _buildStatItem('Records', '${_allAttendanceRecords.length}', Colors.blue),
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
                const Text(
                  'Calendar View',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TableCalendar<Map<String, dynamic>>(
            locale: 'id_ID',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            eventLoader: _getEventsForDay,
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            onDaySelected: (selectedDay, focusedDay) {
              if (!isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _filterAttendanceByDate(selectedDay);
              }
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
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
              markerDecoration: BoxDecoration(
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
              Icon(Icons.event_busy, color: Colors.grey, size: 48),
              const SizedBox(height: 12),
              Text(
                'No attendance data for ${TimezoneHelper.formatJakartaTime(_selectedDay!, 'dd MMM yyyy')}',
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

    return Container(
      margin: const EdgeInsets.all(16),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.event, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Events on ${TimezoneHelper.formatJakartaTime(_selectedDay!, 'dd MMM yyyy')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filteredData.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final event = _filteredData[index];
              final eventTime = DateTime.parse(event['event_time']);
              final jakartaTime = TimezoneHelper.toJakartaTime(eventTime);
              final eventColor = _getEventColor(event['type']);
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: eventColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: event['photo_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: event['photo_url'],
                            width: 45,
                            height: 45,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Icon(
                              _getEventIcon(event['type']),
                              color: eventColor,
                              size: 20,
                            ),
                            errorWidget: (context, url, error) => Icon(
                              _getEventIcon(event['type']),
                              color: eventColor,
                              size: 20,
                            ),
                          ),
                        )
                      : Icon(
                          _getEventIcon(event['type']),
                          color: eventColor,
                          size: 20,
                        ),
                ),
                title: Text(
                  _getEventLabel(event['type']),
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      TimezoneHelper.formatJakartaTime(jakartaTime, 'HH:mm:ss') + ' WIB',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Record',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (event['status'] != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getStatusColor(event['status']).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event['status'].toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: _getStatusColor(event['status']),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                trailing: event['photo_url'] != null || event['location'] != null
                    ? Icon(Icons.info_outline, color: primaryColor, size: 20)
                    : null,
                onTap: () => _showEventDetails(event),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}