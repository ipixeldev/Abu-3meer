import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { deriveStreakCount } from '../services/streakService.js';

describe('daily streak derivation', () => {
  const now = new Date('2026-08-27T22:30:00.000Z');

  it('starts a new streak for the first check-in', () => {
    assert.deepEqual(deriveStreakCount(0, null, now), {
      alreadyCheckedIn: false,
      nextStreak: 1,
    });
  });

  it('does not award a second check-in on the same UTC day', () => {
    assert.deepEqual(
      deriveStreakCount(4, new Date('2026-08-27T00:01:00.000Z'), now),
      { alreadyCheckedIn: true, nextStreak: 4 },
    );
  });

  it('increments consecutive days and resets missed days', () => {
    assert.deepEqual(
      deriveStreakCount(4, new Date('2026-08-26T01:00:00.000Z'), now),
      { alreadyCheckedIn: false, nextStreak: 5 },
    );
    assert.deepEqual(
      deriveStreakCount(9, new Date('2026-08-24T23:59:00.000Z'), now),
      { alreadyCheckedIn: false, nextStreak: 1 },
    );
  });
});
