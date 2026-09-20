import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLanguage {
  static const String _languageKey = "selected_language";

  static ValueNotifier<String> currentLanguage = ValueNotifier<String>("en");

  static Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(_languageKey) ?? "en";

    if (savedLanguage == "en" || savedLanguage == "vi") {
      currentLanguage.value = savedLanguage;
    } else {
      currentLanguage.value = "en";
    }
  }

  static Future<void> changeLanguage(String language) async {
    if (language != "en" && language != "vi") {
      return;
    }

    currentLanguage.value = language;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language);
  }

  static bool get isEnglish {
    return currentLanguage.value == "en";
  }

  static String tr(String english, String vietnamese) {
    return isEnglish ? english : vietnamese;
  }

  static String text(String key) {
    final language = currentLanguage.value;
    final values = _translations[key];

    if (values == null) {
      return key;
    }

    return values[language] ?? values["en"] ?? key;
  }

  static final Map<String, Map<String, String>> _translations = {
    "appTitle": {"en": "Medication Reminder", "vi": "Nhắc Nhở Uống Thuốc"},
    "settings": {"en": "Settings", "vi": "Cài Đặt"},
    "language": {"en": "Language", "vi": "Ngôn Ngữ"},
    "themeColor": {"en": "Theme Color", "vi": "Màu Giao Diện"},
    "textSize": {"en": "Text Size", "vi": "Cỡ Chữ"},
    "normal": {"en": "Normal", "vi": "Bình Thường"},
    "large": {"en": "Large", "vi": "Lớn"},
    "timeFormat": {"en": "Time Format", "vi": "Định Dạng Giờ"},
    "scanPrescription": {"en": "Scan Prescription", "vi": "Quét Toa Thuốc"},
    "openCamera": {"en": "Open Camera", "vi": "Mở Máy Ảnh"},
    "addPrescription": {"en": "Add Prescription", "vi": "Thêm Toa Thuốc"},
    "chooseFromGallery": {
      "en": "Choose from Gallery",
      "vi": "Chọn Từ Thư Viện",
    },
    "chooseFromPhotoLibrary": {
      "en": "Choose from Photo Library",
      "vi": "Chọn Từ Thư Viện Ảnh",
    },
    "addAnotherPhoto": {"en": "Add Another Photo", "vi": "Thêm Ảnh Khác"},
    "addPhotosFromLibrary": {
      "en": "Add Photos from Library",
      "vi": "Thêm Ảnh Từ Thư Viện",
    },
    "noImageSelected": {"en": "No Image Selected", "vi": "Chưa Chọn Ảnh"},
    "confirmCombinedInformation": {
      "en": "Confirm Combined Information",
      "vi": "Xác Nhận Thông Tin Đã Ghép",
    },
    "continueWithCombinedDetails": {
      "en": "Continue with Combined Details",
      "vi": "Tiếp Tục Với Thông Tin Đã Ghép",
    },
    "enterMedicationManually": {
      "en": "Enter Medication Manually",
      "vi": "Nhập Thuốc Thủ Công",
    },
    "rawText": {"en": "Raw Text", "vi": "Chữ Gốc"},
    "hideText": {"en": "Hide Text", "vi": "Ẩn Chữ"},
    "analyzeAgain": {"en": "Analyze Again", "vi": "Phân Tích Lại"},
    "myMedications": {"en": "My Medications", "vi": "Thuốc Của Tôi"},
    "medicationDetails": {"en": "Medication Details", "vi": "Thông Tin Thuốc"},
    "medicationName": {"en": "Medication Name", "vi": "Tên Thuốc"},
    "dosage": {"en": "Dosage", "vi": "Liều Lượng"},
    "quantity": {"en": "Quantity", "vi": "Số Lượng"},
    "totalQuantity": {"en": "Total Quantity", "vi": "Tổng Số Lượng"},
    "remainingQuantity": {"en": "Remaining Quantity", "vi": "Số Lượng Còn Lại"},
    "pharmacyName": {
      "en": "Pharmacy / Clinic Name",
      "vi": "Tên Nhà Thuốc / Phòng Khám",
    },
    "pharmacyPhone": {
      "en": "Pharmacy / Clinic Phone",
      "vi": "Số Điện Thoại Nhà Thuốc / Phòng Khám",
    },
    "instructions": {"en": "Instructions", "vi": "Hướng Dẫn"},
    "notes": {"en": "Notes / Warnings", "vi": "Ghi Chú / Cảnh Báo"},
    "notesHint": {
      "en": "Example: Take with food, avoid alcohol, or warning notes",
      "vi": "Ví dụ: Uống cùng thức ăn, tránh rượu, hoặc ghi chú cảnh báo",
    },
    "startDate": {"en": "Start Date", "vi": "Ngày Bắt Đầu"},
    "endDate": {"en": "End Date", "vi": "Ngày Kết Thúc"},
    "selectStartDate": {"en": "Select start date", "vi": "Chọn ngày bắt đầu"},
    "selectEndDate": {"en": "Select end date", "vi": "Chọn ngày kết thúc"},
    "noEndDate": {"en": "No end date", "vi": "Không có ngày kết thúc"},
    "saveMedication": {"en": "Save Medication", "vi": "Lưu Thuốc"},
    "editMedication": {"en": "Edit Medication", "vi": "Sửa Thuốc"},
    "deleteMedication": {"en": "Delete Medication", "vi": "Xoá Thuốc"},
    "addMedication": {"en": "Add Medication", "vi": "Thêm Thuốc"},
    "searchMedications": {"en": "Search medications...", "vi": "Tìm thuốc..."},
    "all": {"en": "All", "vi": "Tất Cả"},
    "active": {"en": "Active", "vi": "Đang Dùng"},
    "ended": {"en": "Ended", "vi": "Đã Kết Thúc"},
    "notStarted": {"en": "Not Started", "vi": "Chưa Bắt Đầu"},
    "needRefill": {"en": "Need Refill", "vi": "Cần Refill"},
    "outOfMedicine": {"en": "OUT OF MEDICINE", "vi": "ĐÃ HẾT THUỐC"},
    "lowNeedRefill": {"en": "LOW - NEED REFILL", "vi": "SẮP HẾT - CẦN REFILL"},
    "refillNeededNow": {"en": "Refill Needed Now", "vi": "Cần Refill Ngay"},
    "needMoreMedicine": {"en": "Need More Medicine?", "vi": "Cần Thêm Thuốc?"},
    "callPharmacy": {"en": "Call Pharmacy", "vi": "Gọi Nhà Thuốc"},
    "callNow": {"en": "Call now:", "vi": "Gọi ngay:"},
    "callForRefill": {"en": "Call for refill:", "vi": "Gọi refill:"},
    "gotMyRefill": {"en": "I Got My Refill", "vi": "Đã Nhận Refill"},
    "refill": {"en": "Refill", "vi": "Refill"},
    "reminderTimes": {"en": "Reminder Times", "vi": "Giờ Nhắc"},
    "addTime": {"en": "Add Time", "vi": "Thêm Giờ"},
    "editTime": {"en": "Edit Time", "vi": "Sửa Giờ"},
    "deleteTime": {"en": "Delete Time", "vi": "Xoá Giờ"},
    "nextDose": {"en": "Next Dose", "vi": "Liều Tiếp Theo"},
    "doseStatus": {"en": "Dose Status", "vi": "Trạng Thái Liều"},
    "taken": {"en": "Taken", "vi": "Đã Uống"},
    "missed": {"en": "Missed", "vi": "Bỏ Lỡ"},
    "scheduled": {"en": "Scheduled", "vi": "Đã Lên Lịch"},
    "dueNow": {"en": "Due Now", "vi": "Đến Giờ Uống"},
    "late": {"en": "Late", "vi": "Trễ"},
    "asNeeded": {"en": "As Needed", "vi": "Khi Cần"},
    "doseHistory": {"en": "Dose History", "vi": "Lịch Sử Uống Thuốc"},
    "clearAllHistory": {"en": "Clear All History", "vi": "Xoá Toàn Bộ Lịch Sử"},
    "noDoseHistory": {
      "en": "No dose history yet",
      "vi": "Chưa có lịch sử uống thuốc",
    },
    "resetTodayDoseStatus": {
      "en": "Reset Today's Dose Status",
      "vi": "Đặt Lại Trạng Thái Hôm Nay",
    },
    "autoFixReminderTimes": {
      "en": "Auto Fix Reminder Times",
      "vi": "Tự Động Sửa Giờ Nhắc",
    },
    "treatmentProgress": {
      "en": "Treatment Progress",
      "vi": "Tiến Trình Điều Trị",
    },
    "treatmentDates": {"en": "Treatment Dates", "vi": "Ngày Điều Trị"},
    "supplyEstimate": {"en": "Supply Estimate", "vi": "Ước Tính Thuốc Còn"},
    "medicineStatus": {"en": "Medicine Status", "vi": "Trạng Thái Thuốc"},
    "privacyNote": {"en": "Privacy Note", "vi": "Ghi Chú Riêng Tư"},
    "safetyNote": {"en": "Safety Note", "vi": "Ghi Chú An Toàn"},
    "safetyText": {
      "en":
          "This app is only a reminder tool. Always follow your doctor, pharmacist, or prescription label.",
      "vi":
          "Ứng dụng này chỉ là công cụ nhắc nhở. Luôn làm theo hướng dẫn của bác sĩ, dược sĩ hoặc nhãn thuốc.",
    },
    "privacyText": {
      "en": "Medication data is saved locally on this device.",
      "vi": "Thông tin thuốc được lưu cục bộ trên thiết bị này.",
    },
    "cancel": {"en": "Cancel", "vi": "Huỷ"},
    "delete": {"en": "Delete", "vi": "Xoá"},
    "edit": {"en": "Edit", "vi": "Sửa"},
    "save": {"en": "Save", "vi": "Lưu"},
    "undo": {"en": "Undo", "vi": "Hoàn Tác"},
    "loading": {"en": "Loading...", "vi": "Đang tải..."},
    "noMedicationsYet": {"en": "No medications yet", "vi": "Chưa có thuốc"},
    "useExampleForTesting": {
      "en": "Use Example for Testing",
      "vi": "Dùng Ví Dụ Để Thử",
    },
    "refillToFullQuantity": {
      "en": "Refill to Full Quantity",
      "vi": "Đổ Đầy Lại Theo Tổng Số Lượng",
    },
    "useRecommendedQuantity": {
      "en": "Use Recommended Quantity",
      "vi": "Dùng Số Lượng Đề Xuất",
    },
    "quickTreatmentLength": {
      "en": "Quick Treatment Length",
      "vi": "Chọn Nhanh Thời Gian Điều Trị",
    },
  };
}
