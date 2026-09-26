import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'medication.dart';

class CloudMedicationSnapshot {
  final bool exists;
  final List<Medication> medications;
  final Map<String, String> tombstones;
  final bool containsLegacyData;

  const CloudMedicationSnapshot({
    required this.exists,
    required this.medications,
    this.tombstones = const {},
    this.containsLegacyData = false,
  });
}

class CloudMedicationService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _medicationsCollection(
    String userId,
  ) {
    return _firestore.collection("users").doc(userId).collection("medications");
  }

  static DocumentReference<Map<String, dynamic>> _legacyDocument(
    String userId,
  ) {
    return _firestore
        .collection("users")
        .doc(userId)
        .collection("private")
        .doc("medications");
  }

  static Stream<String> watchMedicationChanges(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return Stream<String>.value("");
    }

    return _medicationsCollection(cleanUserId).snapshots().map((snapshot) {
      final versions = snapshot.docs.map((document) {
        final data = document.data();
        final updatedAt = data["updatedAt"]?.toString() ?? "";
        final deleted = data["deleted"] == true ? "1" : "0";
        return "${document.id}|$updatedAt|$deleted";
      }).toList()..sort();

      // serverUpdatedAt is deliberately excluded. Uploading an unchanged
      // medication can refresh that server timestamp, but it must not create
      // an endless listen -> upload -> listen loop.
      return versions.join("\n");
    }).distinct();
  }

  static Future<CloudMedicationSnapshot> downloadMedications(
    String userId,
  ) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return const CloudMedicationSnapshot(exists: false, medications: []);
    }

    final query = await _medicationsCollection(cleanUserId).get();

    final medications = <Medication>[];
    final tombstones = <String, String>{};

    for (final document in query.docs) {
      final data = document.data();
      final updatedAt = data["updatedAt"]?.toString() ?? "";

      if (data["deleted"] == true) {
        tombstones[document.id] = updatedAt;
        continue;
      }

      final doseQuery = await document.reference
          .collection("doseRecords")
          .get();
      final records = <String, String>{};
      final recordVersions = <String, String>{};
      final deletedRecords = <String, String>{};

      for (final recordDocument in doseQuery.docs) {
        final recordData = recordDocument.data();

        final recordKey = recordData["recordKey"]?.toString() ?? "";
        final status = recordData["status"]?.toString() ?? "";
        final recordUpdatedAt =
            recordData["updatedAt"]?.toString() ?? updatedAt;

        if (recordKey.isEmpty) continue;

        if (recordData["deleted"] == true) {
          deletedRecords[recordKey] = recordUpdatedAt;
          continue;
        }

        if (status.isNotEmpty) {
          records[recordKey] = status;
          recordVersions[recordKey] = recordUpdatedAt;
        }
      }

      medications.add(
        Medication.fromJson(data).copyWith(
          id: document.id,
          doseRecords: records,
          doseRecordUpdatedAt: recordVersions,
          deletedDoseRecords: deletedRecords,
          updatedAt: updatedAt,
        ),
      );
    }

    CloudMedicationSnapshot? legacySnapshot;

    try {
      legacySnapshot = await _downloadLegacyMedications(cleanUserId);
    } catch (_) {
      // A finished migration may remove legacy-read access without affecting v2.
    }

    if (legacySnapshot?.exists == true) {
      final existingFingerprints = medications
          .map(_medicationFingerprint)
          .toSet();

      for (final legacyMedication in legacySnapshot!.medications) {
        if (isLegacyMedicationDeleted(
          legacyMedication.id,
          tombstones,
        )) {
          continue;
        }

        final hasMatchingId =
            legacyMedication.id.trim().isNotEmpty &&
            medications.any((item) => item.id == legacyMedication.id);
        final fingerprint = _medicationFingerprint(legacyMedication);

        if (!hasMatchingId && existingFingerprints.contains(fingerprint)) {
          continue;
        }

        medications.add(legacyMedication);
        existingFingerprints.add(fingerprint);
      }
    }

    return CloudMedicationSnapshot(
      exists: query.docs.isNotEmpty || legacySnapshot?.exists == true,
      medications: medications,
      tombstones: tombstones,
      containsLegacyData: legacySnapshot?.containsLegacyData == true,
    );
  }

  @visibleForTesting
  static bool isLegacyMedicationDeleted(
    String medicationId,
    Map<String, String> tombstones,
  ) {
    final id = medicationId.trim();
    return id.isNotEmpty && tombstones.containsKey(id);
  }

  static Future<CloudMedicationSnapshot> _downloadLegacyMedications(
    String userId,
  ) async {
    final document = await _legacyDocument(userId).get();

    if (!document.exists) {
      return const CloudMedicationSnapshot(exists: false, medications: []);
    }

    final data = document.data();
    final rawMedications = data?["medications"];
    final medications = <Medication>[];
    // Legacy records do not carry reliable edit timestamps. Do not stamp them
    // with "now": that makes an old deleted record look newer than its
    // tombstone and causes it to be restored on the next sync.
    const legacyFallbackUpdatedAt = '1970-01-01T00:00:00.000Z';

    if (rawMedications is List) {
      for (final item in rawMedications) {
        if (item is! Map) continue;

        try {
          final medication = Medication.fromJson(
            Map<String, dynamic>.from(item),
          );
          medications.add(
            medication.copyWith(
              updatedAt: medication.updatedAt.trim().isEmpty
                  ? legacyFallbackUpdatedAt
                  : medication.updatedAt,
            ),
          );
        } catch (_) {
          // Ignore one damaged legacy entry.
        }
      }
    }

    return CloudMedicationSnapshot(
      exists: true,
      medications: medications,
      containsLegacyData: true,
    );
  }

  static Future<void> uploadMedicationSet({
    required String userId,
    required List<Medication> medications,
    required Map<String, String> tombstones,
  }) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) return;

    for (final medication in medications) {
      await _uploadMedication(userId: cleanUserId, medication: medication);
    }

    for (final entry in tombstones.entries) {
      await _uploadTombstone(
        userId: cleanUserId,
        medicationId: entry.key,
        updatedAt: entry.value,
      );
    }
  }

  static Future<void> _uploadMedication({
    required String userId,
    required Medication medication,
  }) async {
    final id = medication.id.trim();

    if (id.isEmpty) return;

    final updatedAt = medication.updatedAt.trim().isEmpty
        ? DateTime.now().toUtc().toIso8601String()
        : medication.updatedAt;
    final document = _medicationsCollection(userId).doc(id);
    await _firestore.runTransaction<void>((transaction) async {
      final current = await transaction.get(document);
      final remoteUpdatedAt = current.data()?["updatedAt"]?.toString() ?? "";

      if (_isNewer(remoteUpdatedAt, updatedAt)) {
        return;
      }

      final data = Map<String, dynamic>.from(medication.toJson());
      data.remove("doseRecords");
      data.remove("doseRecordUpdatedAt");
      data.remove("deletedDoseRecords");
      data.addAll({
        "id": id,
        "ownerUid": userId,
        "schemaVersion": 2,
        "deleted": false,
        "updatedAt": updatedAt,
        "serverUpdatedAt": FieldValue.serverTimestamp(),
      });
      transaction.set(document, data);
    });

    final doseCollection = document.collection("doseRecords");

    for (final entry in medication.doseRecords.entries) {
      final recordUpdatedAt =
          medication.doseRecordUpdatedAt[entry.key] ?? updatedAt;
      final recordDocument = doseCollection.doc(_recordDocumentId(entry.key));

      await _firestore.runTransaction<void>((transaction) async {
        final current = await transaction.get(recordDocument);
        final remoteUpdatedAt = current.data()?["updatedAt"]?.toString() ?? "";

        if (_isNewer(remoteUpdatedAt, recordUpdatedAt)) return;

        transaction.set(recordDocument, {
          "ownerUid": userId,
          "schemaVersion": 2,
          "recordKey": entry.key,
          "status": entry.value,
          "deleted": false,
          "updatedAt": recordUpdatedAt,
          "serverUpdatedAt": FieldValue.serverTimestamp(),
        });
      });
    }

    for (final entry in medication.deletedDoseRecords.entries) {
      final recordDocument = doseCollection.doc(_recordDocumentId(entry.key));

      await _firestore.runTransaction<void>((transaction) async {
        final current = await transaction.get(recordDocument);
        final remoteUpdatedAt = current.data()?["updatedAt"]?.toString() ?? "";

        if (_isNewer(remoteUpdatedAt, entry.value)) return;

        transaction.set(recordDocument, {
          "ownerUid": userId,
          "schemaVersion": 2,
          "recordKey": entry.key,
          "deleted": true,
          "updatedAt": entry.value,
          "serverUpdatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    }
  }

  static Future<void> _uploadTombstone({
    required String userId,
    required String medicationId,
    required String updatedAt,
  }) async {
    if (medicationId.trim().isEmpty) return;

    final document = _medicationsCollection(userId).doc(medicationId);

    await _firestore.runTransaction<void>((transaction) async {
      final current = await transaction.get(document);
      final remoteUpdatedAt = current.data()?["updatedAt"]?.toString() ?? "";

      if (_isNewer(remoteUpdatedAt, updatedAt)) return;

      transaction.set(document, {
        "id": medicationId,
        "ownerUid": userId,
        "schemaVersion": 2,
        "deleted": true,
        "updatedAt": updatedAt,
        "serverUpdatedAt": FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> deleteLegacyMedicationData(String userId) async {
    if (userId.trim().isEmpty) return;
    await _legacyDocument(userId.trim()).delete();
  }

  static Future<void> deleteMedicationData(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) return;

    final medications = await _medicationsCollection(cleanUserId).get();

    for (final medication in medications.docs) {
      final records = await medication.reference
          .collection("doseRecords")
          .get();

      for (final record in records.docs) {
        await record.reference.delete();
      }

      await medication.reference.delete();
    }

    await _legacyDocument(cleanUserId).delete();
    await _firestore
        .collection("users")
        .doc(cleanUserId)
        .collection("settings")
        .doc("preferences")
        .delete();
  }

  static String _recordDocumentId(String recordKey) {
    return base64Url.encode(utf8.encode(recordKey)).replaceAll("=", "");
  }

  static String _medicationFingerprint(Medication medication) {
    return [
      medication.name.trim().toLowerCase(),
      medication.dosage.trim().toLowerCase(),
      medication.instructions.trim().toLowerCase(),
      medication.startDate.trim(),
      medication.endDate.trim(),
      medication.pharmacyPhone.trim(),
      medication.reminderTimes.join(","),
    ].join("|");
  }

  static bool _isNewer(String first, String second) {
    final firstDate = DateTime.tryParse(first);
    final secondDate = DateTime.tryParse(second);

    if (firstDate == null) return false;
    if (secondDate == null) return true;

    return firstDate.isAfter(secondDate);
  }
}
