import 'package:abu_3meer/production/point_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('production point rules', () {
    test('normal and member exact predictions award 100 and 200', () {
      expect(calculatePoints(basePoints: 100, multiplier: 1), 100);
      expect(calculatePoints(basePoints: 100, multiplier: 2), 200);
    });

    test('normal and member video questions award 40 and 80', () {
      expect(calculatePoints(basePoints: 40, multiplier: 1), 40);
      expect(calculatePoints(basePoints: 40, multiplier: 2), 80);
    });

    test('normal and member Player Cards award 20 and 40', () {
      expect(calculatePoints(basePoints: 20, multiplier: 1), 20);
      expect(calculatePoints(basePoints: 20, multiplier: 2), 40);
    });

    test('negative point inputs are rejected', () {
      expect(
        () => calculatePoints(basePoints: -1, multiplier: 1),
        throwsArgumentError,
      );
      expect(
        () => calculatePoints(basePoints: 20, multiplier: -1),
        throwsArgumentError,
      );
    });
  });

  group('idempotency keys', () {
    test('the same source and user always produce the same ledger ID', () {
      final first = rewardLedgerId(
        source: PointSource.exactPrediction,
        sourceId: 'match-1',
        userId: 'user-1',
      );
      final second = rewardLedgerId(
        source: PointSource.exactPrediction,
        sourceId: 'match-1',
        userId: 'user-1',
      );
      expect(first, second);
    });
  });

  group('prediction deadlines', () {
    final opens = DateTime.utc(2026, 8, 20, 18);
    final closes = DateTime.utc(2026, 8, 20, 20);

    test('submission before the server deadline succeeds', () {
      expect(
        predictionIsOpen(
          serverNow: DateTime.utc(2026, 8, 20, 19),
          opensAt: opens,
          closesAt: closes,
        ),
        isTrue,
      );
    });

    test('submission at or after the server deadline fails', () {
      expect(
        predictionIsOpen(
          serverNow: closes,
          opensAt: opens,
          closesAt: closes,
        ),
        isFalse,
      );
    });
  });
}
