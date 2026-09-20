import 'package:flutter/material.dart';

import 'schedule_preferences.dart';

class InstructionCorrection {
  final String original;
  final String interpretedAs;

  const InstructionCorrection({
    required this.original,
    required this.interpretedAs,
  });
}

class InstructionInterpretation {
  final String normalizedText;
  final List<InstructionCorrection> corrections;

  const InstructionInterpretation({
    required this.normalizedText,
    required this.corrections,
  });

  bool get usedSpellingAssistance => corrections.isNotEmpty;

  String correctionSummary({int maximumCorrections = 3}) {
    if (corrections.isEmpty || maximumCorrections <= 0) {
      return "";
    }

    final visibleCorrections = corrections
        .take(maximumCorrections)
        .map((correction) {
          return "“${correction.original}” → “${correction.interpretedAs}”";
        })
        .join(", ");

    final hiddenCount = corrections.length - maximumCorrections;

    if (hiddenCount > 0) {
      return "$visibleCorrections, +$hiddenCount";
    }

    return visibleCorrections;
  }
}

class TimeHelper {
  // These corrections are intentionally conservative. They only cover common
  // typing/OCR mistakes in medication action, unit, and schedule words. Dose
  // numbers, times, strengths, and quantities are never corrected.
  static const Map<String, String> _safeInstructionTermCorrections = {
    "tkae": "take",
    "taek": "take",
    "takee": "take",
    "takke": "take",
    "tak": "take",
    "direcitons": "directions",
    "directons": "directions",
    "directon": "direction",
    "instrutions": "instructions",
    "instuctions": "instructions",
    "instrction": "instruction",
    "descrption": "description",
    "admnister": "administer",
    "adminster": "administer",
    "swalow": "swallow",
    "swalllow": "swallow",
    "inahle": "inhale",
    "instil": "instill",
    "aply": "apply",
    "dissovle": "dissolve",
    "talbet": "tablet",
    "tabet": "tablet",
    "tablwt": "tablet",
    "tablett": "tablet",
    "tab1et": "tablet",
    "talbets": "tablets",
    "tabltes": "tablets",
    "tab1ets": "tablets",
    "pil": "pill",
    "pils": "pills",
    "capsul": "capsule",
    "capusle": "capsule",
    "capsuel": "capsule",
    "capsuls": "capsules",
    "capusles": "capsules",
    "capsuels": "capsules",
    "supository": "suppository",
    "suppositry": "suppository",
    "supositories": "suppositories",
    "drp": "drop",
    "drps": "drops",
    "pufs": "puffs",
    "patche": "patch",
    "spry": "spray",
    "teaspon": "teaspoon",
    "tablespon": "tablespoon",
    "evry": "every",
    "evey": "every",
    "everry": "every",
    "everv": "every",
    "ech": "each",
    "houre": "hour",
    "hors": "hours",
    "houres": "hours",
    "hourrs": "hours",
    "daliy": "daily",
    "dalily": "daily",
    "dayly": "daily",
    "dai1y": "daily",
    "da11y": "daily",
    "onxe": "once",
    "0nce": "once",
    "twise": "twice",
    "twce": "twice",
    "tw1ce": "twice",
    "threetime": "three times",
    "mornig": "morning",
    "morining": "morning",
    "mornng": "morning",
    "afternon": "afternoon",
    "evenig": "evening",
    "evenning": "evening",
    "nite": "night",
    "nigth": "night",
    "bedtme": "bedtime",
    "bedime": "bedtime",
    "breakfest": "breakfast",
    "brekfast": "breakfast",
    "luch": "lunch",
    "diner": "dinner",
    "befor": "before",
    "befroe": "before",
    "afer": "after",
    "aftr": "after",
    "meel": "meal",
    "meels": "meals",
    "foood": "food",
    "needd": "needed",
    "needded": "needed",
    "necessry": "necessary",
    "requiered": "required",
    "prm": "prn",
    "uonng": "uong",
    "uog": "uong",
    "uoong": "uong",
    "vienn": "vien",
    "moii": "moi",
    "m0i": "moi",
    "ngya": "ngay",
    "ngayy": "ngay",
    "lna": "lan",
    "lann": "lan",
    "trouc": "truoc",
    "trouoc": "truoc",
    "saau": "sau",
    "sangg": "sang",
    "toii": "toi",
  };

  static const Set<String> _safeFuzzyInstructionTerms = {
    "directions",
    "direction",
    "instructions",
    "instruction",
    "description",
    "take",
    "give",
    "administer",
    "swallow",
    "inhale",
    "instill",
    "inject",
    "insert",
    "apply",
    "chew",
    "dissolve",
    "tablet",
    "tablets",
    "capsule",
    "capsules",
    "pill",
    "pills",
    "suppository",
    "suppositories",
    "drop",
    "drops",
    "puff",
    "puffs",
    "patch",
    "patches",
    "spray",
    "sprays",
    "teaspoon",
    "teaspoons",
    "tablespoon",
    "tablespoons",
    "every",
    "each",
    "hour",
    "hours",
    "daily",
    "once",
    "twice",
    "morning",
    "afternoon",
    "evening",
    "night",
    "bedtime",
    "breakfast",
    "lunch",
    "dinner",
    "before",
    "after",
    "meal",
    "meals",
    "food",
    "needed",
    "necessary",
    "required",
  };

  static final ValueNotifier<String> currentTimeFormat = ValueNotifier<String>(
    "ampm",
  );

  static void applyDeviceTimeFormat(bool uses24HourClock) {
    final deviceFormat = uses24HourClock ? "24h" : "ampm";

    if (currentTimeFormat.value != deviceFormat) {
      currentTimeFormat.value = deviceFormat;
    }
  }

  static bool get uses24HourFormat {
    return currentTimeFormat.value == "24h";
  }

  static String timeToString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, "0");
    final minute = time.minute.toString().padLeft(2, "0");

    return "$hour:$minute";
  }

  /// Parses a persisted 24-hour time without changing invalid values.
  ///
  /// This is intentionally stricter than [stringToTime], which keeps its
  /// user-interface fallback for older callers.
  static TimeOfDay? tryParseStoredTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  static TimeOfDay stringToTime(String value) {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    final parts = cleanValue.split(":");

    if (parts.length != 2) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    final parsedHour = int.tryParse(parts[0]) ?? 8;
    final parsedMinute = int.tryParse(parts[1]) ?? 0;

    final safeHour = parsedHour < 0
        ? 0
        : parsedHour > 23
        ? 23
        : parsedHour;

    final safeMinute = parsedMinute < 0
        ? 0
        : parsedMinute > 59
        ? 59
        : parsedMinute;

    return TimeOfDay(hour: safeHour, minute: safeMinute);
  }

  static String formatTimeForDisplay(TimeOfDay time) {
    if (uses24HourFormat) {
      return timeToString(time);
    }

    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, "0");
    final period = time.period == DayPeriod.am ? "AM" : "PM";

    return "$hour12:$minute $period";
  }

  static String formatStoredTimeForDisplay(String storedTime) {
    return formatTimeForDisplay(stringToTime(storedTime));
  }

  static String formatDateTimeAsTime(DateTime dateTime) {
    return timeToString(
      TimeOfDay(hour: dateTime.hour, minute: dateTime.minute),
    );
  }

  static String formatDateTimeAsDisplayTime(DateTime dateTime) {
    return formatTimeForDisplay(
      TimeOfDay(hour: dateTime.hour, minute: dateTime.minute),
    );
  }

  static int midnightCrossIndex(List<TimeOfDay> times) {
    for (int index = 1; index < times.length; index++) {
      final previousMinutes =
          times[index - 1].hour * 60 + times[index - 1].minute;
      final currentMinutes = times[index].hour * 60 + times[index].minute;

      if (currentMinutes < previousMinutes) {
        return index;
      }
    }

    return -1;
  }

  static bool reminderOccursOnDate({
    required List<TimeOfDay> times,
    required int reminderIndex,
    required DateTime date,
    DateTime? treatmentStartDate,
  }) {
    if (reminderIndex < 0 || reminderIndex >= times.length) {
      return false;
    }

    if (treatmentStartDate == null) {
      return true;
    }

    final selectedDate = DateTime(date.year, date.month, date.day);
    final startDate = DateTime(
      treatmentStartDate.year,
      treatmentStartDate.month,
      treatmentStartDate.day,
    );

    if (selectedDate.isBefore(startDate)) {
      return false;
    }

    if (selectedDate != startDate) {
      return true;
    }

    final crossIndex = midnightCrossIndex(times);

    if (crossIndex < 0) {
      return true;
    }

    // On the first treatment day, times after the schedule crosses midnight
    // belong to the following calendar day. They must not appear as missed
    // doses before midnight.
    return reminderIndex < crossIndex;
  }

  static String doseRecordKeyForDate(DateTime date, TimeOfDay time) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");

    return "$year-$month-$day|${timeToString(time)}";
  }

  static DateTime getDateTimeForToday(TimeOfDay time) {
    final now = DateTime.now();

    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  static DateTime getDateTimeForDate(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static DateTime? getNextDoseDateTime(List<TimeOfDay> times) {
    if (times.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final candidates = <DateTime>[];

    for (final time in times) {
      final todayDose = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      if (todayDose.isAfter(now) || todayDose.isAtSameMomentAs(now)) {
        candidates.add(todayDose);
      } else {
        candidates.add(todayDose.add(const Duration(days: 1)));
      }
    }

    candidates.sort((a, b) {
      return a.compareTo(b);
    });

    return candidates.first;
  }

  static List<TimeOfDay> generateReminderTimesFromInstructions(
    String instructions,
  ) {
    final text = normalizeInstruction(instructions);
    final compact = _compactText(text);

    if (text.trim().isEmpty) {
      return const [];
    }

    if (_containsAsNeeded(text, compact)) {
      return const [];
    }

    if (_requiresManualScheduleReview(text, compact)) {
      return const [];
    }

    final explicitTimes = _extractExplicitTimes(text);
    final namedScheduleTimes = _applyMealTimingOffset(
      _extractNamedScheduleTimes(text, compact),
      text,
      compact,
    );
    final everyHourInterval = _extractEveryHourInterval(text);

    if (everyHourInterval != null) {
      final possibleStartTimes = [...explicitTimes, ...namedScheduleTimes];

      if (possibleStartTimes.isNotEmpty) {
        return generateTimesByIntervalFromStart(
          everyHourInterval,
          possibleStartTimes.first,
        );
      }

      return generateTimesByInterval(everyHourInterval);
    }

    if (explicitTimes.isNotEmpty) {
      return _sortTimesChronologically(
        removeDuplicateTimes([...explicitTimes, ...namedScheduleTimes]),
      );
    }

    final dailyFrequency = _extractDailyFrequency(text, compact);

    if (namedScheduleTimes.length >= 2) {
      return namedScheduleTimes;
    }

    if (dailyFrequency != null) {
      if (namedScheduleTimes.length == dailyFrequency) {
        return namedScheduleTimes;
      }

      return _applyMealTimingOffset(
        _timesForDailyFrequency(
          dailyFrequency,
          takeWithMeals: _containsWithMeals(text, compact),
        ),
        text,
        compact,
      );
    }

    if (_containsBreakfastLunchDinner(text, compact)) {
      return _applyMealTimingOffset(
        SchedulePreferences.mealTimesForFrequency(3),
        text,
        compact,
      );
    }

    if (_containsAllMealsInstruction(text, compact)) {
      return _applyMealTimingOffset(
        SchedulePreferences.mealTimesForFrequency(3),
        text,
        compact,
      );
    }

    if (namedScheduleTimes.isNotEmpty) {
      return namedScheduleTimes;
    }

    if (_containsWithMeals(text, compact)) {
      return _applyMealTimingOffset(
        SchedulePreferences.mealTimesForFrequency(1),
        text,
        compact,
      );
    }

    if (_containsMorningAndNight(text, compact)) {
      return [SchedulePreferences.breakfastTime, SchedulePreferences.bedtime];
    }

    if (_containsMorningAndEvening(text, compact)) {
      return [
        SchedulePreferences.breakfastTime,
        SchedulePreferences.dinnerTime,
      ];
    }

    if (_containsTwiceDaily(text, compact)) {
      return [
        SchedulePreferences.breakfastTime,
        SchedulePreferences.dinnerTime,
      ];
    }

    if (_containsThreeTimesDaily(text, compact)) {
      return const [
        TimeOfDay(hour: 8, minute: 0),
        TimeOfDay(hour: 14, minute: 0),
        TimeOfDay(hour: 20, minute: 0),
      ];
    }

    if (_containsFourTimesDaily(text, compact)) {
      return const [
        TimeOfDay(hour: 6, minute: 0),
        TimeOfDay(hour: 12, minute: 0),
        TimeOfDay(hour: 18, minute: 0),
        TimeOfDay(hour: 22, minute: 0),
      ];
    }

    if (_containsNightTime(text, compact)) {
      return [SchedulePreferences.bedtime];
    }

    if (_containsNoonTime(text, compact)) {
      return [SchedulePreferences.lunchTime];
    }

    if (_containsMorningTime(text, compact)) {
      return [SchedulePreferences.breakfastTime];
    }

    if (_containsDaily(text, compact)) {
      return [SchedulePreferences.breakfastTime];
    }

    return const [];
  }

  static List<TimeOfDay> generateTimesByInterval(int intervalHours) {
    return generateTimesByIntervalFromStart(
      intervalHours,
      SchedulePreferences.wakeTime,
    );
  }

  static String explainGeneratedSchedule(String instructions) {
    final text = normalizeInstruction(instructions);
    final compact = _compactText(text);
    final times = generateReminderTimesFromInstructions(instructions);

    if (times.isEmpty) {
      return "No automatic fixed schedule was created. Review the directions and choose times manually.";
    }

    final displayTimes = times.map(formatTimeForDisplay).join(", ");

    if (_extractEveryHourInterval(text) != null) {
      return "The directions contain an hourly interval. The first dose starts at the selected time and later doses keep that interval: $displayTimes.";
    }

    if (_containsWithMeals(text, compact)) {
      final timing = _containsBeforeMeal(text, compact)
          ? "${SchedulePreferences.beforeMealMinutes} minutes before your saved meal time"
          : _containsAfterMeal(text, compact)
          ? "${SchedulePreferences.afterMealMinutes} minutes after your saved meal time"
          : "at your saved meal time";
      return "The directions mention food or a meal, so reminders are placed $timing: $displayTimes.";
    }

    return "The directions were matched to your personal daily schedule: $displayTimes. You can edit every time before saving.";
  }

  static List<TimeOfDay> generateTimesByIntervalFromStart(
    int intervalHours,
    TimeOfDay firstDoseTime,
  ) {
    if (intervalHours <= 0 || intervalHours > 24) {
      return [firstDoseTime];
    }

    if (intervalHours == 24) {
      return [firstDoseTime];
    }

    final times = <TimeOfDay>[];
    final firstDoseMinutes = firstDoseTime.hour * 60 + firstDoseTime.minute;
    final doseCount = (24 / intervalHours).round().clamp(1, 24).toInt();

    for (int i = 0; i < doseCount; i++) {
      final doseMinutes =
          (firstDoseMinutes + i * intervalHours * 60) % (24 * 60);

      times.add(TimeOfDay(hour: doseMinutes ~/ 60, minute: doseMinutes % 60));
    }

    if (times.isEmpty) {
      return [firstDoseTime];
    }

    return removeDuplicateTimes(times);
  }

  static int getDoseAmountFromInstructions(String instructions) {
    final text = normalizeInstruction(instructions);

    if (text.contains("half") ||
        text.contains("one half") ||
        text.contains("1/2") ||
        text.contains("0.5") ||
        text.contains("½") ||
        text.contains("nửa") ||
        text.contains("nua")) {
      return 1;
    }

    final decimalMatch = RegExp(
      r'(take|give|administer|swallow|inhale|instill|inject|uống|uong|dùng|dung|insert|đặt|dat|use|apply|chew|dissolve|nhỏ|nho|xịt|xit|bôi|boi|tiêm|tiem)\s+(\d+\.\d+)',
      caseSensitive: false,
    ).firstMatch(text);

    if (decimalMatch != null) {
      final amount = double.tryParse(decimalMatch.group(2) ?? "");

      if (amount != null && amount > 0 && amount < 1) {
        return 1;
      }

      if (amount != null && amount >= 1 && amount <= 20) {
        return amount.round();
      }
    }

    final actionNumberMatch = RegExp(
      r'(take|give|administer|swallow|inhale|instill|inject|uống|uong|dùng|dung|insert|đặt|dat|use|apply|chew|dissolve|nhỏ|nho|xịt|xit|bôi|boi|tiêm|tiem)\s+(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(text);

    if (actionNumberMatch != null) {
      final amount = int.tryParse(actionNumberMatch.group(2) ?? "");

      if (amount != null && amount > 0 && amount <= 20) {
        return amount;
      }
    }

    final unitNumberMatch = RegExp(
      r'\b(\d{1,2})\s*(tablet|tablets|capsule|capsules|pill|pills|tab|tabs|cap|caps|suppository|suppositories|drop|drops|puff|puffs|patch|patches|spray|sprays|teaspoon|teaspoons|tablespoon|tablespoons|ml|milliliter|milliliters|unit|units|viên|vien|giọt|giot|nhát|nhat|muỗng|muong)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (unitNumberMatch != null) {
      final amount = int.tryParse(unitNumberMatch.group(1) ?? "");

      if (amount != null && amount > 0 && amount <= 20) {
        return amount;
      }
    }

    final actionWordMatch = RegExp(
      r'(take|give|administer|swallow|inhale|instill|inject|insert|use|apply|chew|dissolve|uống|uong|dùng|dung|đặt|dat|nhỏ|nho|xịt|xit|bôi|boi|tiêm|tiem)\s+(one|two|three|four|five|six|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau)',
      caseSensitive: false,
    ).firstMatch(text);

    if (actionWordMatch != null) {
      final amount = _wordToDoseAmount(actionWordMatch.group(2) ?? "");

      if (amount > 0) {
        return amount;
      }
    }

    final unitWordMatch = RegExp(
      r'\b(one|two|three|four|five|six|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau)\s*(tablet|tablets|capsule|capsules|pill|pills|tab|tabs|cap|caps|suppository|suppositories|drop|drops|puff|puffs|patch|patches|spray|sprays|teaspoon|teaspoons|tablespoon|tablespoons|unit|units|viên|vien|giọt|giot|nhát|nhat|muỗng|muong)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (unitWordMatch != null) {
      final amount = _wordToDoseAmount(unitWordMatch.group(1) ?? "");

      if (amount > 0) {
        return amount;
      }
    }

    return 1;
  }

  static int _wordToDoseAmount(String word) {
    final cleanWord = word.toLowerCase().trim();

    switch (cleanWord) {
      case "one":
      case "một":
      case "mot":
        return 1;
      case "two":
      case "hai":
        return 2;
      case "three":
      case "ba":
        return 3;
      case "four":
      case "bốn":
      case "bon":
        return 4;
      case "five":
      case "năm":
      case "nam":
        return 5;
      case "six":
      case "sáu":
      case "sau":
        return 6;
      default:
        return 0;
    }
  }

  static List<TimeOfDay> removeDuplicateTimes(List<TimeOfDay> times) {
    final seen = <String>{};
    final cleanTimes = <TimeOfDay>[];

    for (final time in times) {
      final key = timeToString(time);

      if (!seen.contains(key)) {
        seen.add(key);
        cleanTimes.add(time);
      }
    }

    return cleanTimes;
  }

  static InstructionInterpretation interpretInstruction(String instructions) {
    final baseText = instructions
        .toLowerCase()
        .replaceAll("&", " and ")
        .replaceAll(RegExp(r'[^a-z0-9à-ỹ\s./:@½]'), ' ')
        .replaceAll(RegExp(r'\ba\.?\s*m\.?\b'), 'am')
        .replaceAll(RegExp(r'\bp\.?\s*m\.?\b'), 'pm')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (baseText.isEmpty) {
      return const InstructionInterpretation(
        normalizedText: "",
        corrections: [],
      );
    }

    final corrections = <InstructionCorrection>[];
    final seenCorrections = <String>{};
    final correctedTerms = <String>[];

    for (final term in baseText.split(" ")) {
      final interpretedTerm = _interpretInstructionTerm(term);

      if (interpretedTerm != term) {
        final correctionKey = "$term|$interpretedTerm";

        if (seenCorrections.add(correctionKey)) {
          corrections.add(
            InstructionCorrection(
              original: term,
              interpretedAs: interpretedTerm,
            ),
          );
        }
      }

      correctedTerms.add(interpretedTerm);
    }

    return InstructionInterpretation(
      normalizedText: correctedTerms.join(" "),
      corrections: List.unmodifiable(corrections),
    );
  }

  static String normalizeInstruction(String instructions) {
    return interpretInstruction(instructions).normalizedText;
  }

  static String correctInstructionTerm(String term) {
    final cleanTerm = term
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9à-ỹ]'), '')
        .trim();

    if (cleanTerm.isEmpty) {
      return "";
    }

    return _interpretInstructionTerm(cleanTerm);
  }

  static String _interpretInstructionTerm(String term) {
    final mappedTerm = _safeInstructionTermCorrections[term];

    if (mappedTerm != null) {
      return mappedTerm;
    }

    if (term.length < 4 ||
        RegExp(r'\d').hasMatch(term) ||
        _safeFuzzyInstructionTerms.contains(term)) {
      return term;
    }

    final matches = _safeFuzzyInstructionTerms.where((candidate) {
      return _isAtMostOneEditApart(term, candidate);
    }).toList();

    return matches.length == 1 ? matches.first : term;
  }

  static bool _isAtMostOneEditApart(String first, String second) {
    if (first == second) {
      return true;
    }

    final lengthDifference = (first.length - second.length).abs();

    if (lengthDifference > 1) {
      return false;
    }

    if (first.length == second.length) {
      final mismatchIndexes = <int>[];

      for (int index = 0; index < first.length; index++) {
        if (first[index] != second[index]) {
          mismatchIndexes.add(index);

          if (mismatchIndexes.length > 2) {
            return false;
          }
        }
      }

      if (mismatchIndexes.length == 1) {
        return true;
      }

      if (mismatchIndexes.length == 2) {
        final firstMismatch = mismatchIndexes[0];
        final secondMismatch = mismatchIndexes[1];

        return secondMismatch == firstMismatch + 1 &&
            first[firstMismatch] == second[secondMismatch] &&
            first[secondMismatch] == second[firstMismatch];
      }

      return false;
    }

    final shorter = first.length < second.length ? first : second;
    final longer = first.length < second.length ? second : first;
    int shortIndex = 0;
    int longIndex = 0;
    bool skippedOneCharacter = false;

    while (shortIndex < shorter.length && longIndex < longer.length) {
      if (shorter[shortIndex] == longer[longIndex]) {
        shortIndex += 1;
        longIndex += 1;
        continue;
      }

      if (skippedOneCharacter) {
        return false;
      }

      skippedOneCharacter = true;
      longIndex += 1;
    }

    return true;
  }

  static bool containsEveryHours(String text, int hours) {
    return extractEveryHours(text) == hours;
  }

  static int? extractEveryHours(String text) {
    if (isAsNeededInstruction(text) || requiresManualScheduleReview(text)) {
      return null;
    }

    return _extractEveryHourInterval(normalizeInstruction(text));
  }

  static bool isAsNeededInstruction(String instructions) {
    final text = normalizeInstruction(instructions);

    return _containsAsNeeded(text, _compactText(text));
  }

  static bool requiresManualScheduleReview(String instructions) {
    final text = normalizeInstruction(instructions);

    if (text.isEmpty) {
      return false;
    }

    return _requiresManualScheduleReview(text, _compactText(text));
  }

  static bool hasVariableDoseAmount(String instructions) {
    final text = normalizeInstruction(instructions);

    if (text.isEmpty) {
      return false;
    }

    if (text.contains("half") ||
        text.contains("1/2") ||
        text.contains("0.5") ||
        text.contains("1.5") ||
        text.contains("½") ||
        text.contains("nửa") ||
        text.contains("nua")) {
      return true;
    }

    return RegExp(
          r'\b\d{1,2}\s*(to|or)\s*\d{1,2}\s*(tablet|tablets|capsule|capsules|pill|pills|tab|tabs|cap|caps|drop|drops|puff|puffs|patch|patches|viên|vien)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(one|two|three|four|một|mot|hai|ba|bốn|bon)\s*(to|or|hoặc|hoac)\s*(one|two|three|four|một|mot|hai|ba|bốn|bon)\s*(tablet|tablets|capsule|capsules|pill|pills|tab|tabs|cap|caps|drop|drops|puff|puffs|patch|patches|viên|vien)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b\d{1,2}\s+\d{1,2}\s*(tablet|tablets|capsule|capsules|pill|pills|tab|tabs|cap|caps|drop|drops|puff|puffs|patch|patches|viên|vien)\b',
          caseSensitive: false,
        ).hasMatch(text);
  }

  static bool hasRecognizableSchedule(String instructions) {
    final text = normalizeInstruction(instructions);

    if (text.isEmpty) {
      return false;
    }

    final compact = _compactText(text);

    return _containsAsNeeded(text, compact) ||
        _requiresManualScheduleReview(text, compact) ||
        _extractEveryHourInterval(text) != null ||
        _extractExplicitTimes(text).isNotEmpty ||
        _extractNamedScheduleTimes(text, compact).isNotEmpty ||
        _extractDailyFrequency(text, compact) != null ||
        _containsBreakfastLunchDinner(text, compact) ||
        _containsWithMeals(text, compact) ||
        _containsDaily(text, compact);
  }

  static String selectScheduleDirections({
    required String instructions,
    required String notes,
  }) {
    final cleanInstructions = instructions.trim();
    final cleanNotes = notes.trim();

    bool hasAutomaticTimes(String value) {
      return value.isNotEmpty &&
          generateReminderTimesFromInstructions(value).isNotEmpty;
    }

    bool isMeaningfulAsNeededDirection(String value) {
      return value.isNotEmpty && isAsNeededInstruction(value);
    }

    if (hasAutomaticTimes(cleanInstructions) ||
        isMeaningfulAsNeededDirection(cleanInstructions)) {
      return cleanInstructions;
    }

    if (hasAutomaticTimes(cleanNotes) ||
        isMeaningfulAsNeededDirection(cleanNotes)) {
      return cleanNotes;
    }

    if (hasRecognizableSchedule(cleanInstructions)) {
      return cleanInstructions;
    }

    if (hasRecognizableSchedule(cleanNotes)) {
      return cleanNotes;
    }

    return cleanInstructions.isNotEmpty ? cleanInstructions : cleanNotes;
  }

  static String combineDoseDirections({
    required String instructions,
    required String notes,
  }) {
    final cleanInstructions = instructions.trim();
    final cleanNotes = notes.trim();

    if (cleanInstructions.isEmpty) return cleanNotes;
    if (cleanNotes.isEmpty) return cleanInstructions;
    if (cleanInstructions.toLowerCase() == cleanNotes.toLowerCase()) {
      return cleanInstructions;
    }

    return "$cleanInstructions $cleanNotes";
  }

  static List<TimeOfDay> _extractExplicitTimes(String text) {
    final normalizedText = text
        .replaceAll(RegExp(r'\ba\.?\s*m\.?\b'), "am")
        .replaceAll(RegExp(r'\bp\.?\s*m\.?\b'), "pm")
        .replaceAll(RegExp(r'\s+'), " ")
        .trim();

    final times = <TimeOfDay>[];

    final militaryTimePattern = RegExp(
      r'(\b(at|around|about|lúc|luc|and|or|và|va)\s+|[,;&@]\s*)([01]\d|2[0-3])([0-5]\d)\b',
      caseSensitive: false,
    );

    for (final match in militaryTimePattern.allMatches(normalizedText)) {
      final hour = int.tryParse(match.group(3) ?? "");
      final minute = int.tryParse(match.group(4) ?? "");

      if (hour == null || minute == null) {
        continue;
      }

      times.add(TimeOfDay(hour: hour, minute: minute));
    }

    final vietnameseContextHourPattern = RegExp(
      r'\b(lúc|luc|vào|vao)\s*(\d{1,2})\s*(giờ|gio)\b(?!\s*[0-5]?\d\b)',
      caseSensitive: false,
    );

    for (final match in vietnameseContextHourPattern.allMatches(
      normalizedText,
    )) {
      final hour = int.tryParse(match.group(2) ?? "");

      if (hour == null || hour < 0 || hour > 23) {
        continue;
      }

      times.add(TimeOfDay(hour: hour, minute: 0));
    }

    final hasVietnameseHourContext = RegExp(
      r'\b(lúc|luc|vào|vao)\b',
      caseSensitive: false,
    ).hasMatch(normalizedText);

    if (hasVietnameseHourContext) {
      final additionalVietnameseHourPattern = RegExp(
        r'\b(\d{1,2})\s*(giờ|gio)\b(?!\s*[0-5]?\d\b)',
        caseSensitive: false,
      );

      for (final match in additionalVietnameseHourPattern.allMatches(
        normalizedText,
      )) {
        final hour = int.tryParse(match.group(1) ?? "");

        if (hour == null || hour < 0 || hour > 23) {
          continue;
        }

        times.add(TimeOfDay(hour: hour, minute: 0));
      }
    }

    final vietnameseHourMinutePattern = RegExp(
      r'\b(\d{1,2})\s*(h|g|giờ|gio)\s*([0-5]?\d)\s*(phút|phut)?\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)?\b',
      caseSensitive: false,
    );

    for (final match in vietnameseHourMinutePattern.allMatches(
      normalizedText,
    )) {
      final hour = int.tryParse(match.group(1) ?? "");
      final minute = int.tryParse(match.group(3) ?? "");
      final period = match.group(5) ?? "";

      if (hour == null || minute == null) {
        continue;
      }

      final convertedHour = period.trim().isEmpty
          ? hour
          : _convertVietnameseHour(hour, period);

      if (convertedHour >= 0 &&
          convertedHour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        times.add(TimeOfDay(hour: convertedHour, minute: minute));
      }
    }

    final vietnameseSpecificTimePattern = RegExp(
      r'\b(\d{1,2})\s*(giờ|gio|g)\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)\b',
      caseSensitive: false,
    );

    for (final match in vietnameseSpecificTimePattern.allMatches(
      normalizedText,
    )) {
      final hour = int.tryParse(match.group(1) ?? "");
      final period = match.group(3) ?? "";

      if (hour == null) {
        continue;
      }

      final convertedHour = _convertVietnameseHour(hour, period);

      if (convertedHour >= 0 && convertedHour <= 23) {
        times.add(TimeOfDay(hour: convertedHour, minute: 0));
      }
    }

    final vietnameseHOnlyPattern = RegExp(
      r'\b(\d{1,2})\s*(h|g)\s*(sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)?\b',
      caseSensitive: false,
    );

    for (final match in vietnameseHOnlyPattern.allMatches(normalizedText)) {
      final hour = int.tryParse(match.group(1) ?? "");
      final period = match.group(3) ?? "";

      if (hour == null) {
        continue;
      }

      final convertedHour = period.trim().isEmpty
          ? hour
          : _convertVietnameseHour(hour, period);

      if (convertedHour >= 0 && convertedHour <= 23) {
        times.add(TimeOfDay(hour: convertedHour, minute: 0));
      }
    }

    final timeWithMinutePattern = RegExp(
      r'\b([01]?\d|2[0-3])\s*[:.]\s*([0-5]\d)\s*(am|pm)?\b',
      caseSensitive: false,
    );

    for (final match in timeWithMinutePattern.allMatches(normalizedText)) {
      final hour = int.tryParse(match.group(1) ?? "");
      final minute = int.tryParse(match.group(2) ?? "");
      final period = match.group(3);

      if (hour == null || minute == null) {
        continue;
      }

      final convertedHour = _convertHourWithPeriod(hour, period);

      if (convertedHour >= 0 && convertedHour <= 23) {
        times.add(TimeOfDay(hour: convertedHour, minute: minute));
      }
    }

    final hourOnlyAmPmPattern = RegExp(
      r'\b(1[0-2]|0?[1-9])\s*(am|pm)\b',
      caseSensitive: false,
    );

    for (final match in hourOnlyAmPmPattern.allMatches(normalizedText)) {
      final hour = int.tryParse(match.group(1) ?? "");
      final period = match.group(2);

      if (hour == null) {
        continue;
      }

      final convertedHour = _convertHourWithPeriod(hour, period);

      if (convertedHour >= 0 && convertedHour <= 23) {
        times.add(TimeOfDay(hour: convertedHour, minute: 0));
      }
    }

    final englishNamedTimePattern = RegExp(
      r'\b(\d{1,2})\s*(in the\s*)?(morning|afternoon|evening|night|noon|bedtime)\b',
      caseSensitive: false,
    );

    for (final match in englishNamedTimePattern.allMatches(normalizedText)) {
      final hour = int.tryParse(match.group(1) ?? "");
      final period = match.group(3) ?? "";

      if (hour == null) {
        continue;
      }

      final convertedHour = _convertEnglishNamedHour(hour, period);

      if (convertedHour >= 0 && convertedHour <= 23) {
        times.add(TimeOfDay(hour: convertedHour, minute: 0));
      }
    }

    return removeDuplicateTimes(times);
  }

  static int _convertHourWithPeriod(int hour, String? period) {
    if (period == null || period.trim().isEmpty) {
      return hour;
    }

    final cleanPeriod = period.toLowerCase();

    if (cleanPeriod == "am") {
      if (hour == 12) {
        return 0;
      }

      return hour;
    }

    if (cleanPeriod == "pm") {
      if (hour == 12) {
        return 12;
      }

      return hour + 12;
    }

    return hour;
  }

  static int _convertVietnameseHour(int hour, String period) {
    final cleanPeriod = period.toLowerCase();

    if (cleanPeriod.contains("sáng") || cleanPeriod.contains("sang")) {
      if (hour == 12) {
        return 0;
      }

      return hour;
    }

    if (cleanPeriod.contains("trưa") || cleanPeriod.contains("trua")) {
      if (hour < 12) {
        return hour + 12;
      }

      return hour;
    }

    if (cleanPeriod.contains("chiều") ||
        cleanPeriod.contains("chieu") ||
        cleanPeriod.contains("tối") ||
        cleanPeriod.contains("toi")) {
      if (hour < 12) {
        return hour + 12;
      }

      return hour;
    }

    if (cleanPeriod.contains("đêm") || cleanPeriod.contains("dem")) {
      if (hour == 12) {
        return 0;
      }

      if (hour < 12) {
        return hour + 12;
      }

      return hour;
    }

    return hour;
  }

  static int _convertEnglishNamedHour(int hour, String period) {
    final cleanPeriod = period.toLowerCase();

    if (cleanPeriod.contains("morning")) {
      if (hour == 12) {
        return 0;
      }

      return hour;
    }

    if (cleanPeriod.contains("noon")) {
      return 12;
    }

    if (cleanPeriod.contains("afternoon") ||
        cleanPeriod.contains("evening") ||
        cleanPeriod.contains("night") ||
        cleanPeriod.contains("bedtime")) {
      if (hour < 12) {
        return hour + 12;
      }

      return hour;
    }

    return hour;
  }

  static String _compactText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9à-ỹ]'), '');
  }

  static List<TimeOfDay> _sortTimesChronologically(List<TimeOfDay> times) {
    final sortedTimes = List<TimeOfDay>.from(times);

    sortedTimes.sort((a, b) {
      final aMinutes = a.hour * 60 + a.minute;
      final bMinutes = b.hour * 60 + b.minute;

      return aMinutes.compareTo(bMinutes);
    });

    return sortedTimes;
  }

  static List<TimeOfDay> _timesForDailyFrequency(
    int frequency, {
    required bool takeWithMeals,
  }) {
    if (takeWithMeals && frequency <= 3) {
      return SchedulePreferences.mealTimesForFrequency(frequency);
    }

    switch (frequency) {
      case 1:
        return [SchedulePreferences.breakfastTime];
      case 2:
        return [
          SchedulePreferences.breakfastTime,
          SchedulePreferences.dinnerTime,
        ];
      case 3:
        return const [
          TimeOfDay(hour: 8, minute: 0),
          TimeOfDay(hour: 14, minute: 0),
          TimeOfDay(hour: 20, minute: 0),
        ];
      case 4:
        return const [
          TimeOfDay(hour: 6, minute: 0),
          TimeOfDay(hour: 12, minute: 0),
          TimeOfDay(hour: 18, minute: 0),
          TimeOfDay(hour: 22, minute: 0),
        ];
      case 5:
        return const [
          TimeOfDay(hour: 6, minute: 0),
          TimeOfDay(hour: 10, minute: 0),
          TimeOfDay(hour: 14, minute: 0),
          TimeOfDay(hour: 18, minute: 0),
          TimeOfDay(hour: 22, minute: 0),
        ];
      case 6:
        return const [
          TimeOfDay(hour: 6, minute: 0),
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 12, minute: 0),
          TimeOfDay(hour: 15, minute: 0),
          TimeOfDay(hour: 18, minute: 0),
          TimeOfDay(hour: 21, minute: 0),
        ];
      default:
        return [SchedulePreferences.breakfastTime];
    }
  }

  static bool _containsBeforeMeal(String text, String compact) {
    return text.contains("before meal") ||
        text.contains("before a meal") ||
        text.contains("before meals") ||
        RegExp(
          r'\bbefore (the )?(breakfast|lunch|dinner|supper|morning meal|midday meal|evening meal)\b',
        ).hasMatch(text) ||
        text.contains("before food") ||
        text.contains("before eat") ||
        text.contains("before eating") ||
        text.contains("empty stomach") ||
        RegExp(
          r'\btrước (bữa )?(sáng|trưa|tối)\b|\btruoc (bua )?(sang|trua|toi)\b',
        ).hasMatch(text) ||
        text.contains("trước ăn") ||
        text.contains("truoc an") ||
        text.contains("trước bữa ăn") ||
        text.contains("truoc bua an") ||
        _hasSpacedAbbreviation(text, "ac") ||
        compact.contains("beforemeal") ||
        compact.contains("beforefood") ||
        compact.contains("beforeeat") ||
        compact.contains("truocan") ||
        compact.contains("truocbuaan");
  }

  static bool _containsAfterMeal(String text, String compact) {
    return text.contains("after meal") ||
        text.contains("after a meal") ||
        text.contains("after meals") ||
        RegExp(
          r'\bafter (the )?(breakfast|lunch|dinner|supper|morning meal|midday meal|evening meal)\b',
        ).hasMatch(text) ||
        text.contains("after food") ||
        text.contains("after eat") ||
        text.contains("after eating") ||
        RegExp(
          r'\bsau (bữa )?(sáng|trưa|tối)\b|\bsau (bua )?(sang|trua|toi)\b',
        ).hasMatch(text) ||
        text.contains("sau ăn") ||
        text.contains("sau an") ||
        text.contains("sau bữa ăn") ||
        text.contains("sau bua an") ||
        _hasSpacedAbbreviation(text, "pc") ||
        compact.contains("aftermeal") ||
        compact.contains("afterfood") ||
        compact.contains("aftereat") ||
        compact.contains("sauan") ||
        compact.contains("saubuaan");
  }

  static List<TimeOfDay> _applyMealTimingOffset(
    List<TimeOfDay> times,
    String text,
    String compact,
  ) {
    if (!_containsWithMeals(text, compact)) {
      return times;
    }

    var offset = 0;

    if (_containsBeforeMeal(text, compact)) {
      offset = -SchedulePreferences.beforeMealMinutes;
    } else if (_containsAfterMeal(text, compact)) {
      offset = SchedulePreferences.afterMealMinutes;
    }

    if (offset == 0) {
      return times;
    }

    return _sortTimesChronologically(
      removeDuplicateTimes(
        times.map((time) => SchedulePreferences.shift(time, offset)).toList(),
      ),
    );
  }

  static int? _extractDailyFrequency(String text, String compact) {
    if (_containsFourTimesDaily(text, compact)) {
      return 4;
    }

    if (_containsThreeTimesDaily(text, compact)) {
      return 3;
    }

    if (_containsTwiceDaily(text, compact)) {
      return 2;
    }

    final englishNumberMatch = RegExp(
      r'\b([1-6])\s*(x|times?)\s*(daily|a day|per day|each day|every day)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (englishNumberMatch != null) {
      return int.tryParse(englishNumberMatch.group(1) ?? "");
    }

    final englishWordMatch = RegExp(
      r'\b(one|two|three|four|five|six)\s+times?\s*(daily|a day|per day|each day|every day)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (englishWordMatch != null) {
      return _wordToDoseAmount(englishWordMatch.group(1) ?? "");
    }

    final vietnameseNumberMatch = RegExp(
      r'\b([1-6])\s*(lần|lan)\s*(mỗi ngày|moi ngay|một ngày|mot ngay|trong ngày|trong ngay|ngày|ngay)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (vietnameseNumberMatch != null) {
      return int.tryParse(vietnameseNumberMatch.group(1) ?? "");
    }

    final vietnameseReverseMatch = RegExp(
      r'\b(mỗi ngày|moi ngay|ngày|ngay)\s*([1-6])\s*(lần|lan)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (vietnameseReverseMatch != null) {
      return int.tryParse(vietnameseReverseMatch.group(2) ?? "");
    }

    final compactVietnameseMatch = RegExp(
      r'(moingay|ngay)([1-6])(lan|lần)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (compactVietnameseMatch != null) {
      return int.tryParse(compactVietnameseMatch.group(2) ?? "");
    }

    if (text.contains("once daily") ||
        text.contains("once a day") ||
        text.contains("once per day") ||
        text.contains("one time daily") ||
        text.contains("one time a day") ||
        text.contains("1 time daily") ||
        text.contains("1 time a day") ||
        text.contains("1x daily") ||
        text.contains("1x a day") ||
        _hasSpacedAbbreviation(text, "qd") ||
        _hasSpacedAbbreviation(text, "qday") ||
        text.contains("một lần mỗi ngày") ||
        text.contains("mot lan moi ngay") ||
        text.contains("1 lần mỗi ngày") ||
        text.contains("1 lan moi ngay") ||
        text.contains("eachday") ||
        text.contains("everyday") ||
        compact.contains("ngay1lan") ||
        compact.contains("moingay1lan") ||
        compact.contains("eachday") ||
        compact.contains("everyday") ||
        compact.contains("onceaday") ||
        compact.contains("onceperday")) {
      return 1;
    }

    return null;
  }

  static List<TimeOfDay> _extractNamedScheduleTimes(
    String text,
    String compact,
  ) {
    final times = <TimeOfDay>[];

    void addTime(int hour, [int minute = 0]) {
      times.add(TimeOfDay(hour: hour, minute: minute));
    }

    final hasMidnight =
        _hasWord(text, "midnight") ||
        text.contains("nửa đêm") ||
        text.contains("nua dem") ||
        compact.contains("nuadem");

    final hasBreakfast =
        text.contains("breakfast") ||
        text.contains("morning meal") ||
        text.contains("bữa sáng") ||
        text.contains("bua sang") ||
        compact.contains("buasang");

    final hasMorning =
        _hasWord(text, "morning") ||
        _hasSpacedAbbreviation(text, "qam") ||
        text.contains("buổi sáng") ||
        text.contains("buoi sang") ||
        text.contains("mỗi sáng") ||
        text.contains("moi sang") ||
        compact.contains("buoisang") ||
        compact.contains("moisang");

    final hasLunch =
        text.contains("lunch") ||
        _hasWord(text, "noon") ||
        _hasWord(text, "midday") ||
        text.contains("bữa trưa") ||
        text.contains("bua trua") ||
        text.contains("buổi trưa") ||
        text.contains("buoi trua") ||
        compact.contains("buatrua") ||
        compact.contains("buoitrua");

    final hasAfternoon =
        _hasWord(text, "afternoon") ||
        text.contains("buổi chiều") ||
        text.contains("buoi chieu") ||
        compact.contains("buoichieu");

    final hasDinner =
        text.contains("dinner") ||
        text.contains("supper") ||
        text.contains("evening meal") ||
        text.contains("bữa tối") ||
        text.contains("bua toi") ||
        compact.contains("buatoi");

    final hasEvening =
        !hasDinner &&
        (_hasWord(text, "evening") ||
            _hasSpacedAbbreviation(text, "qpm") ||
            text.contains("buổi tối") ||
            text.contains("buoi toi") ||
            compact.contains("buoitoi"));

    final hasBedtime =
        text.contains("bedtime") ||
        text.contains("at bed time") ||
        _hasSpacedAbbreviation(text, "qhs") ||
        text.contains("trước khi ngủ") ||
        text.contains("truoc khi ngu") ||
        text.contains("khi đi ngủ") ||
        text.contains("khi di ngu") ||
        compact.contains("truockhingu") ||
        compact.contains("khidingu");

    final hasNight =
        !hasMidnight &&
        !hasDinner &&
        !hasEvening &&
        (_hasWord(text, "night") ||
            text.contains("nightly") ||
            text.contains("mỗi tối") ||
            text.contains("moi toi") ||
            text.contains("mỗi đêm") ||
            text.contains("moi dem") ||
            compact.contains("moitoi") ||
            compact.contains("moidem"));

    if (hasMidnight) {
      addTime(0);
    }

    if (hasBreakfast || hasMorning) {
      times.add(
        hasBreakfast
            ? SchedulePreferences.breakfastTime
            : SchedulePreferences.wakeTime,
      );
    }

    if (hasLunch) {
      times.add(SchedulePreferences.lunchTime);
    }

    if (hasAfternoon) {
      addTime(14);
    }

    if (hasDinner) {
      times.add(SchedulePreferences.dinnerTime);
    }

    if (hasEvening) {
      addTime(20);
    }

    if (hasBedtime || hasNight) {
      times.add(SchedulePreferences.bedtime);
    }

    return _sortTimesChronologically(removeDuplicateTimes(times));
  }

  static bool _containsAllMealsInstruction(String text, String compact) {
    return text.contains("with meals") ||
        text.contains("at meals") ||
        text.contains("each meal") ||
        text.contains("every meal") ||
        text.contains("after each meal") ||
        text.contains("before each meal") ||
        text.contains("after every meal") ||
        text.contains("before every meal") ||
        text.contains("three meals") ||
        text.contains("3 meals") ||
        text.contains("mỗi bữa ăn") ||
        text.contains("moi bua an") ||
        text.contains("các bữa ăn") ||
        text.contains("cac bua an") ||
        text.contains("3 bữa") ||
        text.contains("3 bua") ||
        compact.contains("aftereachmeal") ||
        compact.contains("beforeeachmeal") ||
        compact.contains("aftereverymeal") ||
        compact.contains("beforeeverymeal") ||
        compact.contains("moibuaan") ||
        compact.contains("cacbuaan");
  }

  static bool _requiresManualScheduleReview(String text, String compact) {
    final hasNegatedDoseAction =
        text.contains("do not take") ||
        text.contains("do not use") ||
        text.contains("do not give") ||
        text.contains("do not administer") ||
        text.contains("stop taking") ||
        text.contains("stop using") ||
        text.contains("hold this medication") ||
        text.contains("hold medication") ||
        text.contains("không uống") ||
        text.contains("khong uong") ||
        text.contains("không dùng") ||
        text.contains("khong dung") ||
        text.contains("ngưng uống") ||
        text.contains("ngung uong") ||
        text.contains("ngừng dùng") ||
        text.contains("ngung dung") ||
        compact.contains("donottake") ||
        compact.contains("donotuse") ||
        compact.contains("stoptaking") ||
        compact.contains("holdmedication") ||
        compact.contains("khonguong") ||
        compact.contains("khongdung") ||
        compact.contains("ngunguong") ||
        compact.contains("ngungdung");

    final hasIntervalRange =
        RegExp(
          r'\b(every|each)\s*\d{1,2}\s*(to|or)?\s+\d{1,2}\s*(hour|hours|hr|hrs|h)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(mỗi|moi|cứ|cu|cách|cach)\s*\d{1,2}\s*(đến|den|tới|toi|hoặc|hoac)?\s+\d{1,2}\s*(giờ|gio|tiếng|tieng)\b',
          caseSensitive: false,
        ).hasMatch(text);

    final hasDailyFrequencyRange = RegExp(
      r'\b\d{1,2}\s*(to|or)?\s+\d{1,2}\s*(times?|x|lần|lan)\s*(daily|a day|per day|mỗi ngày|moi ngay|ngày|ngay)\b',
      caseSensitive: false,
    ).hasMatch(text);

    final englishMealChoice = RegExp(
      r'\b(after|before)(?:\s+(?:eat|eating|food|(?:a\s+)?meals?))?\s+(?:or|and\s*/\s*or)\s+(after|before)\b',
      caseSensitive: false,
    ).firstMatch(text);
    final vietnameseMealChoice = RegExp(
      r'\b(sau|trước|truoc)(?:\s+(?:khi\s+)?(?:ăn|an|bữa\s+ăn|bua\s+an))?\s+(?:hoặc|hoac)\s+(sau|trước|truoc)\b',
      caseSensitive: false,
    ).firstMatch(text);
    final hasConflictingMealTiming =
        (englishMealChoice != null &&
            englishMealChoice.group(1)?.toLowerCase() !=
                englishMealChoice.group(2)?.toLowerCase()) ||
        (vietnameseMealChoice != null &&
            _normalizeVietnameseMealSide(vietnameseMealChoice.group(1)) !=
                _normalizeVietnameseMealSide(vietnameseMealChoice.group(2)));

    final hasMaximumOnly =
        text.contains("up to") ||
        text.contains("no more than") ||
        text.contains("not more than") ||
        text.contains("do not exceed") ||
        text.contains("maximum") ||
        text.contains("max dose") ||
        text.contains("tối đa") ||
        text.contains("toi da") ||
        text.contains("không quá") ||
        text.contains("khong qua") ||
        compact.contains("toida") ||
        compact.contains("khongqua");

    final hasWhileAwake =
        text.contains("while awake") ||
        text.contains("during waking hours") ||
        text.contains("when awake") ||
        text.contains("khi thức") ||
        text.contains("khi thuc") ||
        compact.contains("khithuc");

    final hasNonDailyFrequency =
        text.contains("every other day") ||
        text.contains("alternate days") ||
        text.contains("every 2 days") ||
        text.contains("every two days") ||
        RegExp(
          r'\bevery\s+([2-9]|[1-9]\d+)\s+(days?|weeks?|months?)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        text.contains("once a week") ||
        text.contains("once weekly") ||
        text.contains("every week") ||
        _hasWord(text, "weekly") ||
        text.contains("once a month") ||
        text.contains("every month") ||
        _hasWord(text, "monthly") ||
        text.contains("cách ngày") ||
        text.contains("cach ngay") ||
        text.contains("mỗi tuần") ||
        text.contains("moi tuan") ||
        text.contains("mỗi tháng") ||
        text.contains("moi thang") ||
        RegExp(
          r'\b(mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|sundays?)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(mỗi|moi)\s+([2-9]|[1-9]\d+)\s+(ngày|ngay|tuần|tuan|tháng|thang)\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\b(thứ|thu)\s*(hai|ba|tư|tu|năm|nam|sáu|sau|bảy|bay|[2-7])\b|\b(chủ nhật|chu nhat)\b',
          caseSensitive: false,
        ).hasMatch(text);

    final hasChangingSchedule =
        text.contains("taper") ||
        text.contains("increase the dose") ||
        text.contains("decrease the dose") ||
        RegExp(
          r'\bfor\s+\d+\s+days?\s+then\b',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          r'\bthen\s+(take|use|apply|insert|uống|uong|dùng|dung)\b',
          caseSensitive: false,
        ).hasMatch(text);

    final saysAsDirected =
        text.contains("as directed") ||
        text.contains("as instructed") ||
        text.contains("theo chỉ dẫn") ||
        text.contains("theo chi dan") ||
        text.contains("theo hướng dẫn") ||
        text.contains("theo huong dan");

    final detectedEveryHourInterval = _extractEveryHourInterval(text);
    final detectedDailyFrequency = _extractDailyFrequency(text, compact);
    final detectedExplicitTimes = _extractExplicitTimes(text);
    final detectedNamedTimes = _extractNamedScheduleTimes(text, compact);
    final detectedSpecificTimes = removeDuplicateTimes([
      ...detectedExplicitTimes,
      ...detectedNamedTimes,
    ]);
    final hasNonRepeatingDailyInterval =
        detectedEveryHourInterval != null &&
        24 % detectedEveryHourInterval != 0;
    final hasConflictingFrequency =
        detectedDailyFrequency != null &&
        detectedSpecificTimes.isNotEmpty &&
        detectedDailyFrequency != detectedSpecificTimes.length;

    final hasAnotherScheduleSignal =
        detectedEveryHourInterval != null ||
        detectedExplicitTimes.isNotEmpty ||
        detectedNamedTimes.isNotEmpty ||
        detectedDailyFrequency != null ||
        _containsWithMeals(text, compact) ||
        _containsDaily(text, compact);

    final hasDoseAction = RegExp(
      r'\b(take|give|administer|swallow|inhale|instill|inject|insert|use|apply|chew|dissolve|uống|uong|dùng|dung|đặt|dat|nhỏ|nho|xịt|xit|bôi|boi|tiêm|tiem)\b',
      caseSensitive: false,
    ).hasMatch(text);

    final hasIncompleteDirection =
        hasDoseAction && !hasAnotherScheduleSignal && !saysAsDirected;

    return hasNegatedDoseAction ||
        hasIntervalRange ||
        hasDailyFrequencyRange ||
        hasConflictingMealTiming ||
        hasMaximumOnly ||
        hasWhileAwake ||
        hasNonDailyFrequency ||
        hasChangingSchedule ||
        hasNonRepeatingDailyInterval ||
        hasConflictingFrequency ||
        hasIncompleteDirection ||
        (saysAsDirected && !hasAnotherScheduleSignal);
  }

  static String _normalizeVietnameseMealSide(String? value) {
    final cleanValue = value?.toLowerCase().trim() ?? "";

    if (cleanValue == "trước" || cleanValue == "truoc") {
      return "before";
    }

    if (cleanValue == "sau") {
      return "after";
    }

    return cleanValue;
  }

  static bool _hasSpacedAbbreviation(String text, String abbreviation) {
    final characters = abbreviation
        .toLowerCase()
        .split("")
        .map((character) => RegExp.escape(character))
        .join(r'[\s.]*');

    return RegExp(
      r'(^|[^a-z0-9à-ỹ])' + characters + r'([^a-z0-9à-ỹ]|$)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool _containsAsNeeded(String text, String compact) {
    return text.contains("as needed") ||
        text.contains("as necessary") ||
        text.contains("if needed") ||
        text.contains("when needed") ||
        text.contains("as required") ||
        text.contains("if required") ||
        text.contains("when required") ||
        text.contains("only when needed") ||
        text.contains("prn") ||
        text.contains("khi cần") ||
        text.contains("khi can") ||
        text.contains("nếu cần") ||
        text.contains("neu can") ||
        text.contains("khi có triệu chứng") ||
        text.contains("khi co trieu chung") ||
        compact.contains("khican") ||
        compact.contains("neucan") ||
        compact.contains("khicotrieuchung");
  }

  static bool _containsTwiceDaily(String text, String compact) {
    return text.contains("twice daily") ||
        text.contains("twice a day") ||
        text.contains("twice per day") ||
        text.contains("2 times daily") ||
        text.contains("2 times a day") ||
        text.contains("2 times per day") ||
        text.contains("two times daily") ||
        text.contains("two times a day") ||
        text.contains("two times per day") ||
        text.contains("2x daily") ||
        text.contains("2x a day") ||
        _hasSpacedAbbreviation(text, "bid") ||
        _hasSpacedAbbreviation(text, "bd") ||
        text.contains("2 lần") ||
        text.contains("2 lan") ||
        text.contains("hai lần") ||
        text.contains("hai lan") ||
        text.contains("hai lần mỗi ngày") ||
        text.contains("hai lan moi ngay") ||
        compact.contains("ngay2lan") ||
        compact.contains("ngày2lần") ||
        compact.contains("moingay2lan");
  }

  static bool _containsThreeTimesDaily(String text, String compact) {
    return text.contains("3 times daily") ||
        text.contains("3 times a day") ||
        text.contains("3 times per day") ||
        text.contains("three times daily") ||
        text.contains("three times a day") ||
        text.contains("three times per day") ||
        text.contains("3x daily") ||
        text.contains("3x a day") ||
        _hasSpacedAbbreviation(text, "tid") ||
        _hasSpacedAbbreviation(text, "tds") ||
        text.contains("3 lần") ||
        text.contains("3 lan") ||
        text.contains("ba lần") ||
        text.contains("ba lan") ||
        compact.contains("ngay3lan") ||
        compact.contains("ngày3lần") ||
        compact.contains("moingay3lan");
  }

  static bool _containsFourTimesDaily(String text, String compact) {
    return text.contains("4 times daily") ||
        text.contains("4 times a day") ||
        text.contains("4 times per day") ||
        text.contains("four times daily") ||
        text.contains("four times a day") ||
        text.contains("four times per day") ||
        text.contains("4x daily") ||
        text.contains("4x a day") ||
        _hasSpacedAbbreviation(text, "qid") ||
        text.contains("4 lần") ||
        text.contains("4 lan") ||
        text.contains("bốn lần") ||
        text.contains("bon lan") ||
        compact.contains("ngay4lan") ||
        compact.contains("ngày4lần") ||
        compact.contains("moingay4lan");
  }

  static int? _extractEveryHourInterval(String text) {
    final everyHourMatch = RegExp(
      r'\b(every|each)\s*(\d{1,2})\s*(hour|hours|hr|hrs|h)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (everyHourMatch != null) {
      final interval = int.tryParse(everyHourMatch.group(2) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final compact = _compactText(text);
    final compactEveryHourMatch = RegExp(
      r'(every|each)(\d{1,2})(hour|hours|hr|hrs|h)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (compactEveryHourMatch != null) {
      final interval = int.tryParse(compactEveryHourMatch.group(2) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final everyWordHourMatch = RegExp(
      r'\b(every|each)\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(hour|hours|hr|hrs|hourly)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (everyWordHourMatch != null) {
      final interval = _wordToHourInterval(everyWordHourMatch.group(2) ?? "");

      if (interval != null) {
        return interval;
      }
    }

    final qHourMatch = RegExp(
      r'\bq\s*(\d{1,2})\s*(h|hr|hrs|hour|hours)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (qHourMatch != null) {
      final interval = int.tryParse(qHourMatch.group(1) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final compactQHourMatch = RegExp(
      r'q(\d{1,2})(h|hr|hrs|hour|hours)',
      caseSensitive: false,
    ).firstMatch(compact);

    if (compactQHourMatch != null) {
      final interval = int.tryParse(compactQHourMatch.group(1) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final qNoUnitMatch = RegExp(
      r'\bq\s?([468]|12|24)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (qNoUnitMatch != null) {
      final interval = int.tryParse(qNoUnitMatch.group(1) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final vietnameseHourMatch = RegExp(
      r'(mỗi|moi|cứ|cu|cách|cach)(\s+nhau)?\s*(\d{1,2})\s*(giờ|gio|tiếng|tieng|h)',
      caseSensitive: false,
    ).firstMatch(text);

    if (vietnameseHourMatch != null) {
      final interval = int.tryParse(vietnameseHourMatch.group(3) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final vietnameseReverseHourMatch = RegExp(
      r'\b(\d{1,2})\s*(giờ|gio|tiếng|tieng|h)\s*/?\s*(một lần|mot lan|mỗi lần|moi lan|lần|lan)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (vietnameseReverseHourMatch != null) {
      final interval = int.tryParse(vietnameseReverseHourMatch.group(1) ?? "");

      if (interval != null && interval > 0 && interval <= 24) {
        return interval;
      }
    }

    final vietnameseWordHourMatch = RegExp(
      r'\b(mỗi|moi|cứ|cu|cách|cach)\s*(mười hai|muoi hai|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|tám|tam|chín|chin|mười|muoi)\s*(giờ|gio|tiếng|tieng)\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (vietnameseWordHourMatch != null) {
      final interval = _vietnameseWordToHourInterval(
        vietnameseWordHourMatch.group(2) ?? "",
      );

      if (interval != null) {
        return interval;
      }
    }

    return null;
  }

  static int? _wordToHourInterval(String word) {
    switch (word.toLowerCase().trim()) {
      case "one":
        return 1;
      case "two":
        return 2;
      case "three":
        return 3;
      case "four":
        return 4;
      case "five":
        return 5;
      case "six":
        return 6;
      case "seven":
        return 7;
      case "eight":
        return 8;
      case "nine":
        return 9;
      case "ten":
        return 10;
      case "eleven":
        return 11;
      case "twelve":
        return 12;
      default:
        return null;
    }
  }

  static int? _vietnameseWordToHourInterval(String word) {
    switch (word.toLowerCase().trim()) {
      case "một":
      case "mot":
        return 1;
      case "hai":
        return 2;
      case "ba":
        return 3;
      case "bốn":
      case "bon":
        return 4;
      case "năm":
      case "nam":
        return 5;
      case "sáu":
      case "sau":
        return 6;
      case "bảy":
      case "bay":
        return 7;
      case "tám":
      case "tam":
        return 8;
      case "chín":
      case "chin":
        return 9;
      case "mười":
      case "muoi":
        return 10;
      case "mười hai":
      case "muoi hai":
        return 12;
      default:
        return null;
    }
  }

  static bool _containsBreakfastLunchDinner(String text, String compact) {
    final hasBreakfast =
        text.contains("breakfast") ||
        text.contains("morning meal") ||
        compact.contains("buoisang") ||
        compact.contains("bữasáng");

    final hasLunch =
        text.contains("lunch") ||
        compact.contains("buoitrua") ||
        compact.contains("bữatrưa");

    final hasDinner =
        text.contains("dinner") ||
        text.contains("supper") ||
        compact.contains("buoitoi") ||
        compact.contains("bữatối");

    return hasBreakfast && hasLunch && hasDinner;
  }

  static bool _containsMorningAndNight(String text, String compact) {
    final hasMorning =
        text.contains("morning") ||
        text.contains("breakfast") ||
        text.contains("sáng") ||
        text.contains("sang") ||
        compact.contains("moisang") ||
        compact.contains("mỗisáng");

    final hasNight =
        text.contains("night") ||
        text.contains("bedtime") ||
        text.contains("tối") ||
        text.contains("toi") ||
        compact.contains("moitoi") ||
        compact.contains("mỗitối");

    return hasMorning && hasNight;
  }

  static bool _containsMorningAndEvening(String text, String compact) {
    final hasMorning =
        text.contains("morning") ||
        text.contains("breakfast") ||
        text.contains("sáng") ||
        text.contains("sang") ||
        compact.contains("moisang") ||
        compact.contains("mỗisáng");

    final hasEvening =
        text.contains("evening") ||
        text.contains("dinner") ||
        text.contains("chiều") ||
        text.contains("chieu") ||
        compact.contains("buoichieu") ||
        compact.contains("buổichiều");

    return hasMorning && hasEvening;
  }

  static bool _containsWithMeals(String text, String compact) {
    return _containsBeforeMeal(text, compact) ||
        _containsAfterMeal(text, compact) ||
        text.contains("with meals") ||
        text.contains("with a meal") ||
        text.contains("with food") ||
        text.contains("mealtime") ||
        text.contains("meal time") ||
        text.contains("bụng đói") ||
        text.contains("bung doi") ||
        compact.contains("withameal") ||
        compact.contains("bungdoi");
  }

  static bool _containsNightTime(String text, String compact) {
    return text.contains("night") ||
        text.contains("nightly") ||
        text.contains("bedtime") ||
        text.contains("evening") ||
        text.contains("dinner") ||
        _hasSpacedAbbreviation(text, "qhs") ||
        _hasSpacedAbbreviation(text, "qpm") ||
        compact.contains("everynight") ||
        compact.contains("bedtime") ||
        compact.contains("moitoi") ||
        compact.contains("mỗitối") ||
        compact.contains("moidem") ||
        compact.contains("mỗidem") ||
        text.contains("tối") ||
        text.contains("toi") ||
        text.contains("đêm") ||
        text.contains("dem");
  }

  static bool _containsNoonTime(String text, String compact) {
    return text.contains("noon") ||
        text.contains("lunch") ||
        text.contains("midday") ||
        text.contains("trưa") ||
        text.contains("trua") ||
        compact.contains("buoitrua") ||
        compact.contains("buổitrưa");
  }

  static bool _containsMorningTime(String text, String compact) {
    return text.contains("morning") ||
        text.contains("breakfast") ||
        _hasSpacedAbbreviation(text, "qam") ||
        compact.contains("everymorning") ||
        text.contains("sáng") ||
        text.contains("sang") ||
        compact.contains("moisang") ||
        compact.contains("mỗisáng");
  }

  static bool _containsDaily(String text, String compact) {
    return text.contains("daily") ||
        text.contains("every day") ||
        text.contains("each day") ||
        text.contains("everyday") ||
        text.contains("eachday") ||
        text.contains("once daily") ||
        text.contains("once a day") ||
        text.contains("once per day") ||
        text.contains("one time daily") ||
        text.contains("one time a day") ||
        text.contains("1 time daily") ||
        text.contains("1 time a day") ||
        text.contains("1x daily") ||
        text.contains("1x a day") ||
        _hasSpacedAbbreviation(text, "qd") ||
        text.contains("q day") ||
        text.contains("mỗi ngày") ||
        text.contains("moi ngay") ||
        text.contains("ngày 1") ||
        text.contains("ngay 1") ||
        compact.contains("eachday") ||
        compact.contains("everyday") ||
        compact.contains("onceaday") ||
        compact.contains("onceperday") ||
        compact.contains("moingay") ||
        compact.contains("mỗingày");
  }

  static bool _hasWord(String text, String word) {
    final escapedWord = RegExp.escape(word.toLowerCase());

    return RegExp(
      r'(^|[^a-z0-9à-ỹ])' + escapedWord + r'([^a-z0-9à-ỹ]|$)',
      caseSensitive: false,
    ).hasMatch(text);
  }
}
