import 'package:flutter_test/flutter_test.dart';

import 'package:abu_3meer/production/models.dart';

void main() {
  group('leaderboard previous-month availability', () {
    const activeId = '2026-2027';
    final seasons = <LeaderboardSeason>[
      LeaderboardSeason(
        id: activeId,
        displayName: '2026/27 Season',
        startsAt: DateTime.utc(2026, 8, 30, 15),
        active: true,
      ),
    ];

    test('stays hidden for one full calendar-month interval', () {
      expect(
        leaderboardPreviousMonthAvailable(
          seasons: seasons,
          activeSeasonId: activeId,
          now: DateTime.utc(2026, 9, 29, 23, 59),
        ),
        isFalse,
      );
      expect(
        leaderboardPreviousMonthAvailable(
          seasons: seasons,
          activeSeasonId: activeId,
          now: DateTime.utc(2026, 9, 30, 14, 59, 59),
        ),
        isFalse,
      );
      expect(
        leaderboardPreviousMonthAvailable(
          seasons: seasons,
          activeSeasonId: activeId,
          now: DateTime.utc(2026, 9, 30, 15),
        ),
        isTrue,
      );
    });

    test('calendar-month addition clamps short months in UTC', () {
      expect(
        leaderboardSeasonFirstMonthEndsAt(DateTime.utc(2027, 1, 31, 20)),
        DateTime.utc(2027, 2, 28, 20),
      );
      expect(
        leaderboardSeasonFirstMonthEndsAt(DateTime.utc(2028, 1, 31, 20)),
        DateTime.utc(2028, 2, 29, 20),
      );
      expect(
        leaderboardSeasonFirstMonthEndsAt(DateTime.utc(2028, 12, 31, 20)),
        DateTime.utc(2029, 1, 31, 20),
      );
    });

    test('uses active metadata and degrades safely when it is absent', () {
      expect(
        leaderboardPreviousMonthAvailable(
          seasons: seasons,
          activeSeasonId: 'missing',
          now: DateTime.utc(2026, 8, 31),
        ),
        isFalse,
      );
      expect(
        leaderboardPreviousMonthAvailable(
          seasons: const <LeaderboardSeason>[],
          activeSeasonId: null,
          now: DateTime.utc(2026, 8, 31),
        ),
        isTrue,
      );
    });

    test('parses season management metadata from the API', () {
      final season = LeaderboardSeason.fromMap(<String, dynamic>{
        'id': '2026-2027',
        'displayName': '2026/27 Season',
        'management_mode': 'manual',
        'updated_at': '2026-09-01T08:30:00Z',
      });

      expect(season.managementMode, 'manual');
      expect(season.updatedAt, DateTime.utc(2026, 9, 1, 8, 30));
    });
  });
}
