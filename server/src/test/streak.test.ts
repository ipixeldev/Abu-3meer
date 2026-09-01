import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  dailyStreakIdempotencyKey,
  deriveStreakCount,
  hasStreakExpired,
  streakInactivityWindowMs,
} from '../services/streakService.js';

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

  it('increments across UTC dates only while the app-open gap is under 24 hours', () => {
    assert.deepEqual(
      deriveStreakCount(4, new Date('2026-08-26T23:00:00.000Z'), now),
      { alreadyCheckedIn: false, nextStreak: 5 },
    );
    assert.deepEqual(
      deriveStreakCount(9, new Date('2026-08-26T22:29:59.999Z'), now),
      { alreadyCheckedIn: false, nextStreak: 1 },
    );
  });

  it('expires at the exact 24-hour inactivity boundary', () => {
    const exactBoundary = new Date(
      now.getTime() - streakInactivityWindowMs,
    );
    const justInsideWindow = new Date(exactBoundary.getTime() + 1);

    assert.equal(hasStreakExpired(exactBoundary, now), true);
    assert.equal(hasStreakExpired(justInsideWindow, now), false);
    assert.deepEqual(deriveStreakCount(12, exactBoundary, now), {
      alreadyCheckedIn: false,
      nextStreak: 1,
    });
    assert.deepEqual(deriveStreakCount(12, justInsideWindow, now), {
      alreadyCheckedIn: false,
      nextStreak: 13,
    });
  });

  it('resets after multiple missed days', () => {
    assert.deepEqual(
      deriveStreakCount(9, new Date('2026-08-24T23:59:00.000Z'), now),
      { alreadyCheckedIn: false, nextStreak: 1 },
    );
  });

  it('uses one stable idempotency key per user and UTC day', () => {
    assert.equal(
      dailyStreakIdempotencyKey('user_1', new Date('2026-09-01T00:00:00Z')),
      'streak:user_1:2026-09-01',
    );
    assert.equal(
      dailyStreakIdempotencyKey('user_1', new Date('2026-09-01T23:59:59Z')),
      'streak:user_1:2026-09-01',
    );
    assert.notEqual(
      dailyStreakIdempotencyKey('user_1', new Date('2026-09-02T00:00:00Z')),
      'streak:user_1:2026-09-01',
    );
  });
});
