import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import '../models/attendance_model.dart';
import '../services/device_service.dart';
import '../services/attendance_service.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final String organizationId;
  final String organizationName;
  final bool isRequired;

  const DeviceSelectionScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
    this.isRequired = false,
  });

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final DeviceService _deviceService = DeviceService();
  final AttendanceService _attendanceService = AttendanceService();

  List<AttendanceDevice> _devices = [];
  AttendanceDevice? _selectedDevice;
  AttendanceDevice? _previouslySelectedDevice; // Track previous selection
  bool _isLoading = true;
  bool _isSelecting = false;
  geolocator.Position? _currentPosition;
  Map<String, double> _distances = {};

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _getCurrentLocation();
  }

  Future<void> _loadDevices() async {
    try {
      setState(() => _isLoading = true);

      final devices = await _deviceService.loadDevices(widget.organizationId);
      final selectedDevice = await _deviceService.loadSelectedDevice(widget.organizationId);

      setState(() {
        _devices = devices;
        _selectedDevice = selectedDevice;
        _previouslySelectedDevice = selectedDevice; // Store initial selection
        _isLoading = false;
      });

      _calculateDistances();
      debugPrint('Loaded ${devices.length} devices');
      debugPrint('Current selected device: ${selectedDevice?.deviceName}');
    } catch (e) {
      debugPrint('Error loading devices: $e');
      _showSnackBar('Failed to load devices: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      debugPrint('Getting current location...');
      _currentPosition = await _attendanceService.getCurrentLocation();
      if (_currentPosition != null) {
        debugPrint('Current location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      } else {
        debugPrint('Failed to get current location');
      }
      _calculateDistances();
    } catch (e) {
      debugPrint('Failed to get current location: $e');
    }
  }

  void _calculateDistances() {
    if (_currentPosition == null || _devices.isEmpty) {
      debugPrint('Cannot calculate distances - missing location or devices');
      return;
    }

    final newDistances = <String, double>{};
    for (final device in _devices) {
      if (device.hasValidCoordinates) {
        final distance = geolocator.Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          device.latitude!,
          device.longitude!,
        );
        newDistances[device.id] = distance;
        debugPrint('Distance to ${device.deviceName}: ${distance.toStringAsFixed(0)}m');
      }
    }

    setState(() {
      _distances = newDistances;
    });
  }

  Future<void> _selectDevice(AttendanceDevice device) async {
    if (_isSelecting) {
      debugPrint('Device selection already in progress');
      return;
    }

    debugPrint('Selecting device: ${device.deviceName} (ID: ${device.id})');
    
    setState(() {
      _isSelecting = true;
      _selectedDevice = device;
    });

    try {
      await _deviceService.setSelectedDevice(device);
      debugPrint('Device selected successfully: ${device.deviceName}');

      // Update current position to device coordinates if available
      if (device.hasValidCoordinates) {
        setState(() {
          _currentPosition = geolocator.Position(
            longitude: device.longitude!,
            latitude: device.latitude!,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
        });
        debugPrint('Updated position to device coordinates: ${device.latitude}, ${device.longitude}');
      }

      _showSnackBar('${device.deviceName} selected successfully');

      await Future.delayed(const Duration(milliseconds: 500));

      // Check if device actually changed
      final deviceChanged = _previouslySelectedDevice?.id != device.id;

      debugPrint('Device changed: $deviceChanged');
      debugPrint('Previous device: ${_previouslySelectedDevice?.deviceName}');
      debugPrint('New device: ${device.deviceName}');

      if (mounted) {
        // Return comprehensive data about the selection
        Navigator.of(context).pop({
          'success': true,
          'deviceChanged': deviceChanged,
          'selectedDevice': device,
          'previousDevice': _previouslySelectedDevice,
        });
      }
    } catch (e) {
      debugPrint('Error selecting device: $e');
      _showSnackBar('Failed to select device: $e', isError: true);
      setState(() {
        _selectedDevice = _previouslySelectedDevice; // Restore previous selection
      });
    } finally {
      if (mounted) {
        setState(() => _isSelecting = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()}m away';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km away';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Select Device Location'),
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: widget.isRequired
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop({
                  'success': false, 
                  'deviceChanged': false
                }),
              ),
      ),
      body: _isLoading ? _buildLoadingView() : _buildDeviceList(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading locations...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.organizationName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your attendance location',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              if (_currentPosition == null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_off,
                        color: Colors.orange.shade300,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Location not available',
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.green.shade300,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Location detected',
                        style: TextStyle(
                          color: Colors.green.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadDevices();
              await _getCurrentLocation();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final distance = _distances[device.id];
                final isSelected = _selectedDevice?.id == device.id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    borderRadius: BorderRadius.circular(16),
                    elevation: isSelected ? 8 : 2,
                    shadowColor: isSelected ? primaryColor.withValues(alpha: 0.3) : Colors.black12,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _isSelecting ? null : () => _selectDevice(device),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: isSelected ? Border.all(color: primaryColor, width: 2) : null,
                          color: isSelected ? primaryColor.withValues(alpha: 0.05) : Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isSelected ? primaryColor : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getDeviceIcon(device.deviceTypeId),
                                    color: isSelected ? Colors.white : Colors.grey.shade600,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.deviceName,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? primaryColor : Colors.black87,
                                        ),
                                      ),
                                      if (device.deviceCode.isNotEmpty && device.deviceCode != device.deviceName) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          device.deviceCode,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_isSelecting && isSelected) ...[
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                                    ),
                                  ),
                                ] else if (isSelected) ...[
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (device.location != null && device.location!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      device.location!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${device.radiusMeters}m radius',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (distance != null) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (distance <= device.radiusMeters)
                                          ? Colors.blue.shade50
                                          : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (distance <= device.radiusMeters)
                                              ? Icons.near_me
                                              : Icons.location_searching,
                                          size: 12,
                                          color: (distance <= device.radiusMeters)
                                              ? Colors.blue.shade600
                                              : Colors.orange.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDistance(distance),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: (distance <= device.radiusMeters)
                                                ? Colors.blue.shade700
                                                : Colors.orange.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (!widget.isRequired)
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              'You can change your device selection anytime from the profile settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.devices_outlined,
                size: 40,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Devices Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No attendance devices have been configured for your organization yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String deviceTypeId) {
    switch (deviceTypeId.toLowerCase()) {
      case 'rfid':
        return Icons.credit_card;
      case 'biometric':
        return Icons.fingerprint;
      case 'mobile':
        return Icons.phone_android;
      case 'web':
        return Icons.web;
      case 'qr_code':
        return Icons.qr_code;
      default:
        return Icons.device_unknown;
    }
  }
}