// screens/main_dashboard.dart
import 'package:flutter/material.dart';
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
  
  // Add GlobalKey for accessing UserDashboard and AttendanceHistoryPage
  final GlobalKey<UserDashboardState> _dashboardKey = GlobalKey<UserDashboardState>();
  final GlobalKey<AttendanceHistoryPageState> _historyKey = GlobalKey<AttendanceHistoryPageState>();
  
  // Method to refresh dashboard profile
  void _refreshDashboardProfile() {
    debugPrint('MainDashboard: Profile updated callback received');
    if (_dashboardKey.currentState != null) {
      _dashboardKey.currentState!.refreshUserProfile();
    }
  }
  
  // Method to refresh attendance history
  void _refreshAttendanceHistory() {
    debugPrint('MainDashboard: Refreshing attendance history');
    if (_historyKey.currentState != null) {
      _historyKey.currentState!.refreshData();
    }
  }
  
  // Build pages with keys and callbacks
  List<Widget> get _pages => [
    UserDashboard(key: _dashboardKey),
    AttendanceHistoryPage(
      key: _historyKey,
      onAttendanceUpdated: _refreshAttendanceHistory, // New callback
    ),
    ProfilePage(
      onProfileUpdated: _refreshDashboardProfile, // Add callback
    ),
  ];

  final List<BottomNavigationBarItem> _bottomNavItems = [
    const BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home),
      label: 'Home',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.history_outlined),
      activeIcon: Icon(Icons.history),
      label: 'History',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
                
                // Handle different tab selections
                if (index == 0 && _dashboardKey.currentState != null) {
                  // Refresh profile when returning to Home tab
                  debugPrint('Returning to home tab - refreshing profile');
                  _dashboardKey.currentState!.refreshUserProfile();
                } else if (index == 1) {
                  // Refresh attendance history when History tab is selected
                  debugPrint('History tab selected - refreshing attendance history');
                  _refreshAttendanceHistory();
                }
              },
              selectedItemColor: primaryColor,
              unselectedItemColor: Colors.grey.shade400,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              iconSize: 24,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
              items: _bottomNavItems,
            ),
          ),
        ),
      ),
    );
  }
}