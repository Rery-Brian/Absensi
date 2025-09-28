// services/device_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_model.dart';

class DeviceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  AttendanceDevice? _selectedDevice;
  
  static const String _selectedDeviceKey = 'selected_device_id';

  AttendanceDevice? get selectedDevice => _selectedDevice;

  /// Load all devices for the given organization
  Future<List<AttendanceDevice>> loadDevices(String organizationId) async {
    try {
      final response = await _supabase
          .from('attendance_devices')
          .select('''
            *,
            device_types(name, category)
          ''')
          .eq('organization_id', int.parse(organizationId))
          .eq('is_active', true)
          .order('device_name');

      final devices = List<Map<String, dynamic>>.from(response)
          .map((json) => AttendanceDevice.fromJson(json))
          .toList();

      return devices;
    } catch (e) {
      throw Exception('Error loading devices: $e');
    }
  }

  /// Load a specific device by ID
  Future<AttendanceDevice?> loadDeviceById(String deviceId) async {
    try {
      final response = await _supabase
          .from('attendance_devices')
          .select('''
            *,
            device_types(name, category)
          ''')
          .eq('id', int.parse(deviceId))
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        return AttendanceDevice.fromJson(response);
      }
      return null;
    } catch (e) {
      throw Exception('Error loading device: $e');
    }
  }

  /// Set the selected device and save to preferences
  Future<void> setSelectedDevice(AttendanceDevice device) async {
    try {
      _selectedDevice = device;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedDeviceKey, device.id);
    } catch (e) {
      throw Exception('Error setting selected device: $e');
    }
  }

  /// Load the previously selected device from preferences
  Future<AttendanceDevice?> loadSelectedDevice(String organizationId) async {
    try {
      if (_selectedDevice != null && _selectedDevice!.organizationId == organizationId) {
        return _selectedDevice;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString(_selectedDeviceKey);
      
      if (savedDeviceId != null) {
        final device = await loadDeviceById(savedDeviceId);
        if (device != null && device.organizationId == organizationId) {
          _selectedDevice = device;
          return device;
        } else {
          await clearSelectedDevice();
        }
      }

      return null;
    } catch (e) {
      throw Exception('Error loading selected device: $e');
    }
  }

  /// Clear the selected device
  Future<void> clearSelectedDevice() async {
    try {
      _selectedDevice = null;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedDeviceKey);
    } catch (e) {
      throw Exception('Error clearing selected device: $e');
    }
  }

  /// Check if a device selection is required for the organization
  Future<bool> isSelectionRequired(String organizationId) async {
    try {
      final devices = await loadDevices(organizationId);
      
      // If there are multiple devices, selection is required
      if (devices.length > 1) {
        return true;
      }
      
      // If there's exactly one device, auto-select it
      if (devices.length == 1) {
        await setSelectedDevice(devices.first);
        return false;
      }
      
      // No devices available - selection not required
      return false;
    } catch (e) {
      throw Exception('Error checking selection requirement: $e');
    }
  }
}