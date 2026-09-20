import 'package:flutter_application_1/pill_box_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('maps the 10 compartments by row then column', () {
    expect(PillBoxSlot.slotCount, 10);
    expect(PillBoxSlot.indexFor(rowIndex: 0, columnIndex: 0), 0);
    expect(PillBoxSlot.indexFor(rowIndex: 0, columnIndex: 4), 4);
    expect(PillBoxSlot.indexFor(rowIndex: 1, columnIndex: 0), 5);
    expect(PillBoxSlot.indexFor(rowIndex: 1, columnIndex: 4), 9);
  });

  test('normalizes an Arduino address', () {
    expect(
      PillBoxService.normalizeAddress('http://192.168.1.50/'),
      '192.168.1.50',
    );
    expect(PillBoxService.normalizeAddress('pillbox.local'), 'pillbox.local');
  });

  test('rejects an empty Arduino address', () {
    expect(() => PillBoxService.normalizeAddress('  '), throwsFormatException);
  });

  test('sends the correct HTTP command for a compartment', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.host, '192.168.4.1');
      expect(request.url.path, '/slot');
      expect(request.url.queryParameters, {'index': '7'});
      return http.Response('{"message":"Slot lit","activeSlot":7}', 200);
    });
    final service = PillBoxService(client: client);

    final response = await service.lightSlot('192.168.4.1', 7);

    expect(response.ok, isTrue);
    expect(response.message, 'Slot lit');
    expect(response.activeSlot, 7);
    service.close();
  });

  test(
    'reports an Arduino HTTP error without treating it as success',
    () async {
      final service = PillBoxService(
        client: MockClient(
          (_) async => http.Response('{"message":"Invalid slot"}', 400),
        ),
      );

      final response = await service.lightSlot('pillbox.local', 2);

      expect(response.ok, isFalse);
      expect(response.message, 'Invalid slot');
      service.close();
    },
  );

  test('reports a network failure with a useful connection message', () async {
    final service = PillBoxService(
      client: MockClient((_) async => throw Exception('network unavailable')),
    );

    final response = await service.turnOff('192.168.4.1');

    expect(response.ok, isFalse);
    expect(response.message, contains('Could not reach the pill box'));
    service.close();
  });

  test('accepts a successful Arduino response with an empty body', () async {
    final service = PillBoxService(
      client: MockClient((_) async => http.Response('', 204)),
    );

    final response = await service.turnOff('192.168.4.1');

    expect(response.ok, isTrue);
    expect(response.message, 'Pill box responded.');
    service.close();
  });
}
