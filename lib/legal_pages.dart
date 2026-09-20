import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'app_theme.dart';

class LegalConsentService {
  static const String currentVersion = "2026-07-27";
  static const String _versionKey = "legal_consent_version";
  static const String _acceptedAtKey = "legal_consent_accepted_at";
  static const String _userKey = "legal_consent_user_id";

  static Future<void> recordAcceptance({required String userId}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_versionKey, currentVersion);
      await preferences.setString(
        _acceptedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await preferences.setString(_userKey, userId.trim());
    } catch (_) {
      // A local receipt failure must not strand the customer after sign-in.
    }
  }
}

class LegalDocumentsPage extends StatelessWidget {
  const LegalDocumentsPage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  Future<void> _openPage(BuildContext context, Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _LegalBackground(
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr("Terms & Privacy", "Điều Khoản & Quyền Riêng Tư"),
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        "Review the rules for using the app and how your information is handled.",
                        "Xem quy định sử dụng ứng dụng và cách thông tin của bạn được xử lý.",
                      ),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _LegalDocumentButton(
                      icon: Icons.description_outlined,
                      title: tr("Terms of Use", "Điều Khoản Sử Dụng"),
                      subtitle: tr(
                        "Age requirement, medical disclaimer, and customer responsibilities.",
                        "Yêu cầu độ tuổi, miễn trừ y tế và trách nhiệm của người dùng.",
                      ),
                      onTap: () {
                        _openPage(context, const TermsOfUsePage());
                      },
                    ),
                    const SizedBox(height: 14),
                    _LegalDocumentButton(
                      icon: Icons.privacy_tip_outlined,
                      title: tr("Privacy Policy", "Chính Sách Riêng Tư"),
                      subtitle: tr(
                        "What the app stores, syncs, and shares only when you ask.",
                        "Thông tin ứng dụng lưu, đồng bộ và chỉ chia sẻ khi bạn yêu cầu.",
                      ),
                      onTap: () {
                        _openPage(context, const PrivacyPolicyPage());
                      },
                    ),
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

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScaffold(
      title: tr(
        "Medication Reminder Terms of Use",
        "Điều Khoản Sử Dụng Medication Reminder",
      ),
      effectiveDate: tr(
        "Effective Date: July 27, 2026",
        "Ngày hiệu lực: 27 tháng 7, 2026",
      ),
      sections: [
        _LegalSectionData(
          icon: Icons.check_circle_outline_rounded,
          title: tr("Agreement to These Terms", "Đồng Ý Với Điều Khoản"),
          text: tr(
            "By creating an account or continuing as a guest, you confirm that you have read and agree to these Terms of Use and the Privacy Policy.",
            "Khi tạo tài khoản hoặc tiếp tục với tư cách khách, bạn xác nhận đã đọc và đồng ý với Điều Khoản Sử Dụng và Chính Sách Riêng Tư.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.cake_outlined,
          title: tr("Age Requirement", "Yêu Cầu Độ Tuổi"),
          text: tr(
            "You must be at least 18 years old to use this app. Do not provide a false date of birth to bypass the age check.",
            "Bạn phải từ 18 tuổi trở lên để sử dụng ứng dụng. Không cung cấp ngày sinh sai để vượt qua bước kiểm tra tuổi.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.health_and_safety_outlined,
          title: tr("Not Medical Advice", "Không Phải Lời Khuyên Y Tế"),
          text: tr(
            "Medication Reminder is only a reminder and tracking tool. It does not diagnose, prescribe, recommend doses, or replace a doctor, pharmacist, clinic, hospital, or emergency service. Always follow the medication label and a licensed healthcare professional's instructions.",
            "Medication Reminder chỉ là công cụ nhắc nhở và theo dõi. Ứng dụng không chẩn đoán, kê đơn, khuyến nghị liều hoặc thay thế bác sĩ, dược sĩ, phòng khám, bệnh viện hay dịch vụ cấp cứu. Luôn làm theo nhãn thuốc và hướng dẫn của chuyên gia y tế có giấy phép.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.fact_check_outlined,
          title: tr(
            "Check Scans and Reminders",
            "Kiểm Tra Kết Quả Quét và Lời Nhắc",
          ),
          text: tr(
            "OCR, typed instructions, pharmacy search results, automatic calculations, reminder times, and notifications can be incomplete or incorrect. You are responsible for reviewing every medication name, dose, instruction, date, provider, and reminder before saving or taking medication.",
            "OCR, hướng dẫn đã nhập, kết quả tìm nhà thuốc, phép tính tự động, giờ nhắc và thông báo có thể thiếu hoặc sai. Bạn có trách nhiệm kiểm tra mọi tên thuốc, liều, hướng dẫn, ngày, cơ sở y tế và lời nhắc trước khi lưu hoặc uống thuốc.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.notifications_active_outlined,
          title: tr("Notification Limits", "Giới Hạn Thông Báo"),
          text: tr(
            "Notifications can be delayed or blocked by device settings, battery restrictions, network conditions, or operating-system behavior. Do not rely on this app as your only way to remember essential medication.",
            "Thông báo có thể bị trễ hoặc chặn do cài đặt thiết bị, giới hạn pin, mạng hoặc hệ điều hành. Không dùng ứng dụng này làm cách duy nhất để nhớ thuốc thiết yếu.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.person_outline_rounded,
          title: tr("Your Account and Data", "Tài Khoản và Dữ Liệu"),
          text: tr(
            "Keep your sign-in information secure and enter only information you are authorized to store. Guest data remains on the device and may be lost if the app is removed or the device is unavailable. You may delete your account from Account & Cloud Sync.",
            "Giữ an toàn thông tin đăng nhập và chỉ nhập thông tin bạn được phép lưu. Dữ liệu khách nằm trên thiết bị và có thể mất nếu ứng dụng bị xóa hoặc thiết bị không còn sử dụng được. Bạn có thể xóa tài khoản trong Tài Khoản & Đồng Bộ.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.emergency_outlined,
          title: tr("Emergencies", "Trường Hợp Khẩn Cấp"),
          text: tr(
            "Do not use this app for an emergency. If you think you took the wrong medication or dose, contact a licensed healthcare professional, poison control service, or local emergency service immediately.",
            "Không dùng ứng dụng này cho trường hợp khẩn cấp. Nếu bạn nghĩ mình đã uống sai thuốc hoặc sai liều, hãy liên hệ ngay chuyên gia y tế có giấy phép, trung tâm chống độc hoặc dịch vụ cấp cứu địa phương.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.update_rounded,
          title: tr("Changes and Contact", "Thay Đổi và Liên Hệ"),
          text: tr(
            "These terms may be updated as the app changes. A new agreement may be requested when an important update is made. Add the developer's support email before public App Store release.",
            "Điều khoản có thể được cập nhật khi ứng dụng thay đổi. Ứng dụng có thể yêu cầu đồng ý lại khi có thay đổi quan trọng. Hãy thêm email hỗ trợ của nhà phát triển trước khi phát hành công khai trên App Store.",
          ),
        ),
      ],
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScaffold(
      title: tr(
        "Medication Reminder Privacy Policy",
        "Chính Sách Riêng Tư Medication Reminder",
      ),
      effectiveDate: tr(
        "Effective Date: July 24, 2026",
        "Ngày hiệu lực: 24 tháng 7, 2026",
      ),
      sections: [
        _LegalSectionData(
          icon: Icons.medication_rounded,
          title: tr("Information Stored by the App", "Thông Tin Ứng Dụng Lưu"),
          text: tr(
            "Medication Reminder may store medication name, dosage, quantity, remaining quantity, reminder times, dose history, notes, pharmacy, doctor, clinic, or hospital name, and its phone number.",
            "Medication Reminder có thể lưu tên thuốc, liều lượng, tổng số lượng, số lượng còn lại, giờ nhắc, lịch sử liều, ghi chú, tên nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện, và số điện thoại của cơ sở đó.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.camera_alt_rounded,
          title: tr("Camera and Photo Library", "Camera và Thư Viện Ảnh"),
          text: tr(
            "The app uses the camera or photo library only when you choose to scan a prescription label. OCR runs on the selected image to help fill medication details. When you type at least two letters in the Medication Name field, including when correcting a scanned name, only that medication-name query is sent to the U.S. National Library of Medicine RxNorm service. Dose instructions, notes, account details, and your medication list are not sent to RxNorm.",
            "Ứng dụng chỉ dùng camera hoặc thư viện ảnh khi bạn chọn quét nhãn thuốc. OCR xử lý ảnh đã chọn để hỗ trợ điền thông tin thuốc. Khi bạn nhập ít nhất hai ký tự trong ô Tên Thuốc, kể cả khi sửa tên đã quét, chỉ nội dung tìm kiếm tên thuốc đó được gửi đến dịch vụ RxNorm của Thư viện Y khoa Quốc gia Hoa Kỳ. Hướng dẫn liều, ghi chú, thông tin tài khoản và danh sách thuốc không được gửi đến RxNorm.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.map_outlined,
          title: tr("Healthcare Provider Search", "Tìm Cơ Sở và Bác Sĩ"),
          text: tr(
            "When you type in the Pharmacy / Doctor / Clinic / Hospital field, only that provider-search text is sent to Apple Maps to find matching providers, locations, addresses, and publicly listed phone numbers. Medication names, doses, instructions, notes, account details, and your medication list are not sent with the provider search. Selecting a result saves the provider name, address, and phone number in the medication record.",
            "Khi bạn nhập trong ô Nhà Thuốc / Bác Sĩ / Phòng Khám / Bệnh Viện, chỉ nội dung tìm kiếm cơ sở hoặc bác sĩ đó được gửi đến Apple Maps để tìm kết quả phù hợp, địa chỉ và số điện thoại công khai. Tên thuốc, liều dùng, hướng dẫn, ghi chú, thông tin tài khoản và danh sách thuốc không được gửi cùng nội dung tìm kiếm. Khi chọn kết quả, hồ sơ thuốc lưu tên, địa chỉ và số điện thoại của cơ sở hoặc bác sĩ.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.phone_rounded,
          title: tr("Care Location Phone Calls", "Gọi Cơ Sở Y Tế"),
          text: tr(
            "The app may open the phone dialer when you tap a saved pharmacy, doctor, clinic, or hospital phone number. The app does not place calls automatically.",
            "Ứng dụng có thể mở trình gọi điện khi bạn bấm vào số điện thoại nhà thuốc, bác sĩ, phòng khám hoặc bệnh viện đã lưu. Ứng dụng không tự động gọi điện.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.account_circle_rounded,
          title: tr("Accounts and Cloud Sync", "Tài Khoản và Đồng Bộ Đám Mây"),
          text: tr(
            "The app uses Firebase Authentication. You may use an anonymous guest account or create an email account. If you create an email account, Firebase stores the email address and authentication information needed to operate the account.",
            "Ứng dụng dùng Firebase Authentication. Bạn có thể dùng tài khoản khách ẩn danh hoặc tạo tài khoản email. Nếu tạo tài khoản email, Firebase lưu địa chỉ email và thông tin xác thực cần thiết để vận hành tài khoản.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.cloud_done_rounded,
          title: tr(
            "How Medication Information Is Stored",
            "Cách Lưu Thông Tin Thuốc",
          ),
          text: tr(
            "The offline medication cache is encrypted on this device with a key held in the operating-system secure key store. Guest medication data stays local. Email accounts sync separate medication and dose-history records to Cloud Firestore under the account ID. Firestore rules restrict each account to its own records, and Firebase App Check helps reject requests that do not come from a registered app. The app does not sell medication data or use it for advertising.",
            "Bộ nhớ thuốc ngoại tuyến được mã hóa trên thiết bị bằng khóa trong kho khóa an toàn của hệ điều hành. Dữ liệu khách chỉ lưu cục bộ. Tài khoản email đồng bộ từng thuốc và lịch sử liều riêng biệt lên Cloud Firestore theo mã tài khoản. Quy tắc Firestore giới hạn mỗi tài khoản chỉ truy cập dữ liệu của mình và Firebase App Check hỗ trợ từ chối yêu cầu không đến từ ứng dụng đã đăng ký. Ứng dụng không bán dữ liệu hoặc dùng cho quảng cáo.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.share_rounded,
          title: tr(
            "Caregiver Export and Sharing",
            "Xuất và Chia Sẻ với Người Chăm Sóc",
          ),
          text: tr(
            "The dashboard can create a medication and adherence report. Nothing is sent automatically. The report is copied or placed into an email or message only after you choose that action and select a recipient in the device app.",
            "Bảng theo dõi có thể tạo báo cáo thuốc và tuân thủ. Không có nội dung nào được tự động gửi. Báo cáo chỉ được sao chép hoặc đưa vào email hay tin nhắn sau khi bạn chọn thao tác và chọn người nhận trong ứng dụng của thiết bị.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.bug_report_outlined,
          title: tr("Optional Crash Reports", "Báo Cáo Lỗi Tùy Chọn"),
          text: tr(
            "Crash reporting is off by default. If you enable Share Crash Reports in Settings, Firebase Crashlytics may receive app version, operating-system, device, stack-trace, and crash diagnostics. The app does not attach medication names, doses, instructions, notes, or dose history to these reports. You can turn sharing off again at any time.",
            "Báo cáo lỗi mặc định được tắt. Nếu bạn bật Chia sẻ báo cáo lỗi trong Cài đặt, Firebase Crashlytics có thể nhận phiên bản ứng dụng, hệ điều hành, thiết bị, dấu vết ngăn xếp và dữ liệu chẩn đoán lỗi. Ứng dụng không đính kèm tên thuốc, liều, hướng dẫn, ghi chú hoặc lịch sử liều vào các báo cáo này. Bạn có thể tắt chia sẻ bất cứ lúc nào.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.manage_accounts_rounded,
          title: tr(
            "Your Choices and Data Deletion",
            "Lựa Chọn và Xóa Dữ Liệu",
          ),
          text: tr(
            "You can sync manually, sign out, or permanently delete your account and its medication records from the Account & Cloud Sync screen. Deleting the app alone may not delete cloud data. Account deletion may require a recent sign-in for security.",
            "Bạn có thể đồng bộ thủ công, đăng xuất hoặc xóa vĩnh viễn tài khoản và dữ liệu thuốc trong màn hình Tài Khoản & Đồng Bộ. Chỉ xóa ứng dụng có thể không xóa dữ liệu đám mây. Việc xóa tài khoản có thể yêu cầu đăng nhập lại gần đây để bảo mật.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.notifications_rounded,
          title: tr("Permissions", "Quyền Truy Cập"),
          text: tr(
            "Camera permission is used to take prescription label photos. Photo library permission is used to choose prescription label photos. Notification permission is used to send medication reminders.",
            "Quyền camera được dùng để chụp nhãn thuốc. Quyền thư viện ảnh được dùng để chọn ảnh nhãn thuốc. Quyền thông báo được dùng để gửi nhắc nhở uống thuốc.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.health_and_safety_rounded,
          title: tr("Medical Disclaimer", "Miễn Trừ Y Tế"),
          text: tr(
            "Medication Reminder is a reminder and tracking tool only. It does not provide medical advice, diagnosis, treatment, or prescription recommendations. Always confirm medication instructions with a licensed healthcare professional.",
            "Medication Reminder chỉ là công cụ nhắc nhở và theo dõi. Ứng dụng không cung cấp lời khuyên y tế, chẩn đoán, điều trị, hoặc khuyến nghị đơn thuốc. Luôn xác nhận hướng dẫn dùng thuốc với chuyên gia y tế có giấy phép.",
          ),
        ),
        _LegalSectionData(
          icon: Icons.email_rounded,
          title: tr("Contact", "Liên Hệ"),
          text: tr(
            "For privacy questions, contact the app developer. Add your support email before App Store submission.",
            "Nếu có câu hỏi về quyền riêng tư, hãy liên hệ nhà phát triển ứng dụng. Thêm email hỗ trợ trước khi gửi lên App Store.",
          ),
        ),
      ],
    );
  }
}

class _LegalDocumentScaffold extends StatelessWidget {
  final String title;
  final String effectiveDate;
  final List<_LegalSectionData> sections;

  const _LegalDocumentScaffold({
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _LegalBackground(
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      effectiveDate,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    for (var index = 0; index < sections.length; index++) ...[
                      _LegalSection(section: sections[index]),
                      if (index != sections.length - 1)
                        const SizedBox(height: 14),
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

class _LegalSectionData {
  final IconData icon;
  final String title;
  final String text;

  const _LegalSectionData({
    required this.icon,
    required this.title,
    required this.text,
  });
}

class _LegalSection extends StatelessWidget {
  final _LegalSectionData section;

  const _LegalSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(section.icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    color: Color(0xFF1E2A3A),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  section.text,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.4,
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

class _LegalDocumentButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LegalDocumentButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1E2A3A),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalBackground extends StatelessWidget {
  final Widget child;

  const _LegalBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: AppTheme.pageDecoration(),
      child: child,
    );
  }
}
