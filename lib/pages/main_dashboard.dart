import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard.dart';
import 'attendance_history.dart';
import 'profile.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _currentIndex = 0;

  static const Color primaryColor = Color(0xFF6366F1);
  static const Color accentColor = Color(0xFF22D3EE);

  final GlobalKey<UserDashboardState> _dashboardKey =
      GlobalKey<UserDashboardState>();
  final GlobalKey<AttendanceHistoryPageState> _historyKey =
      GlobalKey<AttendanceHistoryPageState>();

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  void _refreshDashboardProfile() {
    _dashboardKey.currentState?.refreshUserProfile();
  }

  void _refreshAttendanceHistory() {
    _historyKey.currentState?.refreshData();
  }

  List<Widget> get _pages => [
        UserDashboard(key: _dashboardKey),
        AttendanceHistoryPage(
          key: _historyKey,
          onAttendanceUpdated: _refreshAttendanceHistory,
        ),
        ProfilePage(onProfileUpdated: _refreshDashboardProfile),
      ];

  final List<IconData> _icons = [
    Icons.home_outlined,
    Icons.history_outlined,
    Icons.person_outline,
  ];

  final List<String> _labels = ["Home", "History", "Profile"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) _dashboardKey.currentState?.refreshUserProfile();
          if (index == 1) _refreshAttendanceHistory();
        },
        children: _pages,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_icons.length, (index) {
              final isActive = _currentIndex == index;

              return GestureDetector(
                behavior: HitTestBehavior.translucent, // area tap lebih luas
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = index);
                  _pageController.jumpToPage(index);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                          _icons[index],
                          size: isActive ? 26 : 24,
                          color:
                              isActive ? Colors.white : Colors.grey.shade600,
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Text(
                            _labels[index],
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
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}