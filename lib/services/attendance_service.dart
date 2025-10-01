import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart' hide Position;
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // User-friendly error messages
  static const String _networkError = 'Please check your internet connection and try again.';
  static const String _authError = 'Please log in again to continue.';
  static const String _permissionError = 'You don\'t have permission to perform this action.';
  static const String _genericError = 'Something went wrong. Please try again in a moment.';

  Future<UserProfile?> loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw _AuthException('Please log in to access your profile.');
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
    } on _AuthException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading profile: ${e.message}');
      throw _DatabaseException('Unable to load your profile. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading profile: $e');
      throw _GeneralException('Failed to load your profile. Please restart the app.');
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
    } on PostgrestException catch (e) {
      debugPrint('Database error creating profile: ${e.message}');
      throw _DatabaseException('Unable to set up your profile. Please contact support.');
    } catch (e) {
      debugPrint('Unexpected error creating profile: $e');
      throw _GeneralException('Profile setup failed. Please contact support.');
    }
  }

  Future<OrganizationMember?> loadOrganizationMember() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw _AuthException('Please log in to view your organization details.');
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
    } on _AuthException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading organization: ${e.message}');
      throw _DatabaseException('Unable to load your organization details. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading organization: $e');
      throw _GeneralException('Failed to load organization information. Please restart the app.');
    }
  }

  Future<AttendanceDevice?> loadAttendanceDevice(String organizationId) async {
    try {
      final deviceResponse = await _supabase
          .from('attendance_devices')
          .select('*')
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
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading device: ${e.message}');
      throw _DatabaseException('Unable to load attendance settings. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading device: $e');
      throw _GeneralException('Failed to load attendance settings. Please restart the app.');
    }
  }

  Future<void> _validateUserAccess(String organizationMemberId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw _AuthException('Your session has expired. Please log in again.');
    }

    try {
      final memberVerification = await _supabase
          .from('organization_members')
          .select('id, user_id')
          .eq('id', organizationMemberId)
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (memberVerification == null) {
        throw _PermissionException('You don\'t have access to this information.');
      }
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error validating access: ${e.message}');
      throw _DatabaseException('Unable to verify your access. Please try again.');
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
    } on _AuthException catch (e) {
      throw e;
    } on _PermissionException catch (e) {
      throw e;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading today records: ${e.message}');
      throw _DatabaseException('Unable to load today\'s attendance. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading today records: $e');
      throw _GeneralException('Failed to load attendance records. Please try again.');
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
    } on _AuthException catch (e) {
      throw e;
    } on _PermissionException catch (e) {
      throw e;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading recent records: ${e.message}');
      throw _DatabaseException('Unable to load your attendance history. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading recent records: $e');
      throw _GeneralException('Failed to load attendance history. Please try again.');
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
    } on _AuthException catch (e) {
      throw e;
    } on _PermissionException catch (e) {
      throw e;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading today logs: ${e.message}');
      throw _DatabaseException('Unable to load today\'s activity. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading today logs: $e');
      throw _GeneralException('Failed to load activity logs. Please try again.');
    }
  }

  Future<MemberSchedule?> loadCurrentSchedule(String organizationMemberId) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      final user = _supabase.auth.currentUser;
      
      if (user == null) {
        throw _AuthException('Your session has expired. Please log in again.');
      }

      debugPrint('Loading schedule for member: $organizationMemberId, user: ${user.id}');

      final memberVerification = await _supabase
          .from('organization_members')
          .select('id, user_id, organization_id')
          .eq('id', organizationMemberId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (memberVerification == null) {
        throw _PermissionException('You don\'t have access to this schedule.');
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
    } on _AuthException catch (e) {
      throw e;
    } on _PermissionException catch (e) {
      throw e;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading schedule: ${e.message}');
      throw _DatabaseException('Unable to load your work schedule. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading schedule: $e');
      throw _GeneralException('Failed to load work schedule. Please try again.');
    }
  }

  Future<MemberSchedule?> _getDefaultScheduleForMember(String organizationMemberId, String organizationId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw _AuthException('Your session has expired. Please log in again.');
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
        throw _AuthException('Your session has expired. Please log in again.');
      }

      debugPrint('Loading work schedule details for schedule: $workScheduleId, day: $dayOfWeek');

      final hasAccess = await _supabase
          .from('work_schedules')
          .select('id, organization_id')
          .eq('id', workScheduleId)
          .single();

      if (hasAccess == null) {
        throw _DataException('Work schedule not found.');
      }

      final memberCheck = await _supabase
          .from('organization_members')
          .select('id')
          .eq('user_id', user.id)
          .eq('organization_id', hasAccess['organization_id'])
          .eq('is_active', true)
          .maybeSingle();

      if (memberCheck == null) {
        throw _PermissionException('You don\'t have access to this work schedule.');
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
    } on _AuthException catch (e) {
      throw e;
    } on _PermissionException catch (e) {
      throw e;
    } on _DataException catch (e) {
      throw e;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading schedule details: ${e.message}');
      throw _DatabaseException('Unable to load schedule details. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error loading schedule details: $e');
      throw _GeneralException('Failed to load schedule details. Please try again.');
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
      debugPrint('Error checking working day: $e');
      return true; // Default to working day if we can't determine
    }
  }

  Future<Position> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw _LocationException('Location services are disabled. Please enable them in your device settings.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw _LocationException('Location permission is required for attendance. Please allow location access.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw _LocationException('Location access is permanently denied. Please enable it in Settings > App Permissions.');
      }

      // Try high accuracy first with longer timeout
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 30),
        );
        debugPrint('Got location with accuracy: ${position.accuracy}m');
        return position;
      } catch (e) {
        debugPrint('High accuracy failed: $e, trying medium accuracy...');
        
        // Fallback to medium accuracy if high accuracy fails
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        );
        debugPrint('Got location with medium accuracy: ${position.accuracy}m');
        return position;
      }
    } on _LocationException {
      rethrow;
    } catch (e) {
      debugPrint('Location error: $e');
      if (e.toString().contains('timeout')) {
        throw _LocationException('Unable to get your location. Please wait a moment and try again in an open area.');
      }
      throw _LocationException('Failed to get your location. Please check your GPS settings.');
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
        throw _AuthException('Your session has expired. Please log in again.');
      }

      final orgTime = TimezoneHelper.nowInOrgTime();
      final timestamp = orgTime.millisecondsSinceEpoch;
      final fileName = '${user.id}/$timestamp.jpg';
      final file = File(imagePath);

      if (!file.existsSync()) {
        throw _DataException('Photo file not found. Please take the photo again.');
      }

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
    } on _AuthException {
      rethrow;
    } on _DataException {
      rethrow;
    } on SocketException {
      throw _NetworkException('Unable to upload photo. Please check your internet connection.');
    } on StorageException catch (e) {
      debugPrint('Storage error uploading photo: ${e.message}');
      throw _DataException('Photo upload failed. Please try taking the photo again.');
    } catch (e) {
      debugPrint('Unexpected error uploading photo: $e');
      throw _GeneralException('Failed to upload photo. Please try again.');
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
          throw _ValidationException('Unknown attendance action. Please try again.');
      }
    } on _ValidationException {
      rethrow;
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error performing attendance: ${e.message}');
      throw _DatabaseException('Unable to record attendance. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error performing attendance: $e');
      throw _GeneralException('Failed to record attendance. Please try again.');
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
    // Calculate break duration from logs
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
    
    final lastBreakOut = todayLogs
        .where((log) => log.eventType == 'break_out')
        .lastOrNull;

    if (lastBreakOut != null) {
      final breakDuration = now.difference(lastBreakOut.eventTime).inMinutes;
      
      // Update attendance record with accumulated break time
      await updateBreakDuration(int.parse(organizationMemberId), breakDuration);
      
      debugPrint('Break duration calculated and updated: $breakDuration minutes');
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
      throw _ValidationException('Today is not a working day according to your schedule.');
    }

    final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

    switch (type) {
      case 'check_in':
        if (existingRecord?.hasCheckedIn == true) {
          throw _ValidationException('You have already checked in today.');
        }
        if (scheduleDetails?.startTime != null) {
          final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
          final maxEarlyMinutes = 30;
          if (_isTimeBeforeScheduled(now, scheduledStart, maxEarlyMinutes)) {
            throw _ValidationException('Check-in is too early. You can check in 30 minutes before ${scheduleDetails.startTime}.');
          }
        }
        break;
        
      case 'check_out':
        if (existingRecord?.hasCheckedIn != true) {
          throw _ValidationException('You must check in before you can check out.');
        }
        if (existingRecord?.hasCheckedOut == true) {
          throw _ValidationException('You have already checked out for today.');
        }
        if (existingRecord?.actualCheckIn != null && scheduleDetails?.minimumHours != null) {
          final workHours = DateTime.now().difference(existingRecord!.actualCheckIn!).inHours;
          if (workHours < scheduleDetails!.minimumHours!) {
            throw _ValidationException('You need to complete at least ${scheduleDetails.minimumHours} hours before checking out.');
          }
        }
        break;
        
      case 'break_out':
        if (existingRecord?.hasCheckedIn != true) {
          throw _ValidationException('You must check in before taking a break.');
        }
        if (lastLog?.eventType == 'break_out') {
          throw _ValidationException('You are already on break. Please resume work first.');
        }
        if (scheduleDetails?.breakStart != null && scheduleDetails?.breakEnd != null) {
          final breakStart = TimeHelper.parseTimeString(scheduleDetails!.breakStart!);
          final breakEnd = TimeHelper.parseTimeString(scheduleDetails.breakEnd!);
          if (!_isWithinBreakWindow(now, breakStart, breakEnd)) {
            throw _ValidationException('Break time is ${scheduleDetails.breakStart} - ${scheduleDetails.breakEnd}. Please wait for the break period.');
          }
        }
        break;
        
      case 'break_in':
        if (existingRecord?.hasCheckedIn != true) {
          throw _ValidationException('You must check in first before resuming work.');
        }
        if (lastLog?.eventType != 'break_out') {
          throw _ValidationException('You are not currently on break.');
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
      debugPrint('Error getting attendance status: $e');
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
              reason: 'Please complete your minimum work hours before checking out.',
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
      debugPrint('Error getting available actions: $e');
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
      return 'You can check in 30 minutes before ${scheduleDetails?.startTime}.';
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
    return true; // Can be extended with business logic
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } on SocketException {
      throw _NetworkException('Unable to sign out. Please check your connection and try again.');
    } on AuthException catch (e) {
      debugPrint('Auth error signing out: ${e.message}');
      throw _AuthException('Sign out failed. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error signing out: $e');
      throw _GeneralException('Unable to sign out. Please restart the app.');
    }
  }

  User? get currentUser => _supabase.auth.currentUser;

  bool get isAuthenticated => _supabase.auth.currentUser != null;

  SupabaseClient get supabase => _supabase;

  // Enhanced break duration update method
  Future<void> updateBreakDuration(int organizationMemberId, int additionalMinutes) async {
    try {
      await _validateUserAccess(organizationMemberId.toString());
      
      final today = TimezoneHelper.getTodayDateString();
      
      // Get current attendance record
      final response = await _supabase
          .from('attendance_records')
          .select('id, break_duration_minutes')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .maybeSingle();

      if (response != null) {
        final currentDuration = response['break_duration_minutes'] as int? ?? 0;
        final newTotalDuration = currentDuration + additionalMinutes;
        
        await _supabase
            .from('attendance_records')
            .update({
              'break_duration_minutes': newTotalDuration,
              'updated_at': TimezoneHelper.nowInOrgTime().toIso8601String(),
            })
            .eq('id', response['id']);
        
        debugPrint('Break duration updated: $currentDuration + $additionalMinutes = $newTotalDuration minutes');
      } else {
        // Create attendance record if it doesn't exist (edge case)
        debugPrint('Warning: No attendance record found for break duration update');
        throw _DataException('No attendance record found for today. Please check in first.');
      }
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on _DataException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error updating break duration: ${e.message}');
      throw _DatabaseException('Unable to update break time. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error updating break duration: $e');
      throw _GeneralException('Failed to update break duration. Please try again.');
    }
  }

  // Get detailed break information for today
  Future<Map<String, dynamic>> getTodayBreakInfo(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final today = TimezoneHelper.getTodayDateString();
      
      // Get attendance record break duration
      final recordResponse = await _supabase
          .from('attendance_records')
          .select('break_duration_minutes')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .maybeSingle();

      final totalBreakMinutes = recordResponse?['break_duration_minutes'] as int? ?? 0;

      // Get break logs to calculate sessions
      final logsResponse = await _supabase
          .from('attendance_logs')
          .select('event_type, event_time')
          .eq('organization_member_id', organizationMemberId)
          .gte('event_time', '${today}T00:00:00')
          .lte('event_time', '${today}T23:59:59')
          .inFilter('event_type', ['break_out', 'break_in'])
          .order('event_time', ascending: true);

      final logs = List<Map<String, dynamic>>.from(logsResponse);
      List<Map<String, dynamic>> breakSessions = [];
      DateTime? currentBreakStart;
      bool isCurrentlyOnBreak = false;

      for (var log in logs) {
        if (log['event_type'] == 'break_out') {
          currentBreakStart = DateTime.parse(log['event_time']);
          isCurrentlyOnBreak = true;
        } else if (log['event_type'] == 'break_in' && currentBreakStart != null) {
          final breakEnd = DateTime.parse(log['event_time']);
          final duration = breakEnd.difference(currentBreakStart).inMinutes;
          
          breakSessions.add({
            'start': currentBreakStart,
            'end': breakEnd,
            'duration': duration,
          });
          
          currentBreakStart = null;
          isCurrentlyOnBreak = false;
        }
      }

      // Add current ongoing break if exists
      if (isCurrentlyOnBreak && currentBreakStart != null) {
        breakSessions.add({
          'start': currentBreakStart,
          'end': null, // Ongoing
          'duration': TimezoneHelper.nowInOrgTime().difference(currentBreakStart).inMinutes,
        });
      }

      return {
        'total_break_minutes': totalBreakMinutes,
        'break_sessions': breakSessions,
        'is_currently_on_break': isCurrentlyOnBreak,
        'current_break_start': currentBreakStart?.toIso8601String(),
      };
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error getting break info: ${e.message}');
      throw _DatabaseException('Unable to load break information. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error getting break info: $e');
      throw _GeneralException('Failed to load break information. Please try again.');
    }
  }

  // Additional methods for comprehensive attendance management...

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
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading attendance range: ${e.message}');
      throw _DatabaseException('Unable to load attendance history for the selected dates.');
    } catch (e) {
      debugPrint('Unexpected error loading attendance range: $e');
      throw _GeneralException('Failed to load attendance records. Please try again.');
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
      int totalBreakMinutes = 0;

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

          if (record.breakDurationMinutes != null) {
            totalBreakMinutes += record.breakDurationMinutes!;
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
        'total_break_minutes': totalBreakMinutes,
        'average_work_hours': totalWorkMinutes > 0 ? (totalWorkMinutes / 60) / presentDays : 0,
        'average_break_minutes': totalBreakMinutes > 0 ? totalBreakMinutes / presentDays : 0,
        'attendance_rate': records.isNotEmpty ? (presentDays / records.length * 100) : 0,
      };
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error calculating summary: ${e.message}');
      throw _DatabaseException('Unable to calculate attendance summary. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error calculating summary: $e');
      throw _GeneralException('Failed to calculate attendance summary. Please try again.');
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
    } on _AuthException {
      rethrow;
    } on _PermissionException {
      rethrow;
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading logs range: ${e.message}');
      throw _DatabaseException('Unable to load activity logs for the selected dates.');
    } catch (e) {
      debugPrint('Unexpected error loading logs range: $e');
      throw _GeneralException('Failed to load activity logs. Please try again.');
    }
  }

  Future<bool> validateAttendancePermissions(String organizationMemberId) async {
    try {
      await _validateUserAccess(organizationMemberId);
      
      final member = await loadOrganizationMember();
      if (member == null || !member.isActive) {
        throw _PermissionException('Your account is inactive. Please contact your administrator.');
      }

      final schedule = await loadCurrentSchedule(organizationMemberId);
      if (schedule == null) {
        throw _DataException('No work schedule assigned. Please contact your administrator.');
      }

      final isWorkingDay = await isTodayWorkingDay(organizationMemberId);
      if (!isWorkingDay) {
        throw _ValidationException('Today is not a working day according to your schedule.');
      }

      return true;
    } catch (e) {
      rethrow;
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
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error loading settings: ${e.message}');
      throw _DatabaseException('Unable to load attendance settings.');
    } catch (e) {
      debugPrint('Unexpected error loading settings: $e');
      return null;
    }
  }

  Future<bool> isLocationRequired(String organizationId) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      return settings?['require_location'] ?? true;
    } catch (e) {
      return true; // Default to requiring location
    }
  }

  Future<bool> isPhotoRequired(String organizationId, String attendanceType) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      if (settings == null) return true;

      final photoSettings = settings['photo_requirements'] as Map<String, dynamic>?;
      return photoSettings?[attendanceType] ?? true;
    } catch (e) {
      return true; // Default to requiring photo
    }
  }

  Future<int> getLocationToleranceMeters(String organizationId) async {
    try {
      final settings = await getAttendanceSettings(organizationId);
      return settings?['location_tolerance_meters'] ?? 100;
    } catch (e) {
      return 100; // Default tolerance
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
      debugPrint('Error checking attendance action: $e');
      return false;
    }
  }

  Future<void> cleanupOldAttendancePhotos(int daysToKeep) async {
    try {
      final user = _supabase.auth.currentUser;
      
      if (user == null) {
        throw _AuthException('Please log in to perform cleanup.');
      }

      debugPrint('Cleanup request for attendance photos older than $daysToKeep days');
      // Implementation would go here for actual cleanup
      
    } on _AuthException {
      rethrow;
    } catch (e) {
      debugPrint('Error during photo cleanup: $e');
      throw _GeneralException('Photo cleanup failed. Please try again later.');
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
            issues.add('Missing check-out for ${_formatDate(recordDate)}');
          }
        }

        if (record.workDurationMinutes != null && record.workDurationMinutes! > 16 * 60) {
          issues.add('Unusually long work session on ${_formatDate(DateTime.parse(record.attendanceDate))}: ${_formatHours(record.workDurationMinutes! / 60)}');
        }

        if (record.checkInLocation == null && record.hasCheckedIn) {
          issues.add('Missing location data for ${_formatDate(DateTime.parse(record.attendanceDate))}');
        }

        // Break duration validation
        if (record.breakDurationMinutes != null && record.breakDurationMinutes! > 4 * 60) {
          issues.add('Excessive break time on ${_formatDate(DateTime.parse(record.attendanceDate))}: ${_formatHours(record.breakDurationMinutes! / 60)}');
        }
      }

      return issues;
    } on _AuthException {
      return ['Please log in to check your attendance data.'];
    } on _PermissionException {
      return ['You don\'t have permission to view this data.'];
    } on _NetworkException {
      return ['Unable to check attendance data. Please check your connection.'];
    } catch (e) {
      debugPrint('Error validating data integrity: $e');
      return ['Unable to validate attendance data. Please try again later.'];
    }
  }

  // Helper methods for formatting
  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatHours(double hours) {
    if (hours < 1) {
      return '${(hours * 60).round()} minutes';
    }
    return '${hours.toStringAsFixed(1)} hours';
  }
}

// Custom Exception Classes for better error handling
class _AuthException implements Exception {
  final String message;
  _AuthException(this.message);
  
  @override
  String toString() => message;
}

class _NetworkException implements Exception {
  final String message;
  _NetworkException(this.message);
  
  @override
  String toString() => message;
}

class _DatabaseException implements Exception {
  final String message;
  _DatabaseException(this.message);
  
  @override
  String toString() => message;
}

class _PermissionException implements Exception {
  final String message;
  _PermissionException(this.message);
  
  @override
  String toString() => message;
}

class _ValidationException implements Exception {
  final String message;
  _ValidationException(this.message);
  
  @override
  String toString() => message;
}

class _LocationException implements Exception {
  final String message;
  _LocationException(this.message);
  
  @override
  String toString() => message;
}

class _DataException implements Exception {
  final String message;
  _DataException(this.message);
  
  @override
  String toString() => message;
}

class _GeneralException implements Exception {
  final String message;
  _GeneralException(this.message);
  
  @override
  String toString() => message;
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