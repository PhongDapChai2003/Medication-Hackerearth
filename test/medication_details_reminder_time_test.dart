import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_details_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chooses the next free pill-box compartment', () {
    Medication medication(String id, int slot) => Medication(
      id: id,
      name: id,
      dosage: '1 tablet',
      instructions: 'Take daily',
      pillBoxSlot: slot,
    );

    final medications = <Medication>[
      medication('first', 0),
      medication('second', 1),
    ];

    expect(
      chooseAvailablePillBoxSlot(medications: medications, preferredSlot: 0),
      2,
    );
    expect(
      chooseAvailablePillBoxSlot(
        medications: medications,
        excludedMedicationId: 'first',
        preferredSlot: 0,
      ),
      0,
    );
  });

  testWidgets('iPhone reminder time picker adds a selected time', (
    tester,
  ) async {
    AppLanguage.currentLanguage.value = 'en';

    await tester.pumpWidget(const MaterialApp(home: MedicationDetailsPage()));
    await tester.pumpAndSettle();

    final setTimesSwitch = find.byType(SwitchListTile);
    await tester.ensureVisible(setTimesSwitch);
    await tester.tap(setTimesSwitch);
    await tester.pumpAndSettle();

    final addTimeButton = find.text('Add reminder time');
    await tester.ensureVisible(addTimeButton);
    await tester.tap(addTimeButton);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('reminder-time-done')));
    await tester.pumpAndSettle();

    expect(find.text('8:00 AM'), findsOneWidget);
  });
}
