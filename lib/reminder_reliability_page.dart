import 'dart:io';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'notification_service.dart';

class ReminderReliabilityPage extends StatefulWidget {
  const ReminderReliabilityPage({super.key});

  @override
  State<ReminderReliabilityPage> createState() =>
      _ReminderReliabilityPageState();
}

class _ReminderReliabilityPageState extends State<ReminderReliabilityPage> {
  bool _loading = true;
  bool _exactTiming = false;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == 'en' ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exact = await NotificationService.refreshExactAlarmPermission();
    if (!mounted) return;
    setState(() {
      _exactTiming = exact;
      _loading = false;
    });
  }

  Future<void> _allowReminders() async {
    setState(() => _loading = true);
    final notificationsAllowed = await NotificationService.requestPermission();
    var exactAllowed = true;
    if (Platform.isAndroid) {
      exactAllowed = await NotificationService.requestExactAlarmAccess();
    }
    if (!mounted) return;
    setState(() {
      _exactTiming = exactAllowed;
      _loading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          notificationsAllowed
              ? tr('Reminder access updated.', 'Đã cập nhật quyền nhắc nhở.')
              : tr(
                  'Notifications are still blocked in device settings.',
                  'Thông báo vẫn bị chặn trong cài đặt thiết bị.',
                ),
        ),
      ),
    );
  }

  Future<void> _testReminder() async {
    await NotificationService.scheduleTestReminder();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          tr(
            'Test scheduled for 10 seconds. Lock the phone to check it.',
            'Đã đặt kiểm tra sau 10 giây. Hãy khóa điện thoại để kiểm tra.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Reminder Reliability', 'Độ tin cậy nhắc nhở')),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: AppTheme.pagePadding(context),
            children: [
              _StatusCard(
                icon: Icons.notifications_active_outlined,
                title: tr('Notification access', 'Quyền thông báo'),
                body: tr(
                  'Allow alerts and sound so reminders can reach you when the app is closed.',
                  'Cho phép cảnh báo và âm thanh để nhận lời nhắc khi ứng dụng đã đóng.',
                ),
              ),
              const SizedBox(height: 12),
              if (Platform.isAndroid)
                _StatusCard(
                  icon: _exactTiming
                      ? Icons.check_circle_outline_rounded
                      : Icons.schedule_rounded,
                  title: _exactTiming
                      ? tr('Exact timing is ready', 'Đã sẵn sàng đúng giờ')
                      : tr(
                          'Exact timing needs access',
                          'Cần quyền nhắc đúng giờ',
                        ),
                  body: _exactTiming
                      ? tr(
                          'Android can deliver reminders at the scheduled minute.',
                          'Android có thể gửi lời nhắc đúng phút đã đặt.',
                        )
                      : tr(
                          'Without exact-alarm access, Android may delay reminders to save battery.',
                          'Nếu không có quyền báo thức chính xác, Android có thể trì hoãn lời nhắc để tiết kiệm pin.',
                        ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loading ? null : _allowReminders,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.security_rounded),
                label: Text(
                  tr(
                    'Allow reliable reminders',
                    'Cho phép nhắc nhở đáng tin cậy',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _testReminder,
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(
                  tr(
                    'Test reminder and sound',
                    'Kiểm tra lời nhắc và âm thanh',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                tr(
                  'A reminder app can still be affected by device settings, battery restrictions, or a powered-off phone. Always keep a backup plan for important medication.',
                  'Ứng dụng nhắc nhở vẫn có thể bị ảnh hưởng bởi cài đặt thiết bị, tiết kiệm pin hoặc điện thoại tắt nguồn. Luôn có phương án dự phòng cho thuốc quan trọng.',
                ),
                style: const TextStyle(
                  color: AppTheme.mutedInk,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    color: AppTheme.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.mutedInk,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
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
