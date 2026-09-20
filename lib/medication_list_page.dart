import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'date_helper.dart';
import 'medication.dart';
import 'medication_details_page.dart';
import 'medication_storage.dart';
import 'pharmacy_medications_page.dart';
import 'reminder_page.dart';
import 'route_transitions.dart';
import 'scan_page.dart';
import 'time_helper.dart';

enum _MedicationAddMethod { camera, manual, photoLibrary }

class MedicationLocationGroup {
  final String key;
  final List<Medication> medications;

  MedicationLocationGroup({required this.key, required this.medications});

  String get address {
    for (final medication in medications) {
      if (medication.pharmacyAddress.trim().isNotEmpty) {
        return medication.pharmacyAddress.trim();
      }
    }

    return "";
  }

  String get providerName {
    for (final medication in medications) {
      if (medication.pharmacyName.trim().isNotEmpty) {
        return medication.pharmacyName.trim();
      }
    }

    return "";
  }

  String get phone {
    for (final medication in medications) {
      if (medication.pharmacyPhone.trim().isNotEmpty) {
        return medication.pharmacyPhone.trim();
      }
    }

    return "";
  }
}

List<MedicationLocationGroup> groupMedicationsByAddress(
  List<Medication> medications,
) {
  final groups = <String, MedicationLocationGroup>{};

  for (int index = 0; index < medications.length; index++) {
    final medication = medications[index];
    final normalizedAddress = normalizeMedicationLocationValue(
      medication.pharmacyAddress,
    );
    final normalizedProviderName = normalizeMedicationLocationValue(
      medication.pharmacyName,
    );
    final normalizedPhone = medication.pharmacyPhone.replaceAll(
      RegExp(r"[^0-9+]"),
      "",
    );
    final providerIdentity = [
      normalizedProviderName,
      normalizedPhone,
    ].where((value) => value.isNotEmpty).join("|");
    final key = normalizedAddress.isNotEmpty
        ? "address:$normalizedAddress"
        : providerIdentity.isNotEmpty
        ? "provider:$providerIdentity"
        : "ungrouped:${medication.id.trim().isNotEmpty ? medication.id.trim() : index}";

    groups.putIfAbsent(
      key,
      () => MedicationLocationGroup(key: key, medications: <Medication>[]),
    );
    groups[key]!.medications.add(medication);
  }

  return groups.values.toList();
}

String normalizeMedicationLocationValue(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r"[\s,.;]+"), " ").trim();
}

class MedicationListPage extends StatefulWidget {
  final bool embeddedInHomeShell;
  final VoidCallback? onOpenScanAdd;

  const MedicationListPage({
    super.key,
    this.embeddedInHomeShell = false,
    this.onOpenScanAdd,
  });

  @override
  State<MedicationListPage> createState() => MedicationListPageState();
}

class MedicationListPageState extends State<MedicationListPage> {
  final TextEditingController searchController = TextEditingController();

  List<Medication> medications = [];
  String selectedFilter = "all";
  bool isLoading = true;
  bool isRefreshingCloud = false;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    MedicationStorage.dataRevision.addListener(refreshFromLocal);
    loadMedications();
  }

  Future<void> refreshFromLocal() async {
    final loadedMedications =
        await MedicationStorage.loadCurrentLocalMedications();

    if (!mounted) return;
    setState(() {
      medications = loadedMedications;
      isLoading = false;
    });
  }

  Future<void> loadMedications() async {
    await refreshFromLocal();
    unawaited(refreshFromCloud());
  }

  Future<void> refreshFromCloud() async {
    if (isRefreshingCloud) {
      return;
    }

    isRefreshingCloud = true;

    try {
      final loadedMedications = await MedicationStorage.loadMedications();

      if (!mounted) {
        return;
      }

      setState(() {
        medications = loadedMedications;
        isLoading = false;
      });
    } finally {
      isRefreshingCloud = false;
    }
  }

  Future<void> refreshEverything() async {
    await refreshFromLocal();
    await refreshFromCloud();
  }

  List<Medication> get filteredMedications {
    final searchText = searchController.text.trim().toLowerCase();

    final filtered = medications.where((medication) {
      final matchesSearch =
          medication.name.toLowerCase().contains(searchText) ||
          medication.dosage.toLowerCase().contains(searchText) ||
          medication.instructions.toLowerCase().contains(searchText) ||
          medication.notes.toLowerCase().contains(searchText) ||
          medication.pharmacyName.toLowerCase().contains(searchText) ||
          medication.pharmacyAddress.toLowerCase().contains(searchText) ||
          medication.pharmacyPhone.toLowerCase().contains(searchText);

      if (!matchesSearch) {
        return false;
      }

      if (selectedFilter == "all") {
        return true;
      }

      if (selectedFilter == "active") {
        return getTreatmentStatus(medication) == "active";
      }

      if (selectedFilter == "low") {
        return isLowQuantity(medication);
      }

      if (selectedFilter == "ended") {
        return getTreatmentStatus(medication) == "ended";
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      final aIsOut = isOutOfMedication(a);
      final bIsOut = isOutOfMedication(b);

      if (aIsOut && !bIsOut) {
        return -1;
      }

      if (!aIsOut && bIsOut) {
        return 1;
      }

      final aIsLow = isLowQuantity(a);
      final bIsLow = isLowQuantity(b);

      if (aIsLow && !bIsLow) {
        return -1;
      }

      if (!aIsLow && bIsLow) {
        return 1;
      }

      return medications.indexOf(a).compareTo(medications.indexOf(b));
    });

    return filtered;
  }

  String getTreatmentStatus(Medication medication) {
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);
    final today = DateHelper.dateOnly(DateTime.now());

    if (startDate != null && today.isBefore(DateHelper.dateOnly(startDate))) {
      return "upcoming";
    }

    if (endDate != null && today.isAfter(DateHelper.dateOnly(endDate))) {
      return "ended";
    }

    return "active";
  }

  String getTreatmentStatusText(Medication medication) {
    final status = getTreatmentStatus(medication);

    if (status == "upcoming") {
      return tr("Not started", "Chưa bắt đầu");
    }

    if (status == "ended") {
      return tr("Ended", "Đã kết thúc");
    }

    return tr("Active", "Đang dùng");
  }

  Color getTreatmentStatusColor(Medication medication) {
    final status = getTreatmentStatus(medication);

    if (status == "upcoming") {
      return const Color(0xFF3B82F6);
    }

    if (status == "ended") {
      return const Color(0xFFEF4444);
    }

    return const Color(0xFF22C55E);
  }

  int parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  int totalQuantity(Medication medication) {
    return parseQuantityNumber(medication.quantity);
  }

  int remainingQuantity(Medication medication) {
    final total = totalQuantity(medication);

    if (total <= 0) {
      return 0;
    }

    if (medication.remainingQuantity.trim().isEmpty) {
      return total;
    }

    return parseQuantityNumber(medication.remainingQuantity);
  }

  double quantityProgress(Medication medication) {
    final total = totalQuantity(medication);
    final remaining = remainingQuantity(medication);

    if (total <= 0) {
      return 0;
    }

    return (remaining / total).clamp(0.0, 1.0);
  }

  bool isOutOfMedication(Medication medication) {
    final total = totalQuantity(medication);

    if (total <= 0) {
      return false;
    }

    return remainingQuantity(medication) <= 0;
  }

  bool isLowQuantity(Medication medication) {
    final total = totalQuantity(medication);
    final remaining = remainingQuantity(medication);

    if (total <= 0) {
      return false;
    }

    return remaining / total <= 0.05;
  }

  bool hasQuantity(Medication medication) {
    return totalQuantity(medication) > 0;
  }

  String getQuantityText(Medication medication) {
    if (!hasQuantity(medication)) {
      return tr("Quantity not entered", "Chưa nhập số lượng");
    }

    if (isOutOfMedication(medication)) {
      return tr(
        "OUT OF MEDICINE • 0 of ${totalQuantity(medication)} left",
        "ĐÃ HẾT THUỐC • còn 0 trên ${totalQuantity(medication)}",
      );
    }

    return tr(
      "Remaining ${remainingQuantity(medication)} of ${totalQuantity(medication)}",
      "Còn lại ${remainingQuantity(medication)} trên ${totalQuantity(medication)}",
    );
  }

  List<TimeOfDay> getReminderTimes(Medication medication) {
    if (medication.reminderTimes.isNotEmpty) {
      return medication.reminderTimes.map((time) {
        return TimeHelper.stringToTime(time);
      }).toList();
    }

    final scheduleDirections = TimeHelper.selectScheduleDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );

    return TimeHelper.generateReminderTimesFromInstructions(scheduleDirections);
  }

  bool isAsNeededMedication(Medication medication) {
    final scheduleDirections = TimeHelper.selectScheduleDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );

    return TimeHelper.isAsNeededInstruction(scheduleDirections);
  }

  String getNextDoseText(Medication medication) {
    final nextDose = TimeHelper.getNextDoseDateTime(
      getReminderTimes(medication),
    );

    if (nextDose == null) {
      return "--";
    }

    return TimeHelper.formatDateTimeAsDisplayTime(nextDose);
  }

  String getTodayDoseSummary(Medication medication) {
    final today = DateHelper.todayString();

    int takenCount = 0;
    int missedCount = 0;

    medication.doseRecords.forEach((key, value) {
      if (!key.startsWith("$today|")) {
        return;
      }

      if (value == "taken") {
        takenCount++;
      }

      if (value == "missed") {
        missedCount++;
      }
    });

    if (takenCount == 0 && missedCount == 0) {
      return tr("No dose marked today", "Chưa đánh dấu liều hôm nay");
    }

    return tr(
      "$takenCount taken • $missedCount missed",
      "$takenCount đã uống • $missedCount bỏ lỡ",
    );
  }

  Future<void> openMedicationDetails({
    Medication? medication,
    int medicationIndex = -1,
  }) async {
    final didSave = await Navigator.push(
      context,
      slowPageRoute(
        builder: (context) => MedicationDetailsPage(
          medication: medication,
          medicationIndex: medicationIndex,
        ),
      ),
    );

    if (didSave == true) {
      await loadMedications();
    }
  }

  Future<void> openMedicationScanner({
    bool openPhotoLibraryOnStart = false,
  }) async {
    final didSave = await Navigator.push<bool>(
      context,
      slowPageRoute(
        builder: (context) =>
            ScanPage(openPhotoLibraryOnStart: openPhotoLibraryOnStart),
      ),
    );

    if (didSave == true) {
      await loadMedications();
    }
  }

  Future<void> openAddMedicationMenu() async {
    if (widget.embeddedInHomeShell && widget.onOpenScanAdd != null) {
      widget.onOpenScanAdd!();
      return;
    }

    final selectedMethod = await showModalBottomSheet<_MedicationAddMethod>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xFF172033).withValues(alpha: 0.42),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return const AddMedicationChoiceSheet();
      },
    );

    if (!mounted || selectedMethod == null) {
      return;
    }

    switch (selectedMethod) {
      case _MedicationAddMethod.camera:
        await openMedicationScanner();
      case _MedicationAddMethod.manual:
        await openMedicationDetails();
      case _MedicationAddMethod.photoLibrary:
        await openMedicationScanner(openPhotoLibraryOnStart: true);
    }
  }

  Future<void> openReminderPage(Medication medication, int index) async {
    final didChange = await Navigator.push(
      context,
      slowPageRoute(
        builder: (context) =>
            ReminderPage(medication: medication, medicationIndex: index),
      ),
    );

    if (didChange == true) {
      await loadMedications();
    }
  }

  Future<void> openPharmacyGroup(MedicationLocationGroup group) async {
    await Navigator.push<void>(
      context,
      slowPageRoute<void>(
        builder: (context) {
          return PharmacyMedicationsPage(
            providerName: group.providerName,
            address: group.address,
            phone: group.phone,
            initialMedications: List<Medication>.from(group.medications),
            initialAllMedications: List<Medication>.from(medications),
          );
        },
      ),
    );

    await refreshFromLocal();
  }

  Future<bool> confirmRefillPickup(Medication medication) async {
    final name = medication.name.trim().isEmpty
        ? tr("this medication", "thuốc này")
        : medication.name.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            tr(
              "Did you already pick up the refill?",
              "Bạn đã nhận thuốc refill chưa?",
            ),
          ),
          content: Text(
            tr(
              "Only tap Yes after you already got $name from the pharmacy. The app will set the remaining quantity back to full.",
              "Chỉ bấm Có sau khi bạn đã nhận $name từ nhà thuốc. Ứng dụng sẽ đặt số lượng còn lại về đầy.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(tr("Cancel", "Huỷ")),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                tr("Yes, I Got It", "Có, Đã Nhận"),
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

  Future<void> markMedicationRefilled(int index) async {
    if (index < 0 || index >= medications.length) {
      return;
    }

    final medication = medications[index];
    final total = medication.quantity.trim();

    if (total.isEmpty || parseQuantityNumber(total) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "Please enter total quantity first.",
              "Vui lòng nhập tổng số lượng trước.",
            ),
          ),
        ),
      );
      return;
    }

    final confirmed = await confirmRefillPickup(medication);

    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }

    final previousMedication = medication;

    final refilledMedication = medication.copyWith(remainingQuantity: total);

    final updated = await MedicationStorage.updateMedicationById(
      medication.id,
      refilledMedication,
    );
    await loadMedications();

    if (!mounted) {
      return;
    }

    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "This medication was removed before the refill was saved.",
              "Thuốc này đã bị xoá trước khi refill được lưu.",
            ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            "Refill saved. Remaining quantity is full now.",
            "Đã lưu refill. Số lượng thuốc đã đầy lại.",
          ),
        ),
        action: SnackBarAction(
          label: tr("Undo", "Hoàn tác"),
          onPressed: () async {
            await MedicationStorage.updateMedicationById(
              previousMedication.id,
              previousMedication,
            );
            await loadMedications();
          },
        ),
      ),
    );
  }

  Future<void> deleteMedication(int index) async {
    final deletedMedication = medications[index];

    final deleted = await MedicationStorage.deleteMedicationById(
      deletedMedication.id,
    );
    if (!deleted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "This medication was already removed.",
              "Thuốc này đã được xoá rồi.",
            ),
          ),
        ),
      );
      await loadMedications();
      return;
    }
    await loadMedications();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            "Deleted ${deletedMedication.name}",
            "Đã xoá ${deletedMedication.name}",
          ),
        ),
        action: SnackBarAction(
          label: tr("Undo", "Hoàn tác"),
          onPressed: () async {
            final currentMedications =
                await MedicationStorage.loadMedications();
            currentMedications.insert(index, deletedMedication);
            await MedicationStorage.saveMedicationList(currentMedications);
            await loadMedications();
          },
        ),
      ),
    );
  }

  Future<void> confirmDeleteMedication(int index) async {
    final medication = medications[index];

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr("Delete medication?", "Xoá thuốc?")),
          content: Text(
            tr(
              "Are you sure you want to delete ${medication.name}?",
              "Bạn có chắc muốn xoá ${medication.name} không?",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text(tr("Cancel", "Huỷ")),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(
                tr("Delete", "Xoá"),
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

    if (shouldDelete == true) {
      await deleteMedication(index);
    }
  }

  Future<void> callProvider(String phoneNumber) async {
    final cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r"[^0-9+]"), "");

    if (cleanPhoneNumber.isEmpty) {
      return;
    }

    final uri = Uri(scheme: "tel", path: cleanPhoneNumber);

    try {
      final didOpen = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (didOpen || !mounted) {
        return;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            "This device cannot open the phone dialer.",
            "Thiết bị này không mở được trình gọi điện.",
          ),
        ),
      ),
    );
  }

  Widget buildMedicationCard(Medication medication) {
    final realIndex = medications.indexOf(medication);
    final times = getReminderTimes(medication);

    return MedicationCard(
      medication: medication,
      nextDoseText: getNextDoseText(medication),
      todaySummary: getTodayDoseSummary(medication),
      treatmentStatusText: getTreatmentStatusText(medication),
      treatmentStatusColor: getTreatmentStatusColor(medication),
      quantityText: getQuantityText(medication),
      quantityProgress: quantityProgress(medication),
      hasQuantity: hasQuantity(medication),
      isLowQuantity: isLowQuantity(medication),
      isOutOfMedicine: isOutOfMedication(medication),
      supplyTotalQuantity: totalQuantity(medication),
      supplyRemainingQuantity: remainingQuantity(medication),
      supplyDoseAmount: TimeHelper.getDoseAmountFromInstructions(
        TimeHelper.combineDoseDirections(
          instructions: medication.instructions,
          notes: medication.notes,
        ),
      ),
      supplyDosesPerDay: times.length,
      isAsNeededMedication: isAsNeededMedication(medication),
      onTap: () {
        openReminderPage(medication, realIndex);
      },
      onEdit: () {
        openMedicationDetails(
          medication: medication,
          medicationIndex: realIndex,
        );
      },
      onRefill: () {
        markMedicationRefilled(realIndex);
      },
      onDelete: () {
        confirmDeleteMedication(realIndex);
      },
    );
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(refreshFromLocal);
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredMedications;
    final locationGroups = groupMedicationsByAddress(filtered);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppTheme.primaryColor,
            onRefresh: refreshEverything,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppTheme.pagePadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.pageMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HeaderRow(
                        title: tr("My Medications", "Thuốc Của Tôi"),
                        onBack: widget.embeddedInHomeShell
                            ? null
                            : () {
                                Navigator.pop(context, true);
                              },
                      ),
                      const SizedBox(height: 18),
                      SearchBox(
                        controller: searchController,
                        hint: tr("Search medications...", "Tìm thuốc..."),
                        onChanged: () {
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 14),
                      FilterRow(
                        selectedFilter: selectedFilter,
                        onSelect: (filter) {
                          setState(() {
                            selectedFilter = filter;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      if (isLoading)
                        LoadingCard(
                          text: tr(
                            "Loading medications...",
                            "Đang tải thuốc...",
                          ),
                        )
                      else if (filtered.isEmpty)
                        EmptyMedicationCard(onAdd: openAddMedicationMenu)
                      else
                        Column(
                          children: locationGroups.map((group) {
                            return MedicationLocationGroupSection(
                              group: group,
                              onCall: group.phone.isEmpty
                                  ? null
                                  : () {
                                      callProvider(group.phone);
                                    },
                              onOpen: () {
                                openPharmacyGroup(group);
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HeaderRow extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const HeaderRow({super.key, required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          )
        else ...[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.lightColor,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.medication_rounded, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class MedicationAddPage extends StatefulWidget {
  final Future<void> Function()? onMedicationSaved;

  const MedicationAddPage({super.key, this.onMedicationSaved});

  @override
  State<MedicationAddPage> createState() => _MedicationAddPageState();
}

class _MedicationAddPageState extends State<MedicationAddPage> {
  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> openScanner({bool photos = false}) async {
    final didSave = await Navigator.of(context).push<bool>(
      slowPageRoute(
        builder: (context) => ScanPage(openPhotoLibraryOnStart: photos),
      ),
    );

    if (didSave == true) {
      await widget.onMedicationSaved?.call();
    }
  }

  Future<void> openManualEntry() async {
    final didSave = await Navigator.of(context).push<bool>(
      slowPageRoute(builder: (context) => const MedicationDetailsPage()),
    );

    if (didSave == true) {
      await widget.onMedicationSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: double.infinity,
      decoration: AppTheme.pageDecoration(),
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const PageStorageKey<String>("scan-add-page-scroll"),
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            34 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppTheme.lightColor,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.document_scanner_rounded,
                            color: AppTheme.primaryColor,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr("Scan or Add", "Quét hoặc thêm"),
                                style: const TextStyle(
                                  color: Color(0xFF172033),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tr(
                                  "Choose one simple way to add your medication.",
                                  "Chọn một cách đơn giản để thêm thuốc.",
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 14,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AddMedicationChoiceTile(
                      icon: Icons.camera_alt_rounded,
                      title: tr("Scan with Camera", "Quét bằng camera"),
                      description: tr(
                        "Take clear label photos and let the app fill in the details.",
                        "Chụp rõ nhãn thuốc để ứng dụng tự điền thông tin.",
                      ),
                      onTap: () {
                        openScanner();
                      },
                    ),
                    const SizedBox(height: 14),
                    AddMedicationChoiceTile(
                      icon: Icons.photo_library_rounded,
                      title: tr("Choose from Photos", "Chọn từ thư viện ảnh"),
                      description: tr(
                        "Use medication-label photos already on your device.",
                        "Dùng ảnh nhãn thuốc có sẵn trên thiết bị.",
                      ),
                      onTap: () {
                        openScanner(photos: true);
                      },
                    ),
                    const SizedBox(height: 14),
                    AddMedicationChoiceTile(
                      icon: Icons.edit_note_rounded,
                      title: tr("Enter Manually", "Nhập thủ công"),
                      description: tr(
                        "Type the medication information yourself.",
                        "Tự nhập thông tin thuốc.",
                      ),
                      onTap: openManualEntry,
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr(
                                "Camera and Photos can read the label for you. Manual Entry gives you full control.",
                                "Camera và Ảnh có thể đọc nhãn giúp bạn. Nhập thủ công cho phép bạn tự điền mọi thông tin.",
                              ),
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddMedicationChoiceSheet extends StatelessWidget {
  const AddMedicationChoiceSheet({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  void _select(BuildContext context, _MedicationAddMethod method) {
    Navigator.pop(context, method);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFFDFBFD),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            22 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8DEE8),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.lightColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.medication_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr("Add a medication", "Thêm thuốc"),
                              style: const TextStyle(
                                color: Color(0xFF172033),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tr(
                                "Choose the easiest way for you.",
                                "Chọn cách thuận tiện nhất cho bạn.",
                              ),
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  AddMedicationChoiceTile(
                    icon: Icons.camera_alt_rounded,
                    title: tr("Scan with Camera", "Quét bằng camera"),
                    description: tr(
                      "Take clear label photos and let the app fill in the details.",
                      "Chụp rõ nhãn thuốc để ứng dụng tự điền thông tin.",
                    ),
                    onTap: () {
                      _select(context, _MedicationAddMethod.camera);
                    },
                  ),
                  const SizedBox(height: 12),
                  AddMedicationChoiceTile(
                    icon: Icons.edit_note_rounded,
                    title: tr("Enter Manually", "Nhập thủ công"),
                    description: tr(
                      "Type the medication information yourself.",
                      "Tự nhập thông tin thuốc.",
                    ),
                    onTap: () {
                      _select(context, _MedicationAddMethod.manual);
                    },
                  ),
                  const SizedBox(height: 12),
                  AddMedicationChoiceTile(
                    icon: Icons.photo_library_rounded,
                    title: tr("Choose from Photos", "Chọn từ thư viện ảnh"),
                    description: tr(
                      "Select one or more label photos already on your device.",
                      "Chọn một hoặc nhiều ảnh nhãn thuốc có sẵn trên thiết bị.",
                    ),
                    onTap: () {
                      _select(context, _MedicationAddMethod.photoLibrary);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      tr("Cancel", "Huỷ"),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AddMedicationChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const AddMedicationChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE7EAF0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AppTheme.primaryColor, size: 25),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;

  const SearchBox({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) {
        onChanged();
      },
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search_rounded, color: AppTheme.primaryColor),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      ),
    );
  }
}

class FilterRow extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onSelect;

  const FilterRow({
    super.key,
    required this.selectedFilter,
    required this.onSelect,
  });

  String labelFor(String filter) {
    final language = AppLanguage.currentLanguage.value;

    if (filter == "all") {
      return language == "en" ? "All" : "Tất cả";
    }

    if (filter == "active") {
      return language == "en" ? "Active" : "Đang dùng";
    }

    if (filter == "low") {
      return language == "en" ? "Need Refill" : "Cần Refill";
    }

    return language == "en" ? "Ended" : "Đã hết";
  }

  @override
  Widget build(BuildContext context) {
    final filters = ["all", "active", "low", "ended"];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final selected = selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              selected: selected,
              label: Text(
                labelFor(filter),
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              selectedColor: AppTheme.primaryColor,
              backgroundColor: Colors.white.withValues(alpha: 0.92),
              side: BorderSide(
                color: AppTheme.primaryColor.withValues(alpha: 0.18),
              ),
              onSelected: (_) {
                onSelect(filter);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class MedicationLocationGroupSection extends StatelessWidget {
  final MedicationLocationGroup group;
  final VoidCallback? onCall;
  final VoidCallback onOpen;

  const MedicationLocationGroupSection({
    super.key,
    required this.group,
    required this.onCall,
    required this.onOpen,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final providerName = group.providerName.isEmpty
        ? tr("Provider not saved", "Chưa lưu cơ sở")
        : group.providerName;
    final address = group.address.isEmpty
        ? tr(
            "No address saved — edit this medication to add one.",
            "Chưa lưu địa chỉ — sửa thuốc để thêm địa chỉ.",
          )
        : group.address;

    final visibleMedications = group.medications.take(3).toList();
    final hiddenCount = group.medications.length - visibleMedications.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.18),
                width: 1.3,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.lightColor.withValues(alpha: 0.72),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.local_pharmacy_rounded,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  providerName,
                                  style: const TextStyle(
                                    color: Color(0xFF1E2A3A),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  address,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 13,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              "${group.medications.length}",
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (group.phone.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: onCall,
                            icon: const Icon(Icons.call_rounded, size: 19),
                            label: Text(
                              "${tr("Call", "Gọi")} ${group.phone}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...visibleMedications.map((medication) {
                  return Container(
                    padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF1E5EC))),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.lightColor.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.medication_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                medication.name.trim().isEmpty
                                    ? tr("Medication", "Thuốc")
                                    : medication.name,
                                style: const TextStyle(
                                  color: Color(0xFF1E2A3A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (medication.dosage.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  medication.dosage,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF98A2B3),
                        ),
                      ],
                    ),
                  );
                }),
                if (hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(17, 5, 17, 11),
                    child: Text(
                      tr(
                        "+$hiddenCount more medication${hiddenCount == 1 ? "" : "s"}",
                        "+$hiddenCount thuốc khác",
                      ),
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.fromLTRB(17, 12, 14, 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFF1E5EC))),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          tr(
                            "View this pharmacy and all medications",
                            "Xem cơ sở và tất cả thuốc",
                          ),
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MedicationCard extends StatelessWidget {
  final Medication medication;
  final String nextDoseText;
  final String todaySummary;
  final String treatmentStatusText;
  final Color treatmentStatusColor;
  final String quantityText;
  final double quantityProgress;
  final bool hasQuantity;
  final bool isLowQuantity;
  final bool isOutOfMedicine;
  final int supplyTotalQuantity;
  final int supplyRemainingQuantity;
  final int supplyDoseAmount;
  final int supplyDosesPerDay;
  final bool isAsNeededMedication;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRefill;
  final VoidCallback onDelete;

  const MedicationCard({
    super.key,
    required this.medication,
    required this.nextDoseText,
    required this.todaySummary,
    required this.treatmentStatusText,
    required this.treatmentStatusColor,
    required this.quantityText,
    required this.quantityProgress,
    required this.hasQuantity,
    required this.isLowQuantity,
    required this.isOutOfMedicine,
    required this.supplyTotalQuantity,
    required this.supplyRemainingQuantity,
    required this.supplyDoseAmount,
    required this.supplyDosesPerDay,
    required this.isAsNeededMedication,
    required this.onTap,
    required this.onEdit,
    required this.onRefill,
    required this.onDelete,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final warningColor = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isLowQuantity
                    ? warningColor.withValues(alpha: 0.55)
                    : AppTheme.primaryColor.withValues(alpha: 0.14),
                width: isLowQuantity ? 1.7 : 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLowQuantity) ...[
                  RefillWarningBanner(
                    isOutOfMedicine: isOutOfMedicine,
                    pharmacyName: medication.pharmacyName,
                    pharmacyPhone: medication.pharmacyPhone,
                    onRefill: onRefill,
                    onEditDetails: onEdit,
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppTheme.lightColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.medication_rounded,
                        color: AppTheme.primaryColor,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medication.name.trim().isEmpty
                                ? tr("Medication", "Thuốc")
                                : medication.name,
                            style: const TextStyle(
                              color: Color(0xFF1E2A3A),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            medication.dosage.trim().isEmpty
                                ? medication.instructions
                                : medication.dosage,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == "edit") {
                          onEdit();
                        }

                        if (value == "refill") {
                          onRefill();
                        }

                        if (value == "delete") {
                          onDelete();
                        }
                      },
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            value: "edit",
                            child: Row(
                              children: [
                                const Icon(Icons.edit_rounded, size: 20),
                                const SizedBox(width: 10),
                                Text(tr("Edit", "Sửa")),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: "refill",
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.local_pharmacy_rounded,
                                  size: 20,
                                  color: Color(0xFF22C55E),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  tr("Refill", "Refill"),
                                  style: const TextStyle(
                                    color: Color(0xFF22C55E),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: "delete",
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                  color: Color(0xFFEF4444),
                                ),
                                const SizedBox(width: 10),
                                Text(tr("Delete", "Xoá")),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
                if (medication.instructions.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    medication.instructions,
                    style: const TextStyle(
                      color: Color(0xFF1E2A3A),
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoPill(
                      icon: Icons.schedule_rounded,
                      text: "${tr("Next", "Tiếp")}: $nextDoseText",
                      color: AppTheme.primaryColor,
                    ),
                    InfoPill(
                      icon: Icons.check_circle_rounded,
                      text: todaySummary,
                      color: const Color(0xFF22C55E),
                    ),
                    InfoPill(
                      icon: Icons.info_rounded,
                      text: treatmentStatusText,
                      color: treatmentStatusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                QuantitySection(
                  quantityText: quantityText,
                  quantityProgress: quantityProgress,
                  hasQuantity: hasQuantity,
                  isLowQuantity: isLowQuantity,
                  isOutOfMedicine: isOutOfMedicine,
                ),
                const SizedBox(height: 12),
                SupplyEstimateMiniCard(
                  totalQuantity: supplyTotalQuantity,
                  remainingQuantity: supplyRemainingQuantity,
                  doseAmount: supplyDoseAmount,
                  dosesPerDay: supplyDosesPerDay,
                  isAsNeededMedication: isAsNeededMedication,
                  isOutOfMedicine: isOutOfMedicine,
                ),
                const SizedBox(height: 14),
                Text(
                  "${tr("Start Date", "Ngày bắt đầu")}: ${DateHelper.displayMedicationDate(medication.startDate)}"
                  "   •   "
                  "${tr("End Date", "Ngày kết thúc")}: ${medication.endDate.isEmpty ? tr("No end date", "Không có ngày kết thúc") : DateHelper.displayMedicationDate(medication.endDate)}",
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (medication.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    medication.notes,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RefillWarningBanner extends StatelessWidget {
  final bool isOutOfMedicine;
  final String pharmacyName;
  final String pharmacyPhone;
  final VoidCallback onRefill;
  final VoidCallback onEditDetails;

  const RefillWarningBanner({
    super.key,
    required this.isOutOfMedicine,
    required this.pharmacyName,
    required this.pharmacyPhone,
    required this.onRefill,
    required this.onEditDetails,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final color = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOutOfMedicine) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr("OUT OF MEDICINE", "ĐÃ HẾT THUỐC"),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 21,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(
                isOutOfMedicine
                    ? Icons.error_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isOutOfMedicine
                      ? tr("Refill Needed Now", "Cần Refill Ngay")
                      : tr("Need More Medicine?", "Cần Thêm Thuốc?"),
                  style: TextStyle(
                    color: isOutOfMedicine
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF92400E),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SimplePharmacyListCallBox(
            isOutOfMedicine: isOutOfMedicine,
            pharmacyName: pharmacyName,
            pharmacyPhone: pharmacyPhone,
            onEditDetails: onEditDetails,
          ),
          const SizedBox(height: 12),
          Text(
            isOutOfMedicine
                ? tr(
                    "This medicine is out. Call for a refill now. After you get the medicine, tap the green button.",
                    "Thuốc này đã hết. Gọi để refill ngay. Sau khi nhận thuốc, bấm nút màu xanh.",
                  )
                : tr(
                    "After you get the medicine, tap the green button.",
                    "Sau khi nhận thuốc, bấm nút màu xanh.",
                  ),
            style: TextStyle(
              color: isOutOfMedicine
                  ? const Color(0xFF991B1B)
                  : const Color(0xFF92400E),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onRefill,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.done_all_rounded),
              label: Text(
                tr("I Got My Refill", "Đã Nhận Refill"),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ListPhoneCallButton extends StatelessWidget {
  final String phoneNumber;
  final String label;
  final bool isOutOfMedicine;

  const ListPhoneCallButton({
    super.key,
    required this.phoneNumber,
    required this.label,
    required this.isOutOfMedicine,
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
    final color = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          callPhone(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(82),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_rounded, size: 26, color: Colors.white),
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
                    style: const TextStyle(
                      color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.white,
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

class SimplePharmacyListCallBox extends StatelessWidget {
  final bool isOutOfMedicine;
  final String pharmacyName;
  final String pharmacyPhone;
  final VoidCallback onEditDetails;

  const SimplePharmacyListCallBox({
    super.key,
    required this.isOutOfMedicine,
    required this.pharmacyName,
    required this.pharmacyPhone,
    required this.onEditDetails,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    final hasName = pharmacyName.trim().isNotEmpty;
    final hasPhone = pharmacyPhone.trim().isNotEmpty;

    if (!hasName && !hasPhone) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.24),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr("No pharmacy phone saved.", "Chưa lưu số nhà thuốc."),
              style: const TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              isOutOfMedicine
                  ? tr(
                      "Medicine is out, but no pharmacy phone is saved. Tap Edit to add where the patient got this medicine.",
                      "Thuốc đã hết, nhưng chưa lưu số nhà thuốc. Bấm Sửa để thêm nơi bệnh nhân nhận thuốc.",
                    )
                  : tr(
                      "Tap Edit to add where the patient got this medicine.",
                      "Bấm Sửa để thêm nơi bệnh nhân nhận thuốc.",
                    ),
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onEditDetails,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.edit_rounded),
              label: Text(
                tr("Edit Medication", "Sửa Thuốc"),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF22C55E).withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOutOfMedicine
                ? tr("Call now:", "Gọi ngay:")
                : tr("Call for refill:", "Gọi refill:"),
            style: TextStyle(
              color: isOutOfMedicine
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF1E2A3A),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (hasName) ...[
            const SizedBox(height: 10),
            Text(
              pharmacyName.trim(),
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                fontSize: 21,
                height: 1.2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (hasPhone) ...[
            const SizedBox(height: 12),
            ListPhoneCallButton(
              phoneNumber: pharmacyPhone.trim(),
              label: tr("Call Pharmacy", "Gọi Nhà Thuốc"),
              isOutOfMedicine: isOutOfMedicine,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            tr("Ask them for a refill.", "Hỏi họ refill thuốc."),
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class QuantitySection extends StatelessWidget {
  final String quantityText;
  final double quantityProgress;
  final bool hasQuantity;
  final bool isLowQuantity;
  final bool isOutOfMedicine;

  const QuantitySection({
    super.key,
    required this.quantityText,
    required this.quantityProgress,
    required this.hasQuantity,
    required this.isLowQuantity,
    required this.isOutOfMedicine,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOutOfMedicine
        ? const Color(0xFFEF4444)
        : isLowQuantity
        ? const Color(0xFFF59E0B)
        : AppTheme.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOutOfMedicine
            ? const Color(0xFFEF4444).withValues(alpha: 0.10)
            : AppTheme.lightColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOutOfMedicine
              ? const Color(0xFFEF4444).withValues(alpha: 0.30)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOutOfMedicine ? Icons.error_rounded : Icons.inventory_2_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quantityText,
                  style: TextStyle(
                    color: isOutOfMedicine
                        ? const Color(0xFF991B1B)
                        : hasQuantity
                        ? const Color(0xFF1E2A3A)
                        : const Color(0xFF667085),
                    fontWeight: FontWeight.bold,
                    fontSize: isOutOfMedicine ? 16 : 14,
                  ),
                ),
                if (hasQuantity) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: LinearProgressIndicator(
                      value: quantityProgress,
                      minHeight: 8,
                      color: color,
                      backgroundColor: Colors.white,
                    ),
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

class SupplyEstimateMiniCard extends StatelessWidget {
  final int totalQuantity;
  final int remainingQuantity;
  final int doseAmount;
  final int dosesPerDay;
  final bool isAsNeededMedication;
  final bool isOutOfMedicine;

  const SupplyEstimateMiniCard({
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
    String mainText;
    String helperText;

    if (totalQuantity <= 0) {
      mainText = language == "en"
          ? "Supply Estimate: --"
          : "Ước tính thuốc còn: --";
      helperText = language == "en"
          ? "Enter quantity to estimate days left."
          : "Nhập số lượng để ước tính số ngày còn thuốc.";
      color = AppTheme.primaryColor;
      icon = Icons.inventory_2_rounded;
    } else if (isAsNeededMedication) {
      mainText = language == "en"
          ? "Cannot estimate days left"
          : "Không thể ước tính số ngày";
      helperText = language == "en"
          ? "As-needed medicine depends on how often it is used."
          : "Thuốc dùng khi cần phụ thuộc vào số lần dùng.";
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
      helperText = language == "en" ? "OUT OF MEDICINE" : "ĐÃ HẾT THUỐC";
      color = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else {
      final safeDoseAmount = math.max(1, doseAmount);
      final dailyUse = math.max(1, safeDoseAmount * dosesPerDay);
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
          ? "Estimated empty date: ${DateHelper.displayDate(emptyDate)}"
          : "Có thể hết khoảng: ${DateHelper.displayDate(emptyDate)}";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language == "en" ? "Supply Estimate" : "Ước Tính Thuốc Còn",
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mainText,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  helperText,
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    height: 1.3,
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

class InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const InfoPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class LoadingCard extends StatelessWidget {
  final String text;

  const LoadingCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(width: 14),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyMedicationCard extends StatelessWidget {
  final VoidCallback onAdd;

  const EmptyMedicationCard({super.key, required this.onAdd});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.medication_liquid_rounded,
            color: AppTheme.primaryColor,
            size: 52,
          ),
          const SizedBox(height: 12),
          Text(
            tr("No medications yet", "Chưa có thuốc"),
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              "Add or scan a medication to start tracking reminders.",
              "Thêm hoặc quét thuốc để bắt đầu theo dõi nhắc nhở.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr("Add Medication", "Thêm thuốc")),
          ),
        ],
      ),
    );
  }
}
