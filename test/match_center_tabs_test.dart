import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/features/match/screens/match_facts_screen.dart';

void main() {
  test('match centre exposes only Facts, Lineup and Table in that order', () {
    expect(matchCenterTabOrder, const <String>['facts', 'lineup', 'table']);
  });
}
