import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard.dart';
import 'attendance_history.dart';
import 'performance_attendance.dart';
import 'profile.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;
  bool _isAnimating = false; // 👈 buat nahan event ganda saat animasi

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color accentColor = Color(0xFF22D3EE);

  final GlobalKey<UserDashboardState> _dashboardKey =
      GlobalKey<UserDashboardState>();
  final GlobalKey<AttendanceHistoryPageState> _historyKey =
      GlobalKey<AttendanceHistoryPageState>();

  late final PageController _pageController = PageController();

  void _onBottomNavTap(int index) async {
    if (_isAnimating || index == _currentIndex) return; // 👈 cegah spam/duplikat
    HapticFeedback.selectionClick();
    setState(() {
      _isAnimating = true;
    });
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentIndex = index;
      _isAnimating = false;
    });
  }

  void _refreshDashboardProfile() {
    _dashboardKey.currentState?.refreshUserProfile();
  }

  void _refreshAttendanceHistory() {
    _historyKey.currentState?.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final bottomNavHeight = 70.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final pages = [
      _buildSafeContent(UserDashboard(key: _dashboardKey), bottomNavHeight, bottomPadding),
      _buildSafeContent(
        AttendanceHistoryPage(
          key: _historyKey,
          onAttendanceUpdated: _refreshAttendanceHistory,
        ),
        bottomNavHeight,
        bottomPadding,
      ),
      _buildSafeContent(const AttendancePerformancePage(), bottomNavHeight, bottomPadding),
      _buildSafeContent(
        ProfilePage(onProfileUpdated: _refreshDashboardProfile),
        bottomNavHeight,
        bottomPadding,
      ),
    ];

    final icons = [
      Icons.home_outlined,
      Icons.history_outlined,
      Icons.trending_up_outlined,
      Icons.person_outline,
    ];

    final labels = ["Home", "History", "Performance", "Profile"];

    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // 👈 user gak bisa geser manual
        onPageChanged: (index) {
          if (!_isAnimating) {
            setState(() => _currentIndex = index);
          }
          if (index == 0) _dashboardKey.currentState?.refreshUserProfile();
          if (index == 1) _refreshAttendanceHistory();
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
