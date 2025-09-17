import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class TimezoneHelper {
  static late tz.Location jakartaTimeZone;
  
  static void initialize() {
    tz.initializeTimeZones();
    jakartaTimeZone = tz.getLocation('Asia/Jakarta');
  }
  
  static DateTime nowInJakarta() {
    return tz.TZDateTime.now(jakartaTimeZone);
  }
  
  static DateTime toJakartaTime(DateTime dateTime) {
    return tz.TZDateTime.from(dateTime, jakartaTimeZone);
  }
  
  static String formatJakartaTime(DateTime dateTime, String pattern) {
    final jakartaTime = tz.TZDateTime.from(dateTime, jakartaTimeZone);
    return DateFormat(pattern, 'id_ID').format(jakartaTime);
  }
  
  // Additional helper methods
  static String getTodayDateString() {
    final today = nowInJakarta();
    return DateFormat('yyyy-MM-dd').format(today);
  }
  
  static String getCurrentTimeString() {
    final now = nowInJakarta();
    return DateFormat('HH:mm:ss').format(now);
  }
  
  static String formatAttendanceDateTime(DateTime dateTime) {
    final jakartaTime = tz.TZDateTime.from(dateTime, jakartaTimeZone);
    return DateFormat('dd MMM yyyy, HH:mm WIB', 'id_ID').format(jakartaTime);
  }
}