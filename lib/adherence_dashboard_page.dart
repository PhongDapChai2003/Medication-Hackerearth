import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'date_helper.dart';
import 'medication.dart';
import 'medication_storage.dart';
import 'notification_service.dart';

class AdherenceDashboardPage extends StatefulWidget {
  const AdherenceDashboardPage({super.key});

  @override
  State<AdherenceDashboardPage> createState() => _AdherenceDashboardPageState();
}

class _AdherenceDashboardPageState extends State<AdherenceDashboardPage> {
  List<Medication> medications = [];
  bool loading = true;
  int selectedRangeDays = 7;

  @override
  void initState() {
    super.initState();
    MedicationStorage.dataRevision.addListener(loadLocal);
    // Show encrypted on-device history immediately. Cloud refresh continues
    // without blocking the report screen.
    loadLocal();
    Future<void>.delayed(Duration.zero, load);
  }

  @override
  void dispose() {
    MedicationStorage.dataRevision.removeListener(loadLocal);
    super.dispose();
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> loadLocal() async {
    final items = await MedicationStorage.loadCurrentLocalMedications();

    if (!mounted) return;
    setState(() {
      medications = items;
      loading = false;
    });
  }

  Future<void> load() async {
    final items = await MedicationStorage.loadMedications();

    if (!mounted) return;
    setState(() {
      medications = items;
      loading = false;
    });
  }

  int countStatusOnDate(String status, DateTime date) {
    final prefix = "${DateHelper.dateToString(date)}|";
    var count = 0;

    for (final medication in medications) {
      count += medication.doseRecords.entries.where((entry) {
        return entry.key.startsWith(prefix) && entry.value == status;
      }).length;
    }

    return count;
  }

  int countStatusInRange(String status, int numberOfDays) {
    final end = DateHelper.dateOnly(DateTime.now());
    final start = end.subtract(Duration(days: numberOfDays - 1));
    var count = 0;

    for (final medication in medications) {
      for (final entry in medication.doseRecords.entries) {
        if (entry.value != status) {
          continue;
        }

        final dividerIndex = entry.key.indexOf("|");

        if (dividerIndex <= 0) {
          continue;
        }

        final date = DateTime.tryParse(entry.key.substring(0, dividerIndex));

        if (date == null) {
          continue;
        }

        final recordDate = DateHelper.dateOnly(date);

        if (!recordDate.isBefore(start) && !recordDate.isAfter(end)) {
          count += 1;
        }
      }
    }

    return count;
  }

  String remainingQuantity(Medication medication) {
    final remaining = medication.remainingQuantity.trim();

    if (remaining.isNotEmpty) {
      return remaining;
    }

    final original = medication.quantity.trim();
    return original.isEmpty ? "--" : original;
  }

  double? remainingQuantityNumber(Medication medication) {
    final value = remainingQuantity(medication).replaceAll(",", "").trim();
    return double.tryParse(value);
  }

  bool needsRefillAttention(Medication medication) {
    final remaining = remainingQuantityNumber(medication);

    if (remaining != null && remaining <= 0) {
      return true;
    }

    final days = NotificationService.estimateDaysLeft(medication);
    return days > 0 && days <= 7;
  }

  int refillSortValue(Medication medication) {
    final remaining = remainingQuantityNumber(medication);

    if (remaining != null && remaining <= 0) {
      return -1;
    }

    final days = NotificationService.estimateDaysLeft(medication);
    return days <= 0 ? 100000 : days;
  }

  String buildReport() {
    final taken = countStatusInRange("taken", selectedRangeDays);
    final missed = countStatusInRange("missed", selectedRangeDays);
    final skipped = countStatusInRange("skipped", selectedRangeDays);
    final completed = taken + missed + skipped;
    final adherence = completed == 0 ? 0 : (taken * 100 / completed).round();
    final buffer = StringBuffer()
      ..writeln("Medication Reminder - Complete History Report")
      ..writeln("Generated: ${DateTime.now()}")
      ..writeln("Period: Last $selectedRangeDays days")
      ..writeln("Doses marked Taken: $adherence%")
      ..writeln("Taken: $taken | Missed: $missed | Skipped: $skipped")
      ..writeln();

    for (final medication in medications) {
      buffer.writeln("${medication.name} ${medication.dosage}".trim());
      buffer.writeln("Directions: ${medication.instructions}");
      buffer.writeln("Remaining: ${remainingQuantity(medication)}");

      final daysLeft = NotificationService.estimateDaysLeft(medication);
      if (daysLeft > 0) {
        buffer.writeln("Estimated supply: $daysLeft days");
      }

      final records = medication.doseRecords.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));

      // Include the complete saved history, not only the latest 30 entries.
      for (final record in records) {
        buffer.writeln("  ${record.key}: ${record.value}");
      }

      buffer.writeln();
    }

    buffer.writeln(
      "Reminder tool only. Confirm medical directions with a clinician or pharmacist.",
    );
    return buffer.toString();
  }

  Future<void> copyReport() async {
    await Clipboard.setData(ClipboardData(text: buildReport()));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr("Report copied.", "Đã sao chép báo cáo."))),
    );
  }

  Future<void> emailReport() async {
    final uri = Uri(
      scheme: "mailto",
      queryParameters: {
        "subject": "Medication and adherence report",
        "body": buildReport(),
      },
    );
    var opened = false;

    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr("Could not open email.", "Không thể mở email.")),
        ),
      );
    }
  }

  Future<void> textReport() async {
    await Clipboard.setData(ClipboardData(text: buildReport()));
    var opened = false;

    try {
      opened = await launchUrl(Uri(scheme: "sms"));
    } catch (_) {
      opened = false;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? tr(
                  "Report copied. Paste it into the message for your caregiver.",
                  "Đã sao chép báo cáo. Hãy dán vào tin nhắn cho người chăm sóc.",
                )
              : tr(
                  "Report copied, but Messages could not open.",
                  "Đã sao chép báo cáo nhưng không thể mở Tin nhắn.",
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rangeTaken = countStatusInRange("taken", selectedRangeDays);
    final rangeMissed = countStatusInRange("missed", selectedRangeDays);
    final rangeSkipped = countStatusInRange("skipped", selectedRangeDays);
    final rangeTotal = rangeTaken + rangeMissed + rangeSkipped;
    final adherence = rangeTotal == 0 ? 0.0 : rangeTaken / rangeTotal;
    final today = DateHelper.dateOnly(DateTime.now());
    final todayTaken = countStatusOnDate("taken", today);
    final todayMissed = countStatusOnDate("missed", today);
    final todaySkipped = countStatusOnDate("skipped", today);
    final refillMedications = [...medications]
      ..sort(
        (first, second) =>
            refillSortValue(first).compareTo(refillSortValue(second)),
      );
    final urgentRefillCount = medications.where(needsRefillAttention).length;

    return Scaffold(
      appBar: AppBar(title: Text(tr("Reports & History", "Báo Cáo & Lịch Sử"))),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: RefreshIndicator(
          onRefresh: load,
          color: AppTheme.primaryColor,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppTheme.pagePadding(context),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.pageMaxWidth,
                  ),
                  child: loading
                      ? Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr(
                                "Reports and complete history",
                                "Báo cáo và toàn bộ lịch sử",
                              ),
                              style: const TextStyle(
                                color: AppTheme.ink,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr(
                                "Review your progress and export every saved dose record.",
                                "Xem tiến độ và xuất mọi liều thuốc đã lưu.",
                              ),
                              style: const TextStyle(
                                color: AppTheme.mutedInk,
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _PeriodSelector(
                              selectedDays: selectedRangeDays,
                              tr: tr,
                              onChanged: (days) {
                                setState(() {
                                  selectedRangeDays = days;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _AdherenceHero(
                              adherence: adherence,
                              total: rangeTotal,
                              taken: rangeTaken,
                              missed: rangeMissed,
                              skipped: rangeSkipped,
                              numberOfDays: selectedRangeDays,
                              tr: tr,
                            ),
                            const SizedBox(height: 20),
                            _SectionHeading(
                              icon: Icons.today_rounded,
                              title: tr("Today", "Hôm nay"),
                            ),
                            const SizedBox(height: 10),
                            _DoseStatGrid(
                              taken: todayTaken,
                              missed: todayMissed,
                              skipped: todaySkipped,
                              tr: tr,
                            ),
                            const SizedBox(height: 16),
                            _AttentionCard(
                              missedCount: rangeMissed,
                              urgentRefillCount: urgentRefillCount,
                              tr: tr,
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: tr(
                                "Daily recorded progress",
                                "Tiến độ ghi nhận mỗi ngày",
                              ),
                              subtitle: tr(
                                "Green shows doses marked Taken.",
                                "Màu xanh là liều được đánh dấu Đã uống.",
                              ),
                              child: Column(
                                children: List.generate(selectedRangeDays, (
                                  index,
                                ) {
                                  final date = today.subtract(
                                    Duration(
                                      days: selectedRangeDays - 1 - index,
                                    ),
                                  );
                                  final dayTaken = countStatusOnDate(
                                    "taken",
                                    date,
                                  );
                                  final dayMissed =
                                      countStatusOnDate("missed", date) +
                                      countStatusOnDate("skipped", date);
                                  final total = dayTaken + dayMissed;

                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == selectedRangeDays - 1
                                          ? 0
                                          : 14,
                                    ),
                                    child: _DailyProgressRow(
                                      date: date,
                                      taken: dayTaken,
                                      total: total,
                                      tr: tr,
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: tr(
                                "Medication supply",
                                "Số thuốc còn lại",
                              ),
                              subtitle: tr(
                                "Refill estimates are based on the saved quantity and schedule.",
                                "Ước tính mua thêm dựa trên số lượng và lịch đã lưu.",
                              ),
                              child: refillMedications.isEmpty
                                  ? _EmptyDashboardMessage(
                                      icon: Icons.medication_rounded,
                                      message: tr(
                                        "No medications yet.",
                                        "Chưa có thuốc.",
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < refillMedications.length;
                                          index++
                                        ) ...[
                                          _RefillRow(
                                            medication:
                                                refillMedications[index],
                                            remaining: remainingQuantity(
                                              refillMedications[index],
                                            ),
                                            remainingNumber:
                                                remainingQuantityNumber(
                                                  refillMedications[index],
                                                ),
                                            daysLeft:
                                                NotificationService.estimateDaysLeft(
                                                  refillMedications[index],
                                                ),
                                            tr: tr,
                                          ),
                                          if (index !=
                                              refillMedications.length - 1)
                                            const Divider(height: 18),
                                        ],
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              title: tr(
                                "Share with a caregiver",
                                "Chia sẻ với người chăm sóc",
                              ),
                              subtitle: tr(
                                "Nothing is shared automatically.",
                                "Ứng dụng không tự động chia sẻ.",
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    tr(
                                      "You choose who receives this medication report.",
                                      "Bạn chọn người sẽ nhận báo cáo thuốc này.",
                                    ),
                                    style: const TextStyle(
                                      color: AppTheme.mutedInk,
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: copyReport,
                                        icon: const Icon(Icons.copy_rounded),
                                        label: Text(tr("Copy", "Sao chép")),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: emailReport,
                                        icon: const Icon(Icons.email_rounded),
                                        label: const Text("Email"),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: textReport,
                                        icon: const Icon(Icons.sms_rounded),
                                        label: Text(tr("Message", "Tin nhắn")),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _RecordedDataNote(tr: tr),
                            const SizedBox(height: 28),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onChanged;
  final String Function(String, String) tr;

  const _PeriodSelector({
    required this.selectedDays,
    required this.onChanged,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PeriodButton(
              selected: selectedDays == 7,
              label: tr("Last 7 days", "7 ngày gần đây"),
              onTap: () {
                onChanged(7);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PeriodButton(
              selected: selectedDays == 30,
              label: tr("Last 30 days", "30 ngày gần đây"),
              onTap: () {
                onChanged(30);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _PeriodButton({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.mutedInk,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdherenceHero extends StatelessWidget {
  final double adherence;
  final int total;
  final int taken;
  final int missed;
  final int skipped;
  final int numberOfDays;
  final String Function(String, String) tr;

  const _AdherenceHero({
    required this.adherence,
    required this.total,
    required this.taken,
    required this.missed,
    required this.skipped,
    required this.numberOfDays,
    required this.tr,
  });

  String get encouragement {
    if (total == 0) {
      return tr(
        "No doses were recorded in this period.",
        "Chưa có liều nào được ghi trong thời gian này.",
      );
    }

    if (adherence >= 0.9) {
      return tr("Excellent recorded progress!", "Tiến độ ghi nhận rất tốt!");
    }

    if (adherence >= 0.75) {
      return tr("Good progress—keep going.", "Tiến độ tốt—hãy tiếp tục.");
    }

    return tr(
      "Some recorded doses need attention.",
      "Một số liều đã ghi cần được chú ý.",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : adherence,
                    strokeWidth: 13,
                    strokeCap: StrokeCap.round,
                    color: const Color(0xFF86EFAC),
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      total == 0 ? "--" : "${(adherence * 100).round()}%",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      tr("Taken", "Đã uống"),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            encouragement,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              "Based on $total dose records from the last $numberOfDays days.",
              "Dựa trên $total liều đã ghi trong $numberOfDays ngày gần đây.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroCount(label: tr("Taken", "Đã uống"), value: taken),
              _HeroCount(label: tr("Missed", "Bỏ lỡ"), value: missed),
              _HeroCount(label: tr("Skipped", "Đã bỏ qua"), value: skipped),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroCount extends StatelessWidget {
  final String label;
  final int value;

  const _HeroCount({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeading({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 24),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DoseStatGrid extends StatelessWidget {
  final int taken;
  final int missed;
  final int skipped;
  final String Function(String, String) tr;

  const _DoseStatGrid({
    required this.taken,
    required this.missed,
    required this.skipped,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackCards = constraints.maxWidth < 540;
        final cardWidth = stackCards
            ? constraints.maxWidth
            : (constraints.maxWidth - 20) / 3;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DoseStatCard(
              width: cardWidth,
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF16A34A),
              value: taken,
              label: tr("Taken", "Đã uống"),
            ),
            _DoseStatCard(
              width: cardWidth,
              icon: Icons.cancel_rounded,
              color: const Color(0xFFDC2626),
              value: missed,
              label: tr("Missed", "Bỏ lỡ"),
            ),
            _DoseStatCard(
              width: cardWidth,
              icon: Icons.remove_circle_rounded,
              color: const Color(0xFF64748B),
              value: skipped,
              label: tr("Skipped", "Đã bỏ qua"),
            ),
          ],
        );
      },
    );
  }
}

class _DoseStatCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color color;
  final int value;
  final String label;

  const _DoseStatCard({
    required this.width,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$value",
                  style: TextStyle(
                    color: color,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.mutedInk,
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

class _AttentionCard extends StatelessWidget {
  final int missedCount;
  final int urgentRefillCount;
  final String Function(String, String) tr;

  const _AttentionCard({
    required this.missedCount,
    required this.urgentRefillCount,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final needsAttention = missedCount > 0 || urgentRefillCount > 0;
    final color = needsAttention
        ? const Color(0xFFB54708)
        : const Color(0xFF15803D);
    final background = needsAttention
        ? const Color(0xFFFFFAEB)
        : const Color(0xFFF0FDF4);
    final border = needsAttention
        ? const Color(0xFFFEC84B)
        : const Color(0xFF86EFAC);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            needsAttention
                ? Icons.notifications_active_rounded
                : Icons.verified_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsAttention
                      ? tr("Needs attention", "Cần chú ý")
                      : tr(
                          "No recorded problems",
                          "Không có vấn đề được ghi nhận",
                        ),
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (missedCount > 0) ...[
                  const SizedBox(height: 7),
                  Text(
                    tr(
                      "$missedCount missed dose records in this period.",
                      "$missedCount liều được ghi là bỏ lỡ trong thời gian này.",
                    ),
                    style: TextStyle(
                      color: color,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (urgentRefillCount > 0) ...[
                  const SizedBox(height: 5),
                  Text(
                    tr(
                      "$urgentRefillCount medications may need a refill soon.",
                      "$urgentRefillCount thuốc có thể cần mua thêm sớm.",
                    ),
                    style: TextStyle(
                      color: color,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (!needsAttention) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      "Keep recording each dose to maintain an accurate dashboard.",
                      "Tiếp tục ghi mỗi liều để bảng theo dõi luôn chính xác.",
                    ),
                    style: TextStyle(
                      color: color,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.mutedInk,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DailyProgressRow extends StatelessWidget {
  final DateTime date;
  final int taken;
  final int total;
  final String Function(String, String) tr;

  const _DailyProgressRow({
    required this.date,
    required this.taken,
    required this.total,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : taken / total;
    final dateLabel = MaterialLocalizations.of(context).formatShortDate(date);

    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            dateLabel,
            maxLines: 1,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              color: const Color(0xFF22C55E),
              backgroundColor: total == 0
                  ? const Color(0xFFE2E8F0)
                  : const Color(0xFFFEE2E2),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            total == 0
                ? tr("No record", "Chưa ghi")
                : tr("$taken of $total", "$taken/$total"),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: const TextStyle(
              color: AppTheme.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _RefillRow extends StatelessWidget {
  final Medication medication;
  final String remaining;
  final double? remainingNumber;
  final int daysLeft;
  final String Function(String, String) tr;

  const _RefillRow({
    required this.medication,
    required this.remaining,
    required this.remainingNumber,
    required this.daysLeft,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    late final String status;

    if (remainingNumber != null && remainingNumber! <= 0) {
      color = const Color(0xFFDC2626);
      icon = Icons.error_rounded;
      status = tr("Out of medication", "Đã hết thuốc");
    } else if (daysLeft > 0 && daysLeft <= 7) {
      color = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_rounded;
      status = tr(
        "Refill soon • about $daysLeft days",
        "Mua thêm sớm • khoảng $daysLeft ngày",
      );
    } else if (daysLeft > 7) {
      color = const Color(0xFF16A34A);
      icon = Icons.check_circle_rounded;
      status = tr(
        "About $daysLeft days remaining",
        "Còn khoảng $daysLeft ngày",
      );
    } else {
      color = const Color(0xFF64748B);
      icon = Icons.help_outline_rounded;
      status = tr("Estimate unavailable", "Chưa thể ước tính");
    }

    final name = medication.name.trim().isEmpty
        ? tr("Medication", "Thuốc")
        : medication.name.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr("$remaining remaining", "Còn $remaining"),
                style: const TextStyle(
                  color: AppTheme.mutedInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyDashboardMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyDashboardMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 38),
            const SizedBox(height: 9),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.mutedInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordedDataNote extends StatelessWidget {
  final String Function(String, String) tr;

  const _RecordedDataNote({required this.tr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                "This dashboard only counts doses marked Taken, Missed, or Skipped. It supports medication organization and does not replace advice from a pharmacist or clinician.",
                "Bảng này chỉ tính các liều được đánh dấu Đã uống, Bỏ lỡ hoặc Đã bỏ qua. Bảng giúp sắp xếp thuốc và không thay thế tư vấn của dược sĩ hoặc bác sĩ.",
              ),
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
