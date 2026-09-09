import { getClient } from '../db/pool.js';
import { config } from '../config.js';
import {
  awardPointsInTransaction,
  invalidatePointCaches,
} from './pointsService.js';

export interface StreakResult {
  streakCount: number;
  pointsAwarded: number;
  alreadyCheckedIn: boolean;
}

export const streakInactivityWindowMs = 24 * 60 * 60 * 1000;

function utcDateKey(value: Date): string {
  return value.toISOString().slice(0, 10);
}

export function dailyStreakIdempotencyKey(userId: string, value: Date): string {
  return `streak:${userId}:${utcDateKey(value)}`;
}

export function hasStreakExpired(
  lastCheckIn: Date | null,
  now: Date,
): boolean {
  if (!lastCheckIn) return false;
  return now.getTime() - lastCheckIn.getTime() >= streakInactivityWindowMs;
}

export function deriveStreakCount(
  currentStreak: number,
  lastCheckIn: Date | null,
  now: Date,
): { alreadyCheckedIn: boolean; nextStreak: number } {
  if (!lastCheckIn) {
    return { alreadyCheckedIn: false, nextStreak: 1 };
  }

  const today = utcDateKey(now);
  const lastDay = utcDateKey(lastCheckIn);
  const expired = hasStreakExpired(lastCheckIn, now);
  if (lastDay === today && !expired) {
    return { alreadyCheckedIn: true, nextStreak: currentStreak };
  }

  return {
    alreadyCheckedIn: false,
    // A streak is based on actual app attendance, not only calendar labels.
    // Crossing midnight still advances it, but 24 hours without a launch
    // always starts a new streak even when the previous check-in was on the
    // immediately preceding UTC date.
    nextStreak: expired ? 1 : currentStreak + 1,
  };
}

async function persistStreakActivity(
  client: Awaited<ReturnType<typeof getClient>>,
  userId: string,
  streakCount: number,
  now: Date,
): Promise<void> {
  // Keep the attendance timestamp and the account's last-active timestamp in
  // the same transaction. The profile row is already locked by the caller,
  // so concurrent launches cannot award twice or move the timestamp backwards.
  const result = await client.query(
    `WITH updated_profile AS (
       UPDATE user_profiles
       SET streak_count = $1,
           streak_best = GREATEST(streak_best, $1),
           streak_last_checkin = GREATEST(streak_last_checkin, $2),
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $3
       RETURNING user_id
     )
     UPDATE users
     SET last_active_at = GREATEST(last_active_at, $2)
     WHERE id IN (SELECT user_id FROM updated_profile)`,
    [streakCount, now, userId],
  );
  if (result.rowCount !== 1) {
    throw new Error('Unable to update the streak profile.');
  }
}

/**
 * Updates the attendance streak and fixed daily XP in one transaction. A
 * profile row lock plus the UTC-day ledger key makes concurrent launches safe.
 * Daily attendance deliberately never receives the YouTube member multiplier.
 */
export async function checkInDailyStreak(
  userId: string,
): Promise<StreakResult> {
  const client = await getClient();
  let didAwardPoints = false;

  try {
    await client.query('BEGIN');
    const profileRes = await client.query(
      `SELECT streak_count, streak_best, streak_last_checkin
       FROM user_profiles
       WHERE user_id = $1
       FOR UPDATE`,
      [userId],
    );

    if (profileRes.rowCount !== 1) {
      throw Object.assign(new Error('User profile not found.'), { statusCode: 404 });
    }

    // Capture the check-in time only after the profile lock is acquired. This
    // prevents a request that waited on another launch from overwriting the
    // newer activity timestamp with an earlier pre-lock timestamp.
    const now = new Date();
    const profile = profileRes.rows[0];
    const currentStreak = Number(profile.streak_count || 0);
    const lastCheckIn = profile.streak_last_checkin
      ? new Date(profile.streak_last_checkin)
      : null;
    const derived = deriveStreakCount(currentStreak, lastCheckIn, now);

    if (derived.alreadyCheckedIn) {
      // The daily XP entry remains once-per-UTC-day, but every launch refreshes
      // the inactivity clock. Without this touch, a morning launch followed by
      // an evening launch would incorrectly expire 24 hours after the morning.
      await persistStreakActivity(client, userId, currentStreak, now);
      await client.query('COMMIT');
      return {
        streakCount: currentStreak,
        pointsAwarded: 0,
        alreadyCheckedIn: true,
      };
    }

    const ruleRes = await client.query(
      `SELECT base_points
       FROM point_rules
       WHERE key = 'dailyStreak'`,
    );
    const award = await awardPointsInTransaction(client, {
      userId,
      sourceType: 'daily_streak',
      sourceId: utcDateKey(now),
      basePoints: Number(
        ruleRes.rows[0]?.base_points ?? config.pointDefaults.dailyStreak,
      ),
      multiplier: 1,
      description: `Daily login XP (Day ${derived.nextStreak})`,
      idempotencyKey: dailyStreakIdempotencyKey(userId, now),
    });
    didAwardPoints = award.alreadyAwarded !== true && award.pointsAwarded > 0;

    await persistStreakActivity(client, userId, derived.nextStreak, now);

    await client.query('COMMIT');
    if (didAwardPoints) await invalidatePointCaches();

    return {
      streakCount: derived.nextStreak,
      pointsAwarded: didAwardPoints ? award.pointsAwarded : 0,
      alreadyCheckedIn: award.alreadyAwarded === true,
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
