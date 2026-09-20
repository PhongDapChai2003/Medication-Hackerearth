import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'medication_storage.dart';
import 'schedule_preferences.dart';
import 'time_helper.dart';

class ScheduleSettingsPage extends StatefulWidget {
  const ScheduleSettingsPage({super.key});

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  late TimeOfDay wake;
  late TimeOfDay breakfast;
  late TimeOfDay lunch;
  late TimeOfDay dinner;
  late TimeOfDay bedtime;
  late int beforeMeal;
  late int afterMeal;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    wake = SchedulePreferences.wakeTime;
    breakfast = SchedulePreferences.breakfastTime;
    lunch = SchedulePreferences.lunchTime;
    dinner = SchedulePreferences.dinnerTime;
    bedtime = SchedulePreferences.bedtime;
    beforeMeal = SchedulePreferences.beforeMealMinutes;
    afterMeal = SchedulePreferences.afterMealMinutes;
  }

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<TimeOfDay> chooseTime(TimeOfDay current) async {
    return await showTimePicker(
          context: context,
          initialTime: current,
          initialEntryMode: TimePickerEntryMode.inputOnly,
          helpText: AppLanguage.currentLanguage.value == "en"
              ? "Enter time"
              : "Nhập giờ",
        ) ??
        current;
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);

    try {
      await SchedulePreferences.save(
        wake: wake,
        breakfast: breakfast,
        lunch: lunch,
        dinner: dinner,
        sleep: bedtime,
        beforeMeal: beforeMeal,
        afterMeal: afterMeal,
      );
      await MedicationStorage.refreshNotificationSchedule();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "Personal schedule saved and reminders refreshed.",
              "Đã lưu lịch cá nhân và cập nhật giờ nhắc.",
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              "Could not save the personal schedule. Please try again.",
              "Không thể lưu lịch cá nhân. Vui lòng thử lại.",
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("Personal Schedule", "Lịch Cá Nhân"))),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: AppTheme.pagePadding(context),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppTheme.formMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(
                          "These times are used when scanned directions say morning, breakfast, lunch, dinner, bedtime, before food, or after food.",
                          "Các giờ này được dùng khi hướng dẫn quét có ghi buổi sáng, bữa sáng, bữa trưa, bữa tối, trước khi ngủ, trước ăn hoặc sau ăn.",
                        ),
                        style: const TextStyle(
                          color: Color(0xFF475467),
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ScheduleTimeTile(
                        icon: Icons.wb_sunny_outlined,
                        title: tr("Wake time", "Giờ thức dậy"),
                        time: wake,
                        onTap: () async {
                          final value = await chooseTime(wake);
                          if (mounted) setState(() => wake = value);
                        },
                      ),
                      _ScheduleTimeTile(
                        icon: Icons.breakfast_dining_rounded,
                        title: tr("Breakfast", "Bữa sáng"),
                        time: breakfast,
                        onTap: () async {
                          final value = await chooseTime(breakfast);
                          if (mounted) setState(() => breakfast = value);
                        },
                      ),
                      _ScheduleTimeTile(
                        icon: Icons.lunch_dining_rounded,
                        title: tr("Lunch", "Bữa trưa"),
                        time: lunch,
                        onTap: () async {
                          final value = await chooseTime(lunch);
                          if (mounted) setState(() => lunch = value);
                        },
                      ),
                      _ScheduleTimeTile(
                        icon: Icons.dinner_dining_rounded,
                        title: tr("Dinner", "Bữa tối"),
                        time: dinner,
                        onTap: () async {
                          final value = await chooseTime(dinner);
                          if (mounted) setState(() => dinner = value);
                        },
                      ),
                      _ScheduleTimeTile(
                        icon: Icons.bedtime_rounded,
                        title: tr("Bedtime", "Giờ đi ngủ"),
                        time: bedtime,
                        onTap: () async {
                          final value = await chooseTime(bedtime);
                          if (mounted) setState(() => bedtime = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      _OffsetTile(
                        title: tr("Before meal reminder", "Nhắc trước bữa ăn"),
                        value: beforeMeal,
                        onChanged: (value) =>
                            setState(() => beforeMeal = value),
                      ),
                      _OffsetTile(
                        title: tr("After meal reminder", "Nhắc sau bữa ăn"),
                        value: afterMeal,
                        onChanged: (value) => setState(() => afterMeal = value),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: saving ? null : save,
                        icon: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(tr("Save Schedule", "Lưu Lịch")),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
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

class _ScheduleTimeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final TimeOfDay time;
  final VoidCallback onTap;

  const _ScheduleTimeTile({
    required this.icon,
    required this.title,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    TimeHelper.formatTimeForDisplay(time),
                    maxLines: 1,
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF98A2B3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OffsetTile extends StatelessWidget {
  final String title;
  final int value;
  final ValueChanged<int> onChanged;

  const _OffsetTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            DropdownButton<int>(
              value: value,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: const [15, 30, 45, 60].map((minutes) {
                return DropdownMenuItem<int>(
                  value: minutes,
                  child: Text("$minutes min"),
                );
              }).toList(),
              onChanged: (minutes) {
                if (minutes != null) onChanged(minutes);
              },
            ),
          ],
        ),
      ),
    );
  }
}
