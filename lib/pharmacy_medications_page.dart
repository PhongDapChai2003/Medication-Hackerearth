import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'medication.dart';
import 'medication_details_page.dart';
import 'medication_storage.dart';
import 'reminder_page.dart';
import 'route_transitions.dart';
import 'time_helper.dart';

class PharmacyMedicationsPage extends StatefulWidget {
  final String providerName;
  final String address;
  final String phone;
  final List<Medication> initialMedications;
  final List<Medication> initialAllMedications;

  const PharmacyMedicationsPage({
    super.key,
    required this.providerName,
    required this.address,
    required this.phone,
    required this.initialMedications,
    required this.initialAllMedications,
  });

  @override
  State<PharmacyMedicationsPage> createState() =>
      _PharmacyMedicationsPageState();
}

class _PharmacyMedicationsPageState extends State<PharmacyMedicationsPage> {
  List<Medication> allMedications = <Medication>[];
  List<Medication> medications = <Medication>[];
  bool isRefreshingCloud = false;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    allMedications = List<Medication>.from(widget.initialAllMedications);
    medications = List<Medication>.from(widget.initialMedications);
    MedicationStorage.dataRevision.addListener(refreshFromLocal);
    MedicationStorage.syncStatus.addListener(refreshAfterCloudSync);
    unawaited(refreshFromLocal());
  }

  String normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[\s,.;]+"), " ")
        .trim();
  }

  String normalizePhone(String value) {
    return value.replaceAll(RegExp(r"[^0-9+]"), "");
  }

  List<Medication> medicationsForThisProvider(List<Medication> loaded) {
    final initialIds = widget.initialMedications
        .map((medication) => medication.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final targetAddress = normalize(widget.address);
    final targetProvider = normalize(widget.providerName);
    final targetPhone = normalizePhone(widget.phone);

    return loaded.where((medication) {
      if (targetAddress.isNotEmpty) {
        return normalize(medication.pharmacyAddress) == targetAddress;
      }

      if (targetProvider.isNotEmpty || targetPhone.isNotEmpty) {
        final providerMatches =
            targetProvider.isEmpty ||
            normalize(medication.pharmacyName) == targetProvider;
        final phoneMatches =
            targetPhone.isEmpty ||
            normalizePhone(medication.pharmacyPhone) == targetPhone;

        return providerMatches && phoneMatches;
      }

      return initialIds.contains(medication.id.trim());
    }).toList();
  }

  void applyLoadedMedications(List<Medication> loaded) {
    if (!mounted) {
      return;
    }

    setState(() {
      allMedications = loaded;
      medications = medicationsForThisProvider(loaded);
    });
  }

  Future<void> refreshFromLocal() async {
    final loaded = await MedicationStorage.loadCurrentLocalMedications();
    applyLoadedMedications(loaded);
  }

  Future<void> refreshFromCloud() async {
    if (isRefreshingCloud) {
      return;
    }

    isRefreshingCloud = true;

    try {
      final loaded = await MedicationStorage.loadMedications();
      applyLoadedMedications(loaded);
    } finally {
      isRefreshingCloud = false;
    }
  }

  Future<void> refreshEverything() async {
    await refreshFromLocal();
    await refreshFromCloud();
  }

  void refreshAfterCloudSync() {
    if (MedicationStorage.syncStatus.value.state ==
        MedicationSyncState.synced) {
      unawaited(refreshFromLocal());
    }
  }

  Future<void> callProvider() async {
    final cleanPhone = normalizePhone(widget.phone);

    if (cleanPhone.isEmpty) {
      return;
    }

    try {
      final opened = await launchUrl(
        Uri(scheme: "tel", path: cleanPhone),
        mode: LaunchMode.externalApplication,
      );

      if (opened || !mounted) {
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

  int medicationIndex(Medication medication) {
    final id = medication.id.trim();

    if (id.isNotEmpty) {
      return allMedications.indexWhere((item) => item.id.trim() == id);
    }

    return allMedications.indexOf(medication);
  }

  Future<void> openMedication(Medication medication) async {
    final index = medicationIndex(medication);

    if (index < 0) {
      return;
    }

    await Navigator.push<void>(
      context,
      slowPageRoute(
        builder: (context) => ReminderPage(
          medication: allMedications[index],
          medicationIndex: index,
        ),
      ),
    );

    await refreshFromLocal();
  }

  Future<void> editMedication(Medication medication) async {
    final index = medicationIndex(medication);

    if (index < 0) {
      return;
    }

    await Navigator.push<void>(
      context,
      slowPageRoute(
        builder: (context) => MedicationDetailsPage(
          medication: allMedications[index],
          medicationIndex: index,
        ),
      ),
    );

    await refreshFromLocal();
  }

  String reminderText(Medication medication) {
    final times = medication.reminderTimes
        .map(TimeHelper.stringToTime)
        .map(TimeHelper.formatTimeForDisplay)
        .toList();

    if (times.isEmpty) {
      return tr("Open to view schedule", "Mở để xem lịch uống");
    }

    return times.join(" • ");
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(refreshFromLocal);
    MedicationStorage.syncStatus.removeListener(refreshAfterCloudSync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providerName = widget.providerName.trim().isEmpty
        ? tr("Provider", "Cơ sở")
        : widget.providerName.trim();
    final address = widget.address.trim().isEmpty
        ? tr(
            "No address saved. Edit a medication to add it.",
            "Chưa lưu địa chỉ. Hãy sửa thuốc để thêm địa chỉ.",
          )
        : widget.address.trim();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppTheme.primaryColor,
            onRefresh: refreshEverything,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppTheme.pagePadding(context),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        tr("Pharmacy Medications", "Thuốc Theo Cơ Sở"),
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.lightColor.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: Icon(
                              Icons.local_pharmacy_rounded,
                              color: AppTheme.primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  providerName,
                                  style: const TextStyle(
                                    color: Color(0xFF1E2A3A),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  address,
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
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
                      if (widget.phone.trim().isNotEmpty) ...[
                        const SizedBox(height: 15),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: callProvider,
                            icon: const Icon(Icons.call_rounded),
                            label: Text(
                              "${tr("Call", "Gọi")} ${widget.phone.trim()}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        tr(
                          "Medications from this location",
                          "Thuốc từ cơ sở này",
                        ),
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.lightColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        "${medications.length}",
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                if (medications.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      tr(
                        "No medications are currently saved for this location.",
                        "Hiện chưa có thuốc nào được lưu cho cơ sở này.",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  ...medications.map((medication) {
                    return PharmacyMedicationCard(
                      medication: medication,
                      reminderText: reminderText(medication),
                      onTap: () {
                        openMedication(medication);
                      },
                      onEdit: () {
                        editMedication(medication);
                      },
                    );
                  }),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PharmacyMedicationCard extends StatelessWidget {
  final Medication medication;
  final String reminderText;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const PharmacyMedicationCard({
    super.key,
    required this.medication,
    required this.reminderText,
    required this.onTap,
    required this.onEdit,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Material(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(23),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.lightColor.withValues(alpha: 0.8),
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
                    children: <Widget>[
                      Text(
                        medication.name.trim().isEmpty
                            ? tr("Medication", "Thuốc")
                            : medication.name,
                        style: const TextStyle(
                          color: Color(0xFF1E2A3A),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (medication.dosage.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          medication.dosage,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      if (medication.instructions.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          medication.instructions,
                          style: const TextStyle(
                            color: Color(0xFF475467),
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.schedule_rounded,
                            color: AppTheme.primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              reminderText,
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (medication.remainingQuantity.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          "${tr("Remaining", "Còn lại")}: ${medication.remainingQuantity}",
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
                IconButton(
                  tooltip: tr("Edit medication", "Sửa thuốc"),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  color: const Color(0xFF667085),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
