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
      final cleanTime = timeString.trim();
      final parts = cleanTime.split(':');
      if (parts.length < 2) {
        throw FormatException('Invalid time format: $timeString');
      }
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23) {
        throw RangeError('Hour must be between 0 and 23, got: $hour');
      }
      if (minute < 0 || minute > 59) {
        throw RangeError('Minute must be between 0 and 59, got: $minute');
      }
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      print('Error parsing time string "$timeString": $e');
      // Return current org time as fallback
      return getCurrentTime();
    }
  }

  static int timeToMinutes(TimeOfDay time) {
    return time.hour * 60 + time.minute;
  }

  static TimeOfDay minutesToTime(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  static bool isWithinTimeWindow(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = timeToMinutes(current);
    final startMinutes = timeToMinutes(start);
    final endMinutes = timeToMinutes(end);

    if (endMinutes < startMinutes) {
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    } else {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    }
  }

  static int calculateTimeDifference(TimeOfDay start, TimeOfDay end) {
    final startMinutes = timeToMinutes(start);
    final endMinutes = timeToMinutes(end);
    if (endMinutes >= startMinutes) {
      return endMinutes - startMinutes;
    } else {
      return (24 * 60) - startMinutes + endMinutes;
    }
  }

  static bool isTimeBefore(TimeOfDay time1, TimeOfDay time2) {
    return timeToMinutes(time1) < timeToMinutes(time2);
  }

  static bool isTimeAfter(TimeOfDay time1, TimeOfDay time2) {
    return timeToMinutes(time1) > timeToMinutes(time2);
  }

  static TimeOfDay addMinutes(TimeOfDay time, int minutes) {
    final totalMinutes = timeToMinutes(time) + minutes;
    return minutesToTime(totalMinutes);
  }

  static TimeOfDay subtractMinutes(TimeOfDay time, int minutes) {
    final totalMinutes = timeToMinutes(time) - minutes;
    return minutesToTime(totalMinutes < 0 ? totalMinutes + (24 * 60) : totalMinutes);
  }

  /// Get current time as TimeOfDay (organization timezone)
  static TimeOfDay getCurrentTime() {
    final now = TimezoneHelper.nowInOrgTime();
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }

  static bool isValidTimeFormat(String? timeString) {
    if (timeString == null || timeString.isEmpty) return false;
    try {
      parseTimeString(timeString);
      return true;
    } catch (e) {
      return false;
    }
  }

  static String formatTimeWithTimezone(String? timeString, {String? timezone}) {
    if (timeString == null || timeString.isEmpty) return 'Not set';
    try {
      final time = parseTimeString(timeString);
      final tzName = timezone ?? TimezoneHelper.currentTimeZone.name;
      return '${formatTimeOfDay(time)} $tzName';
    } catch (e) {
      return 'Invalid time';
    }
  }

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

  static String formatTimeWithOrgTimezone(String? dbTime) {
    return formatTimeWithTimezone(dbTime, timezone: TimezoneHelper.currentTimeZone.name);
  }

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

  static int getCurrentDayOfWeek() {
    final now = TimezoneHelper.nowInOrgTime();
    return now.weekday % 7;
  }

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

  // ✅ NEW: Check if current time is within work hours
  static bool isWithinWorkHours(String? startTime, String? endTime, {int graceMinutes = 30}) {
    if (startTime == null || endTime == null) return true; // Allow if no schedule
    if (!isValidTimeFormat(startTime) || !isValidTimeFormat(endTime)) return true;
    
    try {
      final current = getCurrentTime();
      final workStart = parseTimeString(startTime);
      final workEnd = parseTimeString(endTime);
      
      // Allow check-in starting from graceMinutes before work starts
      final allowedStartTime = subtractMinutes(workStart, graceMinutes);
      
      // Allow check-out until graceMinutes after work ends
      final allowedEndTime = addMinutes(workEnd, graceMinutes);
      
      return isWithinTimeWindow(current, allowedStartTime, allowedEndTime);
    } catch (e) {
      print('Error checking work hours: $e');
      return true; // Allow if error occurs
    }
  }

  // ✅ NEW: Check if current time is past work end time
  static bool isAfterWorkHours(String? endTime, {int graceMinutes = 30}) {
    if (endTime == null || !isValidTimeFormat(endTime)) return false;
    
    try {
      final current = getCurrentTime();
      final workEnd = parseTimeString(endTime);
      final allowedEndTime = addMinutes(workEnd, graceMinutes);
      
      return isTimeAfter(current, allowedEndTime);
    } catch (e) {
      print('Error checking if after work hours: $e');
      return false;
    }
  }

  // ✅ NEW: Check if current time is before work start time
  static bool isBeforeWorkHours(String? startTime, {int graceMinutes = 30}) {
    if (startTime == null || !isValidTimeFormat(startTime)) return false;
    
    try {
      final current = getCurrentTime();
      final workStart = parseTimeString(startTime);
      final allowedStartTime = subtractMinutes(workStart, graceMinutes);
      
      return isTimeBefore(current, allowedStartTime);
    } catch (e) {
      print('Error checking if before work hours: $e');
      return false;
    }
  }

  // ✅ NEW: Get remaining work time in minutes
  static int getRemainingWorkMinutes(String? endTime) {
    if (endTime == null || !isValidTimeFormat(endTime)) return 0;
    
    try {
      final current = getCurrentTime();
      final workEnd = parseTimeString(endTime);
      
      if (isTimeAfter(current, workEnd)) return 0;
      
      return calculateTimeDifference(current, workEnd);
    } catch (e) {
      print('Error calculating remaining work time: $e');
      return 0;
    }
  }
}