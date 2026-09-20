import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/notification_service.dart';
import 'package:flutter_application_1/time_helper.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  const medication = Medication(
    id: "amoxicillin-test",
    name: "Amoxicillin",
    dosage: "500 mg",
    quantity: "30",
    remainingQuantity: "20",
    instructions: "Take 2 capsules with food",
    reminderTimes: ["07:00"],
  );

  setUp(() {
    AppLanguage.currentLanguage.value = "en";
    TimeHelper.currentTimeFormat.value = "ampm";
  });

  test("fixed-offset fallback uses the operating system offset", () {
    final location = NotificationService.buildFixedOffsetFallbackLocation(
      offset: const Duration(hours: 5, minutes: 30),
      abbreviation: "IST",
    );
    final localTime = tz.TZDateTime.from(
      DateTime.utc(2026, 1, 15, 0),
      location,
    );

    expect(localTime.hour, 5);
    expect(localTime.minute, 30);
    expect(localTime.timeZoneOffset, const Duration(hours: 5, minutes: 30));
    expect(localTime.timeZoneName, "IST");
  });

  test("IANA timezone data preserves daylight-saving changes", () {
    timezone_data.initializeTimeZones();
    final newYork = tz.getLocation("America/New_York");
    final winter = tz.TZDateTime(newYork, 2026, 1, 15, 9);
    final summer = tz.TZDateTime(newYork, 2026, 7, 15, 9);

    expect(winter.timeZoneOffset, const Duration(hours: -5));
    expect(summer.timeZoneOffset, const Duration(hours: -4));
  });

  test("dose notification includes medication, time, and friendly wording", () {
    final title = NotificationService.buildDoseNotificationTitle(medication);
    final body = NotificationService.buildDoseNotificationBody(
      medication,
      reminderTime: const TimeOfDay(hour: 7, minute: 0),
    );

    expect(title, contains("Hey friend"));
    expect(title, contains("Amoxicillin"));
    expect(title, isNot(contains("💊")));
    expect(body, contains("7:00 AM"));
    expect(body, contains("500 mg dose"));
    expect(body, contains("Take 2 capsules with food"));
    expect(body.toLowerCase(), contains("don’t forget"));
    expect(body, isNot(contains("Taken")));
    expect(body, isNot(contains("Missed")));
  });

  test("follow-up clearly explains the unresolved dose actions", () {
    final title = NotificationService.buildDoseFollowUpTitle(medication);
    final body = NotificationService.buildDoseFollowUpBody(
      medication,
      reminderTime: const TimeOfDay(hour: 19, minute: 0),
    );

    expect(NotificationService.unresolvedFollowUpMinutes, 15);
    expect(title, contains("Did you get a chance"));
    expect(title, contains("Amoxicillin"));
    expect(title, isNot(contains("⏰")));
    expect(body, contains("7:00 PM"));
    expect(body, contains("Dose: 500 mg"));
    expect(body, contains("second reminder"));
    expect(body, isNot(contains("Taken")));
    expect(body, isNot(contains("Missed")));
  });

  test("dose and follow-up notifications use the preferred user name", () {
    final doseTitle = NotificationService.buildDoseNotificationTitle(
      medication,
      preferredName: "  Phong   Truong  ",
    );
    final followUpTitle = NotificationService.buildDoseFollowUpTitle(
      medication,
      preferredName: "Phong Truong",
    );

    expect(doseTitle, startsWith("Phong Truong,"));
    expect(doseTitle, contains("Amoxicillin"));
    expect(followUpTitle, startsWith("Phong Truong,"));
    expect(followUpTitle, contains("Amoxicillin"));
  });

  test("out-of-medicine reminder does not tell the user to take a dose", () {
    final emptyMedication = medication.copyWith(remainingQuantity: "0");
    final title = NotificationService.buildDoseNotificationTitle(
      emptyMedication,
    );
    final body = NotificationService.buildDoseNotificationBody(
      emptyMedication,
      reminderTime: const TimeOfDay(hour: 7, minute: 0),
    );

    expect(title.toLowerCase(), contains("refill"));
    expect(title, isNot(contains("⚠️")));
    expect(body.toLowerCase(), contains("supply appears empty"));
    expect(body.toLowerCase(), contains("contact your pharmacy"));
    expect(body.toLowerCase(), isNot(contains("take it as directed")));
  });

  test("an exact dose record key is preserved for notification actions", () {
    const recordKey = "2026-07-25|07:00";

    expect(
      NotificationService.resolveDoseRecordKey({
        "recordKey": recordKey,
        "reminderTime": "07:00",
      }),
      recordKey,
    );
  });

  test(
    "Android reminders use exact delivery only when permission is granted",
    () {
      expect(
        NotificationService.scheduleModeForExactAlarmPermission(true),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
      expect(
        NotificationService.scheduleModeForExactAlarmPermission(false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    },
  );
}
