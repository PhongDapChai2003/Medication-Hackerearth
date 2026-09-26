import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'date_helper.dart';
import 'medication.dart';
import 'medication_storage.dart';
import 'pill_box_service.dart';
import 'time_helper.dart';

class PillBoxScheduleEntry {
  const PillBoxScheduleEntry({required this.slot, required this.minuteOfDay});

  final int slot;
  final int minuteOfDay;
}

class PillBoxReminderBridge {
  PillBoxReminderBridge._();

  static const String _lastTriggerKey = 'pill_box_last_trigger_v1';
  static Timer? _timer;
  static bool _checking = false;

  static void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(checkNow());
    });
    unawaited(checkNow());
    unawaited(syncScheduleNow());
  }

  static Future<bool> syncScheduleNow({DateTime? clock}) async {
    final now = clock ?? DateTime.now();

    try {
      final medications = await MedicationStorage.loadCurrentLocalMedications();
      final entries = buildScheduleEntries(medications, now);
      if (entries.length > PillBoxService.maxScheduleEntries) return false;
      final service = PillBoxService();

      try {
        final cleared = await service.clearSchedule();
        if (!cleared.ok) return false;

        for (final entry in entries) {
          final added = await service.addSchedule(
            slot: entry.slot,
            minuteOfDay: entry.minuteOfDay,
          );
          if (!added.ok) return false;
        }

        final clockResult = await service.synchronizeClock(now);
        return clockResult.ok;
      } finally {
        service.close();
      }
    } catch (_) {
      // Phone notifications remain available when the box is disconnected.
      return false;
    }
  }

  static List<PillBoxScheduleEntry> buildScheduleEntries(
    Iterable<Medication> medications,
    DateTime date,
  ) {
    final entries = <PillBoxScheduleEntry>[];
    final seen = <String>{};

    for (final medication in medications) {
      if (!_canUseMedication(medication, date)) continue;

      for (final savedTime in medication.reminderTimes) {
        final time = TimeHelper.stringToTime(savedTime);
        final minuteOfDay = (time.hour * 60) + time.minute;
        final key = '${medication.pillBoxSlot}|$minuteOfDay';
        if (!seen.add(key)) continue;
        entries.add(
          PillBoxScheduleEntry(
            slot: medication.pillBoxSlot,
            minuteOfDay: minuteOfDay,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final timeComparison = a.minuteOfDay.compareTo(b.minuteOfDay);
      return timeComparison != 0 ? timeComparison : a.slot.compareTo(b.slot);
    });
    return entries;
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> checkNow({DateTime? clock}) async {
    if (_checking) return;
    _checking = true;

    try {
      final now = clock ?? DateTime.now();
      final medications = await MedicationStorage.loadCurrentLocalMedications();

      for (final medication in medications) {
        if (!_canUseMedication(medication, now)) continue;

        for (final savedTime in medication.reminderTimes) {
          final time = TimeHelper.stringToTime(savedTime);
          if (time.hour != now.hour || time.minute != now.minute) continue;

          final triggerKey = _triggerKey(medication, savedTime, now);
          final preferences = await SharedPreferences.getInstance();
          if (preferences.getString(_lastTriggerKey) == triggerKey) return;

          final service = PillBoxService();
          try {
            final result = await service.lightSlot(medication.pillBoxSlot);
            if (result.ok) {
              await preferences.setString(_lastTriggerKey, triggerKey);
            }
          } finally {
            service.close();
          }
          return;
        }
      }
    } catch (_) {
      // Medication reminders must continue even if the box is disconnected.
    } finally {
      _checking = false;
    }
  }

  static Future<bool> triggerMedication(String medicationId) async {
    if (medicationId.trim().isEmpty) return false;

    try {
      final medications = await MedicationStorage.loadCurrentLocalMedications();
      final medication = medications.where(
        (item) => item.id == medicationId && item.pillBoxSlot >= 0,
      );
      if (medication.isEmpty) return false;

      final service = PillBoxService();
      try {
        final result = await service.lightSlot(medication.first.pillBoxSlot);
        return result.ok;
      } finally {
        service.close();
      }
    } catch (_) {
      return false;
    }
  }

  static bool _canUseMedication(Medication medication, DateTime date) {
    if (medication.pillBoxSlot < 0 ||
        medication.pillBoxSlot >= PillBoxSlot.slotCount ||
        medication.reminderTimes.isEmpty) {
      return false;
    }

    final currentDate = DateHelper.dateOnly(date);
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (startDate != null &&
        currentDate.isBefore(DateHelper.dateOnly(startDate))) {
      return false;
    }
    if (endDate != null && currentDate.isAfter(DateHelper.dateOnly(endDate))) {
      return false;
    }
    return true;
  }

  static String _triggerKey(
    Medication medication,
    String reminderTime,
    DateTime date,
  ) {
    final dateText = DateHelper.dateToString(DateHelper.dateOnly(date));
    return [
      dateText,
      medication.id,
      reminderTime,
      medication.pillBoxSlot,
    ].join('|');
  }
}
