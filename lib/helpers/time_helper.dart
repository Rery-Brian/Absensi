// helpers/time_helper.dart
import 'package:flutter/material.dart';
import 'timezone_helper.dart';

class TimeHelper {
  /// Parse time string from database to TimeOfDay
  /// Handles formats: "HH:mm", "HH:mm:ss", "HH:mm:ss.SSS"
  static TimeOfDay parseTimeString(String? timeString) {
    if (timeString == null || timeString.isEmpty) {
      throw ArgumentError('Time string cannot be null or empty');
    }

    try {
      // Remove any extra whitespace
      final cleanTime = timeString.trim();
      
      // Split by colon and take only hour and minute
      final parts = cleanTime.split(':');
      
      if (parts.length < 2) {
        throw FormatException('Invalid time format: $timeString');
      }

      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      // Validate hour and minute ranges
      if (hour < 0 || hour > 23) {
        throw RangeError('Hour must be between 0 and 23, got: $hour');
      }
      
      if (minute < 0 || minute > 59) {
        throw RangeError('Minute must be between 0 and 59, got: $minute');
      }

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print('Error parsing time string "$timeString": $e');
      // Return current Jakarta time as fallback
      return getCurrentTime();
    }
  }

  /// Convert TimeOfDay to minutes since midnight
  static int timeToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  /// Convert minutes since midnight to TimeOfDay
  static TimeOfDay minutesToTime(int minutes) {
    final hour = (minutes ~/ 60) % 24; // Handle overflow
    final minute = minutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Format TimeOfDay to string in HH:mm format
  static String formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Check if current time is within time window
  static bool isWithinTimeWindow(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = timeToMinutes(current);
    final startMinutes = timeToMinutes(start);
    final endMinutes = timeToMinutes(end);

    // Handle overnight shifts
    if (endMinutes < startMinutes) {
      // Overnight: check if current is after start OR before end
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    } else {
      // Normal shift: check if current is between start and end
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
  }

  /// Calculate difference between two times in minutes
  static int calculateTimeDifference(TimeOfDay start, TimeOfDay end) {
    final startMinutes = timeToMinutes(start);
    final endMinutes = timeToMinutes(end);
    
    if (endMinutes >= startMinutes) {
      return endMinutes - startMinutes;
    } else {
      // Handle overnight difference
      return (24 * 60) - startMinutes + endMinutes;
    }
  }

  /// Check if time is before another time (considering same day)
  static bool isTimeBefore(TimeOfDay time1, TimeOfDay time2) {
    return timeToMinutes(time1) < timeToMinutes(time2);
  }

  /// Check if time is after another time (considering same day)
  static bool isTimeAfter(TimeOfDay time1, TimeOfDay time2) {
    return timeToMinutes(time1) > timeToMinutes(time2);
  }

  /// Add minutes to a TimeOfDay
  static TimeOfDay addMinutes(TimeOfDay time, int minutes) {
    final totalMinutes = timeToMinutes(time) + minutes;
    return minutesToTime(totalMinutes);
  }

  /// Subtract minutes from a TimeOfDay
  static TimeOfDay subtractMinutes(TimeOfDay time, int minutes) {
    final totalMinutes = timeToMinutes(time) - minutes;
    return minutesToTime(totalMinutes < 0 ? totalMinutes + (24 * 60) : totalMinutes);
  }

  /// Get current time as TimeOfDay (Jakarta timezone)
  static TimeOfDay getCurrentTime() {
    final now = TimezoneHelper.nowInJakarta();
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }

  /// Validate time format
  static bool isValidTimeFormat(String? timeString) {
    if (timeString == null || timeString.isEmpty) return false;
    
    try {
      parseTimeString(timeString);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get time with timezone consideration (for display purposes)
  static String formatTimeWithTimezone(String? timeString, {String timezone = 'WIB'}) {
    if (timeString == null || timeString.isEmpty) return 'Not set';
    
    try {
      final time = parseTimeString(timeString);
      return '${formatTimeOfDay(time)} $timezone';
    } catch (e) {
      return 'Invalid time';
    }
  }

  /// Parse database TIME field and return formatted string
  static String formatDatabaseTime(String? dbTime) {
    if (dbTime == null || dbTime.isEmpty) return 'Not set';
    
    try {
      final time = parseTimeString(dbTime);
      return formatTimeOfDay(time);
    } catch (e) {
      print('Error formatting database time "$dbTime": $e');
      return 'Invalid time';
    }
  }

  /// Format time for display with WIB timezone
  static String formatTimeWithWIB(String? dbTime) {
    return formatTimeWithTimezone(dbTime, timezone: 'WIB');
  }

  /// Compare current Jakarta time with schedule time
  static bool isCurrentTimeAfterSchedule(String? scheduleTime, {int bufferMinutes = 0}) {
    if (scheduleTime == null || !isValidTimeFormat(scheduleTime)) return false;
    
    try {
      final current = getCurrentTime();
      final scheduled = parseTimeString(scheduleTime);
      final scheduledWithBuffer = addMinutes(scheduled, bufferMinutes);
      
      return isTimeAfter(current, scheduledWithBuffer);
    } catch (e) {
      print('Error comparing times: $e');
      return false;
    }
  }

  /// Check if current time is within attendance window
  static bool isWithinAttendanceWindow(String? scheduleTime, {int beforeMinutes = 15, int afterMinutes = 15}) {
    if (scheduleTime == null || !isValidTimeFormat(scheduleTime)) return false;
    
    try {
      final current = getCurrentTime();
      final scheduled = parseTimeString(scheduleTime);
      final windowStart = subtractMinutes(scheduled, beforeMinutes);
      final windowEnd = addMinutes(scheduled, afterMinutes);
      
      return isWithinTimeWindow(current, windowStart, windowEnd);
    } catch (e) {
      print('Error checking attendance window: $e');
      return false;
    }
  }

  /// Calculate late minutes based on current Jakarta time
  static int calculateCurrentLateness(String? scheduledTime) {
    if (scheduledTime == null || !isValidTimeFormat(scheduledTime)) return 0;
    
    try {
      final current = getCurrentTime();
      final scheduled = parseTimeString(scheduledTime);
      
      if (isTimeBefore(current, scheduled)) return 0;
      return calculateTimeDifference(scheduled, current);
    } catch (e) {
      print('Error calculating lateness: $e');
      return 0;
    }
  }

  /// Get day of week for work schedule (0 = Sunday, 1 = Monday, etc.)
  static int getCurrentDayOfWeek() {
    final now = TimezoneHelper.nowInJakarta();
    return now.weekday % 7; // Convert DateTime.weekday (1-7) to (0-6)
  }

  /// Format duration in minutes to human readable format
  static String formatDuration(int minutes) {
    if (minutes <= 0) return '0m';
    
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    
    if (hours == 0) {
      return '${remainingMinutes}m';
    } else if (remainingMinutes == 0) {
      return '${hours}h';
    } else {
      return '${hours}h ${remainingMinutes}m';
    }
  }
}