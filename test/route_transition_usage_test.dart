import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('affected navigation files use only the shared slow route helper', () {
    const paths = <String>[
      'lib/main.dart',
      'lib/medication_list_page.dart',
      'lib/reminder_page.dart',
      'lib/pharmacy_medications_page.dart',
      'lib/scan_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();

      expect(
        source,
        contains('slowPageRoute('),
        reason: '$path must use the shared route transition helper.',
      );
      expect(
        source,
        isNot(contains('MaterialPageRoute')),
        reason: '$path must not bypass the shared transition helper.',
      );
    }
  });
}
