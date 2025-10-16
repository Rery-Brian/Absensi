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

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _verifyOrganizationMembership();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  void _onBottomNavTap(int index) async {
    if (_isAnimating || index == _currentIndex) return;
    
    HapticFeedback.selectionClick();
    
    setState(() {
      _isAnimating = true;
    });
    
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    if (mounted) {
      setState(() {
        _currentIndex = index;
        _isAnimating = false;
      });
    }
  }

  void _refreshDashboardProfile() {
    debugPrint('MainDashboard: Refreshing dashboard profile');
    _dashboardKey.currentState?.refreshUserProfile();
  }

  void _refreshAttendance() {
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

    final pages = [
      _buildSafeContent(
        UserDashboard(key: _dashboardKey),
        bottomNavHeight,
        bottomPadding,
      ),
      _buildSafeContent(
        AttendancePage(
          key: _attendanceKey,
          onAttendanceUpdated: _refreshAttendance,
        ),
        bottomNavHeight,
        bottomPadding,
      ),
      _buildSafeContent(
        ProfilePage(onProfileUpdated: _refreshDashboardProfile),
        bottomNavHeight,
        bottomPadding,
      ),
    ];

    final icons = [
      Icons.home_outlined,
      Icons.event_note_outlined,
      Icons.person_outline,
    ];

    final labels = [
      LocalizationHelper.getText('home'),
      LocalizationHelper.getText('attendance'),
      LocalizationHelper.getText('profile'),
    ];

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          if (!_isAnimating) {
            setState(() => _currentIndex = index);
          }
          
          if (index == 0) {
            _dashboardKey.currentState?.refreshUserProfile();
          }
          if (index == 1) {
            _refreshAttendance();
          }
        },
        children: pages,
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