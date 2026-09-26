import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'date_helper.dart';
import 'healthcare_place_search.dart';
import 'medication.dart';
import 'medication_storage.dart';
import 'pill_box_reminder_bridge.dart';
import 'rxnorm_service.dart';
import 'smooth_action_button.dart';
import 'time_helper.dart';

class MedicationDetailsPage extends StatefulWidget {
  final Medication? medication;
  final int medicationIndex;

  const MedicationDetailsPage({
    super.key,
    this.medication,
    this.medicationIndex = -1,
  });

  @override
  State<MedicationDetailsPage> createState() => _MedicationDetailsPageState();
}

class _MedicationDetailsPageState extends State<MedicationDetailsPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController dosageController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController remainingQuantityController =
      TextEditingController();
  final TextEditingController pharmacyNameController = TextEditingController();
  final TextEditingController pharmacyAddressController =
      TextEditingController();
  final TextEditingController pharmacyPhoneController = TextEditingController();
  final TextEditingController instructionsController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final FocusNode medicationNameFocusNode = FocusNode();
  final FocusNode dosageFocusNode = FocusNode();

  DateTime? startDate;
  DateTime? endDate;
  bool useCustomReminderTimes = false;
  List<TimeOfDay> customReminderTimes = <TimeOfDay>[];
  int pillBoxSlot = -1;

  bool isSaving = false;
  bool enablePharmacyCall = false;
  bool isSearchingRxNorm = false;
  String rxNormSearchMessage = "";
  Timer? medicationSearchDebounce;
  Timer? medicationSuggestionDismissTimer;
  int medicationSearchRequest = 0;
  bool medicationSuggestionsOpen = false;
  List<RxNormSuggestion> savedMedicationSuggestions = [];
  List<RxNormSuggestion> localMedicationSuggestions = [];
  List<RxNormSuggestion> rxNormSuggestions = [];

  bool get isEditing {
    return widget.medication != null && widget.medicationIndex >= 0;
  }

  @override
  void initState() {
    super.initState();

    final medication = widget.medication;

    if (medication != null) {
      nameController.text = medication.name;
      dosageController.text = medication.dosage;
      quantityController.text = medication.quantity;
      remainingQuantityController.text = medication.remainingQuantity;
      pharmacyNameController.text = medication.pharmacyName;
      pharmacyAddressController.text = medication.pharmacyAddress;
      pharmacyPhoneController.text = medication.pharmacyPhone;
      instructionsController.text = medication.instructions;
      notesController.text = medication.notes;
      pillBoxSlot = medication.pillBoxSlot;

      startDate = DateHelper.parseMedicationDate(medication.startDate);
      endDate = DateHelper.parseMedicationDate(medication.endDate);

      if (medication.reminderTimes.isNotEmpty) {
        useCustomReminderTimes = true;
        customReminderTimes = medication.reminderTimes
            .map(TimeHelper.stringToTime)
            .toList();
      }

      enablePharmacyCall =
          medication.pharmacyName.trim().isNotEmpty ||
          medication.pharmacyAddress.trim().isNotEmpty ||
          medication.pharmacyPhone.trim().isNotEmpty;
    }

    instructionsController.addListener(updatePreview);
    notesController.addListener(updatePreview);
    quantityController.addListener(updatePreview);
    remainingQuantityController.addListener(updatePreview);
    pharmacyNameController.addListener(updatePreview);
    pharmacyAddressController.addListener(updatePreview);
    pharmacyPhoneController.addListener(updatePreview);
    medicationNameFocusNode.addListener(handleMedicationNameFocusChanged);
    unawaited(loadSavedMedicationSuggestions());
  }

  void updatePreview() {
    if (mounted) {
      setState(() {});
    }
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> loadSavedMedicationSuggestions() async {
    try {
      final medications = await MedicationStorage.loadCurrentLocalMedications();
      final suggestions = <RxNormSuggestion>[];
      final seen = <String>{};

      for (final medication in medications) {
        final name = medication.name.trim();
        final dosage = medication.dosage.trim();
        final key = "${name.toLowerCase()}|${dosage.toLowerCase()}";

        if (name.isEmpty || !seen.add(key)) continue;

        suggestions.add(
          RxNormSuggestion(
            name: name,
            rxcui: "",
            score: 0,
            source: "Saved medication",
            entryName: name,
            strength: dosage,
            isSavedMedication: true,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        savedMedicationSuggestions = suggestions;
      });

      if (medicationNameFocusNode.hasFocus) {
        handleMedicationNameChanged(nameController.text);
      }
    } catch (_) {
      // Search remains available from the on-device catalog and RxNorm.
    }
  }

  void handleMedicationNameFocusChanged() {
    if (!mounted) return;

    medicationSuggestionDismissTimer?.cancel();

    if (!medicationNameFocusNode.hasFocus) {
      medicationSearchDebounce?.cancel();
      medicationSearchRequest += 1;

      setState(() {
        isSearchingRxNorm = false;
      });

      // iOS can move focus before a tapped autocomplete row receives onTap.
      // Keeping the panel briefly visible makes pre-filled edit fields work.
      medicationSuggestionDismissTimer = Timer(
        const Duration(milliseconds: 240),
        () {
          if (!mounted || medicationNameFocusNode.hasFocus) {
            return;
          }

          setState(() {
            medicationSuggestionsOpen = false;
          });
        },
      );
      return;
    }

    setState(() {
      medicationSuggestionsOpen = true;
    });
    handleMedicationNameChanged(nameController.text);
  }

  void handleMedicationNameChanged(String value) {
    medicationSearchDebounce?.cancel();
    medicationSearchRequest += 1;
    final request = medicationSearchRequest;
    final cleanQuery = value.trim();

    final localSuggestions = RxNormService.findOnDeviceSuggestions(
      cleanQuery,
      savedMedications: savedMedicationSuggestions,
      maximumResults: 8,
    );

    setState(() {
      medicationSuggestionsOpen = medicationNameFocusNode.hasFocus;
      localMedicationSuggestions = localSuggestions;
      rxNormSuggestions = [];
      rxNormSearchMessage = "";
      isSearchingRxNorm = cleanQuery.length >= 2;
    });

    if (cleanQuery.length < 2) {
      return;
    }

    medicationSearchDebounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(searchRxNorm(cleanQuery, request));
    });
  }

  Future<void> searchRxNorm(String query, int request) async {
    try {
      final results = await RxNormService.findMedicationNames(
        query,
        maximumResults: 12,
      );

      if (!mounted ||
          request != medicationSearchRequest ||
          nameController.text.trim() != query) {
        return;
      }

      setState(() {
        rxNormSuggestions = results;
        isSearchingRxNorm = false;
        rxNormSearchMessage = results.isEmpty
            ? tr(
                "No online match. You can keep the name you entered.",
                "Không tìm thấy tên trực tuyến. Bạn vẫn có thể giữ tên đã nhập.",
              )
            : "";
      });
    } catch (_) {
      if (!mounted || request != medicationSearchRequest) {
        return;
      }

      setState(() {
        isSearchingRxNorm = false;
        rxNormSearchMessage = tr(
          "Online lookup is unavailable. On-device suggestions still work.",
          "Không thể tra cứu trực tuyến. Gợi ý trên thiết bị vẫn hoạt động.",
        );
      });
    }
  }

  List<RxNormSuggestion> get visibleMedicationSuggestions {
    final combined = <RxNormSuggestion>[];
    final seen = <String>{};

    for (final suggestion in [
      ...localMedicationSuggestions,
      ...rxNormSuggestions,
    ]) {
      final key = [
        suggestion.medicationName,
        suggestion.strength,
        suggestion.doseForm,
      ].join("|").toLowerCase();

      if (!seen.add(key)) continue;

      combined.add(suggestion);

      if (combined.length >= 10) {
        break;
      }
    }

    return combined;
  }

  void selectMedicationSuggestion(RxNormSuggestion suggestion) {
    medicationSearchDebounce?.cancel();
    medicationSuggestionDismissTimer?.cancel();
    medicationSearchRequest += 1;
    final selectedName = suggestion.medicationName.trim();

    if (selectedName.isEmpty) return;

    nameController.value = TextEditingValue(
      text: selectedName,
      selection: TextSelection.collapsed(offset: selectedName.length),
    );

    if (dosageController.text.trim().isEmpty &&
        suggestion.strength.trim().isNotEmpty) {
      dosageController.text = suggestion.strength.trim();
    }

    setState(() {
      medicationSuggestionsOpen = false;
      localMedicationSuggestions = [];
      rxNormSuggestions = [];
      rxNormSearchMessage = "";
      isSearchingRxNorm = false;
    });

    dosageFocusNode.requestFocus();
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  String cleanPhoneDigits(String value) {
    return value.replaceAll(RegExp(r'[^0-9]'), "");
  }

  String formatPhoneNumberForSave(String value) {
    final trimmed = value.trim();
    final digits = cleanPhoneDigits(trimmed);

    if (digits.length == 10) {
      return "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}";
    }

    return trimmed;
  }

  void showErrorMessage(String english, String vietnamese) {
    final language = AppLanguage.currentLanguage.value;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(language == "en" ? english : vietnamese)),
    );
  }

  String get scheduleDirections {
    return TimeHelper.selectScheduleDirections(
      instructions: instructionsController.text,
      notes: notesController.text,
    );
  }

  String get doseDirections {
    return TimeHelper.combineDoseDirections(
      instructions: instructionsController.text,
      notes: notesController.text,
    );
  }

  bool isAsNeededMedication() {
    if (scheduleDirections.isEmpty) {
      return false;
    }

    return TimeHelper.isAsNeededInstruction(scheduleDirections);
  }

  int getRecommendedQuantity() {
    if (startDate == null || endDate == null) {
      return 0;
    }

    final reminderTimes = TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirections,
    );

    if (reminderTimes.isEmpty) {
      return 0;
    }

    final doseAmount = TimeHelper.getDoseAmountFromInstructions(doseDirections);

    final dosesPerDay = reminderTimes.length;

    final totalDays = DateHelper.treatmentTotalDays(
      startDate: startDate!,
      endDate: endDate!,
    );

    return doseAmount * dosesPerDay * totalDays;
  }

  void useRecommendedQuantity() {
    final language = AppLanguage.currentLanguage.value;

    if (scheduleDirections.isEmpty) {
      showErrorMessage(
        "Please enter instructions or a description first.",
        "Vui lòng nhập hướng dẫn hoặc mô tả trước.",
      );
      return;
    }

    if (isAsNeededMedication()) {
      showErrorMessage(
        "As-needed medication does not have a fixed recommended quantity.",
        "Thuốc dùng khi cần không có số lượng đề xuất cố định.",
      );
      return;
    }

    if (TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirections,
    ).isEmpty) {
      showErrorMessage(
        "This schedule needs manual review. Add and verify reminder times from the medication reminder screen.",
        "Lịch này cần kiểm tra thủ công. Hãy thêm và xác minh giờ nhắc trong màn hình nhắc thuốc.",
      );
      return;
    }

    if (startDate == null || endDate == null) {
      showErrorMessage(
        "Please select start date and end date first.",
        "Vui lòng chọn ngày bắt đầu và ngày kết thúc trước.",
      );
      return;
    }

    final recommendedQuantity = getRecommendedQuantity();

    if (recommendedQuantity <= 0) {
      showErrorMessage(
        "Could not calculate recommended quantity.",
        "Không thể tính số lượng đề xuất.",
      );
      return;
    }

    setState(() {
      quantityController.text = recommendedQuantity.toString();
      remainingQuantityController.text = recommendedQuantity.toString();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == "en"
              ? "Recommended quantity set to $recommendedQuantity."
              : "Đã đặt số lượng đề xuất là $recommendedQuantity.",
        ),
      ),
    );
  }

  void setTreatmentLength(int days) {
    final language = AppLanguage.currentLanguage.value;
    final start = startDate ?? DateTime.now();

    setState(() {
      startDate = start;
      endDate = start.add(Duration(days: days - 1));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          language == "en"
              ? "Treatment length set to $days days."
              : "Đã đặt thời gian điều trị là $days ngày.",
        ),
      ),
    );
  }

  void useExampleForTesting() {
    final now = DateTime.now();
    medicationSearchDebounce?.cancel();
    medicationSearchRequest += 1;

    setState(() {
      nameController.text = "Amoxicillin";
      dosageController.text = "500 mg";
      quantityController.text = "42";
      remainingQuantityController.text = "42";
      pharmacyNameController.text = "CVS Pharmacy";
      pharmacyAddressController.text = "123 Main Street, Anaheim, CA 92805";
      pharmacyPhoneController.text = "(714) 123-4567";
      enablePharmacyCall = true;
      instructionsController.text = "Take 2 capsules every 8 hours";
      notesController.text =
          "Testing example. Please double-check all medication information.";
      startDate = now;
      endDate = now.add(const Duration(days: 6));
      localMedicationSuggestions = [];
      rxNormSuggestions = [];
      rxNormSearchMessage = "";
      isSearchingRxNorm = false;
    });
  }

  Future<void> pickStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      startDate = pickedDate;

      if (endDate != null && endDate!.isBefore(pickedDate)) {
        endDate = pickedDate;
      }
    });
  }

  Future<void> pickEndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: endDate ?? startDate ?? DateTime.now(),
      firstDate: startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      endDate = pickedDate;
    });
  }

  void clearEndDate() {
    setState(() {
      endDate = null;
    });
  }

  void refillToFullQuantity() {
    final totalQuantity = quantityController.text.trim();

    if (totalQuantity.isEmpty) {
      return;
    }

    setState(() {
      remainingQuantityController.text = totalQuantity;
    });
  }

  List<String> buildReminderTimes() {
    if (useCustomReminderTimes) {
      final sortedTimes = List<TimeOfDay>.from(customReminderTimes)
        ..sort((a, b) {
          return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
        });

      return sortedTimes.map(TimeHelper.timeToString).toList();
    }

    final existingMedication = widget.medication;
    final currentDirections = scheduleDirections;
    final existingDirections = existingMedication == null
        ? ""
        : TimeHelper.selectScheduleDirections(
            instructions: existingMedication.instructions,
            notes: existingMedication.notes,
          );

    if (existingMedication != null &&
        existingMedication.reminderTimes.isNotEmpty &&
        currentDirections == existingDirections) {
      return existingMedication.reminderTimes;
    }

    return TimeHelper.generateReminderTimesFromInstructions(
      currentDirections,
    ).map((time) {
      return TimeHelper.timeToString(time);
    }).toList();
  }

  Future<void> addCustomReminderTime() async {
    final pickedTime = await pickReminderTime(
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      title: tr("Add reminder time", "Thêm giờ nhắc"),
    );

    if (pickedTime == null || !mounted) {
      return;
    }

    final alreadyExists = customReminderTimes.any(
      (time) =>
          time.hour == pickedTime.hour && time.minute == pickedTime.minute,
    );

    if (alreadyExists) {
      showErrorMessage(
        "That reminder time is already added.",
        "Giờ nhắc này đã được thêm.",
      );
      return;
    }

    setState(() {
      customReminderTimes.add(pickedTime);
      customReminderTimes.sort((a, b) {
        return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
      });
    });
  }

  Future<void> editCustomReminderTime(int index) async {
    if (index < 0 || index >= customReminderTimes.length) {
      return;
    }

    final pickedTime = await pickReminderTime(
      initialTime: customReminderTimes[index],
      title: tr("Change reminder time", "Đổi giờ nhắc"),
    );

    if (pickedTime == null || !mounted) {
      return;
    }

    final duplicate = customReminderTimes.asMap().entries.any((entry) {
      return entry.key != index &&
          entry.value.hour == pickedTime.hour &&
          entry.value.minute == pickedTime.minute;
    });

    if (duplicate) {
      showErrorMessage(
        "That reminder time is already added.",
        "Giờ nhắc này đã được thêm.",
      );
      return;
    }

    setState(() {
      customReminderTimes[index] = pickedTime;
      customReminderTimes.sort((a, b) {
        return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
      });
    });
  }

  Future<TimeOfDay?> pickReminderTime({
    required TimeOfDay initialTime,
    required String title,
  }) {
    final now = DateTime.now();
    var selectedTime = initialTime;
    final initialDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      initialTime.hour,
      initialTime.minute,
    );

    return showCupertinoModalPopup<TimeOfDay>(
      context: context,
      builder: (pickerContext) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final use24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);

            return Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBackground.resolveFrom(context),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF1E2A3A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const ValueKey<String>(
                                'reminder-time-cancel',
                              ),
                              onPressed: () => Navigator.pop(pickerContext),
                              child: Text(tr('Cancel', 'Huỷ')),
                            ),
                            TextButton(
                              key: const ValueKey<String>(
                                'reminder-time-done',
                              ),
                              onPressed: () => Navigator.pop(
                                pickerContext,
                                selectedTime,
                              ),
                              child: Text(tr('Done', 'Xong')),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 210,
                        child: CupertinoDatePicker(
                          key: const ValueKey<String>('reminder-time-picker'),
                          mode: CupertinoDatePickerMode.time,
                          initialDateTime: initialDateTime,
                          use24hFormat: use24HourFormat,
                          onDateTimeChanged: (dateTime) {
                            setPickerState(() {
                              selectedTime = TimeOfDay.fromDateTime(dateTime);
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void removeCustomReminderTime(int index) {
    if (index < 0 || index >= customReminderTimes.length) {
      return;
    }

    setState(() {
      customReminderTimes.removeAt(index);
    });
  }

  bool validateBeforeSave({
    required String name,
    required String quantity,
    required String remainingQuantity,
    required bool pharmacyCallEnabled,
    required String pharmacyPhone,
    required String instructions,
    required String notes,
  }) {
    if (name.isEmpty || (instructions.isEmpty && notes.isEmpty)) {
      showErrorMessage(
        "Please enter the medication name and instructions or a description.",
        "Vui lòng nhập tên thuốc và hướng dẫn hoặc mô tả.",
      );
      return false;
    }

    final totalQuantityNumber = parseQuantityNumber(quantity);
    final remainingQuantityNumber = parseQuantityNumber(remainingQuantity);

    if (quantity.isNotEmpty && totalQuantityNumber <= 0) {
      showErrorMessage(
        "Total quantity must be a number above 0.",
        "Tổng số lượng phải là số lớn hơn 0.",
      );
      return false;
    }

    if (remainingQuantity.isNotEmpty &&
        quantity.isNotEmpty &&
        remainingQuantityNumber > totalQuantityNumber) {
      showErrorMessage(
        "Remaining quantity cannot be greater than total quantity.",
        "Số lượng còn lại không thể lớn hơn tổng số lượng.",
      );
      return false;
    }

    if (pharmacyCallEnabled &&
        pharmacyPhone.trim().isNotEmpty &&
        cleanPhoneDigits(pharmacyPhone).length < 7) {
      showErrorMessage(
        "The pharmacy, doctor, clinic, or hospital phone number looks too short.",
        "Số điện thoại nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện có vẻ quá ngắn.",
      );
      return false;
    }

    if (startDate != null && endDate != null && endDate!.isBefore(startDate!)) {
      showErrorMessage(
        "End date cannot be before start date.",
        "Ngày kết thúc không thể trước ngày bắt đầu.",
      );
      return false;
    }

    return true;
  }

  Future<void> saveMedication() async {
    final name = nameController.text.trim();
    final dosage = dosageController.text.trim();
    final quantity = quantityController.text.trim();
    final remainingQuantity = remainingQuantityController.text.trim().isEmpty
        ? quantity
        : remainingQuantityController.text.trim();
    final pharmacyName = enablePharmacyCall
        ? pharmacyNameController.text.trim()
        : "";
    final pharmacyAddress = enablePharmacyCall
        ? pharmacyAddressController.text.trim()
        : "";
    final pharmacyPhone = enablePharmacyCall
        ? formatPhoneNumberForSave(pharmacyPhoneController.text.trim())
        : "";
    final instructions = instructionsController.text.trim();
    final notes = notesController.text.trim();

    if (!validateBeforeSave(
      name: name,
      quantity: quantity,
      remainingQuantity: remainingQuantity,
      pharmacyCallEnabled: enablePharmacyCall,
      pharmacyPhone: pharmacyPhone,
      instructions: instructions,
      notes: notes,
    )) {
      return;
    }

    if (useCustomReminderTimes &&
        customReminderTimes.isEmpty &&
        !isAsNeededMedication()) {
      showErrorMessage(
        "Add at least one reminder time, or turn off Set times myself.",
        "Hãy thêm ít nhất một giờ nhắc hoặc tắt Tự chọn giờ nhắc.",
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    final reminderTimes = buildReminderTimes();

    final existingMedication = widget.medication;

    final savedMedication = Medication(
      id: existingMedication?.id ?? "",
      name: name,
      dosage: dosage,
      quantity: quantity,
      remainingQuantity: remainingQuantity,
      inventoryBaselineQuantity:
          existingMedication?.inventoryBaselineQuantity ?? "",
      inventoryBaselineAt: existingMedication?.inventoryBaselineAt ?? "",
      pharmacyName: pharmacyName,
      pharmacyAddress: pharmacyAddress,
      pharmacyPhone: pharmacyPhone,
      instructions: instructions,
      notes: notes,
      reminderTimes: reminderTimes,
      doseStatus: widget.medication?.doseStatus ?? "notTakenYet",
      doseStatusDate: widget.medication?.doseStatusDate ?? "",
      doseRecords: widget.medication?.doseRecords ?? const <String, String>{},
      doseRecordUpdatedAt:
          widget.medication?.doseRecordUpdatedAt ?? const <String, String>{},
      deletedDoseRecords:
          widget.medication?.deletedDoseRecords ?? const <String, String>{},
      startDate: startDate == null ? "" : DateHelper.dateToString(startDate!),
      endDate: endDate == null ? "" : DateHelper.dateToString(endDate!),
      pillBoxSlot: pillBoxSlot,
      updatedAt: existingMedication?.updatedAt ?? "",
    );

    try {
      if (existingMedication != null) {
        await MedicationStorage.upsertMedicationById(
          existingMedication.id,
          savedMedication,
        ).timeout(const Duration(seconds: 12));
      } else {
        await MedicationStorage.saveMedication(
          savedMedication,
        ).timeout(const Duration(seconds: 12));
      }

      // The medication is already safely stored. Bluetooth sync happens in
      // the background so an unavailable pill box cannot block this screen.
      unawaited(PillBoxReminderBridge.syncScheduleNow());

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } on TimeoutException {
      if (mounted) {
        showErrorMessage(
          "Saving took too long. Your phone's local storage did not respond. Please try again.",
          "Lưu quá lâu. Bộ nhớ trên điện thoại không phản hồi. Vui lòng thử lại.",
        );
      }
    } catch (error, stackTrace) {
      debugPrint("Medication save failed: $error");
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        showErrorMessage(
          "Medication could not be saved. Please try again.",
          "Không thể lưu thuốc. Vui lòng thử lại.",
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> deleteMedication() async {
    final medication = widget.medication;
    if (medication == null || isSaving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr("Delete medication?", "Xoá thuốc?")),
          content: Text(
            tr(
              "Delete ${medication.name}? Its reminder schedule and history will also be removed.",
              "Xoá ${medication.name}? Lịch nhắc và lịch sử của thuốc cũng sẽ bị xoá.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr("Cancel", "Huỷ")),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                tr("Delete", "Xoá"),
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => isSaving = true);
    try {
      final deleted = await MedicationStorage.deleteMedicationById(
        medication.id,
      ).timeout(const Duration(seconds: 12));
      if (!deleted) {
        throw StateError("Medication no longer exists.");
      }
      unawaited(PillBoxReminderBridge.syncScheduleNow());
      if (mounted) {
        // Details may be opened from either the medication list or a reminder
        // screen. Return to the list route so deleting cannot leave the nested
        // medication navigator on an empty/removed reminder page.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on TimeoutException {
      if (mounted) {
        showErrorMessage(
          "Deleting took too long. Please try again.",
          "Xoá quá lâu. Vui lòng thử lại.",
        );
      }
    } catch (_) {
      if (mounted) {
        showErrorMessage(
          "Medication could not be deleted. Please try again.",
          "Không thể xoá thuốc. Vui lòng thử lại.",
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    medicationSearchDebounce?.cancel();
    medicationSuggestionDismissTimer?.cancel();
    medicationNameFocusNode.removeListener(handleMedicationNameFocusChanged);
    instructionsController.removeListener(updatePreview);
    notesController.removeListener(updatePreview);
    quantityController.removeListener(updatePreview);
    remainingQuantityController.removeListener(updatePreview);
    pharmacyNameController.removeListener(updatePreview);
    pharmacyAddressController.removeListener(updatePreview);
    pharmacyPhoneController.removeListener(updatePreview);

    nameController.dispose();
    dosageController.dispose();
    quantityController.dispose();
    remainingQuantityController.dispose();
    pharmacyNameController.dispose();
    pharmacyAddressController.dispose();
    pharmacyPhoneController.dispose();
    instructionsController.dispose();
    notesController.dispose();
    medicationNameFocusNode.dispose();
    dosageFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: AppTheme.pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppTheme.formMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_ios),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isEditing
                          ? tr("Edit Medication", "Sửa Thuốc")
                          : tr("Add Medication", "Thêm Thuốc"),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E2A3A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        "Enter the medicine name, directions, and important warnings. A pharmacy, doctor, clinic, or hospital is optional.",
                        "Nhập tên thuốc, hướng dẫn dùng và cảnh báo quan trọng. Nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện là lựa chọn không bắt buộc.",
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF667085),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SmoothActionButton(
                      icon: Icons.science_rounded,
                      label: language == "en"
                          ? "Use Example for Testing"
                          : "Dùng Ví Dụ Để Thử",
                      outlined: true,
                      onPressed: useExampleForTesting,
                    ),
                    const SizedBox(height: 18),
                    DetailsInputField(
                      controller: nameController,
                      label: AppLanguage.text("medicationName"),
                      hintText: language == "en"
                          ? "Start typing, for example: Tyle..."
                          : "Bắt đầu nhập, ví dụ: Tyle...",
                      icon: Icons.medication_rounded,
                      focusNode: medicationNameFocusNode,
                      onChanged: handleMedicationNameChanged,
                      textInputAction: TextInputAction.search,
                    ),
                    if (medicationSuggestionsOpen &&
                        nameController.text.trim().isNotEmpty &&
                        (visibleMedicationSuggestions.isNotEmpty ||
                            isSearchingRxNorm ||
                            rxNormSearchMessage.isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      MedicationSuggestionList(
                        query: nameController.text,
                        suggestions: visibleMedicationSuggestions,
                        isSearching: isSearchingRxNorm,
                        message: rxNormSearchMessage,
                        onInteractionStart: () {
                          medicationSuggestionDismissTimer?.cancel();
                        },
                        onSelected: selectMedicationSuggestion,
                      ),
                    ],
                    const SizedBox(height: 14),
                    DetailsInputField(
                      controller: dosageController,
                      label: AppLanguage.text("dosage"),
                      hintText: language == "en"
                          ? "Example: 500 mg"
                          : "Ví dụ: 500 mg",
                      icon: Icons.scale_rounded,
                      focusNode: dosageFocusNode,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    DetailsInputField(
                      controller: instructionsController,
                      label: AppLanguage.text("instructions"),
                      hintText: language == "en"
                          ? "Example: Take 2 capsules every 8 hours. Small spelling mistakes are okay."
                          : "Ví dụ: Uống 2 viên mỗi 8 giờ. Có thể nhập sai chính tả nhẹ.",
                      icon: Icons.description_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    DetailsInputField(
                      controller: notesController,
                      label: AppLanguage.text("notes"),
                      hintText: AppLanguage.text("notesHint"),
                      icon: Icons.warning_amber_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 14),
                    LiveDosePreviewCard(
                      scheduleDirections: scheduleDirections,
                      doseDirections: doseDirections,
                    ),
                    const SizedBox(height: 14),
                    ManualReminderTimesCard(
                      enabled: useCustomReminderTimes,
                      times: customReminderTimes,
                      onEnabledChanged: (enabled) {
                        setState(() {
                          useCustomReminderTimes = enabled;

                          if (enabled && customReminderTimes.isEmpty) {
                            customReminderTimes = List<TimeOfDay>.of(
                              TimeHelper.generateReminderTimesFromInstructions(
                                scheduleDirections,
                              ),
                            );
                          }
                        });
                      },
                      onAdd: addCustomReminderTime,
                      onEdit: editCustomReminderTime,
                      onRemove: removeCustomReminderTime,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: pillBoxSlot,
                      decoration: InputDecoration(
                        labelText: tr("Pill box compartment", "Ngăn hộp thuốc"),
                        helperText: tr(
                          "Choose the physical compartment containing this medication.",
                          "Chọn ngăn thực tế chứa thuốc này.",
                        ),
                        prefixIcon: const Icon(Icons.grid_view_rounded),
                        border: const OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(
                          value: -1,
                          child: Text(tr("Not assigned", "Chưa gán")),
                        ),
                        ...List<DropdownMenuItem<int>>.generate(
                          7,
                          (index) => DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              tr(
                                "Compartment ${index + 1}",
                                "Ngăn ${index + 1}",
                              ),
                            ),
                          ),
                        ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) => setState(() {
                              pillBoxSlot = value ?? -1;
                            }),
                    ),
                    const SizedBox(height: 18),
                    DetailsInputField(
                      controller: quantityController,
                      label: language == "en"
                          ? "Total Quantity"
                          : "Tổng Số Lượng",
                      hintText: language == "en" ? "Example: 42" : "Ví dụ: 42",
                      icon: Icons.inventory_2_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                    DetailsInputField(
                      controller: remainingQuantityController,
                      label: language == "en"
                          ? "Remaining Quantity"
                          : "Số Lượng Còn Lại",
                      hintText: language == "en" ? "Example: 42" : "Ví dụ: 42",
                      icon: Icons.inventory_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                    MedicineStatusPreviewCard(
                      quantityText: quantityController.text,
                      remainingQuantityText: remainingQuantityController.text,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: refillToFullQuantity,
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
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        language == "en"
                            ? "Refill to Full Quantity"
                            : "Đổ Đầy Lại Theo Tổng Số Lượng",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: useRecommendedQuantity,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF22C55E),
                        side: BorderSide(
                          color: const Color(
                            0xFF22C55E,
                          ).withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                      icon: const Icon(Icons.calculate_rounded),
                      label: Text(
                        language == "en"
                            ? "Use Recommended Quantity"
                            : "Dùng Số Lượng Đề Xuất",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PharmacyCallOptionCard(
                      enabled: enablePharmacyCall,
                      onChanged: (value) {
                        setState(() {
                          enablePharmacyCall = value;
                        });
                      },
                    ),
                    if (enablePharmacyCall) ...[
                      const SizedBox(height: 14),
                      HealthcarePlaceSearchField(
                        nameController: pharmacyNameController,
                        addressController: pharmacyAddressController,
                        phoneController: pharmacyPhoneController,
                        label: language == "en"
                            ? "Pharmacy / Doctor / Clinic / Hospital (Optional)"
                            : "Nhà Thuốc / Bác Sĩ / Phòng Khám / Bệnh Viện (Không bắt buộc)",
                        hintText: language == "en"
                            ? "Search CVS, a doctor, city, or ZIP"
                            : "Tìm CVS, bác sĩ, thành phố hoặc mã ZIP",
                        borderRadius: 18,
                        fillColor: Colors.white.withValues(alpha: 0.92),
                      ),
                      const SizedBox(height: 14),
                      DetailsInputField(
                        controller: pharmacyAddressController,
                        label: language == "en"
                            ? "Provider Address (used for grouping)"
                            : "Địa Chỉ Cơ Sở (dùng để nhóm thuốc)",
                        hintText: language == "en"
                            ? "Select a result or enter the address"
                            : "Chọn kết quả hoặc nhập địa chỉ",
                        icon: Icons.location_on_rounded,
                        keyboardType: TextInputType.streetAddress,
                      ),
                      const SizedBox(height: 14),
                      DetailsInputField(
                        controller: pharmacyPhoneController,
                        label: language == "en"
                            ? "Phone Number (Optional)"
                            : "Số Điện Thoại (Không bắt buộc)",
                        hintText: language == "en"
                            ? "Example: (714) 123-4567"
                            : "Ví dụ: (714) 123-4567",
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                    const SizedBox(height: 18),
                    DatePickerCard(
                      title: AppLanguage.text("startDate"),
                      value: startDate == null
                          ? tr("Select start date", "Chọn ngày bắt đầu")
                          : DateHelper.displayDate(startDate!),
                      icon: Icons.calendar_month_rounded,
                      onTap: pickStartDate,
                    ),
                    const SizedBox(height: 12),
                    DatePickerCard(
                      title: AppLanguage.text("endDate"),
                      value: endDate == null
                          ? AppLanguage.text("noEndDate")
                          : DateHelper.displayDate(endDate!),
                      icon: Icons.event_available_rounded,
                      onTap: pickEndDate,
                      trailing: endDate == null
                          ? null
                          : IconButton(
                              onPressed: clearEndDate,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    TreatmentLengthQuickCard(onSelectDays: setTreatmentLength),
                    const SizedBox(height: 14),
                    SupplyPreviewCard(
                      scheduleDirections: scheduleDirections,
                      doseDirections: doseDirections,
                      quantityText: quantityController.text,
                      remainingQuantityText: remainingQuantityController.text,
                      startDate: startDate,
                      endDate: endDate,
                    ),
                    const SizedBox(height: 24),
                    SmoothActionButton(
                      icon: Icons.save_rounded,
                      label: AppLanguage.text("saveMedication"),
                      onPressed: isSaving ? null : saveMedication,
                      isLoading: isSaving,
                    ),
                    if (widget.medication != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: isSaving ? null : deleteMedication,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          tr("Delete medication", "Xoá thuốc"),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
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

class ManualReminderTimesCard extends StatelessWidget {
  final bool enabled;
  final List<TimeOfDay> times;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  const ManualReminderTimesCard({
    super.key,
    required this.enabled,
    required this.times,
    required this.onEnabledChanged,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: enabled
            ? AppTheme.lightColor.withValues(alpha: 0.62)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: enabled ? 0.34 : 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: onEnabledChanged,
              secondary: Icon(
                Icons.edit_calendar_rounded,
                color: AppTheme.primaryColor,
              ),
              title: Text(
                language == "en" ? "Set times myself" : "Tự chọn giờ nhắc",
                style: const TextStyle(
                  color: Color(0xFF1E2A3A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                language == "en"
                    ? "Your selected times replace the automatic schedule."
                    : "Giờ bạn chọn sẽ thay thế lịch tự động.",
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            if (times.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  language == "en"
                      ? "No reminder time selected yet."
                      : "Chưa chọn giờ nhắc.",
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              ...times.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onEdit(entry.key),
                          icon: const Icon(Icons.schedule_rounded, size: 19),
                          label: Text(
                            TimeHelper.formatTimeForDisplay(entry.value),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: language == "en" ? "Remove time" : "Xóa giờ",
                        onPressed: () => onRemove(entry.key),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_alarm_rounded),
              label: Text(
                language == "en" ? "Add reminder time" : "Thêm giờ nhắc",
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              language == "en"
                  ? "Verify every time against the prescription label or pharmacist’s directions."
                  : "Hãy kiểm tra từng giờ theo nhãn thuốc hoặc hướng dẫn của dược sĩ.",
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PharmacyCallOptionCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const PharmacyCallOptionCard({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          onChanged(!enabled);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: enabled
                ? AppTheme.primaryColor.withValues(alpha: 0.09)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled
                  ? AppTheme.primaryColor.withValues(alpha: 0.45)
                  : const Color(0xFFD7DFEA),
              width: 1.4,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTheme.primaryColor
                      : const Color(0xFFEAF1FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.add_location_alt_rounded,
                  color: enabled ? Colors.white : AppTheme.primaryColor,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        "Save a care location (Optional)",
                        "Lưu cơ sở y tế (Không bắt buộc)",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      enabled
                          ? tr(
                              "Search a pharmacy, doctor, clinic, or hospital below. A saved phone number can be used when medicine is low.",
                              "Tìm nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện bên dưới. Có thể dùng số điện thoại đã lưu khi thuốc sắp hết.",
                            )
                          : tr(
                              "Turn this on to search and save a pharmacy, doctor, clinic, or hospital.",
                              "Bật để tìm và lưu nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện.",
                            ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.35,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: AppTheme.primaryColor,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MedicineStatusPreviewCard extends StatelessWidget {
  final String quantityText;
  final String remainingQuantityText;

  const MedicineStatusPreviewCard({
    super.key,
    required this.quantityText,
    required this.remainingQuantityText,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalQuantity = parseQuantityNumber(quantityText);
    final remainingQuantity = remainingQuantityText.trim().isEmpty
        ? totalQuantity
        : parseQuantityNumber(remainingQuantityText);

    String status;
    String message;
    Color color;
    IconData icon;

    if (quantityText.trim().isEmpty) {
      status = tr("Quantity not entered", "Chưa nhập số lượng");
      message = tr(
        "Enter total quantity and remaining quantity to see the medicine status.",
        "Nhập tổng số lượng và số lượng còn lại để xem trạng thái thuốc.",
      );
      color = AppTheme.primaryColor;
      icon = Icons.inventory_2_rounded;
    } else if (totalQuantity <= 0) {
      status = tr("Check quantity", "Kiểm tra số lượng");
      message = tr(
        "Total quantity must be greater than 0.",
        "Tổng số lượng phải lớn hơn 0.",
      );
      color = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else if (remainingQuantity > totalQuantity) {
      status = tr("Check quantity", "Kiểm tra số lượng");
      message = tr(
        "Remaining quantity cannot be greater than total quantity.",
        "Số lượng còn lại không thể lớn hơn tổng số lượng.",
      );
      color = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else if (remainingQuantity <= 0) {
      status = tr("OUT OF MEDICINE", "ĐÃ HẾT THUỐC");
      message = tr(
        "Refill this medicine before the next dose.",
        "Hãy refill thuốc này trước liều tiếp theo.",
      );
      color = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else if (remainingQuantity / totalQuantity <= 0.05) {
      status = tr("LOW - NEED REFILL", "SẮP HẾT - CẦN REFILL");
      message = tr(
        "Medicine is low. Plan a refill soon.",
        "Thuốc sắp hết. Hãy chuẩn bị refill sớm.",
      );
      color = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_rounded;
    } else if (remainingQuantity == totalQuantity) {
      status = tr("FULL", "ĐẦY");
      message = tr("Medicine quantity looks full.", "Số lượng thuốc đang đầy.");
      color = const Color(0xFF22C55E);
      icon = Icons.check_circle_rounded;
    } else {
      status = tr("OK", "ỔN");
      message = tr("Medicine quantity looks okay.", "Số lượng thuốc còn ổn.");
      color = const Color(0xFF22C55E);
      icon = Icons.check_circle_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
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
                  tr("Medicine Status", "Trạng Thái Thuốc"),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontSize:
                        status.contains("OUT") ||
                            status.contains("HẾT") ||
                            status.contains("LOW") ||
                            status.contains("REFILL")
                        ? 22
                        : 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (totalQuantity > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      "Remaining: $remainingQuantity of $totalQuantity",
                      "Còn lại: $remainingQuantity trên $totalQuantity",
                    ),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
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

class MedicationSuggestionList extends StatelessWidget {
  final String query;
  final List<RxNormSuggestion> suggestions;
  final bool isSearching;
  final String message;
  final VoidCallback? onInteractionStart;
  final ValueChanged<RxNormSuggestion> onSelected;

  const MedicationSuggestionList({
    super.key,
    required this.query,
    required this.suggestions,
    required this.isSearching,
    required this.message,
    this.onInteractionStart,
    required this.onSelected,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  TextSpan highlightedName(String value) {
    final cleanQuery = query.trim();
    final matchIndex = value.toLowerCase().indexOf(cleanQuery.toLowerCase());

    if (cleanQuery.isEmpty || matchIndex < 0) {
      return TextSpan(text: value);
    }

    final matchEnd = matchIndex + cleanQuery.length;

    return TextSpan(
      children: [
        if (matchIndex > 0) TextSpan(text: value.substring(0, matchIndex)),
        TextSpan(
          text: value.substring(matchIndex, matchEnd),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        if (matchEnd < value.length) TextSpan(text: value.substring(matchEnd)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.22),
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < suggestions.length; index++) ...[
              InkWell(
                onTapDown: (_) {
                  onInteractionStart?.call();
                },
                onTap: () => onSelected(suggestions[index]),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        suggestions[index].isSavedMedication
                            ? Icons.history_rounded
                            : Icons.search_rounded,
                        color: const Color(0xFF344054),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              highlightedName(suggestions[index].name),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1E2A3A),
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              suggestions[index].detailText(
                                vietnamese:
                                    AppLanguage.currentLanguage.value == "vi",
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 11.5,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.north_west_rounded,
                        size: 20,
                        color: Color(0xFF475467),
                      ),
                    ],
                  ),
                ),
              ),
              if (index < suggestions.length - 1)
                Divider(
                  height: 1,
                  indent: 50,
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                ),
            ],
            if (isSearching)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr(
                          "Finding more verified medication names...",
                          "Đang tìm thêm tên thuốc đã được chuẩn hóa...",
                        ),
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!isSearching && message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
              color: AppTheme.primaryColor.withValues(alpha: 0.05),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 17,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      tr(
                        "Suggestions help with names and strength only. Confirm the bottle label or prescription before saving.",
                        "Gợi ý chỉ hỗ trợ tên và hàm lượng. Hãy kiểm tra nhãn chai hoặc toa thuốc trước khi lưu.",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF475467),
                        fontSize: 10.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
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

class DetailsInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  const DetailsInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.focusNode,
    this.onChanged,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, color: AppTheme.primaryColor),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.18),
            width: 1.4,
          ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class LiveDosePreviewCard extends StatelessWidget {
  final String scheduleDirections;
  final String doseDirections;

  const LiveDosePreviewCard({
    super.key,
    required this.scheduleDirections,
    required this.doseDirections,
  });

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    final doseAmount = TimeHelper.getDoseAmountFromInstructions(doseDirections);
    final instructionInterpretation = TimeHelper.interpretInstruction(
      scheduleDirections,
    );

    final times = TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirections,
    );

    final isEmpty = scheduleDirections.trim().isEmpty;
    final isAsNeeded = TimeHelper.isAsNeededInstruction(scheduleDirections);
    final needsManualReview = !isEmpty && !isAsNeeded && times.isEmpty;

    String message;

    if (isEmpty) {
      message = language == "en"
          ? "Enter timing in Instructions or Description/Notes to preview reminder times."
          : "Nhập thời gian trong Hướng dẫn hoặc Mô tả/Ghi chú để xem trước giờ nhắc.";
    } else if (isAsNeeded) {
      message = language == "en"
          ? "As-needed medication detected.\nDose amount: $doseAmount\nNo fixed reminder times will be created."
          : "Đã nhận diện thuốc dùng khi cần.\nSố lượng mỗi liều: $doseAmount\nSẽ không tạo giờ nhắc cố định.";
    } else if (needsManualReview) {
      message = language == "en"
          ? "Manual review needed.\nDose amount: $doseAmount\nThe app did not guess a time. Save the medication, then add and verify the time on its reminder screen."
          : "Cần kiểm tra thủ công.\nSố lượng mỗi liều: $doseAmount\nỨng dụng không đoán giờ. Hãy lưu thuốc, sau đó thêm và xác minh giờ trong màn hình nhắc.";
    } else {
      final timeText = times
          .map((time) {
            return TimeHelper.formatTimeForDisplay(time);
          })
          .join(", ");

      final explanation = TimeHelper.explainGeneratedSchedule(
        scheduleDirections,
      );

      message = language == "en"
          ? "Live preview\nDose amount: $doseAmount\nAuto reminder times: $timeText\n\nWhy these times: $explanation"
          : "Xem trước\nSố lượng mỗi liều: $doseAmount\nGiờ nhắc tự động: $timeText\n\nLý do chọn giờ: $explanation";
    }

    if (instructionInterpretation.usedSpellingAssistance) {
      final correctionSummary = instructionInterpretation.correctionSummary();

      message = language == "en"
          ? "$message\n\nSpelling help used: $correctionSummary. Your original text was kept—verify the dose and times."
          : "$message\n\nĐã hỗ trợ chính tả: $correctionSummary. Nội dung bạn nhập vẫn được giữ—hãy kiểm tra liều và giờ.";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isAsNeeded || needsManualReview || isEmpty
            ? const Color(0xFFF59E0B).withValues(alpha: 0.09)
            : AppTheme.lightColor.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isAsNeeded || needsManualReview || isEmpty
              ? const Color(0xFFF59E0B).withValues(alpha: 0.28)
              : AppTheme.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAsNeeded || needsManualReview || isEmpty
                ? Icons.info_outline_rounded
                : Icons.auto_awesome_rounded,
            color: isAsNeeded || needsManualReview || isEmpty
                ? const Color(0xFFF59E0B)
                : AppTheme.primaryColor,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TreatmentLengthQuickCard extends StatelessWidget {
  final void Function(int days) onSelectDays;

  const TreatmentLengthQuickCard({super.key, required this.onSelectDays});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            language == "en"
                ? "Quick Treatment Length"
                : "Chọn Nhanh Thời Gian Điều Trị",
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              QuickDaysButton(days: 7, onTap: onSelectDays),
              QuickDaysButton(days: 10, onTap: onSelectDays),
              QuickDaysButton(days: 14, onTap: onSelectDays),
              QuickDaysButton(days: 30, onTap: onSelectDays),
            ],
          ),
        ],
      ),
    );
  }
}

class QuickDaysButton extends StatelessWidget {
  final int days;
  final void Function(int days) onTap;

  const QuickDaysButton({super.key, required this.days, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    return OutlinedButton(
      onPressed: () {
        onTap(days);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        language == "en" ? "$days days" : "$days ngày",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class SupplyPreviewCard extends StatelessWidget {
  final String scheduleDirections;
  final String doseDirections;
  final String quantityText;
  final String remainingQuantityText;
  final DateTime? startDate;
  final DateTime? endDate;

  const SupplyPreviewCard({
    super.key,
    required this.scheduleDirections,
    required this.doseDirections,
    required this.quantityText,
    required this.remainingQuantityText,
    required this.startDate,
    required this.endDate,
  });

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.currentLanguage.value;

    final doseAmount = TimeHelper.getDoseAmountFromInstructions(doseDirections);

    final times = TimeHelper.generateReminderTimesFromInstructions(
      scheduleDirections,
    );

    final dosesPerDay = times.length;
    final totalQuantity = parseQuantityNumber(quantityText);
    final remainingQuantity = remainingQuantityText.trim().isEmpty
        ? totalQuantity
        : parseQuantityNumber(remainingQuantityText);

    String title = language == "en" ? "Supply Preview" : "Xem Trước Số Lượng";
    String message;
    Color color = AppTheme.primaryColor;

    if (TimeHelper.isAsNeededInstruction(scheduleDirections)) {
      color = const Color(0xFFF59E0B);
      message = language == "en"
          ? "As-needed medication detected. Supply need depends on use, so the app will not calculate a fixed quantity."
          : "Đã nhận diện thuốc dùng khi cần. Số lượng cần dùng phụ thuộc vào thực tế, nên ứng dụng sẽ không tính số lượng cố định.";
    } else if (scheduleDirections.trim().isNotEmpty && times.isEmpty) {
      color = const Color(0xFFF59E0B);
      message = language == "en"
          ? "This schedule needs manual review. Add and verify reminder times before using a supply estimate."
          : "Lịch này cần kiểm tra thủ công. Hãy thêm và xác minh giờ nhắc trước khi dùng ước tính số lượng.";
    } else if (startDate == null || endDate == null) {
      message = language == "en"
          ? "Select start date and end date to estimate how much medication is needed."
          : "Chọn ngày bắt đầu và ngày kết thúc để ước tính số lượng thuốc cần dùng.";
    } else if (totalQuantity <= 0) {
      final totalDays = DateHelper.treatmentTotalDays(
        startDate: startDate!,
        endDate: endDate!,
      );

      final neededUnits = totalDays * dosesPerDay * doseAmount;

      message = language == "en"
          ? "Recommended quantity: $neededUnits units for $totalDays days."
          : "Số lượng đề xuất: $neededUnits đơn vị cho $totalDays ngày.";
    } else {
      final totalDays = DateHelper.treatmentTotalDays(
        startDate: startDate!,
        endDate: endDate!,
      );

      final neededUnits = totalDays * dosesPerDay * doseAmount;
      final difference = remainingQuantity - neededUnits;

      if (difference >= 0) {
        color = const Color(0xFF22C55E);
        message = language == "en"
            ? "Looks enough. Need about $neededUnits units for $totalDays days. Extra remaining: $difference."
            : "Có vẻ đủ. Cần khoảng $neededUnits đơn vị cho $totalDays ngày. Còn dư: $difference.";
      } else {
        color = const Color(0xFFEF4444);
        message = language == "en"
            ? "Warning: may be short by ${difference.abs()} units. Need about $neededUnits units for $totalDays days."
            : "Cảnh báo: có thể thiếu ${difference.abs()} đơn vị. Cần khoảng $neededUnits đơn vị cho $totalDays ngày.";
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medical_information_rounded, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "$title\n$message",
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DatePickerCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  const DatePickerCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
