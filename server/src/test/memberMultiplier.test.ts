import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  awardPointsInTransaction,
  enforceEligibleMultiplier,
  isMemberMultiplierEligible,
  memberMultiplierForSource,
  PointSourceType,
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
});
