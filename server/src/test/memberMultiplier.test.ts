import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  enforceEligibleMultiplier,
  isMemberMultiplierEligible,
  memberMultiplierForSource,
  PointSourceType,
} from '../services/pointsService.js';

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

  it('doubles video-question answers for verified members', () => {
    assert.equal(isMemberMultiplierEligible('video_phrase'), true);
    assert.equal(memberMultiplierForSource('video_phrase', true, 2), 2);
    assert.equal(memberMultiplierForSource('video_phrase', false, 2), 1);
  });

  it('never doubles signup, daily streak, or Player Card points', () => {
    const baseOnlySources: PointSourceType[] = [
      'signup_bonus',
      'daily_streak',
      'player_card',
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
  });
});
