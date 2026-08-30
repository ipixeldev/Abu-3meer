import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';

MatchEvent fixture({
  required String id,
  required String home,
  required String away,
  required DateTime kickoff,
  String providerMatchId = '',
}) => MatchEvent(
  id: id,
  providerMatchId: providerMatchId,
  homeTeam: home,
  awayTeam: away,
  competition: 'La Liga',
  kickoffAt: kickoff,
  predictionOpensAt: kickoff.subtract(const Duration(hours: 24)),
  predictionClosesAt: kickoff,
  status: 'upcoming',
);

void main() {
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
      away: 'Malaga CF',
      kickoff: DateTime.utc(2027, 1, 2, 15),
    );

    expect(sameFootballMatchForMatching(first, later), isFalse);
  });
}
