import { getClient, query } from '../db/pool.js';
import { redis } from '../redis/client.js';
import { config } from '../config.js';

export interface AwardPointsParams {
  userId: string;
  sourceType: 'signup_bonus' | 'prediction_exact' | 'prediction_scorer' | 'prediction_winner' | 'prediction_win' | 'video_phrase' | 'player_card' | 'daily_streak' | 'admin_adjustment' | 'achievement_bonus';
  sourceId: string;
  basePoints: number;
  multiplier?: number;
  description: string;
  idempotencyKey: string;
}

export async function awardPoints(params: AwardPointsParams): Promise<{ success: boolean; pointsAwarded: number; alreadyAwarded?: boolean }> {
  const client = await getClient();
  try {
    await client.query('BEGIN');

    // 1. Check idempotency
    const existing = await client.query(
      'SELECT id, final_points FROM point_transactions WHERE idempotency_key = $1',
      [params.idempotencyKey]
    );

    if (existing.rows.length > 0) {
      await client.query('ROLLBACK');
      return { success: true, pointsAwarded: existing.rows[0].final_points, alreadyAwarded: true };
    }

    const multiplier = params.multiplier ?? 1.0;
    const finalPoints = Math.round(params.basePoints * multiplier);

    // 2. Insert ledger transaction
    await client.query(
      `INSERT INTO point_transactions (user_id, source_type, source_id, base_points, multiplier, final_points, description, idempotency_key)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        params.userId,
        params.sourceType,
        params.sourceId,
        params.basePoints,
        multiplier,
        finalPoints,
        params.description,
        params.idempotencyKey,
      ]
    );

    // 3. Update user profile balance
    const profileUpdate = await client.query(
      `UPDATE user_profiles
       SET total_points = total_points + $1,
           monthly_points = monthly_points + $1,
           season_points = season_points + $1,
           loyalty_points = loyalty_points + $1,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $2`,
      [finalPoints, params.userId]
    );

    if (profileUpdate.rowCount !== 1) {
      throw new Error(`Point balance profile not found for user ${params.userId}`);
    }

    await client.query('COMMIT');

    // 4. Invalidate Redis leaderboard cache
    await Promise.all([
      redis.del('cache:leaderboard:monthly:top100'),
      redis.del('cache:leaderboard:season:top100'),
    ]).catch((error) => {
      // The immutable ledger and balance are already committed. A temporary
      // cache outage must not make a successful points transaction look lost.
      console.warn('[PointsService] Points committed; cache invalidation failed:', error);
    });

    return { success: true, pointsAwarded: finalPoints };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[PointsService] Error awarding points:', err);
    throw err;
  } finally {
    client.release();
  }
}

export async function getPointRules(): Promise<Record<string, number>> {
  const res = await query('SELECT key, base_points FROM point_rules');
  const rules: Record<string, number> = {};
  for (const row of res.rows) {
    rules[row.key] = row.base_points;
  }
  return rules;
}
