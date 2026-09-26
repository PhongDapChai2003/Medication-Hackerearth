import 'package:flutter_application_1/cloud_medication_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy medication is not restored when its ID has a tombstone', () {
    expect(
      CloudMedicationService.isLegacyMedicationDeleted(
        'med_deleted',
        const {'med_deleted': '2026-09-26T10:00:00.000Z'},
      ),
      isTrue,
    );
  });

  test('legacy medication without a matching tombstone can migrate', () {
    expect(
      CloudMedicationService.isLegacyMedicationDeleted(
        ' med_active ',
        const {'med_deleted': '2026-09-26T10:00:00.000Z'},
      ),
      isFalse,
    );
  });
}