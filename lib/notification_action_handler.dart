import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'medication_storage.dart';
import 'notification_service.dart';
import 'pill_box_reminder_bridge.dart';

@pragma("vm:entry-point")
void medicationNotificationActionBackground(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationActionHandler.handleInBackground(response);
  } catch (_) {
    // A notification action must never crash the background isolate.
  }
}

class NotificationActionHandler {
  static Future<void> handle(NotificationResponse response) async {
    await _handle(response);
  }

  static Future<void> handleInBackground(NotificationResponse response) async {
    await _handle(response);
  }

  static Future<void> _handle(NotificationResponse response) async {
    final payload = response.payload ?? "";

    if (payload.trim().isEmpty) return;

    dynamic decoded;

    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }

    if (decoded is! Map) return;

    if ((response.actionId ?? '').isEmpty) {
      await PillBoxReminderBridge.triggerMedication(
        decoded["medicationId"]?.toString() ?? "",
      );
      return;
    }

    if (response.actionId == NotificationService.doseActionMute) {
      return;
    }

    String status = "";

    if (response.actionId == NotificationService.doseActionTaken) {
      status = "taken";
    } else if (response.actionId == NotificationService.doseActionMissed) {
      status = "missed";
    }

    if (status.isEmpty) return;

    final recordKey = NotificationService.resolveDoseRecordKey(decoded);

    final changed = await MedicationStorage.applyDoseActionFromNotification(
      accountId: decoded["accountId"]?.toString() ?? "",
      medicationId: decoded["medicationId"]?.toString() ?? "",
      recordKey: recordKey,
      status: status,
    );

    if (changed) {
      await NotificationService.showDoseActionConfirmation(
        payload: decoded,
        status: status,
      );
    }
  }
}
