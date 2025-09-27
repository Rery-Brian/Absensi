// models/branch_model.dart

class Branch {
  final String id;
  final String organizationId;
  final String code;
  final String name;
  final String? address;
  final String? city;
  final String? stateProvince;
  final double? latitude;
  final double? longitude;
  final int radiusMeters;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Branch({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.name,
    this.address,
    this.city,
    this.stateProvince,
    this.latitude,
    this.longitude,
    this.radiusMeters = 100,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id']?.toString() ?? '',
      organizationId: json['organization_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      stateProvince: json['state_province']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      radiusMeters: json['radius_meters'] ?? 100,
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'organization_id': organizationId,
      'code': code,
      'name': name,
      'address': address,
      'city': city,
      'state_province': stateProvince,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool get hasValidCoordinates => latitude != null && longitude != null;

  String get fullAddress {
    List<String> addressParts = [];
    
    if (address != null && address!.isNotEmpty) {
      addressParts.add(address!);
    }
    if (city != null && city!.isNotEmpty) {
      addressParts.add(city!);
    }
    if (stateProvince != null && stateProvince!.isNotEmpty) {
      addressParts.add(stateProvince!);
    }
    
    return addressParts.join(', ');
  }

  String get displayName => name.isNotEmpty ? name : code;

  // Helper method to create a copy with updated fields
  Branch copyWith({
    String? id,
    String? organizationId,
    String? code,
    String? name,
    String? address,
    String? city,
    String? stateProvince,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Branch(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      code: code ?? this.code,
      name: name ?? this.name,
      address: address ?? this.address,
      city: city ?? this.city,
      stateProvince: stateProvince ?? this.stateProvince,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Branch && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Branch(id: $id, name: $name, code: $code, organizationId: $organizationId)';
  }
}