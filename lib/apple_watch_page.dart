import 'dart:io';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';
import 'apple_watch_service.dart';
import 'medication_storage.dart';

class AppleWatchPage extends StatefulWidget {
  const AppleWatchPage({super.key});

  @override
  State<AppleWatchPage> createState() => _AppleWatchPageState();
}

class _AppleWatchPageState extends State<AppleWatchPage> {
  AppleWatchStatus? status;
  bool loading = true;
  bool syncing = false;

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == 'en' ? english : vietnamese;
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final result = await AppleWatchService.status();
    if (!mounted) return;
    setState(() {
      status = result;
      loading = false;
    });
  }

  Future<void> sync() async {
    setState(() => syncing = true);
    final medications = await MedicationStorage.loadCurrentLocalMedications();
    final synced = await AppleWatchService.syncMedicationSummary(medications);
    await refresh();
    if (!mounted) return;
    setState(() => syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? tr(
                  'Medication summary sent to Apple Watch.',
                  'Đã gửi danh sách thuốc đến Apple Watch.',
                )
              : tr(
                  'Notification mirroring is ready. A companion Watch app is required for direct data sync.',
                  'Đã sẵn sàng phản chiếu thông báo. Cần ứng dụng Watch đi kèm để đồng bộ dữ liệu trực tiếp.',
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = status;
    final paired = current?.paired == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Apple Watch')),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
        child: ListView(
          padding: AppTheme.pagePadding(context),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WatchStatusCard(
                      loading: loading,
                      supported: Platform.isIOS && current?.supported == true,
                      paired: paired,
                      reachable: current?.reachable == true,
                      tr: tr,
                    ),
                    const SizedBox(height: 14),
                    _WatchInstructionCard(
                      number: '1',
                      title: tr('Pair your Watch', 'Ghép đôi đồng hồ'),
                      body: tr(
                        'Use the Watch app on your iPhone and keep Bluetooth on.',
                        'Dùng ứng dụng Watch trên iPhone và bật Bluetooth.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _WatchInstructionCard(
                      number: '2',
                      title: tr('Mirror reminders', 'Phản chiếu lời nhắc'),
                      body: tr(
                        'In the iPhone Watch app, open Notifications and enable Medication Reminder.',
                        'Trong ứng dụng Watch trên iPhone, mở Thông báo và bật Medication Reminder.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _WatchInstructionCard(
                      number: '3',
                      title: tr(
                        'Use Taken or Missed',
                        'Chọn Đã uống hoặc Bỏ lỡ',
                      ),
                      body: tr(
                        'Reminder actions can be used from the mirrored notification on your Watch.',
                        'Bạn có thể dùng hành động ngay trên thông báo được phản chiếu trên đồng hồ.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: syncing ? null : sync,
                      icon: syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(
                        tr('Check and sync', 'Kiểm tra và đồng bộ'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
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

class _WatchStatusCard extends StatelessWidget {
  final bool loading;
  final bool supported;
  final bool paired;
  final bool reachable;
  final String Function(String, String) tr;

  const _WatchStatusCard({
    required this.loading,
    required this.supported,
    required this.paired,
    required this.reachable,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final title = loading
        ? tr('Checking Apple Watch…', 'Đang kiểm tra Apple Watch…')
        : !supported
        ? tr('Use this feature on iPhone', 'Dùng tính năng này trên iPhone')
        : paired
        ? tr('Apple Watch is paired', 'Apple Watch đã ghép đôi')
        : tr('No paired Watch found', 'Không tìm thấy Watch đã ghép đôi');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppTheme.lightColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.watch_rounded, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
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
                if (paired) ...[
                  const SizedBox(height: 4),
                  Text(
                    reachable
                        ? tr('Connected now', 'Đang kết nối')
                        : tr(
                            'Paired; open the Watch to connect',
                            'Đã ghép đôi; mở Watch để kết nối',
                          ),
                    style: const TextStyle(
                      color: AppTheme.mutedInk,
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

class _WatchInstructionCard extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _WatchInstructionCard({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: AppTheme.lightColor,
            foregroundColor: AppTheme.primaryColor,
            child: Text(
              number,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.mutedInk,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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
