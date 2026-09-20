import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_language.dart';
import 'auth_service.dart';
import 'date_helper.dart';
import 'medication.dart';
import 'time_helper.dart';

class _RollingDoseCandidate {
  final Medication medication;
  final DateTime date;
  final TimeOfDay time;
  final DateTime scheduledAt;
  final String recordKey;
  final bool allowFollowUp;
  final bool scheduleInitial;

  const _RollingDoseCandidate({
    required this.medication,
    required this.date,
    required this.time,
    required this.scheduledAt,
    required this.recordKey,
    required this.allowFollowUp,
    this.scheduleInitial = true,
  });
}

class _RepeatingDoseCandidate {
  final Medication medication;
  final TimeOfDay time;
  final DateTime nextScheduledAt;
  final bool allowFollowUp;

  const _RepeatingDoseCandidate({
    required this.medication,
    required this.time,
    required this.nextScheduledAt,
    required this.allowFollowUp,
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static bool _canScheduleExactAndroidAlarms = false;
  static Future<void> Function(NotificationResponse response)?
  _notificationResponseHandler;
  static void Function(NotificationResponse response)?
  _backgroundNotificationResponseHandler;

  // Android keeps old channel sound settings forever. A new channel version
  // makes the bottle-shake sound take effect for existing installations too.
  static const String _channelId = "medication_reminders_friendly_v6";
  static const String _channelName = "Friendly Medication Reminders";
  static const String _channelDescription =
      "Friendly medication reminders with your recorded bottle-shake sound.";
  static const String _notificationSound = "medicine_bottle_shake.wav";
  static const String _doseCategoryIdentifier = "medication_dose_actions";
  static const String _exactAlarmPermissionRequestedKey =
      "exact_alarm_permission_requested";
  static const String _lastKnownTimeZoneKey = "last_known_time_zone";

  static const int _refillTimeIndex = 999;
  static const int _maximumDoseOccurrences = 28;
  static const int _maximumRefillNotificationSlots = 8;
  static const int unresolvedFollowUpMinutes = 15;
  static const String doseActionTaken = "dose_taken";
  static const String doseActionMissed = "dose_missed";
  static const String doseActionMute = "dose_mute";

  static void configureNotificationResponseHandler(
    Future<void> Function(NotificationResponse response) handler, {
    void Function(NotificationResponse response)? backgroundHandler,
  }) {
    _notificationResponseHandler = handler;
    _backgroundNotificationResponseHandler = backgroundHandler;
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final handler = _notificationResponseHandler;

    if (handler != null) {
      unawaited(handler(response).catchError((_) {}));
    }
  }

  @visibleForTesting
  static tz.Location buildFixedOffsetFallbackLocation({
    required Duration offset,
    required String abbreviation,
  }) {
    final safeAbbreviation = abbreviation.trim().isEmpty
        ? "Local"
        : abbreviation.trim();
    return tz.Location(
      "OS fixed-offset fallback",
      <int>[tz.minTime],
      <int>[0],
      <tz.TimeZone>[
        tz.TimeZone(offset, isDst: false, abbreviation: safeAbbreviation),
      ],
    );
  }

  static Future<void> _configureLocalTimeZone() async {
    String? timezoneName;

    try {
      final dynamic localTimezone = await FlutterTimezone.getLocalTimezone();
      timezoneName = localTimezone is String
          ? localTimezone.trim()
          : localTimezone.identifier.toString().trim();

      if (timezoneName.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(timezoneName));
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(_lastKnownTimeZoneKey, timezoneName);
        return;
      }
    } catch (_) {
      // Try the last OS-provided IANA timezone before using a fixed offset.
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final savedTimezone = preferences
          .getString(_lastKnownTimeZoneKey)
          ?.trim();
      if (savedTimezone != null && savedTimezone.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(savedTimezone));
        return;
      }
    } catch (_) {
      // Shared preferences may not be available during early startup/tests.
    }

    final now = DateTime.now();
    tz.setLocalLocation(
      buildFixedOffsetFallbackLocation(
        offset: now.timeZoneOffset,
        abbreviation: now.timeZoneName,
      ),
    );
  }

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    timezone_data.initializeTimeZones();
    await _configureLocalTimeZone();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings("@mipmap/ic_launcher");

    final categories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        _doseCategoryIdentifier,
        actions: [
          DarwinNotificationAction.plain(
            doseActionTaken,
            tr("Taken", "Đã uống"),
          ),
          DarwinNotificationAction.plain(
            doseActionMissed,
            tr("Missed", "Bỏ lỡ"),
          ),
        ],
      ),
    ];

    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          notificationCategories: categories,
        );

    final DarwinInitializationSettings macSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          notificationCategories: categories,
        );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macSettings,
    );

    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _backgroundNotificationResponseHandler,
    );

    await requestPermission();

    if (Platform.isAndroid) {
      await refreshExactAlarmPermission();
    }

    _isInitialized = true;
  }

  static AndroidScheduleMode scheduleModeForExactAlarmPermission(
    bool canScheduleExactAlarms,
  ) {
    return canScheduleExactAlarms
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static AndroidScheduleMode get _androidScheduleMode {
    return scheduleModeForExactAlarmPermission(_canScheduleExactAndroidAlarms);
  }

  static bool get canScheduleExactAndroidAlarms {
    return !Platform.isAndroid || _canScheduleExactAndroidAlarms;
  }

  static Future<bool> refreshExactAlarmPermission({
    bool requestIfNeeded = false,
  }) async {
    if (!Platform.isAndroid) {
      return true;
    }

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) {
      _canScheduleExactAndroidAlarms = false;
      return false;
    }

    var allowed = await androidPlugin.canScheduleExactNotifications() ?? false;

    if (!allowed && requestIfNeeded) {
      final preferences = await SharedPreferences.getInstance();
      final alreadyRequested =
          preferences.getBool(_exactAlarmPermissionRequestedKey) ?? false;

      if (!alreadyRequested) {
        await preferences.setBool(_exactAlarmPermissionRequestedKey, true);
        allowed = await androidPlugin.requestExactAlarmsPermission() ?? false;
      }
    }

    _canScheduleExactAndroidAlarms = allowed;
    return allowed;
  }

  static Future<bool> requestExactAlarmAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final allowed =
        await androidPlugin?.requestExactAlarmsPermission() ?? false;
    _canScheduleExactAndroidAlarms = allowed;
    return allowed;
  }

  static Future<void> scheduleTestReminder({
    Duration delay = const Duration(seconds: 10),
  }) async {
    if (!isNotificationSupportedOnThisPlatform) return;

    await initialize();
    if (Platform.isAndroid) {
      await refreshExactAlarmPermission();
    }

    await _notificationsPlugin.zonedSchedule(
      id: 2147483000,
      title: tr("Medication reminder test", "Kiểm tra nhắc uống thuốc"),
      body: tr(
        "Your reminders and bottle-shake sound are ready.",
        "Lời nhắc và âm thanh lắc chai đã sẵn sàng.",
      ),
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _notificationDetails(actionable: false),
      androidScheduleMode: _androidScheduleMode,
    );
  }

  static Future<bool> requestPermission() async {
    if (!isNotificationSupportedOnThisPlatform) {
      return false;
    }

    bool allowed = true;

    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final result = await androidPlugin?.requestNotificationsPermission();

      allowed = result ?? true;
    }

    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      final result = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      allowed = result ?? true;
    }

    if (Platform.isMacOS) {
      final macPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();

      final result = await macPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      allowed = result ?? true;
    }

    return allowed;
  }

  static String tr(String english, String vietnamese) {
    return AppLanguage.currentLanguage.value == "en" ? english : vietnamese;
  }

  static NotificationDetails _notificationDetails({
    bool actionable = true,
    bool quiet = false,
    Color? accentColor,
  }) {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: quiet ? Importance.low : Importance.max,
          priority: quiet ? Priority.low : Priority.high,
          playSound: !quiet,
          sound: quiet
              ? null
              : const RawResourceAndroidNotificationSound(
                  "medicine_bottle_shake",
                ),
          enableVibration: !quiet,
          color: accentColor,
          ticker: "Medication Reminder",
          actions: actionable
              ? [
                  AndroidNotificationAction(
                    doseActionTaken,
                    tr("Taken", "Đã uống"),
                  ),
                  AndroidNotificationAction(
                    doseActionMissed,
                    tr("Missed", "Bỏ lỡ"),
                  ),
                ]
              : null,
        );

    final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !quiet,
      sound: quiet ? null : _notificationSound,
      categoryIdentifier: actionable ? _doseCategoryIdentifier : null,
      presentBanner: true,
      presentList: true,
      threadIdentifier: actionable
          ? "medication-dose-reminders"
          : "medication-updates",
      interruptionLevel: quiet
          ? InterruptionLevel.passive
          : InterruptionLevel.active,
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(
    TimeOfDay time, {
    DateTime? notBeforeDate,
  }) {
    final now = tz.TZDateTime.now(tz.local);

    var targetDate = DateHelper.dateOnly(DateTime.now());
    final cleanNotBeforeDate = notBeforeDate == null
        ? null
        : DateHelper.dateOnly(notBeforeDate);

    if (cleanNotBeforeDate != null && cleanNotBeforeDate.isAfter(targetDate)) {
      targetDate = cleanNotBeforeDate;
    }

    var scheduledDate = tz.TZDateTime(
      tz.local,
      targetDate.year,
      targetDate.month,
      targetDate.day,
      time.hour,
      time.minute,
    );

    if (scheduledDate.isBefore(now) || scheduledDate.isAtSameMomentAs(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  static tz.TZDateTime _timeOnDate(DateTime date, TimeOfDay time) {
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  static DateTime _followUpDateTime(DateTime scheduledAt) {
    return scheduledAt.add(const Duration(minutes: unresolvedFollowUpMinutes));
  }

  static bool _hasRoomForFollowUp(
    TimeOfDay currentTime,
    List<TimeOfDay> dailyTimes,
  ) {
    if (dailyTimes.length <= 1) {
      return true;
    }

    final currentMinutes = currentTime.hour * 60 + currentTime.minute;
    var minutesUntilNextDose = 24 * 60;

    for (final otherTime in dailyTimes) {
      final otherMinutes = otherTime.hour * 60 + otherTime.minute;
      var difference = otherMinutes - currentMinutes;

      if (difference <= 0) {
        difference += 24 * 60;
      }

      if (difference < minutesUntilNextDose) {
        minutesUntilNextDose = difference;
      }
    }

    return minutesUntilNextDose > unresolvedFollowUpMinutes;
  }

  static bool _doseIsResolved(Medication medication, String recordKey) {
    final status = medication.doseRecords[recordKey];
    return status == "taken" || status == "missed" || status == "skipped";
  }

  static DateTime _nextRepeatingFollowUpAt({
    required Medication medication,
    required TimeOfDay reminderTime,
    required DateTime nextInitialAt,
    required DateTime now,
  }) {
    var mostRecentInitialAt = DateTime(
      now.year,
      now.month,
      now.day,
      reminderTime.hour,
      reminderTime.minute,
    );

    if (mostRecentInitialAt.isAfter(now)) {
      mostRecentInitialAt = mostRecentInitialAt.subtract(
        const Duration(days: 1),
      );
    }

    final recentFollowUpAt = _followUpDateTime(mostRecentInitialAt);
    final recentRecordKey =
        "${DateHelper.dateToString(mostRecentInitialAt)}|${TimeHelper.timeToString(reminderTime)}";

    if (recentFollowUpAt.isAfter(now) &&
        !_doseIsResolved(medication, recentRecordKey)) {
      return recentFollowUpAt;
    }

    return _followUpDateTime(nextInitialAt);
  }

  static int _notificationId({
    required int medicationIndex,
    required int timeIndex,
  }) {
    return (medicationIndex + 1) * 1000 + timeIndex;
  }

  static int _refillNotificationId({required int medicationIndex}) {
    return _notificationId(
      medicationIndex: medicationIndex,
      timeIndex: _refillTimeIndex,
    );
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    DateTime? notBeforeDate,
    bool repeatDaily = true,
    String? payload,
    bool actionable = true,
  }) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    final scheduledTime = _nextInstanceOfTime(
      time,
      notBeforeDate: notBeforeDate,
    );

    if (repeatDaily) {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledTime,
        notificationDetails: _notificationDetails(actionable: actionable),
        payload: payload,
        androidScheduleMode: _androidScheduleMode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledTime,
      notificationDetails: _notificationDetails(actionable: actionable),
      payload: payload,
      androidScheduleMode: _androidScheduleMode,
    );
  }

  static Future<void> _scheduleOneTimeReminder({
    required int id,
    required String title,
    required String body,
    required DateTime date,
    required TimeOfDay time,
    String? payload,
    bool actionable = true,
  }) async {
    final scheduledTime = _timeOnDate(date, time);
    final now = tz.TZDateTime.now(tz.local);

    if (!scheduledTime.isAfter(now)) {
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledTime,
      notificationDetails: _notificationDetails(actionable: actionable),
      payload: payload,
      androidScheduleMode: _androidScheduleMode,
    );
  }

  static Future<void> scheduleRollingMedicationReminders({
    required List<Medication> medications,
    String accountId = "",
  }) async {
    if (!isNotificationSupportedOnThisPlatform) return;

    await initialize();
    await _notificationsPlugin.cancelAll();

    final now = DateTime.now();
    final today = DateHelper.dateOnly(now);
    final repeatingCandidates = <_RepeatingDoseCandidate>[];
    final datedCandidates = <_RollingDoseCandidate>[];

    for (final medication in medications) {
      if (isTreatmentFinished(medication)) continue;

      final uniqueTimes = <String, TimeOfDay>{};

      for (final time in getReminderTimesForEstimate(medication)) {
        uniqueTimes[TimeHelper.timeToString(time)] = time;
      }

      final times = uniqueTimes.values.toList()
        ..sort((a, b) {
          final aMinutes = a.hour * 60 + a.minute;
          final bMinutes = b.hour * 60 + b.minute;
          return aMinutes.compareTo(bMinutes);
        });

      if (times.isEmpty) continue;

      final startDate = DateHelper.parseMedicationDate(medication.startDate);
      final endDate = DateHelper.parseMedicationDate(medication.endDate);
      final cleanStartDate = startDate == null
          ? null
          : DateHelper.dateOnly(startDate);
      final cleanEndDate = endDate == null
          ? null
          : DateHelper.dateOnly(endDate);
      final startsInFuture =
          cleanStartDate != null && cleanStartDate.isAfter(today);

      // A native daily notification continues while the app is closed. It is
      // safe only after treatment starts because time-only recurring triggers
      // can otherwise fire before a future start date.
      if (cleanEndDate == null && !startsInFuture) {
        for (final time in times) {
          final nextTime = _nextInstanceOfTime(time);
          repeatingCandidates.add(
            _RepeatingDoseCandidate(
              medication: medication,
              time: time,
              nextScheduledAt: DateTime(
                nextTime.year,
                nextTime.month,
                nextTime.day,
                nextTime.hour,
                nextTime.minute,
              ),
              allowFollowUp:
                  !isOutOfMedication(medication) &&
                  _hasRoomForFollowUp(time, times),
            ),
          );
        }

        continue;
      }

      var date = today;

      if (cleanStartDate != null && cleanStartDate.isAfter(date)) {
        date = cleanStartDate;
      }

      var generatedForMedication = 0;

      while (generatedForMedication < _maximumDoseOccurrences) {
        if (cleanEndDate != null && date.isAfter(cleanEndDate)) {
          break;
        }

        for (final time in times) {
          if (generatedForMedication >= _maximumDoseOccurrences) {
            break;
          }

          final scheduledAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          final recordKey =
              "${DateHelper.dateToString(date)}|${TimeHelper.timeToString(time)}";
          final allowFollowUp =
              !isOutOfMedication(medication) &&
              _hasRoomForFollowUp(time, times);
          final followUpAt = _followUpDateTime(scheduledAt);
          final scheduleInitial = scheduledAt.isAfter(now);
          final scheduleUnresolvedFollowUp =
              allowFollowUp &&
              followUpAt.isAfter(now) &&
              !_doseIsResolved(medication, recordKey);

          if (!scheduleInitial && !scheduleUnresolvedFollowUp) {
            continue;
          }

          datedCandidates.add(
            _RollingDoseCandidate(
              medication: medication,
              date: date,
              time: time,
              scheduledAt: scheduledAt,
              recordKey: recordKey,
              allowFollowUp: allowFollowUp,
              scheduleInitial: scheduleInitial,
            ),
          );
          generatedForMedication += 1;
        }

        date = date.add(const Duration(days: 1));
      }
    }

    repeatingCandidates.sort(
      (a, b) => a.nextScheduledAt.compareTo(b.nextScheduledAt),
    );
    datedCandidates.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    var scheduledDoseCount = 0;

    for (final candidate in repeatingCandidates.take(_maximumDoseOccurrences)) {
      final title = buildDoseNotificationTitle(candidate.medication);
      final body = buildDoseNotificationBody(
        candidate.medication,
        reminderTime: candidate.time,
      );
      final reminderTime = TimeHelper.timeToString(candidate.time);
      final payloadData = <String, dynamic>{
        "type": "repeatingDose",
        "accountId": accountId,
        "medicationId": candidate.medication.id,
        "medicationName": candidate.medication.name.trim(),
        "reminderTime": reminderTime,
        "title": title,
        "body": body,
      };
      final payload = jsonEncode(payloadData);

      await scheduleReminder(
        id: _stableNotificationId(
          "daily|${candidate.medication.id}|$reminderTime",
        ),
        title: title,
        body: body,
        time: candidate.time,
        payload: payload,
      );

      if (candidate.allowFollowUp) {
        final followUpAt = _nextRepeatingFollowUpAt(
          medication: candidate.medication,
          reminderTime: candidate.time,
          nextInitialAt: candidate.nextScheduledAt,
          now: now,
        );
        final followUpTime = TimeOfDay.fromDateTime(followUpAt);
        final followUpTitle = buildDoseFollowUpTitle(candidate.medication);
        final followUpBody = buildDoseFollowUpBody(
          candidate.medication,
          reminderTime: candidate.time,
        );
        final followUpPayload = <String, dynamic>{
          ...payloadData,
          "type": "repeatingDoseFollowUp",
          "isFollowUp": true,
          "title": followUpTitle,
          "body": followUpBody,
        };

        await scheduleReminder(
          id: _stableNotificationId(
            "followup|daily|${candidate.medication.id}|$reminderTime",
          ),
          title: followUpTitle,
          body: followUpBody,
          time: followUpTime,
          notBeforeDate: DateHelper.dateOnly(followUpAt),
          payload: jsonEncode(followUpPayload),
        );
      }

      scheduledDoseCount += 1;
    }

    final remainingDatedSlots = _maximumDoseOccurrences - scheduledDoseCount;

    for (final candidate in datedCandidates.take(remainingDatedSlots)) {
      final title = buildDoseNotificationTitle(candidate.medication);
      final body = buildDoseNotificationBody(
        candidate.medication,
        reminderTime: candidate.time,
      );
      final payloadData = <String, dynamic>{
        "type": "dose",
        "accountId": accountId,
        "medicationId": candidate.medication.id,
        "medicationName": candidate.medication.name.trim(),
        "reminderTime": TimeHelper.timeToString(candidate.time),
        "recordKey": candidate.recordKey,
        "title": title,
        "body": body,
      };
      final payload = jsonEncode(payloadData);

      if (candidate.scheduleInitial) {
        await _scheduleOneTimeReminder(
          id: _stableNotificationId(
            "${candidate.medication.id}|${candidate.recordKey}",
          ),
          title: title,
          body: body,
          date: candidate.date,
          time: candidate.time,
          payload: payload,
        );
      }

      if (candidate.allowFollowUp) {
        final followUpAt = _followUpDateTime(candidate.scheduledAt);
        final followUpTitle = buildDoseFollowUpTitle(candidate.medication);
        final followUpBody = buildDoseFollowUpBody(
          candidate.medication,
          reminderTime: candidate.time,
        );
        final followUpPayload = <String, dynamic>{
          ...payloadData,
          "type": "doseFollowUp",
          "isFollowUp": true,
          "title": followUpTitle,
          "body": followUpBody,
        };

        await _scheduleOneTimeReminder(
          id: _stableNotificationId(
            "followup|${candidate.medication.id}|${candidate.recordKey}",
          ),
          title: followUpTitle,
          body: followUpBody,
          date: DateHelper.dateOnly(followUpAt),
          time: TimeOfDay.fromDateTime(followUpAt),
          payload: jsonEncode(followUpPayload),
        );
      }
    }

    var refillCount = 0;

    for (
      int i = 0;
      i < medications.length && refillCount < _maximumRefillNotificationSlots;
      i++
    ) {
      final medication = medications[i];

      if (isTreatmentFinished(medication) ||
          !isLowQuantityMedication(medication)) {
        continue;
      }

      await scheduleRefillReminder(medication: medication, medicationIndex: i);
      refillCount += 1;
    }
  }

  static String resolveDoseRecordKey(Map<dynamic, dynamic> payload) {
    final existingRecordKey = payload["recordKey"]?.toString().trim() ?? "";

    if (existingRecordKey.isNotEmpty) {
      return existingRecordKey;
    }

    final reminderTime = payload["reminderTime"]?.toString().trim() ?? "";

    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(reminderTime)) {
      return "";
    }

    final time = TimeHelper.stringToTime(reminderTime);
    final now = DateTime.now();
    var doseDate = DateHelper.dateOnly(now);
    final scheduledToday = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // A late-night alert answered shortly after midnight still belongs to the
    // previous day's dose.
    if (scheduledToday.isAfter(now)) {
      doseDate = doseDate.subtract(const Duration(days: 1));
    }

    return "${DateHelper.dateToString(doseDate)}|${TimeHelper.timeToString(time)}";
  }

  static Future<void> scheduleSnoozeFromPayload(
    String payload, {
    int minutes = unresolvedFollowUpMinutes,
  }) async {
    if (!isNotificationSupportedOnThisPlatform || payload.trim().isEmpty) {
      return;
    }

    await initialize();
    dynamic decoded;

    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }

    if (decoded is! Map) return;

    final medicationId = decoded["medicationId"]?.toString() ?? "";
    final recordKey = resolveDoseRecordKey(decoded);
    final title = decoded["title"]?.toString() ?? "Medication Reminder";
    final body = decoded["body"]?.toString() ?? "Please take your medication.";
    final scheduledAt = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(minutes: minutes));
    final snoozePayload = Map<String, dynamic>.from(decoded);

    if (recordKey.isNotEmpty) {
      snoozePayload["recordKey"] = recordKey;
    }

    await _notificationsPlugin.zonedSchedule(
      id: _stableNotificationId("snooze|$medicationId|$recordKey"),
      title: title,
      body: tr(
        "$body • Remind me again in $minutes minutes",
        "$body • Nhắc lại sau $minutes phút",
      ),
      scheduledDate: scheduledAt,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: _androidScheduleMode,
      payload: jsonEncode(snoozePayload),
    );
  }

  static Future<void> showDoseActionConfirmation({
    required Map<dynamic, dynamic> payload,
    required String status,
  }) async {
    if (!isNotificationSupportedOnThisPlatform ||
        (status != "taken" && status != "missed")) {
      return;
    }

    await initialize();

    final medicationId = payload["medicationId"]?.toString().trim() ?? "";
    final medicationName = payload["medicationName"]?.toString().trim() ?? "";
    final recordKey = resolveDoseRecordKey(payload);
    final storedTime = payload["reminderTime"]?.toString().trim() ?? "";
    final timeText = RegExp(r'^\d{1,2}:\d{2}$').hasMatch(storedTime)
        ? TimeHelper.formatStoredTimeForDisplay(storedTime)
        : "";
    final displayName = medicationName.isEmpty
        ? tr("Medication", "Thuốc")
        : medicationName;
    final wasTaken = status == "taken";
    final title = wasTaken
        ? tr("$displayName marked Taken", "Đã đánh dấu uống $displayName")
        : tr("$displayName marked Missed", "Đã đánh dấu bỏ lỡ $displayName");
    final body = wasTaken
        ? tr(
            "${timeText.isEmpty ? "Dose" : "$timeText dose"} recorded. Remaining quantity was updated.",
            "Đã ghi nhận ${timeText.isEmpty ? "liều thuốc" : "liều lúc $timeText"}. Số lượng còn lại đã được cập nhật.",
          )
        : tr(
            "${timeText.isEmpty ? "Dose" : "$timeText dose"} recorded as missed. Quantity was not reduced.",
            "Đã ghi nhận ${timeText.isEmpty ? "liều thuốc" : "liều lúc $timeText"} là bỏ lỡ. Số lượng thuốc không bị giảm.",
          );

    await _notificationsPlugin.show(
      id: _stableNotificationId(
        "confirmation|$medicationId|$recordKey|$status",
      ),
      title: title,
      body: body,
      notificationDetails: _notificationDetails(
        actionable: false,
        quiet: true,
        accentColor: wasTaken
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
      ),
    );
  }

  static int _stableNotificationId(String value) {
    var hash = 2166136261;

    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    return 10000 + (hash % 2000000000);
  }

  static Future<void> scheduleMedicationReminders({
    required Medication medication,
    required int medicationIndex,
    String accountId = "",
  }) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    await cancelDoseReminders(medicationIndex);

    if (isTreatmentFinished(medication)) {
      return;
    }

    final times = getReminderTimesForEstimate(medication);

    if (times.isEmpty) {
      return;
    }

    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (endDate != null) {
      var scheduleDate = DateHelper.dateOnly(DateTime.now());

      if (startDate != null &&
          DateHelper.dateOnly(startDate).isAfter(scheduleDate)) {
        scheduleDate = DateHelper.dateOnly(startDate);
      }

      final finalDate = DateHelper.dateOnly(endDate);
      int occurrenceIndex = 0;

      while (!scheduleDate.isAfter(finalDate) &&
          occurrenceIndex < _maximumDoseOccurrences) {
        for (final time in times) {
          if (occurrenceIndex >= _maximumDoseOccurrences) {
            break;
          }

          final id = _notificationId(
            medicationIndex: medicationIndex,
            timeIndex: occurrenceIndex,
          );

          final scheduledTime = _timeOnDate(scheduleDate, time);

          if (scheduledTime.isAfter(tz.TZDateTime.now(tz.local))) {
            final recordKey =
                "${DateHelper.dateToString(scheduleDate)}|${TimeHelper.timeToString(time)}";
            final title = buildDoseNotificationTitle(medication);
            final body = buildDoseNotificationBody(
              medication,
              reminderTime: time,
            );
            final payloadData = <String, dynamic>{
              "type": "dose",
              "accountId": accountId,
              "medicationId": medication.id,
              "medicationName": medication.name.trim(),
              "reminderTime": TimeHelper.timeToString(time),
              "recordKey": recordKey,
              "title": title,
              "body": body,
            };
            final payload = jsonEncode(payloadData);

            await _scheduleOneTimeReminder(
              id: id,
              title: title,
              body: body,
              date: scheduleDate,
              time: time,
              payload: payload,
            );

            if (!isOutOfMedication(medication) &&
                _hasRoomForFollowUp(time, times)) {
              final initialAt = DateTime(
                scheduleDate.year,
                scheduleDate.month,
                scheduleDate.day,
                time.hour,
                time.minute,
              );
              final followUpAt = _followUpDateTime(initialAt);
              final followUpTitle = buildDoseFollowUpTitle(medication);
              final followUpBody = buildDoseFollowUpBody(
                medication,
                reminderTime: time,
              );

              await _scheduleOneTimeReminder(
                id: _stableNotificationId(
                  "followup|${medication.id}|$recordKey",
                ),
                title: followUpTitle,
                body: followUpBody,
                date: DateHelper.dateOnly(followUpAt),
                time: TimeOfDay.fromDateTime(followUpAt),
                payload: jsonEncode({
                  ...payloadData,
                  "type": "doseFollowUp",
                  "isFollowUp": true,
                  "title": followUpTitle,
                  "body": followUpBody,
                }),
              );
            }

            occurrenceIndex += 1;
          }
        }

        scheduleDate = scheduleDate.add(const Duration(days: 1));
      }

      return;
    }

    for (int i = 0; i < times.length && i < _maximumDoseOccurrences; i++) {
      final reminderTime = TimeHelper.timeToString(times[i]);
      final title = buildDoseNotificationTitle(medication);
      final body = buildDoseNotificationBody(
        medication,
        reminderTime: times[i],
      );
      final payloadData = <String, dynamic>{
        "type": "repeatingDose",
        "accountId": accountId,
        "medicationId": medication.id,
        "medicationName": medication.name.trim(),
        "reminderTime": reminderTime,
        "title": title,
        "body": body,
      };
      final payload = jsonEncode(payloadData);

      await scheduleReminder(
        id: _notificationId(medicationIndex: medicationIndex, timeIndex: i),
        title: title,
        body: body,
        time: times[i],
        notBeforeDate: startDate,
        payload: payload,
      );

      if (!isOutOfMedication(medication) &&
          _hasRoomForFollowUp(times[i], times)) {
        final nextInitial = _nextInstanceOfTime(times[i]);
        final followUpAt = _followUpDateTime(
          DateTime(
            nextInitial.year,
            nextInitial.month,
            nextInitial.day,
            nextInitial.hour,
            nextInitial.minute,
          ),
        );
        final followUpTitle = buildDoseFollowUpTitle(medication);
        final followUpBody = buildDoseFollowUpBody(
          medication,
          reminderTime: times[i],
        );

        await scheduleReminder(
          id: _stableNotificationId(
            "followup|daily|${medication.id}|$reminderTime",
          ),
          title: followUpTitle,
          body: followUpBody,
          time: TimeOfDay.fromDateTime(followUpAt),
          notBeforeDate: DateHelper.dateOnly(followUpAt),
          payload: jsonEncode({
            ...payloadData,
            "type": "repeatingDoseFollowUp",
            "isFollowUp": true,
            "title": followUpTitle,
            "body": followUpBody,
          }),
        );
      }
    }
  }

  static Future<void> scheduleRefillReminder({
    required Medication medication,
    required int medicationIndex,
  }) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    await _notificationsPlugin.cancel(
      id: _refillNotificationId(medicationIndex: medicationIndex),
    );

    if (isTreatmentFinished(medication)) {
      return;
    }

    if (!isLowQuantityMedication(medication)) {
      return;
    }

    const refillTime = TimeOfDay(hour: 9, minute: 0);
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (endDate != null) {
      final nextRefill = _nextInstanceOfTime(refillTime);
      final finalTreatmentDate = DateHelper.dateOnly(endDate);
      final nextRefillDate = DateHelper.dateOnly(
        DateTime(nextRefill.year, nextRefill.month, nextRefill.day),
      );

      if (nextRefillDate.isAfter(finalTreatmentDate)) {
        return;
      }
    }

    await scheduleReminder(
      id: _refillNotificationId(medicationIndex: medicationIndex),
      title: buildRefillNotificationTitle(medication),
      body: buildRefillNotificationBody(medication),
      time: refillTime,
      repeatDaily: false,
      actionable: false,
    );
  }

  static Future<void> cancelReminder(int id) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    await _notificationsPlugin.cancel(id: id);
  }

  static Future<void> cancelDoseReminders(int medicationIndex) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    for (int i = 0; i < 50; i++) {
      final id = _notificationId(
        medicationIndex: medicationIndex,
        timeIndex: i,
      );

      await _notificationsPlugin.cancel(id: id);
    }
  }

  static Future<void> cancelMedicationReminders(int medicationIndex) async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    await cancelDoseReminders(medicationIndex);

    await _notificationsPlugin.cancel(
      id: _refillNotificationId(medicationIndex: medicationIndex),
    );
  }

  static Future<void> cancelAllReminders() async {
    if (!isNotificationSupportedOnThisPlatform) {
      return;
    }

    await initialize();

    await _notificationsPlugin.cancelAll();
  }

  static String buildNotificationTitle(Medication medication) {
    return buildDoseNotificationTitle(medication);
  }

  static String buildNotificationBody(Medication medication) {
    return buildDoseNotificationBody(medication);
  }

  static String _notificationUserName([String? preferredName]) {
    return (preferredName ?? AuthService.currentUser?.displayName ?? "")
        .trim()
        .replaceAll(RegExp(r"\s+"), " ");
  }

  static String buildDoseNotificationTitle(
    Medication medication, {
    String? preferredName,
  }) {
    final name = medication.name.trim();
    final userName = _notificationUserName(preferredName);

    if (isOutOfMedication(medication)) {
      if (name.isEmpty) {
        return userName.isEmpty
            ? tr("Medication refill needed", "Cần lấy thêm thuốc")
            : tr(
                "$userName, medication refill needed",
                "$userName ơi, cần lấy thêm thuốc",
              );
      }

      return userName.isEmpty
          ? tr("$name needs a refill", "$name cần refill")
          : tr(
              "$userName, $name needs a refill",
              "$userName ơi, $name cần refill",
            );
    }

    if (name.isEmpty) {
      return userName.isEmpty
          ? tr("Hey friend, medication time", "Bạn ơi, đến giờ uống thuốc rồi")
          : tr(
              "$userName, medication time",
              "$userName ơi, đến giờ uống thuốc rồi",
            );
    }

    return userName.isEmpty
        ? tr(
            "Hey friend, it’s time for $name",
            "Bạn ơi, đến giờ uống $name rồi",
          )
        : tr(
            "$userName, it’s time for $name",
            "$userName ơi, đến giờ uống $name rồi",
          );
  }

  static String buildDoseNotificationBody(
    Medication medication, {
    TimeOfDay? reminderTime,
  }) {
    final name = medication.name.trim();
    final dosage = medication.dosage.trim();
    final instructions = medication.instructions.trim();
    final parts = <String>[];

    if (reminderTime != null) {
      parts.add(TimeHelper.formatTimeForDisplay(reminderTime));
    }

    if (isOutOfMedication(medication)) {
      parts.add(
        tr(
          "${name.isEmpty ? "Your medication" : "Your $name"} supply appears empty. Please contact your pharmacy before taking this dose.",
          "${name.isEmpty ? "Thuốc của bạn" : name} có vẻ đã hết. Hãy liên hệ nhà thuốc trước khi dùng liều này.",
        ),
      );

      final pharmacyText = buildPharmacyContactText(medication);

      if (pharmacyText.isNotEmpty) {
        parts.add(pharmacyText);
      }

      return parts.join(" • ");
    }

    parts.add(
      dosage.isNotEmpty
          ? tr("Don’t forget your $dosage dose.", "Đừng quên liều $dosage nhé.")
          : tr("Don’t forget your medication.", "Đừng quên uống thuốc nhé."),
    );

    if (instructions.isNotEmpty) {
      parts.add(instructions);
    } else {
      parts.add(
        tr(
          "Please follow the directions on your prescription label.",
          "Hãy làm theo hướng dẫn trên nhãn toa thuốc.",
        ),
      );
    }

    if (isLowQuantityMedication(medication)) {
      final remaining = getRemainingQuantity(medication);
      parts.add(
        tr(
          "Only $remaining remaining—plan your refill soon.",
          "Chỉ còn $remaining—hãy chuẩn bị refill sớm.",
        ),
      );
    }

    return parts.join(" • ");
  }

  static String buildDoseFollowUpTitle(
    Medication medication, {
    String? preferredName,
  }) {
    final name = medication.name.trim();
    final userName = _notificationUserName(preferredName);

    if (name.isEmpty) {
      return userName.isEmpty
          ? tr("Just checking in, friend", "Bạn ơi, mình nhắc nhẹ nhé")
          : tr(
              "$userName, just checking in",
              "$userName ơi, mình nhắc nhẹ nhé",
            );
    }

    return userName.isEmpty
        ? tr(
            "Did you get a chance to take $name?",
            "Bạn đã kịp uống $name chưa?",
          )
        : tr(
            "$userName, did you get a chance to take $name?",
            "$userName ơi, bạn đã kịp uống $name chưa?",
          );
  }

  static String buildDoseFollowUpBody(
    Medication medication, {
    required TimeOfDay reminderTime,
  }) {
    final name = medication.name.trim();
    final dosage = medication.dosage.trim();
    final timeText = TimeHelper.formatTimeForDisplay(reminderTime);
    final medicationText = name.isEmpty ? tr("Medication", "Thuốc") : name;
    final doseText = dosage.isEmpty
        ? tr("Dose as directed", "Liều theo hướng dẫn")
        : tr("Dose: $dosage", "Liều: $dosage");

    return tr(
      "$timeText • $medicationText • $doseText • This is a gentle second reminder in case the first one slipped by.",
      "$timeText • $medicationText • $doseText • Đây là lời nhắc nhẹ lần hai nếu bạn đã bỏ lỡ thông báo đầu tiên.",
    );
  }

  static String buildRefillNotificationTitle(Medication medication) {
    final name = medication.name.trim();

    if (isOutOfMedication(medication)) {
      if (name.isEmpty) {
        return "OUT OF MEDICINE";
      }

      return "OUT OF MEDICINE: $name";
    }

    final daysLeft = estimateDaysLeft(medication);

    if (daysLeft > 0 && daysLeft <= 7) {
      if (name.isEmpty) {
        return "Refill soon: $daysLeft days left";
      }

      return "Refill soon: $name";
    }

    if (name.isEmpty) {
      return "Need more medicine?";
    }

    return "Need more $name?";
  }

  static String buildRefillNotificationBody(Medication medication) {
    final parts = <String>[];

    final name = medication.name.trim();
    final quantityText = buildQuantityText(medication);
    final supplyEstimateText = buildSupplyEstimateText(medication);
    final pharmacyText = buildPharmacyContactText(medication);

    if (isOutOfMedication(medication)) {
      if (name.isNotEmpty) {
        parts.add("$name is OUT OF MEDICINE");
      } else {
        parts.add("This medication is OUT OF MEDICINE");
      }
    } else {
      if (name.isNotEmpty) {
        parts.add("$name is almost out");
      } else {
        parts.add("Your medication is almost out");
      }
    }

    if (quantityText.isNotEmpty) {
      parts.add(quantityText);
    }

    if (supplyEstimateText.isNotEmpty) {
      parts.add(supplyEstimateText);
    }

    if (pharmacyText.isNotEmpty) {
      parts.add(pharmacyText);
      parts.add("Ask them for a refill");
    } else {
      parts.add("Call the pharmacy, clinic, or doctor for a refill");
    }

    return parts.join(" • ");
  }

  static String buildQuantityText(Medication medication) {
    final totalQuantity = medication.quantity.trim();

    if (totalQuantity.isEmpty) {
      return "";
    }

    final remainingQuantity = medication.remainingQuantity.trim().isEmpty
        ? totalQuantity
        : medication.remainingQuantity.trim();

    return "Remaining: $remainingQuantity of $totalQuantity";
  }

  static String buildSupplyEstimateText(Medication medication) {
    final totalQuantity = _parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return "";
    }

    final remainingQuantity = getRemainingQuantity(medication);

    if (remainingQuantity <= 0) {
      return "Supply estimate: 0 days left";
    }

    final times = getReminderTimesForEstimate(medication);

    final directions = _scheduleDirections(medication);

    if (times.isEmpty && TimeHelper.isAsNeededInstruction(directions)) {
      return "Supply estimate: as-needed medicine, cannot estimate days left";
    }

    if (times.isEmpty && directions.isNotEmpty) {
      return "Supply estimate unavailable until reminder times are verified";
    }

    if (times.isEmpty) {
      return "";
    }

    final doseAmount = math.max(
      1,
      TimeHelper.getDoseAmountFromInstructions(_doseDirections(medication)),
    );

    final dailyUse = math.max(1, doseAmount * times.length);

    final rawDaysLeft = (remainingQuantity / dailyUse).floor();
    final daysLeft = rawDaysLeft < 1 ? 1 : rawDaysLeft;

    final emptyDate = DateHelper.dateOnly(
      DateTime.now(),
    ).add(Duration(days: daysLeft));

    return "Supply estimate: about $daysLeft days left • Empty around ${DateHelper.displayDate(emptyDate)}";
  }

  static int estimateDaysLeft(Medication medication) {
    final totalQuantity = _parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return 0;
    }

    final remainingQuantity = getRemainingQuantity(medication);

    if (remainingQuantity <= 0) {
      return 0;
    }

    final times = getReminderTimesForEstimate(medication);

    if (times.isEmpty) {
      return 0;
    }

    final doseAmount = math.max(
      1,
      TimeHelper.getDoseAmountFromInstructions(_doseDirections(medication)),
    );

    final dailyUse = math.max(1, doseAmount * times.length);

    final rawDaysLeft = (remainingQuantity / dailyUse).floor();

    return rawDaysLeft < 1 ? 1 : rawDaysLeft;
  }

  static List<TimeOfDay> getReminderTimesForEstimate(Medication medication) {
    if (medication.reminderTimes.isNotEmpty) {
      return medication.reminderTimes.map((time) {
        return TimeHelper.stringToTime(time);
      }).toList();
    }

    return TimeHelper.generateReminderTimesFromInstructions(
      _scheduleDirections(medication),
    );
  }

  static int getRemainingQuantity(Medication medication) {
    final totalQuantity = _parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return 0;
    }

    if (medication.remainingQuantity.trim().isEmpty) {
      return totalQuantity;
    }

    return _parseQuantityNumber(medication.remainingQuantity);
  }

  static String buildPharmacyContactText(Medication medication) {
    final pharmacyName = medication.pharmacyName.trim();
    final pharmacyPhone = medication.pharmacyPhone.trim();

    if (pharmacyName.isEmpty && pharmacyPhone.isEmpty) {
      return "";
    }

    if (pharmacyName.isNotEmpty && pharmacyPhone.isNotEmpty) {
      return "Call $pharmacyName: $pharmacyPhone";
    }

    if (pharmacyName.isNotEmpty) {
      return "Call $pharmacyName";
    }

    return "Call pharmacy: $pharmacyPhone";
  }

  static bool isOutOfMedication(Medication medication) {
    final totalQuantity = _parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return false;
    }

    return getRemainingQuantity(medication) <= 0;
  }

  static bool isLowQuantityMedication(Medication medication) {
    final totalQuantity = _parseQuantityNumber(medication.quantity);

    if (totalQuantity <= 0) {
      return false;
    }

    final remainingQuantity = getRemainingQuantity(medication);
    final percentRemaining = remainingQuantity / totalQuantity;

    return percentRemaining <= 0.05;
  }

  static bool isTreatmentFinished(Medication medication) {
    final endDate = DateHelper.parseMedicationDate(medication.endDate);

    if (endDate == null) {
      return false;
    }

    return DateHelper.isBeforeToday(endDate);
  }

  static bool isTreatmentNotStarted(Medication medication) {
    final startDate = DateHelper.parseMedicationDate(medication.startDate);

    if (startDate == null) {
      return false;
    }

    return DateHelper.isAfterToday(startDate);
  }

  static String _scheduleDirections(Medication medication) {
    return TimeHelper.selectScheduleDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );
  }

  static String _doseDirections(Medication medication) {
    return TimeHelper.combineDoseDirections(
      instructions: medication.instructions,
      notes: medication.notes,
    );
  }

  static int _parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) {
      return 0;
    }

    return int.tryParse(match.group(0) ?? "") ?? 0;
  }

  static String buildReminderPreviewText(Medication medication) {
    final directions = _scheduleDirections(medication);
    final generatedTimes = TimeHelper.generateReminderTimesFromInstructions(
      directions,
    );

    final times = medication.reminderTimes.isNotEmpty
        ? medication.reminderTimes
        : generatedTimes.map((time) {
            return TimeHelper.timeToString(time);
          }).toList();

    final pharmacyText = buildPharmacyContactText(medication);
    final supplyEstimateText = buildSupplyEstimateText(medication);

    String refillText = "";

    if (isOutOfMedication(medication)) {
      refillText = pharmacyText.isEmpty
          ? " Separate refill alert is ON because this medication is OUT OF MEDICINE."
          : " Separate refill alert is ON because this medication is OUT OF MEDICINE. $pharmacyText.";
    } else if (isLowQuantityMedication(medication)) {
      refillText = pharmacyText.isEmpty
          ? " Separate refill alert is ON because quantity is 5% or less."
          : " Separate refill alert is ON because quantity is 5% or less. $pharmacyText.";
    }

    if (supplyEstimateText.isNotEmpty) {
      refillText = "$refillText $supplyEstimateText.";
    }

    if (isTreatmentFinished(medication)) {
      return "Treatment ended. No notifications will be scheduled.";
    }

    if (isTreatmentNotStarted(medication)) {
      return "Treatment has not started. Dose notifications are scheduled to begin on the start date.";
    }

    if (times.isEmpty && TimeHelper.isAsNeededInstruction(directions)) {
      return "As-needed medication: no fixed dose reminders.$refillText";
    }

    if (times.isEmpty && directions.isNotEmpty) {
      return "Reminder times need manual review and verification.$refillText";
    }

    if (times.isEmpty) {
      return "No dose reminder times set.$refillText";
    }

    final displayTimes = times
        .map((time) {
          return TimeHelper.formatStoredTimeForDisplay(time);
        })
        .join(", ");

    return tr(
      "Dose reminders: $displayTimes. If a dose is still unresolved, one friendly follow-up is sent $unresolvedFollowUpMinutes minutes later.$refillText",
      "Giờ nhắc liều: $displayTimes. Nếu liều vẫn chưa được đánh dấu, ứng dụng sẽ nhắc lại nhẹ nhàng sau $unresolvedFollowUpMinutes phút.$refillText",
    );
  }

  static bool get isInitialized {
    return _isInitialized;
  }

  static bool get isNotificationSupportedOnThisPlatform {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
}
