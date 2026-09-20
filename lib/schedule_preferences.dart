import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchedulePreferences {
  static const String _wakeKey = "personal_schedule_wake";
  static const String _breakfastKey = "personal_schedule_breakfast";
  static const String _lunchKey = "personal_schedule_lunch";
  static const String _dinnerKey = "personal_schedule_dinner";
  static const String _bedtimeKey = "personal_schedule_bedtime";
  static const String _beforeMealKey = "personal_schedule_before_meal";
  static const String _afterMealKey = "personal_schedule_after_meal";

  static TimeOfDay wakeTime = const TimeOfDay(hour: 7, minute: 0);
  static TimeOfDay breakfastTime = const TimeOfDay(hour: 8, minute: 0);
  static TimeOfDay lunchTime = const TimeOfDay(hour: 12, minute: 0);
  static TimeOfDay dinnerTime = const TimeOfDay(hour: 18, minute: 0);
  static TimeOfDay bedtime = const TimeOfDay(hour: 22, minute: 0);
  static int beforeMealMinutes = 30;
  static int afterMealMinutes = 30;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    wakeTime = _parseTime(
      preferences.getString(_wakeKey),
      const TimeOfDay(hour: 7, minute: 0),
    );
    breakfastTime = _parseTime(
      preferences.getString(_breakfastKey),
      const TimeOfDay(hour: 8, minute: 0),
    );
    lunchTime = _parseTime(
      preferences.getString(_lunchKey),
      const TimeOfDay(hour: 12, minute: 0),
    );
    dinnerTime = _parseTime(
      preferences.getString(_dinnerKey),
      const TimeOfDay(hour: 18, minute: 0),
    );
    bedtime = _parseTime(
      preferences.getString(_bedtimeKey),
      const TimeOfDay(hour: 22, minute: 0),
    );
    beforeMealMinutes = _parseOffset(preferences.getInt(_beforeMealKey));
    afterMealMinutes = _parseOffset(preferences.getInt(_afterMealKey));
  }

  static Future<void> save({
    required TimeOfDay wake,
    required TimeOfDay breakfast,
    required TimeOfDay lunch,
    required TimeOfDay dinner,
    required TimeOfDay sleep,
    required int beforeMeal,
    required int afterMeal,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    wakeTime = wake;
    breakfastTime = breakfast;
    lunchTime = lunch;
    dinnerTime = dinner;
    bedtime = sleep;
    beforeMealMinutes = beforeMeal;
    afterMealMinutes = afterMeal;

    await Future.wait([
      preferences.setString(_wakeKey, _timeToString(wake)),
      preferences.setString(_breakfastKey, _timeToString(breakfast)),
      preferences.setString(_lunchKey, _timeToString(lunch)),
      preferences.setString(_dinnerKey, _timeToString(dinner)),
      preferences.setString(_bedtimeKey, _timeToString(sleep)),
      preferences.setInt(_beforeMealKey, beforeMeal),
      preferences.setInt(_afterMealKey, afterMeal),
    ]);
    revision.value += 1;
  }

  static TimeOfDay shift(TimeOfDay time, int minutes) {
    final totalMinutes = (time.hour * 60 + time.minute + minutes) % (24 * 60);
    final cleanMinutes = totalMinutes < 0
        ? totalMinutes + 24 * 60
        : totalMinutes;

    return TimeOfDay(hour: cleanMinutes ~/ 60, minute: cleanMinutes % 60);
  }

  static List<TimeOfDay> mealTimesForFrequency(int frequency) {
    if (frequency <= 1) {
      return [breakfastTime];
    }

    if (frequency == 2) {
      return [breakfastTime, dinnerTime];
    }

    return [breakfastTime, lunchTime, dinnerTime];
  }

  static String _timeToString(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, "0")}:${time.minute.toString().padLeft(2, "0")}";
  }

  static TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    final parts = (value ?? "").split(":");

    if (parts.length != 2) {
      return fallback;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  static int _parseOffset(int? value) {
    return const [15, 30, 45, 60].contains(value) ? value! : 30;
  }
}
