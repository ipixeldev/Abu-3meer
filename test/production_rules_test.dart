import 'package:abu_3meer/production/point_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('production point rules', () {
    test('normal and member exact predictions award 100 and 200', () {
      expect(calculatePoints(basePoints: 100, multiplier: 1), 100);
      expect(
        calculatePoints(
          basePoints: 100,
          multiplier: memberMultiplierForSource(
            source: PointSource.exactPrediction,
            isMember: true,
          ),
        ),
        200,
      );
    });

    test('first scorer uses its independent bonus rule', () {
      expect(PointRuleDefaults.baseFor(PointSource.firstScorer), 20);
      expect(
        calculatePoints(
          basePoints: 20,
          multiplier: memberMultiplierForSource(
            source: PointSource.firstScorer,
            isMember: true,
          ),
        ),
        40,
      );
    });

    test('normal and member video questions award 40 and 80', () {
      expect(calculatePoints(basePoints: 40, multiplier: 1), 40);
      expect(
        calculatePoints(
          basePoints: 40,
          multiplier: memberMultiplierForSource(
            source: PointSource.videoQuestion,
            isMember: true,
          ),
        ),
        80,
      );
    });

    test('Player Cards stay at base points for channel members', () {
      expect(
        calculatePoints(
          basePoints: 20,
          multiplier: memberMultiplierForSource(
            source: PointSource.playerCard,
            isMember: true,
          ),
        ),
        20,
      );
      expect(isMemberMultiplierEligible(PointSource.dailyStreak), isFalse);
      expect(isMemberMultiplierEligible(PointSource.signUpBonus), isFalse);
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
        predictionIsOpen(serverNow: closes, opensAt: opens, closesAt: closes),
        isFalse,
      );
    });
  });
}
