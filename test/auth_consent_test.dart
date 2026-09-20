import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/auth_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AppLanguage.currentLanguage.value = "en";
    SharedPreferences.setMockInitialValues({
      "adult_eligibility_confirmed_v1": true,
    });
  });

  testWidgets("Guest access requires an intentional legal agreement", (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthenticationPage()));
    await tester.pumpAndSettle();

    final guestButtonFinder = find.widgetWithText(
      TextButton,
      "Continue as guest",
    );

    expect(guestButtonFinder, findsOneWidget);
    expect(tester.widget<TextButton>(guestButtonFinder).onPressed, isNull);

    final consentFinder = find.byKey(const Key("legal-consent-checkbox"));
    await tester.ensureVisible(consentFinder);
    await tester.pumpAndSettle();
    await tester.tap(consentFinder);
    await tester.pump();

    expect(tester.widget<TextButton>(guestButtonFinder).onPressed, isNotNull);
    expect(find.byKey(const Key("open-terms-of-use")), findsOneWidget);
    expect(find.byKey(const Key("open-privacy-policy")), findsOneWidget);
  });

  testWidgets("Birthday is requested only after choosing guest access", (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MaterialApp(home: AuthenticationPage()));
    await tester.pumpAndSettle();

    expect(find.text("What is your date of birth?"), findsNothing);

    final consentFinder = find.byKey(const Key("legal-consent-checkbox"));
    await tester.ensureVisible(consentFinder);
    await tester.tap(consentFinder);
    await tester.pump();

    final guestButtonFinder = find.widgetWithText(
      TextButton,
      "Continue as guest",
    );
    await tester.ensureVisible(guestButtonFinder);
    await tester.tap(guestButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text("What is your date of birth?"), findsOneWidget);
  });
}
