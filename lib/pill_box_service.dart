import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PillBoxSlot {
  const PillBoxSlot._();

  static const int rowCount = 2;
  static const int columnCount = 5;
  static const int slotCount = rowCount * columnCount;

  static int indexFor({required int rowIndex, required int columnIndex}) {
    if (rowIndex < 0 || rowIndex >= rowCount) {
      throw RangeError.range(rowIndex, 0, rowCount - 1, 'rowIndex');
    }
    if (columnIndex < 0 || columnIndex >= columnCount) {
      throw RangeError.range(columnIndex, 0, columnCount - 1, 'columnIndex');
    }
    return (rowIndex * columnCount) + columnIndex;
  }
}

class PillBoxResponse {
  const PillBoxResponse({
    required this.ok,
    required this.message,
    this.activeSlot,
  });

  final bool ok;
  final String message;
  final int? activeSlot;
}

class PillBoxService {
  PillBoxService({http.Client? client}) : _client = client ?? http.Client();

  static const String _addressKey = 'pill_box_device_address_v1';
  static const String defaultAddress = '192.168.4.1';
  final http.Client _client;

  static Future<String> loadAddress() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_addressKey) ?? defaultAddress;
  }

  static Future<void> saveAddress(String address) async {
    final normalized = normalizeAddress(address);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_addressKey, normalized);
  }

  static String normalizeAddress(String address) {
    var value = address.trim();
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    value = value.replaceFirst(RegExp(r'^https?://'), '');

    final parsed = Uri.tryParse('http://$value');
    if (value.isEmpty || parsed == null || parsed.host.isEmpty) {
      throw const FormatException('Enter the IP address shown by Arduino.');
    }
    return value;
  }

  Future<PillBoxResponse> testConnection(String address) {
    return _send(address, '/status');
  }

  Future<PillBoxResponse> lightSlot(String address, int slot) {
    if (slot < 0 || slot >= PillBoxSlot.slotCount) {
      throw RangeError.range(slot, 0, PillBoxSlot.slotCount - 1, 'slot');
    }
    return _send(address, '/slot', query: {'index': '$slot'});
  }

  Future<PillBoxResponse> turnOff(String address) {
    return _send(address, '/off');
  }

  Future<PillBoxResponse> _send(
    String address,
    String path, {
    Map<String, String>? query,
  }) async {
    final host = normalizeAddress(address);
    final base = Uri.parse('http://$host$path');
    final uri = query == null ? base : base.replace(queryParameters: query);

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      Map<String, dynamic> map = <String, dynamic>{};
      try {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          map = data;
        }
      } on FormatException {
        // Some Arduino sketches respond with plain text or an empty body.
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return PillBoxResponse(
        ok: ok,
        message:
            map['message']?.toString() ??
            (ok ? 'Pill box responded.' : 'Pill box returned an error.'),
        activeSlot: map['activeSlot'] is int ? map['activeSlot'] as int : null,
      );
    } catch (_) {
      return const PillBoxResponse(
        ok: false,
        message:
            'Could not reach the pill box. Check the IP address and Wi-Fi.',
      );
    }
  }

  void close() {
    _client.close();
  }
}
