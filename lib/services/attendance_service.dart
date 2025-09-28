import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart' hide Position;
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<UserProfile?> loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return null;
      }

      final profileResponse = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profileResponse == null) {
        await _createUserProfile(user);
        
        final newProfileResponse = await _supabase
            .from('user_profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
            
        return newProfileResponse != null ? UserProfile.fromJson(newProfileResponse) : null;
      } else {
        return UserProfile.fromJson(profileResponse);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createUserProfile(User user) async {
    try {
      String firstName = user.userMetadata?['first_name'] ?? 'User';
      String lastName = user.userMetadata?['last_name'] ?? '';

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
    } catch (e) {
      throw Exception('Error creating user profile: $e');
    }
  }

  Future<OrganizationMember?> loadOrganizationMember() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return null;
      }

      final memberResponse = await _supabase
          .from('organization_members')
          .select('*')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (memberResponse == null) {
        final autoRegistered = await tryAutoRegisterToOrganization(user.id);
        if (autoRegistered) {
          return await loadOrganizationMember();
        }
        
        return null;
      }

      Map<String, dynamic>? orgDetails;
      Map<String, dynamic>? deptDetails;
      Map<String, dynamic>? posDetails;

      orgDetails = await _supabase
          .from('organizations')
          .select('id, name, code, timezone')
          .eq('id', memberResponse['organization_id'])
          .single();

      if (orgDetails?['timezone'] != null) {
        TimezoneHelper.initialize(orgDetails!['timezone']);
        debugPrint('Organization timezone loaded: ${orgDetails['timezone']}');
      }

      if (memberResponse['department_id'] != null) {
        deptDetails = await _supabase
            .from('departments')
            .select('id, name, code')
            .eq('id', memberResponse['department_id'])
            .maybeSingle();
      }

      if (memberResponse['position_id'] != null) {
        posDetails = await _supabase
            .from('positions')
            .select('id, title, code')
            .eq('id', memberResponse['position_id'])
            .maybeSingle();
      }

      final combinedResponse = {
        ...memberResponse,
        'organizations': orgDetails,
        'departments': deptDetails,
        'positions': posDetails,
      };

      return OrganizationMember.fromJson(combinedResponse);
    } catch (e) {
      throw Exception('Error loading organization member: $e');
    }
  }

  Future<bool> tryAutoRegisterToOrganization(String userId) async {
    try {
      final defaultOrg = await _supabase
          .from('organizations')
          .select('id, code, timezone')
          .eq('code', 'COMPANY001')
          .maybeSingle();

      if (defaultOrg?['timezone'] != null) {
        TimezoneHelper.initialize(defaultOrg!['timezone']);
        debugPrint('Default organization timezone loaded: ${defaultOrg['timezone']}');
      }
          
      if (defaultOrg == null) {
        return false;
      }

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

      final memberData = {
        'organization_id': defaultOrg['id'],
        'user_id': userId,
        'department_id': defaultDept?['id'],
        'position_id': defaultPos?['id'],
        'hire_date': DateTime.now().toIso8601String().split('T')[0],
        'is_active': true,
      };

      await _supabase
          .from('organization_members')
          .insert(memberData)
          .select()
          .single();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<AttendanceDevice?> loadAttendanceDevice(String organizationId) async {
    try {
      final deviceResponse = await _supabase
          .from('attendance_devices')
          .select('*') // Simplified, removed device_types join
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (deviceResponse != null) {
        return AttendanceDevice.fromJson(deviceResponse);
      } else {
        return null;
      }
    } catch (e) {
      throw Exception('Error loading attendance device: $e');
    }
  }

  Future<void> _validateUserAccess(String organizationMemberId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    final memberVerification = await _supabase
        .from('organization_members')
        .select('id, user_id')
        .eq('id', organizationMemberId)
        .eq('user_id', user.id)
        .eq('is_active', true)
        .maybeSingle();

    if (memberVerification == null) {
      throw Exception('Unauthorized: Access denied to organization member data');
    }
  }

  Future<List<AttendanceRecord>> loadTodayAttendanceRecords(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final today = TimezoneHelper.getTodayDateString();

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

      return records;
    } catch (e) {
      throw Exception('Error loading today attendance records: $e');
    }
  }

  Future<List<AttendanceRecord>> loadRecentAttendanceRecords(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            shifts(id, name, start_time, end_time)
          ''')
          .eq('organization_member_id', organizationMemberId)
          .order('attendance_date', ascending: false)
          .limit(30);

      final records = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceRecord.fromJson(json))
          .toList();

      return records;
    } catch (e) {
      throw Exception('Error loading recent attendance records: $e');
    }
  }

  Future<List<AttendanceLog>> getTodayAttendanceLogs(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final today = TimezoneHelper.getTodayDateString();
      final startOfDay = '$today 00:00:00';
      final endOfDay = '$today 23:59:59';
      
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

      return logs;
    } catch (e) {
      throw Exception('Error loading today attendance logs: $e');
    }
  }

  Future<MemberSchedule?> loadCurrentSchedule(String organizationMemberId) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      final user = _supabase.auth.currentUser;
      
      if (user == null) {
        throw Exception('No authenticated user');
      }

      debugPrint('Loading schedule for member: $organizationMemberId, user: ${user.id}');

      final memberVerification = await _supabase
          .from('organization_members')
          .select('id, user_id, organization_id')
          .eq('id', organizationMemberId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (memberVerification == null) {
        throw Exception('Unauthorized: Organization member does not belong to current user');
      }

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
        debugPrint('Found schedule: ${scheduleResponse}');
        return MemberSchedule.fromJson(scheduleResponse);
      } else {
        debugPrint('No active schedule found, trying to find default schedule');
        return await _getDefaultScheduleForMember(
          organizationMemberId, 
          memberVerification['organization_id'].toString()
        );
      }
    } catch (e) {
      debugPrint('Error loading current schedule: $e');
      throw Exception('Error loading current schedule: $e');
    }
  }

  Future<MemberSchedule?> _getDefaultScheduleForMember(String organizationMemberId, String organizationId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final defaultWorkSchedule = await _supabase
          .from('work_schedules')
          .select('id, name, code, description, organization_id')
          .eq('organization_id', organizationId)
          .eq('is_default', true)
          .eq('is_active', true)
          .maybeSingle();

      if (defaultWorkSchedule != null) {
        debugPrint('Found default work schedule: ${defaultWorkSchedule['name']}');
        
        return MemberSchedule(
          id: 'default',
          organizationMemberId: organizationMemberId,
          workScheduleId: defaultWorkSchedule['id'].toString(),
          shiftId: null,
          effectiveDate: DateTime.now(),
          endDate: null,
          isActive: true,
          workSchedule: WorkSchedule.fromJson(defaultWorkSchedule),
          shift: null,
        );
      }

      final defaultShift = await _supabase
          .from('shifts')
          .select('id, name, start_time, end_time, code, organization_id')
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      if (defaultShift != null) {
        debugPrint('Found default shift: ${defaultShift['name']}');
        
        return MemberSchedule(
          id: 'default_shift',
          organizationMemberId: organizationMemberId,
          workScheduleId: null,
          shiftId: defaultShift['id'].toString(),
          effectiveDate: DateTime.now(),
          endDate: null,
          isActive: true,
          workSchedule: null,
          shift: Shift.fromJson(defaultShift),
        );
      }

      debugPrint('No default schedule or shift found');
      return null;
    } catch (e) {
      debugPrint('Error getting default schedule: $e');
      return null;
    }
  }

  Future<WorkScheduleDetails?> loadWorkScheduleDetails(String workScheduleId, int dayOfWeek) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      debugPrint('Loading work schedule details for schedule: $workScheduleId, day: $dayOfWeek');

      final hasAccess = await _supabase
          .from('work_schedules')
          .select('id, organization_id')
          .eq('id', workScheduleId)
          .single();

      if (hasAccess == null) {
        throw Exception('Work schedule not found');
      }

      final memberCheck = await _supabase
          .from('organization_members')
          .select('id')
          .eq('user_id', user.id)
          .eq('organization_id', hasAccess['organization_id'])
          .eq('is_active', true)
          .maybeSingle();

      if (memberCheck == null) {
        throw Exception('Unauthorized: User does not have access to this work schedule');
      }

      final response = await _supabase
          .from('work_schedule_details')
          .select('*')
          .eq('work_schedule_id', workScheduleId)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      if (response != null) {
        debugPrint('Found work schedule details: $response');
        return WorkScheduleDetails.fromJson(response);
      } else {
        debugPrint('No work schedule details found for day $dayOfWeek');
        return null;
      }
    } catch (e) {
      debugPrint('Error loading work schedule details: $e');
      throw Exception('Error loading work schedule details: $e');
    }
  }

  Future<bool> isTodayWorkingDay(String organizationMemberId) async {
    try {
      final schedule = await loadCurrentSchedule(organizationMemberId);
      if (schedule?.workScheduleId != null) {
        final today = DateTime.now();
        final dayOfWeek = today.weekday;
        final scheduleDetails = await loadWorkScheduleDetails(schedule!.workScheduleId!, dayOfWeek);
        return scheduleDetails?.isWorkingDay ?? true;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  Future<Position> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  double? calculateDistance(double lat1, double lon1, double? lat2, double? lon2) {
    if (lat2 == null || lon2 == null) return null;
    
    final distance = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    return distance;
  }

  bool isWithinRadius(Position currentPosition, AttendanceDevice device) {
    if (!device.hasValidCoordinates) {
      return false;
    }

    double? distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      device.latitude,
      device.longitude,
    );

    if (distance == null) {
      return false;
    }

    return distance <= device.radiusMeters;
  }

  Future<String?> uploadPhoto(String imagePath) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user');
      }

      final orgTime = TimezoneHelper.nowInOrgTime();
      final timestamp = orgTime.millisecondsSinceEpoch;
      final fileName = '${user.id}/$timestamp.jpg';
      final file = File(imagePath);

      await _supabase.storage
          .from('attendance_photos')
          .upload(fileName, file, fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ));

      final publicUrl = _supabase.storage
          .from('attendance_photos')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

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
      final now = TimezoneHelper.nowInOrgTime();

      final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
      final existingRecord = todayRecords?.isNotEmpty == true ? todayRecords!.first : null;

      await _validateAttendanceSequence(type, existingRecord, todayLogs, scheduleDetails);

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
      throw Exception('Failed to perform attendance: $e');
    }
  }

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

    } else {
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
    }

    await _logAttendanceEvent(
      organizationMemberId, 'check_in', now, currentPosition, device
    );

    return true;
  }

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

    if (existingRecord.actualCheckIn != null) {
      final workDuration = now.difference(existingRecord.actualCheckIn!).inMinutes;
      updateData['work_duration_minutes'] = workDuration;

      if (scheduleDetails?.minimumHours != null) {
        final expectedMinutes = (scheduleDetails!.minimumHours! * 60).toInt();
        final overtimeMinutes = workDuration - expectedMinutes;
        if (overtimeMinutes > 0) {
          updateData['overtime_minutes'] = overtimeMinutes;
        }
      }
    }

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

    await _logAttendanceEvent(
      organizationMemberId, 'check_out', now, currentPosition, device
    );

    return true;
  }

  Future<bool> _performBreakOut(
    String organizationMemberId,
    DateTime now,
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device
  ) async {
    await _logAttendanceEvent(
      organizationMemberId, 'break_out', now, currentPosition, device
    );

    return true;
  }

  Future<bool> _performBreakIn(
    String organizationMemberId,
    DateTime now,
    Position currentPosition,
    String photoUrl,
    AttendanceDevice? device
  ) async {
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
    
    final lastBreakOut = todayLogs
        .where((log) => log.eventType == 'break_out')
        .lastOrNull;

    if (lastBreakOut != null) {
      final breakDuration = now.difference(lastBreakOut.eventTime).inMinutes;
      
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

    await _logAttendanceEvent(
      organizationMemberId, 'break_in', now, currentPosition, device
    );

    return true;
  }

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

  Future<void> _validateAttendanceSequence(
    String type, 
    AttendanceRecord? existingRecord, 
    List<AttendanceLog> todayLogs,
    WorkScheduleDetails? scheduleDetails
  ) async {
    final now = TimeHelper.getCurrentTime();
    
    if (scheduleDetails != null && !scheduleDetails.isWorkingDay) {
      throw Exception('Today is not a working day according to your schedule');
    }

    final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

    switch (type) {
      case 'check_in':
        if (existingRecord?.hasCheckedIn == true) {
          throw Exception('You have already checked in today');
        }
        if (scheduleDetails?.startTime != null) {
          final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
          final maxEarlyMinutes = 30;
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
        if (lastLog?.eventType == 'break_out') {
          throw Exception('You are already on break. Please resume work first.');
        }
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
        if (lastLog?.eventType != 'break_out') {
          throw Exception('You are not currently on break');
        }
        break;
    }
  }

  bool _isTimeBeforeScheduled(TimeOfDay current, TimeOfDay scheduled, int maxEarlyMinutes) {
    final currentMinutes = TimeHelper.timeToMinutes(current);
    final scheduledMinutes = TimeHelper.timeToMinutes(scheduled);
    return currentMinutes < (scheduledMinutes - maxEarlyMinutes);
  }

  bool _isWithinBreakWindow(TimeOfDay current, TimeOfDay breakStart, TimeOfDay breakEnd) {
    return TimeHelper.isWithinTimeWindow(current, breakStart, breakEnd);
  }

  int _calculateLateMinutes(TimeOfDay scheduled, TimeOfDay actual) {
    final diff = TimeHelper.calculateTimeDifference(scheduled, actual);
    return TimeHelper.isTimeAfter(actual, scheduled) ? diff : 0;
  }

  int _calculateEarlyLeaveMinutes(TimeOfDay scheduled, TimeOfDay actual) {
    final diff = TimeHelper.calculateTimeDifference(actual, scheduled);
    return TimeHelper.isTimeBefore(actual, scheduled) ? diff : 0;
  }

  Future<AttendanceStatus> getCurrentAttendanceStatus(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
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
      return AttendanceStatus.unknown;
    }
  }

  Future<List<AttendanceAction>> getAvailableActions(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final status = await getCurrentAttendanceStatus(organizationMemberId);
      final schedule = await loadCurrentSchedule(organizationMemberId);
      
      WorkScheduleDetails? scheduleDetails;
      if (schedule?.workScheduleId != null) {
        final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
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
          if (_canTakeBreak(currentTime, scheduleDetails)) {
            actions.add(AttendanceAction(
              type: 'break_out',
              label: 'Take Break',
              isEnabled: true,
            ));
          }
          
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
          break;

        case AttendanceStatus.unknown:
          actions.add(AttendanceAction(
            type: 'check_in',
            label: 'Check In',
            isEnabled: true,
          ));
          break;
      }

      return actions;
    } catch (e) {
      return [];
    }
  }

  bool _canCheckIn(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (scheduleDetails?.startTime == null) return true;
    
    final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
    return !_isTimeBeforeScheduled(currentTime, scheduledStart, 30);
  }

  String? _getCheckInReason(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (!_canCheckIn(currentTime, scheduleDetails)) {
      return 'Too early to check in. Scheduled start: ${scheduleDetails?.startTime}';
    }
    return null;
  }

  bool _canTakeBreak(TimeOfDay currentTime, WorkScheduleDetails? scheduleDetails) {
    if (scheduleDetails?.breakStart == null || scheduleDetails?.breakEnd == null) {
      return true;
    }
    
    final breakStart = TimeHelper.parseTimeString(scheduleDetails!.breakStart!);
    final breakEnd = TimeHelper.parseTimeString(scheduleDetails.breakEnd!);
    return _isWithinBreakWindow(currentTime, breakStart, breakEnd);
  }

  bool _canCheckOut(WorkScheduleDetails? scheduleDetails) {
    return true;
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  User? get currentUser => _supabase.auth.currentUser;

  bool get isAuthenticated => _supabase.auth.currentUser != null;

  SupabaseClient get supabase => _supabase;

  Future<void> updateBreakDuration(int organizationMemberId, int additionalMinutes) async {
    try {
      await _validateUserAccess(organizationMemberId.toString());
      
      final today = TimezoneHelper.getTodayDateString();
      final response = await _supabase
          .from('attendance_records')
          .select('id, break_duration_minutes')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .single();

      if (response != null) {
        final currentDuration = response['break_duration_minutes'] as int? ?? 0;
        await _supabase
            .from('attendance_records')
            .update({'break_duration_minutes': currentDuration + additionalMinutes})
            .eq('id', response['id']);
        debugPrint('Break duration updated: ${currentDuration + additionalMinutes} minutes');
      } else {
        throw Exception('No attendance record found for today');
      }
    } catch (e) {
      debugPrint('Error updating break duration: $e');
      throw Exception('Failed to update break duration: $e');
    }
  }

  Future<List<AttendanceRecord>> loadAttendanceRecordsInRange(
    String organizationMemberId, 
    DateTime startDate, 
    DateTime endDate
  ) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final response = await _supabase
          .from('attendance_records')
          .select('''
            *,
            shifts(id, name, start_time, end_time)
          ''')
          .eq('organization_member_id', organizationMemberId)
          .gte('attendance_date', startDate.toIso8601String().split('T')[0])
          .lte('attendance_date', endDate.toIso8601String().split('T')[0])
          .order('attendance_date', ascending: false);

      final records = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceRecord.fromJson(json))
          .toList();

      return records;
    } catch (e) {
      throw Exception('Error loading attendance records in range: $e');
    }
  }

  Future<Map<String, dynamic>> getAttendanceSummary(
    String organizationMemberId,
    DateTime startDate,
    DateTime endDate
  ) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final records = await loadAttendanceRecordsInRange(organizationMemberId, startDate, endDate);
      
      int presentDays = 0;
      int absentDays = 0;
      int lateDays = 0;
      int totalLateMinutes = 0;
      int totalOvertimeMinutes = 0;
      int totalWorkMinutes = 0;

      for (final record in records) {
        if (record.status == 'present') {
          presentDays++;
          
          if (record.lateMinutes != null && record.lateMinutes! > 0) {
            lateDays++;
            totalLateMinutes += record.lateMinutes!;
          }
          
          if (record.overtimeMinutes != null) {
            totalOvertimeMinutes += record.overtimeMinutes!;
          }
          
          if (record.workDurationMinutes != null) {
            totalWorkMinutes += record.workDurationMinutes!;
          }
        } else if (record.status == 'absent') {
          absentDays++;
        }
      }

      return {
        'present_days': presentDays,
        'absent_days': absentDays,
        'late_days': lateDays,
        'total_late_minutes': totalLateMinutes,
        'total_overtime_minutes': totalOvertimeMinutes,
        'total_work_minutes': totalWorkMinutes,
        'average_work_hours': totalWorkMinutes > 0 ? (totalWorkMinutes / 60) / presentDays : 0,
        'attendance_rate': records.isNotEmpty ? (presentDays / records.length * 100) : 0,
      };
    } catch (e) {
      throw Exception('Error calculating attendance summary: $e');
    }
  }

  Future<bool> hasAttendanceRecordToday(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final today = TimezoneHelper.getTodayDateString();
      final response = await _supabase
          .from('attendance_records')
          .select('id')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .limit(1)
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('Error checking today attendance record: $e');
      return false;
    }
  }

  Future<AttendanceRecord?> getTodayAttendanceRecord(String organizationMemberId) async {
    try {
      final records = await loadTodayAttendanceRecords(organizationMemberId);
      return records.isNotEmpty ? records.first : null;
    } catch (e) {
      debugPrint('Error getting today attendance record: $e');
      return null;
    }
  }

  Future<List<AttendanceLog>> getAttendanceLogsInRange(
    String organizationMemberId,
    DateTime startDate,
    DateTime endDate
  ) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final startDateStr = '${startDate.toIso8601String().split('T')[0]} 00:00:00';
      final endDateStr = '${endDate.toIso8601String().split('T')[0]} 23:59:59';
      
      final response = await _supabase
          .from('attendance_logs')
          .select('*')
          .eq('organization_member_id', organizationMemberId)
          .gte('event_time', startDateStr)
          .lte('event_time', endDateStr)
          .order('event_time', ascending: false);

      final logs = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceLog.fromJson(json))
          .toList();

      return logs;
    } catch (e) {
      throw Exception('Error loading attendance logs in range: $e');
    }
  }

  Future<bool> validateAttendancePermissions(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final member = await loadOrganizationMember();
      if (member == null || !member.isActive) {
        throw Exception('Member account is not active');
      }

      final schedule = await loadCurrentSchedule(organizationMemberId);
      if (schedule == null) {
        throw Exception('No active schedule found');
      }

      final isWorkingDay = await isTodayWorkingDay(organizationMemberId);
      if (!isWorkingDay) {
        throw Exception('Today is not a working day');
      }

      return true;
    } catch (e) {
      throw Exception('Attendance validation failed: $e');
    }
  }

  Future<Map<String, dynamic>?> getAttendanceSettings(String organizationId) async {
    try {
      final response = await _supabase
          .from('attendance_settings')
          .select('*')
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error loading attendance settings: $e');
      return null;
    }
  }

  Future<bool> isLocationRequired(String organizationId) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      return settings?['require_location'] ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<bool> isPhotoRequired(String organizationId, String attendanceType) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      if (settings == null) return true;

      final photoSettings = settings['photo_requirements'] as Map<String, dynamic>?;
      return photoSettings?[attendanceType] ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<int> getLocationToleranceMeters(String organizationId) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      return settings?['location_tolerance_meters'] ?? 100;
    } catch (e) {
      return 100;
    }
  }

  Future<bool> canPerformAttendanceAction(String organizationMemberId, String actionType) async {
    try {
      final status = await getCurrentAttendanceStatus(organizationMemberId);
      final actions = await getAvailableActions(organizationMemberId);
      
      final action = actions.firstWhere(
        (a) => a.type == actionType,
        orElse: () => AttendanceAction(type: actionType, label: '', isEnabled: false),
      );

      return action.isEnabled;
    } catch (e) {
      return false;
    }
  }

  Future<void> cleanupOldAttendancePhotos(int daysToKeep) async {
    try {
      final user = _supabase.auth.currentUser;
      
      if (user == null) return;

      debugPrint('Cleanup request for attendance photos older than $daysToKeep days');
      
    } catch (e) {
      debugPrint('Error during photo cleanup: $e');
    }
  }

  Future<List<String>> validateAttendanceDataIntegrity(String organizationMemberId) async {
    List<String> issues = [];

    try {
      await _validateUserAccess(organizationMemberId);
      
      final records = await loadRecentAttendanceRecords(organizationMemberId);
      
      for (final record in records) {
        if (record.hasCheckedIn && !record.hasCheckedOut) {
          final recordDate = DateTime.parse(record.attendanceDate);
          final daysDiff = DateTime.now().difference(recordDate).inDays;
          
          if (daysDiff > 0) {
            issues.add('Missing check-out for ${record.attendanceDate}');
          }
        }

        if (record.workDurationMinutes != null && record.workDurationMinutes! > 16 * 60) {
          issues.add('Unusually long work duration on ${record.attendanceDate}: ${(record.workDurationMinutes! / 60).toStringAsFixed(1)} hours');
        }

        if (record.checkInLocation == null && record.hasCheckedIn) {
          issues.add('Missing location data for check-in on ${record.attendanceDate}');
        }
      }

      return issues;
    } catch (e) {
      return ['Error validating attendance data: $e'];
    }
  }
}

enum AttendanceStatus {
  notCheckedIn,
  working,
  onBreak,
  checkedOut,
  unknown,
}

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

  @override
  String toString() {
    return 'AttendanceAction(type: $type, label: $label, isEnabled: $isEnabled, reason: $reason)';
  }
}