import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'localization_helper.dart';

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

  /// Format datetime dengan pattern dan locale sesuai bahasa user
  static String formatOrgTime(DateTime dateTime, String pattern) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    
    // Dapatkan locale berdasarkan bahasa yang dipilih user
    final locale = LocalizationHelper.currentLanguage == 'id' ? 'id_ID' : 'en_US';
    
    return DateFormat(pattern, locale).format(orgTime);
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

  /// Format attendance datetime dengan locale sesuai bahasa user
  static String formatAttendanceDateTime(DateTime dateTime) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    
    // Dapatkan locale berdasarkan bahasa yang dipilih user
    final locale = LocalizationHelper.currentLanguage == 'id' ? 'id_ID' : 'en_US';
    
    return DateFormat('dd MMM yyyy, HH:mm', locale).format(orgTime) + ' ${currentTimeZone.name}';
  }
  
  /// Format custom dengan locale awareness
  static String formatWithLocale(DateTime dateTime, String pattern) {
    if (!_isInitialized) {
      initialize('UTC');
    }
    
    final orgTime = tz.TZDateTime.from(dateTime, currentTimeZone);
    final locale = LocalizationHelper.currentLanguage == 'id' ? 'id_ID' : 'en_US';
    
    return DateFormat(pattern, locale).format(orgTime);
  }
}