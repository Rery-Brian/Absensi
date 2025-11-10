import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard.dart';
import 'attendance_page.dart';
import 'profile.dart';
import 'join_organization_screen.dart';
import 'login.dart';
import '../helpers/localization_helper.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;
  bool _isAnimating = false;
  bool _isCheckingOrg = true;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color accentColor = Color(0xFF22D3EE);

  final GlobalKey<UserDashboardState> _dashboardKey =
      GlobalKey<UserDashboardState>();
  final GlobalKey<AttendancePageState> _attendanceKey =
      GlobalKey<AttendancePageState>();

  // ✅ OPTIMIZATION: Track which pages have been initialized (lazy loading)
  final Set<int> _initializedPages = {0}; // Dashboard sudah initialized di awal
  
  // ✅ OPTIMIZATION: Debounce refresh calls
  DateTime? _lastRefreshTime;
  static const Duration _refreshDebounceTime = Duration(seconds: 3); // ✅ Increase debounce time

  @override
  void initState() {
    super.initState();
    _verifyOrganizationMembership();
  }

  Future<void> _verifyOrganizationMembership() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      
      if (user == null) {
        debugPrint('MainDashboard: No authenticated user - redirecting to login');
        if (mounted) {
          _redirectToLogin();
        }
        return;
      }

      debugPrint('MainDashboard: Checking organization for user: ${user.id}');

      final orgMember = await Supabase.instance.client
          .from('organization_members')
          .select('id, organization_id, is_active')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      if (!mounted) return;

      if (orgMember == null) {
        debugPrint('MainDashboard: No organization found - redirecting to join screen');
        
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const JoinOrganizationScreen(),
          ),
        );
        return;
      }

      debugPrint('MainDashboard: Organization found (ID: ${orgMember['organization_id']}) - continuing');
      
      setState(() => _isCheckingOrg = false);
      
    } catch (e) {
      debugPrint('MainDashboard: Error verifying organization: $e');
      
      if (mounted) {
        setState(() => _isCheckingOrg = false);
      }
    }
  }

  void _redirectToLogin() {
    if (!mounted) return;
    
    debugPrint('MainDashboard: Redirecting to login');
    
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const Login()),
      (route) => false,
    );
  }

  void _onBottomNavTap(int index) {
    if (index == _currentIndex) return; // ✅ Skip jika sudah di halaman yang sama
    
    HapticFeedback.selectionClick();
    
    // ✅ OPTIMIZATION: Direct navigation tanpa animasi (lebih cepat)
    setState(() {
      _currentIndex = index;
      _initializedPages.add(index); // ✅ Mark page as initialized
    });
    
    // ✅ OPTIMIZATION: Lazy initialize page data only when first accessed (delay untuk smooth transition)
    if (!_initializedPages.contains(index) || _initializedPages.length == 1) {
      Future.microtask(() => _lazyInitializePage(index));
    }
  }
  
  // ✅ OPTIMIZATION: Lazy initialize page data
  void _lazyInitializePage(int index) {
    // Initialize page-specific data only when first accessed
    switch (index) {
      case 0:
        // Dashboard - already loaded in initState, no need to refresh
        break;
      case 1:
        // Attendance - refresh only if not initialized (delay untuk performa)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _currentIndex == 1) {
            _attendanceKey.currentState?.refreshData();
          }
        });
        break;
      case 2:
        // Profile - no initialization needed
        break;
    }
  }

  void _refreshDashboardProfile() {
    // ✅ OPTIMIZATION: Debounce refresh calls
    final now = DateTime.now();
    if (_lastRefreshTime != null && 
        now.difference(_lastRefreshTime!) < _refreshDebounceTime) {
      debugPrint('MainDashboard: Refresh debounced');
      return;
    }
    _lastRefreshTime = now;
    
    debugPrint('MainDashboard: Refreshing dashboard profile');
    _dashboardKey.currentState?.refreshUserProfile();
  }

  void _refreshAttendance() {
    // ✅ OPTIMIZATION: Debounce refresh calls
    final now = DateTime.now();
    if (_lastRefreshTime != null && 
        now.difference(_lastRefreshTime!) < _refreshDebounceTime) {
      debugPrint('MainDashboard: Refresh debounced');
      return;
    }
    _lastRefreshTime = now;
    
    debugPrint('MainDashboard: Refreshing attendance');
    _attendanceKey.currentState?.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingOrg) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              Text(
                LocalizationHelper.getText('verifying_organization'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bottomNavHeight = 70.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // ✅ OPTIMIZATION: Lazy build pages - hanya build yang visible atau sudah pernah diakses
    final pages = List<Widget?>.generate(3, (index) {
      // Build page jika: current page atau sudah pernah diakses
      if (index == _currentIndex || _initializedPages.contains(index)) {
        switch (index) {
          case 0:
            return _buildSafeContent(
              UserDashboard(key: _dashboardKey),
              bottomNavHeight,
              bottomPadding,
            );
          case 1:
            return _buildSafeContent(
              AttendancePage(
                key: _attendanceKey,
                onAttendanceUpdated: _refreshAttendance,
              ),
              bottomNavHeight,
              bottomPadding,
            );
          case 2:
            return _buildSafeContent(
              ProfilePage(onProfileUpdated: _refreshDashboardProfile),
              bottomNavHeight,
              bottomPadding,
            );
          default:
            return null;
        }
      }
      return null; // Placeholder untuk halaman yang belum di-load
    });

    final icons = [
      Icons.home_outlined,
      Icons.event_note_outlined,
      Icons.person_outline,
    ];

    final labels = [
      LocalizationHelper.getText('home'),
      LocalizationHelper.getText('report'),
      LocalizationHelper.getText('profile'),
    ];

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false, // ✅ OPTIMIZATION: Disable resize untuk performa
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // ✅ OPTIMIZATION: Build pages on-demand, gunakan SizedBox.shrink untuk placeholder
          pages[0] ?? const SizedBox.shrink(),
          pages[1] ?? const SizedBox.shrink(),
          pages[2] ?? const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(icons.length, (index) {
              final isActive = _currentIndex == index;

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _onBottomNavTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 20 : 14,
                    vertical: 10,
                  ),
                  decoration: isActive
                      ? BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [primaryColor, accentColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        )
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        icons[index],
                        size: isActive ? 26 : 24,
                        color: isActive
                            ? Colors.white
                            : Colors.grey.shade600,
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 6),
                        Text(
                          labels[index],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSafeContent(Widget child, double bottomNavHeight, double bottomPadding) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomNavHeight + bottomPadding),
        child: child,
      ),
    );
  }
}