import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class TimezoneHelper {
  static late tz.Location currentTimeZone;

  static void initialize(String timezone) {
    tz.initializeTimeZones();
    currentTimeZone = tz.getLocation(timezone);
  }

  static DateTime nowInOrgTime() {
    return tz.TZDateTime.now(currentTimeZone);
  }

  static DateTime toOrgTime(DateTime dateTime) {
    return tz.TZDateTime.from(dateTime, currentTimeZone);
  }

  static String formatOrgTime(DateTime dateTime, String pattern) {
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    return DateFormat(pattern, 'id_ID').format(orgTime);
  }

  static String getTodayDateString() {
    final today = nowInOrgTime();
    return DateFormat('yyyy-MM-dd').format(today);
  }

  static String getCurrentTimeString() {
    final now = nowInOrgTime();
    return DateFormat('HH:mm:ss').format(now);
  }

  static String formatAttendanceDateTime(DateTime dateTime) {
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(orgTime) + ' ${currentTimeZone.name}';
  }
}