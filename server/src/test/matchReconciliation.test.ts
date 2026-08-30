import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import type {
  ExternalFootballMatch,
  MatchTimelineDetail,
} from '../services/footballDetailsService.js';
import { normalizeApiFootballMatchDetailsPayload } from '../services/footballDetailsService.js';
import {
  FIRST_SCORER_RECONCILIATION_GRACE_MS,
  findCompletedProviderMatch,
  firstScorerAfterProviderGrace,
  firstScorerFromTimeline,
  officialFirstScorer,
  recoverFinishedMatchSettlements,
  settlementRecoveryRequired,
} from '../services/matchReconciliationService.js';

function timelineEvent(
  minute: string,
  type: string,
  player: string,
): MatchTimelineDetail {
  return {
    minute,
    type,
    player,
    assist: '',
    detail: '',
    team: '',
    isHome: true,
  };
}

describe('completed football-match reconciliation', () => {
  it('uses No scorer for an official 0-0 result without fetching a timeline', () => {
    assert.equal(
      officialFirstScorer({ homeScore: 0, awayScore: 0, timeline: [] }),
      'No scorer',
    );
  });

  it('extracts the chronologically first scored goal including stoppage time', () => {
    const timeline = [
      timelineEvent('45+2', 'goal', 'Second Player'),
      timelineEvent('12', 'goal', 'First Player'),
      timelineEvent('8', 'yellow_card', 'Booked Player'),
      timelineEvent('10', 'penalty', 'Missed Penalty'),
    ];
    assert.equal(firstScorerFromTimeline(timeline), 'First Player');
    assert.equal(
      officialFirstScorer({ homeScore: 2, awayScore: 0, timeline }),
      'First Player',
    );
  });

  it('never treats an API-Football saved penalty as the first scorer', () => {
    const details = normalizeApiFootballMatchDetailsPayload({
      fixture: [{
        fixture: { status: { short: 'FT' } },
        league: { season: 2026 },
        teams: {
          home: { id: 1, name: 'Home' },
          away: { id: 2, name: 'Away' },
        },
        goals: { home: 1, away: 0 },
      }],
      events: [
        {
          time: { elapsed: 10 },
          team: { id: 1, name: 'Home' },
          player: { name: 'Penalty Taker' },
          type: 'Goal',
          detail: 'Missed Penalty',
          comments: 'Penalty saved',
        },
        {
          time: { elapsed: 20 },
          team: { id: 1, name: 'Home' },
          player: { name: 'Actual Scorer' },
          type: 'Goal',
          detail: 'Normal Goal',
        },
      ],
    });

    assert.equal(details.timeline[0]?.type, 'missed_penalty');
    assert.equal(details.timeline[1]?.type, 'goal');
    assert.equal(firstScorerFromTimeline(details.timeline), 'Actual Scorer');
  });

  it('matches a provider result by normalized teams and nearby kickoff', () => {
    const provider: ExternalFootballMatch = {
      id: 'external_123',
      competition_name: 'La Liga',
      home_team_id: '1',
      away_team_id: '2',
      home_team: 'Real Madrid',
      away_team: 'Malaga CF',
      home_logo_url: '',
      away_logo_url: '',
      kickoff_at: '2026-08-30T17:00:00.000Z',
      predictions_open_at: '2026-08-29T17:00:00.000Z',
      predictions_close_at: '2026-08-30T16:55:00.000Z',
      status: 'completed',
      home_score: 2,
      away_score: 1,
      first_scorer: 'Kylian Mbappe',
      first_scorer_options: [],
      provider: 'API-Football',
    };
    const match = findCompletedProviderMatch(
      {
        id: 'admin_1',
        home_team: 'Real Madrid',
        away_team: 'Malaga CF',
        kickoff_at: new Date('2026-08-30T17:02:00.000Z'),
      },
      [provider],
    );
    assert.equal(match?.id, 'external_123');
  });

  it('does not bind the same teams from a different kickoff to a managed match', () => {
    const provider: ExternalFootballMatch = {
      id: 'external_later',
      competition_name: 'La Liga',
      home_team_id: '1',
      away_team_id: '2',
      home_team: 'Real Madrid',
      away_team: 'Malaga CF',
      home_logo_url: '',
      away_logo_url: '',
      kickoff_at: '2026-08-30T17:06:00.000Z',
      predictions_open_at: '2026-08-29T17:06:00.000Z',
      predictions_close_at: '2026-08-30T17:01:00.000Z',
      status: 'completed',
      home_score: 2,
      away_score: 1,
      first_scorer: 'Kylian Mbappe',
      first_scorer_options: [],
      provider: 'API-Football',
    };

    assert.equal(findCompletedProviderMatch({
      id: 'admin_1',
      home_team: 'Real Madrid',
      away_team: 'Malaga CF',
      kickoff_at: new Date('2026-08-30T17:00:00.000Z'),
    }, [provider]), undefined);
  });

  it('pairs provider teams with equivalent accented managed names', () => {
    const provider: ExternalFootballMatch = {
      id: 'external_123',
      competition_name: 'La Liga',
      home_team_id: '1',
      away_team_id: '2',
      home_team: 'Real Madrid',
      away_team: 'Malaga CF',
      home_logo_url: '',
      away_logo_url: '',
      kickoff_at: '2026-08-30T17:00:00.000Z',
      predictions_open_at: '2026-08-29T17:00:00.000Z',
      predictions_close_at: '2026-08-30T16:55:00.000Z',
      status: 'completed',
      home_score: 2,
      away_score: 1,
      first_scorer: 'Kylian Mbappe',
      first_scorer_options: [],
      provider: 'API-Football',
    };

    assert.equal(findCompletedProviderMatch({
      id: 'managed_accented',
      home_team: 'Real Madrid',
      away_team: 'Málaga CF',
      kickoff_at: new Date('2026-08-30T17:00:00.000Z'),
    }, [provider])?.id, 'external_123');
  });

  it('waits for provider events, then settles score rewards without a scorer', () => {
    const kickoffAt = new Date('2026-08-30T17:00:00.000Z');
    expectFirstScorerFallback('', new Date(
      kickoffAt.getTime() + FIRST_SCORER_RECONCILIATION_GRACE_MS - 1,
    ));
    expectFirstScorerFallback('Unknown', new Date(
      kickoffAt.getTime() + FIRST_SCORER_RECONCILIATION_GRACE_MS,
    ));

    function expectFirstScorerFallback(expected: string, now: Date) {
      assert.equal(
        firstScorerAfterProviderGrace({
          kickoffAt,
          homeScore: 2,
          awayScore: 1,
          now,
        }),
        expected,
      );
    }
  });

  it('recovers provider and managed finished matches after queue loss', async () => {
    const attempts: string[] = [];
    const result = await recoverFinishedMatchSettlements(
      async matchId => {
        attempts.push(matchId);
        if (matchId === 'managed_retry') throw new Error('Redis unavailable');
      },
      async () => ['external_1570360', 'managed_retry', 'managed_ready'],
    );

    assert.deepEqual(attempts, [
      'external_1570360',
      'managed_retry',
      'managed_ready',
    ]);
    assert.deepEqual(result, { found: 3, enqueued: 2, failed: 1 });

    const retried: string[] = [];
    const secondPass = await recoverFinishedMatchSettlements(
      async matchId => { retried.push(matchId); },
      async () => ['managed_retry'],
    );
    assert.deepEqual(retried, ['managed_retry']);
    assert.deepEqual(secondPass, { found: 1, enqueued: 1, failed: 0 });
  });

  it('recovers a partial settlement after its last prediction was rewarded', () => {
    assert.equal(settlementRecoveryRequired({
      rewardProcessed: false,
      hasUnrewarded: false,
    }), true);
    assert.equal(settlementRecoveryRequired({
      rewardProcessed: true,
      hasUnrewarded: true,
    }), true);
    assert.equal(settlementRecoveryRequired({
      rewardProcessed: true,
      hasUnrewarded: false,
    }), false);
  });
});
