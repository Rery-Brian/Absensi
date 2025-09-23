// services/attendance_service.dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_model.dart' hide Position;
import '../helpers/timezone_helper.dart';

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
      // Create profile logic...
    } else {
      print('✅ Profile found: ${profileResponse['display_name']}');
    }
    
    return profileResponse != null ? UserProfile.fromJson(profileResponse) : null;
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
      
      final result = await _supabase.rpc('add_user_to_organization', params: {
        'p_user_id': userId,
        'p_employee_id': null,
        'p_organization_code': 'COMPANY001',
        'p_department_code': 'IT',
        'p_position_code': 'STAFF',
      });

      if (result != null) {
        print('User auto-registered successfully with member ID: $result');
        return true;
      }
      
      return false;
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
            attendance_logs(*)
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
          .limit(5);

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
  
  /// Perform attendance (check in or check out)
  Future<bool> performAttendance({
    required String type,
    required String organizationMemberId,
    required Position currentPosition,
    required String photoUrl,
    AttendanceDevice? device,
    MemberSchedule? schedule,
    List<AttendanceRecord>? todayRecords,
  }) async {
    try {
      final today = TimezoneHelper.getTodayDateString();
      final now = TimezoneHelper.nowInJakarta();

      print('Performing attendance: $type for member: $organizationMemberId');
      print('Date: $today, Time: ${now.toIso8601String()}');

      final existingRecord = todayRecords?.isNotEmpty == true
          ? todayRecords!.first
          : null;

      if (existingRecord != null) {
        print('Updating existing attendance record: ${existingRecord.id}');
        
        // Update existing record
        if (type == 'check_in' && !existingRecord.hasCheckedIn) {
          await _supabase
              .from('attendance_records')
              .update({
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
              })
              .eq('id', existingRecord.id);

          print('Check-in updated successfully');
        } else if (type == 'check_out' && !existingRecord.hasCheckedOut) {
          await _supabase
              .from('attendance_records')
              .update({
                'actual_check_out': now.toIso8601String(),
                'check_out_photo_url': photoUrl,
                'check_out_location': {
                  'latitude': currentPosition.latitude,
                  'longitude': currentPosition.longitude,
                },
                'check_out_method': 'mobile_app',
                'check_out_device_id': device?.id,
                'updated_at': now.toIso8601String(),
              })
              .eq('id', existingRecord.id);

          print('Check-out updated successfully');
        } else {
          throw Exception('${type == 'check_in' ? 'Check-in' : 'Check-out'} already done today');
        }
      } else if (type == 'check_in') {
        print('Creating new attendance record');
        
        // Create new record for check-in
        final newRecord = await _supabase
            .from('attendance_records')
            .insert({
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
            })
            .select()
            .single();

        print('New attendance record created: ${newRecord['id']}');
      } else {
        throw Exception('Cannot check-out without check-in');
      }

      // Insert attendance log
      await _supabase.from('attendance_logs').insert({
        'organization_member_id': organizationMemberId,
        'event_type': type,
        'event_time': now.toIso8601String(),
        'device_id': device?.id,
        'method': 'mobile_app',
        'location': {
          'latitude': currentPosition.latitude,
          'longitude': currentPosition.longitude,
        },
        'is_verified': device != null ? isWithinRadius(currentPosition, device) : false,
      });

      print('Attendance log inserted successfully');
      print('Attendance operation completed successfully');
      
      return true;
    } catch (e) {
      print('Error performing attendance: $e');
      throw Exception('Failed to perform attendance: $e');
    }
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