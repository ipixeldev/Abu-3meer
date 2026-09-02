import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  assembleRankedLeaderboardRows,
  discoverFutureLeaderboardSeasons,
  eligibleLeaderboardSourceTypes,
  initialLeaderboardSeasonStart,
  isTrackedLeaderboardClubName,
  leaderboardSeasonWindowsOverlap,
  utcMonthWindow,
  validateManualLeaderboardSeasonWindow,
} from '../services/leaderboardService.js';
import type { RankedRow } from '../services/leaderboardService.js';

describe('XP-only leaderboard periods', () => {
  it('uses one ranked row for both the podium and authenticated user', () => {
    const rows: RankedRow[] = [
      {
        publicId: 'broz',
        username: 'broz',
        displayName: 'Omar',
        avatarUrl: null,
        supportedTeam: 'Barcelona',
        isYouTubeMember: false,
        points: '55',
        rank: '1',
        totalPlayers: '3',
        isCurrentUser: false,
      },
      {
        publicId: 'dev',
        username: 'dev',
        displayName: 'dev',
        avatarUrl: null,
        supportedTeam: 'Real Madrid',
        isYouTubeMember: false,
        points: '10',
        rank: '2',
        totalPlayers: '3',
        isCurrentUser: true,
      },
      {
        publicId: 'brozteamedit',
        username: 'brozteamedit',
        displayName: 'Broz Team',
        avatarUrl: null,
        supportedTeam: 'Barcelona',
        isYouTubeMember: false,
        points: '5',
        rank: '3',
        totalPlayers: '3',
        isCurrentUser: false,
      },
    ];

    const snapshot = assembleRankedLeaderboardRows(rows, 100);
    assert.equal(snapshot.entries[1].points, 10);
    assert.equal(snapshot.currentUser?.points, 10);
    assert.strictEqual(snapshot.currentUser, snapshot.entries[1]);
  });

  it('retains an authenticated user outside the public row limit', () => {
    const rows: RankedRow[] = [
      {
        publicId: 'leader',
        username: 'leader',
        displayName: 'Leader',
        avatarUrl: null,
        supportedTeam: 'Barcelona',
        isYouTubeMember: false,
        points: 100,
        rank: 1,
        totalPlayers: 24,
        isCurrentUser: false,
      },
      {
        publicId: 'fan24',
        username: 'fan24',
        displayName: 'Fan 24',
        avatarUrl: null,
        supportedTeam: 'Real Madrid',
        isYouTubeMember: false,
        points: 1,
        rank: 24,
        totalPlayers: 24,
        isCurrentUser: true,
      },
    ];

    const snapshot = assembleRankedLeaderboardRows(rows, 1);
    assert.deepEqual(snapshot.entries.map(entry => entry.publicId), ['leader']);
    assert.equal(snapshot.currentUser?.publicId, 'fan24');
    assert.equal(snapshot.currentUser?.rank, 24);
    assert.equal(snapshot.totalPlayers, 24);
  });

  it('queries the public rows and authenticated row in one ranked statement', async () => {
    const service = await readFile(
      path.resolve(process.cwd(), 'src/services/leaderboardService.ts'),
      'utf8',
    );
    const routes = await readFile(
      path.resolve(process.cwd(), 'src/routes/leaderboardRoutes.ts'),
      'utf8',
    );

    assert.match(
      service,
      /WHERE rank <= \$3\s+OR \(\$4::text IS NOT NULL AND database_user_id = \$4::text\)/,
    );
    assert.match(service, /AS "isCurrentUser"/);
    assert.match(routes, /databaseUserId: request\.user\?\.id/);
    assert.match(routes, /Cache-Control', 'private, no-store/);
  });

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

  it('keeps lifetime XP distinct from the configured season window', () => {
    const seasonStart = new Date(initialLeaderboardSeasonStart);
    assert.equal(
      seasonStart.toISOString(),
      '2026-08-30T15:00:00.000Z',
    );

    // This mirrors the reported production totals: 60 XP was earned before
    // the season boundary, 65 later in August, and 5 in September. Lifetime XP
    // intentionally keeps all three awards while season XP includes only the
    // awards inside the administrator-configured season window.
    const ledger = [
      { points: 60, createdAt: new Date('2026-08-30T14:59:59.999Z') },
      { points: 65, createdAt: new Date('2026-08-31T12:00:00.000Z') },
      { points: 5, createdAt: new Date('2026-09-01T12:00:00.000Z') },
    ];
    const lifetimePoints = ledger.reduce((sum, award) => sum + award.points, 0);
    const seasonPoints = ledger
      .filter((award) => award.createdAt >= seasonStart)
      .reduce((sum, award) => sum + award.points, 0);

    assert.equal(lifetimePoints, 130);
    assert.equal(seasonPoints, 70);
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
