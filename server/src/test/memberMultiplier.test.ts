import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  awardPointsInTransaction,
  enforceEligibleMultiplier,
  isMemberMultiplierEligible,
  isXpEarningSource,
  memberMultiplierForSource,
  PointSourceType,
  signupBonusIdempotencyKey,
} from '../services/pointsService.js';
import type { PoolClient } from 'pg';

describe('YouTube member point multiplier scope', () => {
  const predictionSources: PointSourceType[] = [
    'prediction_exact',
    'prediction_scorer',
    'prediction_winner',
    'prediction_win',
  ];

  it('doubles prediction rewards for verified members', () => {
    for (const source of predictionSources) {
      assert.equal(isMemberMultiplierEligible(source), true);
      assert.equal(memberMultiplierForSource(source, true, 2), 2);
      assert.equal(memberMultiplierForSource(source, false, 2), 1);
    }
  });

  it('doubles all video-challenge answers for verified members', () => {
    for (const source of ['video_phrase', 'player_card'] as PointSourceType[]) {
      assert.equal(isMemberMultiplierEligible(source), true);
      assert.equal(memberMultiplierForSource(source, true, 2), 2);
      assert.equal(memberMultiplierForSource(source, false, 2), 1);
    }
  });

  it('never doubles signup, daily streak, achievement, or admin points', () => {
    const baseOnlySources: PointSourceType[] = [
      'signup_bonus',
      'daily_streak',
      'admin_adjustment',
      'achievement_bonus',
    ];

    for (const source of baseOnlySources) {
      assert.equal(isMemberMultiplierEligible(source), false);
      assert.equal(memberMultiplierForSource(source, true, 2), 1);
      assert.equal(enforceEligibleMultiplier(source, 2), 1);
    }
  });

  it('earns fixed XP for signup and daily login without enabling other legacy sources', () => {
    assert.equal(isXpEarningSource('signup_bonus'), true);
    assert.equal(isXpEarningSource('daily_streak'), true);
    assert.equal(isXpEarningSource('achievement_bonus'), false);
    assert.equal(isXpEarningSource('admin_adjustment'), false);
    assert.equal(signupBonusIdempotencyKey('user_1'), 'signup_bonus_user_1');
  });

  it('enforces base points at the ledger boundary for ineligible sources', () => {
    assert.equal(enforceEligibleMultiplier('daily_streak', 5), 1);
    assert.equal(enforceEligibleMultiplier('signup_bonus', 10), 1);
    assert.equal(enforceEligibleMultiplier('prediction_exact', 2), 2);
    assert.equal(enforceEligibleMultiplier('video_phrase', 2), 2);
    assert.equal(enforceEligibleMultiplier('player_card', 2), 2);
  });

  it('returns the original points for an idempotent challenge replay', async () => {
    const statements: string[] = [];
    const client = {
      query: async (text: string) => {
        statements.push(text);
        if (statements.length === 1) return { rowCount: 0, rows: [] };
        return {
          rowCount: 1,
          rows: [{ user_id: 'user_1', final_points: 20 }],
        };
      },
    } as unknown as PoolClient;

    const result = await awardPointsInTransaction(client, {
      userId: 'user_1',
      sourceType: 'video_phrase',
      sourceId: 'challenge_1',
      basePoints: 10,
      multiplier: 2,
      description: 'Solved challenge',
      idempotencyKey: 'challenge:challenge_1:user:user_1',
    });

    assert.deepEqual(result, {
      success: true,
      pointsAwarded: 20,
      alreadyAwarded: true,
    });
    assert.equal(statements.length, 2);
    assert.doesNotMatch(statements.join('\n'), /UPDATE user_profiles/);
  });

  it('writes daily login XP once at base multiplier and updates ranking counters', async () => {
    const calls: Array<{ text: string; values?: unknown[] }> = [];
    const client = {
      query: async (text: string, values?: unknown[]) => {
        calls.push({ text, values });
        return calls.length === 1
          ? { rowCount: 1, rows: [{ final_points: 5 }] }
          : { rowCount: 1, rows: [] };
      },
    } as unknown as PoolClient;

    const result = await awardPointsInTransaction(client, {
      userId: 'user_1',
      sourceType: 'daily_streak',
      sourceId: '2026-09-01',
      basePoints: 5,
      multiplier: 10,
      description: 'Daily login XP',
      idempotencyKey: 'streak:user_1:2026-09-01',
    });

    assert.deepEqual(result, { success: true, pointsAwarded: 5 });
    assert.equal(calls[0].values?.[4], 1);
    assert.equal(calls[0].values?.[5], 5);
    assert.match(calls[1].text, /monthly_points = monthly_points \+ \$1/);
    assert.match(calls[1].text, /season_points = season_points \+ \$1/);
    assert.doesNotMatch(calls[1].text, /loyalty_points/);
  });
});
