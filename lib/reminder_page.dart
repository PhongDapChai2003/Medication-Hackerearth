import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'date_helper.dart';
import 'dose_history_page.dart';
import 'medication.dart';
import 'medication_details_page.dart';
import 'medication_storage.dart';
import 'route_transitions.dart';
import 'smooth_action_button.dart';
import 'time_helper.dart';

class ReminderPage extends StatefulWidget {
  final Medication medication;
  final int medicationIndex;
  final String? initialDoseTime;

  const ReminderPage({
    super.key,
    required this.medication,
    this.medicationIndex = -1,
    this.initialDoseTime,
  });

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  late Medication medication;
  final ScrollController pageScrollController = ScrollController();
  final Map<String, GlobalKey> doseCardKeys = <String, GlobalKey>{};

  bool isSaving = false;
  bool medicationUnavailable = false;
  final Set<String> savingDoseRecordKeys = <String>{};
  static const int doseWindowMinutes = 120;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    medication = widget.medication;
    MedicationStorage.dataRevision.addListener(refreshMedicationFromLocal);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await autoAdjustDefaultReminderTime();
      await focusInitialDose();
    });
  }

  GlobalKey doseCardKey(TimeOfDay time) {
    final storedTime = TimeHelper.timeToString(time);
    return doseCardKeys.putIfAbsent(storedTime, GlobalKey.new);
  }

  Future<void> focusInitialDose() async {
    final initialDoseTime = widget.initialDoseTime?.trim() ?? "";

    if (initialDoseTime.isEmpty || !mounted) return;

    await WidgetsBinding.instance.endOfFrame;
    final targetContext = doseCardKeys[initialDoseTime]?.currentContext;

    if (!mounted || targetContext == null || !targetContext.mounted) return;

    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(refreshMedicationFromLocal);
    pageScrollController.dispose();
    super.dispose();
  }

  Future<void> refreshMedicationFromLocal() async {
    final medications = await MedicationStorage.loadCurrentLocalMedications();
    final index = medications.indexWhere((item) => item.id == medication.id);

    if (!mounted) return;
    if (index < 0) {
      setState(() => medicationUnavailable = true);
      return;
    }
    setState(() {
      medication = medications[index];
      medicationUnavailable = false;
    });
  }

  List<TimeOfDay> get reminderTimes {
    if (medication.reminderTimes.isNotEmpty) {
      return medication.reminderTimes
          .map((time) => TimeHelper.stringToTime(time))
          .toList();
    }

    return TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirectionText,
    );
  }

  String get scheduleDirectionText {
    return TimeHelper.selectScheduleDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );
  }

  bool get scheduleDetectedFromNotes {
    final notes = medication.notes.trim();

    return notes.isNotEmpty && scheduleDirectionText == notes;
  }

  String get doseDirectionText {
    return TimeHelper.combineDoseDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );
  }

  bool get isAsNeededMedication {
    return TimeHelper.isAsNeededInstruction(scheduleDirectionText);
  }

  bool get needsManualScheduleReview {
    final directions = scheduleDirectionText.trim();

    if (directions.isEmpty || isAsNeededMedication) {
      return false;
    }

    return TimeHelper.requiresManualScheduleReview(directions) ||
        !TimeHelper.hasRecognizableSchedule(directions);
  }

  bool get hasVariableDoseAmount {
    return TimeHelper.hasVariableDoseAmount(doseDirectionText);
  }

  int? get fixedHourInterval {
    if (TimeHelper.isAsNeededInstruction(scheduleDirectionText)) {
      return null;
    }

    return TimeHelper.extractEveryHours(scheduleDirectionText);
  }

  bool get hasFixedHourInterval {
    return fixedHourInterval != null;
  }

  int get doseAmount {
    return TimeHelper.getDoseAmountFromInstructions(doseDirectionText);
  }

  bool shouldAutoReplaceDefaultReminderTime() {
    if (medication.reminderTimes.length != 1) {
      return false;
    }

    if (medication.reminderTimes.first != "08:00") {
      return false;
    }

    final generatedTimes = TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirectionText,
    );

    if (generatedTimes.isEmpty) {
      return false;
    }

    if (generatedTimes.length != 1) {
      return true;
    }

    return TimeHelper.timeToString(generatedTimes.first) != "08:00";
  }

  bool shouldRemoveDefaultReminderTime() {
    if (medication.reminderTimes.length != 1 ||
        medication.reminderTimes.first != "08:00") {
      return false;
    }

    return isAsNeededMedication || needsManualScheduleReview;
  }

  Future<void> autoAdjustDefaultReminderTime() async {
    if (shouldRemoveDefaultReminderTime()) {
      final updatedMedication = medication.copyWith(
        reminderTimes: const [],
        doseStatus: "notTakenYet",
        doseStatusDate: "",
      );

      setState(() {
        medication = updatedMedication;
      });

      await saveMedicationChanges();
      return;
    }

    if (!shouldAutoReplaceDefaultReminderTime()) {
      return;
    }

    final generatedTimes = getGeneratedReminderTimeStrings();

    if (generatedTimes.isEmpty) {
      return;
    }

    final updatedMedication = medication.copyWith(
      reminderTimes: generatedTimes,
      doseStatus: "notTakenYet",
      doseStatusDate: "",
    );

    setState(() {
      medication = updatedMedication;
    });

    await saveMedicationChanges();
  }

  List<String> getGeneratedReminderTimeStrings() {
    final intervalHours = fixedHourInterval;
    final currentTimes = reminderTimes;

    final generatedTimes = intervalHours != null && currentTimes.isNotEmpty
        ? TimeHelper.generateTimesByIntervalFromStart(
            intervalHours,
            currentTimes.first,
          )
        : TimeHelper.generateReminderTimesFromInstructions(
            scheduleDirectionText,
          );

    final generated = generatedTimes.map((time) {
      return TimeHelper.timeToString(time);
    }).toList();

    final seen = <String>{};
    final cleanTimes = <String>[];

    for (final time in generated) {
      if (seen.add(time)) {
        cleanTimes.add(time);
      }
    }

    return cleanTimes;
  }

  List<({int index, TimeOfDay time})> get todayReminderEntries {
    final times = reminderTimes;
    final today = DateTime.now();
    final treatmentStartDate = DateHelper.parseMedicationDate(
      medication.startDate,
    );
    final entries = <({int index, TimeOfDay time})>[];

    for (int index = 0; index < times.length; index++) {
      if (TimeHelper.reminderOccursOnDate(
        times: times,
        reminderIndex: index,
        date: today,
        treatmentStartDate: treatmentStartDate,
      )) {
        entries.add((index: index, time: times[index]));
      }
    }

    return entries;
  }

  DateTime getDoseDateTimeForTime(TimeOfDay time) {
    final now = DateTime.now();

    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  String doseRecordKey(TimeOfDay time) {
    final doseDateTime = getDoseDateTimeForTime(time);

    return TimeHelper.doseRecordKeyForDate(doseDateTime, time);
  }

  String asNeededDoseRecordKey() {
    final now = DateTime.now();

    return "${DateHelper.dateToString(now)}|asNeeded|${now.millisecondsSinceEpoch}";
  }

  String getDoseStatus(TimeOfDay time) {
    final key = doseRecordKey(time);
    final savedStatus = medication.doseRecords[key];

    if (savedStatus == "taken" ||
        savedStatus == "missed" ||
        savedStatus == "skipped") {
      return savedStatus!;
    }

    final now = DateTime.now();
    final scheduledDateTime = getDoseDateTimeForTime(time);
    final endOfWindow = scheduledDateTime.add(
      const Duration(minutes: doseWindowMinutes),
    );

    if (now.isBefore(scheduledDateTime)) {
      return "scheduled";
    }

    if (now.isAfter(endOfWindow)) {
      return "late";
    }

    return "due";
  }

  String getMainDoseStatus(Map<String, String> records) {
    final today = DateHelper.todayString();
    final times = todayReminderEntries.map((entry) => entry.time).toList();

    if (times.isEmpty) {
      final todayTakenCount = countTodayTakenRecords(records);

      if (todayTakenCount > 0) {
        return "taken";
      }

      return "notTakenYet";
    }

    int takenCount = 0;
    int missedCount = 0;

    for (final time in times) {
      final key = "$today|${TimeHelper.timeToString(time)}";
      final status = records[key];

      if (status == "taken") {
        takenCount++;
      }

      if (status == "missed" || status == "skipped") {
        missedCount++;
      }
    }

    if (times.isNotEmpty && takenCount == times.length) {
      return "taken";
    }

    if (missedCount > 0) {
      return "missed";
    }

    return "notTakenYet";
  }

  Future<bool> saveMedicationChanges() async {
    if (medication.id.trim().isEmpty) {
      return false;
    }

    final updated = await MedicationStorage.updateMedicationById(
      medication.id,
      medication,
    );
    if (!updated && mounted) {
      setState(() => medicationUnavailable = true);
    }
    return updated;
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  int getTotalQuantityForPage() {
    return parseQuantityNumber(medication.quantity);
  }

  int getRemainingQuantityForPage() {
    final totalQuantity = getTotalQuantityForPage();

    if (totalQuantity <= 0) {
      return 0;
    }

    if (medication.remainingQuantity.trim().isEmpty) {
      return totalQuantity;
    }

    return parseQuantityNumber(medication.remainingQuantity);
  }

  bool isOutOfMedicineForPage() {
    final totalQuantity = getTotalQuantityForPage();

    if (totalQuantity <= 0) {
      return false;
    }

    return getRemainingQuantityForPage() <= 0;
  }

  bool isLowQuantityForPage() {
    final totalQuantity = getTotalQuantityForPage();

    if (totalQuantity <= 0) {
      return false;
    }

    final remainingQuantity = getRemainingQuantityForPage();
    final percentRemaining = remainingQuantity / totalQuantity;

    return percentRemaining <= 0.05;
  }

  Future<bool> confirmRefillPickup() async {
    final language = AppLanguage.currentLanguage.value;

    final name = medication.name.trim().isEmpty
        ? (language == "en" ? "this medication" : "thuốc này")
        : medication.name.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            language == "en"
                ? "Did you already pick up the refill?"
                : "Bạn đã nhận thuốc refill chưa?",
          ),
          content: Text(
            language == "en"
                ? "Only tap Yes after you already got $name from the pharmacy. The app will set the remaining quantity back to full."
                : "Chỉ bấm Có sau khi bạn đã nhận $name từ nhà thuốc. Ứng dụng sẽ đặt số lượng còn lại về đầy.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(language == "en" ? "Cancel" : "Huỷ"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                language == "en" ? "Yes, I Got It" : "Có, Đã Nhận",
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> markMedicationRefilled() async {
    if (isSaving) {
      return;
    }

    final language = AppLanguage.currentLanguage.value;
    final totalQuantity = medication.quantity.trim();

    if (totalQuantity.isEmpty || parseQuantityNumber(totalQuantity) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "Please enter total quantity first."
                : "Vui lòng nhập tổng số lượng trước.",
          ),
        ),
      );
      return;
    }

    final confirmed = await confirmRefillPickup();

    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }

    final previousMedication = medication;

    setState(() {
      isSaving = true;
      medication = medication.copyWith(remainingQuantity: totalQuantity);
    });

    try {
      await saveMedicationChanges();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            language == "en"
                ? "Refill saved. Remaining quantity is full now."
                : "Đã lưu refill. Số lượng thuốc đã đầy lại.",
          ),
          action: SnackBarAction(
            label: language == "en" ? "Undo" : "Hoàn tác",
            onPressed: () async {
              setState(() {
                medication = previousMedication;
              });

              await saveMedicationChanges();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    language == "en"
                        ? "Refill change undone."
                        : "Đã hoàn tác thay đổi refill.",
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<bool> confirmDoseMark(TimeOfDay time, String status) async {
    final language = AppLanguage.currentLanguage.value;
    final isTaken = status == "taken";
    final outOfMedicineWarning = isTaken && isOutOfMedicineForPage();

    final name = medication.name.trim().isEmpty
        ? (language == "en" ? "this medication" : "thuốc này")
        : medication.name.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            outOfMedicineWarning
                ? (language == "en"
                      ? "Medicine is out. Did you really take it?"
                      : "Thuốc đã hết. Bạn thật sự đã uống?")
                : isTaken
                ? (language == "en"
                      ? "Mark this dose as taken?"
                      : "Đánh dấu liều này đã uống?")
                : (language == "en"
                      ? "Mark this dose as missed?"
                      : "Đánh dấu liều này bỏ lỡ?"),
          ),
          content: Text(
            outOfMedicineWarning
                ? (language == "en"
                      ? "The app says $name is OUT OF MEDICINE.\n\nOnly tap Yes if you really took this dose.\n\nTime: ${TimeHelper.formatTimeForDisplay(time)}\nDose amount: $doseAmount"
                      : "Ứng dụng báo $name ĐÃ HẾT THUỐC.\n\nChỉ bấm Có nếu bạn thật sự đã uống liều này.\n\nGiờ: ${TimeHelper.formatTimeForDisplay(time)}\nSố lượng mỗi liều: $doseAmount")
                : (language == "en"
                      ? "$name at ${TimeHelper.formatTimeForDisplay(time)}\nDose amount: $doseAmount"
                      : "$name lúc ${TimeHelper.formatTimeForDisplay(time)}\nSố lượng mỗi liều: $doseAmount"),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(language == "en" ? "Cancel" : "Huỷ"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                outOfMedicineWarning
                    ? (language == "en"
                          ? "Yes, I Really Took It"
                          : "Có, Tôi Đã Uống")
                    : (language == "en" ? "Yes" : "Có"),
                style: TextStyle(
                  color: isTaken
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<bool> confirmDeleteReminderTime(String displayTime) async {
    final language = AppLanguage.currentLanguage.value;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            language == "en"
                ? "Delete this reminder time?"
                : "Xoá giờ nhắc này?",
          ),
          content: Text(
            language == "en"
                ? "Delete reminder time $displayTime? You can undo after deletion."
                : "Xoá giờ nhắc $displayTime? Bạn có thể hoàn tác sau khi xoá.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(language == "en" ? "Cancel" : "Huỷ"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                language == "en" ? "Delete" : "Xoá",
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  String decreaseRemainingQuantityByDoseAmount() {
    final totalQuantity = parseQuantityNumber(medication.quantity);

    final currentRemaining = medication.remainingQuantity.trim().isEmpty
        ? totalQuantity
        : parseQuantityNumber(medication.remainingQuantity);

    if (currentRemaining <= 0) {
      return medication.remainingQuantity;
    }

    final updatedRemaining = currentRemaining - doseAmount;

    if (updatedRemaining < 0) {
      return "0";
    }

    return updatedRemaining.toString();
  }

  String increaseRemainingQuantityByDoseAmount() {
    return increaseRemainingQuantityBy(doseAmount);
  }

  String increaseRemainingQuantityBy(int amount) {
    final totalQuantity = parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return medication.remainingQuantity;
    }

    final currentRemaining = medication.remainingQuantity.trim().isEmpty
        ? totalQuantity
        : parseQuantityNumber(medication.remainingQuantity);

    final restored = math.min(totalQuantity, currentRemaining + amount);

    return restored.toString();
  }

  int countTodayTakenRecords(Map<String, String> records) {
    final today = DateHelper.todayString();
    int count = 0;

    records.forEach((key, value) {
      if (key.startsWith("$today|") && value == "taken") {
        count++;
      }
    });

    return count;
  }

  Map<String, String> removeTodayDoseRecords(Map<String, String> records) {
    final today = DateHelper.todayString();
    final updatedRecords = Map<String, String>.from(records);

    updatedRecords.removeWhere((key, value) {
      return key.startsWith("$today|");
    });

    return updatedRecords;
  }

  String statusUndoText(String status) {
    final language = AppLanguage.currentLanguage.value;

    if (status == "taken") {
      return language == "en" ? "Taken" : "Đã uống";
    }

    if (status == "missed") {
      return language == "en" ? "Missed" : "Bỏ lỡ";
    }

    return status;
  }

  Future<void> markAsNeededDoseTaken() async {
    if (isSaving) {
      return;
    }

    final language = AppLanguage.currentLanguage.value;
    final previousMedication = medication;
    final outOfMedicineWarning = isOutOfMedicineForPage();

    final name = medication.name.trim().isEmpty
        ? (language == "en" ? "this medication" : "thuốc này")
        : medication.name.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            outOfMedicineWarning
                ? (language == "en"
                      ? "Medicine is out. Did you really take it?"
                      : "Thuốc đã hết. Bạn thật sự đã uống?")
                : (language == "en"
                      ? "Log this as-needed dose?"
                      : "Ghi nhận liều dùng khi cần?"),
          ),
          content: Text(
            outOfMedicineWarning
                ? (language == "en"
                      ? "The app says $name is OUT OF MEDICINE.\n\nOnly tap Yes if you really took this dose now.\n\nDose amount: $doseAmount."
                      : "Ứng dụng báo $name ĐÃ HẾT THUỐC.\n\nChỉ bấm Có nếu bạn thật sự đã uống liều này bây giờ.\n\nSố lượng mỗi liều: $doseAmount.")
                : (language == "en"
                      ? "Only tap Yes if you actually took this dose now. Dose amount: $doseAmount."
                      : "Chỉ bấm Có nếu bạn thật sự đã uống liều này bây giờ. Số lượng mỗi liều: $doseAmount."),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(language == "en" ? "Cancel" : "Huỷ"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                outOfMedicineWarning
                    ? (language == "en"
                          ? "Yes, I Really Took It"
                          : "Có, Tôi Đã Uống")
                    : (language == "en" ? "Yes" : "Có"),
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final updatedRecords = Map<String, String>.from(medication.doseRecords);
    updatedRecords[asNeededDoseRecordKey()] = "taken";

    final updatedMedication = medication.copyWith(
      remainingQuantity: decreaseRemainingQuantityByDoseAmount(),
      doseRecords: updatedRecords,
      doseStatus: "taken",
      doseStatusDate: DateHelper.todayString(),
    );

    try {
      setState(() {
        medication = updatedMedication;
      });

      await saveMedicationChanges();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            language == "en"
                ? "As-needed dose logged. Dose amount: $doseAmount."
                : "Đã ghi nhận liều dùng khi cần. Số lượng mỗi liều: $doseAmount.",
          ),
          action: SnackBarAction(
            label: language == "en" ? "Undo" : "Hoàn tác",
            onPressed: () async {
              setState(() {
                medication = previousMedication;
              });

              await saveMedicationChanges();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    language == "en"
                        ? "As-needed dose restored."
                        : "Đã hoàn tác liều dùng khi cần.",
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> markDose(TimeOfDay time, String status) async {
    if (isSaving) {
      return;
    }

    final key = doseRecordKey(time);

    if (savingDoseRecordKeys.contains(key)) {
      return;
    }

    final currentStatus = getDoseStatus(time);

    if (currentStatus == "scheduled") {
      showNotAvailableMessage();
      return;
    }

    if (status == "taken" &&
        currentStatus != "due" &&
        currentStatus != "late") {
      showNotAvailableMessage();
      return;
    }

    if (status == "missed" &&
        currentStatus != "due" &&
        currentStatus != "late") {
      showNotAvailableMessage();
      return;
    }

    final language = AppLanguage.currentLanguage.value;

    setState(() {
      savingDoseRecordKeys.add(key);
    });

    Medication? previousMedication;

    try {
      final confirmed = await confirmDoseMark(time, status);

      if (!confirmed || !mounted) {
        return;
      }

      previousMedication = medication;
      final previousSavedStatus = previousMedication.doseRecords[key] ?? "";
      final optimisticMedication = MedicationStorage.applyDoseRecordChange(
        medication: previousMedication,
        recordKey: key,
        status: status,
      );

      setState(() {
        medication = optimisticMedication;
      });

      final updatedMedication = await MedicationStorage.applyDoseAction(
        medicationId: medication.id,
        recordKey: key,
        status: status,
      );

      if (!mounted) {
        return;
      }

      if (updatedMedication == null) {
        setState(() {
          medication = previousMedication!;
        });
        return;
      }

      setState(() {
        medication = updatedMedication;
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();

      final undoController = messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            language == "en"
                ? "${TimeHelper.formatTimeForDisplay(time)} marked as ${statusUndoText(status)}. Dose amount: $doseAmount."
                : "Đã đánh dấu ${TimeHelper.formatTimeForDisplay(time)} là ${statusUndoText(status)}. Số lượng mỗi liều: $doseAmount.",
          ),
          action: SnackBarAction(
            label: language == "en" ? "Undo" : "Hoàn tác",
            onPressed: () async {
              messenger.hideCurrentSnackBar(
                reason: SnackBarClosedReason.action,
              );

              if (savingDoseRecordKeys.contains(key)) {
                return;
              }

              if (mounted) {
                setState(() {
                  savingDoseRecordKeys.add(key);
                });
              }

              try {
                final restoredMedication =
                    previousSavedStatus == "taken" ||
                        previousSavedStatus == "missed" ||
                        previousSavedStatus == "skipped"
                    ? await MedicationStorage.applyDoseAction(
                        medicationId: medication.id,
                        recordKey: key,
                        status: previousSavedStatus,
                      )
                    : await MedicationStorage.removeDoseAction(
                        medicationId: medication.id,
                        recordKey: key,
                      );

                if (mounted && restoredMedication != null) {
                  setState(() {
                    medication = restoredMedication;
                  });
                }
              } finally {
                if (mounted) {
                  setState(() {
                    savingDoseRecordKeys.remove(key);
                  });
                }
              }
            },
          ),
        ),
      );
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2), undoController.close),
      );
    } catch (_) {
      if (mounted) {
        if (previousMedication != null) {
          setState(() {
            medication = previousMedication!;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              language == "en"
                  ? "This dose could not be saved. Please try again."
                  : "Không thể lưu liều này. Vui lòng thử lại.",
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          savingDoseRecordKeys.remove(key);
        });
      }
    }
  }

  void showNotAvailableMessage() {
    final language = AppLanguage.currentLanguage.value;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == "en"
              ? "This dose is not due yet."
              : "Liều này chưa tới giờ uống.",
        ),
      ),
    );
  }

  Future<TimeOfDay?> pickCustomerTime(TimeOfDay initialTime) async {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      helpText: AppLanguage.currentLanguage.value == "en"
          ? "Enter reminder time"
          : "Nhập giờ nhắc",
    );
  }

  TimeOfDay calculateFirstDoseTimeForEditedInterval({
    required TimeOfDay selectedTime,
    required int editedIndex,
    required int intervalHours,
  }) {
    final selectedMinutes = selectedTime.hour * 60 + selectedTime.minute;
    final intervalOffsetMinutes = editedIndex * intervalHours * 60;

    var firstDoseMinutes =
        (selectedMinutes - intervalOffsetMinutes) % (24 * 60);

    if (firstDoseMinutes < 0) {
      firstDoseMinutes += 24 * 60;
    }

    return TimeOfDay(
      hour: firstDoseMinutes ~/ 60,
      minute: firstDoseMinutes % 60,
    );
  }

  Future<void> applyFixedIntervalSchedule({
    required TimeOfDay selectedTime,
    int editedIndex = 0,
  }) async {
    if (isSaving) {
      return;
    }

    final intervalHours = fixedHourInterval;

    if (intervalHours == null) {
      return;
    }

    final firstDoseTime = calculateFirstDoseTimeForEditedInterval(
      selectedTime: selectedTime,
      editedIndex: editedIndex,
      intervalHours: intervalHours,
    );

    final fixedTimes =
        TimeHelper.generateTimesByIntervalFromStart(
          intervalHours,
          firstDoseTime,
        ).map((time) {
          return TimeHelper.timeToString(time);
        }).toList();

    if (fixedTimes.isEmpty) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final language = AppLanguage.currentLanguage.value;
      final updatedMedication = medication.copyWith(
        reminderTimes: fixedTimes,
      );

      setState(() {
        medication = updatedMedication;
      });

      await saveMedicationChanges();

      if (!mounted) {
        return;
      }

      final timeText = fixedTimes
          .map((time) {
            return TimeHelper.formatStoredTimeForDisplay(time);
          })
          .join(", ");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "Every $intervalHours hours from ${TimeHelper.formatTimeForDisplay(firstDoseTime)}: $timeText"
                : "Mỗi $intervalHours giờ từ ${TimeHelper.formatTimeForDisplay(firstDoseTime)}: $timeText",
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> setFixedIntervalFirstDoseTime() async {
    final times = reminderTimes;
    final initialTime = times.isEmpty ? TimeOfDay.now() : times.first;
    final selectedTime = await pickCustomerTime(initialTime);

    if (selectedTime == null) {
      return;
    }

    await applyFixedIntervalSchedule(selectedTime: selectedTime);
  }

  Future<void> addReminderTime() async {
    if (hasFixedHourInterval) {
      await setFixedIntervalFirstDoseTime();
      return;
    }

    final selectedTime = await pickCustomerTime(TimeOfDay.now());

    if (selectedTime == null) {
      return;
    }

    final updatedTimes = reminderTimes
        .map((time) => TimeHelper.timeToString(time))
        .toList();

    final newTimeString = TimeHelper.timeToString(selectedTime);

    if (!updatedTimes.contains(newTimeString)) {
      updatedTimes.add(newTimeString);
    }

    updatedTimes.sort();

    setState(() {
      medication = medication.copyWith(reminderTimes: updatedTimes);
    });

    await saveMedicationChanges();
  }

  Future<void> editReminderTime(int index) async {
    final times = reminderTimes;

    if (index < 0 || index >= times.length) {
      return;
    }

    final selectedTime = await pickCustomerTime(times[index]);

    if (selectedTime == null) {
      return;
    }

    if (hasFixedHourInterval) {
      await applyFixedIntervalSchedule(
        selectedTime: selectedTime,
        editedIndex: index,
      );
      return;
    }

    final updatedTimes = times
        .map((time) => TimeHelper.timeToString(time))
        .toList();

    updatedTimes[index] = TimeHelper.timeToString(selectedTime);
    updatedTimes.sort();

    setState(() {
      medication = medication.copyWith(
        reminderTimes: updatedTimes,
      );
    });

    await saveMedicationChanges();
  }

  Future<void> deleteReminderTime(int index) async {
    if (isSaving) {
      return;
    }

    final language = AppLanguage.currentLanguage.value;

    final times = reminderTimes
        .map((time) => TimeHelper.timeToString(time))
        .toList();

    if (index < 0 || index >= times.length) {
      return;
    }

    final deletedTime = times[index];
    final displayTime = TimeHelper.formatStoredTimeForDisplay(deletedTime);

    final confirmed = await confirmDeleteReminderTime(displayTime);

    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }

    final previousMedication = medication;

    setState(() {
      isSaving = true;
    });

    times.removeAt(index);

    final updatedRecords = removeTodayDoseRecords(medication.doseRecords);

    final updatedMedication = medication.copyWith(
      reminderTimes: times,
      doseRecords: updatedRecords,
      doseStatus: "notTakenYet",
      doseStatusDate: "",
    );

    try {
      setState(() {
        medication = updatedMedication;
      });

      await saveMedicationChanges();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            language == "en"
                ? "Deleted reminder time $displayTime."
                : "Đã xoá giờ nhắc $displayTime.",
          ),
          action: SnackBarAction(
            label: language == "en" ? "Undo" : "Hoàn tác",
            onPressed: () async {
              setState(() {
                medication = previousMedication;
              });

              await saveMedicationChanges();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    language == "en"
                        ? "Reminder time restored."
                        : "Đã khôi phục giờ nhắc.",
                  ),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> editMedicationDetails() async {
    if (widget.medicationIndex < 0) {
      return;
    }

    final didSave = await Navigator.push(
      context,
      slowPageRoute(
        builder: (context) => MedicationDetailsPage(
          medication: medication,
          medicationIndex: widget.medicationIndex,
        ),
      ),
    );

    if (didSave == true) {
      final updatedMedications = await MedicationStorage.loadMedications();
      final updatedIndex = updatedMedications.indexWhere(
        (item) => item.id == medication.id,
      );

      if (updatedIndex >= 0) {
        setState(() {
          medication = updatedMedications[updatedIndex];
        });
      }
    }
  }

  Future<void> openDoseHistoryPage() async {
    final didChange = await Navigator.push<bool>(
      context,
      slowPageRoute(
        builder: (context) => DoseHistoryPage(
          medication: medication,
          medicationIndex: widget.medicationIndex,
        ),
      ),
    );

    if (didChange == true) {
      final updatedMedications = await MedicationStorage.loadMedications();

      if (!mounted) {
        return;
      }

      final updatedIndex = updatedMedications.indexWhere(
        (item) => item.id == medication.id,
      );
      if (updatedIndex < 0) {
        setState(() => medicationUnavailable = true);
        return;
      }

      setState(() => medication = updatedMedications[updatedIndex]);
    }
  }

  DateTime? getNextDoseDateTimeForMedication() {
    final now = DateTime.now();
    final dueCandidates = <DateTime>[];
    final scheduledCandidates = <DateTime>[];

    for (final entry in todayReminderEntries) {
      final time = entry.time;
      final status = getDoseStatus(time);
      final scheduledDateTime = getDoseDateTimeForTime(time);

      if (status == "due") {
        dueCandidates.add(scheduledDateTime);
      } else if (status == "scheduled") {
        scheduledCandidates.add(scheduledDateTime);
      }
    }

    if (dueCandidates.isNotEmpty) {
      dueCandidates.sort();
      return dueCandidates.first;
    }

    if (scheduledCandidates.isNotEmpty) {
      scheduledCandidates.sort();
      return scheduledCandidates.first;
    }

    final tomorrow = DateHelper.dateOnly(now.add(const Duration(days: 1)));
    final treatmentEndDate = DateHelper.parseMedicationDate(medication.endDate);

    if (treatmentEndDate != null && tomorrow.isAfter(treatmentEndDate)) {
      return null;
    }

    final times = reminderTimes;
    final treatmentStartDate = DateHelper.parseMedicationDate(
      medication.startDate,
    );
    final tomorrowCandidates = <DateTime>[];

    for (int index = 0; index < times.length; index++) {
      if (!TimeHelper.reminderOccursOnDate(
        times: times,
        reminderIndex: index,
        date: tomorrow,
        treatmentStartDate: treatmentStartDate,
      )) {
        continue;
      }

      final time = times[index];
      tomorrowCandidates.add(
        DateTime(
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          time.hour,
          time.minute,
        ),
      );
    }

    tomorrowCandidates.sort();
    return tomorrowCandidates.isEmpty ? null : tomorrowCandidates.first;
  }

  String getNextDoseText() {
    final language = AppLanguage.currentLanguage.value;

    if (isAsNeededMedication) {
      return language == "en" ? "As needed" : "Khi cần";
    }

    final nextDose = getNextDoseDateTimeForMedication();

    if (nextDose == null) {
      return "--";
    }

    return TimeHelper.formatDateTimeAsDisplayTime(nextDose);
  }

  int countStatus(String status) {
    final times = todayReminderEntries.map((entry) => entry.time).toList();

    if (times.isEmpty) {
      if (status == "taken") {
        return countTodayTakenRecords(medication.doseRecords);
      }

      return 0;
    }

    int count = 0;

    for (final time in times) {
      if (getDoseStatus(time) == status) {
        count++;
      }
    }

    return count;
  }

  double getTreatmentProgress() {
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (startDate == null || endDate == null) {
      return 0;
    }

    return DateHelper.treatmentProgress(startDate: startDate, endDate: endDate);
  }

  String getTreatmentText() {
    final language = AppLanguage.currentLanguage.value;
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (startDate == null) {
      return language == "en"
          ? "No start date selected"
          : "Chưa chọn ngày bắt đầu";
    }

    if (endDate == null) {
      return language == "en"
          ? "Started ${DateHelper.displayMedicationDate(medication.startDate)} • No end date"
          : "Bắt đầu ${DateHelper.displayMedicationDate(medication.startDate)} • Không có ngày kết thúc";
    }

    final completedDays = DateHelper.treatmentCompletedDays(
      startDate: startDate,
      endDate: endDate,
    );

    final totalDays = DateHelper.treatmentTotalDays(
      startDate: startDate,
      endDate: endDate,
    );

    return language == "en"
        ? "$completedDays of $totalDays days completed"
        : "Đã hoàn thành $completedDays trên $totalDays ngày";
  }

  String getQuantityDisplayText() {
    final language = AppLanguage.currentLanguage.value;

    if (medication.quantity.trim().isEmpty) {
      return language == "en" ? "Quantity not entered" : "Chưa nhập số lượng";
    }

    final remaining = medication.remainingQuantity.trim().isEmpty
        ? medication.quantity
        : medication.remainingQuantity;

    if (isOutOfMedicineForPage()) {
      return language == "en"
          ? "OUT OF MEDICINE • Remaining Qty: 0 of ${medication.quantity} • Dose amount: $doseAmount"
          : "ĐÃ HẾT THUỐC • Còn lại: 0 trên ${medication.quantity} • Mỗi liều: $doseAmount";
    }

    return language == "en"
        ? "Remaining Qty: $remaining of ${medication.quantity} • Dose amount: $doseAmount"
        : "Còn lại: $remaining trên ${medication.quantity} • Mỗi liều: $doseAmount";
  }

  @override
  Widget build(BuildContext context) {
    if (medicationUnavailable) {
      return Scaffold(
        appBar: AppBar(
          title: Text(tr("Medication reminder", "Nhắc uống thuốc")),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr(
                "This medication was deleted or is no longer available.",
                "Thuốc này đã bị xoá hoặc không còn khả dụng.",
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final language = AppLanguage.currentLanguage.value;
    final times = reminderTimes;
    final todayEntries = todayReminderEntries;
    final intervalHours = fixedHourInterval;
    final isLowQuantity = isLowQuantityForPage();
    final isOutOfMedicine = isOutOfMedicineForPage();
    final headerDetails = [
      medication.dosage.trim(),
      medication.instructions.trim(),
    ].where((value) => value.isNotEmpty).join(" • ");

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: pageScrollController,
            padding: AppTheme.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: IconButton(
                            tooltip: language == "en" ? "Back" : "Quay lại",
                            onPressed: () {
                              Navigator.pop(context, true);
                            },
                            icon: const Icon(Icons.arrow_back_ios_new_rounded),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: IconButton(
                            tooltip: language == "en"
                                ? "Edit medication"
                                : "Sửa thuốc",
                            onPressed: editMedicationDetails,
                            icon: Icon(
                              Icons.edit_rounded,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      medication.name,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2A3A),
                      ),
                    ),
                    if (headerDetails.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        headerDetails,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF667085),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (isOutOfMedicine) ...[
                      const SizedBox(height: 16),
                      OutOfMedicineTopBanner(
                        pharmacyName: medication.pharmacyName,
                        pharmacyPhone: medication.pharmacyPhone,
                      ),
                    ],
                    const SizedBox(height: 16),
                    DoseSummaryCard(
                      nextDoseText: getNextDoseText(),
                      takenCount: countStatus("taken"),
                      missedCount: countStatus("missed"),
                    ),
                    if (medication.quantity.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      QuantityRemainingCard(
                        text: getQuantityDisplayText(),
                        isOutOfMedicine: isOutOfMedicine,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            times.isEmpty && isAsNeededMedication
                                ? (language == "en"
                                      ? "Take when needed"
                                      : "Dùng khi cần")
                                : AppLanguage.text("reminderTimes"),
                            style: const TextStyle(
                              color: Color(0xFF1E2A3A),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!(times.isEmpty && isAsNeededMedication))
                          TextButton.icon(
                            onPressed: addReminderTime,
                            icon: Icon(
                              intervalHours == null
                                  ? Icons.add_rounded
                                  : Icons.schedule_rounded,
                              color: AppTheme.primaryColor,
                            ),
                            label: Text(
                              intervalHours == null
                                  ? (language == "en" ? "Add" : "Thêm")
                                  : (language == "en"
                                        ? "First dose"
                                        : "Liều đầu"),
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (scheduleDetectedFromNotes ||
                        needsManualScheduleReview ||
                        hasVariableDoseAmount) ...[
                      ScheduleReviewNoticeCard(
                        detectedFromNotes: scheduleDetectedFromNotes,
                        needsManualReview: needsManualScheduleReview,
                        hasVariableDose: hasVariableDoseAmount,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (intervalHours != null && times.isNotEmpty) ...[
                      FixedIntervalScheduleCard(
                        intervalHours: intervalHours,
                        firstDoseTime: times.first,
                        onSetFirstDose: setFixedIntervalFirstDoseTime,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (times.isEmpty && isAsNeededMedication)
                      AsNeededDoseCard(
                        doseAmount: doseAmount,
                        onLogTaken: markAsNeededDoseTaken,
                        onAddTime: addReminderTime,
                      )
                    else if (times.isEmpty)
                      EmptyReminderTimes(onAddTime: addReminderTime)
                    else
                      Column(
                        children: todayEntries.map((entry) {
                          final time = entry.time;
                          final status = getDoseStatus(time);
                          final doseDateTime = getDoseDateTimeForTime(time);
                          final recordKey = doseRecordKey(time);

                          return KeyedSubtree(
                            key: doseCardKey(time),
                            child: DoseTimeCard(
                              time: time,
                              status: status,
                              doseDateTime: doseDateTime,
                              isSaving: savingDoseRecordKeys.contains(
                                recordKey,
                              ),
                              highlighted:
                                  widget.initialDoseTime ==
                                  TimeHelper.timeToString(time),
                              onEdit: () {
                                editReminderTime(entry.index);
                              },
                              onDelete: intervalHours == null
                                  ? () {
                                      deleteReminderTime(entry.index);
                                    }
                                  : null,
                              onMarkTaken: () {
                                markDose(time, "taken");
                              },
                              onMarkMissed: () {
                                markDose(time, "missed");
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    if ((isLowQuantity || isOutOfMedicine) &&
                        medication.quantity.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      RefillActionCard(
                        isLowQuantity: isLowQuantity,
                        isOutOfMedicine: isOutOfMedicine,
                        totalQuantity: medication.quantity,
                        remainingQuantity:
                            medication.remainingQuantity.trim().isEmpty
                            ? medication.quantity
                            : medication.remainingQuantity,
                        pharmacyName: medication.pharmacyName,
                        pharmacyPhone: medication.pharmacyPhone,
                        onMarkRefilled: markMedicationRefilled,
                      ),
                    ],
                    const SizedBox(height: 18),
                    Material(
                      color: Colors.white.withValues(alpha: 0.90),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(
                          color: AppTheme.primaryColor.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          splashColor: AppTheme.primaryColor.withValues(
                            alpha: 0.08,
                          ),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 3,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            16,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppTheme.lightColor,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          title: Text(
                            language == "en" ? "More details" : "Xem thêm",
                            style: const TextStyle(
                              color: Color(0xFF1E2A3A),
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            language == "en"
                                ? "History, settings and treatment information"
                                : "Lịch sử, cài đặt và thông tin điều trị",
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            if (!isAsNeededMedication &&
                                medication.quantity.trim().isNotEmpty) ...[
                              SupplyEstimateCard(
                                totalQuantity: getTotalQuantityForPage(),
                                remainingQuantity:
                                    getRemainingQuantityForPage(),
                                doseAmount: doseAmount,
                                dosesPerDay: times.length,
                                isAsNeededMedication: false,
                                isOutOfMedicine: isOutOfMedicine,
                              ),
                            ],
                            const SizedBox(height: 12),
                            TreatmentCard(
                              progress: getTreatmentProgress(),
                              treatmentText: getTreatmentText(),
                              startDate: medication.startDate,
                              endDate: medication.endDate,
                            ),
                            const SizedBox(height: 12),
                            SmoothActionButton(
                              icon: Icons.history_rounded,
                              label: language == "en"
                                  ? "Dose History"
                                  : "Lịch Sử Uống Thuốc",
                              outlined: true,
                              onPressed: openDoseHistoryPage,
                            ),
                            if (medication.notes.trim().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              NotesCard(notes: medication.notes),
                            ],
                            const SizedBox(height: 12),
                            const SafetyReminderCard(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScheduleReviewNoticeCard extends StatelessWidget {
  final bool detectedFromNotes;
  final bool needsManualReview;
  final bool hasVariableDose;

  const ScheduleReviewNoticeCard({
    super.key,
    required this.detectedFromNotes,
    required this.needsManualReview,
    required this.hasVariableDose,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final messages = <String>[];

    if (detectedFromNotes) {
      messages.add(
        language == "en"
            ? "A schedule was detected in Description/Notes because the Instructions field did not contain a clear schedule."
            : "Ứng dụng đã nhận diện lịch trong phần Mô Tả/Ghi Chú vì ô Hướng Dẫn không có lịch rõ ràng.",
      );
    }

    if (needsManualReview) {
      messages.add(
        language == "en"
            ? "This direction contains a range, maximum limit, conflicting before/after-meal wording, changing dose, while-awake timing, non-daily frequency, or incomplete schedule. The app did not guess the reminder times. Add and verify them manually."
            : "Hướng dẫn có khoảng thời gian, giới hạn tối đa, cách dùng trước/sau bữa ăn bị mâu thuẫn, thay đổi liều, chỉ dùng khi thức, lịch không theo ngày hoặc chưa đủ thông tin. Ứng dụng không tự đoán giờ; hãy thêm và kiểm tra thủ công.",
      );
    }

    if (hasVariableDose) {
      messages.add(
        language == "en"
            ? "The dose amount varies or includes a fraction. Quantity auto-reduction cannot know the exact amount taken, so verify the remaining quantity after marking a dose."
            : "Số lượng mỗi liều thay đổi hoặc có phần lẻ. Tự động trừ số lượng không thể biết liều chính xác, vì vậy hãy kiểm tra số lượng còn lại sau khi đánh dấu.",
      );
    }

    final needsCautionColor = needsManualReview || hasVariableDose;
    final accentColor = needsCautionColor
        ? const Color(0xFFD97706)
        : const Color(0xFF2563EB);
    final backgroundColor = needsCautionColor
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFEFF6FF);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              needsCautionColor
                  ? Icons.rule_folder_rounded
                  : Icons.description_rounded,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsCautionColor
                      ? (language == "en"
                            ? "Review Scanned Directions"
                            : "Kiểm Tra Hướng Dẫn Đã Quét")
                      : (language == "en"
                            ? "Schedule Found in Notes"
                            : "Đã Tìm Thấy Lịch Trong Ghi Chú"),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                ...List.generate(messages.length, (index) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == messages.length - 1 ? 0 : 6,
                    ),
                    child: Text(
                      messages[index],
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FixedIntervalScheduleCard extends StatelessWidget {
  final int intervalHours;
  final TimeOfDay firstDoseTime;
  final VoidCallback onSetFirstDose;

  const FixedIntervalScheduleCard({
    super.key,
    required this.intervalHours,
    required this.firstDoseTime,
    required this.onSetFirstDose,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final firstDoseText = TimeHelper.formatTimeForDisplay(firstDoseTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.lightColor.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.28),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.repeat_rounded, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language == "en"
                          ? "Every $intervalHours hours detected"
                          : "Đã nhận diện mỗi $intervalHours giờ",
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      language == "en"
                          ? "First dose: $firstDoseText"
                          : "Liều đầu: $firstDoseText",
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            language == "en"
                ? "Choose the first dose time and every other reminder will stay exactly $intervalHours hours apart, including overnight. Verify the schedule with the prescription label or pharmacist."
                : "Chọn giờ liều đầu và tất cả giờ nhắc khác sẽ cách nhau đúng $intervalHours giờ, kể cả ban đêm. Hãy kiểm tra lại theo nhãn thuốc hoặc dược sĩ.",
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onSetFirstDose,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
              ),
              icon: const Icon(Icons.access_time_filled_rounded),
              label: Text(
                language == "en"
                    ? "Choose First Dose Time"
                    : "Chọn Giờ Liều Đầu",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhoneCallButton extends StatelessWidget {
  final String phoneNumber;
  final String label;
  final bool inverted;

  const PhoneCallButton({
    super.key,
    required this.phoneNumber,
    required this.label,
    this.inverted = false,
  });

  String get cleanPhoneNumber {
    return phoneNumber.replaceAll(RegExp(r'[^0-9+]'), "");
  }

  Future<void> callPhone(BuildContext context) async {
    final language = AppLanguage.currentLanguage.value;

    if (cleanPhoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "No phone number saved."
                : "Chưa lưu số điện thoại.",
          ),
        ),
      );
      return;
    }

    final uri = Uri(scheme: "tel", path: cleanPhoneNumber);

    final canCall = await canLaunchUrl(uri);

    if (!canCall) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language == "en"
                ? "This device cannot open the phone dialer."
                : "Thiết bị này không mở được trình gọi điện.",
          ),
        ),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = inverted ? Colors.white : const Color(0xFF22C55E);
    final foregroundColor = inverted ? const Color(0xFFEF4444) : Colors.white;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          callPhone(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          minimumSize: const Size.fromHeight(82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_rounded, size: 26, color: foregroundColor),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      phoneNumber,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OutOfMedicineTopBanner extends StatelessWidget {
  final String pharmacyName;
  final String pharmacyPhone;

  const OutOfMedicineTopBanner({
    super.key,
    required this.pharmacyName,
    required this.pharmacyPhone,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final hasName = pharmacyName.trim().isNotEmpty;
    final hasPhone = pharmacyPhone.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  language == "en" ? "OUT OF MEDICINE" : "ĐÃ HẾT THUỐC",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            language == "en"
                ? "This medicine is out. Call for a refill now."
                : "Thuốc này đã hết. Gọi để refill ngay.",
            style: const TextStyle(
              color: Colors.white,
              height: 1.35,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasName || hasPhone) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language == "en" ? "Call:" : "Gọi:",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (hasName) ...[
                    const SizedBox(height: 8),
                    Text(
                      pharmacyName.trim(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (hasPhone) ...[
                    const SizedBox(height: 12),
                    PhoneCallButton(
                      phoneNumber: pharmacyPhone.trim(),
                      label: language == "en"
                          ? "Call Pharmacy"
                          : "Gọi Nhà Thuốc",
                      inverted: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SupplyEstimateCard extends StatelessWidget {
  final int totalQuantity;
  final int remainingQuantity;
  final int doseAmount;
  final int dosesPerDay;
  final bool isAsNeededMedication;
  final bool isOutOfMedicine;

  const SupplyEstimateCard({
    super.key,
    required this.totalQuantity,
    required this.remainingQuantity,
    required this.doseAmount,
    required this.dosesPerDay,
    required this.isAsNeededMedication,
    required this.isOutOfMedicine,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    Color color = AppTheme.primaryColor;
    IconData icon = Icons.event_available_rounded;
    String title = language == "en" ? "Supply Estimate" : "Ước Tính Thuốc Còn";
    String mainText;
    String helperText;

    if (totalQuantity <= 0) {
      mainText = language == "en"
          ? "Quantity not entered"
          : "Chưa nhập số lượng";
      helperText = language == "en"
          ? "Enter total quantity and remaining quantity to estimate days left."
          : "Nhập tổng số lượng và số lượng còn lại để ước tính số ngày còn thuốc.";
      color = AppTheme.primaryColor;
      icon = Icons.inventory_2_rounded;
    } else if (isAsNeededMedication) {
      mainText = language == "en"
          ? "Cannot estimate for as-needed medicine"
          : "Không thể ước tính thuốc dùng khi cần";
      helperText = language == "en"
          ? "This medicine does not have fixed reminder times, so days left depends on how often it is used."
          : "Thuốc này không có giờ uống cố định, nên số ngày còn lại phụ thuộc vào số lần dùng.";
      color = const Color(0xFFF59E0B);
      icon = Icons.info_outline_rounded;
    } else if (dosesPerDay <= 0) {
      mainText = language == "en"
          ? "No fixed dose schedule"
          : "Chưa có lịch uống cố định";
      helperText = language == "en"
          ? "Add reminder times to estimate days left."
          : "Thêm giờ nhắc để ước tính số ngày còn thuốc.";
      color = const Color(0xFFF59E0B);
      icon = Icons.schedule_rounded;
    } else if (remainingQuantity <= 0 || isOutOfMedicine) {
      mainText = language == "en" ? "0 days left" : "Còn 0 ngày";
      helperText = language == "en"
          ? "This medicine is out. Call for a refill now."
          : "Thuốc này đã hết. Gọi để refill ngay.";
      color = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else {
      final dailyUse = math.max(1, doseAmount * dosesPerDay);
      final rawDaysLeft = (remainingQuantity / dailyUse).floor();
      final daysLeft = rawDaysLeft < 1 ? 1 : rawDaysLeft;
      final emptyDate = DateHelper.dateOnly(
        DateTime.now(),
      ).add(Duration(days: daysLeft));

      if (daysLeft <= 3) {
        color = const Color(0xFFEF4444);
        icon = Icons.warning_amber_rounded;
      } else if (daysLeft <= 7) {
        color = const Color(0xFFF59E0B);
        icon = Icons.warning_amber_rounded;
      } else {
        color = const Color(0xFF22C55E);
        icon = Icons.check_circle_rounded;
      }

      mainText = language == "en"
          ? "About $daysLeft days left"
          : "Ước tính còn $daysLeft ngày";

      helperText = language == "en"
          ? "Estimated empty date: ${DateHelper.displayDate(emptyDate)}\nBased on $dosesPerDay dose time(s) per day and dose amount $doseAmount."
          : "Có thể hết khoảng: ${DateHelper.displayDate(emptyDate)}\nTính theo $dosesPerDay lần uống mỗi ngày và mỗi liều $doseAmount.";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  mainText,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  helperText,
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    height: 1.35,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RefillActionCard extends StatelessWidget {
  final bool isLowQuantity;
  final bool isOutOfMedicine;
  final String totalQuantity;
  final String remainingQuantity;
  final String pharmacyName;
  final String pharmacyPhone;
  final VoidCallback onMarkRefilled;

  const RefillActionCard({
    super.key,
    required this.isLowQuantity,
    required this.isOutOfMedicine,
    required this.totalQuantity,
    required this.remainingQuantity,
    required this.pharmacyName,
    required this.pharmacyPhone,
    required this.onMarkRefilled,
  });

  bool get hasPharmacyHelp {
    return pharmacyName.trim().isNotEmpty || pharmacyPhone.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final color = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : isLowQuantity
        ? const Color(0xFFEF4444)
        : AppTheme.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOutOfMedicine) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      language == "en" ? "OUT OF MEDICINE" : "ĐÃ HẾT THUỐC",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isOutOfMedicine
                      ? Icons.error_rounded
                      : isLowQuantity
                      ? Icons.warning_amber_rounded
                      : Icons.local_pharmacy_rounded,
                  color: color,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isOutOfMedicine
                      ? (language == "en"
                            ? "Refill Needed Now"
                            : "Cần Refill Ngay")
                      : isLowQuantity
                      ? (language == "en"
                            ? "Need More Medicine?"
                            : "Cần Thêm Thuốc?")
                      : (language == "en" ? "Refill Help" : "Hướng Dẫn Refill"),
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isOutOfMedicine
                ? (language == "en"
                      ? "Remaining: 0 of $totalQuantity"
                      : "Còn lại: 0 trên $totalQuantity")
                : (language == "en"
                      ? "Remaining: $remainingQuantity of $totalQuantity"
                      : "Còn lại: $remainingQuantity trên $totalQuantity"),
            style: TextStyle(
              color: color,
              fontSize: 18,
              height: 1.3,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          SimplePharmacyCallBox(
            isOutOfMedicine: isOutOfMedicine,
            pharmacyName: pharmacyName,
            pharmacyPhone: pharmacyPhone,
          ),
          const SizedBox(height: 14),
          RefillStepRow(
            number: "1",
            text: hasPharmacyHelp
                ? isOutOfMedicine
                      ? (language == "en"
                            ? "Tap the Call Pharmacy button above now."
                            : "Bấm nút Gọi Nhà Thuốc ở trên ngay.")
                      : (language == "en"
                            ? "Tap the Call Pharmacy button above."
                            : "Bấm nút Gọi Nhà Thuốc ở trên.")
                : (language == "en"
                      ? "Call the pharmacy, doctor, or ask family for help."
                      : "Gọi nhà thuốc, bác sĩ, hoặc nhờ người thân giúp."),
          ),
          const SizedBox(height: 10),
          RefillStepRow(
            number: "2",
            text: language == "en"
                ? "Ask for a refill for this medicine."
                : "Hỏi refill thuốc này.",
          ),
          const SizedBox(height: 10),
          RefillStepRow(
            number: "3",
            text: language == "en"
                ? "After you get the medicine, tap the green button below."
                : "Sau khi nhận thuốc, bấm nút màu xanh bên dưới.",
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Text(
              language == "en"
                  ? "Important: This app cannot order medicine by itself. This button only updates the app after the refill is already picked up."
                  : "Quan trọng: Ứng dụng này không tự đặt thuốc. Nút này chỉ cập nhật ứng dụng sau khi bạn đã nhận thuốc refill.",
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.35,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: onMarkRefilled,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 28),
              label: Text(
                language == "en" ? "I Got My Refill" : "Đã Nhận Refill",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SimplePharmacyCallBox extends StatelessWidget {
  final bool isOutOfMedicine;
  final String pharmacyName;
  final String pharmacyPhone;

  const SimplePharmacyCallBox({
    super.key,
    required this.isOutOfMedicine,
    required this.pharmacyName,
    required this.pharmacyPhone,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final hasName = pharmacyName.trim().isNotEmpty;
    final hasPhone = pharmacyPhone.trim().isNotEmpty;

    if (!hasName && !hasPhone) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.phone_disabled_rounded,
              color: Color(0xFFEF4444),
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                language == "en"
                    ? "No pharmacy phone saved.\nTap Edit Medication Details to add it."
                    : "Chưa lưu số nhà thuốc.\nBấm Sửa Thông Tin Thuốc để thêm.",
                style: const TextStyle(
                  color: Color(0xFF1E2A3A),
                  height: 1.35,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.30),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.phone_in_talk_rounded,
                color: Color(0xFF22C55E),
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isOutOfMedicine
                      ? (language == "en" ? "Call now:" : "Gọi ngay:")
                      : (language == "en" ? "Call for refill:" : "Gọi refill:"),
                  style: TextStyle(
                    color: isOutOfMedicine
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF1E2A3A),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (hasName) ...[
            const SizedBox(height: 14),
            Text(
              pharmacyName.trim(),
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (hasPhone) ...[
            const SizedBox(height: 12),
            PhoneCallButton(
              phoneNumber: pharmacyPhone.trim(),
              label: language == "en" ? "Call Pharmacy" : "Gọi Nhà Thuốc",
            ),
          ],
          const SizedBox(height: 12),
          Text(
            language == "en"
                ? "Ask them for a refill."
                : "Hỏi họ refill thuốc.",
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 17,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class RefillStepRow extends StatelessWidget {
  final String number;
  final String text;

  const RefillStepRow({super.key, required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.35,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AsNeededDoseCard extends StatelessWidget {
  final int doseAmount;
  final VoidCallback onLogTaken;
  final VoidCallback onAddTime;

  const AsNeededDoseCard({
    super.key,
    required this.doseAmount,
    required this.onLogTaken,
    required this.onAddTime,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFF59E0B),
            size: 44,
          ),
          const SizedBox(height: 10),
          Text(
            language == "en" ? "As-needed medication" : "Thuốc dùng khi cần",
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            language == "en"
                ? "No fixed reminder times. Log a dose only when you actually take it. Dose amount: $doseAmount."
                : "Không có giờ nhắc cố định. Chỉ ghi nhận khi bạn thật sự dùng thuốc. Số lượng mỗi liều: $doseAmount.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onLogTaken,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                language == "en" ? "Log Taken Now" : "Ghi Nhận Đã Uống",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onAddTime,
            icon: Icon(Icons.add_alarm_rounded, color: AppTheme.primaryColor),
            label: Text(
              language == "en"
                  ? "Add a fixed reminder time"
                  : "Thêm giờ nhắc cố định",
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DoseSummaryCard extends StatelessWidget {
  final String nextDoseText;
  final int takenCount;
  final int missedCount;

  const DoseSummaryCard({
    super.key,
    required this.nextDoseText,
    required this.takenCount,
    required this.missedCount,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language == "en" ? "NEXT DOSE" : "LIỀU TIẾP THEO",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nextDoseText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (takenCount > 0 || missedCount > 0) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (takenCount > 0)
                        SummaryPill(
                          text:
                              "${language == "en" ? "Taken" : "Đã uống"} $takenCount",
                          color: const Color(0xFF22C55E),
                        ),
                      if (missedCount > 0)
                        SummaryPill(
                          text:
                              "${language == "en" ? "Missed" : "Bỏ lỡ"} $missedCount",
                          color: const Color(0xFFEF4444),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SummaryPill extends StatelessWidget {
  final String text;
  final Color color;

  const SummaryPill({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final isWhite = color == Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isWhite ? Colors.white.withValues(alpha: 0.18) : color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class QuantityRemainingCard extends StatelessWidget {
  final String text;
  final bool isOutOfMedicine;

  const QuantityRemainingCard({
    super.key,
    required this.text,
    required this.isOutOfMedicine,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : AppTheme.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isOutOfMedicine
            ? const Color(0xFFEF4444).withValues(alpha: 0.10)
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isOutOfMedicine
              ? const Color(0xFFEF4444).withValues(alpha: 0.34)
              : AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isOutOfMedicine
                  ? const Color(0xFFEF4444).withValues(alpha: 0.13)
                  : AppTheme.lightColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isOutOfMedicine ? Icons.error_rounded : Icons.inventory_2_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isOutOfMedicine
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF1E2A3A),
                fontWeight: FontWeight.bold,
                fontSize: isOutOfMedicine ? 18 : 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TreatmentCard extends StatelessWidget {
  final double progress;
  final String treatmentText;
  final String startDate;
  final String endDate;

  const TreatmentCard({
    super.key,
    required this.progress,
    required this.treatmentText,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            language == "en" ? "Treatment Progress" : "Tiến Trình Điều Trị",
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: AppTheme.primaryColor,
              backgroundColor: AppTheme.lightColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            treatmentText,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${AppLanguage.text("startDate")}: ${DateHelper.displayMedicationDate(startDate)}"
            "   •   "
            "${AppLanguage.text("endDate")}: ${endDate.isEmpty ? AppLanguage.text("noEndDate") : DateHelper.displayMedicationDate(endDate)}",
            style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class DoseTimeCard extends StatelessWidget {
  final TimeOfDay time;
  final String status;
  final DateTime doseDateTime;
  final bool isSaving;
  final bool highlighted;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onMarkTaken;
  final VoidCallback onMarkMissed;

  const DoseTimeCard({
    super.key,
    required this.time,
    required this.status,
    required this.doseDateTime,
    required this.isSaving,
    this.highlighted = false,
    required this.onEdit,
    required this.onDelete,
    required this.onMarkTaken,
    required this.onMarkMissed,
  });

  Color statusColor() {
    if (status == "taken") {
      return const Color(0xFF22C55E);
    }

    if (status == "missed") {
      return const Color(0xFFEF4444);
    }

    if (status == "skipped") {
      return const Color(0xFF64748B);
    }

    if (status == "due") {
      return const Color(0xFFF59E0B);
    }

    if (status == "late") {
      return const Color(0xFFFB7185);
    }

    return AppTheme.primaryColor;
  }

  String statusText() {
    final language = AppLanguage.currentLanguage.value;

    switch (status) {
      case "taken":
        return language == "en" ? "Taken" : "Đã uống";
      case "missed":
        return language == "en" ? "Missed" : "Đã bỏ lỡ";
      case "skipped":
        return language == "en" ? "Skipped" : "Đã bỏ qua";
      case "due":
        return language == "en" ? "Dose time now" : "Đến giờ uống";
      case "late":
        return language == "en" ? "Past dose time" : "Đã quá giờ uống";
      default:
        return language == "en" ? "Scheduled" : "Đã lên lịch";
    }
  }

  String helperText() {
    final language = AppLanguage.currentLanguage.value;

    if (status == "scheduled") {
      return language == "en"
          ? "Actions unlock when the dose time comes."
          : "Nút đánh dấu sẽ mở khi tới giờ uống.";
    }

    if (status == "late") {
      return language == "en"
          ? "You can still mark this dose as taken or missed."
          : "Bạn vẫn có thể đánh dấu liều này là đã uống hoặc bỏ lỡ.";
    }

    if (status == "due") {
      return language == "en"
          ? "You can mark this dose now."
          : "Bạn có thể đánh dấu liều này ngay bây giờ.";
    }

    if (status == "skipped") {
      return language == "en"
          ? "Skipped from the reminder notification. You can review it in Dose History."
          : "Đã bỏ qua từ thông báo nhắc. Bạn có thể xem lại trong Lịch Sử Liều.";
    }

    return "";
  }

  bool get canShowActionButtons {
    return status == "due" || status == "late";
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;
    final color = statusColor();
    final helper = helperText();

    final isTomorrow = DateHelper.dateOnly(
      doseDateTime,
    ).isAfter(DateHelper.dateOnly(DateTime.now()));

    final displayStatus = isTomorrow && status == "scheduled"
        ? "${statusText()} • ${language == "en" ? "Tomorrow" : "Ngày mai"}"
        : statusText();

    return Semantics(
      container: true,
      label:
          "${TimeHelper.formatTimeForDisplay(time)}, $displayStatus${helper.isEmpty ? "" : ", $helper"}",
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: highlighted
                  ? AppTheme.primaryColor
                  : color.withValues(alpha: 0.35),
              width: highlighted ? 3 : 1.4,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  DoseClockIcon(time: time, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TimeHelper.formatTimeForDisplay(time),
                          style: const TextStyle(
                            color: Color(0xFF1E2A3A),
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayStatus,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (helper.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    helper,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(
                          color: AppTheme.primaryColor.withValues(alpha: 0.45),
                        ),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(
                        language == "en" ? "Change time" : "Đổi giờ",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: BorderSide(
                            color: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.45),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          language == "en" ? "Delete" : "Xóa",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (canShowActionButtons) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : onMarkTaken,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          language == "en" ? "Taken" : "Đã uống",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : onMarkMissed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded),
                        label: Text(
                          language == "en" ? "Missed" : "Bỏ lỡ",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class DoseClockIcon extends StatelessWidget {
  final TimeOfDay time;
  final Color color;

  const DoseClockIcon({super.key, required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey("${time.hour}:${time.minute}:${color.hashCode}"),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return SizedBox(
          width: 44,
          height: 44,
          child: CustomPaint(
            painter: DoseClockPainter(
              time: time,
              color: color,
              progress: value,
            ),
          ),
        );
      },
    );
  }
}

class DoseClockPainter extends CustomPainter {
  final TimeOfDay time;
  final Color color;
  final double progress;

  DoseClockPainter({
    required this.time,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final radius = math.min(size.width, size.height) / 2;

    final circlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final tickPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final hourHandPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    final minuteHandPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius - 2, circlePaint);
    canvas.drawCircle(center, radius - 3, borderPaint);

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;

      final start = Offset(
        center.dx + math.cos(angle) * (radius - 10),
        center.dy + math.sin(angle) * (radius - 10),
      );

      final end = Offset(
        center.dx + math.cos(angle) * (radius - 7),
        center.dy + math.sin(angle) * (radius - 7),
      );

      canvas.drawLine(start, end, tickPaint);
    }

    final hourValue = (time.hour % 12) + (time.minute / 60.0);
    final hourAngle = ((hourValue * 30) - 90) * math.pi / 180;
    final minuteAngle = ((time.minute * 6) - 90) * math.pi / 180;

    final animatedHourAngle =
        -math.pi / 2 + ((hourAngle + math.pi / 2) * progress);

    final animatedMinuteAngle =
        -math.pi / 2 + ((minuteAngle + math.pi / 2) * progress);

    final hourHandEnd = Offset(
      center.dx + math.cos(animatedHourAngle) * (radius * 0.43),
      center.dy + math.sin(animatedHourAngle) * (radius * 0.43),
    );

    final minuteHandEnd = Offset(
      center.dx + math.cos(animatedMinuteAngle) * (radius * 0.62),
      center.dy + math.sin(animatedMinuteAngle) * (radius * 0.62),
    );

    canvas.drawLine(center, hourHandEnd, hourHandPaint);
    canvas.drawLine(center, minuteHandEnd, minuteHandPaint);

    final centerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3.3, centerPaint);
  }

  @override
  bool shouldRepaint(covariant DoseClockPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}

class EmptyReminderTimes extends StatelessWidget {
  final VoidCallback onAddTime;

  const EmptyReminderTimes({super.key, required this.onAddTime});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.schedule_rounded, color: AppTheme.primaryColor, size: 44),
          const SizedBox(height: 10),
          Text(
            language == "en" ? "No reminder times yet" : "Chưa có giờ nhắc",
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onAddTime,
            icon: const Icon(Icons.add_rounded),
            label: Text(language == "en" ? "Add Time" : "Thêm Giờ"),
          ),
        ],
      ),
    );
  }
}

class NotesCard extends StatelessWidget {
  final String notes;

  const NotesCard({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B),
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notes,
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SafetyReminderCard extends StatelessWidget {
  const SafetyReminderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.lightColor.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        language == "en"
            ? "This app is only a reminder tool. Always follow your doctor, pharmacist, or prescription label."
            : "Ứng dụng này chỉ là công cụ nhắc nhở. Luôn làm theo hướng dẫn của bác sĩ, dược sĩ hoặc nhãn thuốc.",
        style: const TextStyle(
          color: Color(0xFF1E2A3A),
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
