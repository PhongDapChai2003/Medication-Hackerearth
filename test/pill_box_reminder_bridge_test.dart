import 'package:flutter_application_1/medication.dart';
import 'package:flutter_application_1/pill_box_reminder_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

Medication medication({
  required String id,
  required int slot,
  required List<String> times,
  String startDate = '',
  String endDate = '',
}) {
  return Medication(
    id: id,
    name: id,
    dosage: '1 tablet',
    instructions: 'Take as directed',
    reminderTimes: times,
    pillBoxSlot: slot,
    startDate: startDate,
    endDate: endDate,
  );
}

void main() {
  test('builds sorted Arduino events from assigned medication reminders', () {
    final entries = PillBoxReminderBridge.buildScheduleEntries([
      medication(id: 'evening', slot: 4, times: ['20:30']),
      medication(id: 'morning', slot: 1, times: ['08:15', '12:00']),
    ], DateTime(2026, 9, 22, 7));

    expect(
      entries.map((entry) => '${entry.slot}:${entry.minuteOfDay}').toList(),
      ['1:495', '1:720', '4:1230'],
    );
  });

  test('ignores unassigned, expired, and duplicate reminder events', () {
    final entries = PillBoxReminderBridge.buildScheduleEntries([
      medication(id: 'unassigned', slot: -1, times: ['08:00']),
      medication(
        id: 'expired',
        slot: 2,
        times: ['09:00'],
        endDate: '2026-09-21',
      ),
      medication(id: 'first', slot: 3, times: ['10:00', '10:00']),
      medication(id: 'duplicate', slot: 3, times: ['10:00']),
    ], DateTime(2026, 9, 22, 7));

    expect(entries, hasLength(1));
    expect(entries.single.slot, 3);
    expect(entries.single.minuteOfDay, 600);
  });
}
