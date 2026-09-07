import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { getClient, query } from '../db/pool.js';
import { redis } from '../redis/client.js';
import { config } from '../config.js';
import { activeMemberAccessSql } from './subscriptionAccess.js';

export type PointSourceType =
  | 'signup_bonus'
  | 'prediction_exact'
  | 'prediction_scorer'
  | 'prediction_winner'
  | 'prediction_win'
  | 'video_phrase'
  | 'player_card'
  | 'daily_streak'
  | 'membership_activation'
  | 'membership_renewal'
  | 'admin_adjustment'
  | 'achievement_bonus';

const memberMultiplierSources = new Set<PointSourceType>([
  'prediction_exact',
  'prediction_scorer',
  'prediction_winner',
  'prediction_win',
]);

export const eligiblePointSourceTypes: readonly PointSourceType[] = [
  'signup_bonus',
  'daily_streak',
  'prediction_exact',
  'prediction_scorer',
  'prediction_winner',
  'prediction_win',
  'video_phrase',
  'player_card',
  'membership_activation',
  'membership_renewal',
  'admin_adjustment',
];

const xpEarningSources = new Set<PointSourceType>(eligiblePointSourceTypes);

/** The only actions that may create XP in the product. */
export function isXpEarningSource(sourceType: PointSourceType): boolean {
  return xpEarningSources.has(sourceType);
}

export function signupBonusIdempotencyKey(userId: string): string {
  return `signup_bonus_${userId}`;
}

export function membershipActivationIdempotencyKey(userId: string): string {
  return `membership:activation:${userId}`;
}

export function isMemberMultiplierEligible(sourceType: PointSourceType): boolean {
  return memberMultiplierSources.has(sourceType);
}

/**
 * Membership doubles only match-winner, first-goalscorer, and exact-score
 * prediction rewards. Other XP sources deliberately remain at base value.
 */
export function memberMultiplierForSource(
  sourceType: PointSourceType,
  hasMemberAccess: boolean,
  configuredMultiplier = config.pointDefaults.memberMultiplier,
): number {
  return hasMemberAccess && isMemberMultiplierEligible(sourceType)
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
        monthly_points_delta, season_points_delta, description, idempotency_key)
     VALUES ($1, $2, $3, $4, $5, $6, $6, $6, $7, $8)
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
  return getPointRuleSettings();
}

export interface PointRuleSettings extends Record<string, number> {
  memberMultiplier: number;
}

export async function getPointRuleSettings(
  execute: (
    text: string,
    params?: unknown[],
  ) => Promise<{ rows: Array<Record<string, unknown>> }> = query,
): Promise<PointRuleSettings> {
  const result = await execute(
    `SELECT key, base_points, member_multiplier
     FROM point_rules`,
  );
  const rules: Record<string, number> = {};
  let memberMultiplier = config.pointDefaults.memberMultiplier;
  for (const row of result.rows) {
    const key = String(row.key);
    rules[key] = Number(row.base_points);
    if (key === 'exactPrediction') {
      memberMultiplier = Number(row.member_multiplier);
    }
  }
  return { ...rules, memberMultiplier };
}

export type MembershipRewardProvider = 'revenuecat' | 'youtube';

export interface MembershipRewardCycleResult {
  activationPoints: number;
  renewalPoints: number;
  cycleChanged: boolean;
}

function membershipRenewalIdempotencyKey(
  userId: string,
  provider: MembershipRewardProvider,
  cycleKey: string,
): string {
  const digest = createHash('sha256').update(cycleKey).digest('hex');
  return `membership:renewal:${provider}:${userId}:${digest}`;
}

async function pointRuleValueInTransaction(
  client: PoolClient,
  key: string,
  fallback: number,
): Promise<number> {
  const result = await client.query(
    'SELECT base_points FROM point_rules WHERE key = $1',
    [key],
  );
  return Number(result.rows[0]?.base_points ?? fallback);
}

/**
 * Persist one provider's latest verified membership cycle and award points in
 * the same transaction. The first observed cycle initializes provider state
 * and attempts the global one-time activation award. Only a strictly newer
 * cycle can create a renewal award, so retries and delayed receipts are safe.
 */
export async function recordMembershipRewardCycleInTransaction(
  client: PoolClient,
  params: {
    userId: string;
    provider: MembershipRewardProvider;
    cycleKey: string;
    cycleSequence: number;
    observedAt?: Date;
  },
): Promise<MembershipRewardCycleResult> {
  const cycleKey = params.cycleKey.trim();
  if (
    !cycleKey ||
    cycleKey.length > 180 ||
    !Number.isFinite(params.cycleSequence)
  ) {
    throw new Error('Membership reward cycle is invalid.');
  }
  const observedAt = params.observedAt ?? new Date();
  // Serialize with Admin Studio's access override transaction, which locks the
  // same user row before changing an override. An explicit inactive override
  // must suppress both activation and renewal XP without consuming cycle state.
  const lockedUser = await client.query(
    'SELECT id FROM users WHERE id = $1 FOR SHARE',
    [params.userId],
  );
  if (lockedUser.rowCount !== 1) {
    throw new Error(`Membership reward user not found: ${params.userId}`);
  }
  const effectiveAccess = await client.query(
    `SELECT ${activeMemberAccessSql('candidate.user_id')} AS has_member_access
     FROM (SELECT $1::uuid AS user_id) candidate`,
    [params.userId],
  );
  if (effectiveAccess.rows[0]?.has_member_access !== true) {
    return { activationPoints: 0, renewalPoints: 0, cycleChanged: false };
  }
  const inserted = await client.query(
    `INSERT INTO membership_reward_cycles
       (user_id, provider, cycle_key, cycle_sequence,
        first_observed_at, last_observed_at)
     VALUES ($1, $2, $3, $4, $5, $5)
     ON CONFLICT (user_id, provider) DO NOTHING
     RETURNING cycle_key`,
    [params.userId, params.provider, cycleKey, params.cycleSequence, observedAt],
  );

  const activationBase = await pointRuleValueInTransaction(
    client,
    'firstMembershipActivation',
    config.pointDefaults.firstMembershipActivation,
  );
  const activation = await awardPointsInTransaction(client, {
    userId: params.userId,
    sourceType: 'membership_activation',
    sourceId: params.provider,
    basePoints: activationBase,
    multiplier: 1,
    description: 'First membership activation',
    idempotencyKey: membershipActivationIdempotencyKey(params.userId),
  });

  if (inserted.rowCount) {
    return {
      activationPoints: activation.alreadyAwarded ? 0 : activation.pointsAwarded,
      renewalPoints: 0,
      cycleChanged: false,
    };
  }

  const previous = await client.query(
    `SELECT cycle_key, cycle_sequence
     FROM membership_reward_cycles
     WHERE user_id = $1 AND provider = $2
     FOR UPDATE`,
    [params.userId, params.provider],
  );
  const previousSequence = Number(previous.rows[0]?.cycle_sequence);
  const previousKey = String(previous.rows[0]?.cycle_key ?? '');
  const evidenceFamily = (key: string) => key.split(':', 1)[0];
  // Older builds used entitlement expiry and snapshot identity as renewal
  // evidence. Adopt the authoritative purchase/tenure baseline without
  // creating a migration-time renewal, then require a later sequence.
  if (evidenceFamily(previousKey) !== evidenceFamily(cycleKey)) {
    await client.query(
      `UPDATE membership_reward_cycles
       SET cycle_key = $3, cycle_sequence = $4, last_observed_at = $5
       WHERE user_id = $1 AND provider = $2`,
      [params.userId, params.provider, cycleKey, params.cycleSequence, observedAt],
    );
    return {
      activationPoints: activation.alreadyAwarded ? 0 : activation.pointsAwarded,
      renewalPoints: 0,
      cycleChanged: false,
    };
  }
  if (
    !Number.isFinite(previousSequence) ||
    params.cycleSequence <= previousSequence
  ) {
    return {
      activationPoints: activation.alreadyAwarded ? 0 : activation.pointsAwarded,
      renewalPoints: 0,
      cycleChanged: false,
    };
  }

  await client.query(
    `UPDATE membership_reward_cycles
     SET cycle_key = $3, cycle_sequence = $4, last_observed_at = $5
     WHERE user_id = $1 AND provider = $2`,
    [params.userId, params.provider, cycleKey, params.cycleSequence, observedAt],
  );
  const renewalBase = await pointRuleValueInTransaction(
    client,
    'membershipRenewal',
    config.pointDefaults.membershipRenewal,
  );
  const renewal = await awardPointsInTransaction(client, {
    userId: params.userId,
    sourceType: 'membership_renewal',
    sourceId:
      `${params.provider}:${createHash('sha256').update(cycleKey).digest('hex')}`,
    basePoints: renewalBase,
    multiplier: 1,
    description: 'Membership renewal',
    idempotencyKey: membershipRenewalIdempotencyKey(
      params.userId,
      params.provider,
      cycleKey,
    ),
  });
  return {
    activationPoints: activation.alreadyAwarded ? 0 : activation.pointsAwarded,
    renewalPoints: renewal.alreadyAwarded ? 0 : renewal.pointsAwarded,
    cycleChanged: true,
  };
}

export async function recordMembershipRewardCycle(
  params: Parameters<typeof recordMembershipRewardCycleInTransaction>[1],
): Promise<MembershipRewardCycleResult> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const result = await recordMembershipRewardCycleInTransaction(client, params);
    await client.query('COMMIT');
    if (result.activationPoints > 0 || result.renewalPoints > 0) {
      await invalidatePointCaches();
    }
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export const editablePointRuleKeys = [
  'signUpBonus',
  'dailyStreak',
  'videoQuestion',
  'playerCard',
  'winnerOutcome',
  'firstScorer',
  'exactPrediction',
  'firstMembershipActivation',
  'membershipRenewal',
] as const;

export type EditablePointRuleKey = typeof editablePointRuleKeys[number];
export type PointRuleUpdate = Partial<Record<EditablePointRuleKey, number>> & {
  memberMultiplier?: number;
};

export async function updatePointRuleSettings(
  actorId: string,
  values: PointRuleUpdate,
  connect: () => Promise<PoolClient> = getClient,
): Promise<PointRuleSettings> {
  const client = await connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT key
       FROM point_rules
       WHERE key = ANY($1::varchar[])
       FOR UPDATE`,
      [editablePointRuleKeys],
    );
    const before = await getPointRuleSettings((text, params) =>
      client.query(text, params));
    for (const key of editablePointRuleKeys) {
      const basePoints = values[key];
      if (basePoints === undefined) continue;
      const updated = await client.query(
        `UPDATE point_rules
         SET base_points = $1, updated_at = CURRENT_TIMESTAMP
         WHERE key = $2
         RETURNING key`,
        [basePoints, key],
      );
      if (updated.rowCount !== 1) {
        throw new Error(`Point rule ${key} is not installed.`);
      }
    }
    if (values.memberMultiplier !== undefined) {
      await client.query(
        `UPDATE point_rules
         SET member_multiplier = CASE
               WHEN key = ANY($1::varchar[]) THEN $2
               ELSE 1.00
             END,
             updated_at = CURRENT_TIMESTAMP
         WHERE key = ANY($3::varchar[])`,
        [
          ['exactPrediction', 'firstScorer', 'winnerOutcome'],
          values.memberMultiplier,
          editablePointRuleKeys,
        ],
      );
    }
    const after = await getPointRuleSettings((text, params) =>
      client.query(text, params));
    await client.query(
      `INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id,
          before_state, after_state)
       VALUES ($1, 'point_rules.update', 'settings', 'point_rules',
               $2::jsonb, $3::jsonb)`,
      [actorId, JSON.stringify(before), JSON.stringify(after)],
    );
    await client.query('COMMIT');
    return after;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export interface AdminPointAdjustmentResult {
  adjustmentId: string;
  targetUserId: string;
  delta: number;
  totalPoints: number;
  monthlyPoints: number;
  seasonPoints: number;
  duplicate: boolean;
  periodFloorApplied: boolean;
}

export async function adjustUserPoints(
  params: {
    actorId: string;
    targetUserId: string;
    amount: number;
    reason: string;
    idempotencyKey: string;
    observedAt?: Date;
  },
  connect: () => Promise<PoolClient> = getClient,
  invalidateCaches: () => Promise<void> = invalidatePointCaches,
): Promise<AdminPointAdjustmentResult> {
  const client = await connect();
  let invalidate = false;
  try {
    await client.query('BEGIN');
    const lockedProfile = await client.query(
      `SELECT 1
       FROM user_profiles
       WHERE user_id = $1
       FOR UPDATE`,
      [params.targetUserId],
    );
    if (lockedProfile.rowCount !== 1) {
      throw Object.assign(new Error('User not found.'), { statusCode: 404 });
    }
    const actor = await client.query(
      `SELECT firebase_uid, display_name, username
       FROM users
       WHERE id = $1`,
      [params.actorId],
    );
    const actorSnapshot = actor.rows[0] ?? {};
    // Derive the current balances only after owning the profile lock. Regular
    // awards update the same profile row after writing their ledger entry, so
    // a concurrent award either commits before this read or increments after
    // this correction; neither path can be overwritten.
    const profile = await client.query(
      `WITH current_season AS (
         SELECT id, starts_at, ends_at
         FROM leaderboard_periods
         WHERE type = 'season' AND is_current = TRUE
         ORDER BY starts_at DESC
         LIMIT 1
       )
       SELECT COALESCE(SUM(pt.final_points), 0)::integer AS total_points,
              COALESCE(SUM(COALESCE(
                pt.monthly_points_delta,
                pt.final_points
              )) FILTER (
                WHERE pt.created_at >= (
                  date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                  AT TIME ZONE 'UTC'
                )
              ), 0)::integer AS monthly_points,
              COALESCE(SUM(COALESCE(
                pt.season_points_delta,
                pt.final_points
              )) FILTER (
                WHERE season.starts_at IS NOT NULL
                  AND pt.created_at >= season.starts_at
                  AND (season.ends_at IS NULL OR pt.created_at < season.ends_at)
              ), 0)::integer AS season_points,
              (SELECT id FROM current_season) AS season_id
       FROM point_transactions pt
       LEFT JOIN current_season season ON TRUE
       WHERE pt.user_id = $1
         AND pt.source_type = ANY($2::varchar[])`,
      [params.targetUserId, eligiblePointSourceTypes],
    );
    const before = {
      total: Number(profile.rows[0].total_points),
      monthly: Number(profile.rows[0].monthly_points),
      season: Number(profile.rows[0].season_points),
    };
    const ledgerKey = `admin_adjustment:${params.idempotencyKey}`;
    const duplicate = await client.query(
      `SELECT id, user_id, final_points,
              monthly_points_delta, season_points_delta
       FROM point_transactions
       WHERE idempotency_key = $1`,
      [ledgerKey],
    );
    if (duplicate.rowCount) {
      if (duplicate.rows[0].user_id !== params.targetUserId) {
        throw Object.assign(
          new Error('This adjustment key was already used for another user.'),
          { statusCode: 409 },
        );
      }
      await client.query('COMMIT');
      return {
        adjustmentId: String(duplicate.rows[0].id),
        targetUserId: params.targetUserId,
        delta: Number(duplicate.rows[0].final_points),
        totalPoints: before.total,
        monthlyPoints: before.monthly,
        seasonPoints: before.season,
        duplicate: true,
        periodFloorApplied:
          Number(duplicate.rows[0].monthly_points_delta)
            !== Number(duplicate.rows[0].final_points)
          || Number(duplicate.rows[0].season_points_delta)
            !== Number(duplicate.rows[0].final_points),
      };
    }
    if (before.total + params.amount < 0) {
      throw Object.assign(
        new Error('The adjustment would make lifetime XP negative.'),
        { statusCode: 422 },
      );
    }
    const after = {
      total: before.total + params.amount,
      monthly: Math.max(0, before.monthly + params.amount),
      season: Math.max(0, before.season + params.amount),
    };
    const monthlyDelta = after.monthly - before.monthly;
    const seasonDelta = after.season - before.season;
    const observedAt = params.observedAt ?? new Date();
    const inserted = await client.query(
      `INSERT INTO point_transactions
         (user_id, source_type, source_id, base_points, multiplier,
          final_points, monthly_points_delta, season_points_delta,
          description, idempotency_key, created_at)
       VALUES ($1, 'admin_adjustment', $2, $3, 1.00,
               $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      [
        params.targetUserId,
        params.idempotencyKey,
        params.amount,
        monthlyDelta,
        seasonDelta,
        params.reason,
        ledgerKey,
        observedAt,
      ],
    );
    const adjustmentId = String(inserted.rows[0].id);
    await client.query(
      `UPDATE user_profiles
       SET total_points = $2,
           monthly_points = $3,
           season_points = $4,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [params.targetUserId, after.total, after.monthly, after.season],
    );
    const periodFloorApplied =
      monthlyDelta !== params.amount || seasonDelta !== params.amount;
    await client.query(
      `INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id,
          before_state, after_state)
       VALUES ($1, 'points.adjust', 'user', $2, $3::jsonb, $4::jsonb)`,
      [
        params.actorId,
        params.targetUserId,
        JSON.stringify({
          totalPoints: before.total,
          monthlyPoints: before.monthly,
          seasonPoints: before.season,
        }),
        JSON.stringify({
          pointTransactionId: adjustmentId,
          idempotencyKey: params.idempotencyKey,
          adminId: String(actorSnapshot.firebase_uid || params.actorId),
          adminDisplayName: String(
            actorSnapshot.display_name || actorSnapshot.username || 'Administrator',
          ),
          amount: params.amount,
          reason: params.reason,
          totalPoints: after.total,
          monthlyPoints: after.monthly,
          seasonPoints: after.season,
          periodFloorApplied,
          monthlyPeriod: observedAt.toISOString().slice(0, 7),
          seasonId: profile.rows[0].season_id ?? '',
        }),
      ],
    );
    await client.query('COMMIT');
    invalidate = true;
    return {
      adjustmentId,
      targetUserId: params.targetUserId,
      delta: params.amount,
      totalPoints: after.total,
      monthlyPoints: after.monthly,
      seasonPoints: after.season,
      duplicate: false,
      periodFloorApplied,
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
    if (invalidate) await invalidateCaches();
  }
}
