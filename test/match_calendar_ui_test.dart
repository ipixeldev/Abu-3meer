import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:flutter_test/flutter_test.dart';

MatchEvent fixture(String id, DateTime kickoff) => MatchEvent(
  id: id,
  homeTeam: 'Home $id',
  awayTeam: 'Away $id',
  competition: 'League',
  kickoffAt: kickoff,
  predictionOpensAt: kickoff.subtract(const Duration(days: 2)),
  predictionClosesAt: kickoff.subtract(const Duration(minutes: 30)),
  status: 'open',
);

void main() {
  group('inline match calendar', () {
    final now = DateTime(2026, 8, 27, 15);

    test('defaults to today when today contains a match', () {
      final events = [
        fixture('today', DateTime(2026, 8, 27, 21)),
        fixture('tomorrow', DateTime(2026, 8, 28, 18)),
      ];

      expect(initialMatchCalendarDay(events, now: now), DateTime(2026, 8, 27));
    });

    test('defaults to the closest upcoming match day', () {
      final events = [
        fixture('later', DateTime(2026, 8, 31, 21)),
        fixture('next', DateTime(2026, 8, 29, 18)),
      ];

      expect(initialMatchCalendarDay(events, now: now), DateTime(2026, 8, 29));
    });

    test('skips a closed match today for the next actionable day', () {
      final closedToday = fixture('closed-today', DateTime(2026, 8, 27, 14));
      final events = [
        closedToday,
        fixture('tomorrow', DateTime(2026, 8, 28, 18)),
      ];

      expect(initialMatchCalendarDay(events, now: now), DateTime(2026, 8, 28));
    });

    test('filters and orders matches for the selected local day', () {
      final selected = DateTime(2026, 8, 29);
      final events = [
        fixture('late', DateTime(2026, 8, 29, 21)),
        fixture('other', DateTime(2026, 8, 30, 12)),
        fixture('early', DateTime(2026, 8, 29, 15)),
      ];

      expect(matchEventsOnDay(events, selected).map((event) => event.id), [
        'early',
        'late',
      ]);
    });

    test('day window includes nearby match dates and horizontal context', () {
      final events = [fixture('month-end', DateTime(2026, 9, 25, 18))];
      final days = buildMatchCalendarDays(events, now: now);

      expect(days.first, DateTime(2026, 8, 24));
      expect(days, contains(DateTime(2026, 9, 25)));
      expect(days.last, DateTime(2026, 9, 26));
    });

    test(
      'home preview skips a completed result and selects the next fixture',
      () {
        final completed = fixture(
          'completed',
          DateTime(2026, 8, 27, 14),
        ).copyWith(status: 'completed', homeScore: 2, awayScore: 1);
        final later = fixture('later', DateTime(2026, 8, 30, 21));
        final next = fixture('next', DateTime(2026, 8, 28, 18));

        expect(
          nextHomePredictionMatch([completed, later, next], now: now)?.id,
          'next',
        );
      },
    );

    test('home preview is empty when no future match remains', () {
      final completed = fixture(
        'completed',
        DateTime(2026, 8, 27, 14),
      ).copyWith(status: 'finished', homeScore: 2, awayScore: 1);

      expect(nextHomePredictionMatch([completed], now: now), isNull);
    });
  });
}
