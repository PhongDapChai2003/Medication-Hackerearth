import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class PillBoxSlot {
  const PillBoxSlot._();

  static const int rowCount = 2;
  static const int columnCount = 5;
  static const int slotCount = 7;

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

typedef PillBoxCommandSender = Future<PillBoxResponse> Function(String command);

class PillBoxService {
  PillBoxService({this.commandSender});

  static final _PillBoxBleConnection _connection = _PillBoxBleConnection();
  static const int maxScheduleEntries = 28;
  final PillBoxCommandSender? commandSender;

  bool get isConnected => _connection.isConnected;

  Future<PillBoxResponse> connect() {
    if (commandSender != null) return commandSender!('STATUS');
    return _connection.connect();
  }

  Future<PillBoxResponse> disconnect() async {
    if (commandSender == null) await _connection.disconnect();
    return const PillBoxResponse(ok: true, message: 'Pill box disconnected.');
  }

  Future<PillBoxResponse> testConnection() => _send('STATUS');

  Future<PillBoxResponse> lightSlot(int slot) {
    if (slot < 0 || slot >= PillBoxSlot.slotCount) {
      throw RangeError.range(slot, 0, PillBoxSlot.slotCount - 1, 'slot');
    }
    return _send('SLOT,$slot');
  }

  Future<PillBoxResponse> turnOff() => _send('OFF');

  Future<PillBoxResponse> clearSchedule() => _send('SCHEDULE_CLEAR');

  Future<PillBoxResponse> addSchedule({
    required int slot,
    required int minuteOfDay,
  }) {
    if (slot < 0 || slot >= PillBoxSlot.slotCount) {
      throw RangeError.range(slot, 0, PillBoxSlot.slotCount - 1, 'slot');
    }
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw RangeError.range(minuteOfDay, 0, (24 * 60) - 1, 'minuteOfDay');
    }
    return _send('SCHEDULE_ADD,$slot,$minuteOfDay');
  }

  Future<PillBoxResponse> synchronizeClock(DateTime localTime) {
    final secondsOfDay =
        (localTime.hour * 60 * 60) + (localTime.minute * 60) + localTime.second;
    return _send('CLOCK,$secondsOfDay');
  }

  Future<PillBoxResponse> _send(String command) {
    return commandSender?.call(command) ?? _connection.send(command);
  }

  // The BLE link is shared so background reminder checks can reuse it.
  void close() {}
}

class _PillBoxBleConnection {
  static final Uuid serviceUuid = Uuid.parse(
    '7b9a0001-9f6b-4c2a-8b8f-6d0c0a000001',
  );
  static final Uuid commandUuid = Uuid.parse(
    '7b9a0002-9f6b-4c2a-8b8f-6d0c0a000001',
  );
  static final Uuid responseUuid = Uuid.parse(
    '7b9a0003-9f6b-4c2a-8b8f-6d0c0a000001',
  );

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  Future<PillBoxResponse>? _connecting;
  Future<void> _commandTail = Future<void>.value();
  String? _deviceId;
  bool _connected = false;
  int _requestId = 0;

  bool get isConnected => _connected;

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<PillBoxResponse> connect() {
    if (_connected && _deviceId != null) {
      return Future.value(
        const PillBoxResponse(ok: true, message: 'Pill box connected.'),
      );
    }
    return _connecting ??= _connectInternal().whenComplete(() {
      _connecting = null;
    });
  }

  Future<PillBoxResponse> _connectInternal() async {
    if (!_isSupportedPlatform) {
      return const PillBoxResponse(
        ok: false,
        message:
            'Bluetooth pill-box connection is available on iPhone and Android.',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final permissions = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (permissions.values.any((status) => !status.isGranted)) {
        return const PillBoxResponse(
          ok: false,
          message: 'Allow Nearby devices permission, then try again.',
        );
      }
    }

    try {
      await _ble.statusStream
          .firstWhere((status) => status == BleStatus.ready)
          .timeout(const Duration(seconds: 8));
      final device = await _ble
          .scanForDevices(
            withServices: <Uuid>[serviceUuid],
            scanMode: ScanMode.lowLatency,
          )
          .first
          .timeout(const Duration(seconds: 10));

      final connected = Completer<void>();
      await _connectionSubscription?.cancel();
      _connectionSubscription = _ble
          .connectToDevice(
            id: device.id,
            servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{
              serviceUuid: <Uuid>[commandUuid, responseUuid],
            },
            connectionTimeout: const Duration(seconds: 8),
          )
          .listen(
            (update) {
              if (update.connectionState == DeviceConnectionState.connected) {
                _deviceId = device.id;
                _connected = true;
                if (!connected.isCompleted) connected.complete();
              } else if (update.connectionState ==
                  DeviceConnectionState.disconnected) {
                _connected = false;
                _deviceId = null;
              }
            },
            onError: (Object error) {
              _connected = false;
              _deviceId = null;
              if (!connected.isCompleted) connected.completeError(error);
            },
          );
      await connected.future.timeout(const Duration(seconds: 10));
      return const PillBoxResponse(ok: true, message: 'Pill box connected.');
    } on TimeoutException {
      return const PillBoxResponse(
        ok: false,
        message: 'Pill box not found. Keep it powered and close to the phone.',
      );
    } catch (_) {
      return const PillBoxResponse(
        ok: false,
        message:
            'Could not connect by Bluetooth. Check Bluetooth permission and power.',
      );
    }
  }

  Future<PillBoxResponse> send(String command) {
    final completer = Completer<PillBoxResponse>();
    _commandTail = _commandTail.then((_) async {
      try {
        completer.complete(await _sendNow(command));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<PillBoxResponse> _sendNow(String command) async {
    final connection = await connect();
    if (!connection.ok || _deviceId == null) return connection;

    final requestId = ++_requestId;
    final commandCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: commandUuid,
      deviceId: _deviceId!,
    );
    final responseCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: responseUuid,
      deviceId: _deviceId!,
    );

    try {
      await _ble.writeCharacteristicWithResponse(
        commandCharacteristic,
        value: utf8.encode('$requestId|$command'),
      );
      final prefix = '$requestId|';
      for (var attempt = 0; attempt < 12; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 35));
        final bytes = await _ble.readCharacteristic(responseCharacteristic);
        final response = utf8.decode(bytes, allowMalformed: true);
        if (!response.startsWith(prefix)) continue;
        return _decodeResponse(response.substring(prefix.length));
      }
      return const PillBoxResponse(
        ok: false,
        message: 'The pill box did not answer. Try again.',
      );
    } catch (_) {
      _connected = false;
      return const PillBoxResponse(
        ok: false,
        message: 'Bluetooth connection was lost. Move closer and reconnect.',
      );
    }
  }

  PillBoxResponse _decodeResponse(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return PillBoxResponse(
        ok: decoded['ok'] == true,
        message: decoded['message']?.toString() ?? 'Pill box responded.',
        activeSlot: decoded['activeSlot'] is int
            ? decoded['activeSlot'] as int
            : null,
      );
    } catch (_) {
      return const PillBoxResponse(
        ok: false,
        message: 'The pill box sent an invalid response.',
      );
    }
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connected = false;
    _deviceId = null;
  }
}
