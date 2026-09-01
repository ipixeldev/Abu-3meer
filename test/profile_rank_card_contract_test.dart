import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fan card and profile summary show month and season rank separately',
    () {
      final cardSource = File('lib/demo/production_features.dart')
          .readAsStringSync();
      final profileSource = File('lib/demo/production_ui.dart')
          .readAsStringSync();

      expect(cardSource, contains("label: 'MONTH RANK'"));
      expect(cardSource, contains("label: 'SEASON RANK'"));
      expect(cardSource, contains('fetchUserRanks(widget.profile)'));
      expect(profileSource, contains("'MONTH RANK', 'ترتيب الشهر'"));
      expect(profileSource, contains("'SEASON RANK', 'ترتيب الموسم'"));
      expect(profileSource, contains('userRanks?.currentMonth'));
      expect(profileSource, contains('userRanks?.season'));
    },
  );
}
