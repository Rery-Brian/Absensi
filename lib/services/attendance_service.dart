import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart' hide Position;
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';
import '../helpers/cache_helper.dart';

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CacheHelper _cache = CacheHelper();
  
  // Cache TTL durations
  static const Duration _profileCacheTTL = Duration(minutes: 15);
  static const Duration _orgMemberCacheTTL = Duration(minutes: 10);
  static const Duration _scheduleCacheTTL = Duration(minutes: 5);
  static const Duration _todayDataCacheTTL = Duration(minutes: 2);
  static const Duration _deviceCacheTTL = Duration(minutes: 10);
  static const Duration _statusCacheTTL = Duration(seconds: 30);

  // User-friendly error messages
  static const String _networkError = 'Please check your internet connection and try again.';
  static const String _authError = 'Please log in again to continue.';
  static const String _permissionError = 'You don\'t have permission to perform this action.';
  static const String _genericError = 'Something went wrong. Please try again in a moment.';

  Future<UserProfile?> loadUserProfile({bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw _AuthException('Please log in to access your profile.');
    }

    final cacheKey = CacheKeys.userProfileKey(user.id);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<UserProfile>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: User profile loaded from cache');
        return cached;
      }
    }

    return _executeWithRetry(
      operation: () async {
        try {
          final profileResponse = await _supabase
              .from('user_profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();

          UserProfile? profile;
          if (profileResponse == null) {
            await _createUserProfile(user);
            
            final newProfileResponse = await _supabase
                .from('user_profiles')
                .select()
                .eq('id', user.id)
                .maybeSingle();
                
            profile = newProfileResponse != null ? UserProfile.fromJson(newProfileResponse) : null;
          } else {
            profile = UserProfile.fromJson(profileResponse);
          }
          
          // Cache the result
          if (profile != null) {
            _cache.set(cacheKey, profile, ttl: _profileCacheTTL);
          }
          
          return profile;
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
      },
      maxRetries: 2,
      timeout: const Duration(seconds: 8),
    );
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
      debugPrint('Unexpected ernror creating profile: $e');
      throw _GeneralException('Profile setup failed. Please contact support.');
    }
  }

  Future<OrganizationMember?> loadOrganizationMember({bool forceRefresh = false}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw _AuthException('Please log in to view your organization details.');
    }

    final cacheKey = CacheKeys.orgMemberKey(user.id);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<OrganizationMember>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Organization member loaded from cache');
        // Initialize timezone from cached org
        if (cached.organization?.timezone != null) {
          TimezoneHelper.initialize(cached.organization!.timezone);
        }
        return cached;
      }
    }

    try {
      // ✅ OPTIMIZATION: Load member and organization in parallel
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

      // ✅ OPTIMIZATION: Load all related data in parallel
      final results = await Future.wait([
        _supabase
            .from('organizations')
            .select('id, name, code, timezone, logo_url') // ✅ FIX: Tambahkan logo_url
            .eq('id', memberResponse['organization_id'])
            .single()
            .catchError((e) => null),
        memberResponse['department_id'] != null
            ? _supabase
                .from('departments')
                .select('id, name, code')
                .eq('id', memberResponse['department_id'])
                .maybeSingle()
                .catchError((e) => null)
            : Future.value(null),
        memberResponse['position_id'] != null
            ? _supabase
                .from('positions')
                .select('id, title, code')
                .eq('id', memberResponse['position_id'])
                .maybeSingle()
                .catchError((e) => null)
            : Future.value(null),
      ]);

      final orgDetails = results[0] as Map<String, dynamic>?;
      final deptDetails = results[1] as Map<String, dynamic>?;
      final posDetails = results[2] as Map<String, dynamic>?;

      if (orgDetails?['timezone'] != null) {
        TimezoneHelper.initialize(orgDetails!['timezone']);
        debugPrint('Organization timezone loaded: ${orgDetails['timezone']}');
      }

      final combinedResponse = {
        ...memberResponse,
        'organizations': orgDetails,
        'departments': deptDetails,
        'positions': posDetails,
      };

      final member = OrganizationMember.fromJson(combinedResponse);
      
      // Cache the result
      _cache.set(cacheKey, member, ttl: _orgMemberCacheTTL);
      
      return member;
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

  Future<AttendanceDevice?> loadAttendanceDevice(String organizationId, {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.deviceKey(organizationId);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<AttendanceDevice>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Attendance device loaded from cache');
        return cached;
      }
    }

    try {
      final deviceResponse = await _supabase
          .from('attendance_devices')
          .select('*')
          .eq('organization_id', organizationId)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();

      AttendanceDevice? device;
      if (deviceResponse != null) {
        device = AttendanceDevice.fromJson(deviceResponse);
        // Cache the result
        _cache.set(cacheKey, device, ttl: _deviceCacheTTL);
      }
      
      return device;
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

    // ✅ OPTIMIZATION: Use cached org member untuk validasi jika available
    final orgMemberCacheKey = CacheKeys.orgMemberKey(user.id);
    final cachedOrgMember = _cache.get<OrganizationMember>(orgMemberCacheKey);
    
    if (cachedOrgMember != null && cachedOrgMember.id == organizationMemberId && cachedOrgMember.isActive) {
      // Validasi dari cache - skip database query
      return;
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

  Future<List<AttendanceRecord>> loadTodayAttendanceRecords(String organizationMemberId, {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.todayRecordsKey(organizationMemberId);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<List<AttendanceRecord>>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Today records loaded from cache');
        return cached;
      }
    }

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

      // Cache the result
      _cache.set(cacheKey, records, ttl: _todayDataCacheTTL);

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

  Future<List<AttendanceLog>> getTodayAttendanceLogs(String organizationMemberId, {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.todayLogsKey(organizationMemberId);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<List<AttendanceLog>>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Today logs loaded from cache');
        return cached;
      }
    }

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

      // Cache the result
      _cache.set(cacheKey, logs, ttl: _todayDataCacheTTL);

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

  Future<MemberSchedule?> loadCurrentSchedule(String organizationMemberId, {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.scheduleKey(organizationMemberId);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<MemberSchedule>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Current schedule loaded from cache');
        return cached;
      }
    }

    try {
      final today = TimezoneHelper.getTodayDateString();
      final user = _supabase.auth.currentUser;
      
      if (user == null) {
        throw _AuthException('Your session has expired. Please log in again.');
      }

      debugPrint('Loading schedule for member: $organizationMemberId, user: ${user.id}');

      // ✅ OPTIMIZATION: Use cached org member if available instead of querying
      final orgMemberCacheKey = CacheKeys.orgMemberKey(user.id);
      String? orgId;
      final cachedOrgMember = _cache.get<OrganizationMember>(orgMemberCacheKey);
      if (cachedOrgMember != null && cachedOrgMember.id == organizationMemberId) {
        orgId = cachedOrgMember.organizationId;
      } else {
        final memberVerification = await _supabase
            .from('organization_members')
            .select('id, user_id, organization_id')
            .eq('id', organizationMemberId)
            .eq('user_id', user.id)
            .maybeSingle();

        if (memberVerification == null) {
          throw _PermissionException('You don\'t have access to this schedule.');
        }
        orgId = memberVerification['organization_id'].toString();
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

      MemberSchedule? schedule;
      if (scheduleResponse != null) {
        debugPrint('Found schedule: ${scheduleResponse}');
        schedule = MemberSchedule.fromJson(scheduleResponse);
      } else {
        debugPrint('No active schedule found, trying to find default schedule');
        schedule = await _getDefaultScheduleForMember(
          organizationMemberId, 
          orgId!
        );
      }
      
      // Cache the result
      if (schedule != null) {
        _cache.set(cacheKey, schedule, ttl: _scheduleCacheTTL);
      }
      
      return schedule;
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

  Future<WorkScheduleDetails?> loadWorkScheduleDetails(String workScheduleId, int dayOfWeek, {bool forceRefresh = false}) async {
    final cacheKey = CacheKeys.scheduleDetailsKey(workScheduleId, dayOfWeek);
    
    // Check cache first
    if (!forceRefresh) {
      final cached = _cache.get<WorkScheduleDetails>(cacheKey);
      if (cached != null) {
        debugPrint('CacheHelper: Work schedule details loaded from cache');
        return cached;
      }
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw _AuthException('Your session has expired. Please log in again.');
      }

      debugPrint('Loading work schedule details for schedule: $workScheduleId, day: $dayOfWeek');

      // ✅ OPTIMIZATION: Check cached org member first
      final orgMemberCacheKey = CacheKeys.orgMemberKey(user.id);
      final cachedOrgMember = _cache.get<OrganizationMember>(orgMemberCacheKey);
      String? orgId;
      
      if (cachedOrgMember != null) {
        orgId = cachedOrgMember.organizationId;
      } else {
        final hasAccess = await _supabase
            .from('work_schedules')
            .select('id, organization_id')
            .eq('id', workScheduleId)
            .single();

        if (hasAccess == null) {
          throw _DataException('Work schedule not found.');
        }
        orgId = hasAccess['organization_id'].toString();

        final memberCheck = await _supabase
            .from('organization_members')
            .select('id')
            .eq('user_id', user.id)
            .eq('organization_id', orgId)
            .eq('is_active', true)
            .maybeSingle();

        if (memberCheck == null) {
          throw _PermissionException('You don\'t have access to this work schedule.');
        }
      }

      final response = await _supabase
          .from('work_schedule_details')
          .select('*')
          .eq('work_schedule_id', workScheduleId)
          .eq('day_of_week', dayOfWeek)
          .maybeSingle();

      WorkScheduleDetails? details;
      if (response != null) {
        debugPrint('Found work schedule details: $response');
        details = WorkScheduleDetails.fromJson(response);
        // Cache the result
        _cache.set(cacheKey, details, ttl: _scheduleCacheTTL);
      } else {
        debugPrint('No work schedule details found for day $dayOfWeek');
      }
      
      return details;
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

  // ✅ PERBAIKAN: Prioritaskan max_distance dari configuration
  final maxDistance = device.configuration?['max_distance'] as int? 
      ?? device.radiusMeters;
  
  debugPrint('=== Radius Check ===');
  debugPrint('Distance: ${distance.toStringAsFixed(2)}m');
  debugPrint('Max Distance (config): ${device.configuration?['max_distance']}');
  debugPrint('Radius (column): ${device.radiusMeters}m');
  debugPrint('Using: ${maxDistance}m');
  debugPrint('Within Radius: ${distance <= maxDistance}');

  return distance <= maxDistance;
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

      bool success = false;
      switch (type) {
        case 'check_in':
          success = await _performCheckIn(
            organizationMemberId, today, now, currentPosition, photoUrl, 
            device, schedule, existingRecord, scheduleDetails
          );
          break;
          
        case 'check_out':
          success = await _performCheckOut(
            organizationMemberId, now, currentPosition, photoUrl, 
            device, existingRecord!, scheduleDetails
          );
          break;
          
        case 'break_out':
          success = await _performBreakOut(
            organizationMemberId, now, currentPosition, photoUrl, device
          );
          break;
          
        case 'break_in':
          success = await _performBreakIn(
            organizationMemberId, now, currentPosition, photoUrl, device
          );
          break;
          
        default:
          throw _ValidationException('Unknown attendance action. Please try again.');
      }
      
      // ✅ OPTIMIZATION: Invalidate cache setelah attendance berhasil
      if (success) {
        _invalidateAttendanceCache(organizationMemberId);
      }
      
      return success;
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
  
  /// Invalidate cache untuk attendance data setelah update
  void _invalidateAttendanceCache(String organizationMemberId) {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    // Clear today's data cache
    _cache.remove(CacheKeys.todayRecordsKey(organizationMemberId));
    _cache.remove(CacheKeys.todayLogsKey(organizationMemberId));
    _cache.remove(CacheKeys.statusKey(organizationMemberId));
    _cache.remove(CacheKeys.actionsKey(organizationMemberId));
    _cache.remove(CacheKeys.breakInfoKey(organizationMemberId));
    
    debugPrint('CacheHelper: Invalidated attendance cache for member $organizationMemberId');
  }
  
  /// Update user profile dan invalidate cache
  Future<UserProfile?> updateUserProfile({
    String? displayName,
    String? phone,
    String? mobile,
    String? gender,
    DateTime? dateOfBirth,
    String? profilePhotoUrl,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw _AuthException('Please log in to update your profile.');
    }

    try {
      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (displayName != null) {
        // Parse display_name untuk first_name dan last_name
        final nameParts = displayName.trim().split(' ');
        if (nameParts.isNotEmpty) {
          updateData['first_name'] = nameParts.first;
          updateData['last_name'] = nameParts.length > 1 
              ? nameParts.sublist(1).join(' ') 
              : '';
          updateData['display_name'] = displayName.trim();
        }
      }
      
      if (phone != null) updateData['phone'] = phone.trim().isEmpty ? null : phone.trim();
      if (mobile != null) updateData['mobile'] = mobile.trim().isEmpty ? null : mobile.trim();
      if (gender != null) updateData['gender'] = gender;
      if (dateOfBirth != null) {
        updateData['date_of_birth'] = dateOfBirth.toIso8601String().split('T')[0];
      }
      if (profilePhotoUrl != null) updateData['profile_photo_url'] = profilePhotoUrl;

      await _supabase
          .from('user_profiles')
          .update(updateData)
          .eq('id', user.id);

      // ✅ OPTIMIZATION: Invalidate cache setelah update
      _cache.remove(CacheKeys.userProfileKey(user.id));
      debugPrint('CacheHelper: Invalidated user profile cache after update');

      // ✅ Load fresh data setelah update
      return await loadUserProfile(forceRefresh: true);
    } on SocketException {
      throw _NetworkException(_networkError);
    } on PostgrestException catch (e) {
      debugPrint('Database error updating profile: ${e.message}');
      throw _DatabaseException('Unable to update your profile. Please try again.');
    } catch (e) {
      debugPrint('Unexpected error updating profile: $e');
      throw _GeneralException('Failed to update profile. Please try again.');
    }
  }
  
  /// Invalidate user profile cache (public method untuk digunakan dari luar)
  void invalidateUserProfileCache() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    _cache.remove(CacheKeys.userProfileKey(user.id));
    debugPrint('CacheHelper: User profile cache invalidated');
  }
  
  /// Invalidate organization member cache
  void invalidateOrganizationMemberCache() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    _cache.remove(CacheKeys.orgMemberKey(user.id));
    debugPrint('CacheHelper: Organization member cache invalidated');
  }
  
  /// Invalidate schedule cache untuk member
  void invalidateScheduleCache(String organizationMemberId) {
    _cache.remove(CacheKeys.scheduleKey(organizationMemberId));
    debugPrint('CacheHelper: Schedule cache invalidated for member $organizationMemberId');
  }
  
  /// Invalidate attendance cache (public method untuk digunakan dari luar)
  void invalidateAttendanceCache(String organizationMemberId) {
    _invalidateAttendanceCache(organizationMemberId);
  }

Future<Map<String, dynamic>> getTodayCycleSummary(String organizationMemberId) async {
  try {
    await _validateUserAccess(organizationMemberId);
    
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
    
    List<Map<String, dynamic>> cycles = [];
    DateTime? currentCheckIn;
    int totalWorkMinutes = 0;
    
    for (var log in todayLogs) {
      if (log.eventType == 'check_in') {
        currentCheckIn = log.eventTime;
      } else if (log.eventType == 'check_out' && currentCheckIn != null) {
        final duration = log.eventTime.difference(currentCheckIn).inMinutes;
        totalWorkMinutes += duration;
        
        cycles.add({
          'check_in': currentCheckIn.toIso8601String(), // Convert to String
          'check_out': log.eventTime.toIso8601String(), // Convert to String
          'duration_minutes': duration,
        });
        
        currentCheckIn = null;
      }
    }
    
    // Tambahkan ongoing cycle jika ada
    if (currentCheckIn != null) {
      final ongoingDuration = TimezoneHelper.nowInOrgTime().difference(currentCheckIn).inMinutes;
      cycles.add({
        'check_in': currentCheckIn.toIso8601String(), // Convert to String
        'check_out': null, // Ongoing
        'duration_minutes': ongoingDuration,
      });
      totalWorkMinutes += ongoingDuration;
    }
    
    return {
      'total_cycles': cycles.length,
      'completed_cycles': cycles.where((c) => c['check_out'] != null).length,
      'ongoing_cycle': currentCheckIn != null,
      'total_work_minutes': totalWorkMinutes,
      'cycles': cycles,
    };
  } catch (e) {
    debugPrint('Error getting cycle summary: $e');
    return {
      'total_cycles': 0,
      'completed_cycles': 0,
      'ongoing_cycle': false,
      'total_work_minutes': 0,
      'cycles': [],
    };
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
  // Auto-end break if currently on break
  final breakInfo = await getTodayBreakInfo(organizationMemberId);
  if (breakInfo['is_currently_on_break'] == true) {
    debugPrint('⚠️ User is on break during check-in. Auto-ending break...');
    
    final breakStartTime = TimezoneHelper.toOrgTime(
      DateTime.parse(breakInfo['break_start_time'])
    );
    final actualBreakDuration = now.difference(breakStartTime);
    
    // Insert break_in log (tanpa photo)
    await _supabase.from('attendance_logs').insert({
      'organization_member_id': organizationMemberId,
      'event_type': 'break_in',
      'event_time': now.toIso8601String(),
      'device_id': device?.id,
      'method': 'mobile_app_auto',
      'is_verified': true,
      'verification_method': 'auto_checkin',
    });
    
    await updateBreakDuration(
      int.parse(organizationMemberId),
      actualBreakDuration.inMinutes
    );
    
    debugPrint('✓ Auto-ended break before check-in. Duration: ${actualBreakDuration.inMinutes}m');
  }
  
  // First check-in: Create attendance_records
  if (existingRecord == null) {
    Map<String, dynamic> newRecordData = {
      'organization_member_id': organizationMemberId,
      'attendance_date': today,
      'actual_check_in': now.toIso8601String(),
      'check_in_photo_url': photoUrl, // ✅ Foto check-in pertama
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
    debugPrint('✓ First check-in: Created attendance_records entry');
  } else {
    final checkInCount = await getTodayCheckInCount(organizationMemberId);
    debugPrint('✓ Subsequent check-in (#${checkInCount + 1}): Adding new log only');
  }

  // ✅ PERBAIKAN: Pass photoUrl ke _logAttendanceEvent
  await _logAttendanceEvent(
    organizationMemberId, 
    'check_in', 
    now, 
    currentPosition, 
    device,
    photoUrl: photoUrl, // ✅ Pass photo URL
  );

  final totalCheckIns = await getTodayCheckInCount(organizationMemberId) + 1;
  debugPrint('✓ Check-in logged at ${now.toIso8601String()} - Total: $totalCheckIns');
  
  return true;
}


Future<bool> requiresGpsValidation(String organizationMemberId) async {
  try {
    final member = await _supabase
        .from('organization_members')
        .select('work_location')
        .eq('id', organizationMemberId)
        .single();
    
    final workLocation = member['work_location'] as String?;
    
    // Jika work_location null/empty, default butuh GPS
    if (workLocation == null || workLocation.isEmpty) {
      debugPrint('Work location is null/empty - GPS required by default');
      return true;
    }
    
    // ✅ NORMALISASI: Hapus spasi, lowercase, untuk pengecekan
    final normalizedLocation = workLocation.toLowerCase().replaceAll(' ', '');
    
    // ✅ FIELD WORKER: Cek apakah dimulai dengan "field"
    if (normalizedLocation.startsWith('field')) {
      debugPrint('Field worker detected: $workLocation - GPS not required');
      return false;
    }
    
    // ✅ OFFICE WORKER: Cek apakah dimulai dengan "office" 
    if (normalizedLocation.startsWith('office')) {
      debugPrint('Office worker detected: $workLocation - GPS required');
      return true;
    }
    
    // Default butuh GPS untuk tipe lokasi tidak dikenal
    debugPrint('Unknown work location type: $workLocation - GPS required by default');
    return true;
    
  } catch (e) {
    debugPrint('Error checking GPS requirement: $e');
    return true; // Default ke butuh GPS saat error
  }
}

// ✅ TAMBAHKAN METHOD BARU untuk check device configuration
Future<bool> requiresLocationForDevice(AttendanceDevice? device) async {
  if (device == null) return false;
  
  // ✅ Check device configuration
  final deviceRequiresLocation = 
      device.configuration?['require_location'] as bool? ?? true;
  
  debugPrint('=== Device Location Requirement ===');
  debugPrint('Device: ${device.deviceName}');
  debugPrint('Configuration require_location: ${device.configuration?['require_location']}');
  debugPrint('Requires Location: $deviceRequiresLocation');
  
  return deviceRequiresLocation;
}

Future<String> getWorkLocationType(String organizationMemberId) async {
  try {
    final member = await _supabase
        .from('organization_members')
        .select('work_location')
        .eq('id', organizationMemberId)
        .single();
    
    final workLocation = member['work_location'] as String?;
    
    if (workLocation == null || workLocation.isEmpty) {
      return 'unknown';
    }
    
    // ✅ NORMALISASI
    final normalizedLocation = workLocation.toLowerCase().replaceAll(' ', '');
    
    // ✅ Field check
    if (normalizedLocation.startsWith('field')) {
      return 'field';
    }
    
    // ✅ Office check
    if (normalizedLocation.startsWith('office')) {
      return 'office';
    }
    
    return 'unknown';
  } catch (e) {
    debugPrint('Error getting work location type: $e');
    return 'unknown';
  }
}

Future<Map<String, String>> getWorkLocationDetails(String organizationMemberId) async {
  try {
    final member = await _supabase
        .from('organization_members')
        .select('work_location')
        .eq('id', organizationMemberId)
        .single();
    
    final workLocation = member['work_location'] as String?;
    
    if (workLocation == null || workLocation.isEmpty) {
      return {'type': 'unknown', 'location': '', 'city': ''};
    }
    
    String type = 'unknown';
    String city = '';
    
    // ✅ NORMALISASI untuk pengecekan
    final normalizedLocation = workLocation.toLowerCase().replaceAll(' ', '');
    
    // ✅ Deteksi type
    if (normalizedLocation.startsWith('field')) {
      type = 'field';
    } else if (normalizedLocation.startsWith('office')) {
      type = 'office';
    }
    
    // ✅ Extract city dari berbagai format:
    // Format 1: "office_jakarta" atau "Office_Jakarta"
    // Format 2: "office jakarta" atau "Office Jakarta"  
    // Format 3: "officeworker jakarta"
    // Format 4: "field_bandung", "field bandung", etc.
    
    // Coba extract dengan underscore dulu
    if (workLocation.contains('_')) {
      final parts = workLocation.split('_');
      if (parts.length > 1) {
        city = parts.sublist(1).join('_'); // Join sisanya jika ada multiple underscore
      }
    } 
    // Jika tidak ada underscore, coba dengan spasi
    else if (workLocation.contains(' ')) {
      final parts = workLocation.split(' ');
      if (parts.length > 1) {
        city = parts.sublist(1).join(' '); // Join sisanya jika ada multiple spasi
      }
    }
    // Jika tidak ada pemisah, coba detect dari karakter kapital (camelCase)
    else {
      // Contoh: "officeJakarta" atau "fieldBandung"
      final match = RegExp(r'^(office|field)(.+)$', caseSensitive: false)
          .firstMatch(workLocation);
      if (match != null && match.group(2) != null) {
        city = match.group(2)!;
        // Capitalize first letter
        if (city.isNotEmpty) {
          city = city[0].toUpperCase() + city.substring(1);
        }
      }
    }
    
    return {
      'type': type,
      'location': workLocation,
      'city': city.trim(),
    };
  } catch (e) {
    debugPrint('Error getting work location details: $e');
    return {'type': 'unknown', 'location': '', 'city': ''};
  }
}

  Future<bool> _performCheckOut(
  String organizationMemberId,
  DateTime now,
  Position currentPosition,
  String photoUrl, // Parameter ini tidak digunakan untuk checkout
  AttendanceDevice? device,
  AttendanceRecord existingRecord,
  WorkScheduleDetails? scheduleDetails
) async {
  final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
  final checkInCount = todayLogs.where((log) => log.eventType == 'check_in').length;
  final checkOutCount = todayLogs.where((log) => log.eventType == 'check_out').length;
  
  // Hitung total work duration dari semua cycles
  int totalWorkMinutes = 0;
  DateTime? currentCycleStart;
  
  for (var log in todayLogs) {
    if (log.eventType == 'check_in') {
      currentCycleStart = log.eventTime;
    } else if (log.eventType == 'check_out' && currentCycleStart != null) {
      totalWorkMinutes += log.eventTime.difference(currentCycleStart).inMinutes;
      currentCycleStart = null;
    }
  }
  
  if (currentCycleStart == null && existingRecord.actualCheckIn != null) {
    currentCycleStart = existingRecord.actualCheckIn!;
  }
  
  if (currentCycleStart != null) {
    totalWorkMinutes += now.difference(currentCycleStart).inMinutes;
  }
  
  // Update attendance record - TANPA photo
  Map<String, dynamic> updateData = {
    'actual_check_out': now.toIso8601String(),
    // ✅ HAPUS check_out_photo_url
    'check_out_location': {
      'latitude': currentPosition.latitude,
      'longitude': currentPosition.longitude,
    },
    'check_out_method': 'mobile_app',
    'check_out_device_id': device?.id,
    'work_duration_minutes': totalWorkMinutes,
    'updated_at': now.toIso8601String(),
  };

  if (scheduleDetails?.minimumHours != null) {
    final expectedMinutes = (scheduleDetails!.minimumHours! * 60).toInt();
    final overtimeMinutes = totalWorkMinutes - expectedMinutes;
    if (overtimeMinutes > 0) {
      updateData['overtime_minutes'] = overtimeMinutes;
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

  // ✅ PERBAIKAN: Log tanpa photo untuk checkout
  await _logAttendanceEvent(
    organizationMemberId, 
    'check_out', 
    now, 
    currentPosition, 
    device,
    // ✅ TIDAK pass photoUrl untuk checkout
  );

  // Auto-end break if currently on break
  await autoEndBreakOnCheckout(organizationMemberId, device?.id != null ? int.tryParse(device!.id) : null);

  debugPrint('✓ Check-out #${checkOutCount + 1} completed. Total work: ${totalWorkMinutes}min');
  return true;
}

Future<void> autoEndBreakOnCheckout(String organizationMemberId, int? deviceId) async {
  try {
    // Check if currently on break
    final breakInfo = await getTodayBreakInfo(organizationMemberId);
    
    if (breakInfo['is_currently_on_break'] == true && 
        breakInfo['break_start_time'] != null) {
      
      final now = TimezoneHelper.nowInOrgTime();
      final breakStartTime = TimezoneHelper.toOrgTime(
        DateTime.parse(breakInfo['break_start_time'])
      );
      final actualBreakDuration = now.difference(breakStartTime);

      // Insert break_in log
      await _supabase.from('attendance_logs').insert({
        'organization_member_id': organizationMemberId,
        'event_type': 'break_in',
        'event_time': now.toIso8601String(),
        'device_id': deviceId,
        'method': 'mobile_app_auto',
        'is_verified': true,
        'verification_method': 'auto_checkout',
      });

      // Update break duration
      await updateBreakDuration(
        int.parse(organizationMemberId),
        actualBreakDuration.inMinutes
      );

      debugPrint('✓ Auto-ended break on checkout. Duration: ${actualBreakDuration.inMinutes}m');
    }
  } catch (e) {
    debugPrint('Error auto-ending break: $e');
    // Don't throw, checkout should still succeed
  }
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
  AttendanceDevice? device,
  {String? photoUrl} // ✅ TAMBAHKAN parameter photoUrl
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
      if (photoUrl != null) 'photo_url': photoUrl, // ✅ Simpan photo_url di sini
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
  
  // ✅ NEW: Check if schedule exists for check-in
  if (type == 'check_in') {
    if (scheduleDetails == null) {
      throw _ValidationException(
        'No work schedule assigned. Please contact your administrator to set up your schedule.'
      );
    }
    
    if (!scheduleDetails.isWorkingDay) {
      throw _ValidationException(
        'Today is not a working day according to your schedule.'
      );
    }
  }
  
  // Schedule time validation
  if (scheduleDetails?.startTime != null && scheduleDetails?.endTime != null) {
    final isBeforeWork = TimeHelper.isBeforeWorkHours(
      scheduleDetails!.startTime!,
      graceMinutes: 30
    );
    final isAfterWork = TimeHelper.isAfterWorkHours(
      scheduleDetails.endTime!,
      graceMinutes: 30
    );

    if (type == 'check_in' && isAfterWork) {
      final endTime = scheduleDetails.endTime!;
      throw _ValidationException(
        'Work hours have ended. Check-in is only allowed until 30 minutes after $endTime.'
      );
    }

    if (type == 'check_in' && isBeforeWork) {
      final startTime = scheduleDetails.startTime!;
      throw _ValidationException(
        'Check-in is too early. You can check in starting 30 minutes before $startTime.'
      );
    }

    if (type == 'check_out' && isAfterWork) {
      final endTime = scheduleDetails.endTime!;
      throw _ValidationException(
        'Work hours have ended. Check-out is only allowed until 30 minutes after $endTime.'
      );
    }
  }

  final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

  switch (type) {
    case 'check_in':
      // ✅ FIX: Count check-ins and check-outs
      final checkInLogs = todayLogs.where((log) => log.eventType == 'check_in').toList();
      final checkOutLogs = todayLogs.where((log) => log.eventType == 'check_out').toList();
      
      // ✅ FIX: Hanya boleh check-in jika semua check-in sebelumnya sudah di-checkout
      if (checkInLogs.length > checkOutLogs.length) {
        throw _ValidationException(
          'You are currently checked in. Please check out first before checking in again.'
        );
      }
      
      // ✅ FIX: Tidak boleh check-in jika sedang break
      if (lastLog?.eventType == 'break_out') {
        throw _ValidationException(
          'You are currently on break. Please resume work first before checking in again.'
        );
      }
      
      // Time validation
      if (scheduleDetails?.startTime != null) {
        final scheduledStart = TimeHelper.parseTimeString(scheduleDetails!.startTime!);
        final maxEarlyMinutes = 30;
        if (_isTimeBeforeScheduled(now, scheduledStart, maxEarlyMinutes)) {
          throw _ValidationException(
            'Check-in is too early. You can check in 30 minutes before ${scheduleDetails.startTime}.'
          );
        }
      }
      
      debugPrint('✓ Check-in validation passed (balanced check-in/out)');
      break;
      
    case 'check_out':
      final checkInLogs = todayLogs.where((log) => log.eventType == 'check_in').toList();
      final checkOutLogs = todayLogs.where((log) => log.eventType == 'check_out').toList();
      
      if (checkInLogs.isEmpty) {
        throw _ValidationException('You must check in before you can check out.');
      }
      
      // ✅ FIX: Check if balanced
      if (checkOutLogs.length >= checkInLogs.length) {
        throw _ValidationException(
          'You have already checked out. Please check in first before checking out again.'
        );
      }
      
      // ✅ FIX: Tidak boleh checkout jika sedang break
      if (lastLog?.eventType == 'break_out') {
        throw _ValidationException(
          'You are currently on break. Please resume work before checking out.'
        );
      }
      
      // Minimum hours validation
      if (existingRecord?.actualCheckIn != null && scheduleDetails?.minimumHours != null) {
        final totalWorkMinutes = DateTime.now().difference(existingRecord!.actualCheckIn!).inMinutes;
        final breakMinutes = existingRecord.breakDurationMinutes ?? 0;
        final netWorkHours = (totalWorkMinutes - breakMinutes) / 60;
        
        if (netWorkHours < scheduleDetails!.minimumHours!) {
          throw _ValidationException(
            'You need to complete at least ${scheduleDetails.minimumHours} hours before checking out.'
          );
        }
      }
      
      debugPrint('✓ Check-out validation passed');
      break;
      
    case 'break_out':
      // ✅ FIX: Harus sudah check-in dan belum checkout
      final checkInLogs = todayLogs.where((log) => log.eventType == 'check_in').toList();
      final checkOutLogs = todayLogs.where((log) => log.eventType == 'check_out').toList();
      
      if (checkInLogs.isEmpty) {
        throw _ValidationException('You must check in before taking a break.');
      }
      
      if (checkOutLogs.length >= checkInLogs.length) {
        throw _ValidationException(
          'You have checked out. Please check in first before taking a break.'
        );
      }
      
      // ✅ FIX: Tidak boleh double break-out
      if (lastLog?.eventType == 'break_out') {
        throw _ValidationException(
          'You are already on break. Please resume work first before taking another break.'
        );
      }
      
      // Break time window validation
if (scheduleDetails?.breakStart != null && scheduleDetails?.breakEnd != null) {
  final breakStart = TimeHelper.parseTimeString(scheduleDetails!.breakStart!);
  final breakEnd = TimeHelper.parseTimeString(scheduleDetails.breakEnd!);
  
  // ✅ Allow break from 1 minute before until break end
  final currentMinutes = TimeHelper.timeToMinutes(now);
  final breakStartMinutes = TimeHelper.timeToMinutes(breakStart);
  final breakEndMinutes = TimeHelper.timeToMinutes(breakEnd);
  
  if (currentMinutes < (breakStartMinutes - 1)) {
    throw _ValidationException(
      'Break time starts at ${scheduleDetails.breakStart}. Please wait for the break period.'
    );
  }
  
  if (currentMinutes > breakEndMinutes) {
    throw _ValidationException(
      'Break time has ended at ${scheduleDetails.breakEnd}. You can no longer take a break.'
    );
  }
}
      break;
      
    case 'break_in':
      // ✅ FIX: Harus sedang break
      if (lastLog?.eventType != 'break_out') {
        throw _ValidationException('You are not currently on break.');
      }
      
      // ✅ FIX: Harus masih dalam sesi check-in yang aktif
      final checkInLogs = todayLogs.where((log) => log.eventType == 'check_in').toList();
      final checkOutLogs = todayLogs.where((log) => log.eventType == 'check_out').toList();
      
      if (checkInLogs.isEmpty) {
        throw _ValidationException('You must check in first before resuming work.');
      }
      
      if (checkOutLogs.length >= checkInLogs.length) {
        throw _ValidationException(
          'You have checked out. Please check in first before resuming work.'
        );
      }
      break;
  }
}

bool _isWithinWorkHours(WorkScheduleDetails? scheduleDetails, {int graceMinutes = 30}) {
  if (scheduleDetails?.startTime == null || scheduleDetails?.endTime == null) {
    return true; // Jika tidak ada jadwal, izinkan
  }

  return TimeHelper.isWithinWorkHours(
    scheduleDetails!.startTime!,
    scheduleDetails.endTime!,
    graceMinutes: graceMinutes,
  );
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

  Future<bool> hasActiveSchedule(String organizationMemberId) async {
  try {
    final schedule = await loadCurrentSchedule(organizationMemberId);
    if (schedule == null) return false;
    
    if (schedule.workScheduleId != null) {
      final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
      final scheduleDetails = await loadWorkScheduleDetails(
        schedule.workScheduleId!, 
        dayOfWeek
      );
      return scheduleDetails != null;
    }
    
    return schedule.shiftId != null;
  } catch (e) {
    debugPrint('Error checking schedule: $e');
    return false;
  }
}
Future<int> getTodayCheckInCount(String organizationMemberId) async {
  try {
    await _validateUserAccess(organizationMemberId);
    
    final today = TimezoneHelper.getTodayDateString();
    final startOfDay = '$today 00:00:00';
    final endOfDay = '$today 23:59:59';
    
    final response = await _supabase
        .from('attendance_logs')
        .select('id')
        .eq('organization_member_id', organizationMemberId)
        .eq('event_type', 'check_in')
        .gte('event_time', startOfDay)
        .lte('event_time', endOfDay);

    return List<Map<String, dynamic>>.from(response).length;
  } catch (e) {
    debugPrint('Error getting check-in count: $e');
    return 0;
  }
}
Future<List<DateTime>> getTodayCheckInTimes(String organizationMemberId) async {
  try {
    await _validateUserAccess(organizationMemberId);
    
    final today = TimezoneHelper.getTodayDateString();
    final startOfDay = '$today 00:00:00';
    final endOfDay = '$today 23:59:59';
    
    final response = await _supabase
        .from('attendance_logs')
        .select('event_time')
        .eq('organization_member_id', organizationMemberId)
        .eq('event_type', 'check_in')
        .gte('event_time', startOfDay)
        .lte('event_time', endOfDay)
        .order('event_time', ascending: true);

    return List<Map<String, dynamic>>.from(response)
        .map((log) => DateTime.parse(log['event_time'] as String))
        .toList();
  } catch (e) {
    debugPrint('Error getting check-in times: $e');
    return [];
  }
}
 Future<AttendanceStatus> getCurrentAttendanceStatus(String organizationMemberId, {bool forceRefresh = false}) async {
  final cacheKey = CacheKeys.statusKey(organizationMemberId);
  
  // Check cache first (short TTL karena status bisa berubah)
  if (!forceRefresh) {
    final cached = _cache.get<AttendanceStatus>(cacheKey);
    if (cached != null) {
      debugPrint('CacheHelper: Attendance status loaded from cache');
      return cached;
    }
  }

  try {
    await _validateUserAccess(organizationMemberId);
    
    // ✅ OPTIMIZATION: Load from cache if available, otherwise load fresh
    final todayRecords = await loadTodayAttendanceRecords(organizationMemberId, forceRefresh: forceRefresh);
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId, forceRefresh: forceRefresh);
    
    final existingRecord = todayRecords.isNotEmpty ? todayRecords.first : null;
    final lastLog = todayLogs.isNotEmpty ? todayLogs.last : null;

    // ✅ PERUBAHAN: Cek dari logs, bukan dari record
    final checkInLogs = todayLogs.where((log) => log.eventType == 'check_in').toList();
    final checkOutLogs = todayLogs.where((log) => log.eventType == 'check_out').toList();

    AttendanceStatus status;
    // Jika belum ada check-in sama sekali
    if (checkInLogs.isEmpty) {
      status = AttendanceStatus.notCheckedIn;
    }
    // Jika semua check-in sudah di-checkout (balanced)
    else if (checkOutLogs.length >= checkInLogs.length) {
      status = AttendanceStatus.notCheckedIn;
    }
    // Jika sedang break
    else if (lastLog?.eventType == 'break_out') {
      status = AttendanceStatus.onBreak;
    }
    // Jika ada check-in yang belum di-checkout
    else {
      status = AttendanceStatus.working;
    }
    
    // Cache the result (short TTL)
    _cache.set(cacheKey, status, ttl: _statusCacheTTL);
    
    return status;
  } catch (e) {
    debugPrint('Error getting attendance status: $e');
    return AttendanceStatus.unknown;
  }
}
 
Future<List<AttendanceAction>> getAvailableActions(
  String organizationMemberId, {
  MemberSchedule? existingSchedule, // ✅ TAMBAHKAN parameter optional
  WorkScheduleDetails? existingScheduleDetails, // ✅ TAMBAHKAN parameter optional
}) async {
  try {
    await _validateUserAccess(organizationMemberId);
    
    final status = await getCurrentAttendanceStatus(organizationMemberId);
    
    // ✅ Gunakan existing schedule jika ada, jika tidak load baru
    final schedule = existingSchedule ?? await loadCurrentSchedule(organizationMemberId);
    
    // ✅ Gunakan existing schedule details jika ada
    WorkScheduleDetails? scheduleDetails = existingScheduleDetails;
    
    // ✅ Load schedule details hanya jika belum ada DAN schedule punya workScheduleId
    if (scheduleDetails == null && schedule?.workScheduleId != null) {
      final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
      scheduleDetails = await loadWorkScheduleDetails(schedule!.workScheduleId!, dayOfWeek);
    }

    final currentTime = TimeHelper.getCurrentTime();
    List<AttendanceAction> actions = [];

    final hasSchedule = scheduleDetails != null;
    final isWorkingDay = scheduleDetails?.isWorkingDay ?? false;
    
    final isAfterWorkHours = scheduleDetails?.endTime != null 
        ? TimeHelper.isAfterWorkHours(scheduleDetails!.endTime!, graceMinutes: 30)
        : false;
    
    final isBeforeWorkHours = scheduleDetails?.startTime != null
        ? TimeHelper.isBeforeWorkHours(scheduleDetails!.startTime!, graceMinutes: 30)
        : false;

    // ✅ Get today's logs to determine exact state
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId);
    final checkInCount = todayLogs.where((log) => log.eventType == 'check_in').length;
    final checkOutCount = todayLogs.where((log) => log.eventType == 'check_out').length;
    final isBalanced = checkInCount == checkOutCount;

    switch (status) {
      case AttendanceStatus.notCheckedIn:
        String? checkInReason;
        bool canCheckIn = true;
        
        if (!hasSchedule) {
          checkInReason = 'No work schedule assigned. Contact your administrator.';
          canCheckIn = false;
        } else if (!isWorkingDay) {
          checkInReason = 'Today is not a working day';
          canCheckIn = false;
        } else if (isAfterWorkHours) {
          checkInReason = 'Work hours have ended for today';
          canCheckIn = false;
        } else if (isBeforeWorkHours) {
          checkInReason = 'Too early to check in';
          canCheckIn = false;
        } else {
          // ✅ Show different message for first vs subsequent check-in
          if (checkInCount > 0) {
            checkInReason = isBalanced 
              ? 'Ready for next check-in session'
              : 'Complete current session first';
            canCheckIn = isBalanced;
          } else {
            checkInReason = _getCheckInReason(currentTime, scheduleDetails);
            canCheckIn = _canCheckIn(currentTime, scheduleDetails);
          }
        }
        
        actions.add(AttendanceAction(
          type: 'check_in',
          label: checkInCount > 0 ? 'Check In' : 'Check In',
          isEnabled: canCheckIn,
          reason: checkInReason,
        ));
        break;

      case AttendanceStatus.working:
        // Break action
        if (_canTakeBreak(currentTime, scheduleDetails)) {
          actions.add(AttendanceAction(
            type: 'break_out',
            label: 'Take Break',
            isEnabled: !isAfterWorkHours && hasSchedule,
            reason: !hasSchedule 
                ? 'No schedule assigned'
                : isAfterWorkHours 
                    ? 'Work hours have ended' 
                    : null,
          ));
        }
        
        // Check-out action
        actions.add(AttendanceAction(
          type: 'check_out',
          label: 'Check Out',
          isEnabled: !isAfterWorkHours && hasSchedule,
          reason: !hasSchedule 
              ? 'No schedule assigned'
              : isAfterWorkHours 
                  ? 'Work hours have ended for today' 
                  : null,
        ));
        break;

      case AttendanceStatus.onBreak:
        actions.add(AttendanceAction(
          type: 'break_in',
          label: 'Resume Work',
          isEnabled: !isAfterWorkHours && hasSchedule,
          reason: !hasSchedule 
              ? 'No schedule assigned'
              : isAfterWorkHours 
                  ? 'Work hours have ended' 
                  : null,
        ));
        break;

      case AttendanceStatus.checkedOut:
        // Should not happen with new logic
        break;

      case AttendanceStatus.unknown:
        actions.add(AttendanceAction(
          type: 'check_in',
          label: 'Check In',
          isEnabled: hasSchedule && !isAfterWorkHours && !isBeforeWorkHours,
          reason: !hasSchedule
              ? 'No work schedule assigned. Contact your administrator.'
              : isAfterWorkHours 
                  ? 'Work hours have ended for today'
                  : isBeforeWorkHours
                      ? 'Too early to check in'
                      : null,
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
  
  // ✅ Allow break 1 minute before scheduled break time
  final currentMinutes = TimeHelper.timeToMinutes(currentTime);
  final breakStartMinutes = TimeHelper.timeToMinutes(breakStart);
  final breakEndMinutes = TimeHelper.timeToMinutes(breakEnd);
  
  // Can take break from 1 minute before start until break end time
  return currentMinutes >= (breakStartMinutes - 1) && currentMinutes <= breakEndMinutes;
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
        
        // ✅ FIX: Invalidate cache setelah update break duration
        _invalidateAttendanceCache(organizationMemberId.toString());
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
 Future<Map<String, dynamic>> getTodayBreakInfo(String organizationMemberId, {bool forceRefresh = false}) async {
  final cacheKey = CacheKeys.breakInfoKey(organizationMemberId);
  
  // Check cache first
  if (!forceRefresh) {
    final cached = _cache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) {
      debugPrint('CacheHelper: Break info loaded from cache');
      return cached;
    }
  }

  try {
    await _validateUserAccess(organizationMemberId);
    
    final today = TimezoneHelper.getTodayDateString();
    
    // ✅ OPTIMIZATION: Use cached today records if available
    final todayRecords = await loadTodayAttendanceRecords(organizationMemberId, forceRefresh: forceRefresh);
    final totalBreakMinutes = todayRecords.isNotEmpty 
        ? (todayRecords.first.breakDurationMinutes ?? 0)
        : 0;

    // ✅ OPTIMIZATION: Use cached today logs if available
    final todayLogs = await getTodayAttendanceLogs(organizationMemberId, forceRefresh: forceRefresh);
    final breakLogs = todayLogs.where((log) => 
      log.eventType == 'break_out' || log.eventType == 'break_in'
    ).toList();
    
    List<Map<String, dynamic>> breakSessions = [];
    DateTime? currentBreakStart;
    bool isCurrentlyOnBreak = false;

    // ✅ FIX: Sort logs by event_time untuk memastikan urutan benar
    breakLogs.sort((a, b) => a.eventTime.compareTo(b.eventTime));

    for (var log in breakLogs) {
      if (log.eventType == 'break_out') {
        // ✅ FIX: Jika ada break_out, mulai break session baru
        // Jika ada break session yang belum selesai, selesaikan dulu (edge case)
        if (currentBreakStart != null && isCurrentlyOnBreak) {
          // Break session sebelumnya belum selesai - ini tidak seharusnya terjadi, tapi handle it
          debugPrint('⚠️ Warning: Multiple break_out without break_in. Closing previous break.');
          breakSessions.add({
            'start': currentBreakStart,
            'end': log.eventTime, // Use next break_out time as end (edge case)
            'duration': log.eventTime.difference(currentBreakStart).inMinutes,
          });
        }
        currentBreakStart = log.eventTime;
        isCurrentlyOnBreak = true;
      } else if (log.eventType == 'break_in') {
        // ✅ FIX: Break_in harus selalu menutup break session jika ada
        if (currentBreakStart != null && isCurrentlyOnBreak) {
          final breakEnd = log.eventTime;
          final duration = breakEnd.difference(currentBreakStart).inMinutes;
          
          breakSessions.add({
            'start': currentBreakStart,
            'end': breakEnd,
            'duration': duration,
          });
          
          currentBreakStart = null;
          isCurrentlyOnBreak = false;
        } else if (currentBreakStart == null) {
          // ✅ FIX: Break_in tanpa break_out sebelumnya - ini error state, tapi handle gracefully
          debugPrint('⚠️ Warning: break_in log found without matching break_out');
        }
      }
    }

    // ✅ FIX: Jika masih ada break session yang aktif, tambahkan ke sessions
    if (isCurrentlyOnBreak && currentBreakStart != null) {
      breakSessions.add({
        'start': currentBreakStart,
        'end': null,
        'duration': TimezoneHelper.nowInOrgTime().difference(currentBreakStart).inMinutes,
      });
    }

    final result = {
      'total_break_minutes': totalBreakMinutes,
      'break_sessions': breakSessions,
      'is_currently_on_break': isCurrentlyOnBreak,
      'current_break_start': currentBreakStart?.toIso8601String(),
      'break_start_time': currentBreakStart?.toIso8601String(),
    };
    
    // Cache the result
    _cache.set(cacheKey, result, ttl: _todayDataCacheTTL);
    
    return result;
  } catch (e) {
    debugPrint('Error getting break info: $e');
    rethrow;
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

  // ✅ Helper untuk retry with timeout
  Future<T> _executeWithRetry<T>({
    required Future<T> Function() operation,
    int maxRetries = 2,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    int attempts = 0;
    
    while (attempts < maxRetries) {
      try {
        return await operation().timeout(timeout);
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          rethrow;
        }
        debugPrint('Retry attempt $attempts after error: $e');
        await Future.delayed(Duration(seconds: attempts));
      }
    }
    
    throw Exception('Max retries exceeded');
  }

  // ✅ TAMBAHKAN method baru untuk load data sekaligus
Future<Map<String, dynamic>> loadDashboardData(String organizationMemberId, {bool forceRefresh = false}) async {
  // ✅ OPTIMIZATION: Try to use cached data first
  if (!forceRefresh) {
    final cachedTodayRecords = _cache.get<List<AttendanceRecord>>(CacheKeys.todayRecordsKey(organizationMemberId));
    final cachedTodayLogs = _cache.get<List<AttendanceLog>>(CacheKeys.todayLogsKey(organizationMemberId));
    final cachedRecentRecords = _cache.get<List<AttendanceRecord>>(CacheKeys.recentRecordsKey(organizationMemberId));
    
    if (cachedTodayRecords != null && cachedTodayLogs != null && cachedRecentRecords != null) {
      debugPrint('CacheHelper: Dashboard data loaded from cache');
      return {
        'today_records': cachedTodayRecords,
        'recent_records': cachedRecentRecords,
        'today_logs': cachedTodayLogs,
      };
    }
  }
  
  try {
    await _validateUserAccess(organizationMemberId);
    
    final today = TimezoneHelper.getTodayDateString();
    
    // ✅ OPTIMIZATION: Load semua data dalam parallel
    final results = await Future.wait([
      // Today records
      _supabase
          .from('attendance_records')
          .select('*, shifts(id, name, start_time, end_time)')
          .eq('organization_member_id', organizationMemberId)
          .eq('attendance_date', today)
          .order('created_at'),
      
      // Recent records (30 days) - reduced from full year
      _supabase
          .from('attendance_records')
          .select('*, shifts(id, name, start_time, end_time)')
          .eq('organization_member_id', organizationMemberId)
          .order('attendance_date', ascending: false)
          .limit(30),
      
      // Today logs
      _supabase
          .from('attendance_logs')
          .select('*')
          .eq('organization_member_id', organizationMemberId)
          .gte('event_time', '${today}T00:00:00')
          .lte('event_time', '${today}T23:59:59')
          .order('event_time'),
    ]);
    
    final todayRecords = List<Map<String, dynamic>>.from(results[0])
        .map((json) => AttendanceRecord.fromJson(json))
        .toList();
    final recentRecords = List<Map<String, dynamic>>.from(results[1])
        .map((json) => AttendanceRecord.fromJson(json))
        .toList();
    final todayLogs = List<Map<String, dynamic>>.from(results[2])
        .map((json) => AttendanceLog.fromJson(json))
        .toList();
    
    // ✅ Cache the results
    _cache.set(CacheKeys.todayRecordsKey(organizationMemberId), todayRecords, ttl: _todayDataCacheTTL);
    _cache.set(CacheKeys.todayLogsKey(organizationMemberId), todayLogs, ttl: _todayDataCacheTTL);
    _cache.set(CacheKeys.recentRecordsKey(organizationMemberId), recentRecords, ttl: Duration(minutes: 10));
    
    return {
      'today_records': todayRecords,
      'recent_records': recentRecords,
      'today_logs': todayLogs,
    };
  } catch (e) {
    debugPrint('Error loading dashboard data: $e');
    rethrow;
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