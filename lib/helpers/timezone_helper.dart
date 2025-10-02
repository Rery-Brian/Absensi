import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class TimezoneHelper {
  static late tz.Location currentTimeZone;
  static bool _isInitialized = false;

  // Getter untuk cek apakah sudah diinisialisasi
  static bool get isInitialized => _isInitialized;

  static void initialize(String timezone) {
    try {
      tz.initializeTimeZones();
      currentTimeZone = tz.getLocation(timezone);
      _isInitialized = true;
    } catch (e) {
      // Fallback ke UTC jika timezone tidak valid
      tz.initializeTimeZones();
      currentTimeZone = tz.UTC;
      _isInitialized = true;
      print('Warning: Invalid timezone "$timezone", using UTC instead. Error: $e');
    }
  }

  static DateTime nowInOrgTime() {
    if (!_isInitialized) {
      initialize('UTC');
    }
    return tz.TZDateTime.now(currentTimeZone);
  }

  static DateTime toOrgTime(DateTime dateTime) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    return tz.TZDateTime.from(dateTime, currentTimeZone);
  }

  static String formatOrgTime(DateTime dateTime, String pattern) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    return DateFormat(pattern, 'id_ID').format(orgTime);
  }

  static String getTodayDateString() {
    if (!_isInitialized) {
      initialize('UTC');
    }
    final today = nowInOrgTime();
    return DateFormat('yyyy-MM-dd').format(today);
  }

  static String getCurrentTimeString() {
    if (!_isInitialized) {
      initialize('UTC');
    }
    final now = nowInOrgTime();
    return DateFormat('HH:mm:ss').format(now);
  }

  static String formatAttendanceDateTime(DateTime dateTime) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(orgTime) + ' ${currentTimeZone.name}';
  }
}