class DateHelper {
  static String dateToString(DateTime date) {
    final year = date.year.toString().padLeft(4, "0");
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");

    return "$year-$month-$day";
  }

  static String todayString() {
    return dateToString(DateTime.now());
  }

  static DateTime dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime? parseMedicationDate(String value) {
    if (value.trim().isEmpty) {
      return null;
    }

    try {
      final parsedDate = DateTime.parse(value.trim());

      return dateOnly(parsedDate);
    } catch (e) {
      return null;
    }
  }

  static String displayMedicationDate(String value) {
    final date = parseMedicationDate(value);

    if (date == null) {
      return "--";
    }

    return displayDate(date);
  }

  static String displayDate(DateTime date) {
    final month = date.month.toString().padLeft(2, "0");
    final day = date.day.toString().padLeft(2, "0");
    final year = date.year.toString().padLeft(4, "0");

    return "$month/$day/$year";
  }

  static bool isBeforeToday(DateTime date) {
    return dateOnly(date).isBefore(dateOnly(DateTime.now()));
  }

  static bool isAfterToday(DateTime date) {
    return dateOnly(date).isAfter(dateOnly(DateTime.now()));
  }

  static bool isToday(DateTime date) {
    return dateOnly(date).isAtSameMomentAs(dateOnly(DateTime.now()));
  }

  static int treatmentTotalDays({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final start = dateOnly(startDate);
    final end = dateOnly(endDate);

    final days = end.difference(start).inDays + 1;

    if (days < 1) {
      return 1;
    }

    return days;
  }

  static int treatmentCompletedDays({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final today = dateOnly(DateTime.now());
    final start = dateOnly(startDate);
    final end = dateOnly(endDate);

    if (today.isBefore(start)) {
      return 0;
    }

    if (today.isAfter(end)) {
      return treatmentTotalDays(startDate: start, endDate: end);
    }

    return today.difference(start).inDays + 1;
  }

  static int treatmentRemainingDays({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final total = treatmentTotalDays(startDate: startDate, endDate: endDate);

    final completed = treatmentCompletedDays(
      startDate: startDate,
      endDate: endDate,
    );

    final remaining = total - completed;

    if (remaining < 0) {
      return 0;
    }

    return remaining;
  }

  static double treatmentProgress({
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final total = treatmentTotalDays(startDate: startDate, endDate: endDate);

    if (total <= 0) {
      return 0;
    }

    final completed = treatmentCompletedDays(
      startDate: startDate,
      endDate: endDate,
    );

    return (completed / total).clamp(0.0, 1.0);
  }
}
