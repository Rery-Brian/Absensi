import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import '../models/attendance_model.dart';
import '../services/device_service.dart';
import '../services/attendance_service.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';

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
  final TextEditingController _searchController = TextEditingController();

  List<AttendanceDevice> _devices = [];
  List<AttendanceDevice> _filteredDevices = [];
  AttendanceDevice? _selectedDevice;
  AttendanceDevice? _previouslySelectedDevice; 
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
    _searchController.addListener(_filterDevices);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterDevices() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredDevices = List.from(_devices);
      } else {
        _filteredDevices = _devices.where((device) {
          return device.deviceName.toLowerCase().contains(query) ||
                 (device.location?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _loadDevices() async {
    try {
      setState(() => _isLoading = true);

      final devices = await _deviceService.loadDevices(widget.organizationId);
      final selectedDevice = await _deviceService.loadSelectedDevice(widget.organizationId);

      setState(() {
        _devices = devices;
        _filteredDevices = List.from(devices);
        _selectedDevice = selectedDevice;
        _previouslySelectedDevice = selectedDevice;
        _isLoading = false;
      });

      _calculateDistances();
      debugPrint('Loaded ${devices.length} devices');
      debugPrint('Current selected device: ${selectedDevice?.deviceName}');
    } catch (e) {
      debugPrint('Error loading devices: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_load')} ${LocalizationHelper.getText('location')}: $e',
        );
      }
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

      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${device.deviceName} ${LocalizationHelper.getText('success').toLowerCase()}',
        );
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final deviceChanged = _previouslySelectedDevice?.id != device.id;

      debugPrint('Device changed: $deviceChanged');
      debugPrint('Previous device: ${_previouslySelectedDevice?.deviceName}');
      debugPrint('New device: ${device.deviceName}');

      if (mounted) {
        Navigator.of(context).pop({
          'success': true,
          'deviceChanged': deviceChanged,
          'selectedDevice': device,
          'previousDevice': _previouslySelectedDevice,
        });
      }
    } catch (e) {
      debugPrint('Error selecting device: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_save')} ${LocalizationHelper.getText('location')}: $e',
        );
      }
      setState(() {
        _selectedDevice = _previouslySelectedDevice;
      });
    } finally {
      if (mounted) {
        setState(() => _isSelecting = false);
      }
    }
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()}m ${LocalizationHelper.getText('away')}';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km ${LocalizationHelper.getText('away')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(LocalizationHelper.getText('select_location')),
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
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            LocalizationHelper.getText('loading'),
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return _buildEmptyState();
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
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
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LocalizationHelper.getText('choose_attendance_location'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                _buildLocationStatus(),
                const SizedBox(height: 14),
                _buildSearchBar(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: _filteredDevices.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildNoResultsContent(),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = _filteredDevices[index];
                      return _buildDeviceCard(device);
                    },
                    childCount: _filteredDevices.length,
                  ),
                ),
        ),
        if (!widget.isRequired)
          SliverToBoxAdapter(
            child: _buildFooterMessage(),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: LocalizationHelper.getText('search_location'),
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white.withOpacity(0.7),
            size: 22,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildNoResultsContent() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 48,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              LocalizationHelper.getText('no_locations_found'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              LocalizationHelper.getText('try_different_search'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStatus() {
    if (_currentPosition == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_rounded,
              color: Colors.orange.shade300,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.getText('location_not_available'),
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.gps_fixed_rounded,
              color: Colors.green.shade300,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              LocalizationHelper.getText('location_detected'),
              style: TextStyle(
                color: Colors.green.shade300,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDeviceCard(AttendanceDevice device) {
    final distance = _distances[device.id];
    final isSelected = _selectedDevice?.id == device.id;
    final isInRange = distance != null && distance <= device.radiusMeters;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        elevation: isSelected ? 6 : 1.5,
        shadowColor: isSelected ? primaryColor.withOpacity(0.25) : Colors.black.withOpacity(0.05),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isSelecting ? null : () => _selectDevice(device),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: isSelected 
                  ? Border.all(color: primaryColor, width: 2) 
                  : Border.all(color: Colors.grey.shade200, width: 1),
              color: isSelected 
                  ? primaryColor.withOpacity(0.04) 
                  : Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildDeviceIcon(isSelected, isInRange),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        device.deviceName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? primaryColor : Colors.black87,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    _buildSelectionIndicator(isSelected),
                  ],
                ),
                if (device.location != null && device.location!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          device.location!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _buildDeviceStatusRow(device, distance),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(bool isSelected, bool isInRange) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: isSelected 
            ? LinearGradient(
                colors: [primaryColor, primaryColor.withOpacity(0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [Colors.grey.shade50, Colors.grey.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primaryColor.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_on_rounded,
            color: isSelected ? Colors.white : Colors.grey.shade600,
            size: 26,
          ),
          if (isInRange && !isSelected)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.green.shade500,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionIndicator(bool isSelected) {
    if (_isSelecting && isSelected) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      );
    } else if (isSelected) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.check_rounded,
          color: Colors.white,
          size: 18,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDeviceStatusRow(AttendanceDevice device, double? distance) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.green.shade200, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.radio_button_checked_rounded,
                size: 14,
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                '${device.radiusMeters}m ${LocalizationHelper.getText('radius')}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (distance != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: (distance <= device.radiusMeters)
                  ? Colors.blue.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: (distance <= device.radiusMeters)
                    ? Colors.blue.shade200
                    : Colors.orange.shade200,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  (distance <= device.radiusMeters)
                      ? Icons.near_me_rounded
                      : Icons.location_searching_rounded,
                  size: 14,
                  color: (distance <= device.radiusMeters)
                      ? Colors.blue.shade600
                      : Colors.orange.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDistance(distance),
                  style: TextStyle(
                    fontSize: 12,
                    color: (distance <= device.radiusMeters)
                        ? Colors.blue.shade700
                        : Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: 42,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              LocalizationHelper.getText('no_locations_available'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              LocalizationHelper.getText('no_locations_configured'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: _loadDevices,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text(LocalizationHelper.getText('refresh')),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Text(
        LocalizationHelper.getText('change_location_anytime'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade500,
          height: 1.4,
        ),
      ),
    );
  }
}