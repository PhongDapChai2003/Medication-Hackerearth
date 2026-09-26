import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'cloud_medication_service.dart';
import 'date_helper.dart';
import 'firebase_options.dart';
import 'medication.dart';
import 'notification_service.dart';
import 'pill_box_reminder_bridge.dart';
import 'secure_local_storage.dart';
import 'time_helper.dart';

enum MedicationSyncState { idle, syncing, synced, offline, error }

class MedicationSyncStatus {
  final MedicationSyncState state;
  final DateTime? lastSyncedAt;
  final String message;

  const MedicationSyncStatus({
    required this.state,
    this.lastSyncedAt,
    this.message = "",
  });
}

class _LocalMedicationLoad {
  final List<Medication> medications;
  final Map<String, String> tombstones;
  final bool migratedLegacyData;

  const _LocalMedicationLoad({
    required this.medications,
    required this.tombstones,
    required this.migratedLegacyData,
  });
}

class _MergedMedicationData {
  final List<Medication> medications;
  final Map<String, String> tombstones;

  const _MergedMedicationData({
    required this.medications,
    required this.tombstones,
  });
}

class _DoseRecordEvent {
  final String updatedAt;
  final String status;
  final bool deleted;

  const _DoseRecordEvent({
    required this.updatedAt,
    required this.status,
    required this.deleted,
  });
}

class MedicationStorage {
  static const String _legacyStorageKey = "saved_medications";
  static const String _userStorageKeyPrefix = "saved_medications_user_";
  static const String _legacyClaimedKey =
      "saved_medications_legacy_claimed_by_first_account";
  static const String _persistentRevisionKey =
      "saved_medications_persistent_revision_v1";
  static int _generatedIdCounter = 0;
  static int _lastPersistentRevision = -1;
  static bool _isCheckingPersistentRevision = false;
  static Timer? _externalChangeTimer;
  static Timer? _cloudChangeDebounceTimer;
  static Timer? _doseActionMaintenanceTimer;
  static StreamSubscription<dynamic>? _authStateSubscription;
  static StreamSubscription<String>? _cloudChangeSubscription;
  static String _watchedCloudAccountId = "";
  static String? _lastCloudChangeToken;
  static Future<void> _synchronizationQueue = Future<void>.value();
  static Future<void> _doseActionQueue = Future<void>.value();

  static final ValueNotifier<MedicationSyncStatus> syncStatus =
      ValueNotifier<MedicationSyncStatus>(
        const MedicationSyncStatus(state: MedicationSyncState.idle),
      );
  static final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  static Future<void> startExternalChangeMonitoring() async {
    await _checkPersistentRevision(notifyListeners: false);

    _externalChangeTimer ??= Timer.periodic(const Duration(milliseconds: 800), (
      _,
    ) {
      unawaited(_checkPersistentRevision());
    });
  }

  static Future<void> checkForExternalDataChanges() async {
    await _checkPersistentRevision();
  }

  static Future<void> startCloudSyncMonitoring() async {
    await _authStateSubscription?.cancel();
    _authStateSubscription = AuthService.authStateChanges.listen((user) {
      final userId = user != null && !user.isAnonymous
          ? user.uid.toString().trim()
          : "";
      unawaited(_watchCloudAccount(userId));
    });

    await _watchCloudAccount(currentAccountId);
  }

  static Future<void> _watchCloudAccount(String userId) async {
    final cleanUserId = userId.trim();

    if (_watchedCloudAccountId == cleanUserId &&
        _cloudChangeSubscription != null) {
      return;
    }

    _cloudChangeDebounceTimer?.cancel();
    _cloudChangeDebounceTimer = null;
    await _cloudChangeSubscription?.cancel();
    _cloudChangeSubscription = null;
    _watchedCloudAccountId = cleanUserId;
    _lastCloudChangeToken = null;

    if (cleanUserId.isEmpty) {
      syncStatus.value = const MedicationSyncStatus(
        state: MedicationSyncState.idle,
      );
      return;
    }

    _cloudChangeSubscription =
        CloudMedicationService.watchMedicationChanges(cleanUserId).listen(
          (token) {
            if (_watchedCloudAccountId != cleanUserId ||
                token == _lastCloudChangeToken) {
              return;
            }

            _lastCloudChangeToken = token;
            _cloudChangeDebounceTimer?.cancel();
            _cloudChangeDebounceTimer = Timer(
              const Duration(milliseconds: 450),
              () {
                if (_watchedCloudAccountId == cleanUserId &&
                    currentAccountId == cleanUserId) {
                  unawaited(syncNow());
                }
              },
            );
          },
          onError: (Object error) async {
            if (_watchedCloudAccountId != cleanUserId) return;
            final diagnosticMessage = await _diagnoseCloudFailure(error);
            syncStatus.value = MedicationSyncStatus(
              state: MedicationSyncState.offline,
              lastSyncedAt: syncStatus.value.lastSyncedAt,
              message: diagnosticMessage,
            );
          },
        );
  }

  static Future<void> _checkPersistentRevision({
    bool notifyListeners = true,
  }) async {
    if (_isCheckingPersistentRevision) return;
    _isCheckingPersistentRevision = true;

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final currentRevision = preferences.getInt(_persistentRevisionKey) ?? 0;

      if (_lastPersistentRevision < 0) {
        _lastPersistentRevision = currentRevision;
        return;
      }

      if (currentRevision == _lastPersistentRevision) {
        return;
      }

      _lastPersistentRevision = currentRevision;

      if (notifyListeners) {
        dataRevision.value += 1;
      }
    } finally {
      _isCheckingPersistentRevision = false;
    }
  }

  static Future<void> _announceDataChange() async {
    // Notify the visible UI before touching platform storage. Notification
    // actions can use another isolate, and waiting for reload here can block a
    // medication form even though its encrypted record is already saved.
    dataRevision.value += 1;
    try {
      final preferences = await SharedPreferences.getInstance();
      final revision = DateTime.now().microsecondsSinceEpoch;
      await preferences.setInt(_persistentRevisionKey, revision);
      _lastPersistentRevision = revision;
    } catch (_) {
      // The next external-change poll can restore the persistent revision.
    }
  }

  static bool get canUseCloudSync {
    return AuthService.firebaseAvailable &&
        AuthService.isSignedIn &&
        !AuthService.isGuest &&
        AuthService.userId.trim().isNotEmpty;
  }

  static String get currentAccountId {
    return canUseCloudSync ? AuthService.userId.trim() : "";
  }

  static String _storageKeyForUser(String userId) {
    return "$_userStorageKeyPrefix$userId";
  }

  static String _tombstoneKeyForUser(String userId) {
    return "saved_medications_tombstones_$userId";
  }

  static String _dirtyKeyForUser(String userId) {
    return "saved_medications_cloud_dirty_$userId";
  }

  static String get _activeStorageKey {
    final userId = currentAccountId;
    return userId.isEmpty ? _legacyStorageKey : _storageKeyForUser(userId);
  }

  static Future<List<Medication>> loadMedications() async {
    final localLoad = await _loadLocalForActiveUser();
    final userId = currentAccountId;

    if (userId.isEmpty) {
      return localLoad.medications;
    }

    try {
      final merged = await _synchronize(userId: userId);
      return merged.medications;
    } catch (error) {
      final diagnosticMessage = await _diagnoseCloudFailure(error);
      syncStatus.value = MedicationSyncStatus(
        state: MedicationSyncState.offline,
        lastSyncedAt: syncStatus.value.lastSyncedAt,
        message: diagnosticMessage,
      );
      return localLoad.medications;
    }
  }

  static Future<List<Medication>> loadCurrentLocalMedications() async {
    return (await _loadLocalForActiveUser()).medications;
  }

  static Future<_LocalMedicationLoad> _loadLocalForActiveUser() async {
    final preferences = await SharedPreferences.getInstance();
    final activeKey = _activeStorageKey;
    var medications = _decodeMedicationList(
      await SecureLocalStorage.getString(activeKey),
    );
    var migratedLegacyData = false;
    final userId = currentAccountId;
    final legacyAlreadyClaimed =
        preferences.getBool(_legacyClaimedKey) ?? false;

    if (userId.isNotEmpty && !legacyAlreadyClaimed) {
      final legacyMedications = _decodeMedicationList(
        await SecureLocalStorage.getString(_legacyStorageKey),
      );

      if (legacyMedications.isNotEmpty) {
        medications = _mergeMedicationLists(medications, legacyMedications);
        migratedLegacyData = true;
      }

      await preferences.setBool(_legacyClaimedKey, true);
    }

    final tombstones = userId.isEmpty
        ? <String, String>{}
        : _decodeStringMap(
            await SecureLocalStorage.getString(_tombstoneKeyForUser(userId)),
          );

    await _writeLocalMedicationList(key: activeKey, medications: medications);

    if (migratedLegacyData) {
      await SecureLocalStorage.remove(_legacyStorageKey);
    }

    return _LocalMedicationLoad(
      medications: medications,
      tombstones: tombstones,
      migratedLegacyData: migratedLegacyData,
    );
  }

  static List<Medication> _decodeMedicationList(String? savedData) {
    if (savedData == null || savedData.trim().isEmpty) return [];

    try {
      final decodedData = jsonDecode(savedData);

      if (decodedData is! List) return [];

      final medications = <Medication>[];

      for (final item in decodedData) {
        if (item is! Map) continue;

        try {
          medications.add(
            normalizeMedication(
              Medication.fromJson(Map<String, dynamic>.from(item)),
            ),
          );
        } catch (_) {
          // Skip only the damaged entry.
        }
      }

      return medications;
    } catch (_) {
      return [];
    }
  }

  static Map<String, String> _decodeStringMap(String? savedData) {
    if (savedData == null || savedData.trim().isEmpty) return {};

    try {
      final decoded = jsonDecode(savedData);

      if (decoded is! Map) return {};

      return decoded.map((key, value) {
        return MapEntry(key.toString(), value.toString());
      });
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeLocalMedicationList({
    required String key,
    required List<Medication> medications,
  }) async {
    final normalized = medications.map(normalizeMedication).toList();
    await SecureLocalStorage.setString(
      key,
      jsonEncode(normalized.map((item) => item.toJson()).toList()),
    );
  }

  static Future<void> _writeTombstones(
    String userId,
    Map<String, String> tombstones,
  ) async {
    if (userId.isEmpty) return;
    await SecureLocalStorage.setString(
      _tombstoneKeyForUser(userId),
      jsonEncode(tombstones),
    );
  }

  static Medication normalizeMedication(Medication medication) {
    final quantity = medication.quantity.trim();
    final remainingQuantity = medication.remainingQuantity.trim().isEmpty
        ? quantity
        : medication.remainingQuantity.trim();
    final reminderTimes = medication.reminderTimes
        .map(TimeHelper.tryParseStoredTime)
        .where((time) => time != null)
        .map((time) => TimeHelper.timeToString(time!))
        .toList();
    final now = DateTime.now().toUtc().toIso8601String();
    final medicationUpdatedAt = medication.updatedAt.trim().isEmpty
        ? now
        : medication.updatedAt.trim();
    final inventoryBaselineQuantity =
        medication.inventoryBaselineQuantity.trim().isEmpty
        ? remainingQuantity
        : medication.inventoryBaselineQuantity.trim();
    final inventoryBaselineAt = medication.inventoryBaselineAt.trim().isEmpty
        ? medicationUpdatedAt
        : medication.inventoryBaselineAt.trim();
    final recordVersions = Map<String, String>.from(
      medication.doseRecordUpdatedAt,
    );
    final deletedRecords = Map<String, String>.from(
      medication.deletedDoseRecords,
    );

    for (final recordKey in medication.doseRecords.keys) {
      recordVersions.putIfAbsent(recordKey, () => medicationUpdatedAt);
      deletedRecords.remove(recordKey);
    }

    return medication.copyWith(
      id: medication.id.trim().isEmpty
          ? _generateMedicationId()
          : medication.id.trim(),
      name: medication.name.trim(),
      dosage: medication.dosage.trim(),
      quantity: quantity,
      remainingQuantity: remainingQuantity,
      inventoryBaselineQuantity: inventoryBaselineQuantity,
      inventoryBaselineAt: inventoryBaselineAt,
      pharmacyName: medication.pharmacyName.trim(),
      pharmacyAddress: medication.pharmacyAddress.trim(),
      pharmacyPhone: medication.pharmacyPhone.trim(),
      instructions: medication.instructions.trim(),
      notes: medication.notes.trim(),
      reminderTimes: reminderTimes,
      doseStatus: medication.doseStatus.trim().isEmpty
          ? "notTakenYet"
          : medication.doseStatus.trim(),
      doseStatusDate: medication.doseStatusDate.trim(),
      doseRecords: Map<String, String>.from(medication.doseRecords),
      doseRecordUpdatedAt: recordVersions,
      deletedDoseRecords: deletedRecords,
      startDate: medication.startDate.trim(),
      endDate: medication.endDate.trim(),
      pillBoxSlot: medication.pillBoxSlot >= 0 && medication.pillBoxSlot < 7
          ? medication.pillBoxSlot
          : -1,
      updatedAt: medicationUpdatedAt,
    );
  }

  static String _generateMedicationId() {
    _generatedIdCounter += 1;
    return "med_${DateTime.now().microsecondsSinceEpoch}_$_generatedIdCounter";
  }

  static Future<void> saveMedication(Medication medication) async {
    final medications = await loadCurrentLocalMedications();
    medications.add(
      normalizeMedication(
        medication.copyWith(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      ),
    );
    await saveMedicationList(medications);
  }

  static Future<void> saveMedicationList(
    List<Medication> medications, {
    bool updateNotifications = true,
  }) async {
    final oldLoad = await _loadLocalForActiveUser();
    final oldById = {for (final item in oldLoad.medications) item.id: item};
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedMedications = medications.map((medication) {
      var normalized = normalizeMedication(medication);
      final previous = oldById[normalized.id];

      if (previous != null &&
          _contentFingerprint(previous) != _contentFingerprint(normalized) &&
          previous.updatedAt == normalized.updatedAt) {
        normalized = normalized.copyWith(updatedAt: now);
      }

      final doseStateChanged =
          previous != null && _doseRecordStateChanged(previous, normalized);
      final contentChanged =
          previous != null &&
          _contentFingerprint(previous) != _contentFingerprint(normalized);

      if (contentChanged && !doseStateChanged) {
        normalized = normalized.copyWith(
          inventoryBaselineQuantity: normalized.remainingQuantity,
          inventoryBaselineAt: now,
        );
      }

      return _stampDoseRecordChanges(
        previous: previous,
        current: normalized,
        timestamp: now,
      );
    }).toList();
    final newIds = normalizedMedications.map((item) => item.id).toSet();
    final tombstones = Map<String, String>.from(oldLoad.tombstones);

    for (final oldMedication in oldLoad.medications) {
      if (!newIds.contains(oldMedication.id)) {
        tombstones[oldMedication.id] = now;
      }
    }

    await _writeLocalMedicationList(
      key: _activeStorageKey,
      medications: normalizedMedications,
    );
    unawaited(_announceDataChange());

    final userId = currentAccountId;

    if (userId.isNotEmpty) {
      // Account metadata and Firebase are secondary to the encrypted local
      // save, so neither is allowed to hold the form's loading state open.
      unawaited(_synchronizeAfterLocalSave(userId, tombstones));
    }

    if (updateNotifications) {
      // Permission dialogs and OS notification scheduling must not keep the
      // medication form stuck on its loading state.
      unawaited(_rescheduleNotificationsAfterLocalSave());
    }
  }

  static Future<void> _synchronizeAfterLocalSave(
    String userId,
    Map<String, String> tombstones,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await _writeTombstones(userId, tombstones);
      await preferences.setBool(_dirtyKeyForUser(userId), true);
      await _synchronize(userId: userId).timeout(const Duration(seconds: 20));
    } catch (error) {
      final diagnosticMessage = await _diagnoseCloudFailure(error);
      syncStatus.value = MedicationSyncStatus(
        state: MedicationSyncState.offline,
        lastSyncedAt: syncStatus.value.lastSyncedAt,
        message: diagnosticMessage,
      );
    }
  }

  static Future<void> _rescheduleNotificationsAfterLocalSave() async {
    final latest = await loadCurrentLocalMedications();
    await rescheduleAllMedicationNotifications(latest);
  }

  static Future<void> updateMedication(int index, Medication medication) async {
    final medications = await loadCurrentLocalMedications();

    if (index < 0 || index >= medications.length) return;

    medications[index] = normalizeMedication(
      medication.copyWith(updatedAt: DateTime.now().toUtc().toIso8601String()),
    );
    await saveMedicationList(medications);
  }

  static Future<bool> updateMedicationById(
    String medicationId,
    Medication medication,
  ) async {
    final medications = await loadCurrentLocalMedications();
    final index = medications.indexWhere((item) => item.id == medicationId);

    if (index < 0) return false;

    medications[index] = normalizeMedication(
      medication.copyWith(updatedAt: DateTime.now().toUtc().toIso8601String()),
    );
    await saveMedicationList(medications);
    return true;
  }

  /// Saves an edited medication even when a recent account/cloud refresh has
  /// not yet copied the original record into the active local list.
  static Future<void> upsertMedicationById(
    String medicationId,
    Medication medication,
  ) async {
    final medications = await loadCurrentLocalMedications();
    final cleanId = medicationId.trim();
    final index = medications.indexWhere((item) => item.id == cleanId);
    final normalized = normalizeMedication(
      medication.copyWith(
        id: cleanId.isEmpty ? medication.id : cleanId,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );

    if (index < 0) {
      medications.add(normalized);
    } else {
      medications[index] = normalized;
    }

    await saveMedicationList(medications);
  }

  static Future<void> deleteMedication(int index) async {
    final medications = await loadCurrentLocalMedications();

    if (index < 0 || index >= medications.length) return;

    medications.removeAt(index);
    await saveMedicationList(medications);
  }

  static Future<bool> deleteMedicationById(String medicationId) async {
    final medications = await loadCurrentLocalMedications();
    final index = medications.indexWhere((item) => item.id == medicationId);

    if (index < 0) return false;

    medications.removeAt(index);
    await saveMedicationList(medications);
    return true;
  }

  static Future<void> mergeMedicationsIntoCurrentUser(
    List<Medication> incomingMedications,
  ) async {
    final current = await loadCurrentLocalMedications();
    final merged = _mergeMedicationLists(current, incomingMedications);
    await saveMedicationList(merged);
  }

  static Future<void> clearGuestLocalMedications() async {
    await SecureLocalStorage.remove(_legacyStorageKey);
  }

  static List<Medication> _mergeMedicationLists(
    List<Medication> primary,
    List<Medication> secondary,
  ) {
    final byId = <String, Medication>{};
    final fingerprints = <String>{};

    void add(Medication medication) {
      final normalized = normalizeMedication(medication);
      final fingerprint = _medicationFingerprint(normalized);
      final existing = byId[normalized.id];

      if (existing != null) {
        if (_isNewer(normalized.updatedAt, existing.updatedAt)) {
          byId[normalized.id] = normalized;
        }
        return;
      }

      if (fingerprints.contains(fingerprint)) return;
      byId[normalized.id] = normalized;
      fingerprints.add(fingerprint);
    }

    primary.forEach(add);
    secondary.forEach(add);
    return byId.values.toList();
  }

  static String _medicationFingerprint(Medication medication) {
    return [
      medication.name.toLowerCase(),
      medication.dosage.toLowerCase(),
      medication.instructions.toLowerCase(),
      medication.startDate,
      medication.endDate,
      medication.pharmacyPhone,
      medication.reminderTimes.join(","),
    ].join("|");
  }

  static String _contentFingerprint(Medication medication) {
    final json = Map<String, dynamic>.from(medication.toJson());
    json.remove("updatedAt");
    json.remove("inventoryBaselineQuantity");
    json.remove("inventoryBaselineAt");
    return jsonEncode(json);
  }

  static bool _doseRecordStateChanged(Medication previous, Medication current) {
    return !mapEquals(previous.doseRecords, current.doseRecords) ||
        !mapEquals(previous.deletedDoseRecords, current.deletedDoseRecords);
  }

  static Medication _stampDoseRecordChanges({
    required Medication? previous,
    required Medication current,
    required String timestamp,
  }) {
    final versions = Map<String, String>.from(current.doseRecordUpdatedAt);
    final deleted = Map<String, String>.from(current.deletedDoseRecords);
    final previousRecords = previous?.doseRecords ?? const <String, String>{};

    for (final entry in current.doseRecords.entries) {
      if (previousRecords[entry.key] != entry.value ||
          !versions.containsKey(entry.key)) {
        versions[entry.key] = timestamp;
      }
      deleted.remove(entry.key);
    }

    if (previous != null) {
      for (final oldKey in previous.doseRecords.keys) {
        if (!current.doseRecords.containsKey(oldKey)) {
          versions.remove(oldKey);
          deleted[oldKey] = timestamp;
        }
      }
    }

    return current.copyWith(
      doseRecordUpdatedAt: versions,
      deletedDoseRecords: deleted,
    );
  }

  static Future<_MergedMedicationData> _synchronize({required String userId}) {
    final completer = Completer<_MergedMedicationData>();

    _synchronizationQueue = _synchronizationQueue
        .catchError((_) {
          // One failed sync must not prevent later offline changes from
          // retrying when the connection returns.
        })
        .then((_) async {
          try {
            if (currentAccountId != userId) {
              throw StateError("The signed-in account changed during sync.");
            }

            final merged = await _performSynchronization(userId: userId);
            completer.complete(merged);
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });

    return completer.future;
  }

  static Future<_MergedMedicationData> _performSynchronization({
    required String userId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    syncStatus.value = MedicationSyncStatus(
      state: MedicationSyncState.syncing,
      lastSyncedAt: syncStatus.value.lastSyncedAt,
    );

    await AuthService.refreshCloudSession();

    final cloud = await CloudMedicationService.downloadMedications(userId);
    final reconciliation = await _reconcileDownloadedCloudWithLatestLocal(
      userId: userId,
      cloudMedications: cloud.medications,
      cloudTombstones: cloud.tombstones,
    );
    final merged = reconciliation.data;

    await CloudMedicationService.uploadMedicationSet(
      userId: userId,
      medications: merged.medications,
      tombstones: merged.tombstones,
    );
    final changedDuringUpload = dataRevision.value != reconciliation.revision;
    await preferences.setBool(_dirtyKeyForUser(userId), changedDuringUpload);

    if (cloud.containsLegacyData) {
      await CloudMedicationService.deleteLegacyMedicationData(userId);
    }

    final now = DateTime.now();
    syncStatus.value = MedicationSyncStatus(
      state: MedicationSyncState.synced,
      lastSyncedAt: now,
    );
    return changedDuringUpload ? await _loadLatestLocalSnapshot() : merged;
  }

  static Future<_MergedMedicationData> _loadLatestLocalSnapshot() {
    final completer = Completer<_MergedMedicationData>();

    _doseActionQueue = _doseActionQueue.catchError((_) {}).then((_) async {
      try {
        final latestLocal = await _loadLocalForActiveUser();
        completer.complete(
          _MergedMedicationData(
            medications: latestLocal.medications,
            tombstones: latestLocal.tombstones,
          ),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  static Future<({_MergedMedicationData data, int revision})>
  _reconcileDownloadedCloudWithLatestLocal({
    required String userId,
    required List<Medication> cloudMedications,
    required Map<String, String> cloudTombstones,
  }) {
    final completer = Completer<({_MergedMedicationData data, int revision})>();

    // Keep this critical section short: dose taps wait only for a local
    // read/merge/write, never for Firebase network requests.
    _doseActionQueue = _doseActionQueue.catchError((_) {}).then((_) async {
      try {
        final latestLocal = await _loadLocalForActiveUser();
        final merged = _mergeCloudAndLocal(
          localMedications: latestLocal.medications,
          localTombstones: latestLocal.tombstones,
          cloudMedications: cloudMedications,
          cloudTombstones: cloudTombstones,
        );

        await _writeLocalMedicationList(
          key: _storageKeyForUser(userId),
          medications: merged.medications,
        );
        await _writeTombstones(userId, merged.tombstones);
        completer.complete((data: merged, revision: dataRevision.value));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  static _MergedMedicationData _mergeCloudAndLocal({
    required List<Medication> localMedications,
    required Map<String, String> localTombstones,
    required List<Medication> cloudMedications,
    required Map<String, String> cloudTombstones,
  }) {
    final medications = <String, Medication>{};
    final tombstones = <String, String>{};

    for (final medication in [...cloudMedications, ...localMedications]) {
      final normalized = normalizeMedication(medication);
      final current = medications[normalized.id];

      if (current == null) {
        medications[normalized.id] = normalized;
        continue;
      }

      final fieldWinner = _isNewer(normalized.updatedAt, current.updatedAt)
          ? normalized
          : current;
      medications[normalized.id] = _mergeDoseRecordState(
        first: current,
        second: normalized,
        fieldWinner: fieldWinner,
      );
    }

    for (final entry in cloudTombstones.entries) {
      final current = tombstones[entry.key];

      if (current == null || _isNewer(entry.value, current)) {
        tombstones[entry.key] = entry.value;
      }
    }

    for (final entry in localTombstones.entries) {
      final current = tombstones[entry.key];

      if (current == null || _isNewer(entry.value, current)) {
        tombstones[entry.key] = entry.value;
      }
    }

    for (final entry in tombstones.entries.toList()) {
      final medication = medications[entry.key];

      if (medication == null) continue;

      if (_isNewer(entry.value, medication.updatedAt) ||
          entry.value == medication.updatedAt) {
        medications.remove(entry.key);
      } else {
        tombstones.remove(entry.key);
      }
    }

    final sorted = medications.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _MergedMedicationData(medications: sorted, tombstones: tombstones);
  }

  static bool _isNewer(String first, String second) {
    final firstDate = DateTime.tryParse(first);
    final secondDate = DateTime.tryParse(second);

    if (firstDate == null) return false;
    if (secondDate == null) return true;
    return firstDate.isAfter(secondDate);
  }

  static Medication _mergeDoseRecordState({
    required Medication first,
    required Medication second,
    required Medication fieldWinner,
  }) {
    final events = <String, _DoseRecordEvent>{};

    void addMedicationEvents(Medication medication) {
      for (final entry in medication.doseRecords.entries) {
        final event = _DoseRecordEvent(
          updatedAt:
              medication.doseRecordUpdatedAt[entry.key] ?? medication.updatedAt,
          status: entry.value,
          deleted: false,
        );
        final current = events[entry.key];

        if (current == null || !_isNewer(current.updatedAt, event.updatedAt)) {
          events[entry.key] = event;
        }
      }

      for (final entry in medication.deletedDoseRecords.entries) {
        final event = _DoseRecordEvent(
          updatedAt: entry.value,
          status: "",
          deleted: true,
        );
        final current = events[entry.key];

        if (current == null || !_isNewer(current.updatedAt, event.updatedAt)) {
          events[entry.key] = event;
        }
      }
    }

    addMedicationEvents(first);
    addMedicationEvents(second);

    final records = <String, String>{};
    final versions = <String, String>{};
    final deleted = <String, String>{};

    for (final entry in events.entries) {
      if (entry.value.deleted) {
        deleted[entry.key] = entry.value.updatedAt;
      } else {
        records[entry.key] = entry.value.status;
        versions[entry.key] = entry.value.updatedAt;
      }
    }

    final baselineWinner =
        _isNewer(second.inventoryBaselineAt, first.inventoryBaselineAt)
        ? second
        : first;
    final merged = fieldWinner.copyWith(
      doseRecords: records,
      doseRecordUpdatedAt: versions,
      deletedDoseRecords: deleted,
      inventoryBaselineQuantity: baselineWinner.inventoryBaselineQuantity,
      inventoryBaselineAt: baselineWinner.inventoryBaselineAt,
    );
    return _recalculateRemainingQuantity(merged);
  }

  @visibleForTesting
  static Medication mergeMedicationVersionsForTesting({
    required Medication first,
    required Medication second,
  }) {
    final normalizedFirst = normalizeMedication(first);
    final normalizedSecond = normalizeMedication(second);
    final fieldWinner =
        _isNewer(normalizedSecond.updatedAt, normalizedFirst.updatedAt)
        ? normalizedSecond
        : normalizedFirst;
    return _mergeDoseRecordState(
      first: normalizedFirst,
      second: normalizedSecond,
      fieldWinner: fieldWinner,
    );
  }

  static Medication _recalculateRemainingQuantity(Medication medication) {
    final baseline = _parseQuantityNumber(medication.inventoryBaselineQuantity);

    if (baseline <= 0) return medication;

    final baselineAt = medication.inventoryBaselineAt;
    final doseAmount = math
        .max(
          1,
          TimeHelper.getDoseAmountFromInstructions(_doseDirections(medication)),
        )
        .toInt();
    var takenAfterBaseline = 0;

    for (final entry in medication.doseRecords.entries) {
      if (entry.value != "taken") continue;
      final recordUpdatedAt =
          medication.doseRecordUpdatedAt[entry.key] ?? medication.updatedAt;

      if (baselineAt.trim().isEmpty || _isNewer(recordUpdatedAt, baselineAt)) {
        takenAfterBaseline += 1;
      }
    }

    final remaining = math.max(0, baseline - (takenAfterBaseline * doseAmount));
    return medication.copyWith(remainingQuantity: remaining.toString());
  }

  static Future<bool> syncNow() async {
    final userId = currentAccountId;

    if (userId.isEmpty) return false;

    try {
      final merged = await _synchronize(userId: userId);
      await rescheduleAllMedicationNotifications(merged.medications);
      await _announceDataChange();
      unawaited(PillBoxReminderBridge.syncScheduleNow());
      return true;
    } catch (error) {
      final diagnosticMessage = await _diagnoseCloudFailure(error);
      syncStatus.value = MedicationSyncStatus(
        state: MedicationSyncState.error,
        lastSyncedAt: syncStatus.value.lastSyncedAt,
        message: diagnosticMessage,
      );
      return false;
    }
  }

  static Future<String> _diagnoseCloudFailure(Object error) async {
    final details = error.toString();
    final lowerDetails = details.toLowerCase();
    final permissionDenied =
        lowerDetails.contains("permission-denied") ||
        lowerDetails.contains("permission_denied") ||
        lowerDetails.contains("403");

    if (!permissionDenied) {
      return details;
    }

    final appCheckTokenAvailable = await AuthService.checkAppCheckToken();

    if (!appCheckTokenAvailable) {
      return "$details [diagnostic:app-check-token-unavailable]";
    }

    return "$details [diagnostic:firestore-rules-rejected]";
  }

  static String syncFailureMessage({required bool vietnamese}) {
    final details = syncStatus.value.message.toLowerCase();

    if (details.contains("diagnostic:app-check-token-unavailable")) {
      final macFirebaseConfigurationNeedsUpdate =
          defaultTargetPlatform == TargetPlatform.macOS &&
          DefaultFirebaseOptions.macos.iosBundleId !=
              "com.duytruong.medicationreminder.macos";

      if (macFirebaseConfigurationNeedsUpdate) {
        return vietnamese
            ? "Mac này vẫn liên kết với Firebase App ID cũ. Hãy làm theo hướng dẫn ONE_TIME_FIREBASE_SETUP đi kèm để tạo cấu hình cho com.duytruong.medicationreminder.macos, sau đó dựng lại ứng dụng."
            : "This Mac is still linked to Firebase's old app ID. Follow the included ONE_TIME_FIREBASE_SETUP guide to generate the configuration for com.duytruong.medicationreminder.macos, then rebuild the app.";
      }

      return vietnamese
          ? "Firebase App Check đang chặn bản Release này. Trong Firebase Console, tạm để Cloud Firestore ở chế độ không bắt buộc khi thử nghiệm, hoặc đăng ký DeviceCheck cho ứng dụng iPhone."
          : "Firebase App Check is blocking this Release build. In Firebase Console, keep Cloud Firestore unenforced while testing, or register DeviceCheck for the iPhone app.";
    }

    if (details.contains("diagnostic:firestore-rules-rejected")) {
      return vietnamese
          ? "App Check đang hoạt động, nhưng Firestore Rules đã từ chối yêu cầu. Hãy đăng file firestore.rules đi kèm trong Firestore Database > Rules."
          : "App Check is working, but Firestore Rules rejected the request. Publish the included firestore.rules file in Firestore Database > Rules.";
    }

    if (details.contains("appcheck") ||
        details.contains("app_check") ||
        details.contains("app-check") ||
        details.contains("attestation") ||
        details.contains("403")) {
      return vietnamese
          ? "Firebase App Check đã từ chối bản ứng dụng này. Hãy chạy bản Debug và đăng ký debug token hiện tại."
          : "Firebase App Check rejected this build. Run the Debug build and register its current debug token.";
    }

    if (details.contains("permission-denied") ||
        details.contains("permission_denied")) {
      return vietnamese
          ? "Firebase đã chặn quyền truy cập. Hãy đăng Firestore Rules và kiểm tra App Check."
          : "Firebase blocked cloud access. Publish the Firestore Rules and check App Check.";
    }

    if (details.contains("unauthenticated") ||
        details.contains("user-not-found") ||
        details.contains("invalid-user-token") ||
        details.contains("user-token-expired")) {
      return vietnamese
          ? "Phiên đăng nhập đã hết hạn. Hãy đăng xuất rồi đăng nhập lại."
          : "Your sign-in session expired. Sign out, then sign in again.";
    }

    if (details.contains("not-found") && details.contains("firestore")) {
      return vietnamese
          ? "Cloud Firestore chưa được bật cho dự án Firebase này."
          : "Cloud Firestore is not enabled for this Firebase project.";
    }

    if (details.contains("network") ||
        details.contains("unavailable") ||
        details.contains("deadline-exceeded") ||
        details.contains("socket")) {
      return vietnamese
          ? "Không thể kết nối Firebase. Dữ liệu cục bộ vẫn an toàn; hãy kiểm tra mạng rồi thử lại."
          : "Could not reach Firebase. Your local data is safe; check the connection and try again.";
    }

    return vietnamese
        ? "Không thể đồng bộ. Hãy kiểm tra App Check và Firestore Rules rồi thử lại."
        : "Cloud sync failed. Check App Check and Firestore Rules, then try again.";
  }

  static Future<Medication?> applyDoseAction({
    required String medicationId,
    required String recordKey,
    required String status,
  }) {
    if (medicationId.trim().isEmpty || recordKey.trim().isEmpty) {
      return Future<Medication?>.value();
    }

    if (status != "taken" && status != "missed" && status != "skipped") {
      return Future<Medication?>.value();
    }

    final completer = Completer<Medication?>();

    _doseActionQueue = _doseActionQueue
        .catchError((_) {
          // A failed write must not prevent the next dose from being recorded.
        })
        .then((_) async {
          try {
            final medications = await loadCurrentLocalMedications();
            final changed = _applyDoseActionToList(
              medications: medications,
              medicationId: medicationId,
              recordKey: recordKey,
              status: status,
            );

            final medicationIndex = medications.indexWhere(
              (item) => item.id == medicationId,
            );

            if (!changed || medicationIndex < 0) {
              completer.complete(
                medicationIndex < 0 ? null : medications[medicationIndex],
              );
              return;
            }

            await _persistDoseActionList(medications);
            completer.complete(medications[medicationIndex]);
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });

    return completer.future;
  }

  static Future<Medication?> removeDoseAction({
    required String medicationId,
    required String recordKey,
  }) {
    if (medicationId.trim().isEmpty || recordKey.trim().isEmpty) {
      return Future<Medication?>.value();
    }

    final completer = Completer<Medication?>();

    _doseActionQueue = _doseActionQueue
        .catchError((_) {
          // A failed write must not prevent a later undo or dose action.
        })
        .then((_) async {
          try {
            final medications = await loadCurrentLocalMedications();
            final medicationIndex = medications.indexWhere(
              (item) => item.id == medicationId,
            );

            if (medicationIndex < 0) {
              completer.complete();
              return;
            }

            final medication = medications[medicationIndex];

            if (!medication.doseRecords.containsKey(recordKey)) {
              completer.complete(medication);
              return;
            }

            medications[medicationIndex] = removeDoseRecordChange(
              medication: medication,
              recordKey: recordKey,
            );
            await _persistDoseActionList(medications);
            completer.complete(medications[medicationIndex]);
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        });

    return completer.future;
  }

  static Future<void> _persistDoseActionList(
    List<Medication> medications,
  ) async {
    await _writeLocalMedicationList(
      key: _activeStorageKey,
      medications: medications,
    );

    final userId = currentAccountId;

    if (userId.isNotEmpty) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_dirtyKeyForUser(userId), true);
    }

    await _announceDataChange();
    _scheduleDoseActionMaintenance();
  }

  static void _scheduleDoseActionMaintenance() {
    _doseActionMaintenanceTimer?.cancel();
    _doseActionMaintenanceTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_finishDoseActionMaintenance());
    });
  }

  static Future<void> _finishDoseActionMaintenance() async {
    final userId = currentAccountId;
    var latest = await _loadLocalForActiveUser();

    if (userId.isNotEmpty) {
      try {
        final merged = await _synchronize(userId: userId);
        latest = _LocalMedicationLoad(
          medications: merged.medications,
          tombstones: merged.tombstones,
          migratedLegacyData: false,
        );
      } catch (error) {
        final diagnosticMessage = await _diagnoseCloudFailure(error);
        syncStatus.value = MedicationSyncStatus(
          state: MedicationSyncState.offline,
          lastSyncedAt: syncStatus.value.lastSyncedAt,
          message: diagnosticMessage,
        );
      }
    }

    try {
      await rescheduleAllMedicationNotifications(latest.medications);
    } catch (_) {
      // The dose is already stored safely even if notifications cannot update.
    }
  }

  static Future<bool> applyDoseActionFromNotification({
    required String accountId,
    required String medicationId,
    required String recordKey,
    required String status,
  }) async {
    if (medicationId.trim().isEmpty || recordKey.trim().isEmpty) return false;
    if (status != "taken" && status != "missed" && status != "skipped") {
      return false;
    }

    final cleanAccountId = accountId.trim();
    var storageKey = cleanAccountId.isEmpty
        ? _legacyStorageKey
        : _storageKeyForUser(cleanAccountId);
    var medications = _decodeMedicationList(
      await SecureLocalStorage.getString(storageKey),
    );

    // A reminder may have been scheduled before the user finished signing in.
    // If its payload contains an old or empty account id, locate the matching
    // medication in the device's local stores instead of silently doing
    // nothing.
    if (!medications.any((item) => item.id == medicationId)) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final candidateKeys = preferences.getKeys().where((key) {
        return key == _legacyStorageKey ||
            key.startsWith(_userStorageKeyPrefix);
      }).toList();

      for (final candidateKey in candidateKeys) {
        if (candidateKey == storageKey) continue;
        final candidateMedications = _decodeMedicationList(
          await SecureLocalStorage.getString(candidateKey),
        );

        if (candidateMedications.any((item) => item.id == medicationId)) {
          storageKey = candidateKey;
          medications = candidateMedications;
          break;
        }
      }
    }

    final changed = _applyDoseActionToList(
      medications: medications,
      medicationId: medicationId,
      recordKey: recordKey,
      status: status,
    );

    if (!changed) return false;

    await _writeLocalMedicationList(key: storageKey, medications: medications);

    final storageAccountId = storageKey.startsWith(_userStorageKeyPrefix)
        ? storageKey.substring(_userStorageKeyPrefix.length)
        : "";

    if (storageAccountId.isNotEmpty) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_dirtyKeyForUser(storageAccountId), true);
    }

    await _announceDataChange();

    try {
      await NotificationService.scheduleRollingMedicationReminders(
        medications: medications.map(normalizeMedication).toList(),
        accountId: storageAccountId,
      );
    } catch (_) {
      // The dose action is already safely stored even if rescheduling fails.
    }

    return true;
  }

  static bool _applyDoseActionToList({
    required List<Medication> medications,
    required String medicationId,
    required String recordKey,
    required String status,
  }) {
    final index = medications.indexWhere((item) => item.id == medicationId);

    if (index < 0) return false;

    final medication = medications[index];
    final previousStatus = medication.doseRecords[recordKey] ?? "";

    if (previousStatus == status) return false;

    medications[index] = applyDoseRecordChange(
      medication: medication,
      recordKey: recordKey,
      status: status,
    );
    return true;
  }

  static Medication applyDoseRecordChange({
    required Medication medication,
    required String recordKey,
    required String status,
    String? changedAt,
    String? today,
  }) {
    if (recordKey.trim().isEmpty ||
        (status != "taken" && status != "missed" && status != "skipped")) {
      return medication;
    }

    final previousStatus = medication.doseRecords[recordKey] ?? "";

    if (previousStatus == status) {
      return medication;
    }

    final records = Map<String, String>.from(medication.doseRecords);
    records[recordKey] = status;
    final recordVersions = Map<String, String>.from(
      medication.doseRecordUpdatedAt,
    );
    final deletedRecords = Map<String, String>.from(
      medication.deletedDoseRecords,
    );
    final updatedAt = changedAt ?? DateTime.now().toUtc().toIso8601String();
    recordVersions[recordKey] = updatedAt;
    deletedRecords.remove(recordKey);

    final doseAmount = math
        .max(
          1,
          TimeHelper.getDoseAmountFromInstructions(_doseDirections(medication)),
        )
        .toInt();
    final total = _parseQuantityNumber(medication.quantity);
    var remaining = _parseQuantityNumber(
      medication.remainingQuantity.trim().isEmpty
          ? medication.quantity
          : medication.remainingQuantity,
    );

    if (total > 0 && status == "taken" && previousStatus != "taken") {
      remaining = math.max(0, remaining - doseAmount).toInt();
    }

    if (total > 0 && previousStatus == "taken" && status != "taken") {
      remaining = math.min(total, remaining + doseAmount).toInt();
    }

    final todayPrefix = "${today ?? DateHelper.todayString()}|";
    final todayStatuses = records.entries
        .where((entry) => entry.key.startsWith(todayPrefix))
        .map((entry) => entry.value)
        .toList();
    final mainStatus =
        todayStatuses.contains("missed") || todayStatuses.contains("skipped")
        ? "missed"
        : todayStatuses.contains("taken")
        ? "taken"
        : "notTakenYet";

    return medication.copyWith(
      remainingQuantity: total > 0
          ? remaining.toString()
          : medication.remainingQuantity,
      doseRecords: records,
      doseRecordUpdatedAt: recordVersions,
      deletedDoseRecords: deletedRecords,
      doseStatus: mainStatus,
      doseStatusDate: DateHelper.todayString(),
      updatedAt: updatedAt,
    );
  }

  static Medication removeDoseRecordChange({
    required Medication medication,
    required String recordKey,
    String? changedAt,
    String? today,
  }) {
    final previousStatus = medication.doseRecords[recordKey] ?? "";

    if (recordKey.trim().isEmpty || previousStatus.isEmpty) {
      return medication;
    }

    final records = Map<String, String>.from(medication.doseRecords)
      ..remove(recordKey);
    final recordVersions = Map<String, String>.from(
      medication.doseRecordUpdatedAt,
    )..remove(recordKey);
    final deletedRecords = Map<String, String>.from(
      medication.deletedDoseRecords,
    );
    final updatedAt = changedAt ?? DateTime.now().toUtc().toIso8601String();
    deletedRecords[recordKey] = updatedAt;

    final doseAmount = math
        .max(
          1,
          TimeHelper.getDoseAmountFromInstructions(_doseDirections(medication)),
        )
        .toInt();
    final total = _parseQuantityNumber(medication.quantity);
    var remaining = _parseQuantityNumber(
      medication.remainingQuantity.trim().isEmpty
          ? medication.quantity
          : medication.remainingQuantity,
    );

    if (total > 0 && previousStatus == "taken") {
      remaining = math.min(total, remaining + doseAmount).toInt();
    }

    final todayPrefix = "${today ?? DateHelper.todayString()}|";
    final todayStatuses = records.entries
        .where((entry) => entry.key.startsWith(todayPrefix))
        .map((entry) => entry.value)
        .toList();
    final mainStatus =
        todayStatuses.contains("missed") || todayStatuses.contains("skipped")
        ? "missed"
        : todayStatuses.contains("taken")
        ? "taken"
        : "notTakenYet";

    return medication.copyWith(
      remainingQuantity: total > 0
          ? remaining.toString()
          : medication.remainingQuantity,
      doseRecords: records,
      doseRecordUpdatedAt: recordVersions,
      deletedDoseRecords: deletedRecords,
      doseStatus: mainStatus,
      doseStatusDate: DateHelper.todayString(),
      updatedAt: updatedAt,
    );
  }

  static int _parseQuantityNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? 0 : int.tryParse(match.group(0) ?? "") ?? 0;
  }

  static Future<void> prepareForSignOut() async {
    try {
      await NotificationService.cancelAllReminders();
    } catch (_) {
      // Signing out must still work.
    }
  }

  static Future<void> deleteCurrentAccountAndData() async {
    if (AuthService.isGuest) {
      await AuthService.deleteCurrentUser();
      await SecureLocalStorage.remove(_legacyStorageKey);
      await _announceDataChange();
      await prepareForSignOut();
      return;
    }

    final userId = currentAccountId;

    if (userId.isEmpty) return;

    final localMedications = await loadCurrentLocalMedications();
    await CloudMedicationService.deleteMedicationData(userId);

    try {
      await AuthService.deleteCurrentUser();
    } catch (_) {
      try {
        await CloudMedicationService.uploadMedicationSet(
          userId: userId,
          medications: localMedications,
          tombstones: const {},
        );
      } catch (_) {}
      rethrow;
    }

    final preferences = await SharedPreferences.getInstance();
    await SecureLocalStorage.remove(_storageKeyForUser(userId));
    await SecureLocalStorage.remove(_tombstoneKeyForUser(userId));
    await preferences.remove(_dirtyKeyForUser(userId));
    await preferences.remove("account_preferences_snapshot_v1_$userId");
    await _announceDataChange();
    await prepareForSignOut();
  }

  static Future<void> clearMedications() async {
    final current = await _loadLocalForActiveUser();
    final now = DateTime.now().toUtc().toIso8601String();
    final userId = currentAccountId;

    if (userId.isNotEmpty) {
      final tombstones = Map<String, String>.from(current.tombstones);

      for (final medication in current.medications) {
        tombstones[medication.id] = now;
      }

      await _writeLocalMedicationList(
        key: _storageKeyForUser(userId),
        medications: const [],
      );
      await _writeTombstones(userId, tombstones);
      await syncNow();
    } else {
      await SecureLocalStorage.remove(_legacyStorageKey);
    }

    await _announceDataChange();
    await NotificationService.cancelAllReminders();
  }

  static Future<void> refreshNotificationSchedule() async {
    await rescheduleAllMedicationNotifications(
      await loadCurrentLocalMedications(),
    );
  }

  static Future<void> rescheduleAllMedicationNotifications(
    List<Medication> medications,
  ) async {
    try {
      if (!NotificationService.isNotificationSupportedOnThisPlatform) return;
      await NotificationService.initialize();
      await NotificationService.requestPermission();
      await NotificationService.scheduleRollingMedicationReminders(
        medications: medications.map(normalizeMedication).toList(),
        accountId: currentAccountId,
      );
    } catch (_) {
      // Saving data must not fail because notifications are unavailable.
    }
  }

  static bool shouldScheduleNotificationsForMedication(Medication medication) {
    final normalized = normalizeMedication(medication);
    return !isTreatmentFinished(normalized) &&
        (hasFixedReminderTimes(normalized) ||
            NotificationService.isLowQuantityMedication(normalized));
  }

  static bool isTreatmentFinished(Medication medication) {
    final endDate = DateHelper.parseMedicationDate(medication.endDate);
    return endDate != null && DateHelper.isBeforeToday(endDate);
  }

  static bool isTreatmentNotStarted(Medication medication) {
    final startDate = DateHelper.parseMedicationDate(medication.startDate);
    return startDate != null && DateHelper.isAfterToday(startDate);
  }

  static bool hasFixedReminderTimes(Medication medication) {
    if (medication.reminderTimes.isNotEmpty) return true;
    return TimeHelper.generateReminderTimesFromInstructions(
      _scheduleDirections(medication),
    ).isNotEmpty;
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
}
