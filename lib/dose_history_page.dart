import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'date_helper.dart';
import 'medication.dart';
import 'medication_storage.dart';
import 'time_helper.dart';

class DoseHistoryPage extends StatefulWidget {
  final Medication medication;
  final int medicationIndex;

  const DoseHistoryPage({
    super.key,
    required this.medication,
    required this.medicationIndex,
  });

  @override
  State<DoseHistoryPage> createState() => _DoseHistoryPageState();
}

class _DoseHistoryPageState extends State<DoseHistoryPage> {
  late Medication medication;
  bool isClearing = false;
  bool historyChanged = false;
  bool medicationUnavailable = false;
  String selectedFilter = "all";

  @override
  void initState() {
    super.initState();
    medication = widget.medication;
    MedicationStorage.dataRevision.addListener(refreshMedicationFromLocal);
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(refreshMedicationFromLocal);
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

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  List<DoseHistoryItem> getHistoryItems() {
    final items = <DoseHistoryItem>[];

    medication.doseRecords.forEach((key, status) {
      final parts = key.split("|");

      if (parts.isEmpty) {
        return;
      }

      final dateText = parts[0];
      final date = DateHelper.parseMedicationDate(dateText);

      if (date == null) {
        return;
      }

      final isAsNeeded = parts.length >= 2 && parts[1] == "asNeeded";
      String timeText = "";

      if (isAsNeeded) {
        if (parts.length >= 3) {
          final milliseconds = int.tryParse(parts[2]);

          if (milliseconds != null) {
            final loggedTime = DateTime.fromMillisecondsSinceEpoch(
              milliseconds,
            );

            timeText = TimeHelper.formatTimeForDisplay(
              TimeOfDay(hour: loggedTime.hour, minute: loggedTime.minute),
            );
          }
        }

        if (timeText.isEmpty) {
          timeText = tr("As needed", "Khi cần");
        }
      } else if (parts.length >= 2) {
        timeText = TimeHelper.formatStoredTimeForDisplay(parts[1]);
      }

      items.add(
        DoseHistoryItem(
          date: date,
          dateText: dateText,
          timeText: timeText,
          status: status,
          isAsNeeded: isAsNeeded,
          rawKey: key,
        ),
      );
    });

    items.sort((a, b) {
      final dateCompare = b.date.compareTo(a.date);

      if (dateCompare != 0) {
        return dateCompare;
      }

      return b.rawKey.compareTo(a.rawKey);
    });

    return items;
  }

  List<DoseHistoryItem> getFilteredItems(List<DoseHistoryItem> items) {
    if (selectedFilter == "taken") {
      return items.where((item) => item.status == "taken").toList();
    }

    if (selectedFilter == "missed") {
      return items.where((item) => item.status == "missed").toList();
    }

    if (selectedFilter == "skipped") {
      return items.where((item) => item.status == "skipped").toList();
    }

    if (selectedFilter == "asNeeded") {
      return items.where((item) => item.isAsNeeded).toList();
    }

    return items;
  }

  Map<String, List<DoseHistoryItem>> groupItemsByDate(
    List<DoseHistoryItem> items,
  ) {
    final groupedItems = <String, List<DoseHistoryItem>>{};

    for (final item in items) {
      final key = item.dateText;

      if (!groupedItems.containsKey(key)) {
        groupedItems[key] = [];
      }

      groupedItems[key]!.add(item);
    }

    return groupedItems;
  }

  String dateHeaderText(String dateText) {
    final date = DateHelper.parseMedicationDate(dateText);

    if (date == null) {
      return DateHelper.displayMedicationDate(dateText);
    }

    final today = DateHelper.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    if (date.isAtSameMomentAs(today)) {
      return tr("Today", "Hôm nay");
    }

    if (date.isAtSameMomentAs(yesterday)) {
      return tr("Yesterday", "Hôm qua");
    }

    return DateHelper.displayMedicationDate(dateText);
  }

  int countStatus(List<DoseHistoryItem> items, String status) {
    return items.where((item) {
      return item.status == status;
    }).length;
  }

  int countAsNeeded(List<DoseHistoryItem> items) {
    return items.where((item) {
      return item.isAsNeeded;
    }).length;
  }

  String getFilterTitle() {
    if (selectedFilter == "taken") {
      return tr("Taken", "Đã uống");
    }

    if (selectedFilter == "missed") {
      return tr("Missed", "Bỏ lỡ");
    }

    if (selectedFilter == "asNeeded") {
      return tr("As Needed", "Khi cần");
    }

    if (selectedFilter == "skipped") {
      return tr("Skipped", "Đã bỏ qua");
    }

    return tr("All", "Tất cả");
  }

  String getDoseStatusAfterHistoryChange(Map<String, String> records) {
    final today = DateHelper.todayString();

    bool hasTakenToday = false;
    bool hasMissedToday = false;

    records.forEach((key, value) {
      if (!key.startsWith("$today|")) {
        return;
      }

      if (value == "taken") {
        hasTakenToday = true;
      }

      if (value == "missed" || value == "skipped") {
        hasMissedToday = true;
      }
    });

    if (hasMissedToday) {
      return "missed";
    }

    if (hasTakenToday) {
      return "taken";
    }

    return "notTakenYet";
  }

  Future<bool> confirmClearHistory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr("Clear dose history?", "Xoá lịch sử uống thuốc?")),
          content: Text(
            tr(
              "This will delete all Taken/Missed history for this medication. It will not delete the medication details.",
              "Việc này sẽ xoá toàn bộ lịch sử Đã uống/Bỏ lỡ của thuốc này. Thông tin thuốc sẽ không bị xoá.",
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
                tr("Clear History", "Xoá Lịch Sử"),
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

  Future<bool> confirmDeleteHistoryItem(DoseHistoryItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr("Delete this history item?", "Xoá mục lịch sử này?")),
          content: Text(
            tr(
              "Delete ${item.timeText} on ${DateHelper.displayMedicationDate(item.dateText)}? You can undo after deletion.",
              "Xoá ${item.timeText} vào ${DateHelper.displayMedicationDate(item.dateText)}? Bạn có thể hoàn tác sau khi xoá.",
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

    return result == true;
  }

  Future<void> clearDoseHistory() async {
    if (isClearing) {
      return;
    }

    if (medication.id.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "Cannot clear history for an unsaved medication.",
              "Không thể xoá lịch sử của thuốc chưa được lưu.",
            ),
          ),
        ),
      );
      return;
    }

    final confirmed = await confirmClearHistory();

    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isClearing = true;
    });

    try {
      final previousMedication = medication;

      final updatedMedication = medication.copyWith(
        doseRecords: const {},
        doseStatus: "notTakenYet",
        doseStatusDate: "",
      );

      final updated = await MedicationStorage.updateMedicationById(
        medication.id,
        updatedMedication,
      );

      if (!mounted) {
        return;
      }

      if (!updated) {
        setState(() => medicationUnavailable = true);
        return;
      }

      setState(() {
        medication = updatedMedication;
        historyChanged = true;
        selectedFilter = "all";
      });

      ScaffoldMessenger.of(context).clearSnackBars();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr("Dose history cleared.", "Đã xoá lịch sử uống thuốc."),
          ),
          action: SnackBarAction(
            label: tr("Undo", "Hoàn tác"),
            onPressed: () async {
              final restored = await MedicationStorage.updateMedicationById(
                previousMedication.id,
                previousMedication,
              );

              if (!mounted) {
                return;
              }

              if (!restored) {
                setState(() => medicationUnavailable = true);
                return;
              }

              setState(() {
                medication = previousMedication;
                historyChanged = true;
              });
            },
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isClearing = false;
        });
      }
    }
  }

  Future<void> deleteHistoryItem(DoseHistoryItem item) async {
    if (isClearing) {
      return;
    }

    if (medication.id.trim().isEmpty) {
      return;
    }

    final confirmed = await confirmDeleteHistoryItem(item);

    if (!confirmed) {
      return;
    }

    if (!mounted) {
      return;
    }

    final previousMedication = medication;
    final updatedRecords = Map<String, String>.from(medication.doseRecords);

    updatedRecords.remove(item.rawKey);

    final updatedMedication = medication.copyWith(
      doseRecords: updatedRecords,
      doseStatus: getDoseStatusAfterHistoryChange(updatedRecords),
      doseStatusDate:
          updatedRecords.keys.any((key) {
            return key.startsWith("${DateHelper.todayString()}|");
          })
          ? DateHelper.todayString()
          : "",
    );

    final updated = await MedicationStorage.updateMedicationById(
      medication.id,
      updatedMedication,
    );

    if (!mounted) {
      return;
    }

    if (!updated) {
      setState(() => medicationUnavailable = true);
      return;
    }

    setState(() {
      medication = updatedMedication;
      historyChanged = true;
    });

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr("History item deleted.", "Đã xoá mục lịch sử.")),
        action: SnackBarAction(
          label: tr("Undo", "Hoàn tác"),
          onPressed: () async {
            final restored = await MedicationStorage.updateMedicationById(
              previousMedication.id,
              previousMedication,
            );

            if (!mounted) {
              return;
            }

            if (!restored) {
              setState(() => medicationUnavailable = true);
              return;
            }

            setState(() {
              medication = previousMedication;
              historyChanged = true;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (medicationUnavailable) {
      return Scaffold(
        appBar: AppBar(title: Text(tr("Dose history", "Lịch sử uống thuốc"))),
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

    final allItems = getHistoryItems();
    final filteredItems = getFilteredItems(allItems);
    final groupedItems = groupItemsByDate(filteredItems);

    final takenCount = countStatus(allItems, "taken");
    final missedCount = countStatus(allItems, "missed");
    final skippedCount = countStatus(allItems, "skipped");
    final asNeededCount = countAsNeeded(allItems);

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
                  maxWidth: AppTheme.pageMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context, historyChanged);
                      },
                      icon: const Icon(Icons.arrow_back_ios),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr("Dose History", "Lịch Sử Uống Thuốc"),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      medication.name.trim().isEmpty
                          ? tr("Medication", "Thuốc")
                          : medication.name.trim(),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DoseHistorySummaryCard(
                      takenCount: takenCount,
                      missedCount: missedCount,
                      skippedCount: skippedCount,
                      asNeededCount: asNeededCount,
                    ),
                    if (allItems.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      HistoryFilterCard(
                        selectedFilter: selectedFilter,
                        takenCount: takenCount,
                        missedCount: missedCount,
                        skippedCount: skippedCount,
                        asNeededCount: asNeededCount,
                        totalCount: allItems.length,
                        onSelect: (filter) {
                          setState(() {
                            selectedFilter = filter;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isClearing ? null : clearDoseHistory,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: Text(
                            isClearing
                                ? tr("Clearing...", "Đang xoá...")
                                : tr("Clear All History", "Xoá Tất Cả Lịch Sử"),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (allItems.isEmpty)
                      const EmptyDoseHistoryCard()
                    else if (filteredItems.isEmpty)
                      FilteredEmptyDoseHistoryCard(filterName: getFilterTitle())
                    else
                      Column(
                        children: groupedItems.entries.map((entry) {
                          final dateText = entry.key;
                          final dayItems = entry.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HistoryDateHeader(
                                text: dateHeaderText(dateText),
                                subtitle: DateHelper.displayMedicationDate(
                                  dateText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...dayItems.map((item) {
                                return DoseHistoryCard(
                                  item: item,
                                  onDelete: () {
                                    deleteHistoryItem(item);
                                  },
                                );
                              }),
                              const SizedBox(height: 6),
                            ],
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 24),
                    const DoseHistorySafetyCard(),
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

class DoseHistoryItem {
  final DateTime date;
  final String dateText;
  final String timeText;
  final String status;
  final bool isAsNeeded;
  final String rawKey;

  const DoseHistoryItem({
    required this.date,
    required this.dateText,
    required this.timeText,
    required this.status,
    required this.isAsNeeded,
    required this.rawKey,
  });
}

class HistoryFilterCard extends StatelessWidget {
  final String selectedFilter;
  final int totalCount;
  final int takenCount;
  final int missedCount;
  final int skippedCount;
  final int asNeededCount;
  final ValueChanged<String> onSelect;

  const HistoryFilterCard({
    super.key,
    required this.selectedFilter,
    required this.totalCount,
    required this.takenCount,
    required this.missedCount,
    required this.skippedCount,
    required this.asNeededCount,
    required this.onSelect,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            tr("Filter History", "Lọc Lịch Sử"),
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HistoryFilterPill(
                label: "${tr("All", "Tất cả")} $totalCount",
                selected: selectedFilter == "all",
                color: AppTheme.primaryColor,
                onTap: () {
                  onSelect("all");
                },
              ),
              HistoryFilterPill(
                label: "${tr("Taken", "Đã uống")} $takenCount",
                selected: selectedFilter == "taken",
                color: const Color(0xFF22C55E),
                onTap: () {
                  onSelect("taken");
                },
              ),
              HistoryFilterPill(
                label: "${tr("Missed", "Bỏ lỡ")} $missedCount",
                selected: selectedFilter == "missed",
                color: const Color(0xFFEF4444),
                onTap: () {
                  onSelect("missed");
                },
              ),
              HistoryFilterPill(
                label: "${tr("Skipped", "Đã bỏ qua")} $skippedCount",
                selected: selectedFilter == "skipped",
                color: const Color(0xFFF59E0B),
                onTap: () {
                  onSelect("skipped");
                },
              ),
              HistoryFilterPill(
                label: "${tr("As Needed", "Khi cần")} $asNeededCount",
                selected: selectedFilter == "asNeeded",
                color: const Color(0xFFF59E0B),
                onTap: () {
                  onSelect("asNeeded");
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HistoryFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const HistoryFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryDateHeader extends StatelessWidget {
  final String text;
  final String subtitle;

  const HistoryDateHeader({
    super.key,
    required this.text,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.lightColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text == subtitle ? text : "$text • $subtitle",
              style: const TextStyle(
                color: Color(0xFF1E2A3A),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DoseHistorySummaryCard extends StatelessWidget {
  final int takenCount;
  final int missedCount;
  final int skippedCount;
  final int asNeededCount;

  const DoseHistorySummaryCard({
    super.key,
    required this.takenCount,
    required this.missedCount,
    required this.skippedCount,
    required this.asNeededCount,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          HistorySummaryPill(
            text: "${tr("Taken", "Đã uống")} $takenCount",
            color: const Color(0xFF22C55E),
          ),
          HistorySummaryPill(
            text: "${tr("Missed", "Bỏ lỡ")} $missedCount",
            color: const Color(0xFFEF4444),
          ),
          HistorySummaryPill(
            text: "${tr("Skipped", "Đã bỏ qua")} $skippedCount",
            color: const Color(0xFFF59E0B),
          ),
          HistorySummaryPill(
            text: "${tr("As needed", "Khi cần")} $asNeededCount",
            color: const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }
}

class HistorySummaryPill extends StatelessWidget {
  final String text;
  final Color color;

  const HistorySummaryPill({
    super.key,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class DoseHistoryCard extends StatelessWidget {
  final DoseHistoryItem item;
  final VoidCallback onDelete;

  const DoseHistoryCard({
    super.key,
    required this.item,
    required this.onDelete,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Color statusColor() {
    if (item.status == "taken") {
      return const Color(0xFF22C55E);
    }

    if (item.status == "missed") {
      return const Color(0xFFEF4444);
    }

    if (item.status == "skipped") {
      return const Color(0xFFF59E0B);
    }

    return AppTheme.primaryColor;
  }

  String statusText() {
    if (item.status == "taken") {
      return tr("Taken", "Đã uống");
    }

    if (item.status == "missed") {
      return tr("Missed", "Bỏ lỡ");
    }

    if (item.status == "skipped") {
      return tr("Skipped", "Đã bỏ qua");
    }

    return item.status;
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.26), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                item.status == "taken"
                    ? Icons.check_rounded
                    : item.status == "skipped"
                    ? Icons.skip_next_rounded
                    : Icons.close_rounded,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText(),
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.timeText,
                    style: const TextStyle(
                      color: Color(0xFF1E2A3A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.isAsNeeded) ...[
                    const SizedBox(height: 4),
                    Text(
                      tr("As-needed dose", "Liều dùng khi cần"),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyDoseHistoryCard extends StatelessWidget {
  const EmptyDoseHistoryCard({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.history_rounded, color: AppTheme.primaryColor, size: 48),
          const SizedBox(height: 12),
          Text(
            tr("No dose history yet", "Chưa có lịch sử uống thuốc"),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              "Taken and missed doses will appear here.",
              "Các liều đã uống hoặc bỏ lỡ sẽ hiện ở đây.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class FilteredEmptyDoseHistoryCard extends StatelessWidget {
  final String filterName;

  const FilteredEmptyDoseHistoryCard({super.key, required this.filterName});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            color: AppTheme.primaryColor,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            tr("No $filterName history", "Không có lịch sử $filterName"),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1E2A3A),
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr("Try another filter.", "Hãy thử bộ lọc khác."),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF667085),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class DoseHistorySafetyCard extends StatelessWidget {
  const DoseHistorySafetyCard({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
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
        tr(
          "This history is only a reminder log. Always follow your doctor, pharmacist, or prescription label.",
          "Lịch sử này chỉ là nhật ký nhắc nhở. Luôn làm theo hướng dẫn của bác sĩ, dược sĩ hoặc nhãn thuốc.",
        ),
        style: const TextStyle(
          color: Color(0xFF1E2A3A),
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
