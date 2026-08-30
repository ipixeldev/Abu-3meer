import 'dart:async';

import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2 challenge contracts', () {
    test('legacy challenge kinds map to canonical challenge types', () {
      final now = DateTime.utc(2026, 8, 20);
      final challenge = AbuChallenge(
        id: 'quiz-1',
        kind: 'quiz',
        title: 'Match quiz',
        description: '',
        rewardPoints: 200,
        status: 'open',
        videoUrl: '',
        availableFrom: now.subtract(const Duration(hours: 1)),
        availableUntil: now.add(const Duration(hours: 1)),
        maximumAttempts: 3,
        attemptsUsed: 1,
      );

      expect(challenge.canonicalKind, 'multiQuestion');
      expect(challenge.attemptsRemaining, 2);
    });

    test('public question maps never expose answer keys', () {
      const question = AbuChallengeQuestion(
        id: 'winner',
        prompt: 'Who won?',
        type: 'multipleChoice',
        options: ['Barcelona', 'Real Madrid'],
        correctAnswer: 'Barcelona',
        acceptedAnswers: ['FCB'],
      );

      final public = question.toPublicMap();
      final private = question.toPrivateMap();
      expect(public.containsKey('correctAnswer'), isFalse);
      expect(public.containsKey('acceptedAnswers'), isFalse);
      expect(private['acceptedAnswers'], containsAll(['FCB', 'Barcelona']));
    });
  });

  group('saved prediction states', () {
    test('derives resolved prediction results independently', () {
      final now = DateTime.utc(2026, 8, 20);
      final match = MatchEvent(
        id: 'match-1',
        homeTeam: 'Barcelona',
        awayTeam: 'Real Madrid',
        competition: 'La Liga',
        kickoffAt: now,
        predictionOpensAt: now.subtract(const Duration(days: 2)),
        predictionClosesAt: now.subtract(const Duration(hours: 1)),
        status: 'completed',
        homeScore: 2,
        awayScore: 1,
        firstScorer: 'Lamine Yamal',
      );
      final prediction = SavedPrediction(
        id: 'prediction-1',
        userId: 'user-1',
        matchId: match.id,
        homeScore: 2,
        awayScore: 1,
        firstScorer: 'lamine yamal',
        submittedAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
        rewarded: true,
        pointsAwarded: 500,
        match: match,
      );

      expect(prediction.isPending, isFalse);
      expect(prediction.exactScoreCorrect, isTrue);
      expect(prediction.firstScorerCorrect, isTrue);
      expect(prediction.pointsAwarded, 500);
    });

    test('keeps archived matches resolved when scores are present', () {
      final now = DateTime.utc(2026, 8, 20);
      final prediction = SavedPrediction(
        id: 'prediction-archived',
        userId: 'user-1',
        matchId: 'match-archived',
        homeScore: 1,
        awayScore: 0,
        firstScorer: 'Player',
        submittedAt: now,
        updatedAt: now,
        rewarded: false,
        match: MatchEvent(
          id: 'match-archived',
          homeTeam: 'Home',
          awayTeam: 'Away',
          competition: 'League',
          kickoffAt: now,
          predictionOpensAt: now,
          predictionClosesAt: now,
          status: 'archived',
          homeScore: 1,
          awayScore: 0,
        ),
      );

      expect(prediction.isPending, isFalse);
      expect(prediction.exactScoreCorrect, isTrue);
    });
  });

  group('configurable progression and rewards', () {
    const gatedAchievement = AbuAchievement(
      id: 'elite-predictor',
      title: 'Elite predictor',
      titleAr: 'المتنبئ النخبوي',
      description: '',
      descriptionAr: '',
      iconName: 'emoji_events',
      category: 'predictions',
      requirementType: 'predictions',
      requirementTarget: 10,
      rewardPoints: 500,
      levelUnlock: 'ultra',
      isSecret: false,
      enabled: true,
      sortOrder: 1,
    );

    test('achievement level gate requires the enabled level threshold', () {
      const level = AbuLevel(
        id: 'ultra',
        name: 'Ultra',
        nameAr: 'ألترا',
        minimumPoints: 5000,
      );

      expect(
        gatedAchievement.meetsLevelUnlock(levels: [level], totalPoints: 4999),
        isFalse,
      );
      expect(
        gatedAchievement.meetsLevelUnlock(levels: [level], totalPoints: 5000),
        isTrue,
      );
    });

    test('missing or disabled achievement levels keep the gate closed', () {
      const disabledLevel = AbuLevel(
        id: 'ultra',
        name: 'Ultra',
        nameAr: 'ألترا',
        minimumPoints: 5000,
        enabled: false,
      );

      expect(
        gatedAchievement.meetsLevelUnlock(levels: const [], totalPoints: 10000),
        isFalse,
      );
      expect(
        gatedAchievement.meetsLevelUnlock(
          levels: [disabledLevel],
          totalPoints: 10000,
        ),
        isFalse,
      );
    });

    test('levels include their configured point interval', () {
      const level = AbuLevel(
        id: 'ultra',
        name: 'Ultra',
        nameAr: 'ألترا',
        minimumPoints: 5000,
        maximumPoints: 9999,
      );

      expect(level.containsPoints(4999), isFalse);
      expect(level.containsPoints(5000), isTrue);
      expect(level.containsPoints(9999), isTrue);
      expect(level.containsPoints(10000), isFalse);
    });

    test('unlimited active reward ignores finite stock', () {
      const reward = AbuLoyaltyReward(
        id: 'shoutout',
        title: 'Shoutout',
        titleAr: 'تحية',
        description: '',
        descriptionAr: '',
        imageUrl: '',
        category: 'experience',
        cost: 2500,
        stock: 0,
        unlimitedStock: true,
        memberOnly: false,
        enabled: true,
        startsAt: null,
        endsAt: null,
        fulfilmentType: 'manual',
      );

      expect(reward.isAvailable, isTrue);
    });

    test('football season rolls over on July 1', () {
      expect(footballSeasonId(DateTime.utc(2026, 6, 30)), '2025-2026');
      expect(footballSeasonId(DateTime.utc(2026, 7, 1)), '2026-2027');
    });
  });

  test('scheduled lists re-emit at start and end boundaries', () async {
    final emissions = <List<List<DateTime?>>>[];
    final completed = Completer<void>();
    final base = DateTime.now();
    final subscription =
        refreshAtScheduleBoundaries(
          Stream.value([
            [
              base.add(const Duration(milliseconds: 40)),
              base.add(const Duration(milliseconds: 80)),
            ],
          ]),
          (item) => item,
        ).listen((value) {
          emissions.add(value);
          if (emissions.length == 3 && !completed.isCompleted) {
            completed.complete();
          }
        });

    await completed.future.timeout(const Duration(seconds: 2));
    expect(emissions, hasLength(3));

    await subscription.cancel();
  });
}
