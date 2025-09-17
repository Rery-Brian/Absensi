import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key});

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  final supabase = Supabase.instance.client;
  static const Color primaryColor = Color(0xFF009688);
  
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _allAttendance = [];
  List<Map<String, dynamic>> _filteredAttendance = [];
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
    _selectedDay = DateTime.now();
    _loadUserProfile();
    _loadAllAttendance();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('profiles')
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

  Future<void> _loadAllAttendance() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('attendance')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        
        final attendanceList = List<Map<String, dynamic>>.from(response);
        
        // Group attendance by date for calendar
        final Map<DateTime, List<Map<String, dynamic>>> groupedAttendance = {};
        int checkIns = 0;
        int checkOuts = 0;
        
        for (final attendance in attendanceList) {
          final date = DateTime.parse(attendance['created_at']);
          final dateOnly = DateTime(date.year, date.month, date.day);
          
          if (groupedAttendance[dateOnly] == null) {
            groupedAttendance[dateOnly] = [];
          }
          groupedAttendance[dateOnly]!.add(attendance);
          
          if (attendance['type'] == 'check_in') {
            checkIns++;
          } else {
            checkOuts++;
          }
        }
        
        setState(() {
          _allAttendance = attendanceList;
          _attendanceByDate = groupedAttendance;
          _totalCheckIns = checkIns;
          _totalCheckOuts = checkOuts;
          _filterAttendanceByDate(_selectedDay!);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading attendance: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterAttendanceByDate(DateTime selectedDate) {
    final dateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    setState(() {
      _filteredAttendance = _attendanceByDate[dateOnly] ?? [];
    });
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final dateOnly = DateTime(day.year, day.month, day.day);
    return _attendanceByDate[dateOnly] ?? [];
  }

  Future<void> _showPhotoDialog(String photoUrl, Map<String, dynamic> attendance) async {
    final date = DateTime.parse(attendance['created_at']);
    final isCheckIn = attendance['type'] == 'check_in';
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isCheckIn ? Icons.login : Icons.logout,
                      color: isCheckIn ? primaryColor : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isCheckIn ? 'Check In' : 'Check Out',
                      style: const TextStyle(
                        fontSize: 18,
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
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: photoUrl,
                    width: 300,
                    height: 300,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 300,
                      height: 300,
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 300,
                      height: 300,
                      color: Colors.grey[200],
                      child: const Icon(Icons.error),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('HH:mm:ss WIB').format(date),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            attendance['is_within_radius'] ? Icons.location_on : Icons.location_off,
                            size: 16,
                            color: attendance['is_within_radius'] ? primaryColor : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            attendance['is_within_radius'] 
                                ? 'Dalam radius kantor' 
                                : 'Luar radius kantor',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: attendance['is_within_radius'] ? primaryColor : Colors.red,
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _logout() async {
    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
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
      appBar: AppBar(
        title: const Text("Riwayat Absensi"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadUserProfile();
              _loadAllAttendance();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _showLogoutConfirmation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadUserProfile();
                await _loadAllAttendance();
              },
              color: primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // User Profile Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white,
                            child: Icon(
                              Icons.person,
                              size: 50,
                              color: primaryColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _userProfile?['name'] ?? user?.email ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Statistics
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Total Check In',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '$_totalCheckIns',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Total Check Out',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '$_totalCheckOuts',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Calendar
                    Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
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
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, color: primaryColor),
                                const SizedBox(width: 8),
                                const Text(
                                  'Kalender Absensi',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
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
                              markersMaxCount: 2,
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
                    ),

                    // Selected Day Attendance
                    if (_filteredAttendance.isNotEmpty) ...[
                      Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
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
                                  Icon(Icons.event, color: primaryColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Absensi ${DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDay!)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredAttendance.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final attendance = _filteredAttendance[index];
                                final isCheckIn = attendance['type'] == 'check_in';
                                final date = DateTime.parse(attendance['created_at']);
                                
                                return ListTile(
                                  leading: GestureDetector(
                                    onTap: attendance['photo_url'] != null
                                        ? () => _showPhotoDialog(attendance['photo_url'], attendance)
                                        : null,
                                    child: CircleAvatar(
                                      backgroundColor: isCheckIn ? primaryColor : Colors.orange,
                                      child: attendance['photo_url'] != null
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(20),
                                              child: CachedNetworkImage(
                                                imageUrl: attendance['photo_url'],
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Icon(
                                                  isCheckIn ? Icons.login : Icons.logout,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                errorWidget: (context, url, error) => Icon(
                                                  isCheckIn ? Icons.login : Icons.logout,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              isCheckIn ? Icons.login : Icons.logout,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    isCheckIn ? 'Check In' : 'Check Out',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('HH:mm:ss WIB').format(date),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Row(
                                        children: [
                                          Icon(
                                            attendance['is_within_radius'] 
                                                ? Icons.location_on 
                                                : Icons.location_off,
                                            size: 12,
                                            color: attendance['is_within_radius'] 
                                                ? primaryColor 
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            attendance['is_within_radius'] 
                                                ? 'Dalam radius' 
                                                : 'Luar radius',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: attendance['is_within_radius'] 
                                                  ? primaryColor 
                                                  : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: attendance['photo_url'] != null
                                      ? Icon(Icons.photo_camera, color: primaryColor, size: 20)
                                      : null,
                                  onTap: attendance['photo_url'] != null
                                      ? () => _showPhotoDialog(attendance['photo_url'], attendance)
                                      : null,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.event_busy, color: Colors.grey, size: 48),
                              const SizedBox(height: 8),
                              Text(
                                'Tidak ada absensi pada tanggal ${DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDay!)}',
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}