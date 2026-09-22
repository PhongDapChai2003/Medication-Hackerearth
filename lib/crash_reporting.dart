import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrashReporting {
  static const String _preferenceKey = 'share_anonymous_crash_reports';

  static final ValueNotifier<bool> sharingEnabled = ValueNotifier<bool>(false);
  static bool _firebaseReady = false;
  static bool _handlersInstalled = false;

  static Future<void> loadPreference() async {
    final preferences = await SharedPreferences.getInstance();
    sharingEnabled.value = preferences.getBool(_preferenceKey) ?? false;
  }

  static Future<void> configureAfterFirebase() async {
    // Firebase Crashlytics does not support Flutter web. Firebase Auth and
    // Firestore can still be used there, so do not let Crashlytics disable all
    // Firebase features during web startup.
    if (kIsWeb) {
      _firebaseReady = false;
      return;
    }

    _firebaseReady = true;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      sharingEnabled.value,
    );
  }

  static Future<void> setSharingEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, enabled);
    sharingEnabled.value = enabled;

    if (_firebaseReady) {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enabled,
      );
    }
  }

  static void installGlobalHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);

      if (_firebaseReady && sharingEnabled.value) {
        unawaited(
          FirebaseCrashlytics.instance.recordFlutterFatalError(details),
        );
      }
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      if (!_firebaseReady || !sharingEnabled.value) {
        return false;
      }

      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
      return true;
    };
  }
}
