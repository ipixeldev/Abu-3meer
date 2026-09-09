import 'package:abu_3meer/production/point_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('production point rules', () {
    test('signup and daily login use fixed, non-member defaults', () {
      expect(PointRuleDefaults.signUpBonus, 50);
      expect(PointRuleDefaults.dailyStreak, 5);
      expect(isMemberMultiplierEligible(PointSource.signUpBonus), isFalse);
      expect(isMemberMultiplierEligible(PointSource.dailyStreak), isFalse);
    });

    test('normal and member exact predictions award 50 and 100', () {
      expect(PointRuleDefaults.exactPrediction, 50);
      expect(calculatePoints(basePoints: 50, multiplier: 1), 50);
      expect(
        calculatePoints(
          basePoints: 50,
          multiplier: memberMultiplierForSource(
            source: PointSource.exactPrediction,
            isMember: true,
          ),
        ),
        100,
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

    test('correct word remains 15 XP for members', () {
      expect(PointRuleDefaults.videoQuestion, 15);
      expect(
        calculatePoints(
          basePoints: PointRuleDefaults.videoQuestion,
          multiplier: memberMultiplierForSource(
            source: PointSource.videoQuestion,
            isMember: true,
          ),
        ),
        15,
      );
    });

    test('correct player remains 15 XP for members', () {
      expect(PointRuleDefaults.playerCard, 15);
      expect(
        calculatePoints(
          basePoints: PointRuleDefaults.playerCard,
          multiplier: memberMultiplierForSource(
            source: PointSource.playerCard,
            isMember: true,
          ),
        ),
        15,
      );
      expect(isMemberMultiplierEligible(PointSource.videoQuestion), isFalse);
      expect(isMemberMultiplierEligible(PointSource.playerCard), isFalse);
      expect(isMemberMultiplierEligible(PointSource.dailyStreak), isFalse);
      expect(isMemberMultiplierEligible(PointSource.signUpBonus), isFalse);
      expect(
        memberMultiplierForSource(
          source: PointSource.dailyStreak,
          isMember: true,
        ),
        1,
      );
      expect(
        memberMultiplierForSource(
          source: PointSource.signUpBonus,
          isMember: true,
        ),
        1,
      );
    });

    test('membership activation and renewal use the published XP values', () {
      expect(PointRuleDefaults.firstMembershipActivation, 150);
      expect(PointRuleDefaults.membershipRenewal, 50);
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
