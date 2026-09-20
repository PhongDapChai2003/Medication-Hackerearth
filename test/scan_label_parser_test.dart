import 'package:flutter_application_1/scan_page.dart';
import 'package:flutter_application_1/rxnorm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quantity parser accepts common prescription label formats', () {
    expect(extractLabelQuantity(<String>['QTY: 30']), '30');
    expect(extractLabelQuantity(<String>['Qty. #90 tablets']), '90');
    expect(extractLabelQuantity(<String>['QUANTITY 120']), '120');
    expect(extractLabelQuantity(<String>['Q T Y 45']), '45');
  });

  test(
    'quantity parser repairs narrow OCR mistakes only after a Qty label',
    () {
      expect(extractLabelQuantity(<String>['OTY 3O']), '30');
      expect(extractLabelQuantity(<String>['QTY 6O']), '60');
      expect(extractLabelQuantity(<String>['QTY l5']), '15');
      expect(extractLabelQuantity(<String>['ONE TABLET 30TY']), '30');
      expect(extractLabelQuantity(<String>['RX 123456']), isEmpty);
    },
  );

  test('provider address parser joins a street with city, state, and ZIP', () {
    expect(
      extractLabelProviderAddress(<String>[
        '1002 N. Fairview St',
        'Santa Ana, CA 92703',
        '(714) 881-0012',
      ]),
      '1002 N. Fairview St, Santa Ana, CA 92703',
    );
  });

  test('administrative label text is not kept as dose directions', () {
    expect(
      isAdministrativePrescriptionLine('30TY REMAIN FO 7037TCOO613'),
      isTrue,
    );
    expect(
      stripAdministrativePrescriptionText(
        'UỐNG 1 VIÊN MỖI TỐI 30TY REMAIN FO 7037TCOO613',
      ),
      'UỐNG 1 VIÊN MỖI TỐI',
    );
  });

  test('conservative on-device correction repairs a close OCR drug name', () {
    expect(
      RxNormService.correctLikelyOcrMedicationName('ROSUVASTATING'),
      'Rosuvastatin',
    );
    expect(
      RxNormService.correctLikelyOcrMedicationName('Unlisted Medicine'),
      'Unlisted Medicine',
    );
  });
}
