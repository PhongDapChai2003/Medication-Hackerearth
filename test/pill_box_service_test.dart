import 'package:flutter_application_1/pill_box_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches the firmware schedule capacity', () {
    expect(PillBoxService.maxScheduleEntries, 28);
  });

  test('maps the 7 populated compartments by row then column', () {
    expect(PillBoxSlot.slotCount, 7);
    expect(PillBoxSlot.indexFor(rowIndex: 0, columnIndex: 0), 0);
    expect(PillBoxSlot.indexFor(rowIndex: 0, columnIndex: 4), 4);
    expect(PillBoxSlot.indexFor(rowIndex: 1, columnIndex: 0), 5);
    expect(PillBoxSlot.indexFor(rowIndex: 1, columnIndex: 1), 6);
  });

  test('sends the Bluetooth compartment command', () async {
    String? command;
    final service = PillBoxService(
      commandSender: (value) async {
        command = value;
        return const PillBoxResponse(
          ok: true,
          message: 'Slot lit',
          activeSlot: 6,
        );
      },
    );

    final response = await service.lightSlot(6);

    expect(command, 'SLOT,6');
    expect(response.ok, isTrue);
    expect(response.message, 'Slot lit');
    expect(response.activeSlot, 6);
  });

  test(
    'reports a Bluetooth command error without treating it as success',
    () async {
      final service = PillBoxService(
        commandSender: (_) async =>
            const PillBoxResponse(ok: false, message: 'Invalid slot'),
      );

      final response = await service.lightSlot(2);

      expect(response.ok, isFalse);
      expect(response.message, 'Invalid slot');
    },
  );

  test('sends schedule and clock commands to the pill box', () async {
    final commands = <String>[];
    final service = PillBoxService(
      commandSender: (command) async {
        commands.add(command);
        return const PillBoxResponse(ok: true, message: 'OK');
      },
    );

    expect((await service.clearSchedule()).ok, isTrue);
    expect(
      (await service.addSchedule(slot: 3, minuteOfDay: 8 * 60 + 15)).ok,
      isTrue,
    );
    expect(
      (await service.synchronizeClock(DateTime(2026, 9, 22, 8, 5, 30))).ok,
      isTrue,
    );

    expect(commands, <String>[
      'SCHEDULE_CLEAR',
      'SCHEDULE_ADD,3,495',
      'CLOCK,29130',
    ]);
  });

  test('rejects invalid schedule values before sending a command', () {
    final service = PillBoxService(
      commandSender: (_) async {
        fail('The invalid command must not be sent.');
      },
    );

    expect(
      () => service.addSchedule(slot: 7, minuteOfDay: 0),
      throwsRangeError,
    );
    expect(
      () => service.addSchedule(slot: 0, minuteOfDay: 1440),
      throwsRangeError,
    );
  });
}
