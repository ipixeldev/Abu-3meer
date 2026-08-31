import type { PoolClient } from 'pg';
import { getClient, query } from '../db/pool.js';
import { redis } from '../redis/client.js';
import { config } from '../config.js';

export type PointSourceType =
  | 'signup_bonus'
  | 'prediction_exact'
  | 'prediction_scorer'
  | 'prediction_winner'
  | 'prediction_win'
  | 'video_phrase'
  | 'player_card'
  | 'daily_streak'
  | 'admin_adjustment'
  | 'achievement_bonus';

const memberMultiplierSources = new Set<PointSourceType>([
  'prediction_exact',
  'prediction_scorer',
  'prediction_winner',
  'prediction_win',
  'video_phrase',
  'player_card',
]);

/** The only actions that may create XP in the product. */
export function isXpEarningSource(sourceType: PointSourceType): boolean {
  return memberMultiplierSources.has(sourceType);
}

export function isMemberMultiplierEligible(sourceType: PointSourceType): boolean {
  return memberMultiplierSources.has(sourceType);
}

/**
 * YouTube membership doubles prediction rewards and video-challenge answers,
 * including Player Cards. Sign-up, daily attendance, achievements and manual
 * adjustments deliberately remain at their base value.
 */
export function memberMultiplierForSource(
  sourceType: PointSourceType,
  isYouTubeMember: boolean,
  configuredMultiplier = config.pointDefaults.memberMultiplier,
): number {
  return isYouTubeMember && isMemberMultiplierEligible(sourceType)
    ? configuredMultiplier
    : 1;
}

export function enforceEligibleMultiplier(
  sourceType: PointSourceType,
  requestedMultiplier = 1,
): number {
  return isMemberMultiplierEligible(sourceType) ? requestedMultiplier : 1;
}

export interface AwardPointsParams {
  userId: string;
  sourceType: PointSourceType;
  sourceId: string;
  basePoints: number;
  multiplier?: number;
  description: string;
  idempotencyKey: string;
}

export interface AwardPointsResult {
  success: boolean;
  pointsAwarded: number;
  alreadyAwarded?: boolean;
}

/**
 * Writes an award through an existing database transaction.
 *
 * Callers own BEGIN/COMMIT/ROLLBACK. This is intentionally exported so a
 * domain operation such as solving a challenge can keep its ledger entry,
 * balance update, submission and unlock claim in one atomic transaction.
 */
export async function awardPointsInTransaction(
  client: PoolClient,
  params: AwardPointsParams,
): Promise<AwardPointsResult> {
  if (!isXpEarningSource(params.sourceType)) {
    return { success: true, pointsAwarded: 0 };
  }
  const multiplier = enforceEligibleMultiplier(
    params.sourceType,
    params.multiplier ?? 1.0,
  );
  const finalPoints = Math.round(params.basePoints * multiplier);

  const inserted = await client.query(
    `INSERT INTO point_transactions
       (user_id, source_type, source_id, base_points, multiplier, final_points,
        description, idempotency_key)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (idempotency_key) DO NOTHING
     RETURNING final_points`,
    [
      params.userId,
      params.sourceType,
      params.sourceId,
      params.basePoints,
      multiplier,
      finalPoints,
      params.description,
      params.idempotencyKey,
    ],
  );

  if (!inserted.rowCount) {
    const existing = await client.query(
      `SELECT user_id, final_points
       FROM point_transactions
       WHERE idempotency_key = $1`,
      [params.idempotencyKey],
    );
    if (!existing.rowCount || existing.rows[0].user_id !== params.userId) {
      throw new Error('Point award idempotency key is already owned by another operation');
    }
    return {
      success: true,
      pointsAwarded: Number(existing.rows[0].final_points),
      alreadyAwarded: true,
    };
  }

  const profileUpdate = await client.query(
    `UPDATE user_profiles
     SET total_points = total_points + $1,
         monthly_points = monthly_points + $1,
         season_points = season_points + $1,
         updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $2`,
    [finalPoints, params.userId],
  );
  if (profileUpdate.rowCount !== 1) {
    throw new Error(`Point balance profile not found for user ${params.userId}`);
  }

  return { success: true, pointsAwarded: finalPoints };
}

export async function invalidatePointCaches(): Promise<void> {
  await Promise.all([
    redis.del('cache:leaderboard:monthly:top100'),
    redis.del('cache:leaderboard:season:top100'),
  ]).catch((error) => {
    // The immutable ledger and balance are already committed. A temporary
    // cache outage must not make a successful points transaction look lost.
    console.warn('[PointsService] Points committed; cache invalidation failed:', error);
  });
}

export async function awardPoints(params: AwardPointsParams): Promise<AwardPointsResult> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const result = await awardPointsInTransaction(client, params);
    await client.query('COMMIT');
    if (!result.alreadyAwarded) await invalidatePointCaches();
    return result;
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
