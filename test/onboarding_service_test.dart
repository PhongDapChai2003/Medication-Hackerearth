import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/app_language.dart';
import 'package:flutter_application_1/in_app_guide_overlay.dart';
import 'package:flutter_application_1/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OnboardingService.pendingUserId.value = null;
  });

  test("new account tour saves progress and clears after completion", () async {
    await OnboardingService.requestForNewAccount("user-a");

    expect(OnboardingService.pendingUserId.value, "user-a");
    expect(
      await OnboardingService.loadStepForUser(
        "user-a",
        stepCount: InAppGuideOverlay.stepCount,
      ),
      0,
    );

    await OnboardingService.saveStepForUser("user-a", 2);

    expect(
      await OnboardingService.loadStepForUser(
        "user-a",
        stepCount: InAppGuideOverlay.stepCount,
      ),
      2,
    );

    OnboardingService.pendingUserId.value = null;
    await OnboardingService.restoreForUser("user-a");
    expect(OnboardingService.pendingUserId.value, "user-a");

    await OnboardingService.completeForUser("user-a");
    expect(OnboardingService.pendingUserId.value, isNull);

    await OnboardingService.restoreForUser("user-a");
    expect(OnboardingService.pendingUserId.value, isNull);
  });

  test("a pending tour never opens for a different account", () async {
    await OnboardingService.requestForNewAccount("user-a");
    OnboardingService.pendingUserId.value = null;

    await OnboardingService.restoreForUser("user-b");
    expect(OnboardingService.pendingUserId.value, isNull);

    await OnboardingService.restoreForUser("user-a");
    expect(OnboardingService.pendingUserId.value, "user-a");
  });

  test("Guest tour appears once and keeps its saved step", () async {
    await OnboardingService.requestForGuest("guest-a");

    expect(OnboardingService.pendingUserId.value, "guest-a");

    await OnboardingService.saveStepForUser("guest-a", 2);
    OnboardingService.pendingUserId.value = null;
    await OnboardingService.requestForGuest("guest-a");

    expect(OnboardingService.pendingUserId.value, "guest-a");
    expect(
      await OnboardingService.loadStepForUser(
        "guest-a",
        stepCount: InAppGuideOverlay.stepCount,
      ),
      2,
    );

    await OnboardingService.completeForUser("guest-a");
    await OnboardingService.requestForGuest("guest-b");

    expect(OnboardingService.pendingUserId.value, isNull);
  });

  testWidgets("in-app guide shows the real navigation instruction", (
    tester,
  ) async {
    AppLanguage.currentLanguage.value = "en";
    var nextPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const Scaffold(body: SizedBox.expand()),
            InAppGuideOverlay(
              step: 0,
              onNext: () => nextPressed = true,
              onClose: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.text("Today"), findsOneWidget);
    await tester.tap(find.text("Next"));
    await tester.pump();
    expect(nextPressed, isTrue);
  });
}
