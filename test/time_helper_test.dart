import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_storage.dart';
import 'package:flutter_application_1/schedule_preferences.dart';
import 'package:flutter_application_1/time_helper.dart';

void main() {
  setUp(() {
    SchedulePreferences.wakeTime = const TimeOfDay(hour: 7, minute: 0);
    SchedulePreferences.breakfastTime = const TimeOfDay(hour: 8, minute: 0);
    SchedulePreferences.lunchTime = const TimeOfDay(hour: 12, minute: 0);
    SchedulePreferences.dinnerTime = const TimeOfDay(hour: 18, minute: 0);
    SchedulePreferences.bedtime = const TimeOfDay(hour: 22, minute: 0);
    SchedulePreferences.beforeMealMinutes = 30;
    SchedulePreferences.afterMealMinutes = 30;
    TimeHelper.applyDeviceTimeFormat(false);
  });

  test("strict stored-time parsing rejects invalid clock values", () {
    expect(
      TimeHelper.tryParseStoredTime("9:05"),
      const TimeOfDay(hour: 9, minute: 5),
    );
    expect(
      TimeHelper.tryParseStoredTime("23:59"),
      const TimeOfDay(hour: 23, minute: 59),
    );
    expect(TimeHelper.tryParseStoredTime("25:99"), isNull);
    expect(TimeHelper.tryParseStoredTime("09:60"), isNull);
    expect(TimeHelper.tryParseStoredTime("not-a-time"), isNull);
  });

  test("medication normalization drops invalid reminder times", () {
    const medication = Medication(
      id: "invalid-times",
      name: "Example",
      dosage: "10 mg",
      instructions: "Take once daily",
      reminderTimes: ["9:05", "25:99", "09:60", "23:59"],
    );

    final normalized = MedicationStorage.normalizeMedication(medication);

    expect(normalized.reminderTimes, ["09:05", "23:59"]);
  });

  test("device clock preference controls the displayed time format", () {
    TimeHelper.applyDeviceTimeFormat(true);
    expect(
      TimeHelper.formatTimeForDisplay(const TimeOfDay(hour: 19, minute: 5)),
      "19:05",
    );

    TimeHelper.applyDeviceTimeFormat(false);
    expect(
      TimeHelper.formatTimeForDisplay(const TimeOfDay(hour: 19, minute: 5)),
      "7:05 PM",
    );
  });

  test(
    "after-midnight interval doses do not occur on the first day before midnight",
    () {
      const times = <TimeOfDay>[
        TimeOfDay(hour: 23, minute: 0),
        TimeOfDay(hour: 3, minute: 0),
        TimeOfDay(hour: 7, minute: 0),
      ];
      final startDate = DateTime(2026, 7, 26);

      expect(
        TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: 0,
          date: startDate,
          treatmentStartDate: startDate,
        ),
        isTrue,
      );
      expect(
        TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: 1,
          date: startDate,
          treatmentStartDate: startDate,
        ),
        isFalse,
      );
      expect(
        TimeHelper.reminderOccursOnDate(
          times: times,
          reminderIndex: 2,
          date: startDate,
          treatmentStartDate: startDate,
        ),
        isFalse,
      );
    },
  );

  test(
    "all interval doses use their own calendar time after the first day",
    () {
      const times = <TimeOfDay>[
        TimeOfDay(hour: 23, minute: 0),
        TimeOfDay(hour: 3, minute: 0),
        TimeOfDay(hour: 7, minute: 0),
      ];
      final startDate = DateTime(2026, 7, 26);
      final nextDate = DateTime(2026, 7, 27);

      for (int index = 0; index < times.length; index++) {
        expect(
          TimeHelper.reminderOccursOnDate(
            times: times,
            reminderIndex: index,
            date: nextDate,
            treatmentStartDate: startDate,
          ),
          isTrue,
        );
      }
    },
  );

  test("every scheduled date and time has its own dose record key", () {
    final date = DateTime(2026, 7, 27);
    final firstKey = TimeHelper.doseRecordKeyForDate(
      date,
      const TimeOfDay(hour: 7, minute: 0),
    );
    final secondKey = TimeHelper.doseRecordKeyForDate(
      date,
      const TimeOfDay(hour: 11, minute: 0),
    );
    final nextDayKey = TimeHelper.doseRecordKeyForDate(
      date.add(const Duration(days: 1)),
      const TimeOfDay(hour: 7, minute: 0),
    );

    expect(firstKey, "2026-07-27|07:00");
    expect(secondKey, "2026-07-27|11:00");
    expect(nextDayKey, "2026-07-28|07:00");
    expect(<String>{firstKey, secondKey, nextDayKey}, hasLength(3));
  });

  test("daily after-food directions use the personal breakfast offset", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Take 2 capsules each day after eat",
    );

    expect(times, const [TimeOfDay(hour: 8, minute: 30)]);
    expect(
      TimeHelper.getDoseAmountFromInstructions(
        "Take 2 capsules each day after eat",
      ),
      2,
    );
  });

  test("timing in notes is selected when instructions only contain dose", () {
    final selected = TimeHelper.selectScheduleDirections(
      instructions: "Take 2 capsules",
      notes: "Each day after eating",
    );
    final combined = TimeHelper.combineDoseDirections(
      instructions: "Take 2 capsules",
      notes: "Each day after eating",
    );
    final times = TimeHelper.generateReminderTimesFromInstructions(selected);

    expect(selected, "Each day after eating");
    expect(times, const [TimeOfDay(hour: 8, minute: 30)]);
    expect(TimeHelper.getDoseAmountFromInstructions(combined), 2);
  });

  test("automatic instruction schedule wins over unrelated notes", () {
    final selected = TimeHelper.selectScheduleDirections(
      instructions: "Take 1 tablet at 8 AM and 8 PM",
      notes: "Take with plenty of water",
    );
    final times = TimeHelper.generateReminderTimesFromInstructions(selected);

    expect(times, const [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 20, minute: 0),
    ]);
  });

  test("empty directions never create a guessed default time", () {
    expect(TimeHelper.generateReminderTimesFromInstructions(""), isEmpty);
  });

  test("before-breakfast directions use the personal before-meal offset", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Take 1 tablet before breakfast",
    );

    expect(times, const [TimeOfDay(hour: 7, minute: 30)]);
  });

  test("after-dinner directions use the personal after-meal offset", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Take 1 tablet after dinner",
    );

    expect(times, const [TimeOfDay(hour: 18, minute: 30)]);
  });

  test("Vietnamese named meals use the configured meal offset", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Uống 1 viên trước bữa tối",
    );

    expect(times, const [TimeOfDay(hour: 17, minute: 30)]);
  });

  test("hourly interval starts from the personal wake time", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Take 1 capsule every 4 hours",
    );

    expect(times.length, 6);
    expect(times.first, const TimeOfDay(hour: 7, minute: 0));
  });

  test("as-needed directions do not create fixed reminders", () {
    final times = TimeHelper.generateReminderTimesFromInstructions(
      "Take 1 tablet as needed for pain",
    );

    expect(times, isEmpty);
  });

  test("unsafe ranges stay available for manual review", () {
    const directions = "Take 1 capsule every 4 to 6 hours";

    expect(TimeHelper.requiresManualScheduleReview(directions), isTrue);
    expect(
      TimeHelper.generateReminderTimesFromInstructions(directions),
      isEmpty,
    );
  });

  test(
    "common typed misspellings still calculate dose and daily frequency",
    () {
      const directions = "Tkae 2 talbets twise daliy";
      final times = TimeHelper.generateReminderTimesFromInstructions(
        directions,
      );
      final interpretation = TimeHelper.interpretInstruction(directions);

      expect(TimeHelper.getDoseAmountFromInstructions(directions), 2);
      expect(times, const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
      ]);
      expect(interpretation.usedSpellingAssistance, isTrue);
      expect(interpretation.normalizedText, "take 2 tablets twice daily");
    },
  );

  test("common OCR spacing mistakes still calculate an hourly interval", () {
    const directions = "Take 1 capusle evry 8 hors";
    final times = TimeHelper.generateReminderTimesFromInstructions(directions);

    expect(times.length, 3);
    expect(times.first, const TimeOfDay(hour: 7, minute: 0));
    expect(TimeHelper.extractEveryHours(directions), 8);
  });

  test(
    "one-edit spelling mistakes are interpreted without a fixed typo list",
    () {
      const directions = "Take 3 tablt evrey 12 houes";
      final interpretation = TimeHelper.interpretInstruction(directions);
      final times = TimeHelper.generateReminderTimesFromInstructions(
        directions,
      );

      expect(interpretation.normalizedText, "take 3 tablet every 12 hours");
      expect(TimeHelper.getDoseAmountFromInstructions(directions), 3);
      expect(times.length, 2);
    },
  );

  test(
    "OCR letter and number substitutions in schedule words are corrected",
    () {
      const directions = "TAKE 1 TAB1ET TW1CE DA11Y";
      final interpretation = TimeHelper.interpretInstruction(directions);
      final times = TimeHelper.generateReminderTimesFromInstructions(
        directions,
      );

      expect(interpretation.normalizedText, "take 1 tablet twice daily");
      expect(times.length, 2);
      expect(TimeHelper.getDoseAmountFromInstructions(directions), 1);
    },
  );

  test("Vietnamese typing mistakes still calculate daily frequency", () {
    const directions = "Uonng 1 vien moi ngya 2 lna";
    final times = TimeHelper.generateReminderTimesFromInstructions(directions);

    expect(times, const [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 18, minute: 0),
    ]);
  });

  test("spelling assistance never changes dose numbers", () {
    final interpretation = TimeHelper.interpretInstruction(
      "Tkae 10 talbets daliy",
    );

    expect(interpretation.normalizedText, "take 10 tablets daily");
    expect(
      TimeHelper.getDoseAmountFromInstructions("Tkae 10 talbets daliy"),
      10,
    );
  });

  test("misspelled PRN remains an as-needed instruction", () {
    const directions = "Take 1 tablet prm for pain";

    expect(TimeHelper.isAsNeededInstruction(directions), isTrue);
    expect(
      TimeHelper.generateReminderTimesFromInstructions(directions),
      isEmpty,
    );
  });

  test("negated directions never create an automatic schedule", () {
    const directions = "Do not take this medication daily";

    expect(TimeHelper.requiresManualScheduleReview(directions), isTrue);
    expect(
      TimeHelper.generateReminderTimesFromInstructions(directions),
      isEmpty,
    );
  });

  test("spelling help does not make an unsafe range automatic", () {
    const directions = "Tkae 1 capusle evry 4 to 6 hors";

    expect(TimeHelper.requiresManualScheduleReview(directions), isTrue);
    expect(
      TimeHelper.generateReminderTimesFromInstructions(directions),
      isEmpty,
    );
  });

  test("unclear OCR interval numbers are never guessed", () {
    const directions = "Take 1 tablet every O hours";

    expect(TimeHelper.extractEveryHours(directions), isNull);
    expect(
      TimeHelper.generateReminderTimesFromInstructions(directions),
      isEmpty,
    );
  });

  test("medication stores dose record conflict metadata", () {
    const medication = Medication(
      id: "med_1",
      name: "Example",
      dosage: "10 mg",
      instructions: "Once daily",
      doseRecords: {"2026-07-15|08:00": "taken"},
      doseRecordUpdatedAt: {"2026-07-15|08:00": "2026-07-15T15:00:00.000Z"},
      deletedDoseRecords: {"2026-07-14|08:00": "2026-07-15T15:01:00.000Z"},
      inventoryBaselineQuantity: "30",
      inventoryBaselineAt: "2026-07-01T00:00:00.000Z",
      pillBoxSlot: 4,
      updatedAt: "2026-07-15T15:01:00.000Z",
    );

    final restored = Medication.fromJson(medication.toJson());
    expect(restored.doseRecords, medication.doseRecords);
    expect(restored.doseRecordUpdatedAt, medication.doseRecordUpdatedAt);
    expect(restored.deletedDoseRecords, medication.deletedDoseRecords);
    expect(
      restored.inventoryBaselineQuantity,
      medication.inventoryBaselineQuantity,
    );
    expect(restored.inventoryBaselineAt, medication.inventoryBaselineAt);
    expect(restored.pillBoxSlot, 4);
  });

  test("each reminder time can be marked taken independently", () {
    const medication = Medication(
      id: "multi-dose",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "10",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: "2026-07-27T08:00:00.000Z",
      instructions: "Take 1 tablet every 4 hours",
      reminderTimes: <String>["11:00", "15:00"],
    );

    final afterThreePm = MedicationStorage.applyDoseRecordChange(
      medication: medication,
      recordKey: "2026-07-27|15:00",
      status: "taken",
      changedAt: "2026-07-27T22:00:00.000Z",
      today: "2026-07-27",
    );
    final afterElevenAm = MedicationStorage.applyDoseRecordChange(
      medication: afterThreePm,
      recordKey: "2026-07-27|11:00",
      status: "taken",
      changedAt: "2026-07-27T22:01:00.000Z",
      today: "2026-07-27",
    );

    expect(afterElevenAm.doseRecords["2026-07-27|15:00"], "taken");
    expect(afterElevenAm.doseRecords["2026-07-27|11:00"], "taken");
    expect(afterElevenAm.doseRecords, hasLength(2));
    expect(afterElevenAm.remainingQuantity, "8");

    final afterUndo = MedicationStorage.removeDoseRecordChange(
      medication: afterElevenAm,
      recordKey: "2026-07-27|11:00",
      changedAt: "2026-07-27T22:02:00.000Z",
      today: "2026-07-27",
    );

    expect(afterUndo.doseRecords["2026-07-27|15:00"], "taken");
    expect(afterUndo.doseRecords.containsKey("2026-07-27|11:00"), isFalse);
    expect(afterUndo.remainingQuantity, "9");
  });

  test("two devices reduce quantity for both merged taken doses", () {
    const baselineAt = "2026-07-25T15:00:00.000Z";
    const firstDoseAt = "2026-07-25T16:00:00.000Z";
    const secondDoseAt = "2026-07-25T17:00:00.000Z";
    const first = Medication(
      id: "med_sync",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "9",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: baselineAt,
      instructions: "Take 1 tablet daily",
      doseRecords: {"2026-07-25|08:00": "taken"},
      doseRecordUpdatedAt: {"2026-07-25|08:00": firstDoseAt},
      updatedAt: firstDoseAt,
    );
    const second = Medication(
      id: "med_sync",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "9",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: baselineAt,
      instructions: "Take 1 tablet daily",
      doseRecords: {"2026-07-25|20:00": "taken"},
      doseRecordUpdatedAt: {"2026-07-25|20:00": secondDoseAt},
      updatedAt: secondDoseAt,
    );

    final merged = MedicationStorage.mergeMedicationVersionsForTesting(
      first: first,
      second: second,
    );

    expect(merged.doseRecords.length, 2);
    expect(merged.remainingQuantity, "8");
  });

  test("a newer Taken action cannot be replaced by an older Missed value", () {
    const cloudBeforeTap = Medication(
      id: "med_status_race",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "10",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: "2026-08-02T20:00:00.000Z",
      instructions: "Take 1 tablet daily",
      doseRecords: {"2026-08-02|22:00": "missed"},
      doseRecordUpdatedAt: {"2026-08-02|22:00": "2026-08-02T22:30:00.000Z"},
      updatedAt: "2026-08-02T22:30:00.000Z",
    );
    const localAfterTap = Medication(
      id: "med_status_race",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "9",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: "2026-08-02T20:00:00.000Z",
      instructions: "Take 1 tablet daily",
      doseRecords: {"2026-08-02|22:00": "taken"},
      doseRecordUpdatedAt: {"2026-08-02|22:00": "2026-08-02T22:40:00.000Z"},
      updatedAt: "2026-08-02T22:40:00.000Z",
    );

    final merged = MedicationStorage.mergeMedicationVersionsForTesting(
      first: cloudBeforeTap,
      second: localAfterTap,
    );

    expect(merged.doseRecords["2026-08-02|22:00"], "taken");
    expect(merged.remainingQuantity, "9");
  });

  test("a refill becomes the new quantity baseline across devices", () {
    const originalBaselineAt = "2026-07-25T12:00:00.000Z";
    const refillAt = "2026-07-25T18:00:00.000Z";
    const laterDoseAt = "2026-07-25T19:00:00.000Z";
    const refilled = Medication(
      id: "med_refill",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "10",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: refillAt,
      instructions: "Take 1 tablet daily",
      doseRecords: {"2026-07-24|08:00": "taken", "2026-07-25|08:00": "taken"},
      doseRecordUpdatedAt: {
        "2026-07-24|08:00": "2026-07-24T15:00:00.000Z",
        "2026-07-25|08:00": "2026-07-25T15:00:00.000Z",
      },
      updatedAt: refillAt,
    );
    const otherDevice = Medication(
      id: "med_refill",
      name: "Example",
      dosage: "10 mg",
      quantity: "10",
      remainingQuantity: "7",
      inventoryBaselineQuantity: "10",
      inventoryBaselineAt: originalBaselineAt,
      instructions: "Take 1 tablet daily",
      doseRecords: {
        "2026-07-24|08:00": "taken",
        "2026-07-25|08:00": "taken",
        "2026-07-25|20:00": "taken",
      },
      doseRecordUpdatedAt: {
        "2026-07-24|08:00": "2026-07-24T15:00:00.000Z",
        "2026-07-25|08:00": "2026-07-25T15:00:00.000Z",
        "2026-07-25|20:00": laterDoseAt,
      },
      updatedAt: laterDoseAt,
    );

    final merged = MedicationStorage.mergeMedicationVersionsForTesting(
      first: refilled,
      second: otherDevice,
    );

    expect(merged.inventoryBaselineAt, refillAt);
    expect(merged.remainingQuantity, "9");
  });
}
