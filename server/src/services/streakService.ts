import { config } from '../config.js';
import { getClient } from '../db/pool.js';
import { redis } from '../redis/client.js';

export interface StreakResult {
  streakCount: number;
  pointsAwarded: number;
  alreadyCheckedIn: boolean;
}

function utcDateKey(value: Date): string {
  return value.toISOString().slice(0, 10);
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
 * Performs the streak state change, point-ledger insert and balance update in
 * one database transaction. The profile row lock plus the ledger idempotency
 * key makes concurrent app launches safe: only one call can award points.
 */
export async function checkInDailyStreak(
  userId: string,
  isYouTubeMember: boolean,
): Promise<StreakResult> {
  const now = new Date();
  const today = utcDateKey(now);
  const client = await getClient();

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
      `SELECT base_points, member_multiplier
       FROM point_rules
       WHERE key = 'dailyStreak'`,
    );
    const basePoints = Number(
      ruleRes.rows[0]?.base_points ?? config.pointDefaults.dailyStreak,
    );
    const multiplier = isYouTubeMember
      ? Number(ruleRes.rows[0]?.member_multiplier ?? config.pointDefaults.memberMultiplier)
      : 1;
    const finalPoints = Math.round(basePoints * multiplier);
    const idempotencyKey = `streak:${userId}:${today}`;

    const ledgerInsert = await client.query(
      `INSERT INTO point_transactions
         (user_id, source_type, source_id, base_points, multiplier,
          final_points, description, idempotency_key)
       VALUES ($1, 'daily_streak', $2, $3, $4, $5, $6, $7)
       ON CONFLICT (idempotency_key) DO NOTHING
       RETURNING id`,
      [
        userId,
        today,
        basePoints,
        multiplier,
        finalPoints,
        `Daily streak check-in (Day ${derived.nextStreak})`,
        idempotencyKey,
      ],
    );

    const wasAwarded = ledgerInsert.rowCount === 1;
    const profileUpdate = await client.query(
      `UPDATE user_profiles
       SET streak_count = $1,
           streak_best = GREATEST(streak_best, $1),
           streak_last_checkin = $2,
           total_points = total_points + $3,
           monthly_points = monthly_points + $3,
           season_points = season_points + $3,
           loyalty_points = loyalty_points + $3,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $4`,
      [derived.nextStreak, now, wasAwarded ? finalPoints : 0, userId],
    );
    if (profileUpdate.rowCount !== 1) {
      throw new Error('Unable to update the streak profile.');
    }

    await client.query('COMMIT');

    await Promise.all([
      redis.del('cache:leaderboard:monthly:top100'),
      redis.del('cache:leaderboard:season:top100'),
    ]).catch((error) => {
      console.warn('[StreakService] Check-in committed; cache invalidation failed:', error);
    });

    return {
      streakCount: derived.nextStreak,
      pointsAwarded: wasAwarded ? finalPoints : 0,
      // This also heals the narrow legacy state where a ledger row committed
      // before the old implementation updated streak_last_checkin.
      alreadyCheckedIn: !wasAwarded,
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
