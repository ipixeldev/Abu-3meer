import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fan card and profile summary distinguish lifetime, month, and season XP',
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
      expect(profileSource, contains("'LIFETIME XP'"));
      expect(profileSource, contains("'SEASON XP', 'XP الموسم'"));
      expect(profileSource, contains("'XP ranking'"));
      expect(
        profileSource,
        isNot(contains("'XP ranking · no prizes or rewards'")),
      );
      expect(profileSource, contains('userRanks?.currentMonth'));
      expect(profileSource, contains('userRanks?.season'));
    },
  );
}
