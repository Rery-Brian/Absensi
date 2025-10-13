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
      final selectedDevice =
          await _deviceService.loadSelectedDevice(widget.organizationId);

      setState(() {
        _devices = devices;
        _filteredDevices = List.from(devices);
        _selectedDevice = selectedDevice;
        _previouslySelectedDevice = selectedDevice;
        _isLoading = false;
      });

      _calculateDistances();
      debugPrint('Loaded ${devices.length} devices');
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
      _calculateDistances();
    } catch (e) {
      debugPrint('Failed to get current location: $e');
    }
  }

  void _calculateDistances() {
    if (_currentPosition == null || _devices.isEmpty) return;

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
      }
    }

    setState(() {
      _distances = newDistances;
    });
  }

  Future<void> _selectDevice(AttendanceDevice device) async {
    if (_isSelecting) return;

    setState(() {
      _isSelecting = true;
      _selectedDevice = device;
    });

    try {
      await _deviceService.setSelectedDevice(device);

      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${device.deviceName} ${LocalizationHelper.getText('success').toLowerCase()}',
        );
      }

      await Future.delayed(const Duration(milliseconds: 400));

      final deviceChanged = _previouslySelectedDevice?.id != device.id;

      if (mounted) {
        Navigator.of(context).pop({
          'success': true,
          'deviceChanged': deviceChanged,
          'selectedDevice': device,
          'previousDevice': _previouslySelectedDevice,
        });
      }
    } catch (e) {
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
      if (mounted) setState(() => _isSelecting = false);
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
        title: Text(
          LocalizationHelper.getText('select_location'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.2),
        leading: widget.isRequired
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context)
                    .pop({'success': false, 'deviceChanged': false}),
              ),
      ),
      body: _isLoading ? _buildLoadingView() : _buildDeviceList(),
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildLoadingView() => const Center(
        child: CircularProgressIndicator(),
      );

  Widget _buildDeviceList() {
    if (_devices.isEmpty) return _buildEmptyState();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.organizationName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    LocalizationHelper.getText('choose_attendance_location'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSearchBar(),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: _filteredDevices.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false, child: _buildNoResultsContent())
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildDeviceCard(_filteredDevices[index]),
                    childCount: _filteredDevices.length,
                  ),
                ),
        ),
        if (!widget.isRequired)
          SliverToBoxAdapter(child: _buildFooterMessage()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: LocalizationHelper.getText('search_location'),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          prefixIcon: Icon(Icons.search,
              color: Colors.white.withOpacity(0.7), size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear,
                      color: Colors.white.withOpacity(0.7), size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }

 

  Widget _buildDeviceCard(AttendanceDevice device) {
    final distance = _distances[device.id];
    final isSelected = _selectedDevice?.id == device.id;
    final isInRange = distance != null && distance <= device.radiusMeters;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        elevation: isSelected ? 5 : 1.5,
        shadowColor: Colors.black.withOpacity(0.06),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isSelecting ? null : () => _selectDevice(device),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withOpacity(0.05)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? primaryColor : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildDeviceIcon(isSelected, isInRange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        device.deviceName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? primaryColor : Colors.black87,
                        ),
                      ),
                    ),
                    _buildSelectionIndicator(isSelected),
                  ],
                ),
                if (device.location?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          device.location!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
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
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSelected
              ? [primaryColor, primaryColor.withOpacity(0.85)]
              : [Colors.grey.shade50, Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_on_rounded,
            color: isSelected ? Colors.white : Colors.grey.shade600,
            size: 24,
          ),
          if (isInRange && !isSelected)
            Positioned(
              right: 5,
              top: 5,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green.shade500,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionIndicator(bool isSelected) {
    if (_isSelecting && isSelected) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (isSelected) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDeviceStatusRow(AttendanceDevice device, double? distance) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _statusChip(
          text:
              '${device.radiusMeters}m ${LocalizationHelper.getText('radius')}',
          color: Colors.green,
        ),
        if (distance != null)
          _statusChip(
            text: _formatDistance(distance),
            color: distance <= device.radiusMeters
                ? Colors.blue
                : Colors.orange,
          ),
      ],
    );
  }

  Widget _statusChip({required String text, required MaterialColor color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, color: color.shade400, size: 10),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                color: color.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(LocalizationHelper.getText('no_locations_available')),
        ),
      );

  Widget _buildNoResultsContent() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(LocalizationHelper.getText('no_locations_found')),
        ),
      );

  Widget _buildFooterMessage() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        LocalizationHelper.getText('change_location_anytime'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
    );
  }
}
