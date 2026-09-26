import 'package:flutter/material.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/medication_details_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editing medication offers confirmed deletion', (tester) async {
    AppLanguage.currentLanguage.value = 'en';
    const medication = Medication(
      id: 'delete-test',
      name: 'Test medication',
      dosage: '10 mg',
      quantity: '30',
      remainingQuantity: '30',
      instructions: 'Take once daily',
      reminderTimes: <String>['08:00'],
    );

    await tester.pumpWidget(
      const MaterialApp(home: MedicationDetailsPage(medication: medication)),
    );
    await tester.pumpAndSettle();

    final deleteButton = find.text('Delete medication');
    expect(deleteButton, findsOneWidget);
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete medication?'), findsOneWidget);
    expect(
      find.text(
        'Delete Test medication? Its reminder schedule and history will also be removed.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete medication?'), findsNothing);
  });
}
