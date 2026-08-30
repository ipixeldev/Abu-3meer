import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/features/match/screens/match_facts_screen.dart';
import 'package:abu_3meer/production/models.dart';

void main() {
  test('shorter live match snapshots cannot retract published sections', () {
    const current = MatchDetails(
      timeline: [
        MatchTimelineEvent(
          minute: '12',
          type: 'goal',
          player: 'First',
          team: 'Home',
        ),
        MatchTimelineEvent(
          minute: '70',
          type: 'goal',
          player: 'Second',
          team: 'Away',
          isHome: false,
        ),
      ],
      lineup: [
        MatchLineupPlayer(
          player: 'Home Starter',
          team: 'Home',
          position: 'Forward',
          isHome: true,
          isSubstitute: false,
        ),
        MatchLineupPlayer(
          player: 'Away Starter',
          team: 'Away',
          position: 'Keeper',
          isHome: false,
          isSubstitute: false,
        ),
      ],
      statistics: [
        MatchStatistic(label: 'Shots', homeValue: '10', awayValue: '4'),
        MatchStatistic(label: 'Possession', homeValue: '60%', awayValue: '40%'),
      ],
      standings: [
        MatchStanding(
          rank: 1,
          team: 'Home',
          played: 3,
          won: 3,
          drawn: 0,
          lost: 0,
          goalDifference: 5,
          points: 9,
          teamId: '1',
        ),
        MatchStanding(
          rank: 2,
          team: 'Away',
          played: 3,
          won: 2,
          drawn: 0,
          lost: 1,
          goalDifference: 2,
          points: 6,
          teamId: '2',
        ),
      ],
      status: 'live',
      homeScore: 1,
      awayScore: 0,
    );
    const shorter = MatchDetails(
      timeline: [
        MatchTimelineEvent(
          minute: '12',
          type: 'goal',
          player: 'First',
          assist: 'Updated assist',
          team: 'Home',
        ),
      ],
      lineup: [
        MatchLineupPlayer(
          player: 'Home Starter',
          team: 'Home',
          position: 'Forward',
          isHome: true,
          isSubstitute: false,
          playerImageUrl: 'https://images.example/player.png',
        ),
      ],
      statistics: [
        MatchStatistic(label: 'Shots', homeValue: '11', awayValue: '4'),
      ],
      standings: [
        MatchStanding(
          rank: 1,
          team: 'Home',
          played: 3,
          won: 3,
          drawn: 0,
          lost: 0,
          goalDifference: 5,
          points: 9,
          teamId: '1',
        ),
      ],
      status: 'live',
      homeScore: 1,
    );

    final retained = retainPublishedMatchDetailSections(current, shorter);

    expect(retained.timeline, hasLength(2));
    expect(retained.timeline.first.assist, 'Updated assist');
    expect(retained.lineup, hasLength(2));
    expect(retained.lineup.first.playerImageUrl, contains('player.png'));
    expect(retained.statistics, hasLength(2));
    expect(retained.statistics.first.homeValue, '11');
    expect(retained.standings, hasLength(2));
    expect(retained.awayScore, 0);
  });
}
