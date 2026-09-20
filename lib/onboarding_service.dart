import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _pendingUserKey =
      "new_account_onboarding_pending_user_v1";
  static const String _stepKeyPrefix = "new_account_onboarding_step_v1_";
  static const String _guestPendingUserKey = "guest_onboarding_pending_user_v1";
  static const String _guestCompletedKey = "guest_onboarding_completed_v1";

  static final ValueNotifier<String?> pendingUserId = ValueNotifier<String?>(
    null,
  );

  static String _stepKey(String userId) {
    return "$_stepKeyPrefix$userId";
  }

  static Future<void> requestForNewAccount(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    pendingUserId.value = cleanUserId;

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingUserKey, cleanUserId);
      await preferences.setInt(_stepKey(cleanUserId), 0);
      await preferences.remove(_guestPendingUserKey);
    } catch (_) {
      // The in-memory marker still allows the tour to appear in this session.
    }
  }

  static Future<void> requestForGuest(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();

      if (preferences.getBool(_guestCompletedKey) ?? false) {
        return;
      }

      final previousGuestUserId = preferences.getString(_guestPendingUserKey);
      pendingUserId.value = cleanUserId;
      await preferences.setString(_pendingUserKey, cleanUserId);
      await preferences.setString(_guestPendingUserKey, cleanUserId);

      if (previousGuestUserId != cleanUserId) {
        await preferences.setInt(_stepKey(cleanUserId), 0);
      }
    } catch (_) {
      // The in-memory marker still allows the Guest tour in this session.
      pendingUserId.value = cleanUserId;
    }
  }

  static Future<void> restoreForUser(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final savedUserId = preferences.getString(_pendingUserKey);

      if (savedUserId == cleanUserId) {
        pendingUserId.value = cleanUserId;
      }
    } catch (_) {
      // A preference read failure must never block the customer from the app.
    }
  }

  static Future<int> loadStepForUser(
    String userId, {
    required int stepCount,
  }) async {
    if (stepCount <= 0) {
      return 0;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final savedStep = preferences.getInt(_stepKey(userId)) ?? 0;
      return savedStep.clamp(0, stepCount - 1).toInt();
    } catch (_) {
      return 0;
    }
  }

  static Future<void> saveStepForUser(String userId, int step) async {
    if (userId.trim().isEmpty || step < 0) {
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_stepKey(userId), step);
    } catch (_) {
      // Losing progress is harmless; the tour simply starts earlier next time.
    }
  }

  static Future<void> completeForUser(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return;
    }

    if (pendingUserId.value == cleanUserId) {
      pendingUserId.value = null;
    }

    try {
      final preferences = await SharedPreferences.getInstance();

      if (preferences.getString(_pendingUserKey) == cleanUserId) {
        await preferences.remove(_pendingUserKey);
      }

      if (preferences.getString(_guestPendingUserKey) == cleanUserId) {
        await preferences.setBool(_guestCompletedKey, true);
        await preferences.remove(_guestPendingUserKey);
      }

      await preferences.remove(_stepKey(cleanUserId));
    } catch (_) {
      // Completion in memory is enough for the current session.
    }
  }
}
