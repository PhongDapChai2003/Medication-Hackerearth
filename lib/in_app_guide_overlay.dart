import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_theme.dart';

class InAppGuideOverlay extends StatelessWidget {
  static const int stepCount = 7;

  static int tabForStep(int step) {
    switch (step) {
      case 1:
      case 2:
      case 3:
      case 4:
        return 1;
      case 5:
        return 2;
      case 6:
        return 3;
      case 0:
      default:
        return 0;
    }
  }

  final int step;
  final Rect? targetRect;
  final VoidCallback onNext;
  final VoidCallback onClose;

  const InAppGuideOverlay({
    super.key,
    required this.step,
    this.targetRect,
    required this.onNext,
    required this.onClose,
  });

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == 'en' ? english : vietnamese;
  }

  _GuideStep get _current {
    switch (step) {
      case 1:
        return _GuideStep(
          icon: Icons.document_scanner_rounded,
          title: tr('Open Scan', 'Mở mục Quét'),
          body: tr(
            'Tap Scan below. You can use the camera, choose label photos, or enter the medication yourself.',
            'Nhấn Quét bên dưới. Bạn có thể dùng camera, chọn ảnh nhãn thuốc hoặc tự nhập thông tin.',
          ),
        );
      case 2:
        return _GuideStep(
          icon: Icons.camera_alt_rounded,
          title: tr('Scan with the camera', 'Quét bằng camera'),
          body: tr(
            'Tap Scan Prescription below. Use bright light, hold still, and keep the medication label inside the camera frame.',
            'Nhấn Quét toa thuốc bên dưới. Chụp nơi đủ sáng, giữ yên và để nhãn thuốc trong khung camera.',
          ),
        );
      case 3:
        return _GuideStep(
          icon: Icons.photo_library_rounded,
          title: tr('Or choose label photos', 'Hoặc chọn ảnh nhãn thuốc'),
          body: tr(
            'Tap Photo Library below. Choose 2–3 photos when the label wraps around the bottle, including name, Qty, directions, and pharmacy phone.',
            'Nhấn Thư viện ảnh bên dưới. Chọn 2–3 ảnh nếu nhãn vòng quanh lọ, gồm tên, Qty, hướng dẫn và số điện thoại nhà thuốc.',
          ),
        );
      case 4:
        return _GuideStep(
          icon: Icons.fact_check_rounded,
          title: tr('Review after processing', 'Kiểm tra sau khi xử lý'),
          body: tr(
            'After your photos are processed, a review form appears automatically. Check and correct the medication, Qty, directions, and reminder times before saving.',
            'Sau khi ảnh được xử lý, biểu mẫu kiểm tra sẽ tự động hiện ra. Hãy kiểm tra và sửa tên thuốc, Qty, hướng dẫn và giờ nhắc trước khi lưu.',
          ),
        );
      case 5:
        return _GuideStep(
          icon: Icons.medication_rounded,
          title: tr('Your medications', 'Thuốc của bạn'),
          body: tr(
            'Review saved medicines, quantities, providers, and reminder schedules here.',
            'Xem thuốc đã lưu, số lượng, cơ sở và lịch nhắc tại đây.',
          ),
        );
      case 6:
        return _GuideStep(
          icon: Icons.tune_rounded,
          title: tr('Settings and history', 'Cài đặt và lịch sử'),
          body: tr(
            'Change preferences, open Reports & History, connect Apple Watch, or replay this guide.',
            'Đổi tùy chọn, mở Báo cáo & Lịch sử, kết nối Apple Watch hoặc xem lại hướng dẫn.',
          ),
        );
      case 0:
      default:
        return _GuideStep(
          icon: Icons.calendar_today_rounded,
          title: tr('Today', 'Hôm nay'),
          body: tr(
            'See today’s schedule and record each dose as Taken or Missed.',
            'Xem lịch hôm nay và ghi mỗi liều là Đã uống hoặc Bỏ lỡ.',
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    const pointerSize = 42.0;
    final isLast = step == stepCount - 1;
    final isScanGuideStep = step >= 2 && step <= 4;
    final hasVisibleTarget = step != 4 && targetRect != null;
    final highlightRect = targetRect?.inflate(2);
    final guideCard = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.lightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Close guide', 'Đóng hướng dẫn'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.body,
            style: const TextStyle(
              color: AppTheme.mutedInk,
              fontSize: 14,
              height: 1.38,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(stepCount, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: index == step ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: index == step
                        ? AppTheme.primaryColor
                        : AppTheme.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onNext,
            child: Text(isLast ? tr('Done', 'Xong') : tr('Next', 'Tiếp')),
          ),
          TextButton(
            onPressed: onClose,
            child: Text(tr('Skip guide', 'Bỏ qua hướng dẫn')),
          ),
        ],
      ),
    );

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFF101828).withValues(alpha: 0.52),
              ),
            ),
            if (hasVisibleTarget)
              Positioned(
                left: highlightRect!.left,
                top: highlightRect.top,
                width: highlightRect.width,
                height: highlightRect.height,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ),
            if (hasVisibleTarget)
              Positioned(
                left: highlightRect!.center.dx - pointerSize / 2,
                top: highlightRect.center.dy - pointerSize / 2,
                child: const _FingerPointer(),
              ),
            if (isScanGuideStep)
              Positioned(
                left: 18,
                right: 18,
                top: MediaQuery.viewPaddingOf(context).top + 18,
                child: SafeArea(bottom: false, child: guideCard),
              )
            else
              Positioned(
                left: 18,
                right: 18,
                bottom: 100 + MediaQuery.viewPaddingOf(context).bottom,
                child: SafeArea(top: false, child: guideCard),
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String body;

  const _GuideStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _FingerPointer extends StatefulWidget {
  const _FingerPointer();

  @override
  State<_FingerPointer> createState() => _FingerPointerState();
}

class _FingerPointerState extends State<_FingerPointer>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.92 + (controller.value * 0.08),
          child: child,
        );
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.primaryColor, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Icon(
          Icons.touch_app_rounded,
          color: AppTheme.primaryColor,
          size: 25,
        ),
      ),
    );
  }
}
