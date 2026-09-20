import 'dart:io';

import 'package:flutter/services.dart';

import 'medication.dart';

class AppleWatchStatus {
  final bool supported;
  final bool paired;
  final bool watchAppInstalled;
  final bool reachable;

  const AppleWatchStatus({
    required this.supported,
    required this.paired,
    required this.watchAppInstalled,
    required this.reachable,
  });

  factory AppleWatchStatus.fromMap(Map<Object?, Object?> map) {
    return AppleWatchStatus(
      supported: map['supported'] == true,
      paired: map['paired'] == true,
      watchAppInstalled: map['watchAppInstalled'] == true,
      reachable: map['reachable'] == true,
    );
  }
}

class AppleWatchService {
  static const MethodChannel _channel = MethodChannel(
    'medication_reminder/apple_watch',
  );

  static Future<AppleWatchStatus> status() async {
    if (!Platform.isIOS) {
      return const AppleWatchStatus(
        supported: false,
        paired: false,
        watchAppInstalled: false,
        reachable: false,
      );
    }

    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'watchStatus',
      );
      return AppleWatchStatus.fromMap(result ?? const {});
    } catch (_) {
      return const AppleWatchStatus(
        supported: true,
        paired: false,
        watchAppInstalled: false,
        reachable: false,
      );
    }
  }

  static Future<bool> syncMedicationSummary(
    List<Medication> medications,
  ) async {
    if (!Platform.isIOS) return false;

    final summaries = medications.map((medication) {
      return <String, Object?>{
        'id': medication.id,
        'name': medication.name,
        'dosage': medication.dosage,
        'instructions': medication.instructions,
        'reminderTimes': medication.reminderTimes,
        'remainingQuantity': medication.remainingQuantity,
      };
    }).toList();

    try {
      return await _channel.invokeMethod<bool>('syncMedicationSummary', {
            'medications': summaries,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
