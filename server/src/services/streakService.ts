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

function utcDateKey(value: Date): string {
  return value.toISOString().slice(0, 10);
}

export function dailyStreakIdempotencyKey(userId: string, value: Date): string {
  return `streak:${userId}:${utcDateKey(value)}`;
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
  if (lastDay === today) {
    return { alreadyCheckedIn: true, nextStreak: currentStreak };
  }

  const yesterday = new Date(now);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  return {
    alreadyCheckedIn: false,
    nextStreak: lastDay === utcDateKey(yesterday) ? currentStreak + 1 : 1,
  };
}

/**
 * Updates the attendance streak and fixed daily XP in one transaction. A
 * profile row lock plus the UTC-day ledger key makes concurrent launches safe.
 * Daily attendance deliberately never receives the YouTube member multiplier.
 */
export async function checkInDailyStreak(
  userId: string,
): Promise<StreakResult> {
  const now = new Date();
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

    const profile = profileRes.rows[0];
    const currentStreak = Number(profile.streak_count || 0);
    const lastCheckIn = profile.streak_last_checkin
      ? new Date(profile.streak_last_checkin)
      : null;
    const derived = deriveStreakCount(currentStreak, lastCheckIn, now);

    if (derived.alreadyCheckedIn) {
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

    const profileUpdate = await client.query(
      `UPDATE user_profiles
       SET streak_count = $1,
           streak_best = GREATEST(streak_best, $1),
           streak_last_checkin = $2,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $3`,
      [derived.nextStreak, now, userId],
    );
    if (profileUpdate.rowCount !== 1) {
      throw new Error('Unable to update the streak profile.');
    }

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
