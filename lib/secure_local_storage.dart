import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureLocalStorage {
  static const String _masterKeyName =
      "medication_reminder_local_encryption_key_v1";
  static const String _encryptedPrefix = "encrypted:v1:";
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final AesGcm _algorithm = AesGcm.with256bits();
  static Future<SecretKey>? _masterKeyFuture;

  static Future<String?> getString(String key) async {
    final preferences = await SharedPreferences.getInstance();
    // Notification actions run in a separate Dart isolate on iPhone. Reload
    // the shared preferences cache so the visible app can immediately read a
    // Taken or Missed update written by that background isolate.
    await preferences.reload();
    final savedValue = preferences.getString(key);

    if (savedValue == null || savedValue.isEmpty) {
      return savedValue;
    }

    if (!savedValue.startsWith(_encryptedPrefix)) {
      // Legacy plaintext is readable once and encrypted on the next write.
      return savedValue;
    }

    final payloadText = savedValue.substring(_encryptedPrefix.length);
    final payload = jsonDecode(payloadText);

    if (payload is! Map) {
      throw const FormatException("Invalid encrypted local data.");
    }

    final secretKey = await _loadOrCreateMasterKey();
    final secretBox = SecretBox(
      base64Decode(payload["cipherText"].toString()),
      nonce: base64Decode(payload["nonce"].toString()),
      mac: Mac(base64Decode(payload["mac"].toString())),
    );
    final clearBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(clearBytes);
  }

  static Future<void> setString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final secretKey = await _loadOrCreateMasterKey();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: secretKey,
    );
    final payload = jsonEncode({
      "cipherText": base64Encode(secretBox.cipherText),
      "nonce": base64Encode(secretBox.nonce),
      "mac": base64Encode(secretBox.mac.bytes),
    });

    await preferences.setString(key, "$_encryptedPrefix$payload");
  }

  static Future<void> remove(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }

  static Future<SecretKey> _loadOrCreateMasterKey() async {
    final existingFuture = _masterKeyFuture;

    if (existingFuture != null) {
      return existingFuture;
    }

    final newFuture = _readOrCreateMasterKey();
    _masterKeyFuture = newFuture;

    try {
      return await newFuture;
    } catch (_) {
      if (identical(_masterKeyFuture, newFuture)) {
        _masterKeyFuture = null;
      }
      rethrow;
    }
  }

  static Future<SecretKey> _readOrCreateMasterKey() async {
    final savedKey = await _secureStorage.read(key: _masterKeyName);

    if (savedKey != null && savedKey.trim().isNotEmpty) {
      final keyBytes = base64Decode(savedKey);

      if (keyBytes.length != 32) {
        throw const FormatException("Invalid local encryption key.");
      }

      return SecretKey(keyBytes);
    }

    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _secureStorage.write(
      key: _masterKeyName,
      value: base64Encode(keyBytes),
    );

    return SecretKey(keyBytes);
  }
}
