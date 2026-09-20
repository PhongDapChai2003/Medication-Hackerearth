import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_text_size.dart';
import 'app_theme.dart';

class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("How to Use the App", "Cách Dùng Ứng Dụng")),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.pageDecoration(),
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
                    _GuideWelcomeCard(tr: tr),
                    const SizedBox(height: 16),
                    _LargeTextCard(tr: tr),
                    const SizedBox(height: 24),
                    _GuideSectionTitle(
                      icon: Icons.format_list_numbered_rounded,
                      title: tr("5 simple steps", "5 bước đơn giản"),
                    ),
                    const SizedBox(height: 10),
                    _GuideStepCard(
                      number: 1,
                      icon: Icons.add_rounded,
                      title: tr("Add your medication", "Thêm thuốc"),
                      instructions: [
                        tr(
                          "Tap Scan, the second tab at the bottom.",
                          "Nhấn Quét, mục thứ hai ở phía dưới.",
                        ),
                        tr(
                          "Choose Scan Prescription, Photo Library, or Enter Medication Manually.",
                          "Chọn Quét toa thuốc, Thư viện ảnh hoặc Nhập thuốc thủ công.",
                        ),
                        tr(
                          "For the camera, read the visual guide and tap Start Scanning.",
                          "Với camera, xem hướng dẫn hình ảnh rồi nhấn Bắt đầu quét.",
                        ),
                        tr(
                          "Review every field before saving.",
                          "Kiểm tra mọi thông tin trước khi lưu.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _GuideStepCard(
                      number: 2,
                      icon: Icons.alarm_add_rounded,
                      title: tr(
                        "Check the reminder times",
                        "Kiểm tra giờ nhắc",
                      ),
                      instructions: [
                        tr(
                          "Open the medication after saving it.",
                          "Mở thuốc sau khi lưu.",
                        ),
                        tr(
                          "Confirm the dose amount and reminder times match the prescription label.",
                          "Xác nhận liều lượng và giờ nhắc đúng với nhãn thuốc.",
                        ),
                        tr(
                          "Allow notifications. Each reminder shows the medication name, dose, and time.",
                          "Cho phép thông báo. Mỗi lời nhắc sẽ có tên thuốc, liều lượng và giờ uống.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _GuideStepCard(
                      number: 3,
                      icon: Icons.check_circle_rounded,
                      title: tr("Record each dose", "Ghi lại mỗi liều"),
                      instructions: [
                        tr(
                          "Open Today, or press and hold the notification to see Taken and Missed.",
                          "Mở Hôm nay, hoặc nhấn giữ thông báo để thấy Đã uống và Bỏ lỡ.",
                        ),
                        tr(
                          "Choose Taken only after the medication was taken.",
                          "Chỉ chọn Đã uống sau khi đã uống thuốc.",
                        ),
                        tr(
                          "Choose Missed when the dose was not taken.",
                          "Chọn Bỏ lỡ khi không uống liều đó.",
                        ),
                        tr(
                          "Taken doses automatically reduce the remaining quantity.",
                          "Liều Đã uống sẽ tự động giảm số lượng thuốc còn lại.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _GuideStepCard(
                      number: 4,
                      icon: Icons.call_rounded,
                      title: tr(
                        "Keep each provider together",
                        "Gộp thuốc theo cơ sở",
                      ),
                      instructions: [
                        tr(
                          "Save the pharmacy, clinic, hospital, or doctor name and phone number. The address is optional.",
                          "Lưu tên và số điện thoại của nhà thuốc, phòng khám, bệnh viện hoặc bác sĩ. Địa chỉ là không bắt buộc.",
                        ),
                        tr(
                          "The app groups medications from the same provider. It does not ask for your live location.",
                          "Ứng dụng gộp thuốc từ cùng một cơ sở và không hỏi vị trí hiện tại của bạn.",
                        ),
                        tr(
                          "Open the provider card to see its medications or tap Call.",
                          "Mở thẻ cơ sở để xem thuốc hoặc nhấn Gọi.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _GuideStepCard(
                      number: 5,
                      icon: Icons.cloud_done_rounded,
                      title: tr(
                        "Protect and review your information",
                        "Bảo vệ và xem lại thông tin",
                      ),
                      instructions: [
                        tr(
                          "Use Health Dashboard to review recorded doses and refill warnings.",
                          "Dùng Bảng theo dõi để xem liều đã ghi và cảnh báo mua thêm.",
                        ),
                        tr(
                          "Sign in with the same verified account to sync another device.",
                          "Đăng nhập cùng tài khoản đã xác minh để đồng bộ thiết bị khác.",
                        ),
                        tr(
                          "Pull down on a page to refresh its information.",
                          "Kéo trang xuống để cập nhật thông tin.",
                        ),
                        tr(
                          "Return to Settings → How to Use the App whenever you need help.",
                          "Quay lại Cài đặt → Cách dùng ứng dụng bất cứ khi nào bạn cần trợ giúp.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _GuideSectionTitle(
                      icon: Icons.lightbulb_rounded,
                      title: tr("Helpful tips", "Mẹo hữu ích"),
                    ),
                    const SizedBox(height: 10),
                    _GuideTipCard(
                      icon: Icons.document_scanner_rounded,
                      text: tr(
                        "For scanning, use bright light, hold the phone straight, and include the medication name, strength, directions, and quantity.",
                        "Khi quét, dùng ánh sáng rõ, giữ điện thoại thẳng và chụp đủ tên thuốc, hàm lượng, hướng dẫn và số lượng.",
                      ),
                    ),
                    const SizedBox(height: 10),
                    _GuideTipCard(
                      icon: Icons.notifications_active_rounded,
                      text: tr(
                        "If reminders do not appear, allow Notifications for Medication Reminder in the phone’s Settings.",
                        "Nếu không thấy nhắc nhở, hãy cho phép Thông báo cho Medication Reminder trong Cài đặt điện thoại.",
                      ),
                    ),
                    const SizedBox(height: 22),
                    _SafetyCard(tr: tr),
                    const SizedBox(height: 28),
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

class _GuideWelcomeCard extends StatelessWidget {
  final String Function(String, String) tr;

  const _GuideWelcomeCard({required this.tr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            tr(
              "Welcome! Take one step at a time.",
              "Chào mừng! Hãy làm từng bước một.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              "You can return to this guide anytime from Settings.",
              "Bạn có thể quay lại hướng dẫn này bất cứ lúc nào trong Cài đặt.",
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeTextCard extends StatelessWidget {
  final String Function(String, String) tr;

  const _LargeTextCard({required this.tr});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppTextSize.currentTextSize,
      builder: (context, textSize, child) {
        final isLarge = textSize == "large";

        return Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppTheme.line),
          ),
          child: SwitchListTile(
            value: isLarge,
            onChanged: (enabled) {
              AppTextSize.changeTextSize(enabled ? "large" : "normal");
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            secondary: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.lightColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.text_increase_rounded,
                color: AppTheme.primaryColor,
              ),
            ),
            title: Text(
              tr("Use larger words", "Dùng chữ lớn hơn"),
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              tr(
                "Turn this on if the app is difficult to read.",
                "Bật mục này nếu chữ trong ứng dụng khó đọc.",
              ),
              style: const TextStyle(
                color: AppTheme.mutedInk,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GuideSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _GuideSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 25),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideStepCard extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final List<String> instructions;

  const _GuideStepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.instructions,
  });

  @override
  Widget build(BuildContext context) {
    return _GuideSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  "$number",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: AppTheme.primaryColor, size: 27),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          for (final instruction in instructions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primaryColor,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      instruction,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 15,
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
    );
  }
}

class _GuideTipCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _GuideTipCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return _GuideSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 15,
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

class _SafetyCard extends StatelessWidget {
  final String Function(String, String) tr;

  const _SafetyCard({required this.tr});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB54708);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFEC84B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.health_and_safety_rounded, color: color, size: 30),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    "Important safety reminder",
                    "Nhắc nhở an toàn quan trọng",
                  ),
                  style: const TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    "The app helps organize reminders; it does not replace medical advice. Always compare scanned information with the prescription label. Ask a pharmacist or clinician before changing a dose or schedule.",
                    "Ứng dụng giúp sắp xếp nhắc nhở; không thay thế tư vấn y tế. Luôn so sánh thông tin quét với nhãn thuốc. Hỏi dược sĩ hoặc bác sĩ trước khi đổi liều hoặc lịch uống.",
                  ),
                  style: const TextStyle(
                    color: Color(0xFF7A2E0E),
                    fontSize: 14,
                    height: 1.45,
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

class _GuideSurface extends StatelessWidget {
  final Widget child;

  const _GuideSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
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
      child: child,
    );
  }
}
