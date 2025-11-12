import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/attendance_model.dart' hide Position;
import '../services/attendance_service.dart';
import '../services/camera_service.dart';
import '../services/fake_gps_detector.dart';
import '../pages/camera_selfie_screen.dart';
import '../pages/break_page.dart';
import '../services/device_service.dart';
import '../pages/device_selection_screen.dart';
import '../pages/work_schedule_selection_modal.dart';
import 'login.dart';
import '../helpers/timezone_helper.dart';
import '../helpers/time_helper.dart';
import '../helpers/flushbar_helper.dart';
import '../helpers/localization_helper.dart';
import 'attendance_map_widget.dart';
import 'join_organization_screen.dart';
import 'skeleton_widget.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lottie/lottie.dart';

class UserDashboard extends StatefulWidget {
  final VoidCallback? onAttendanceUpdated;

  const UserDashboard({super.key, this.onAttendanceUpdated});

  @override
  State<UserDashboard> createState() => UserDashboardState();
}

class UserDashboardState extends State<UserDashboard> {
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);
  

  final GlobalKey<_DashboardContentState> _dashboardContentKey =
      GlobalKey<_DashboardContentState>();

  

  void refreshUserProfile() {
    debugPrint('UserDashboard: refreshUserProfile called');
    if (_dashboardContentKey.currentState != null) {
      _dashboardContentKey.currentState!.refreshUserProfile();
    }
  }

  Future<void> refreshAfterScheduleChange() async {
    debugPrint('UserDashboard: refreshAfterScheduleChange called');
    if (_dashboardContentKey.currentState != null) {
      await _dashboardContentKey.currentState!.refreshAfterScheduleChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _DashboardContent(
        key: _dashboardContentKey,
        onAttendanceUpdated: widget.onAttendanceUpdated,
      ),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  final VoidCallback? onAttendanceUpdated;

  const _DashboardContent({super.key, this.onAttendanceUpdated});

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final AttendanceService _attendanceService = AttendanceService();
  final DeviceService _deviceService = DeviceService();
  static const Duration dataLoadTimeout = Duration(seconds: 10);
  static const int maxRetries = 2;
  
  SupabaseClient get _supabase => Supabase.instance.client;

  bool _isSecondaryDataLoading = false;

  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  bool _isLocationUpdating = false;
  bool _isLoading = false;

  bool _requiresGpsValidation = true;
  Map<String, String> _workLocationDetails = {
    'type': 'unknown',
    'location': '',
    'city': '',
  };
  bool _isLoadingLocationInfo = false;

  Position? _currentPosition;
  Position? _gpsPosition;
  double? _distanceToDevice;
  bool? _isWithinRadius;
  UserProfile? _userProfile;
  OrganizationMember? _organizationMember;
  SimpleOrganization? _organization;
  AttendanceDevice? _selectedDevice;
  List<AttendanceRecord> _todayAttendanceRecords = [];
  List<AttendanceRecord> _recentAttendanceRecords = [];
  MemberSchedule? _currentSchedule;
  WorkScheduleDetails? _todayScheduleDetails;
  AttendanceStatus _currentStatus = AttendanceStatus.unknown;
  List<AttendanceAction> _availableActions = [];
  bool _needsDeviceSelection = false;
  Map<String, dynamic>? _breakInfo;
  final List<TimelineItem> _timelineItems = [];

  Timer? _breakIndicatorTimer;
  Timer? _breakCountdownTimer; // ✅ Timer terpisah untuk countdown (1 detik)
  Offset _indicatorPosition = const Offset(20, 100);
  bool _isDragging = false;

  Timer? _debounceTimer;
  Timer? _periodicLocationTimer;
  
  // ✅ FIX: Flag untuk mencegah break monitoring reload break info setelah stop break
  bool _breakJustStopped = false;

  // ✅ Anti-spam dialog Fake GPS
  DateTime? _lastFakeGpsDialogAt;
  bool _isFakeGpsDialogVisible = false;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color backgroundColor = Color(0xFF1F2937);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const double minGpsAccuracy = 20.0;
  static const int maxGpsRetries = 2;
  static const Duration gpsRetryDelay = Duration(seconds: 3);
  // ✅ OPTIMIZATION: Increase location update interval untuk mengurangi GPS usage
  static const Duration locationUpdateInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserData();
    _startPeriodicLocationUpdates();
    _startBreakMonitoring();
    
    // ✅ Listen perubahan bahasa dan rebuild timeline
    LocalizationHelper.languageNotifier.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _periodicLocationTimer?.cancel();
    _breakIndicatorTimer?.cancel();
    _breakCountdownTimer?.cancel(); // ✅ Cancel countdown timer
    LocalizationHelper.languageNotifier.removeListener(_onLanguageChanged); // ✅ Remove listener
    super.dispose();
  }
  
  // ✅ Handler untuk perubahan bahasa
  void _onLanguageChanged() {
    if (mounted) {
      // Rebuild timeline dengan bahasa baru
      _buildDynamicTimeline();
      // Rebuild semua UI
      setState(() {});
    }
  }

  void _startBreakMonitoring() {
    _breakIndicatorTimer?.cancel();
    // ✅ OPTIMIZATION: Timer untuk monitoring break info (5 detik)
    _breakIndicatorTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      if (!mounted) return;
      
      // ✅ FIX: Skip break monitoring jika break baru saja dihentikan
      if (_breakJustStopped) {
        // Reset flag setelah 2 menit (24 ticks * 5 seconds)
        if (timer.tick % 24 == 0) {
          _breakJustStopped = false;
          debugPrint('Break monitoring resumed after stop break');
        }
        return; // Skip monitoring untuk sementara
      }
      
      // ✅ OPTIMIZATION: Check break info setiap 60 detik (12 ticks * 5 seconds)
      if (timer.tick % 12 == 0) {
        try {
          // ✅ OPTIMIZATION: Tidak perlu force refresh, gunakan cache
          await _loadBreakInfo(forceRefresh: false);
        } catch (e) {
          debugPrint('Error monitoring break: $e');
        }
      }
      
      // ✅ Hanya update UI jika status break berubah (bukan untuk countdown)
      final isNowOnBreak = _breakInfo != null && _breakInfo!['is_currently_on_break'] == true;
      if (mounted && isNowOnBreak) {
        // Start countdown timer jika belum ada
        _startBreakCountdownTimer();
      } else if (mounted && !isNowOnBreak) {
        // Stop countdown timer jika break sudah selesai
        _breakCountdownTimer?.cancel();
        _breakCountdownTimer = null;
        setState(() {}); // Update UI untuk hide break indicator
      }
    });
    
    // ✅ Start countdown timer jika sudah ada break aktif
    if (_breakInfo != null && _breakInfo!['is_currently_on_break'] == true) {
      _startBreakCountdownTimer();
    }
  }
  
  // ✅ Timer terpisah untuk countdown break (1 detik) - smooth update
  void _startBreakCountdownTimer() {
    if (_breakCountdownTimer != null && _breakCountdownTimer!.isActive) {
      return; // Timer sudah berjalan
    }
    
    _breakCountdownTimer?.cancel();
    _breakCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // ✅ Update UI setiap 1 detik untuk countdown yang smooth
      if (_breakInfo != null && _breakInfo!['is_currently_on_break'] == true) {
        setState(() {}); // Trigger rebuild untuk update countdown
      } else {
        // Break sudah selesai, stop timer
        timer.cancel();
        _breakCountdownTimer = null;
      }
    });
  }

  void _startPeriodicLocationUpdates() {
    _periodicLocationTimer = Timer.periodic(locationUpdateInterval, (
      timer,
    ) async {
      if (mounted && !_isLocationUpdating && _selectedDevice != null) {
        await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
      }
    });
  }

  Future<bool?> _showMapPreviewDialog() async {
    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final size = MediaQuery.of(context).size;
        final topPadding = MediaQuery.of(context).padding.top;
        final bottomPadding = MediaQuery.of(context).padding.bottom;

        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: Container(
            width: size.width,
            height: size.height,
            color: Colors.white,
            child: Stack(
              children: [
                // === FULL MAP (dengan padding untuk UI elements) ===
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: topPadding + 76, // Header height
                      bottom: bottomPadding + 140, // Info bar + buttons height
                    ),
                    child: AttendanceMapWidget(
                      userPosition: _gpsPosition,
                      officePosition: _currentPosition,
                      userPhotoUrl: _userProfile?.profilePhotoUrl,
                      officePhotoUrl: _organization?.logoUrl,
                      userName: _getDisplayName(),
                      officeName:
                          _selectedDevice?.deviceName ??
                          LocalizationHelper.getText('office'),
                      radiusMeters:
                          _selectedDevice?.radiusMeters.toDouble() ?? 100,
                      showRadius: true,
                    ),
                  ),
                ),

                // === HEADER ===
                Positioned(
                  top: topPadding + 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.map,
                            color: primaryColor,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LocalizationHelper.getText(
                                  'verify_your_location',
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                LocalizationHelper.getText(
                                  'make_sure_within_office_area',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black87,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context, false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // === INFO BAR (USER + OFFICE) ===
                Positioned(
                  bottom: bottomPadding + 74,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF6366F1),
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getDisplayName(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          color: Colors.grey.shade300,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.business,
                                  color: Color(0xFF10B981),
                                  size: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDevice?.deviceName ??
                                      LocalizationHelper.getText('office'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // === BOTTOM BUTTONS ===
                Positioned(
                  bottom: bottomPadding + 16,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: Colors.white,
                          ),
                          child: Text(
                            LocalizationHelper.getText('cancel'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: (_isWithinRadius ?? false)
                              ? () => Navigator.pop(context, true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            disabledBackgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                (_isWithinRadius ?? false)
                                    ? Icons.check_circle
                                    : Icons.warning_amber_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (_isWithinRadius ?? false)
                                    ? LocalizationHelper.getText(
                                        'confirm_location',
                                      )
                                    : LocalizationHelper.getText(
                                        'out_of_range',
                                      ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> refreshUserProfile() async {
    debugPrint('DashboardContent: refreshUserProfile called');
    try {
      // ✅ OPTIMIZATION: Gunakan cache jika available, hanya force refresh jika perlu
      final updatedProfile = await _attendanceService.loadUserProfile(forceRefresh: false);
      if (updatedProfile != null && mounted) {
        // ✅ OPTIMIZATION: Hanya setState jika data benar-benar berubah
        if (_userProfile?.displayName != updatedProfile.displayName ||
            _userProfile?.profilePhotoUrl != updatedProfile.profilePhotoUrl) {
          setState(() {
            _userProfile = updatedProfile;
          });
          debugPrint('✓ User profile refreshed in dashboard');
        }
        
        // ✅ OPTIMIZATION: Load org member hanya jika belum ada atau perlu update
        if (_organizationMember == null) {
          final updatedOrgMember = await _attendanceService.loadOrganizationMember(forceRefresh: false);
          if (updatedOrgMember != null && mounted) {
            setState(() {
              _organizationMember = updatedOrgMember;
            });
            debugPrint('✓ Organization member loaded in dashboard');
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to refresh user profile: $e');
    }
  }

  Future<void> refreshAfterScheduleChange() async {
    debugPrint('DashboardContent: refreshAfterScheduleChange called');
    if (!mounted) return;
    try {
      await _loadScheduleData().timeout(const Duration(seconds: 5), onTimeout: () => Future.value());
      if (!mounted) return;
      await _updateAttendanceStatus().timeout(const Duration(seconds: 5), onTimeout: () => Future.value());
      if (!mounted) return;
      await _buildDynamicTimeline().timeout(const Duration(seconds: 3), onTimeout: () => Future.value());
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('DashboardContent: refreshAfterScheduleChange error: $e');
    }
  }

  void triggerAttendanceHistoryRefresh() {
    debugPrint('Dashboard: Attendance completed - should refresh history');
    widget.onAttendanceUpdated?.call();
  }

  Future<void> _initializeServices() async {
    try {
      await CameraService.initializeCameras();
    } catch (e) {
      debugPrint('Error initializing services: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_initialize_services'),
        );
      }
    }
  }

Future<void> _loadUserData() async {
  if (!mounted) return; // ✅ CHECK #1: Awal method
  
  setState(() => _isInitialLoading = true);

  try {
    // ✅ STEP 1: Load critical data (gunakan cache dari service)
    final criticalData = await Future.wait([
      _attendanceService.loadUserProfile(), // ✅ Service sudah handle caching
      _attendanceService.loadOrganizationMember(), // ✅ Service sudah handle caching
    ]).timeout(
      const Duration(seconds: 6),
      onTimeout: () async {
        debugPrint('⚠️ Critical data timeout, using cached data');
        // ✅ Return cached data jika timeout
        return Future.wait([
          _attendanceService.loadUserProfile(), // Will return cached if available
          _attendanceService.loadOrganizationMember(), // Will return cached if available
        ]);
      },
    );

    if (!mounted) return; // ✅ CHECK #2: Setelah async

    _userProfile = criticalData[0] as UserProfile?;
    _organizationMember = criticalData[1] as OrganizationMember?;

    if (_userProfile == null || _organizationMember == null) {
      if (mounted) { // ✅ CHECK #3: Sebelum Navigator
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('no_user_profile_found'),
        );
        Navigator.of(context).pushReplacementNamed('/login');
      }
      if (mounted) setState(() => _isInitialLoading = false); // ✅ CHECK #4
      return;
    }

    // ✅ STEP 2: Set organization dari member data dulu (temporary)
    if (_organizationMember?.organization != null && mounted) { // ✅ CHECK #5
      setState(() {
        _organization = SimpleOrganization(
          id: _organizationMember!.organization!.id,
          name: _organizationMember!.organization!.name,
          logoUrl: _organizationMember!.organization!.logoUrl,
        );
      });
      debugPrint('✓ Organization set from member data: ${_organization?.name}');
    }

    // ✅ STEP 3: Check device selection FIRST (location dulu)
    await _checkDeviceSelection();

    if (!mounted) return; // ✅ CHECK #6: Setelah async

    if (_needsDeviceSelection) {
      if (mounted) setState(() => _isInitialLoading = false); // ✅ CHECK #7
      return;
    }

    // ✅ STEP 4: Load schedule data AFTER location is selected (jadwal kerja setelah location)
    await _loadScheduleData();

    if (!mounted) return;

    // ✅ STEP 5: Load organization info dan location info (parallel)
    await Future.wait([
      _loadLocationInfo(),
      _loadOrganizationInfo(), // ✅ Load organization info lengkap di sini
    ]).timeout(
      const Duration(seconds: 5),
      onTimeout: () async {
        debugPrint('⚠️ Essential data timeout');
        return [];
      },
    );

    if (!mounted) return;

    // ✅ STEP 6: Load data untuk status card (gunakan cache dari service)
    await Future.wait([
      _loadOrganizationData(forceRefresh: false), // ✅ Gunakan cache
      _loadBreakInfo(forceRefresh: false), // ✅ Gunakan cache
    ]).timeout(
      const Duration(seconds: 5),
      onTimeout: () async {
        debugPrint('⚠️ Organization data timeout, using cached data');
        return [];
      },
    );

    if (!mounted) return; // ✅ CHECK #8: Setelah async

    // ✅ STEP 5: Update status dan timeline
    await _updateAttendanceStatus().timeout(
      const Duration(seconds: 3),
      onTimeout: () async {
        debugPrint('⚠️ Status update timeout');
        return Future.value();
      },
    );

    if (!mounted) return; // ✅ CHECK #9: Setelah async

    await _buildDynamicTimeline().timeout(
      const Duration(seconds: 2),
      onTimeout: () async {
        debugPrint('⚠️ Timeline build timeout');
        return Future.value();
      },
    );

    if (!mounted) return; // ✅ CHECK #10: Setelah async

    // ✅ Hide skeleton - semua data sudah ready
    setState(() => _isInitialLoading = false);
    
  } catch (e) {
    debugPrint('Error in _loadUserData: $e');
    if (mounted) { // ✅ CHECK #11: Sebelum FlushbarHelper
      FlushbarHelper.showError(
        context,
        LocalizationHelper.getText('failed_to_load_user_data'),
      );
    }
    if (mounted) setState(() => _isInitialLoading = false); // ✅ CHECK #12
  }
}

Future<void> _loadRemainingDataInBackground() async {
  if (_organizationMember == null) return;

  if (mounted) {
    setState(() => _isSecondaryDataLoading = true);
  }

  try {
    // ✅ Load data yang tidak urgent (parallel)
    await Future.wait([
      _loadOrganizationData(),
      _loadBreakInfo(),
      _loadLocationInfo(), // Pindahkan ke sini
    ]).timeout(
      const Duration(seconds: 8),
      onTimeout: () async {
        debugPrint('⚠️ Remaining data timeout');
        return [];
      },
    );

    // ✅ Update status (butuh data dari loadOrganizationData)
    await _updateAttendanceStatus().timeout(
      const Duration(seconds: 3),
      onTimeout: () async {
        debugPrint('⚠️ Status update timeout');
        return Future.value();
      },
    );

    // ✅ Build timeline (terakhir)
    await _buildDynamicTimeline().timeout(
      const Duration(seconds: 2),
      onTimeout: () async {
        debugPrint('⚠️ Timeline build timeout');
        return Future.value();
      },
    );

  } catch (e) {
    debugPrint('Error loading remaining data: $e');
  } finally {
    if (mounted) {
      setState(() => _isSecondaryDataLoading = false);
    }
  }
}

  Future<void> _loadSecondaryDataInBackground() async {
  if (_organizationMember == null) return;

  // ✅ Set loading state
  if (mounted) {
    setState(() => _isSecondaryDataLoading = true);
  }

  try {
    // ✅ STEP 1: Load schedule dulu (penting untuk timeline)
    await _loadScheduleData().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ Schedule load timeout');
        return Future.value();
      },
    );

    // ✅ STEP 2: Load data lainnya (parallel, dengan individual timeout)
    await Future.wait([
      _loadOrganizationData().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Organization data timeout');
          return Future.value();
        },
      ),
      _loadBreakInfo().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Break info timeout');
          return Future.value();
        },
      ),
      _loadLocationInfo().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ Location info timeout');
          return Future.value();
        },
      ),
    ]).catchError((e) {
      debugPrint('Some secondary data failed to load: $e');
      return []; // ✅ Return empty list
    });

    // ✅ STEP 3: Update status dan timeline
    await _updateAttendanceStatus().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ Attendance status timeout');
        return Future.value();
      },
    );
    
    await _buildDynamicTimeline().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('⚠️ Timeline build timeout');
        return Future.value();
      },
    );

  } catch (e) {
    debugPrint('Error loading secondary data: $e');
  } finally {
    // ✅ Clear loading state
    if (mounted) {
      setState(() => _isSecondaryDataLoading = false);
    }
  }
}
  Future<void> _loadLocationInfo() async {
  if (_organizationMember == null || _isLoadingLocationInfo || !mounted) return; // ✅

  setState(() => _isLoadingLocationInfo = true);

  try {
    final requiresGps = await _attendanceService.requiresGpsValidation(
      _organizationMember!.id,
    );
    final locationDetails = await _attendanceService.getWorkLocationDetails(
      _organizationMember!.id,
    );

    if (!mounted) return; // ✅ CHECK setelah async

    setState(() {
      _requiresGpsValidation = requiresGps;
      _workLocationDetails = locationDetails;
    });
  } catch (e) {
    debugPrint('Error loading location info: $e');
  } finally {
    if (mounted) { // ✅ CHECK sebelum setState
      setState(() => _isLoadingLocationInfo = false);
    }
  }
}

  Future<void> _loadBreakInfo({bool forceRefresh = false}) async {
    if (_organizationMember == null) return;

    try {
      // ✅ OPTIMIZATION: Service sudah handle caching
      final breakInfo = await _attendanceService.getTodayBreakInfo(
        _organizationMember!.id,
        forceRefresh: forceRefresh,
      );
      
      // ✅ FIX: Update break info dan trigger setState untuk update UI
      final wasOnBreak = _breakInfo != null && _breakInfo!['is_currently_on_break'] == true;
      final isNowOnBreak = breakInfo['is_currently_on_break'] == true;
      
      if (mounted) {
        setState(() {
          _breakInfo = breakInfo;
        });
        
        // ✅ Start/stop countdown timer berdasarkan status break
        if (isNowOnBreak && !wasOnBreak) {
          // Break baru dimulai - start countdown timer
          _startBreakCountdownTimer();
        } else if (!isNowOnBreak && wasOnBreak) {
          // Break sudah selesai - stop countdown timer
          _breakCountdownTimer?.cancel();
          _breakCountdownTimer = null;
        }
      }
      
      debugPrint('Break info loaded: is_currently_on_break=${breakInfo['is_currently_on_break']}');
      debugPrint('Break info: $breakInfo');
    } catch (e) {
      debugPrint('Error loading break info: $e');
    }
  }

  Future<void> _checkDeviceSelection() async {
  if (_organizationMember == null || !mounted) return; // ✅ CHECK di awal

  try {
    final requiresGps = await _attendanceService.requiresGpsValidation(
      _organizationMember!.id,
    );

    if (!mounted) return; // ✅ CHECK setelah async

    setState(() {
      _requiresGpsValidation = requiresGps;
    });

    debugPrint(
      requiresGps
          ? '✓ Office worker detected - GPS validation required'
          : '✓ Field worker detected - GPS validation optional',
    );

    // ✅ STEP 2: Check device selection (1x saja)
    final selectionRequired = await _deviceService.isSelectionRequired(
      _organizationMember!.organizationId,
    );

    final selectedDevice = await _deviceService.loadSelectedDevice(
      _organizationMember!.organizationId,
    );

    // ✅ Block jika Office Worker DAN belum pilih device
    if (selectedDevice == null && requiresGps && selectionRequired) {
      setState(() {
        _needsDeviceSelection = true;
        _selectedDevice = null;
        _currentPosition = null;
      });
      return;
    }

    // ✅ Set device (1x saja)
    _selectedDevice = selectedDevice;

    // ✅ Set position jika ada device
    if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
      _currentPosition = Position(
        longitude: _selectedDevice!.longitude!,
        latitude: _selectedDevice!.latitude!,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );

      // ✅ Update GPS async (tidak blocking)
      if (requiresGps) {
        unawaited(
          _updateGpsPositionAndDistance(debounce: false, retryCount: 0),
        );
      }
    }

    if (!mounted) return;

    setState(() => _needsDeviceSelection = false);
  } catch (e) {
    debugPrint('Error checking location selection: $e');
  }
}

  Future<void> _navigateToDeviceSelection({bool isRequired = false}) async {
    if (_organizationMember == null) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          organizationId: _organizationMember!.organizationId,
          organizationName:
              _organization?.name ?? LocalizationHelper.getText('organization'),
          isRequired: isRequired,
        ),
      ),
    );

    if (result != null && result['success'] == true) {
      final newSelectedDevice = result['selectedDevice'] as AttendanceDevice?;
      final deviceChanged = result['deviceChanged'] as bool? ?? false;

      setState(() {
        _currentPosition = null;
        _gpsPosition = null;
        _distanceToDevice = null;
        _isWithinRadius = null;
        _selectedDevice = newSelectedDevice;
      });

      if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
        setState(() {
          _currentPosition = Position(
            longitude: _selectedDevice!.longitude!,
            latitude: _selectedDevice!.latitude!,
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
      }

      setState(() => _needsDeviceSelection = false);

      await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);

      if (deviceChanged || isRequired) {
        await _forceDataReload();
      }

      if (deviceChanged && mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${LocalizationHelper.getText('location_changed_to')} ${_selectedDevice?.deviceName ?? LocalizationHelper.getText('unknown_device')}',
        );
      }
    }
  }

  Future<void> _showWorkScheduleSelectionModal({bool isRequired = false}) async {
    if (_organizationMember == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: !isRequired,
      builder: (context) => WorkScheduleSelectionModal(
        organizationId: _organizationMember!.organizationId,
        organizationName:
            _organization?.name ?? LocalizationHelper.getText('organization'),
        isRequired: isRequired,
      ),
    );

    if (result != null && result['success'] == true) {
      // Invalidate schedule cache
      _attendanceService.invalidateScheduleCache(_organizationMember!.id);
      
      // Reload schedule data
      await _loadScheduleData();
      
      // Update attendance status and timeline
      await _updateAttendanceStatus(forceRefresh: true);
      await _buildDynamicTimeline();
      
      if (mounted) {
        setState(() {});
        FlushbarHelper.showSuccess(
          context,
          LocalizationHelper.getText('work_schedule_selected_successfully'),
        );
      }
    }
  }

  Future<void> _forceDataReload() async {
    setState(() {
      _isInitialLoading = true;
      _todayAttendanceRecords.clear();
      _recentAttendanceRecords.clear();
      _currentSchedule = null;
      _todayScheduleDetails = null;
      _currentStatus = AttendanceStatus.unknown;
      _availableActions.clear();
      _timelineItems.clear();
      _breakInfo = null;
      _requiresGpsValidation = true;
      _workLocationDetails = {'type': 'unknown', 'location': '', 'city': ''};
    });

    try {
      // ✅ OPTIMIZATION: Force refresh semua data setelah perubahan
      await _loadScheduleData();
      await Future.wait([
        _loadOrganizationData(forceRefresh: true), // ✅ Force refresh
        _loadBreakInfo(forceRefresh: true), // ✅ Force refresh
        _loadLocationInfo(),
      ]);
      await _updateAttendanceStatus(forceRefresh: true); // ✅ Force refresh
      await _buildDynamicTimeline();
    } catch (e) {
      debugPrint('Error in force data reload: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_reload_data')}: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _updateGpsPositionAndDistance({
    bool debounce = true,
    int retryCount = 0,
  }) async {
    if (_isLocationUpdating) return;
    setState(() => _isLocationUpdating = true);

    if (debounce) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 2), () async {
        await _performGpsUpdate(retryCount);
      });
    } else {
      await _performGpsUpdate(retryCount);
    }
  }

  Future<void> _performGpsUpdate(int retryCount) async {
    try {
      final position = await _attendanceService.getCurrentLocation();

      if (position.accuracy <= minGpsAccuracy) {
        setState(() {
          _gpsPosition = position;
          if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
            _distanceToDevice = Geolocator.distanceBetween(
              _gpsPosition!.latitude,
              _gpsPosition!.longitude,
              _selectedDevice!.latitude!,
              _selectedDevice!.longitude!,
            );
            _isWithinRadius = _attendanceService.isWithinRadius(
              _gpsPosition!,
              _selectedDevice!,
            );
          }
          _isLocationUpdating = false;
        });

        // ✅ Trigger Fake GPS dialog segera setelah update posisi (anti-spam 15s)
        if (mounted && _gpsPosition != null) {
          try {
            final isFake = await FakeGpsDetector.isFakeGps(_gpsPosition!);
            if (isFake) {
              final now = DateTime.now();
              final allowShow = !_isFakeGpsDialogVisible &&
                  (_lastFakeGpsDialogAt == null ||
                      now.difference(_lastFakeGpsDialogAt!).inSeconds > 15);
              if (allowShow) {
                final validation = await FakeGpsDetector.validateGpsPosition(_gpsPosition!);
                _isFakeGpsDialogVisible = true;
                await _showFakeGpsDialog(validation);
                _lastFakeGpsDialogAt = DateTime.now();
                _isFakeGpsDialogVisible = false;
              }
            }
          } catch (_) {}
        }
      } else if (retryCount < maxGpsRetries) {
        await Future.delayed(gpsRetryDelay);
        await _performGpsUpdate(retryCount + 1);
      } else {
        setState(() {
          _gpsPosition = position;
          if (_selectedDevice != null && _selectedDevice!.hasValidCoordinates) {
            _distanceToDevice = Geolocator.distanceBetween(
              _gpsPosition!.latitude,
              _gpsPosition!.longitude,
              _selectedDevice!.latitude!,
              _selectedDevice!.longitude!,
            );
            _isWithinRadius = _attendanceService.isWithinRadius(
              _gpsPosition!,
              _selectedDevice!,
            );
          }
          _isLocationUpdating = false;
        });

        // ✅ Trigger Fake GPS dialog juga pada path else (akurasi tidak memenuhi setelah retry)
        if (mounted && _gpsPosition != null) {
          try {
            final isFake = await FakeGpsDetector.isFakeGps(_gpsPosition!);
            if (isFake) {
              final now = DateTime.now();
              final allowShow = !_isFakeGpsDialogVisible &&
                  (_lastFakeGpsDialogAt == null ||
                      now.difference(_lastFakeGpsDialogAt!).inSeconds > 15);
              if (allowShow) {
                final validation = await FakeGpsDetector.validateGpsPosition(_gpsPosition!);
                _isFakeGpsDialogVisible = true;
                await _showFakeGpsDialog(validation);
                _lastFakeGpsDialogAt = DateTime.now();
                _isFakeGpsDialogVisible = false;
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      // Jika error kemungkinan terkait fake GPS, tampilkan dialog dan hentikan flushbar
      final err = e.toString().toLowerCase();
      final isFakeErr = err.contains('fake gps') || err.contains('mock location') || err.contains('gps tidak valid');
      if (isFakeErr && mounted) {
        try {
          // Tampilkan default dialog jika tidak ada posisi valid untuk validasi detail
          await _showFakeGpsDialogDefault();
        } catch (_) {}
        setState(() {
          _isLocationUpdating = false;
        });
        return;
      }

      if (retryCount < maxGpsRetries) {
        await Future.delayed(gpsRetryDelay);
        await _performGpsUpdate(retryCount + 1);
      } else {
        setState(() {
          _distanceToDevice = null;
          _isWithinRadius = null;
          _isLocationUpdating = false;
        });
        if (mounted) {
          FlushbarHelper.showError(
            context,
            LocalizationHelper.getText('unable_to_get_precise_location'),
          );
        }
      }
    }
  }

  Future<void> _loadOrganizationInfo({bool forceRefresh = false}) async {
    if (_organizationMember == null) return;

    // ✅ OPTIMIZATION: Gunakan organization dari cached org member jika available
    if (!forceRefresh && _organizationMember?.organization != null) {
      final org = _organizationMember!.organization!;
      if (mounted) {
        setState(() {
          _organization = SimpleOrganization(
            id: org.id,
            name: org.name,
            logoUrl: org.logoUrl,
          );
        });
        debugPrint('✓ Using organization from cached org member');
        return;
      }
    }

    try {
      dynamic orgIdValue;
      try {
        orgIdValue = int.parse(_organizationMember!.organizationId);
      } catch (e) {
        orgIdValue = _organizationMember!.organizationId;
      }

      final response = await Supabase.instance.client
          .from('organizations')
          .select('id, name, logo_url')
          .eq('id', orgIdValue)
          .single()
          .timeout(const Duration(seconds: 5));

      if (response != null && mounted) {
        final org = SimpleOrganization(
          id: response['id'].toString(),
          name: response['name'] ?? 'Unknown Organization',
          logoUrl: response['logo_url'],
        );
        
        setState(() {
          _organization = org;
        });
        debugPrint('✓ Organization data loaded: ${org.name}, Logo: ${org.logoUrl}');
      }
    } catch (e) {
      debugPrint('Error loading organization info: $e');
      // ✅ OPTIMIZATION: Fallback ke organization dari cached org member
      if (_organizationMember?.organization != null && mounted) {
        final org = _organizationMember!.organization!;
        setState(() {
          _organization = SimpleOrganization(
            id: org.id,
            name: org.name,
            logoUrl: org.logoUrl,
          );
        });
        debugPrint('✓ Using organization from cached org member after error');
      }
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);

    try {
      // ✅ OPTIMIZATION: Force refresh untuk mendapatkan data terbaru
      _userProfile = await _attendanceService.loadUserProfile(forceRefresh: true).timeout(
        const Duration(seconds: 3),
        onTimeout: () async {
          debugPrint('⚠️ Profile refresh timeout, using cached');
          return _userProfile;
        },
      );

      if (_organizationMember != null) {
        // ✅ OPTIMIZATION: Force refresh untuk data yang berubah sering
        await Future.wait([
          _loadScheduleData(),
          _loadLocationInfo(),
          _loadOrganizationData(forceRefresh: true), // ✅ Force refresh attendance data
          _loadBreakInfo(forceRefresh: true), // ✅ Force refresh break info
          _loadOrganizationInfo(),
        ]).timeout(
          const Duration(seconds: 5),
          onTimeout: () async {
            debugPrint('⚠️ Refresh data timeout');
            return [];
          },
        );

        // ✅ OPTIMIZATION: Force refresh status
        await _updateAttendanceStatus(forceRefresh: true).timeout(
          const Duration(seconds: 3),
          onTimeout: () => Future.value(),
        );
        
        await _buildDynamicTimeline().timeout(
          const Duration(seconds: 2),
          onTimeout: () => Future.value(),
        );
      }
    } catch (e) {
      debugPrint('Error refreshing data: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_refresh_data'),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _loadOrganizationData({bool forceRefresh = false}) async {
    if (_organizationMember == null) return;

    try {
      // ✅ OPTIMIZATION: Service sudah handle caching, gunakan parameter forceRefresh
      final data = await _attendanceService.loadDashboardData(
        _organizationMember!.id,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _todayAttendanceRecords = data['today_records'] as List<AttendanceRecord>;
          _recentAttendanceRecords = data['recent_records'] as List<AttendanceRecord>;
        });
      }
    } catch (e) {
      debugPrint('Error loading organization data: $e');
    }
  }

  Future<void> _loadScheduleData() async {
    if (_organizationMember == null || !mounted) return;

    try {
      // ✅ OPTIMIZATION: Service sudah handle caching, tidak perlu cache manual
      _currentSchedule = await _attendanceService.loadCurrentSchedule(
        _organizationMember!.id,
        forceRefresh: false,
      );

      if (!mounted) return;

      // ✅ Check if schedule is null (no cache, no default) - show selection modal
      if (_currentSchedule == null) {
        debugPrint('No schedule found - showing selection modal');
        await _showWorkScheduleSelectionModal(isRequired: true);
        // Reload schedule after selection
        _currentSchedule = await _attendanceService.loadCurrentSchedule(
          _organizationMember!.id,
          forceRefresh: true,
        );
        if (!mounted) return;
      }

      if (_currentSchedule?.workScheduleId != null) {
        final dayOfWeek = TimeHelper.getCurrentDayOfWeek();
        
        // ✅ OPTIMIZATION: Service sudah handle caching
        _todayScheduleDetails = await _attendanceService
            .loadWorkScheduleDetails(
              _currentSchedule!.workScheduleId!,
              dayOfWeek,
            );
        
        if (!mounted) return;
        debugPrint('✓ Schedule details loaded (cached by service)');
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading schedule details: $e');
      // If error and no schedule, show selection modal
      if (_currentSchedule == null && mounted) {
        await _showWorkScheduleSelectionModal(isRequired: true);
      }
    }
  }

  Future<void> _updateAttendanceStatus({bool forceRefresh = false}) async {
    if (_organizationMember == null) return;

    try {
      // ✅ OPTIMIZATION: Service sudah handle caching, pass existing data untuk avoid duplicate query
      final results = await Future.wait([
        _attendanceService.getCurrentAttendanceStatus(
          _organizationMember!.id,
          forceRefresh: forceRefresh,
        ),
        _attendanceService.getAvailableActions(
          _organizationMember!.id,
          existingSchedule: _currentSchedule,
          existingScheduleDetails: _todayScheduleDetails,
        ),
      ]);

      _currentStatus = results[0] as AttendanceStatus;
      _availableActions = results[1] as List<AttendanceAction>;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error updating attendance status: $e');
    }
  }

  Future<List<ScheduleItem>> _getScheduleItemsFromDatabase() async {
    List<ScheduleItem> items = [];

    try {
      if (_todayScheduleDetails != null &&
          _todayScheduleDetails!.isWorkingDay) {
        if (_todayScheduleDetails!.startTime != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.startTime!),
              label: LocalizationHelper.getText('check_in'),
              type: AttendanceActionType.checkIn,
              subtitle: LocalizationHelper.getText('start_work_day'),
            ),
          );
        }

        if (_todayScheduleDetails!.breakStart != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.breakStart!),
              label: LocalizationHelper.getText('break'),
              type: AttendanceActionType.breakOut,
              subtitle: LocalizationHelper.getText('take_a_break'),
            ),
          );
        }

        if (_todayScheduleDetails!.endTime != null) {
          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(_todayScheduleDetails!.endTime!),
              label: LocalizationHelper.getText('check_out'),
              type: AttendanceActionType.checkOut,
              subtitle: LocalizationHelper.getText('end_work_day'),
            ),
          );
        }
      } else if (_currentSchedule?.shiftId != null) {
        items = await _getScheduleItemsFromShift();
      }
    } catch (e) {
      debugPrint('Error getting schedule items: $e');
    }

    return items;
  }

  String _formatTimeFromDatabase(String timeString) {
    try {
      final timeOfDay = TimeHelper.parseTimeString(timeString);
      return TimeHelper.formatTimeOfDay(timeOfDay);
    } catch (e) {
      if (timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          final hour =
              int.tryParse(parts[0])?.toString().padLeft(2, '0') ?? '00';
          final minute =
              int.tryParse(parts[1])?.toString().padLeft(2, '0') ?? '00';
          return '$hour:$minute';
        }
      }
      return timeString;
    }
  }

  Future<List<ScheduleItem>> _getScheduleItemsFromShift() async {
    List<ScheduleItem> items = [];

    try {
      // ✅ OPTIMIZATION: Use shift data from _currentSchedule if available
      Shift? shift = _currentSchedule?.shift;
      
      if (shift == null && _currentSchedule?.shiftId != null) {
        // If shift not loaded, fetch from database
        dynamic shiftIdValue;
        try {
          shiftIdValue = int.parse(_currentSchedule!.shiftId!);
        } catch (e) {
          shiftIdValue = _currentSchedule!.shiftId!;
        }

        final shiftResponse = await Supabase.instance.client
            .from('shifts')
            .select('start_time, end_time, break_duration_minutes')
            .eq('id', shiftIdValue)
            .single();

        if (shiftResponse != null) {
          // Use the shift data to create items
          final startTime = shiftResponse['start_time']?.toString() ?? '';
          final endTime = shiftResponse['end_time']?.toString() ?? '';
          final breakDurationMinutes = shiftResponse['break_duration_minutes'] ?? 0;

          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(startTime),
              label: LocalizationHelper.getText('check_in'),
              type: AttendanceActionType.checkIn,
              subtitle: LocalizationHelper.getText('start_work_day'),
            ),
          );

          if (breakDurationMinutes > 0) {
            final startTimeParsed = TimeHelper.parseTimeString(
              _formatTimeFromDatabase(startTime),
            );
            final endTimeParsed = TimeHelper.parseTimeString(
              _formatTimeFromDatabase(endTime),
            );

            final totalMinutes =
                TimeHelper.timeToMinutes(endTimeParsed) -
                TimeHelper.timeToMinutes(startTimeParsed);
            final breakStartMinutes =
                TimeHelper.timeToMinutes(startTimeParsed) + (totalMinutes ~/ 2);

            items.add(
              ScheduleItem(
                time: TimeHelper.formatTimeOfDay(
                  TimeHelper.minutesToTime(breakStartMinutes),
                ),
                label: LocalizationHelper.getText('break'),
                type: AttendanceActionType.breakOut,
                subtitle: LocalizationHelper.getText('take_a_break'),
              ),
            );
          }

          items.add(
            ScheduleItem(
              time: _formatTimeFromDatabase(endTime),
              label: LocalizationHelper.getText('check_out'),
              type: AttendanceActionType.checkOut,
              subtitle: LocalizationHelper.getText('end_work_day'),
            ),
          );
        }
      } else if (shift != null) {
        // Use shift data from _currentSchedule
        items.add(
          ScheduleItem(
            time: _formatTimeFromDatabase(shift.startTime),
            label: LocalizationHelper.getText('check_in'),
            type: AttendanceActionType.checkIn,
            subtitle: LocalizationHelper.getText('start_work_day'),
          ),
        );

        if (shift.breakDurationMinutes > 0) {
          final startTime = TimeHelper.parseTimeString(
            _formatTimeFromDatabase(shift.startTime),
          );
          final endTime = TimeHelper.parseTimeString(
            _formatTimeFromDatabase(shift.endTime),
          );

          final totalMinutes =
              TimeHelper.timeToMinutes(endTime) -
              TimeHelper.timeToMinutes(startTime);
          final breakStartMinutes =
              TimeHelper.timeToMinutes(startTime) + (totalMinutes ~/ 2);

          items.add(
            ScheduleItem(
              time: TimeHelper.formatTimeOfDay(
                TimeHelper.minutesToTime(breakStartMinutes),
              ),
              label: LocalizationHelper.getText('break'),
              type: AttendanceActionType.breakOut,
              subtitle: LocalizationHelper.getText('take_a_break'),
            ),
          );
        }

        items.add(
          ScheduleItem(
            time: _formatTimeFromDatabase(shift.endTime),
            label: LocalizationHelper.getText('check_out'),
            type: AttendanceActionType.checkOut,
            subtitle: LocalizationHelper.getText('end_work_day'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting schedule from shift: $e');
    }

    return items;
  }

  Future<void> _buildDynamicTimeline() async {
    _timelineItems.clear();

    try {
      final scheduleItems = await _getScheduleItemsFromDatabase();
      if (scheduleItems.isEmpty) {
        if (mounted) setState(() {});
        return;
      }

      final currentTime = TimeHelper.getCurrentTime();

      // Group items by type
      ScheduleItem? checkInItem;
      ScheduleItem? checkOutItem;
      ScheduleItem? breakOutItem;

      for (var item in scheduleItems) {
        switch (item.type) {
          case AttendanceActionType.checkIn:
            checkInItem = item;
            break;
          case AttendanceActionType.checkOut:
            checkOutItem = item;
            break;
          case AttendanceActionType.breakOut:
            breakOutItem = item;
            break;
          case AttendanceActionType.breakIn:
            // Skip, kita gabung dengan breakOut
            break;
        }
      }

      // Add Work Period
      if (checkInItem != null && checkOutItem != null) {
        final checkInTime = TimeHelper.parseTimeString(checkInItem.time);
        final status = _getItemStatus(checkInItem, checkInTime, currentTime);

        _timelineItems.add(
          TimelineItem(
            time: checkInItem.time,
            endTime: checkOutItem.time,
            label: LocalizationHelper.getText('work_time'),
            subtitle: LocalizationHelper.getText('work_period'),
            type: AttendanceActionType.checkIn,
            status: status,
            statusDescription: _getStatusDescription(
              AttendanceActionType.checkIn,
              status,
            ),
          ),
        );
      }

      // ✅ FIX: Add Break Period dengan status detection yang benar
      if (breakOutItem != null) {
        final breakStartTime = TimeHelper.parseTimeString(breakOutItem.time);

        // ✅ Gunakan fungsi _getItemStatus yang sudah diperbaiki
        final status = _getItemStatus(
          breakOutItem,
          breakStartTime,
          currentTime,
        );

        // Hitung break end time
        String breakEndTime = breakOutItem.time;
        if (_todayScheduleDetails?.breakEnd != null) {
          breakEndTime = _formatTimeFromDatabase(
            _todayScheduleDetails!.breakEnd!,
          );
        } else if (_todayScheduleDetails?.breakDurationMinutes != null) {
          final totalMinutes =
              TimeHelper.timeToMinutes(breakStartTime) +
              _todayScheduleDetails!.breakDurationMinutes!;
          breakEndTime = TimeHelper.formatTimeOfDay(
            TimeHelper.minutesToTime(totalMinutes),
          );
        }

        _timelineItems.add(
          TimelineItem(
            time: breakOutItem.time,
            endTime: breakEndTime,
            label: LocalizationHelper.getText('break_time'),
            subtitle: LocalizationHelper.getText('break_period'),
            type: AttendanceActionType.breakOut,
            status: status, // ✅ Status yang sudah benar
            statusDescription: _getStatusDescription(
              AttendanceActionType.breakOut,
              status,
            ),
          ),
        );
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error building timeline: $e');
      if (mounted) setState(() {});
    }
  }

  TimelineStatus _getItemStatus(
    ScheduleItem item,
    TimeOfDay scheduleTime,
    TimeOfDay currentTime,
  ) {
    final currentMinutes = TimeHelper.timeToMinutes(currentTime);
    final scheduleMinutes = TimeHelper.timeToMinutes(scheduleTime);

    // ✅ FIX 1: Check completion berdasarkan logs
    switch (item.type) {
      case AttendanceActionType.checkIn:
        if (_todayAttendanceRecords.isNotEmpty &&
            _todayAttendanceRecords.first.hasCheckedIn) {
          return TimelineStatus.completed;
        }
        break;

      case AttendanceActionType.checkOut:
        if (_todayAttendanceRecords.isNotEmpty &&
            _todayAttendanceRecords.first.hasCheckedOut) {
          return TimelineStatus.completed;
        }
        break;

      case AttendanceActionType.breakOut:
        // ✅ FIX 2: Check break status dari _breakInfo
        if (_breakInfo != null) {
          // Jika sedang break, berarti break_out completed
          if (_breakInfo!['is_currently_on_break'] == true) {
            return TimelineStatus.completed;
          }

          // Jika sudah pernah break (ada break sessions yang complete)
          final breakSessions = _breakInfo!['break_sessions'] as List<dynamic>?;
          if (breakSessions != null && breakSessions.isNotEmpty) {
            final hasCompletedBreak = breakSessions.any(
              (session) => session['end'] != null,
            );
            if (hasCompletedBreak) {
              return TimelineStatus.completed;
            }
          }
        }

        // ✅ FIX 3: Break window detection dengan 1 menit sebelum
        if (currentMinutes >= scheduleMinutes - 1) {
          // Hitung break end time
          int breakEndMinutes = scheduleMinutes + 60; // default 1 jam

          if (_todayScheduleDetails?.breakEnd != null) {
            final breakEndTime = TimeHelper.parseTimeString(
              _formatTimeFromDatabase(_todayScheduleDetails!.breakEnd!),
            );
            breakEndMinutes = TimeHelper.timeToMinutes(breakEndTime);
          } else if (_todayScheduleDetails?.breakDurationMinutes != null) {
            breakEndMinutes =
                scheduleMinutes + _todayScheduleDetails!.breakDurationMinutes!;
          }

          // Active jika dalam rentang break time (1 menit sebelum sampai akhir)
          if (currentMinutes <= breakEndMinutes) {
            return TimelineStatus.active;
          }

          // ✅ Jika sudah lewat break period, return upcoming (akan jadi abu-abu)
          // Note: "upcoming" di sini berarti "passed" atau "missed"
          return TimelineStatus.upcoming;
        }
        break;

      case AttendanceActionType.breakIn:
        if (_breakInfo != null) {
          final breakSessions = _breakInfo!['break_sessions'] as List<dynamic>?;
          if (breakSessions != null && breakSessions.isNotEmpty) {
            final hasCompletedBreak = breakSessions.any(
              (session) => session['end'] != null,
            );
            if (hasCompletedBreak &&
                _breakInfo!['is_currently_on_break'] != true) {
              return TimelineStatus.completed;
            }
          }
        }
        break;
    }

    // ✅ FIX 4: General active window (untuk check-in/out)
    // Active window: 30 menit sebelum sampai 30 menit setelah jadwal
    if (item.type != AttendanceActionType.breakOut) {
      if (currentMinutes >= scheduleMinutes - 30 &&
          currentMinutes <= scheduleMinutes + 30) {
        return TimelineStatus.active;
      }
    }

    // Default: upcoming (belum waktunya atau sudah lewat)
    return TimelineStatus.upcoming;
  }

  String _getStatusDescription(
    AttendanceActionType type,
    TimelineStatus status,
  ) {
    switch (status) {
      case TimelineStatus.completed:
        return LocalizationHelper.getText('completed');
      case TimelineStatus.active:
        return LocalizationHelper.getText('available_now');
      case TimelineStatus.upcoming:
        return LocalizationHelper.getText('not_yet_available');
    }
  }

  int _getPresenceDays() {
    return _recentAttendanceRecords.where((r) => r.status == 'present').length;
  }

  int _getAbsenceDays() {
    return _recentAttendanceRecords.where((r) => r.status == 'absent').length;
  }

  String _getLateness() {
    final totalLateMinutes = _recentAttendanceRecords
        .where((r) => r.lateMinutes != null)
        .map((r) => r.lateMinutes!)
        .fold(0, (sum, minutes) => sum + minutes);
    return TimeHelper.formatDuration(totalLateMinutes);
  }

  String _getCurrentStatusText() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        final hasCheckedInToday = _todayAttendanceRecords.isNotEmpty;
        return hasCheckedInToday
            ? LocalizationHelper.getText('ready_to_check_in_again')
            : LocalizationHelper.getText('ready_to_start');
      case AttendanceStatus.working:
        return LocalizationHelper.getText('currently_working');
      case AttendanceStatus.onBreak:
        return LocalizationHelper.getText('on_break');
      case AttendanceStatus.checkedOut:
        return LocalizationHelper.getText('ready_to_check_in_again');
      case AttendanceStatus.unknown:
        return LocalizationHelper.getText('waiting_for_status');
    }
  }

  Color _getStatusColor() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return warningColor;
      case AttendanceStatus.working:
        return successColor;
      case AttendanceStatus.onBreak:
        return primaryColor;
      case AttendanceStatus.checkedOut:
        return Colors.grey;
      case AttendanceStatus.unknown:
        return errorColor;
    }
  }

  IconData _getStatusIcon() {
    switch (_currentStatus) {
      case AttendanceStatus.notCheckedIn:
        return Icons.schedule;
      case AttendanceStatus.working:
        return Icons.work_outline;
      case AttendanceStatus.onBreak:
        return Icons.coffee_outlined;
      case AttendanceStatus.checkedOut:
        return Icons.check_circle_outline;
      case AttendanceStatus.unknown:
        return Icons.help_outline;
    }
  }

  Future<void> _navigateToBreakPage() async {
    if (_organizationMember == null) {
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('organization_member_not_found'),
        );
      }
      return;
    }

    try {
      int memberId = int.parse(_organizationMember!.id);
      int? deviceId;

      if (_selectedDevice != null) {
        deviceId = int.tryParse(_selectedDevice!.id);
      }

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              BreakPage(organizationMemberId: memberId, deviceId: deviceId),
        ),
      );

      // ✅ FIX: Jika break dihentikan dari BreakPage, clear break info dan refresh data
      if (result == true && mounted) {
        // ✅ Invalidate cache untuk memastikan data fresh
        _attendanceService.invalidateAttendanceCache(_organizationMember!.id);
        
        // ✅ Stop countdown timer karena break sudah selesai
        _breakCountdownTimer?.cancel();
        _breakCountdownTimer = null;
        
        // ✅ Clear break info immediately (break sudah dihentikan dari BreakPage)
        setState(() {
          _breakInfo = null;
          _breakJustStopped = true; // Set flag untuk skip break monitoring sementara
        });
        
        // ✅ Reload data dengan force refresh
        await Future.wait([
          _loadBreakInfo(forceRefresh: true),
          _loadOrganizationData(forceRefresh: true),
          _updateAttendanceStatus(forceRefresh: true),
        ]);
        
        // ✅ Pastikan break info tidak menunjukkan break aktif
        if (mounted && _breakInfo != null && _breakInfo!['is_currently_on_break'] == true) {
          debugPrint('⚠️ Warning: Break info still shows break active after BreakPage. Force clearing...');
          setState(() {
            _breakInfo = null;
          });
        }
      } else if (mounted) {
        // ✅ Reload data jika tidak ada result (user mungkin hanya melihat break page)
        await _refreshData();
      }
    } catch (e) {
      debugPrint('Error navigating to break page: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('failed_to_open_break_page'),
        );
      }
    }
  }

  Future<void> _handleStopBreak() async {
    if (_organizationMember == null || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_breakInfo == null || _breakInfo!['break_start_time'] == null) {
        throw Exception(
          LocalizationHelper.getText('break_start_time_not_found'),
        );
      }

      final now = TimezoneHelper.nowInOrgTime();
      final utcBreakStart = DateTime.parse(_breakInfo!['break_start_time']);
      final breakStartTime = TimezoneHelper.toOrgTime(utcBreakStart);
      final actualBreakDuration = now.difference(breakStartTime);

      if (actualBreakDuration.isNegative) {
        throw Exception(LocalizationHelper.getText('invalid_break_duration'));
      }

      final memberId = int.tryParse(_organizationMember!.id);
      final deviceId = _selectedDevice != null
          ? int.tryParse(_selectedDevice!.id)
          : null;

      if (memberId == null) {
        throw Exception(LocalizationHelper.getText('invalid_member_id'));
      }

      // ✅ FIX: Invalidate cache SEBELUM insert untuk memastikan data fresh
      _attendanceService.invalidateAttendanceCache(_organizationMember!.id);
      
      // ✅ FIX: Insert break_in log
      await Supabase.instance.client.from('attendance_logs').insert({
        'organization_member_id': memberId,
        'event_type': 'break_in',
        'event_time': now.toUtc().toIso8601String(),
        'device_id': deviceId,
        'method': 'mobile_app',
        'is_verified': true,
        'verification_method': 'manual',
      });

      // ✅ FIX: Update break duration (akan invalidate cache lagi untuk memastikan)
      await _attendanceService.updateBreakDuration(
        memberId,
        actualBreakDuration.inMinutes,
      );

      // ✅ FIX: Clear break info IMMEDIATELY - break sudah dihentikan
      // Kita tahu break sudah berhenti karena break_in log sudah di-insert
      // Jangan reload break info dulu karena mungkin masih menggunakan cache/data lama
      if (mounted) {
        // ✅ Stop countdown timer karena break sudah selesai
        _breakCountdownTimer?.cancel();
        _breakCountdownTimer = null;
        
        setState(() {
          _breakInfo = null; // ✅ Clear break info - break indicator akan hilang
          _isLoading = false;
          _breakJustStopped = true; // ✅ Set flag untuk skip break monitoring sementara
        });
      }

      if (mounted) {
        FlushbarHelper.showSuccess(
          context,
          '${LocalizationHelper.getText('break_ended_duration')}: ${_formatDuration(actualBreakDuration)}',
        );
      }

      // ✅ FIX: Reload data lainnya di background (non-blocking)
      // Break info akan di-reload oleh break monitoring timer atau saat diperlukan
      Future.wait([
        _loadBreakInfo(forceRefresh: true), // Reload break info untuk verifikasi (background)
        _loadOrganizationData(forceRefresh: true), // Reload attendance records
        _updateAttendanceStatus(forceRefresh: true), // Update status
      ]).then((_) {
        if (mounted) {
          // ✅ FIX: Pastikan break info tidak menunjukkan break aktif setelah reload
          if (_breakInfo != null && _breakInfo!['is_currently_on_break'] == true) {
            debugPrint('⚠️ Warning: Break info still shows break active after stop. Force clearing...');
            setState(() {
              _breakInfo = null; // Force clear jika masih menunjukkan break aktif
            });
          } else {
            setState(() {}); // Update UI dengan data terbaru
          }
        }
      }).catchError((e) {
        debugPrint('Error reloading data after break stop: $e');
      });
      
      debugPrint('✓ Break stopped successfully. Duration: ${actualBreakDuration.inMinutes} minutes');
      debugPrint('✓ Break info cleared. Break indicator should be hidden now.');
    } catch (e) {
      debugPrint('❌ Error ending break: $e');
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_end_break')}: ${e.toString()}',
        );
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

 Future<void> _performAttendance(String actionType) async {
    if (!mounted) return;

    if (actionType == 'break_out') {
      await _navigateToBreakPage();
      return;
    }

    // ✅ TAMBAHKAN INI - Show map preview untuk office worker
    if (_requiresGpsValidation && actionType == 'check_in') {
      final mapConfirmed = await _showMapPreviewDialog();
      if (mapConfirmed != true) return;
    }

    if (actionType == 'check_out') {
      final confirmed = await _showCheckoutConfirmation();
      if (confirmed != true) return;
    }

    setState(() => _isInitialLoading = true);

    // ✅ Deklarasi positionToUse di luar try block agar bisa diakses dari catch block
    Position? positionToUse;

    try {
      if (_organizationMember == null) {
        if (mounted) {
          FlushbarHelper.showError(
            context,
            LocalizationHelper.getText('configuration_error'),
          );
        }
        return;
      }

      // Check apakah butuh validasi GPS berdasarkan work_location
      final requiresGps = await _attendanceService.requiresGpsValidation(
        _organizationMember!.id,
      );
      final locationDetails = await _attendanceService.getWorkLocationDetails(
        _organizationMember!.id,
      );

      debugPrint('=== Attendance Check ===');
      debugPrint('Work Location: ${locationDetails['location']}');
      debugPrint('Type: ${locationDetails['type']}');
      debugPrint('Requires GPS: $requiresGps');

      if (requiresGps) {
        // OFFICE WORKER - Harus pakai GPS dan dalam radius
        debugPrint(LocalizationHelper.getText('office_worker_mode'));

        if (_selectedDevice == null || !_selectedDevice!.hasValidCoordinates) {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.getText('attendance_location_not_configured'),
            );
          } 
          return;
        }

        final now = DateTime.now();
        final gpsAge = _gpsPosition != null
            ? now.difference(_gpsPosition!.timestamp).inSeconds
            : 999;

        // Update GPS jika belum ada atau sudah lama (>60 detik)
        if (_gpsPosition == null || gpsAge > 60) {
          if (mounted) {
            FlushbarHelper.showInfo(
              context,
              LocalizationHelper.getText('getting_your_location'),
            );
          }
          await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
        }

        // Cek lagi setelah update
        if (_gpsPosition == null) {
          if (mounted) {
            FlushbarHelper.showError(
              context,
              LocalizationHelper.getText('unable_to_get_location_gps'),
            );
          }
          return;
        }

        // ✅ VALIDASI FAKE GPS sebelum validasi radius - SHOW POPUP INSTEAD OF FLUSHBAR
        try {
          // Selalu refresh GPS tepat sebelum validasi fake GPS agar pakai data terbaru
          debugPrint('Refreshing GPS before fake GPS validation...');
          await _updateGpsPositionAndDistance(debounce: false, retryCount: 0);
          if (_gpsPosition == null) {
            debugPrint('GPS position still null after refresh; skipping fake GPS validation');
          }

          debugPrint('Running fake GPS validation on latest position...');
          final isFake = await FakeGpsDetector.isFakeGps(_gpsPosition!);
          if (isFake) {
            final validation = await FakeGpsDetector.validateGpsPosition(_gpsPosition!);
            if (mounted) {
              // ✅ GANTI: Show popup alert di tengah layar
              debugPrint('Showing Fake GPS dialog (validation warnings: ${validation['warnings']})');
              await _showFakeGpsDialog(validation);
            }
            return;
          }
        } catch (e) {
          debugPrint('Error validating fake GPS: $e');
          // Jika error, tetap lanjutkan (jangan block attendance)
        }

        // Validasi radius
        final isWithinRadius = _attendanceService.isWithinRadius(
          _gpsPosition!,
          _selectedDevice!,
        );

        debugPrint(
          'GPS Position: ${_gpsPosition!.latitude}, ${_gpsPosition!.longitude}',
        );
        debugPrint(
          'Device Position: ${_selectedDevice!.latitude}, ${_selectedDevice!.longitude}',
        );
        debugPrint('Distance: ${_distanceToDevice}m');
        debugPrint('Within Radius: $isWithinRadius');

        if (!isWithinRadius) {
          if (mounted) {
            final distance = _formatDistance(_distanceToDevice);
            FlushbarHelper.showError(
              context,
              '${LocalizationHelper.getText('you_are_away_from')} $distance ${_selectedDevice!.deviceName}. ${LocalizationHelper.getText('please_move_closer')}',
            );
          }
          return;
        }

        positionToUse = _gpsPosition;
        debugPrint(
          '✓ GPS validated - ${LocalizationHelper.getText('within_radius')} ${_selectedDevice!.radiusMeters}m',
        );
      } else {
        // FIELD WORKER - Tidak perlu validasi GPS/radius
        debugPrint(LocalizationHelper.getText('field_worker_mode'));

        // Coba ambil GPS untuk logging (opsional), tapi tidak wajib
        try {
          positionToUse = await _attendanceService.getCurrentLocation().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint(
                'GPS timeout for field worker - using fallback position',
              );
              return Position(
                longitude: 0.0,
                latitude: 0.0,
                timestamp: DateTime.now(),
                accuracy: 999.0,
                altitude: 0.0,
                heading: 0.0,
                speed: 0.0,
                speedAccuracy: 0.0,
                altitudeAccuracy: 0.0,
                headingAccuracy: 0.0,
              );
            },
          );
          debugPrint(
            '✓ GPS obtained for field worker: ${positionToUse.latitude}, ${positionToUse.longitude}',
          );
        } catch (e) {
          debugPrint('Could not get GPS for field worker (not required): $e');
          // Gunakan posisi dummy untuk field worker
          positionToUse = Position(
            longitude: 0.0,
            latitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 999.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          debugPrint('✓ Using fallback position for field worker');
        }
      }

      // ✅ PERBAIKAN: Ambil foto berdasarkan configuration
      String? photoUrl;
      if (actionType == 'check_in') {
        // ✅ Cek configuration: allow_selfie (default true jika tidak ada)
        final allowSelfie = _selectedDevice?.configuration?['allow_selfie'] as bool? ?? true;
        
        debugPrint('=== Photo Configuration ===');
        debugPrint('Device: ${_selectedDevice?.deviceName}');
        debugPrint('Allow Selfie: $allowSelfie');
        
        if (allowSelfie) {
          // ✅ Foto WAJIB
          debugPrint('Photo required for check-in');
          
          final imagePath = await _takeSelfie();
          if (imagePath == null) {
            if (mounted) {
              FlushbarHelper.showError(
                context,
                LocalizationHelper.getText('photo_required_check_in'),
              );
            }
            return;
          }

          if (mounted) {
            FlushbarHelper.showInfo(
              context,
              LocalizationHelper.getText('uploading_photo'),
            );
          }

          photoUrl = await _attendanceService.uploadPhoto(imagePath);

          if (photoUrl == null) {
            if (mounted) {
              FlushbarHelper.showError(
                context,
                LocalizationHelper.getText('failed_upload_photo'),
              );
            }
            return;
          }

          File(imagePath).delete().catchError(
            (e) => debugPrint('Failed to delete temp file: $e'),
          );
          debugPrint('✓ Photo uploaded successfully: $photoUrl');
        } else {
          // ✅ Foto OPSIONAL - skip photo taking
          debugPrint('Photo not required - skipping photo capture');
          photoUrl = null; // ✅ Explicit null untuk attendance tanpa foto
        }
      }

      // Simpan attendance record
      debugPrint('Saving attendance: $actionType');
      final success = await _attendanceService.performAttendance(
        type: actionType,
        organizationMemberId: _organizationMember!.id,
        currentPosition: positionToUse!,
        photoUrl: photoUrl ?? '', // ✅ Empty string jika tidak ada foto
        device: requiresGps ? _selectedDevice : null,
        schedule: _currentSchedule,
        todayRecords: _todayAttendanceRecords,
        scheduleDetails: _todayScheduleDetails,
      );

      if (success) {
        debugPrint('✓ Attendance saved successfully');
        if (mounted) await _showSuccessAttendancePopup(actionType);

        // ✅ OPTIMIZATION: Service sudah invalidate cache, refresh data dengan forceRefresh
        // Cache sudah di-invalidate oleh service, jadi kita force refresh untuk mendapatkan data terbaru
        await Future.wait([
          _loadBreakInfo(forceRefresh: true), // ✅ Force refresh break info
          _updateAttendanceStatus(forceRefresh: true), // ✅ Force refresh status
        ]);
        unawaited(_loadOrganizationData(forceRefresh: true)); // ✅ Refresh attendance records di background
        unawaited(_buildDynamicTimeline()); // ✅ Refresh timeline di background
        triggerAttendanceHistoryRefresh();
      }
    } catch (e) {
      debugPrint('❌ Error performing attendance: $e');
      if (mounted) {
        // ✅ Cek apakah error terkait fake GPS (case-insensitive)
        final _err = e.toString();
        final _errL = _err.toLowerCase();
        if (_errL.contains('gps tidak valid') ||
            _errL.contains('fake gps') ||
            _errL.contains('mock location')) {
          // Coba validasi ulang untuk mendapatkan detail warning
          try {
            if (positionToUse != null) {
              final validation = await FakeGpsDetector.validateGpsPosition(positionToUse!);
              await _showFakeGpsDialog(validation);
            } else {
              // Jika tidak ada position, tampilkan popup dengan pesan default
              await _showFakeGpsDialogDefault();
            }
          } catch (validationError) {
            // Jika error validasi, tampilkan popup dengan pesan default
            await _showFakeGpsDialogDefault();
          }
        } else {
          String errorMessage = LocalizationHelper.getText(
            'failed_to_perform_attendance',
          );

          // ✅ Cek apakah error Location terkait fake GPS (case-insensitive)
          final _isLocation = _errL.contains('location');
          if (_isLocation &&
              (_errL.contains('gps tidak valid') ||
               _errL.contains('fake gps') ||
               _errL.contains('mock location'))) {
            // Tampilkan popup fake GPS
            await _showFakeGpsDialogDefault();
          } else if (e.toString().contains('Location')) {
            errorMessage =
                '${LocalizationHelper.getText('location_error')}: ${e.toString()}';
            FlushbarHelper.showError(context, errorMessage);
          } else if (e.toString().contains('schedule')) {
            errorMessage =
                '${LocalizationHelper.getText('schedule_error')}: ${e.toString()}';
            FlushbarHelper.showError(context, errorMessage);
          } else {
            errorMessage = e.toString();
            FlushbarHelper.showError(context, errorMessage);
          }
        }
      }
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  /// Menampilkan popup fake GPS dengan validation data
  Future<void> _showFakeGpsDialog(Map<String, dynamic> validation) async {
    if (!mounted) return;

    final warnings = validation['warnings'] as List<String>;
    String _mapWarningToKey(String w) {
      final lw = w.toLowerCase();
      if (lw.contains('mock location')) return 'warning_mock_location_detected';
      if (lw.contains('akurasi gps tidak valid') || lw.contains('gps invalid')) return 'warning_gps_accuracy_invalid';
      if (lw.contains('akurasi gps rendah') || lw.contains('low accuracy')) return 'warning_gps_low_accuracy';
      if (lw.contains('terlalu sempurna') || lw.contains('too perfect')) return 'warning_too_perfect_no_movement';
      if (lw.contains('timestamp gps tidak sesuai') || lw.contains('timestamp mismatch')) return 'warning_gps_timestamp_mismatch';
      if (lw.contains('data gps sudah lama') || lw.contains('stale')) return 'warning_gps_data_stale';
      if (lw.contains('lokasi tidak mungkin') || lw.contains('impossible location')) return 'warning_impossible_location';
      if (lw.contains('kecepatan tidak realistis') || lw.contains('unrealistic speed')) return 'warning_unrealistic_speed';
      if (lw.contains('tingkat kepercayaan gps rendah') || lw.contains('low confidence')) return 'warning_low_gps_confidence';
      return w; // fallback show as-is
    }
    final localizedWarnings = warnings.map((w) {
      final key = _mapWarningToKey(w);
      return (key == w) ? w : LocalizationHelper.getText(key);
    }).toList();
    final confidence = validation['confidence'] as double;
    final accuracy = validation['accuracy'] as double?;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                // Icon Warning
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off,
                    color: Color(0xFFEF4444),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  LocalizationHelper.getText('fake_gps_detected_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Description
                const SizedBox(height: 24),
                
                // Warning Details
                if (localizedWarnings.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: const Color(0xFFEF4444),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              LocalizationHelper.getText('detection_reasons'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...localizedWarnings.map((warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 6, right: 8),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  warning,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Additional Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0EA5E9).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: const Color(0xFF0EA5E9),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            LocalizationHelper.getText('how_to_fix'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0EA5E9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(LocalizationHelper.getText('fix_step_1')),
                      _buildInstructionItem(LocalizationHelper.getText('fix_step_2')),
                      _buildInstructionItem(LocalizationHelper.getText('fix_step_3')),
                      _buildInstructionItem(LocalizationHelper.getText('fix_step_4')),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // OK Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      LocalizationHelper.getText('ok_understood'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstructionItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF0EA5E9),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Menampilkan popup fake GPS dengan pesan default (ketika tidak ada position untuk validasi)
  Future<void> _showFakeGpsDialogDefault() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                // Icon Warning
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off,
                    color: Color(0xFFEF4444),
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),
                
                // Title
                Text(
                  LocalizationHelper.getText('fake_gps_detected_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                
                const SizedBox(height: 10),
                
                // Warning Details (Default)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWarningItem(LocalizationHelper.getText('warning_mock_location_detected')),
                      _buildWarningItem(LocalizationHelper.getText('warning_fake_gps_app_may_be_active')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                
                // OK Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      LocalizationHelper.getText('ok_understood'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showCheckoutConfirmation() async {
    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.logout, color: warningColor, size: 30),
                ),
                const SizedBox(height: 20),
                Text(
                  LocalizationHelper.getText('confirm_check_out'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  LocalizationHelper.getText('end_work_session'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          LocalizationHelper.getText('cancel'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          LocalizationHelper.getText('yes_check_out'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _takeSelfie() async {
    if (!CameraService.isInitialized) {
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('camera_not_available'),
        );
      }
      return null;
    }

    final hasPermission = await CameraService.requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        FlushbarHelper.showError(
          context,
          LocalizationHelper.getText('camera_permission_required'),
        );
      }
      return null;
    }

    try {
      if (!mounted) return null;
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CameraSelfieScreen(cameras: CameraService.cameras),
        ),
      );
      return result;
    } catch (e) {
      if (mounted) {
        FlushbarHelper.showError(
          context,
          '${LocalizationHelper.getText('failed_to_take_photo')}: $e',
        );
      }
      return null;
    }
  }

  Future<void> _showSuccessAttendancePopup(String type) async {
  if (!mounted) return;

  final orgTime = TimezoneHelper.nowInOrgTime();

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                MediaQuery.of(context).orientation == Orientation.landscape;

            return SingleChildScrollView(
              child: Container(
                width: MediaQuery.of(context).size.width *
                    (isLandscape ? 0.6 : 0.85),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, primaryColor.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        vertical: isLandscape ? 15 : 30,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          // 🎬 LOTTIE ANIMATION (Ganti icon check_circle)
                          Lottie.asset(
                            'assets/lottie/Done.json',
                            width: isLandscape ? 100 : 140,
                            height: isLandscape ? 100 : 140,
                            repeat: false, // Play once only
                            // Fallback jika file tidak ada
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: isLandscape ? 60 : 80,
                                height: isLandscape ? 60 : 80,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.check_circle,
                                  size: isLandscape ? 30 : 40,
                                  color: primaryColor,
                                ),
                              );
                            },
                          ),
                          SizedBox(height: isLandscape ? 12 : 20),
                          Text(
                            LocalizationHelper.getText(
                              'attendance_successful',
                            ),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isLandscape ? 20 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isLandscape ? 4 : 8),
                          Text(
                            _getAttendanceTypeLabel(type),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isLandscape ? 14 : 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: isLandscape ? 4 : 8),
                          Text(
                            TimezoneHelper.formatAttendanceDateTime(orgTime),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isLandscape ? 12 : 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isLandscape ? 15 : 20),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );

  // ⏳ Tutup otomatis setelah 2 detik
  await Future.delayed(const Duration(seconds: 2));
  if (mounted && Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}

  String _getAttendanceTypeLabel(String type) {
    switch (type) {
      case 'check_in':
        return LocalizationHelper.getText('check_in_completed');
      case 'check_out':
        return LocalizationHelper.getText('check_out_completed');
      case 'break_out':
        return LocalizationHelper.getText('break_started');
      case 'break_in':
        return LocalizationHelper.getText('work_resumed');
      default:
        return LocalizationHelper.getText('attendance_recorded');
    }
  }

  String _getDisplayName() {
    final user = Supabase.instance.client.auth.currentUser;

    if (_userProfile?.displayName != null &&
        _userProfile!.displayName!.isNotEmpty) {
      return _userProfile!.displayName!;
    }
    if (_userProfile?.fullName != null && _userProfile!.fullName!.isNotEmpty) {
      return _userProfile!.fullName!;
    }
    if (_userProfile?.firstName != null &&
        _userProfile!.firstName!.isNotEmpty) {
      return _userProfile!.firstName!;
    }
    if (user?.email != null) {
      return user!.email!.split('@')[0];
    }
    return LocalizationHelper.getText('user');
  }

  String _formatDistance(double? distanceInMeters) {
    if (distanceInMeters == null)
      return LocalizationHelper.getText('unknown_distance');
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toInt()} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    if (duration.inHours > 0) {
      return "${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
    }
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Duration _getBreakElapsedTime() {
    if (_breakInfo == null ||
        _breakInfo!['is_currently_on_break'] != true ||
        _breakInfo!['break_start_time'] == null) {
      return Duration.zero;
    }

    try {
      final utcBreakStart = DateTime.parse(_breakInfo!['break_start_time']);
      final breakStartTime = TimezoneHelper.toOrgTime(utcBreakStart);
      final now = TimezoneHelper.nowInOrgTime();
      final elapsed = now.difference(breakStartTime);

      return elapsed.isNegative ? Duration.zero : elapsed;
    } catch (e) {
      debugPrint('Error calculating break elapsed time: $e');
      debugPrint('Break info: $_breakInfo');
      return Duration.zero;
    }
  }

  Widget _buildDeviceInfoChip() {
    if (_selectedDevice == null) {
      return GestureDetector(
        onTap: () => _navigateToDeviceSelection(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _requiresGpsValidation
                ? Colors.orange.withOpacity(0.2) // Orange untuk Office Worker
                : Colors.blue.withOpacity(0.2), // Blue untuk Field Worker
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _requiresGpsValidation ? Icons.warning : Icons.add_location,
                color: _requiresGpsValidation ? Colors.orange : Colors.blue,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _requiresGpsValidation
                    ? LocalizationHelper.getText('no_location')
                    : LocalizationHelper.getText('add_location'),
                style: TextStyle(
                  color: _requiresGpsValidation ? Colors.orange : Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                color: _requiresGpsValidation ? Colors.orange : Colors.blue,
                size: 16,
              ),
            ],
          ),
        ),
      );
    }

    String deviceName = _selectedDevice!.deviceName;
    if (deviceName.contains(" - ")) {
      deviceName = deviceName.split(" - ").last;
    }

    return GestureDetector(
      onTap: () => _navigateToDeviceSelection(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                deviceName.length > 10
                    ? deviceName.substring(0, 10) + '…'
                    : deviceName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakIndicator() {
    if (_breakInfo == null || _breakInfo!['is_currently_on_break'] != true) {
      return const SizedBox.shrink();
    }

    final elapsedTime = _getBreakElapsedTime();
    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _indicatorPosition.dx,
      top: _indicatorPosition.dy,
      child: GestureDetector(
        onPanStart: (details) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          setState(() {
            double newX = _indicatorPosition.dx + details.delta.dx;
            double newY = _indicatorPosition.dy + details.delta.dy;

            newX = newX.clamp(0.0, screenSize.width - 180);
            newY = newY.clamp(50.0, screenSize.height - 200);

            _indicatorPosition = Offset(newX, newY);
          });
        },
        onPanEnd: (details) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 160,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withOpacity(0.9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDragging ? 0.3 : 0.2),
                blurRadius: _isDragging ? 20 : 15,
                offset: Offset(0, _isDragging ? 8 : 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _navigateToBreakPage(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.coffee,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            LocalizationHelper.getText('on_break_indicator'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          _formatDuration(elapsedTime),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _isLoading ? null : () => _handleStopBreak(),
                          child: Center(
                            child: _isLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: primaryColor,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    LocalizationHelper.getText('stop_break'),
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _getDisplayName();

    if (_needsDeviceSelection) {
      return _buildDeviceSelectionRequiredView();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshData,
            color: primaryColor,
            backgroundColor: Colors.white,
            // Disable spinner karena kita pakai skeleton
            displacement: 40,
            strokeWidth: 2.5,
            child: _buildMainContent(displayName),
          ),
          _buildBreakIndicator(),
        ],
      ),
    );
  }

  Widget _buildDeviceSelectionRequiredView() {
    final displayName = _getDisplayName();

    return RefreshIndicator(
      onRefresh: _loadUserData,
      color: primaryColor,
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_organization?.logoUrl != null)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _organization!.logoUrl!,
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                              : null,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('Error loading organization logo: $error');
                                  return Icon(
                                    Icons.business,
                                    color: primaryColor,
                                    size: 20,
                                  );
                                },
                              ),
                            ),
                          )
                        else
                          Icon(Icons.business, color: primaryColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _organization?.name ?? 'Organization',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.orange.shade400,
                          backgroundImage: _userProfile?.profilePhotoUrl != null
                              ? NetworkImage(_userProfile!.profilePhotoUrl!)
                              : null,
                          child: _userProfile?.profilePhotoUrl == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 28,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${LocalizationHelper.getText('hello')}, $displayName",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Text(
                                'Location Setup Required',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
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
                            color: Colors.orange.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on,
                            size: 40,
                            color: Colors.orange.shade400,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Attendance Location Required',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Please select an attendance location to continue using the attendance system.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isInitialLoading
                                ? null
                                : () => _navigateToDeviceSelection(
                                    isRequired: true,
                                  ),
                            icon: _isInitialLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.location_on),
                            label: Text(
                              _isInitialLoading
                                  ? 'Loading...'
                                  : 'Select Location',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

Widget _buildMainContent(String displayName) {
  // ✅ Hanya show skeleton saat initial loading atau refresh
  if (_isInitialLoading || _isRefreshing) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          SkeletonWidgets.buildSkeletonHeader(),
          SkeletonWidgets.buildSkeletonStatusCard(),
          SkeletonWidgets.buildSkeletonTimelineCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ✅ Tampilkan konten lengkap (tanpa loading indicator pojok)
  return SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    child: Column(
      children: [
        _buildHeader(displayName),
        _buildStatusCard(),
        _buildTimelineCard(),
        const SizedBox(height: 24),
      ],
    ),
  );
}

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Reload data jika halaman kembali visible dan data kosong
  if (mounted && 
      !_isInitialLoading && 
      !_isSecondaryDataLoading &&
      _todayAttendanceRecords.isEmpty && 
      _organizationMember != null) {
    debugPrint('Page resumed - reloading secondary data');
    _loadSecondaryDataInBackground();
  }
}
  Widget _buildHeader(String displayName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [backgroundColor, backgroundColor.withOpacity(0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Organization logo...
                    if (_organization?.logoUrl != null)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _organization!.logoUrl!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('Error loading organization logo: $error');
                              return Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.business,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.business,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _organization?.name ?? 'Unknown Organization',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ PERUBAHAN: Tampilkan device chip untuk SEMUA user
              Row(children: [_buildDeviceInfoChip(), const SizedBox(width: 8)]),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.orange.shade400,
                backgroundImage: _userProfile?.profilePhotoUrl != null
                    ? NetworkImage(_userProfile!.profilePhotoUrl!)
                    : null,
                child: _userProfile?.profilePhotoUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 28)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${LocalizationHelper.getText('hello')}, $displayName",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _getCurrentStatusText(),
                      style: TextStyle(
                        color: _getStatusColor(),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final isOnBreak =
        _breakInfo != null && _breakInfo!['is_currently_on_break'] == true;
    final filteredActions = isOnBreak
        ? _availableActions
              .where((action) => action.type != 'break_out')
              .toList()
        : _availableActions;

    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _getStatusColor().withOpacity(0.1),
              _getStatusColor().withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _getStatusColor().withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _getStatusColor().withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _getStatusColor(),
                                _getStatusColor().withOpacity(0.8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _getStatusColor().withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _getStatusIcon(),
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TimezoneHelper.formatOrgTime(
                            TimezoneHelper.nowInOrgTime(),
                            'HH:mm',
                          ),
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isRefreshing)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // ===== DATE ROW =====
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            TimezoneHelper.formatOrgTime(
                              TimezoneHelper.nowInOrgTime(),
                              'EEEE, dd MMMM yyyy',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (!_requiresGpsValidation) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      _isLoadingLocationInfo
                          ? const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                Icon(
                                  Icons.explore,
                                  size: 14,
                                  color: successColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedDevice != null
                                        ? '${LocalizationHelper.getText('field_work_at')} ${_selectedDevice!.deviceName}'
                                        : (_workLocationDetails['city']
                                                      ?.isNotEmpty ==
                                                  true
                                              ? '${LocalizationHelper.getText('field_work_in')} ${_workLocationDetails['city']}'
                                              : LocalizationHelper.getText('field_work_mode')),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: successColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _selectedDevice != null
                                            ? Icons.check_circle
                                            : Icons.location_searching,
                                        size: 12,
                                        color: successColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _selectedDevice != null
                                            ? LocalizationHelper.getText(
                                                'location_set',
                                              )
                                            : LocalizationHelper.getText(
                                                'ready',
                                              ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: successColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ] else if (_requiresGpsValidation &&
                        _selectedDevice != null) ...[
                      // ✅ OFFICE WORKER WITH DEVICE - Validasi GPS & radius
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedDevice!.deviceName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_selectedDevice!.hasValidCoordinates &&
                                      _gpsPosition != null &&
                                      _isWithinRadius != null)
                                  ? (_isWithinRadius!
                                        ? successColor.withOpacity(0.15)
                                        : warningColor.withOpacity(0.15))
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (_selectedDevice!.hasValidCoordinates &&
                                          _gpsPosition != null &&
                                          _isWithinRadius != null)
                                      ? (_isWithinRadius!
                                            ? Icons.check_circle
                                            : Icons.location_off)
                                      : Icons.location_searching,
                                  size: 12,
                                  color:
                                      (_selectedDevice!.hasValidCoordinates &&
                                          _gpsPosition != null &&
                                          _isWithinRadius != null)
                                      ? (_isWithinRadius!
                                            ? successColor
                                            : warningColor)
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (_selectedDevice!.hasValidCoordinates &&
                                          _gpsPosition != null &&
                                          _isWithinRadius != null)
                                      ? (_isWithinRadius!
                                            ? _formatDistance(_distanceToDevice)
                                            : LocalizationHelper.getText(
                                                'out_of_range',
                                              ))
                                      : LocalizationHelper.getText('locating'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        (_selectedDevice!.hasValidCoordinates &&
                                            _gpsPosition != null &&
                                            _isWithinRadius != null)
                                        ? (_isWithinRadius!
                                              ? successColor
                                              : warningColor)
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else if (_requiresGpsValidation &&
                        _selectedDevice == null) ...[
                      // Office worker belum pilih device
                      const SizedBox(height: 8),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.warning,
                            size: 14,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LocalizationHelper.getText(
                                'no_attendance_location_selected',
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _navigateToDeviceSelection(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 12,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    LocalizationHelper.getText(
                                      'select_location',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ===== ACTION BUTTONS =====
                    if (filteredActions.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: filteredActions.take(2).map((action) {
                          bool shouldEnable =
                              action.isEnabled && !_isInitialLoading;

                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: filteredActions.indexOf(action) == 0
                                    ? 8
                                    : 0,
                                left: filteredActions.indexOf(action) == 1
                                    ? 8
                                    : 0,
                              ),
                              child: ElevatedButton(
                                onPressed: shouldEnable
                                    ? () => _performAttendance(action.type)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: shouldEnable
                                      ? primaryColor
                                      : Colors.grey.shade300,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  elevation: shouldEnable ? 4 : 0,
                                  shadowColor: primaryColor.withOpacity(0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isInitialLoading && action.isEnabled
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Text(
                                        action.label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocalizationHelper.getText('todays_schedule'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          if (_timelineItems.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20), // ini masih boleh const
                child: Text(
                  LocalizationHelper.getText('no_schedule_available'),
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _timelineItems.length,
              itemBuilder: (context, index) {
                return _buildTimelineItem(_timelineItems[index], index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(TimelineItem item, int index) {
    // Format waktu dengan rentang jika ada end time
    String displayTime = item.time;
    if (item.endTime != null && item.endTime!.isNotEmpty) {
      displayTime = '${item.time} - ${item.endTime}';
    }

    return Padding(
      padding: EdgeInsets.only(
        top: index == 0 ? 0 : 12,
        bottom: index == _timelineItems.length - 1 ? 0 : 0,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getItemStatusColor(item.status),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getItemIcon(item.type),
              color: item.status == TimelineStatus.active
                  ? Colors.white
                  : item.status == TimelineStatus.completed
                  ? Colors.white
                  : Colors.grey,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getItemStatusColor(item.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    displayTime,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _getItemStatusColor(item.status),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getItemStatusColor(TimelineStatus status) {
    switch (status) {
      case TimelineStatus.completed:
        return successColor;
      case TimelineStatus.active:
        return primaryColor;
      case TimelineStatus.upcoming:
        return Colors.grey.shade400;
    }
  }

  IconData _getItemIcon(AttendanceActionType type) {
    switch (type) {
      case AttendanceActionType.checkIn:
        return Icons.login;
      case AttendanceActionType.checkOut:
        return Icons.logout;
      case AttendanceActionType.breakOut:
        return Icons.coffee;
      case AttendanceActionType.breakIn:
        return Icons.work;
    }
  }
}

void unawaited(Future<void> future) {}

// Update TimelineItem class to include schedule details
class TimelineItem {
  final String time;
  final String label;
  final String subtitle;
  final AttendanceActionType type;
  final TimelineStatus status;
  final String statusDescription;
  final String? endTime;
  final String? breakStart; // NEW
  final String? breakEnd; // NEW

  TimelineItem({
    required this.time,
    required this.label,
    required this.subtitle,
    required this.type,
    required this.status,
    required this.statusDescription,
    this.endTime,
    this.breakStart, // NEW
    this.breakEnd, // NEW
  });
}

class ScheduleItem {
  final String time;
  final String label;
  final AttendanceActionType type;
  final String subtitle;

  ScheduleItem({
    required this.time,
    required this.label,
    required this.type,
    required this.subtitle,
  });
}

class SimpleOrganization {
  final String id;
  final String name;
  final String? logoUrl;

  SimpleOrganization({required this.id, required this.name, this.logoUrl});
}

enum AttendanceActionType { checkIn, checkOut, breakOut, breakIn }

enum TimelineStatus { completed, active, upcoming }