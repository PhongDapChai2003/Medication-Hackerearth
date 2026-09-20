import 'package:cloud_firestore/cloud_firestore.dart';

class CloudAccountPreferencesSnapshot {
  final bool exists;
  final Map<String, dynamic> values;
  final String updatedAt;

  const CloudAccountPreferencesSnapshot({
    required this.exists,
    this.values = const {},
    this.updatedAt = "",
  });
}

class CloudAccountPreferencesService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _preferencesDocument(
    String userId,
  ) {
    return _firestore
        .collection("users")
        .doc(userId)
        .collection("settings")
        .doc("preferences");
  }

  static Stream<String> watchChanges(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return Stream<String>.value("");
    }

    return _preferencesDocument(cleanUserId).snapshots().map((snapshot) {
      if (!snapshot.exists) return "missing";
      return snapshot.data()?["updatedAt"]?.toString() ?? "present";
    }).distinct();
  }

  static Future<CloudAccountPreferencesSnapshot> download(String userId) async {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return const CloudAccountPreferencesSnapshot(exists: false);
    }

    final document = await _preferencesDocument(cleanUserId).get();
    final data = document.data();
    final rawValues = data?["values"];

    return CloudAccountPreferencesSnapshot(
      exists: document.exists,
      values: rawValues is Map
          ? Map<String, dynamic>.from(rawValues)
          : const {},
      updatedAt: data?["updatedAt"]?.toString() ?? "",
    );
  }

  static Future<void> upload({
    required String userId,
    required Map<String, dynamic> values,
    required String updatedAt,
  }) async {
    final cleanUserId = userId.trim();
    final cleanUpdatedAt = updatedAt.trim();

    if (cleanUserId.isEmpty || cleanUpdatedAt.isEmpty) return;

    final document = _preferencesDocument(cleanUserId);
    await _firestore.runTransaction<void>((transaction) async {
      final current = await transaction.get(document);
      final remoteUpdatedAt = current.data()?["updatedAt"]?.toString() ?? "";

      if (_isNewer(remoteUpdatedAt, cleanUpdatedAt) ||
          remoteUpdatedAt == cleanUpdatedAt) {
        return;
      }

      transaction.set(document, {
        "ownerUid": cleanUserId,
        "schemaVersion": 1,
        "values": Map<String, dynamic>.from(values),
        "updatedAt": cleanUpdatedAt,
        "serverUpdatedAt": FieldValue.serverTimestamp(),
      });
    });
  }

  static bool _isNewer(String first, String second) {
    final firstDate = DateTime.tryParse(first);
    final secondDate = DateTime.tryParse(second);

    if (firstDate == null) return false;
    if (secondDate == null) return true;
    return firstDate.isAfter(secondDate);
  }
}
