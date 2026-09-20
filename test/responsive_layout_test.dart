import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/adherence_dashboard_page.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/auth_page.dart';
import 'package:flutter_application_1/dose_history_page.dart';
import 'package:flutter_application_1/legal_pages.dart';
import 'package:flutter_application_1/in_app_guide_overlay.dart';
import 'package:flutter_application_1/main.dart' as app;
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_details_page.dart';
import 'package:flutter_application_1/pharmacy_medications_page.dart';
import 'package:flutter_application_1/reminder_page.dart';
import 'package:flutter_application_1/scan_page.dart';
import 'package:flutter_application_1/schedule_settings_page.dart';
import 'package:flutter_application_1/user_guide_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sampleMedication = Medication(
    id: "responsive-test-medication",
    name: "Amoxicillin Extended Release",
    dosage: "500 mg",
    quantity: "60",
    remainingQuantity: "42",
    instructions:
        "Take two capsules by mouth every eight hours after food with a full glass of water",
    pharmacyName: "Community Family Pharmacy and Medical Clinic",
    pharmacyAddress: "12345 Very Long Healthcare Boulevard, Garden Grove, CA",
    pharmacyPhone: "(714) 555-0199",
    reminderTimes: ["07:00", "15:00", "23:00"],
    startDate: "2026-07-01",
    endDate: "2026-08-01",
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      "adult_eligibility_confirmed_v1": true,
    });
    AppLanguage.currentLanguage.value = "vi";
  });

  tearDown(() {
    AppLanguage.currentLanguage.value = "en";
  });

  Future<void> pumpSmallPhone(
    WidgetTester tester,
    Widget page, {
    bool scroll = true,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.18),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: page,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final initialException = tester.takeException();
    expect(
      initialException,
      isNull,
      reason: "${page.runtimeType} threw an exception on a small phone.",
    );

    if (scroll && find.byType(Scrollable).evaluate().isNotEmpty) {
      for (var index = 0; index < 8; index++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -360));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  final responsivePages = <String, Widget>{
    "user guide": const UserGuidePage(),
    "legal documents": const LegalDocumentsPage(),
    "terms of use": const TermsOfUsePage(),
    "authentication": const AuthenticationPage(),
    "schedule settings": const ScheduleSettingsPage(),
    "medication details": const MedicationDetailsPage(),
    "reminder": const ReminderPage(
      medication: sampleMedication,
      medicationIndex: 0,
    ),
    "dose history": const DoseHistoryPage(
      medication: sampleMedication,
      medicationIndex: 0,
    ),
    "provider medications": const PharmacyMedicationsPage(
      providerName: "Community Family Pharmacy and Medical Clinic",
      address: "12345 Very Long Healthcare Boulevard, Garden Grove, California",
      phone: "(714) 555-0199",
      initialMedications: [sampleMedication],
      initialAllMedications: [sampleMedication],
    ),
    "scan": const ScanPage(),
    "camera scan guide": const CameraScanGuidePage(),
    "health dashboard": const AdherenceDashboardPage(),
  };

  for (final page in responsivePages.entries) {
    testWidgets("${page.key} fits a small phone", (tester) async {
      await pumpSmallPhone(tester, page.value);
    });
  }

  testWidgets("main dashboard cards fit a small phone", (tester) async {
    final doses = <app.HomeDoseInfo>[
      app.HomeDoseInfo(
        medication: sampleMedication,
        medicationIndex: 0,
        time: const TimeOfDay(hour: 7, minute: 0),
        dateTime: DateTime(2026, 8, 1, 7),
        status: "due",
      ),
      app.HomeDoseInfo(
        medication: sampleMedication.copyWith(
          name: "A medication with a very long display name",
        ),
        medicationIndex: 1,
        time: const TimeOfDay(hour: 23, minute: 0),
        dateTime: DateTime(2026, 8, 1, 23),
        status: "scheduled",
      ),
    ];

    await pumpSmallPhone(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            app.HomeCalendarHeader(
              selectedDate: DateTime(2026, 8, 1),
              alertCount: 12,
              onChooseDate: () {},
              onOpenAlerts: () {},
              onOpenAccount: () {},
            ),
            const SizedBox(height: 12),
            app.HomeWeekCalendar(
              selectedDate: DateTime(2026, 8, 1),
              onSelected: (_) {},
            ),
            const SizedBox(height: 12),
            app.TodayNextDoseWidget(
              isLoading: false,
              doses: [doses.first],
              onOpenMedications: () {},
              onOpenReminder: (_, {doseDateTime}) {},
            ),
            const SizedBox(height: 12),
            app.TodayNextDoseWidget(
              isLoading: false,
              doses: doses,
              onOpenMedications: () {},
              onOpenReminder: (_, {doseDateTime}) {},
            ),
            const SizedBox(height: 12),
            app.HomeCalendarDayOverview(
              isLoading: false,
              selectedDate: DateTime(2026, 8, 1),
              doses: doses,
              nextReminder: doses.first,
              onOpenReminder: (_, {doseDateTime}) {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets("today defaults to the timeline and keeps the simple dose list", (
    tester,
  ) async {
    final dose = app.HomeDoseInfo(
      medication: sampleMedication,
      medicationIndex: 0,
      time: const TimeOfDay(hour: 7, minute: 0),
      dateTime: DateTime(2026, 8, 1, 7),
      status: "scheduled",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: app.HomeCalendarDayOverview(
            isLoading: false,
            selectedDate: DateTime(2026, 8, 1),
            doses: [dose],
            nextReminder: dose,
            onOpenReminder: (_, {doseDateTime}) {},
          ),
        ),
      ),
    );

    expect(find.byType(app.HomeCompactMedicationTimeline), findsNothing);
    expect(find.byType(app.HomeHourlyMedicationTimeline), findsOneWidget);

    await tester.tap(find.text("Đơn giản"));
    await tester.pumpAndSettle();

    expect(find.byType(app.HomeCompactMedicationTimeline), findsOneWidget);
    expect(find.byType(app.HomeHourlyMedicationTimeline), findsNothing);
  });

  testWidgets("bell shows the next scheduled dose in the daily summary", (
    tester,
  ) async {
    final dose = app.HomeDoseInfo(
      medication: sampleMedication,
      medicationIndex: 0,
      time: const TimeOfDay(hour: 15, minute: 0),
      dateTime: DateTime(2026, 8, 1, 15),
      status: "scheduled",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: app.HomeAlertsPage(
          todayDoses: [dose],
          lowQuantityMedications: const [],
          onReload: () async => app.HomeAlertSnapshot(
            todayDoses: [dose],
            lowQuantityMedications: const [],
          ),
          onOpenMedications: () {},
          onOpenDose: (_) async {},
        ),
      ),
    );

    expect(find.text("Tổng quan hôm nay"), findsOneWidget);
    expect(find.text("Sắp tới"), findsOneWidget);
    expect(find.text(sampleMedication.name), findsOneWidget);
  });

  testWidgets("every in-app guide step fits a small phone", (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (var step = 0; step < InAppGuideOverlay.stepCount; step++) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: const TextScaler.linear(1.18),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Stack(
            children: [
              const Scaffold(body: SizedBox.expand()),
              InAppGuideOverlay(step: step, onNext: () {}, onClose: () {}),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
