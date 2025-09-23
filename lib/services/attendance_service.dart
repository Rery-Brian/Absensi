// services/attendance_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart' hide Position;
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ================== USER PROFILE OPERATIONS ==================
  
  /// Load current user profile from database
  Future<UserProfile?> loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      print('=== DEBUG loadUserProfile ===');
      print('Current user: ${user?.id}');
      print('User email: ${user?.email}');
      
      if (user == null) {
        print('❌ No authenticated user found');
        return null;
      }

      print('🔍 Querying user_profiles table...');
      final profileResponse = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      print('📦 Profile response: $profileResponse');
      
      if (profileResponse == null) {
        print('⚠️ No profile found, attempting to create...');
        await _createUserProfile(user);
        
        // Try to load again after creation
        final newProfileResponse = await _supabase
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
            
        return newProfileResponse != null ? UserProfile.fromJson(newProfileResponse) : null;
      } else {
        print('✅ Profile found: ${profileResponse['display_name']}');
        return UserProfile.fromJson(profileResponse);
      }
    } catch (e) {
      print('❌ Error in loadUserProfile: $e');
      print('Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Create new user profile
  Future<void> _createUserProfile(User user) async {
    try {
      String firstName = user.userMetadata?['first_name'] ?? 'User';
      String lastName = user.userMetadata?['last_name'] ?? '';

      // If no metadata available, use email prefix
      if (firstName == 'User' && lastName.isEmpty) {
        final emailName = user.email?.split('@')[0] ?? 'User';
        firstName = emailName;
      }

      await _supabase.from('user_profiles').insert({
        'id': user.id,
        'first_name': firstName,
        'last_name': lastName,
        'display_name': '$firstName $lastName'.trim(),
        'is_active': true,
      });

      print('User profile created with name: $firstName $lastName');
    } catch (e) {
      print('Error creating user profile: $e');
      throw Exception('Error creating user profile: $e');
    }
  }

  // ================== ORGANIZATION MEMBER OPERATIONS ==================
  
  /// Load organization member data with related information
  Future<OrganizationMember?> loadOrganizationMember() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('No authenticated user found');
        return null;
      }

      print('Loading organization member for user: ${user.id}');

      // Get organization member
      final memberResponse = await _supabase
          .from('organization_members')
          .select('*')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (memberResponse == null) {
        print('User is not a member of any organization');
        print('Attempting auto-registration...');
        
        final autoRegistered = await tryAutoRegisterToOrganization(user.id);
        if (autoRegistered) {
          // Recursive call to load the newly created member
          return await loadOrganizationMember();
        }
        
        return null;
      }

      // Load related data separately to avoid JOIN issues
      Map<String, dynamic>? orgDetails;
      Map<String, dynamic>? deptDetails;
      Map<String, dynamic>? posDetails;

      // Get organization details
      try {
        orgDetails = await _supabase
            .from('organizations')
            .select('id, name, code')
            .eq('id', memberResponse['organization_id'])
            .single();
        print('Organization loaded: ${orgDetails['name']}');
      } catch (e) {
        print('Error loading organization: $e');
      }

      // Get department details if exists
      if (memberResponse['department_id'] != null) {
        try {
          deptDetails = await _supabase
              .from('departments')
              .select('id, name, code')
              .eq('id', memberResponse['department_id'])
              .maybeSingle();
          print('Department loaded: ${deptDetails?['name'] ?? 'None'}');
        } catch (e) {
          print('Error loading department: $e');
        }
      }

      // Get position details if exists
      if (memberResponse['position_id'] != null) {
        try {
          posDetails = await _supabase
              .from('positions')
              .select('id, title, code')
              .eq('id', memberResponse['position_id'])
              .maybeSingle();
          print('Position loaded: ${posDetails?['title'] ?? 'None'}');
        } catch (e) {
          print('Error loading position: $e');
        }
      }

      // Combine all data
      final combinedResponse = {
        ...memberResponse,
        'organizations': orgDetails,
        'departments': deptDetails,
        'positions': posDetails,
      };

      print('Organization member loaded successfully');
      return OrganizationMember.fromJson(combinedResponse);
    } catch (e) {
      print('Error loading organization member: $e');
      throw Exception('Error loading organization member: $e');
    }
  }

  /// Auto-register user to default organization
  Future<bool> tryAutoRegisterToOrganization(String userId) async {
    try {
      print('Attempting auto-registration for user: $userId');
      
      // Check if there's a default organization to register to
      final defaultOrg = await _supabase
          .from('organizations')
          .select('id, code')
          .eq('code', 'COMPANY001')
          .maybeSingle();
          
      if (defaultOrg == null) {
        print('No default organization found with code COMPANY001');
        return false;
      }

      // Check for default department and position
      final defaultDept = await _supabase
          .from('departments')
          .select('id')
          .eq('organization_id', defaultOrg['id'])
          .eq('code', 'IT')
          .maybeSingle();
          
      final defaultPos = await _supabase
          .from('positions')
          .select('id')
          .eq('organization_id', defaultOrg['id'])
          .eq('code', 'STAFF')
          .maybeSingle();

      // Insert new organization member
      final memberData = {
        'organization_id': defaultOrg['id'],
        'user_id': userId,
        'department_id': defaultDept?['id'],
        'position_id': defaultPos?['id'],
        'hire_date': DateTime.now().toIso8601String().split('T')[0],
        'is_active': true,
      };

      final result = await _supabase
          .from('organization_members')
          .insert(memberData)
          .select()
          .single();

      print('User auto-registered successfully with member ID: ${result['id']}');
      return true;
    } catch (e) {
      print('Auto-registration failed: $e');
      return false;
    }
  }

  // ================== ATTENDANCE DEVICE OPERATIONS ==================
  
  /// Load attendance device for organization
  Future<AttendanceDevice?> loadAttendanceDevice(String organizationId) async {
    try {
      print('Loading attendance device for organization: $organizationId');

      final deviceResponse = await _supabase
          .from('attendance_devices')
          .select('''
            *,
            device_types(name, category)
          ''')
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (deviceResponse != null) {
        print('Attendance device loaded: ${deviceResponse['device_name']}');
        print('Device coordinates: ${deviceResponse['latitude']}, ${deviceResponse['longitude']}');
        print('Device radius: ${deviceResponse['radius_meters']}m');
        
        return AttendanceDevice.fromJson(deviceResponse);
      } else {
        print('No attendance device found for organization');
        return null;
      }
    } catch (e) {
      print('Error loading attendance device: $e');
      throw Exception('Error loading attendance device: $e');
    }
  }

  // ================== ATTENDANCE RECORDS OPERATIONS ==================
  
  /// Load today's attendance records for member
  Future<List<AttendanceRecord>> loadTodayAttendanceRecords(String organizationMemberId) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      print('Loading today attendance records for member: $organizationMemberId, date: $today');

      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            shifts(id, name, start_time, end_time)
          ''')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .order('created_at');

      final records = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceRecord.fromJson(json))
          .toList();

      print('Today attendance records loaded: ${records.length} records');
      return records;
    } catch (e) {
      print('Error loading today attendance records: $e');
      throw Exception('Error loading today attendance records: $e');
    }
  }

  /// Load recent attendance records for member
  Future<List<AttendanceRecord>> loadRecentAttendanceRecords(String organizationMemberId) async {
    try {
      print('Loading recent attendance records for member: $organizationMemberId');

      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            shifts(id, name, start_time, end_time)
          ''')
          .eq('organization_member_id', organizationMemberId)
          .order('attendance_date', ascending: false)
          .limit(30); // Get last 30 days

      final records = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceRecord.fromJson(json))
          .toList();

      print('Recent attendance records loaded: ${records.length} records');
      return records;
    } catch (e) {
      print('Error loading recent attendance records: $e');
      throw Exception('Error loading recent attendance records: $e');
    }
  }

  /// Load today's attendance logs for member
  Future<List<AttendanceLog>> getTodayAttendanceLogs(String organizationMemberId) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      final startOfDay = '$today 00:00:00';
      final endOfDay = '$today 23:59:59';
      
      print('Loading today attendance logs for member: $organizationMemberId');

      final response = await _supabase
          .from('attendance_logs')
          .select('*')
          .eq('organization_member_id', organizationMemberId)
          .gte('event_time', startOfDay)
          .lte('event_time', endOfDay)
          .order('event_time');

      final logs = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceLog.fromJson(json))
          .toList();

      print('Today attendance logs loaded: ${logs.length} logs');
      return logs;
    } catch (e) {
      print('Error loading today attendance logs: $e');
      throw Exception('Error loading today attendance logs: $e');
    }
  }

  // ================== SCHEDULE OPERATIONS ==================
  
  /// Load current schedule for member
  Future<MemberSchedule?> loadCurrentSchedule(String organizationMemberId) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      print('Loading current schedule for member: $organizationMemberId, date: $today');

      final scheduleResponse = await _supabase
          .from('member_schedules')
          .select('''
            *,
            shifts(id, name, start_time, end_time, code),
            work_schedules(id, name, code, description)
          ''')
          .eq('organization_member_id', organizationMemberId)
          .lte('effective_date', today)
          .or('end_date.is.null,end_date.gte.$today')
          .eq('is_active', true)
          .order('effective_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (scheduleResponse != null) {
        print('Current schedule loaded: ${scheduleResponse['shifts']?['name'] ?? scheduleResponse['work_schedules']?['name'] ?? 'Unknown'}');
        return MemberSchedule.fromJson(scheduleResponse);
      } else {
        print('No current schedule found for member');
        return null;
      }
    } catch (e) {
      print('Error loading current schedule: $e');
      throw Exception('Error loading current schedule: $e');
    }
  }

  /// Load work schedule details for a specific day
  Future<WorkScheduleDetails?> loadWorkScheduleDetails(String workScheduleId, int dayOfWeek) async {
    try {
      print('Loading work schedule details for schedule: $workScheduleId, day: $dayOfWeek');

      final response = await _supabase
          .from('work_schedule_details')
          .select('*')
          .eq('work_schedule_id', workScheduleId)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      if (response != null) {
        print('Work schedule details loaded for day $dayOfWeek');
        print('Is working day: ${response['is_working_day']}');
        print('Start time: ${response['start_time']}');
        print('End time: ${response['end_time']}');
        return WorkScheduleDetails.fromJson(response);
      } else {
        print('No work schedule details found for day $dayOfWeek');
        return null;
      }
    } catch (e) {
      print('Error loading work schedule details: $e');
      throw Exception('Error loading work schedule details: $e');
    }
  }

  /// Check if today is a working day based on schedule
  Future<bool> isTodayWorkingDay(String organizationMemberId) async {
    try {
      final schedule = await loadCurrentSchedule(organizationMemberId);
      if (schedule?.workScheduleId != null) {
        final today = DateTime.now();
        final dayOfWeek = today.weekday % 7; // Convert to 0-6 format
        final scheduleDetails = await loadWorkScheduleDetails(schedule!.workScheduleId!, dayOfWeek);
        return scheduleDetails?.isWorkingDay ?? true;
      }
      return true; // Default to working day if no schedule found
    } catch (e) {
      print('Error checking if today is working day: $e');
      return true; // Default to working day on error
    }
  }

  // ================== LOCATION OPERATIONS ==================
  
  /// Get current GPS location
  Future<Position> getCurrentLocation() async {
    try {
      print('Checking location services...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      print('Checking location permissions...');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      print('Getting current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      print('Current position: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Error getting location: $e');
      throw Exception('Failed to get location: $e');
    }
  }

  /// Calculate distance between two coordinates
  double? calculateDistance(double lat1, double lon1, double? lat2, double? lon2) {
    if (lat2 == null || lon2 == null) return null;
    
    final distance = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    print('Distance calculated: ${distance.toStringAsFixed(2)}m');
    return distance;
  }

  /// Check if current position is within device radius
  bool isWithinRadius(Position currentPosition, AttendanceDevice device) {
    if (!device.hasValidCoordinates) {
      print('Device coordinates not available');
      return false;
    }

    double? distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      device.latitude,
      device.longitude,
    );

    if (distance == null) {
      print('Cannot calculate distance');
      return false;
    }

    final withinRadius = distance <= device.radiusMeters;
    print('Within radius check: $withinRadius (distance: ${distance.toStringAsFixed(2)}m, radius: ${device.radiusMeters}m)');
    
    return withinRadius;
  }

  // ================== PHOTO OPERATIONS ==================
  
  /// Upload photo to Supabase Storage
  Future<String?> uploadPhoto(String imagePath) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final jakartaTime = TimezoneHelper.nowInJakarta();
      final timestamp = jakartaTime.millisecondsSinceEpoch;
      final fileName = '${user.id}/${timestamp}.jpg';
      final file = File(imagePath);

      print('Uploading photo to: $fileName');
      print('File size: ${await file.length()} bytes');

      // Upload to storage bucket
      await _supabase.storage
          .from('attendance_photos')
          .upload(fileName, file, fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ));

      // Get public URL
      final publicUrl = _supabase.storage
          .from('attendance_photos')
          .getPublicUrl(fileName);

      print('Photo uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('Error uploading photo: $e');
      throw Exception('Failed to upload photo: $e');
    }
  }

  // ================== ATTENDANCE OPERATIONS ==================
  
  /// Perform attendance (check in, check out, break out, break in)
  Future<bool> performAttendance({
    required String type,
    required String organizationMemberId,
    required Position currentPosition,
    required String photoUrl,
    AttendanceDevice? device,
    MemberSchedule? schedule,
    List<AttendanceRecord>? todayRecords,
    WorkScheduleDetails? scheduleDetails,
  }) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      final now = TimezoneHelper.nowInJakarta();

      print('Performing attendance: $type for member: $organizationMemberId');
      print('Date: $today, Time: ${now.toIso8601String()}');

      // Get today's logs to track break state
      final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
      final existingRecord = todayRecords?.isNotEmpty == true ? todayRecords!.first : null;

      // Validate attendance sequence and timing
      await _validateAttendanceSequence(type, existingRecord, todayLogs, scheduleDetails);

      // Handle different attendance types
      switch (type) {
        case 'check_in':
          return await _performCheckIn(
            organizationMemberId, today, now, currentPosition, photoUrl, 
            device, schedule, existingRecord, scheduleDetails
          );
          
        case 'check_out':
          return await _performCheckOut(
            organizationMemberId, now, currentPosition, photoUrl, 
            device, existingRecord!, scheduleDetails
          );
          
        case 'break_out':
          return await _performBreakOut(
            organizationMemberId, now, currentPosition, photoUrl, device
          );
          
        case 'break_in':
          return await _performBreakIn(
            organizationMemberId, now, currentPosition, photoUrl, device
          );
          
        default:
          throw Exception('Unknown attendance type: $type');
      }

    } catch (e) {
      print('Error performing attendance: $e');
      throw Exception('Failed to perform attendance: $e');
    }
  }

  /// Perform check in
  Future<bool> _performCheckIn(
    String organizationMemberId, 
    String today, 
    DateTime now, 
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device,
    MemberSchedule? schedule,
    AttendanceRecord? existingRecord,
    WorkScheduleDetails? scheduleDetails
  ) async {
    if (existingRecord != null) {
      // Update existing record
      Map<String, dynamic> updateData = {
        'actual_check_in': now.toIso8601String(),
        'check_in_photo_url': photoUrl,
        'check_in_location': {
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
        },
        'check_in_method': 'mobile_app',
        'check_in_device_id': device?.id,
        'status': 'present',
        'updated_at': now.toIso8601String(),
      };

      // Calculate lateness
      if (scheduleDetails?.startTime != null) {
        final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
        final actualStart = TimeOfDay.fromDateTime(now);
        final lateMinutes = _calculateLateMinutes(scheduledStart, actualStart);
        if (lateMinutes > 0) {
          updateData['late_minutes'] = lateMinutes;
        }
      }

      await _supabase
          .from('attendance_records')
          .update(updateData)
          .eq('id', existingRecord.id);

      print('Check-in updated on existing record');
    } else {
      // Create new record
      Map<String, dynamic> newRecordData = {
        'organization_member_id': organizationMemberId,
        'attendance_date': today,
        'actual_check_in': now.toIso8601String(),
        'check_in_photo_url': photoUrl,
        'check_in_location': {
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
        },
        'check_in_method': 'mobile_app',
        'check_in_device_id': device?.id,
        'status': 'present',
        'scheduled_shift_id': schedule?.shiftId,
        'validation_status': 'pending',
      };

      // Add scheduled times and calculate lateness
      if (scheduleDetails != null) {
        if (scheduleDetails.startTime != null) {
          newRecordData['scheduled_start'] = scheduleDetails.startTime;
          final scheduledStart = TimeHelper.parseTimeString(scheduleDetails.startTime!);
          final actualStart = TimeOfDay.fromDateTime(now);
          final lateMinutes = _calculateLateMinutes(scheduledStart, actualStart);
          if (lateMinutes > 0) {
            newRecordData['late_minutes'] = lateMinutes;
          }
        }
        if (scheduleDetails.endTime != null) {
          newRecordData['scheduled_end'] = scheduleDetails.endTime;
        }
      }

      await _supabase.from('attendance_records').insert(newRecordData);
      print('New attendance record created for check-in');
    }

    // Log the event
    await _logAttendanceEvent(
      organizationMemberId, 'check_in', now, currentPosition, device
    );

    return true;
  }

  /// Perform check out
  Future<bool> _performCheckOut(
    String organizationMemberId,
    DateTime now,
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device,
    AttendanceRecord existingRecord,
    WorkScheduleDetails? scheduleDetails
  ) async {
    Map<String, dynamic> updateData = {
      'actual_check_out': now.toIso8601String(),
      'check_out_photo_url': photoUrl,
      'check_out_location': {
        'latitude': currentPosition.latitude,
        'longitude': currentPosition.longitude,
      },
      'check_out_method': 'mobile_app',
      'check_out_device_id': device?.id,
      'updated_at': now.toIso8601String(),
    };

    // Calculate work duration
    if (existingRecord.actualCheckIn != null) {
      final workDuration = now.difference(existingRecord.actualCheckIn!).inMinutes;
      updateData['work_duration_minutes'] = workDuration;

      // Calculate overtime
      if (scheduleDetails?.minimumHours != null) {
        final expectedMinutes = (scheduleDetails!.minimumHours! * 60).toInt();
        final overtimeMinutes = workDuration - expectedMinutes;
        if (overtimeMinutes > 0) {
          updateData['overtime_minutes'] = overtimeMinutes;
        }
      }
    }

    // Calculate early leave
    if (scheduleDetails?.endTime != null) {
      final scheduledEnd = TimeHelper.parseTimeString(scheduleDetails!.endTime!);
      final actualEnd = TimeOfDay.fromDateTime(now);
      final earlyMinutes = _calculateEarlyLeaveMinutes(scheduledEnd, actualEnd);
      if (earlyMinutes > 0) {
        updateData['early_leave_minutes'] = earlyMinutes;
      }
    }

    await _supabase
        .from('attendance_records')
        .update(updateData)
        .eq('id', existingRecord.id);

    // Log the event
    await _logAttendanceEvent(
      organizationMemberId, 'check_out', now, currentPosition, device
    );

    print('Check-out completed successfully');
    return true;
  }

  /// Perform break out
  Future<bool> _performBreakOut(
    String organizationMemberId,
    DateTime now,
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device
  ) async {
    // Log break out event
    await _logAttendanceEvent(
      organizationMemberId, 'break_out', now, currentPosition, device
    );

    print('Break out logged successfully');
    return true;
  }

  /// Perform break in (resume work)
  Future<bool> _performBreakIn(
    String organizationMemberId,
    DateTime now,
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device
  ) async {
    // Get today's logs to calculate break duration
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
    
    // Find the last break_out event
    final lastBreakOut = todayLogs
        .where((log) => log.eventType == 'break_out')
        .lastOrNull;

    if (lastBreakOut != null) {
      final breakDuration = now.difference(lastBreakOut.eventTime).inMinutes;
      
      // Update today's attendance record with break duration
      final today = TimezoneHelper.getTodayDateString();
      final todayRecords = await loadTodayAttendanceRecords(organizationMemberId);
      
      if (todayRecords.isNotEmpty) {
        final currentBreakDuration = todayRecords.first.breakDurationMinutes ?? 0;
        await _supabase
            .from('attendance_records')
            .update({
              'break_duration_minutes': currentBreakDuration + breakDuration,
              'updated_at': now.toIso8601String(),
            })
            .eq('id', todayRecords.first.id);
      }
    }

    // Log break in event
    await _logAttendanceEvent(
      organizationMemberId, 'break_in', now, currentPosition, device
    );

    print('Break in (resume work) logged successfully');
    return true;
  }

  /// Log attendance event
  Future<void> _logAttendanceEvent(
    String organizationMemberId,
    String eventType,
    DateTime eventTime,
    Position currentPosition,
    AttendanceDevice? device
  ) async {
    await _supabase.from('attendance_logs').insert({
      'organization_member_id': organizationMemberId,
      'event_type': eventType,
      'event_time': eventTime.toIso8601String(),
      'device_id': device?.id,
      'method': 'mobile_app',
      'location': {
        'latitude': currentPosition.latitude,
        'longitude': currentPosition.longitude,
      },
      'is_verified': device != null ? isWithinRadius(currentPosition, device) : false,
    });
  }

  /// Validate attendance sequence and timing
  Future<void> _validateAttendanceSequence(
    String type, 
    AttendanceRecord? existingRecord, 
    List<AttendanceLog> todayLogs,
    WorkScheduleDetails? scheduleDetails
  ) async {
    final now = TimeHelper.getCurrentTime();
    
    // Check if today is a working day
    if (scheduleDetails != null && !scheduleDetails.isWorkingDay) {
      throw Exception('Today is not a working day according to your schedule');
    }

    // Get last event from logs
    final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

    switch (type) {
      case 'check_in':
        if (existingRecord?.hasCheckedIn == true) {
          throw Exception('You have already checked in today');
        }
        // Check early check-in window
        if (scheduleDetails?.startTime != null) {
          final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
          final maxEarlyMinutes = 30; // Allow 30 minutes early check-in
          if (_isTimeBeforeScheduled(now, scheduledStart, maxEarlyMinutes)) {
            throw Exception('Check-in is too early. Scheduled start: ${scheduleDetails.startTime}');
          }
        }
        break;
        
      case 'check_out':
        if (existingRecord?.hasCheckedIn != true) {
          throw Exception('You must check in before checking out');
        }
        if (existingRecord?.hasCheckedOut == true) {
          throw Exception('You have already checked out today');
        }
        // Check minimum work hours
        if (existingRecord?.actualCheckIn != null && scheduleDetails?.minimumHours != null) {
          final workHours = DateTime.now().difference(existingRecord!.actualCheckIn!).inHours;
          if (workHours < scheduleDetails!.minimumHours!) {
            throw Exception('Minimum work hours (${scheduleDetails.minimumHours}h) not completed');
          }
        }
        break;
        
      case 'break_out':
        if (existingRecord?.hasCheckedIn != true) {
          throw Exception('You must check in before taking a break');
        }
        // Check if already on break
        if (lastLog?.eventType == 'break_out') {
          throw Exception('You are already on break. Please resume work first.');
        }
        // Check break time window
        if (scheduleDetails?.breakStart != null && scheduleDetails?.breakEnd != null) {
          final breakStart = TimeHelper.parseTimeString(scheduleDetails!.breakStart!);
          final breakEnd = TimeHelper.parseTimeString(scheduleDetails.breakEnd!);
          if (!_isWithinBreakWindow(now, breakStart, breakEnd)) {
            throw Exception('Break is only allowed during: ${scheduleDetails.breakStart} - ${scheduleDetails.breakEnd}');
          }
        }
        break;
        
      case 'break_in':
        if (existingRecord?.hasCheckedIn != true) {
          throw Exception('You must check in first');
        }
        // Check if currently on break
        if (lastLog?.eventType != 'break_out') {
          throw Exception('You are not currently on break');
        }
        break;
    }
  }

  /// Check if current time is before scheduled time by more than allowed minutes
  bool _isTimeBeforeScheduled(TimeOfDay current, TimeOfDay scheduled, int maxEarlyMinutes) {
    final currentMinutes = TimeHelper.timeToMinutes(current);
    final scheduledMinutes = TimeHelper.timeToMinutes(scheduled);
    return currentMinutes < (scheduledMinutes - maxEarlyMinutes);
  }

  /// Check if current time is within break window
  bool _isWithinBreakWindow(TimeOfDay current, TimeOfDay breakStart, TimeOfDay breakEnd) {
    return TimeHelper.isWithinTimeWindow(current, breakStart, breakEnd);
  }

  /// Calculate late minutes
  int _calculateLateMinutes(TimeOfDay scheduled, TimeOfDay actual) {
    final diff = TimeHelper.calculateTimeDifference(scheduled, actual);
    return TimeHelper.isTimeAfter(actual, scheduled) ? diff : 0;
  }

  /// Calculate early leave minutes
  int _calculateEarlyLeaveMinutes(TimeOfDay scheduled, TimeOfDay actual) {
    final diff = TimeHelper.calculateTimeDifference(actual, scheduled);
    return TimeHelper.isTimeBefore(actual, scheduled) ? diff : 0;
  }

  /// Get attendance type label for display
  String _getAttendanceTypeLabel(String type) {
    switch (type) {
      case 'check_in':
        return 'Check-in';
      case 'check_out':
        return 'Check-out';
      case 'break_out':
        return 'Break out';
      case 'break_in':
        return 'Break in';
      default:
        return 'Attendance';
    }
  }

  /// Get current attendance status based on today's logs
  Future<AttendanceStatus> getCurrentAttendanceStatus(String organizationMemberId) async {
    try {
      final todayRecords = await loadTodayAttendanceRecords(organizationMemberId);
      final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
      
      final existingRecord = todayRecords.isNotEmpty ? todayRecords.first : null;
      final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

      if (existingRecord == null || !existingRecord.hasCheckedIn) {
        return AttendanceStatus.notCheckedIn;
      }

      if (existingRecord.hasCheckedOut) {
        return AttendanceStatus.checkedOut;
      }

      if (lastLog?.eventType == 'break_out') {
        return AttendanceStatus.onBreak;
      }

      return AttendanceStatus.working;
    } catch (e) {
      print('Error getting attendance status: $e');
      return AttendanceStatus.unknown;
    }
  }

  /// Get next available actions based on current status
  Future<List<AttendanceAction>> getAvailableActions(String organizationMemberId) async {
    try {
      final status = await getCurrentAttendanceStatus(organizationMemberId);
      final schedule = await loadCurrentSchedule(organizationMemberId);
      
      WorkScheduleDetails? scheduleDetails;
      if (schedule?.workScheduleId != null) {
        final dayOfWeek = DateTime.now().weekday % 7;
        scheduleDetails = await loadWorkScheduleDetails(schedule!.workScheduleId!, dayOfWeek);
      }

      final currentTime = TimeHelper.getCurrentTime();
      List<AttendanceAction> actions = [];

      switch (status) {
        case AttendanceStatus.notCheckedIn:
          actions.add(AttendanceAction(
            type: 'check_in',
            label: 'Check In',
            isEnabled: _canCheckIn(currentTime, scheduleDetails),
            reason: _getCheckInReason(currentTime, scheduleDetails),
          ));
          break;

        case AttendanceStatus.working:
          // Add break out action if within break time
          if (_canTakeBreak(currentTime, scheduleDetails)) {
            actions.add(AttendanceAction(
              type: 'break_out',
              label: 'Take Break',
              isEnabled: true,
            ));
          }
          
          // Add check out action if minimum work time is met
          if (_canCheckOut(scheduleDetails)) {
            actions.add(AttendanceAction(
              type: 'check_out',
              label: 'Check Out',
              isEnabled: true,
            ));
          } else {
            actions.add(AttendanceAction(
              type: 'check_out',
              label: 'Check Out',
              isEnabled: false,
              reason: 'Minimum work hours not completed',
            ));
          }
          break;

        case AttendanceStatus.onBreak:
          actions.add(AttendanceAction(
            type: 'break_in',
            label: 'Resume Work',
            isEnabled: true,
          ));
          break;

        case AttendanceStatus.checkedOut:
          // No actions available after check out
          break;

        case AttendanceStatus.unknown:
          // Fallback actions
          actions.add(AttendanceAction(
            type: 'check_in',
            label: 'Check In',
            isEnabled: true,
          ));
          break;
      }

      return actions;
    } catch (e) {
      print('Error getting available actions: $e');
      return [];
    }
  }

  /// Check if can check in
  bool _canCheckIn(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (scheduleDetails?.startTime == null) return true;
    
    final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
    return !_isTimeBeforeScheduled(currentTime, scheduledStart, 30);
  }

  /// Get check in reason
  String? _getCheckInReason(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (!_canCheckIn(currentTime, scheduleDetails)) {
      return 'Too early to check in. Scheduled start: ${scheduleDetails?.startTime}';
    }
    return null;
  }

  /// Check if can take break
  bool _canTakeBreak(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (scheduleDetails?.breakStart == null || scheduleDetails?.breakEnd == null) {
      return true; // Allow break anytime if no schedule
    }
    
    final breakStart = TimeHelper.parseTimeString(scheduleDetails!.breakStart!);
    final breakEnd = TimeHelper.parseTimeString(scheduleDetails.breakEnd!);
    return _isWithinBreakWindow(currentTime, breakStart, breakEnd);
  }

  /// Check if can check out
  bool _canCheckOut(WorkScheduleDetails? scheduleDetails) {
    // For now, always allow check out
    // In real implementation, check minimum work hours
    return true;
  }

  // ================== AUTH OPERATIONS ==================
  
  /// Sign out current user
  Future<void> signOut() async {
    try {
      print('Signing out user...');
      await _supabase.auth.signOut();
      print('User signed out successfully');
    } catch (e) {
      print('Error signing out: $e');
      throw Exception('Failed to sign out: $e');
    }
  }

  // ================== UTILITY METHODS ==================
  
  /// Get current authenticated user
  User? get currentUser => _supabase.auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => _supabase.auth.currentUser != null;

  /// Get Supabase client instance (for direct access if needed)
  SupabaseClient get supabase => _supabase;
}

// ================== ENUMS AND DATA CLASSES ==================

/// Attendance status enum
enum AttendanceStatus {
  notCheckedIn,
  working,
  onBreak,
  checkedOut,
  unknown,
}

/// Attendance action data class
class AttendanceAction {
  final String type;
  final String label;
  final bool isEnabled;
  final String? reason;

  AttendanceAction({
    required this.type,
    required this.label,
    this.isEnabled = true,
    this.reason,
  });
}

/// Additional model class for attendance logs
class AttendanceLog {
  final String id;
  final String organizationMemberId;
  final String? attendanceRecordId;
  final String eventType;
  final DateTime eventTime;
  final String? deviceId;
  final String method;
  final Map<String, dynamic>? location;
  final bool isVerified;

  AttendanceLog({
    required this.id,
    required this.organizationMemberId,
    this.attendanceRecordId,
    required this.eventType,
    required this.eventTime,
    this.deviceId,
    required this.method,
    this.location,
    required this.isVerified,
  });

  factory AttendanceLog.fromJson(Map<String, dynamic> json) {
    return AttendanceLog(
      id: json['id']?.toString() ?? '',
      organizationMemberId: json['organization_member_id']?.toString() ?? '',
      attendanceRecordId: json['attendance_record_id']?.toString(),
      eventType: json['event_type']?.toString() ?? '',
      eventTime: DateTime.parse(json['event_time']),
      deviceId: json['device_id']?.toString(),
      method: json['method']?.toString() ?? '',
      location: json['location'] as Map<String, dynamic>?,
      isVerified: json['is_verified'] ?? false,
    );
  }
}