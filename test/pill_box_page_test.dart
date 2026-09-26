import 'package:flutter/material.dart';
import 'package:flutter_application_1/pill_box_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('smart pill box controls fit a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PillBoxPage()));
    await tester.pumpAndSettle();

    expect(find.text('Smart Pill Box'), findsOneWidget);
    expect(find.text('Connect pill box'), findsOneWidget);
    expect(find.textContaining('do not need to change Wi-Fi'), findsOneWidget);
    expect(find.text('7 compartments'), findsOneWidget);
    expect(find.text('Light compartment 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
