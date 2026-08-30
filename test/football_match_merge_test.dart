import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';

MatchEvent fixture({
  required String id,
  required String home,
  required String away,
  required DateTime kickoff,
  String providerMatchId = '',
  String status = 'upcoming',
  int? homeScore,
  int? awayScore,
}) => MatchEvent(
  id: id,
  providerMatchId: providerMatchId,
  homeTeam: home,
  awayTeam: away,
  competition: 'La Liga',
  kickoffAt: kickoff,
  predictionOpensAt: kickoff.subtract(const Duration(hours: 24)),
  predictionClosesAt: kickoff,
  status: status,
  homeScore: homeScore,
  awayScore: awayScore,
);

void main() {
  test('match details parse refreshed provider status and final score', () {
    final details = MatchDetails.fromMap({
      'status': 'completed',
      'homeScore': 2,
      'awayScore': 1,
    });

    expect(details.status, 'completed');
    expect(details.homeScore, 2);
    expect(details.awayScore, 1);
  });

  test('provider and managed fixtures merge across accented team names', () {
    final kickoff = DateTime.utc(2026, 8, 30, 15);
    final provider = fixture(
      id: 'external_1570360',
      providerMatchId: 'external_1570360',
      home: 'Real Madrid',
      away: 'Malaga',
      kickoff: kickoff,
    );
    final managed = fixture(
      id: 'managed-match',
      home: 'Real Madrid',
      away: 'Málaga',
      kickoff: kickoff,
    );

    expect(footballTeamKeyForMatching('Málaga'), 'malaga');
    expect(sameFootballMatchForMatching(provider, managed), isTrue);

    final merged = mergeManagedFootballMatch(provider, managed);
    expect(merged.id, 'managed-match');
    expect(merged.providerMatchId, 'external_1570360');
    expect(merged.awayTeam, 'Malaga');
  });

  test('provider outage fallback is provider-only and time bounded', () {
    final now = DateTime.utc(2026, 8, 30, 20);
    final recentProvider = fixture(
      id: 'managed-wrapper',
      providerMatchId: 'external_1',
      home: 'Real Madrid',
      away: 'Malaga',
      kickoff: now.subtract(const Duration(hours: 3)),
    );
    final staleProvider = fixture(
      id: 'external_old',
      home: 'Old Home',
      away: 'Old Away',
      kickoff: now.subtract(const Duration(days: 8)),
    );
    final removedManaged = fixture(
      id: 'managed-only',
      home: 'Managed Home',
      away: 'Managed Away',
      kickoff: now.add(const Duration(days: 1)),
    );

    expect(
      retainedProviderMatchesAfterFetchFailure([
        removedManaged,
        staleProvider,
        recentProvider,
      ], now: now).map((event) => event.id),
      ['managed-wrapper'],
    );
  });

  test('provider identity survives an old external-looking managed id', () {
    final kickoff = DateTime.utc(2026, 8, 30, 15);
    final provider = fixture(
      id: 'external_1570360',
      providerMatchId: 'external_1570360',
      home: 'Real Madrid',
      away: 'Malaga',
      kickoff: kickoff,
    );
    final managed = fixture(
      id: 'external_2506193',
      home: 'Real Madrid',
      away: 'Málaga',
      kickoff: kickoff,
    );

    final merged = mergeManagedFootballMatch(provider, managed);
    expect(merged.id, 'external_2506193');
    expect(merged.providerMatchId, 'external_1570360');
    expect(footballDetailsMatchId(merged), 'external_1570360');
  });

  test('same club pairing at a different kickoff remains a separate match', () {
    final first = fixture(
      id: 'one',
      home: 'Real Madrid',
      away: 'Málaga',
      kickoff: DateTime.utc(2026, 8, 30, 15),
    );
    final later = fixture(
      id: 'two',
      home: 'Real Madrid',
      away: 'Málaga',
      kickoff: DateTime.utc(2027, 1, 2, 15),
    );

    expect(sameFootballMatchForMatching(first, later), isFalse);
  });

  test('matching one team is insufficient to merge unrelated fixtures', () {
    final kickoff = DateTime.utc(2026, 8, 30, 15);
    final first = fixture(
      id: 'one',
      home: 'Real Madrid',
      away: 'Málaga',
      kickoff: kickoff,
    );
    final unrelated = fixture(
      id: 'two',
      home: 'Real Madrid',
      away: 'Valencia',
      kickoff: kickoff,
    );

    expect(sameFootballMatchForMatching(first, unrelated), isFalse);
  });

  test(
    'first scorer ignores missed penalties and uses chronological goals',
    () {
      const timeline = [
        MatchTimelineEvent(minute: '33', type: 'Goal', player: 'Second scorer'),
        MatchTimelineEvent(
          minute: '5',
          type: 'missed_penalty',
          player: 'Missed taker',
        ),
        MatchTimelineEvent(
          minute: '12',
          type: 'penalty_goal',
          player: 'First scorer',
        ),
      ];

      expect(firstScorerFromFootballTimeline(timeline), 'First scorer');
    },
  );

  test(
    'published provider result is not downgraded by stale managed state',
    () {
      final kickoff = DateTime.utc(2026, 8, 30, 15);
      final provider = fixture(
        id: 'external_1570360',
        home: 'Real Madrid',
        away: 'Malaga',
        kickoff: kickoff,
        status: 'completed',
        homeScore: 2,
        awayScore: 1,
      );
      final managed = fixture(
        id: 'managed-match',
        home: 'Real Madrid',
        away: 'Málaga',
        kickoff: kickoff,
        status: 'upcoming',
      );

      final merged = mergeManagedFootballMatch(provider, managed);
      expect(merged.status, 'completed');
      expect(merged.homeScore, 2);
      expect(merged.awayScore, 1);
    },
  );
}
