import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  discoverFutureLeaderboardSeasons,
  eligibleLeaderboardSourceTypes,
  isTrackedLeaderboardClubName,
  leaderboardSeasonWindowsOverlap,
  utcMonthWindow,
  validateManualLeaderboardSeasonWindow,
} from '../services/leaderboardService.js';

describe('XP-only leaderboard periods', () => {
  it('allows activity, prediction, and video-answer ledger sources', () => {
    assert.deepEqual([...eligibleLeaderboardSourceTypes], [
      'signup_bonus',
      'daily_streak',
      'prediction_exact',
      'prediction_scorer',
      'prediction_winner',
      'prediction_win',
      'video_phrase',
      'player_card',
    ]);

    const excluded = [
      'achievement_bonus',
      'admin_adjustment',
      'loyalty_redemption',
      'prediction_btts',
    ];
    for (const source of excluded) {
      assert.equal(
        (eligibleLeaderboardSourceTypes as readonly string[]).includes(source),
        false,
      );
    }
  });

  it('builds the current month with exact UTC boundaries', () => {
    const period = utcMonthWindow(
      'current_month',
      new Date('2026-08-31T23:59:59.999Z'),
    );

    assert.equal(period.id, '2026-08');
    assert.equal(period.displayName, 'August 2026');
    assert.equal(period.startsAt.toISOString(), '2026-08-01T00:00:00.000Z');
    assert.equal(period.endsAt?.toISOString(), '2026-09-01T00:00:00.000Z');
  });

  it('builds the previous month across a UTC year boundary', () => {
    const period = utcMonthWindow(
      'previous_month',
      new Date('2027-01-15T12:00:00.000Z'),
    );

    assert.equal(period.id, '2026-12');
    assert.equal(period.displayName, 'December 2026');
    assert.equal(period.startsAt.toISOString(), '2026-12-01T00:00:00.000Z');
    assert.equal(period.endsAt?.toISOString(), '2027-01-01T00:00:00.000Z');
  });

  it('rejects an invalid clock value', () => {
    assert.throws(
      () => utcMonthWindow('current_month', new Date(Number.NaN)),
      /invalid/i,
    );
  });

  it('validates explicit season windows and rejects reversed dates', () => {
    const window = validateManualLeaderboardSeasonWindow(
      '2026-08-30T15:00:00.000Z',
      '2027-08-15T19:00:00.000Z',
    );
    assert.equal(window.startsAt.toISOString(), '2026-08-30T15:00:00.000Z');
    assert.equal(window.endsAt.toISOString(), '2027-08-15T19:00:00.000Z');
    assert.throws(
      () => validateManualLeaderboardSeasonWindow(
        '2027-08-15T19:00:00.000Z',
        '2026-08-30T15:00:00.000Z',
      ),
      /start must be before/i,
    );
  });

  it('treats adjacent manual seasons as non-overlapping', () => {
    assert.equal(
      leaderboardSeasonWindowsOverlap(
        '2026-08-30T15:00:00.000Z',
        '2027-08-15T19:00:00.000Z',
        '2027-08-15T19:00:00.000Z',
        '2028-08-20T19:00:00.000Z',
      ),
      false,
    );
    assert.equal(
      leaderboardSeasonWindowsOverlap(
        '2026-08-30T15:00:00.000Z',
        '2027-08-16T19:00:00.000Z',
        '2027-08-15T19:00:00.000Z',
        '2028-08-20T19:00:00.000Z',
      ),
      true,
    );
  });

  it('recognizes provider variants without matching similarly named clubs', () => {
    assert.equal(isTrackedLeaderboardClubName('Real Madrid C.F.'), true);
    assert.equal(isTrackedLeaderboardClubName('FC Barcelona'), true);
    assert.equal(isTrackedLeaderboardClubName('Fútbol Club Barcelona'), true);
    assert.equal(isTrackedLeaderboardClubName('Real Madrid Castilla'), false);
    assert.equal(isTrackedLeaderboardClubName('Barcelona SC'), false);
  });

  it('discovers each future season from its first valid tracked-club match', () => {
    const discovered = discoverFutureLeaderboardSeasons([
      {
        // The fixed 2026/27 period is never recreated from football metadata.
        seasonId: '2026-2027-provider',
        seasonName: '2026/27 Provider Season',
        seasonStartsAt: '2026-07-01T00:00:00Z',
        kickoffAt: '2026-08-31T19:00:00Z',
        status: 'finished',
        homeTeam: 'Barcelona',
        awayTeam: 'Rayo Vallecano',
      },
      {
        seasonId: '2027-2028',
        seasonName: '2027/28 Season',
        seasonStartsAt: '2027-07-01T00:00:00Z',
        kickoffAt: '2027-08-12T18:00:00Z',
        status: 'cancelled',
        homeTeam: 'Real Madrid',
        awayTeam: 'Getafe',
      },
      {
        seasonId: '2027-2028',
        seasonName: '2027/28 Season',
        seasonStartsAt: '2027-07-01T00:00:00Z',
        kickoffAt: '2027-08-13T18:00:00Z',
        status: 'postponed',
        homeTeam: 'Real Madrid',
        awayTeam: 'Getafe',
      },
      {
        seasonId: '2027-2028',
        seasonName: '2027/28 Season',
        seasonStartsAt: '2027-07-01T00:00:00Z',
        kickoffAt: '2027-08-17T20:00:00Z',
        status: 'scheduled',
        homeTeam: 'Real Madrid CF',
        awayTeam: 'Sevilla',
      },
      {
        seasonId: '2027-2028',
        seasonName: '2027/28 Season',
        seasonStartsAt: '2027-07-01T00:00:00Z',
        kickoffAt: '2027-08-14T20:00:00Z',
        status: 'scheduled',
        homeTeam: 'Atlético Madrid',
        awayTeam: 'Getafe',
      },
      {
        // Deliberately appears after a later valid fixture: selection must use
        // kickoff time, not database/input order.
        seasonId: '2027-2028',
        seasonName: '2027/28 Season',
        seasonStartsAt: '2027-07-01T00:00:00Z',
        kickoffAt: '2027-08-15T20:00:00Z',
        status: 'scheduled',
        homeTeam: 'Valencia',
        awayTeam: 'FC Barcelona',
      },
      {
        seasonId: '2028-2029',
        seasonName: '2028/29 Season',
        seasonStartsAt: '2028-07-01T00:00:00Z',
        kickoffAt: '2028-08-19T18:30:00Z',
        status: 'open',
        homeTeam: 'Real Madrid',
        awayTeam: 'Villarreal',
      },
    ]);

    assert.deepEqual(
      discovered.map(season => ({
        id: season.id,
        displayName: season.displayName,
        startsAt: season.startsAt.toISOString(),
      })),
      [
        {
          id: '2027-2028',
          displayName: '2027/28 Season',
          startsAt: '2027-08-15T20:00:00.000Z',
        },
        {
          id: '2028-2029',
          displayName: '2028/29 Season',
          startsAt: '2028-08-19T18:30:00.000Z',
        },
      ],
    );
  });
});
