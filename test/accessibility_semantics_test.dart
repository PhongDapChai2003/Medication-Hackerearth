import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/medication.dart';

void main() {
  testWidgets('timeline medication exposes one clear tappable label', (
    tester,
  ) async {
    var tapped = false;
    final dose = HomeDoseInfo(
      medication: const Medication(
        name: 'Tylenol',
        dosage: '500 mg',
        instructions: 'Take one tablet',
      ),
      medicationIndex: 0,
      time: const TimeOfDay(hour: 8, minute: 0),
      dateTime: DateTime(2026, 8, 10, 8),
      status: 'taken',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 90,
            child: HomeHourlyMedicationEvent(
              dose: dose,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    final semantics = find.bySemanticsLabel(RegExp(r'Tylenol.*500 mg.*Taken'));
    expect(semantics, findsOneWidget);

    await tester.tap(semantics);
    expect(tapped, isTrue);
  });
}
