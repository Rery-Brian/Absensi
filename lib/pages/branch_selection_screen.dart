// screens/branch_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/branch_model.dart';
import '../services/branch_service.dart';
import '../services/attendance_service.dart';

class BranchSelectionScreen extends StatefulWidget {
  final String organizationId;
  final String organizationName;
  final bool isRequired;

  const BranchSelectionScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
    this.isRequired = false,
  });

  @override
  State<BranchSelectionScreen> createState() => _BranchSelectionScreenState();
}

class _BranchSelectionScreenState extends State<BranchSelectionScreen> {
  final BranchService _branchService = BranchService();
  final AttendanceService _attendanceService = AttendanceService();
  
  List<Branch> _branches = [];
  Branch? _selectedBranch;
  bool _isLoading = true;
  bool _isSelecting = false;
  Position? _currentPosition;
  Map<String, double> _distances = {};

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _getCurrentLocation();
  }

  Future<void> _loadBranches() async {
    try {
      setState(() => _isLoading = true);
      
      final branches = await _branchService.loadBranches(widget.organizationId);
      final selectedBranch = await _branchService.loadSelectedBranch(widget.organizationId);

      setState(() {
        _branches = branches;
        _selectedBranch = selectedBranch;
        _isLoading = false;
      });

      _calculateDistances();
    } catch (e) {
      _showSnackBar('Failed to load branches: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await _attendanceService.getCurrentLocation();
      _calculateDistances();
    } catch (e) {
      debugPrint('Failed to get current location: $e');
    }
  }

  void _calculateDistances() {
    if (_currentPosition == null || _branches.isEmpty) return;

    final newDistances = <String, double>{};
    for (final branch in _branches) {
      if (branch.hasValidCoordinates) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          branch.latitude!,
          branch.longitude!,
        );
        newDistances[branch.id] = distance;
      }
    }

    setState(() {
      _distances = newDistances;
    });
  }

  Future<void> _selectBranch(Branch branch) async {
    if (_isSelecting) return;

    setState(() {
      _isSelecting = true;
      _selectedBranch = branch;
    });

    try {
      await _branchService.setSelectedBranch(branch);
      
      _showSnackBar('${branch.name} selected successfully');
      
      // Wait a moment then navigate back
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showSnackBar('Failed to select branch: $e', isError: true);
      setState(() {
        _selectedBranch = null;
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
        title: const Text('Select Branch'),
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: widget.isRequired ? null : IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading ? _buildLoadingView() : _buildBranchList(),
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
            'Loading branches...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchList() {
    if (_branches.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Header
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
                'Choose your work location',
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
              ],
            ],
          ),
        ),

        // Branch list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _branches.length,
            itemBuilder: (context, index) {
              final branch = _branches[index];
              final distance = _distances[branch.id];
              final isSelected = _selectedBranch?.id == branch.id;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Material(
                  borderRadius: BorderRadius.circular(16),
                  elevation: isSelected ? 8 : 2,
                  shadowColor: isSelected ? primaryColor.withValues(alpha: 0.3) : Colors.black12,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _isSelecting ? null : () => _selectBranch(branch),
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
                                  Icons.business,
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
                                      branch.name,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? primaryColor : Colors.black87,
                                      ),
                                    ),
                                    if (branch.code.isNotEmpty && branch.code != branch.name) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        branch.code,
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
                          
                          if (branch.fullAddress.isNotEmpty) ...[
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
                                    branch.fullAddress,
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
                                      '${branch.radiusMeters}m radius',
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
                                    color: distance <= branch.radiusMeters 
                                        ? Colors.blue.shade50 
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        distance <= branch.radiusMeters 
                                            ? Icons.near_me 
                                            : Icons.location_searching,
                                        size: 12,
                                        color: distance <= branch.radiusMeters 
                                            ? Colors.blue.shade600 
                                            : Colors.orange.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDistance(distance),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: distance <= branch.radiusMeters 
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
        
        // Bottom info
        if (!widget.isRequired)
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              'You can change your branch selection anytime from the profile settings.',
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
                Icons.business_outlined,
                size: 40,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Branches Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No branches have been configured for your organization yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBranches,
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
}