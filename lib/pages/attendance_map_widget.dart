import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../helpers/localization_helper.dart';

class AttendanceMapWidget extends StatefulWidget {
  final Position? userPosition;
  final Position? officePosition;
  final String? userPhotoUrl;
  final String? officePhotoUrl;
  final String userName;
  final String officeName;
  final double radiusMeters;
  final bool showRadius;

  const AttendanceMapWidget({
    super.key,
    required this.userPosition,
    required this.officePosition,
    this.userPhotoUrl,
    this.officePhotoUrl,
    required this.userName,
    required this.officeName,
    required this.radiusMeters,
    this.showRadius = true,
  });

  @override
  State<AttendanceMapWidget> createState() => _AttendanceMapWidgetState();
}

class _AttendanceMapWidgetState extends State<AttendanceMapWidget>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _fitBounds() {
    if (widget.userPosition == null && widget.officePosition == null) return;

    if (widget.userPosition != null && widget.officePosition != null) {
      final bounds = LatLngBounds(
        LatLng(
          math.min(widget.userPosition!.latitude, widget.officePosition!.latitude),
          math.min(widget.userPosition!.longitude, widget.officePosition!.longitude),
        ),
        LatLng(
          math.max(widget.userPosition!.latitude, widget.officePosition!.latitude),
          math.max(widget.userPosition!.longitude, widget.officePosition!.longitude),
        ),
      );

      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
      );
    } else {
      final pos = widget.userPosition ?? widget.officePosition!;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
    }
  }

  List<CircleMarker> _buildCircles() {
    if (!widget.showRadius || widget.officePosition == null) return [];
    return [
      CircleMarker(
        point: LatLng(widget.officePosition!.latitude, widget.officePosition!.longitude),
        radius: widget.radiusMeters,
        useRadiusInMeter: true,
        color: const Color(0xFF10B981).withOpacity(0.15),
        borderColor: const Color(0xFF10B981).withOpacity(0.5),
        borderStrokeWidth: 2,
      ),
    ];
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (widget.userPosition != null) {
      markers.add(
        Marker(
          point: LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude),
          width: 50,
          height: 50,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) => Transform.scale(
              scale: _pulseAnimation.value,
              child: _buildUserMarker(),
            ),
          ),
        ),
      );
    }

    if (widget.officePosition != null) {
      markers.add(
        Marker(
          point: LatLng(widget.officePosition!.latitude, widget.officePosition!.longitude),
          width: 44,
          height: 44,
          child: _buildOfficeMarker(),
        ),
      );
    }

    return markers;
  }

  Widget _buildUserMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6366F1).withOpacity(0.2),
          ),
        ),
        // Main marker
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6366F1), width: 2.5),
            ),
            child: ClipOval(
              child: widget.userPhotoUrl != null && widget.userPhotoUrl!.isNotEmpty
                  ? Image.network(
                      widget.userPhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildDefaultUserIcon(),
                    )
                  : _buildDefaultUserIcon(),
            ),
          ),
        ),
        // Online indicator
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF10B981),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfficeMarker() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF10B981), width: 2.5),
        ),
        child: ClipOval(
          child: widget.officePhotoUrl != null && widget.officePhotoUrl!.isNotEmpty
              ? Image.network(
                  widget.officePhotoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _buildDefaultOfficeIcon(),
                )
              : _buildDefaultOfficeIcon(),
        ),
      ),
    );
  }

  Widget _buildDefaultUserIcon() => Container(
        color: const Color(0xFF6366F1).withOpacity(0.1),
        child: const Icon(Icons.person, color: Color(0xFF6366F1), size: 20),
      );

  Widget _buildDefaultOfficeIcon() => Container(
        color: const Color(0xFF10B981).withOpacity(0.1),
        child: const Icon(Icons.business, color: Color(0xFF10B981), size: 20),
      );

  double? _calculateDistance() {
    if (widget.userPosition == null || widget.officePosition == null) return null;
    return Geolocator.distanceBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      widget.officePosition!.latitude,
      widget.officePosition!.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userPosition == null && widget.officePosition == null) {
      return _buildEmptyState();
    }

    final distance = _calculateDistance();
    final isWithinRadius = distance != null && distance <= widget.radiusMeters;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.userPosition != null
                    ? LatLng(widget.userPosition!.latitude, widget.userPosition!.longitude)
                    : LatLng(widget.officePosition!.latitude, widget.officePosition!.longitude),
                initialZoom: 16,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                backgroundColor: Colors.grey.shade100,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.attendance_app',
                  maxZoom: 19,
                ),
                CircleLayer(circles: _buildCircles()),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
            if (distance != null) _buildDistanceOverlay(distance, isWithinRadius),
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceOverlay(double distance, bool isWithinRadius) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isWithinRadius ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isWithinRadius 
                        ? LocalizationHelper.getText('within_range')
                        : LocalizationHelper.getText('outside_range'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isWithinRadius ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    distance < 1000
                        ? '${distance.toInt()} ${LocalizationHelper.getText('meters')} ${LocalizationHelper.getText('from_office')}'
                        : '${(distance / 1000).toStringAsFixed(1)} ${LocalizationHelper.getText('kilometers')} ${LocalizationHelper.getText('from_office')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        children: [
          _buildControlButton(
            Icons.my_location, 
            _fitBounds, 
            LocalizationHelper.getText('my_location')
          ),
          const SizedBox(height: 6),
          _buildControlButton(
            Icons.add, 
            () {
              _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
            }, 
            LocalizationHelper.getText('zoom_in')
          ),
          const SizedBox(height: 6),
          _buildControlButton(
            Icons.remove, 
            () {
              _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
            }, 
            LocalizationHelper.getText('zoom_out')
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Container(
        height: 300,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                LocalizationHelper.getText('location_not_available'),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
}