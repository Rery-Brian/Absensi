// models/attendance_model.dart

class UserProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String? displayName;
  final String? profilePhotoUrl;
  final bool isActive;

  UserProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.displayName,
    this.profilePhotoUrl,
    required this.isActive,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      displayName: json['display_name'],
      profilePhotoUrl: json['profile_photo_url'],
      isActive: json['is_active'] ?? true,
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}

class Organization {
  final String id;
  final String name;
  final String code;

  Organization({
    required this.id,
    required this.name,
    required this.code,
  });

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

class Department {
  final String id;
  final String name;
  final String code;

  Department({
    required this.id,
    required this.name,
    required this.code,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

class Position {
  final String id;
  final String title;
  final String code;

  Position({
    required this.id,
    required this.title,
    required this.code,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

class OrganizationMember {
  final String id;
  final String userId;
  final String organizationId;
  final String? employeeId;
  final String? departmentId;
  final String? positionId;
  final bool isActive;
  final Organization? organization;
  final Department? department;
  final Position? position;

  OrganizationMember({
    required this.id,
    required this.userId,
    required this.organizationId,
    this.employeeId,
    this.departmentId,
    this.positionId,
    required this.isActive,
    this.organization,
    this.department,
    this.position,
  });

  factory OrganizationMember.fromJson(Map<String, dynamic> json) {
    return OrganizationMember(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      employeeId: json['employee_id']?.toString(),
      departmentId: json['department_id']?.toString(),
      positionId: json['position_id']?.toString(),
      isActive: json['is_active'] ?? true,
      organization: json['organizations'] != null
          ? Organization.fromJson(json['organizations'])
          : null,
      department: json['departments'] != null
          ? Department.fromJson(json['departments'])
          : null,
      position: json['positions'] != null
          ? Position.fromJson(json['positions'])
          : null,
    );
  }
}

class AttendanceDevice {
  final String id;
  final String deviceName;
  final String deviceCode;
  final String organizationId;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final String? location;
  final bool isActive;

  AttendanceDevice({
    required this.id,
    required this.deviceName,
    required this.deviceCode,
    required this.organizationId,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
    this.location,
    required this.isActive,
  });

  factory AttendanceDevice.fromJson(Map<String, dynamic> json) {
    return AttendanceDevice(
      id: json['id']?.toString() ?? '',
      deviceName: json['device_name']?.toString() ?? '',
      deviceCode: json['device_code']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      radiusMeters: _parseDouble(json['radius_meters']) ?? 100.0,
      location: json['location']?.toString(),
      isActive: json['is_active'] ?? true,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool get hasValidCoordinates => latitude != null && longitude != null;
}

class AttendanceRecord {
  final String id;
  final String organizationMemberId;
  final String attendanceDate;
  final DateTime? actualCheckIn;
  final DateTime? actualCheckOut;
  final String? checkInPhotoUrl;
  final String? checkOutPhotoUrl;
  final Map<String, dynamic>? checkInLocation;
  final Map<String, dynamic>? checkOutLocation;
  final String status;
  final String? scheduledShiftId;

  AttendanceRecord({
    required this.id,
    required this.organizationMemberId,
    required this.attendanceDate,
    this.actualCheckIn,
    this.actualCheckOut,
    this.checkInPhotoUrl,
    this.checkOutPhotoUrl,
    this.checkInLocation,
    this.checkOutLocation,
    required this.status,
    this.scheduledShiftId,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      organizationMemberId: json['organization_member_id']?.toString() ?? '',
      attendanceDate: json['attendance_date']?.toString() ?? '',
      actualCheckIn: _parseDateTime(json['actual_check_in']),
      actualCheckOut: _parseDateTime(json['actual_check_out']),
      checkInPhotoUrl: json['check_in_photo_url']?.toString(),
      checkOutPhotoUrl: json['check_out_photo_url']?.toString(),
      checkInLocation: json['check_in_location'] as Map<String, dynamic>?,
      checkOutLocation: json['check_out_location'] as Map<String, dynamic>?,
      status: json['status']?.toString() ?? 'absent',
      scheduledShiftId: json['scheduled_shift_id']?.toString(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool get hasCheckedIn => actualCheckIn != null;
  bool get hasCheckedOut => actualCheckOut != null;
  bool get canCheckOut => hasCheckedIn && !hasCheckedOut;
}

class Shift {
  final String id;
  final String name;
  final String code;
  final String startTime;
  final String endTime;

  Shift({
    required this.id,
    required this.name,
    required this.code,
    required this.startTime,
    required this.endTime,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
    );
  }
}

class WorkSchedule {
  final String id;
  final String name;
  final String code;
  final String? description;

  WorkSchedule({
    required this.id,
    required this.name,
    required this.code,
    this.description,
  });

  factory WorkSchedule.fromJson(Map<String, dynamic> json) {
    return WorkSchedule(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString(),
    );
  }
}

class MemberSchedule {
  final String id;
  final String organizationMemberId;
  final String? shiftId;
  final String? workScheduleId;
  final String effectiveDate;
  final String? endDate;
  final bool isActive;
  final Shift? shift;
  final WorkSchedule? workSchedule;

  MemberSchedule({
    required this.id,
    required this.organizationMemberId,
    this.shiftId,
    this.workScheduleId,
    required this.effectiveDate,
    this.endDate,
    required this.isActive,
    this.shift,
    this.workSchedule,
  });

  factory MemberSchedule.fromJson(Map<String, dynamic> json) {
    return MemberSchedule(
      id: json['id']?.toString() ?? '',
      organizationMemberId: json['organization_member_id']?.toString() ?? '',
      shiftId: json['shift_id']?.toString(),
      workScheduleId: json['work_schedule_id']?.toString(),
      effectiveDate: json['effective_date']?.toString() ?? '',
      endDate: json['end_date']?.toString(),
      isActive: json['is_active'] ?? true,
      shift: json['shifts'] != null ? Shift.fromJson(json['shifts']) : null,
      workSchedule: json['work_schedules'] != null
          ? WorkSchedule.fromJson(json['work_schedules'])
          : null,
    );
  }
}