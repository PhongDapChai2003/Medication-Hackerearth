import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';
import 'app_text_size.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'cloud_account_preferences_service.dart';
import 'medication_storage.dart';
import 'schedule_preferences.dart';

class _LocalAccountPreferences {
  final Map<String, dynamic> values;
  final String updatedAt;

  const _LocalAccountPreferences({
    required this.values,
    required this.updatedAt,
  });
}

class AccountPreferencesSync {
  static const String _localKeyPrefix = "account_preferences_snapshot_v1_";

  static bool _started = false;
  static bool _applyingCloudValues = false;
  static String _activeAccountId = "";
  static String? _lastCloudToken;
  static String _pendingLocalAccountId = "";
  static _LocalAccountPreferences? _pendingLocalChange;
  static Timer? _localChangeDebounce;
  static StreamSubscription<dynamic>? _authStateSubscription;
  static StreamSubscription<String>? _cloudChangeSubscription;
  static Future<void> _syncQueue = Future<void>.value();

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    AppLanguage.currentLanguage.addListener(_onLocalPreferenceChanged);
    AppTheme.currentTheme.addListener(_onLocalPreferenceChanged);
    AppTextSize.currentTextSize.addListener(_onLocalPreferenceChanged);
    SchedulePreferences.revision.addListener(_onLocalPreferenceChanged);

    await _authStateSubscription?.cancel();
    _authStateSubscription = AuthService.authStateChanges.listen((user) {
      final userId = user != null && !user.isAnonymous
          ? user.uid.toString().trim()
          : "";
      unawaited(_watchAccount(userId));
    });

    await _watchAccount(MedicationStorage.currentAccountId);
  }

  static Future<void> _watchAccount(String userId) async {
    final cleanUserId = userId.trim();

    if (_activeAccountId == cleanUserId && _cloudChangeSubscription != null) {
      return;
    }

    _localChangeDebounce?.cancel();
    _localChangeDebounce = null;
    await _cloudChangeSubscription?.cancel();
    _cloudChangeSubscription = null;
    _activeAccountId = cleanUserId;
    _lastCloudToken = null;
    _pendingLocalAccountId = "";
    _pendingLocalChange = null;

    if (cleanUserId.isEmpty) return;

    _cloudChangeSubscription =
        CloudAccountPreferencesService.watchChanges(cleanUserId).listen(
          (token) {
            if (_activeAccountId != cleanUserId || token == _lastCloudToken) {
              return;
            }

            _lastCloudToken = token;
            unawaited(_synchronize(cleanUserId));
          },
          onError: (_) {
            // Medication sync has the visible connection status. Appearance and
            // schedule settings remain safely stored on this device while offline.
          },
        );

    await _synchronize(cleanUserId);
  }

  static void _onLocalPreferenceChanged() {
    if (_applyingCloudValues || _activeAccountId.isEmpty) return;

    _pendingLocalAccountId = _activeAccountId;
    _pendingLocalChange = _LocalAccountPreferences(
      values: _captureCurrentValues(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    unawaited(_saveLocal(_pendingLocalAccountId, _pendingLocalChange!));
    _localChangeDebounce?.cancel();
    _localChangeDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveLocalChangeAndSync());
    });
  }

  static Future<void> _saveLocalChangeAndSync() async {
    final userId = _activeAccountId;

    if (userId.isEmpty || MedicationStorage.currentAccountId != userId) {
      return;
    }

    final local = _pendingLocalAccountId == userId ? _pendingLocalChange : null;

    if (local == null) return;

    await _saveLocal(userId, local);
    await _synchronize(userId);
  }

  static Future<void> _synchronize(String userId) {
    final completer = Completer<void>();

    _syncQueue = _syncQueue
        .catchError((_) {
          // A later setting change or cloud event must still be able to retry.
        })
        .then((_) async {
          try {
            if (_activeAccountId != userId ||
                MedicationStorage.currentAccountId != userId) {
              completer.complete();
              return;
            }

            await AuthService.refreshCloudSession();
            final cloud = await CloudAccountPreferencesService.download(userId);
            final pending = _pendingLocalAccountId == userId
                ? _pendingLocalChange
                : null;
            final local = pending ?? await _loadLocal(userId);

            if (!cloud.exists) {
              final upload =
                  local ??
                  _LocalAccountPreferences(
                    values: _captureCurrentValues(),
                    updatedAt: DateTime.now().toUtc().toIso8601String(),
                  );
              await _saveLocal(userId, upload);
              await CloudAccountPreferencesService.upload(
                userId: userId,
                values: upload.values,
                updatedAt: upload.updatedAt,
              );
              _clearPendingIfSaved(userId, upload.updatedAt);
              completer.complete();
              return;
            }

            if (local == null || !_isNewer(local.updatedAt, cloud.updatedAt)) {
              final downloaded = _LocalAccountPreferences(
                values: cloud.values,
                updatedAt: cloud.updatedAt.trim().isEmpty
                    ? DateTime.now().toUtc().toIso8601String()
                    : cloud.updatedAt,
              );
              await _applyValues(downloaded.values);
              await _saveLocal(userId, downloaded);
              if (local != null) {
                _clearPendingIfSaved(userId, local.updatedAt);
              }
            } else {
              await CloudAccountPreferencesService.upload(
                userId: userId,
                values: local.values,
                updatedAt: local.updatedAt,
              );
              _clearPendingIfSaved(userId, local.updatedAt);
            }

            completer.complete();
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });

    // Preference sync is deliberately best-effort. The current device keeps
    // working offline, while the queued future can retry on the next change.
    return completer.future.catchError((_) {});
  }

  static Map<String, dynamic> _captureCurrentValues() {
    return {
      "language": AppLanguage.currentLanguage.value,
      "theme": AppTheme.currentTheme.value,
      "textSize": AppTextSize.currentTextSize.value,
      "wakeTime": _timeToString(SchedulePreferences.wakeTime),
      "breakfastTime": _timeToString(SchedulePreferences.breakfastTime),
      "lunchTime": _timeToString(SchedulePreferences.lunchTime),
      "dinnerTime": _timeToString(SchedulePreferences.dinnerTime),
      "bedtime": _timeToString(SchedulePreferences.bedtime),
      "beforeMealMinutes": SchedulePreferences.beforeMealMinutes,
      "afterMealMinutes": SchedulePreferences.afterMealMinutes,
    };
  }

  static Future<void> _applyValues(Map<String, dynamic> values) async {
    _applyingCloudValues = true;

    try {
      await AppLanguage.changeLanguage(
        _validString(values["language"], const {"en", "vi"}, "en"),
      );
      await AppTheme.changeTheme(
        _validString(values["theme"], AppTheme.themes.toSet(), "blue"),
      );
      await AppTextSize.changeTextSize(
        _validString(
          values["textSize"],
          AppTextSize.textSizes.toSet(),
          "normal",
        ),
      );
      await SchedulePreferences.save(
        wake: _parseTime(values["wakeTime"], SchedulePreferences.wakeTime),
        breakfast: _parseTime(
          values["breakfastTime"],
          SchedulePreferences.breakfastTime,
        ),
        lunch: _parseTime(values["lunchTime"], SchedulePreferences.lunchTime),
        dinner: _parseTime(
          values["dinnerTime"],
          SchedulePreferences.dinnerTime,
        ),
        sleep: _parseTime(values["bedtime"], SchedulePreferences.bedtime),
        beforeMeal: _validMealOffset(
          values["beforeMealMinutes"],
          SchedulePreferences.beforeMealMinutes,
        ),
        afterMeal: _validMealOffset(
          values["afterMealMinutes"],
          SchedulePreferences.afterMealMinutes,
        ),
      );
      await MedicationStorage.refreshNotificationSchedule();
    } finally {
      _applyingCloudValues = false;
    }
  }

  static Future<_LocalAccountPreferences?> _loadLocal(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString("$_localKeyPrefix$userId");

    if (encoded == null || encoded.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(encoded);

      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final rawValues = map["values"];
      final updatedAt = map["updatedAt"]?.toString() ?? "";

      if (rawValues is! Map || updatedAt.trim().isEmpty) return null;

      return _LocalAccountPreferences(
        values: Map<String, dynamic>.from(rawValues),
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveLocal(
    String userId,
    _LocalAccountPreferences local,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      "$_localKeyPrefix$userId",
      jsonEncode({"values": local.values, "updatedAt": local.updatedAt}),
    );
  }

  static void _clearPendingIfSaved(String userId, String updatedAt) {
    if (_pendingLocalAccountId == userId &&
        _pendingLocalChange?.updatedAt == updatedAt) {
      _pendingLocalAccountId = "";
      _pendingLocalChange = null;
    }
  }

  static String _validString(
    dynamic value,
    Set<String> allowed,
    String fallback,
  ) {
    final candidate = value?.toString() ?? "";
    return allowed.contains(candidate) ? candidate : fallback;
  }

  static int _validMealOffset(dynamic value, int fallback) {
    final candidate = value is int
        ? value
        : int.tryParse(value?.toString() ?? "");
    return const {15, 30, 45, 60}.contains(candidate) ? candidate! : fallback;
  }

  static String _timeToString(TimeOfDay time) {
    return "${time.hour.toString().padLeft(2, "0")}:"
        "${time.minute.toString().padLeft(2, "0")}";
  }

  static TimeOfDay _parseTime(dynamic value, TimeOfDay fallback) {
    final parts = (value?.toString() ?? "").split(":");

    if (parts.length != 2) return fallback;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  static bool _isNewer(String first, String second) {
    final firstDate = DateTime.tryParse(first);
    final secondDate = DateTime.tryParse(second);

    if (firstDate == null) return false;
    if (secondDate == null) return true;
    return firstDate.isAfter(secondDate);
  }
}
