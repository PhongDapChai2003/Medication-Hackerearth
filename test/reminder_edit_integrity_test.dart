import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/date_helper.dart';
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_storage.dart';
import 'package:flutter_application_1/reminder_page.dart';
import 'package:flutter_application_1/route_transitions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const medicationId = 'reminder-edit-integrity';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLanguage.currentLanguage.value = 'en';
    final secureValues = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final arguments = Map<String, dynamic>.from(
              (call.arguments as Map?) ?? const <String, dynamic>{},
            );
            final key = arguments['key']?.toString() ?? '';
            switch (call.method) {
              case 'read':
                return secureValues[key];
              case 'write':
                secureValues[key] = arguments['value']?.toString() ?? '';
                return null;
              case 'delete':
                secureValues.remove(key);
                return null;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  Medication medicationWith({
    required List<String> reminderTimes,
    required Map<String, String> doseRecords,
    required Map<String, String> doseRecordUpdatedAt,
    required Map<String, String> deletedDoseRecords,
    String instructions = 'Take 1 tablet every 8 hours',
  }) {
    return Medication(
      id: medicationId,
      name: 'Test medicine',
      dosage: '10 mg',
      quantity: '30 tablets',
      remainingQuantity: '24 tablets',
      inventoryBaselineQuantity: '24 tablets',
      inventoryBaselineAt: '2026-09-01T00:00:00.000Z',
      instructions: instructions,
      reminderTimes: reminderTimes,
      doseStatus: 'missed',
      doseStatusDate: '2026-09-19',
      doseRecords: doseRecords,
      doseRecordUpdatedAt: doseRecordUpdatedAt,
      deletedDoseRecords: deletedDoseRecords,
      updatedAt: '2026-09-19T10:00:00.000Z',
    );
  }

  Future<Medication> saveAndReload(Medication medication) async {
    await MedicationStorage.saveMedicationList([medication]);
    final saved = await MedicationStorage.loadCurrentLocalMedications();
    expect(saved, hasLength(1));
    return saved.single;
  }

  Future<void> pumpReminderPage(
    WidgetTester tester,
    Medication medication,
  ) async {
    await tester.runAsync(
      () => MedicationStorage.saveMedicationList([medication]),
    );
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReminderPage(medication: medication, medicationIndex: 0),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> changeVisibleReminderTime(
    WidgetTester tester, {
    required int buttonIndex,
    required String hour,
    required String minute,
  }) async {
    final changeButtons = find.widgetWithText(OutlinedButton, 'Change time');
    expect(changeButtons, findsWidgets);
    await tester.ensureVisible(changeButtons.at(buttonIndex));
    await tester.tap(changeButtons.at(buttonIndex));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final timeFields = find.byType(TextField);
    expect(timeFields, findsNWidgets(2));
    await tester.enterText(timeFields.at(0), hour);
    await tester.enterText(timeFields.at(1), minute);
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  test('normal reminder-time edit preserves taken dose and quantity', () async {
    final initial = medicationWith(
      reminderTimes: const ['08:00', '16:00'],
      doseRecords: const {
        '2026-09-18|08:00': 'taken',
        '2026-09-18|16:00': 'missed',
      },
      doseRecordUpdatedAt: const {
        '2026-09-18|08:00': '2026-09-18T16:00:00.000Z',
        '2026-09-18|16:00': '2026-09-19T00:00:00.000Z',
      },
      deletedDoseRecords: const {
        '2026-09-17|08:00': '2026-09-17T16:00:00.000Z',
      },
    );
    await saveAndReload(initial);

    final edited = initial.copyWith(reminderTimes: const ['09:00', '16:00']);
    final saved = await saveAndReload(edited);

    expect(saved.reminderTimes, const ['09:00', '16:00']);
    expect(saved.doseRecords['2026-09-18|08:00'], 'taken');
    expect(saved.doseRecords['2026-09-18|16:00'], 'missed');
    expect(saved.doseRecords, hasLength(2));
    expect(saved.doseRecordUpdatedAt.keys, containsAll(saved.doseRecords.keys));
    expect(saved.deletedDoseRecords['2026-09-17|08:00'], isNotNull);
    expect(saved.quantity, '30 tablets');
  });

  test(
    'fixed-interval schedule edit preserves all statuses and quantity',
    () async {
      final initial = medicationWith(
        reminderTimes: const ['07:00', '15:00', '23:00'],
        doseRecords: const {
          '2026-09-18|07:00': 'taken',
          '2026-09-18|15:00': 'missed',
          '2026-09-18|23:00': 'skipped',
        },
        doseRecordUpdatedAt: const {
          '2026-09-18|07:00': '2026-09-18T15:00:00.000Z',
          '2026-09-18|15:00': '2026-09-18T23:00:00.000Z',
          '2026-09-18|23:00': '2026-09-19T07:00:00.000Z',
        },
        deletedDoseRecords: const {},
      );
      await saveAndReload(initial);

      final edited = initial.copyWith(
        reminderTimes: const ['09:00', '17:00', '01:00'],
      );
      final saved = await saveAndReload(edited);

      expect(saved.reminderTimes, const ['09:00', '17:00', '01:00']);
      expect(saved.doseRecords, initial.doseRecords);
      expect(saved.doseRecordUpdatedAt, initial.doseRecordUpdatedAt);
      expect(saved.deletedDoseRecords, isEmpty);
      expect(saved.quantity, initial.quantity);
    },
  );

  test(
    'reminder deletion is distinct and records removed from today are tombstoned',
    () async {
      final initial = medicationWith(
        reminderTimes: const ['08:00', '16:00'],
        doseRecords: const {
          '2026-09-19|08:00': 'taken',
          '2026-09-19|16:00': 'missed',
          '2026-09-18|08:00': 'taken',
        },
        doseRecordUpdatedAt: const {},
        deletedDoseRecords: const {},
      );
      await saveAndReload(initial);

      final afterReminderDeletion = initial.copyWith(
        reminderTimes: const ['16:00'],
        doseRecords: const {'2026-09-18|08:00': 'taken'},
        doseRecordUpdatedAt: const {},
      );
      final saved = await saveAndReload(afterReminderDeletion);

      expect(saved.reminderTimes, const ['16:00']);
      expect(saved.doseRecords, const {'2026-09-18|08:00': 'taken'});
      expect(
        saved.deletedDoseRecords.keys,
        containsAll(<String>['2026-09-19|08:00', '2026-09-19|16:00']),
      );
      expect(saved.quantity, initial.quantity);
    },
  );

  test('shared route transition durations match the approved timings', () {
    final route = slowPageRoute<void>(
      builder: (context) => const SizedBox.shrink(),
    );

    expect(route.transitionDuration, const Duration(milliseconds: 420));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 320));
  });

  testWidgets(
    'Change time UI preserves dose records, inventory, timestamps, and tombstones',
    (tester) async {
      final today = DateHelper.todayString();
      final initial = medicationWith(
        instructions: 'Take 1 tablet twice daily',
        reminderTimes: const ['08:00', '16:00'],
        doseRecords: {'$today|08:00': 'taken', '$today|16:00': 'missed'},
        doseRecordUpdatedAt: {
          '$today|08:00': '2026-09-19T16:00:00.000Z',
          '$today|16:00': '2026-09-20T00:00:00.000Z',
        },
        deletedDoseRecords: const {
          '2026-09-18|08:00': '2026-09-18T16:00:00.000Z',
        },
      );
      await pumpReminderPage(tester, initial);

      await changeVisibleReminderTime(
        tester,
        buttonIndex: 0,
        hour: '9',
        minute: '30',
      );

      final saved =
          (await MedicationStorage.loadCurrentLocalMedications()).single;
      expect(saved.reminderTimes, const ['09:30', '16:00']);
      expect(saved.doseRecords, initial.doseRecords);
      expect(saved.doseRecordUpdatedAt, initial.doseRecordUpdatedAt);
      expect(saved.deletedDoseRecords, initial.deletedDoseRecords);
      expect(saved.quantity, initial.quantity);
      expect(saved.remainingQuantity, initial.remainingQuantity);
    },
  );

  testWidgets(
    'fixed-interval Change time UI preserves dose history and inventory',
    (tester) async {
      final today = DateHelper.todayString();
      final initial = medicationWith(
        reminderTimes: const ['07:00', '15:00', '23:00'],
        doseRecords: {
          '$today|07:00': 'taken',
          '$today|15:00': 'missed',
          '$today|23:00': 'skipped',
        },
        doseRecordUpdatedAt: {
          '$today|07:00': '2026-09-19T15:00:00.000Z',
          '$today|15:00': '2026-09-19T23:00:00.000Z',
          '$today|23:00': '2026-09-20T07:00:00.000Z',
        },
        deletedDoseRecords: const {
          '2026-09-18|07:00': '2026-09-18T15:00:00.000Z',
        },
      );
      await pumpReminderPage(tester, initial);

      await changeVisibleReminderTime(
        tester,
        buttonIndex: 1,
        hour: '4',
        minute: '00',
      );

      final saved =
          (await MedicationStorage.loadCurrentLocalMedications()).single;
      expect(saved.reminderTimes, const ['08:00', '16:00', '00:00']);
      expect(saved.doseRecords, initial.doseRecords);
      expect(saved.doseRecordUpdatedAt, initial.doseRecordUpdatedAt);
      expect(saved.deletedDoseRecords, initial.deletedDoseRecords);
      expect(saved.quantity, initial.quantity);
      expect(saved.remainingQuantity, initial.remainingQuantity);
    },
  );

  testWidgets('Delete reminder UI remains a separate destructive action', (
    tester,
  ) async {
    final today = DateHelper.todayString();
    final initial = medicationWith(
      instructions: 'Take 1 tablet twice daily',
      reminderTimes: const ['08:00', '16:00'],
      doseRecords: {
        '$today|08:00': 'taken',
        '$today|16:00': 'missed',
        '2026-09-18|08:00': 'taken',
      },
      doseRecordUpdatedAt: const {},
      deletedDoseRecords: const {},
    );
    await pumpReminderPage(tester, initial);

    final deleteButton = find.widgetWithText(OutlinedButton, 'Delete').first;
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final saved =
        (await MedicationStorage.loadCurrentLocalMedications()).single;
    expect(saved.reminderTimes, const ['16:00']);
    expect(saved.doseRecords, const {'2026-09-18|08:00': 'taken'});
    expect(
      saved.deletedDoseRecords.keys,
      containsAll(<String>['$today|08:00', '$today|16:00']),
    );
    expect(saved.quantity, initial.quantity);
    expect(saved.remainingQuantity, initial.remainingQuantity);
  });
}
