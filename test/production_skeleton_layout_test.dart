import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact production skeleton fits its 96px loading slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: productionSkeletonForTesting(96),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 900));

    expect(tester.takeException(), isNull);
  });
}
