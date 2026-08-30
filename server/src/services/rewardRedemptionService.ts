import crypto from 'crypto';
import type { PoolClient } from 'pg';
import { getClient } from '../db/pool.js';
import {
  firebaseAdmin,
  getAdminFirestore,
} from '../firebase/firestore.js';

export type LoyaltyRedemptionFailure =
  | 'reward-not-found'
  | 'profile-missing'
  | 'account-suspended'
  | 'reward-unavailable'
  | 'reward-not-started'
  | 'reward-ended'
  | 'members-only'
  | 'claim-limit'
  | 'out-of-stock'
  | 'insufficient-balance'
  | 'invalid-configuration';

export class LoyaltyRedemptionError extends Error {
  constructor(
    public readonly reason: LoyaltyRedemptionFailure,
    message: string,
  ) {
    super(message);
    this.name = 'LoyaltyRedemptionError';
  }
}

export interface LoyaltyRedemptionState {
  balance: number;
  cost: number;
  stock: number | null;
  claimCount: number;
  perUserLimit: number;
}

export interface LoyaltyRedemptionTransition {
  remainingBalance: number;
  stockRemaining: number | null;
  claimCount: number;
}

export interface LoyaltyRedemptionReceipt extends LoyaltyRedemptionTransition {
  ok: true;
  duplicate: boolean;
  redemptionId: string;
  cost: number;
  cancelled?: boolean;
}

export interface RedeemingUser {
  postgresUserId: string;
  firebaseUid: string;
  email: string | null;
  username: string;
  displayName: string;
  isYouTubeMember: boolean;
}

function idComponent(value: string): string {
  const encoded = encodeURIComponent(value);
  return `${encoded.length}-${encoded}`;
}

/** Matches the stable document ID used by the retired Cloud Function. */
export function loyaltyRedemptionId(
  firebaseUid: string,
  rewardId: string,
  idempotencyKey: string,
): string {
  return `redemption_${[firebaseUid, rewardId, idempotencyKey]
    .map(idComponent)
    .join('_')}`;
}

/** Matches the legacy per-user/per-reward claim counter document. */
export function loyaltyRewardClaimId(
  firebaseUid: string,
  rewardId: string,
): string {
  return `claim_${[firebaseUid, rewardId].map(idComponent).join('_')}`;
}

export function rewardIsAvailableConfiguration(
  enabled: unknown,
  status: unknown,
): boolean {
  if (enabled === false) return false;
  const normalizedStatus = typeof status === 'string' ? status.trim() : '';
  if (normalizedStatus) return ['active', 'live'].includes(normalizedStatus);
  return enabled === true;
}

export function calculateLoyaltyRedemption(
  state: LoyaltyRedemptionState,
): LoyaltyRedemptionTransition {
  const integers = [
    state.balance,
    state.cost,
    state.claimCount,
    state.perUserLimit,
  ];
  if (
    !integers.every(Number.isSafeInteger) ||
    state.balance < 0 ||
    state.cost < 1 ||
    state.claimCount < 0 ||
    state.perUserLimit < 1 ||
    (state.stock !== null &&
      (!Number.isSafeInteger(state.stock) || state.stock < 0))
  ) {
    throw new LoyaltyRedemptionError(
      'invalid-configuration',
      'Reward configuration is invalid.',
    );
  }
  if (state.claimCount >= state.perUserLimit) {
    throw new LoyaltyRedemptionError(
      'claim-limit',
      "You reached this reward's redemption limit.",
    );
  }
  if (state.stock === 0) {
    throw new LoyaltyRedemptionError(
      'out-of-stock',
      'This reward is out of stock.',
    );
  }
  if (state.balance < state.cost) {
    throw new LoyaltyRedemptionError(
      'insufficient-balance',
      'You do not have enough loyalty points.',
    );
  }
  return {
    remainingBalance: state.balance - state.cost,
    stockRemaining: state.stock === null ? null : state.stock - 1,
    claimCount: state.claimCount + 1,
  };
}

function configuredInteger(
  value: unknown,
  field: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  if (value == null) return fallback;
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < minimum ||
    (value as number) > maximum
  ) {
    throw new LoyaltyRedemptionError(
      'invalid-configuration',
      `${field} configuration is invalid.`,
    );
  }
  return value as number;
}

function storedTimestampMillis(value: unknown, field: string): number {
  if (!(value instanceof firebaseAdmin.firestore.Timestamp)) {
    throw new LoyaltyRedemptionError(
      'invalid-configuration',
      `${field} configuration is invalid.`,
    );
  }
  return value.toMillis();
}

function firestoreLedgerId(redemptionId: string): string {
  return redemptionId;
}

export function postgresLoyaltyRedemptionLedgerId(
  redemptionId: string,
): string {
  return `loyalty_redemption_${crypto
    .createHash('sha256')
    .update(redemptionId)
    .digest('hex')}`;
}

export function postgresLoyaltyRefundLedgerId(redemptionId: string): string {
  return `loyalty_refund_${crypto
    .createHash('sha256')
    .update(redemptionId)
    .digest('hex')}`;
}

async function persistPostgresRedemption(
  client: PoolClient,
  user: RedeemingUser,
  rewardId: string,
  receipt: LoyaltyRedemptionReceipt,
): Promise<LoyaltyRedemptionReceipt> {
  if (receipt.cancelled === true) {
    const current = await client.query(
      `SELECT loyalty_points
       FROM user_profiles
       WHERE user_id = $1`,
      [user.postgresUserId],
    );
    if (current.rowCount !== 1) {
      throw new LoyaltyRedemptionError(
        'profile-missing',
        'User profile is missing.',
      );
    }
    return {
      ...receipt,
      remainingBalance: configuredInteger(
        current.rows[0].loyalty_points,
        'Loyalty balance',
        0,
        0,
        1_000_000_000,
      ),
    };
  }

  const idempotencyKey = postgresLoyaltyRedemptionLedgerId(
    receipt.redemptionId,
  );
  const inserted = await client.query(
    `INSERT INTO point_transactions
       (user_id, source_type, source_id, base_points, multiplier,
        final_points, description, idempotency_key)
     VALUES ($1, 'loyalty_redemption', $2, $3, 1.0, $3, $4, $5)
     ON CONFLICT (idempotency_key) DO NOTHING
     RETURNING id`,
    [
      user.postgresUserId,
      rewardId.slice(0, 100),
      -receipt.cost,
      'Loyalty reward redemption',
      idempotencyKey,
    ],
  );

  if (inserted.rowCount === 1) {
    const updated = await client.query(
      `UPDATE user_profiles
       SET loyalty_points = $1,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $2`,
      [receipt.remainingBalance, user.postgresUserId],
    );
    if (updated.rowCount !== 1) {
      throw new LoyaltyRedemptionError(
        'profile-missing',
        'User profile is missing.',
      );
    }
    return receipt;
  }

  const existing = await client.query(
    `SELECT user_id
     FROM point_transactions
     WHERE idempotency_key = $1`,
    [idempotencyKey],
  );
  if (
    existing.rowCount !== 1 ||
    String(existing.rows[0].user_id) !== user.postgresUserId
  ) {
    throw new Error('Redemption idempotency key belongs to another user.');
  }

  // The Firestore receipt stores the balance at redemption time. On a replay,
  // return the current wallet so later point earnings are never hidden by an
  // older successful request.
  const current = await client.query(
    `SELECT loyalty_points
     FROM user_profiles
     WHERE user_id = $1`,
    [user.postgresUserId],
  );
  if (current.rowCount !== 1) {
    throw new LoyaltyRedemptionError(
      'profile-missing',
      'User profile is missing.',
    );
  }
  return {
    ...receipt,
    remainingBalance: configuredInteger(
      current.rows[0].loyalty_points,
      'Loyalty balance',
      0,
      0,
      1_000_000_000,
    ),
  };
}

export interface PostgresLoyaltyRefundResult {
  refunded: boolean;
  balance: number | null;
}

/**
 * Mirrors a Firestore cancellation into the wallet used by the live app.
 * A refund is allowed only when this server's matching negative ledger row
 * exists, which prevents a legacy Firestore-only redemption from minting
 * points. The positive ledger key makes every status replay safe.
 */
export async function refundPostgresLoyaltyRedemption(
  firebaseUid: string,
  redemptionId: string,
  cost: number,
): Promise<PostgresLoyaltyRefundResult> {
  if (!Number.isSafeInteger(cost) || cost < 1 || cost > 1_000_000) {
    throw new LoyaltyRedemptionError(
      'invalid-configuration',
      'Redemption cost configuration is invalid.',
    );
  }
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const profile = await client.query(
      `SELECT u.id, p.loyalty_points
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       WHERE u.firebase_uid = $1
       FOR UPDATE OF p`,
      [firebaseUid],
    );
    if (profile.rowCount !== 1) {
      throw new LoyaltyRedemptionError(
        'profile-missing',
        'User profile is missing.',
      );
    }
    const postgresUserId = String(profile.rows[0].id);
    const balance = configuredInteger(
      profile.rows[0].loyalty_points,
      'Loyalty balance',
      0,
      0,
      1_000_000_000,
    );
    const original = await client.query(
      `SELECT user_id, final_points
       FROM point_transactions
       WHERE idempotency_key = $1`,
      [postgresLoyaltyRedemptionLedgerId(redemptionId)],
    );
    if (original.rowCount === 0) {
      await client.query('COMMIT');
      return { refunded: false, balance };
    }
    if (
      original.rowCount !== 1 ||
      String(original.rows[0].user_id) !== postgresUserId ||
      Number(original.rows[0].final_points) !== -cost
    ) {
      throw new Error('The original loyalty deduction does not match this redemption.');
    }

    const refundKey = postgresLoyaltyRefundLedgerId(redemptionId);
    const inserted = await client.query(
      `INSERT INTO point_transactions
         (user_id, source_type, source_id, base_points, multiplier,
          final_points, description, idempotency_key)
       VALUES ($1, 'loyalty_redemption', $2, $3, 1.0, $3, $4, $5)
       ON CONFLICT (idempotency_key) DO NOTHING
       RETURNING id`,
      [
        postgresUserId,
        `refund:${redemptionId}`.slice(0, 100),
        cost,
        'Cancelled loyalty redemption refund',
        refundKey,
      ],
    );
    if (inserted.rowCount === 1) {
      const updated = await client.query(
        `UPDATE user_profiles
         SET loyalty_points = loyalty_points + $1,
             updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $2
         RETURNING loyalty_points`,
        [cost, postgresUserId],
      );
      if (updated.rowCount !== 1) {
        throw new LoyaltyRedemptionError(
          'profile-missing',
          'User profile is missing.',
        );
      }
      await client.query('COMMIT');
      return {
        refunded: true,
        balance: configuredInteger(
          updated.rows[0].loyalty_points,
          'Loyalty balance',
          0,
          0,
          1_000_000_000,
        ),
      };
    }

    const existingRefund = await client.query(
      `SELECT user_id
       FROM point_transactions
       WHERE idempotency_key = $1`,
      [refundKey],
    );
    if (
      existingRefund.rowCount !== 1 ||
      String(existingRefund.rows[0].user_id) !== postgresUserId
    ) {
      throw new Error('The loyalty refund key belongs to another user.');
    }
    await client.query('COMMIT');
    return { refunded: false, balance };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Redeems through the self-hosted API while retaining the legacy Firestore
 * catalogue/claim/redemption contract. PostgreSQL owns the wallet shown by
 * the current app, so its profile row stays locked until the Firestore
 * transaction and the idempotent local ledger write are both complete.
 */
export async function redeemLoyaltyReward(
  user: RedeemingUser,
  rewardId: string,
  idempotencyKey: string,
): Promise<LoyaltyRedemptionReceipt> {
  const redemptionId = loyaltyRedemptionId(
    user.firebaseUid,
    rewardId,
    idempotencyKey,
  );
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const profile = await client.query(
      `SELECT loyalty_points
       FROM user_profiles
       WHERE user_id = $1
       FOR UPDATE`,
      [user.postgresUserId],
    );
    if (profile.rowCount !== 1) {
      throw new LoyaltyRedemptionError(
        'profile-missing',
        'User profile is missing.',
      );
    }
    const postgresBalance = configuredInteger(
      profile.rows[0].loyalty_points,
      'Loyalty balance',
      0,
      0,
      1_000_000_000,
    );

    const db = getAdminFirestore();
    const redemptionRef = db.collection('loyaltyRedemptions').doc(redemptionId);
    const transactionRef = db
      .collection('loyaltyTransactions')
      .doc(firestoreLedgerId(redemptionId));
    const claimRef = db
      .collection('loyaltyRewardClaims')
      .doc(loyaltyRewardClaimId(user.firebaseUid, rewardId));
    const rewardRef = db.collection('loyaltyRewards').doc(rewardId);
    const userRef = db.collection('users').doc(user.firebaseUid);

    const firestoreReceipt = await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(redemptionRef);
      if (existing.exists) {
        const data = existing.data()!;
        return {
          ok: true as const,
          duplicate: true,
          redemptionId,
          remainingBalance: configuredInteger(
            data.remainingBalance,
            'Stored remaining balance',
            0,
            0,
            1_000_000_000,
          ),
          stockRemaining:
            data.stockRemaining == null
              ? null
              : configuredInteger(
                  data.stockRemaining,
                  'Stored reward stock',
                  0,
                  0,
                  1_000_000,
                ),
          claimCount: configuredInteger(
            data.claimCount,
            'Stored claim count',
            1,
            1,
            100,
          ),
          cost: configuredInteger(
            data.cost,
            'Stored redemption cost',
            0,
            1,
            1_000_000,
          ),
          cancelled:
            String(data.status ?? data.deliveryStatus ?? '') === 'cancelled' ||
            data.refunded === true,
        };
      }

      const [rewardDoc, userDoc, claimDoc] = await Promise.all([
        transaction.get(rewardRef),
        transaction.get(userRef),
        transaction.get(claimRef),
      ]);
      if (!rewardDoc.exists) {
        throw new LoyaltyRedemptionError(
          'reward-not-found',
          'Reward not found.',
        );
      }
      const reward = rewardDoc.data()!;
      const legacyUser = userDoc.data() ?? {};
      const claim = claimDoc.data();
      if (legacyUser.suspended === true) {
        throw new LoyaltyRedemptionError(
          'account-suspended',
          'This account is suspended.',
        );
      }
      if (!rewardIsAvailableConfiguration(reward.enabled, reward.status)) {
        throw new LoyaltyRedemptionError(
          'reward-unavailable',
          'This reward is not available.',
        );
      }

      const nowMs = Date.now();
      const availableFrom = reward.availableFrom ?? reward.startsAt;
      const availableUntil = reward.availableUntil ?? reward.endsAt;
      if (
        availableFrom != null &&
        nowMs < storedTimestampMillis(availableFrom, 'Reward start')
      ) {
        throw new LoyaltyRedemptionError(
          'reward-not-started',
          'This reward is not available yet.',
        );
      }
      if (
        availableUntil != null &&
        nowMs >= storedTimestampMillis(availableUntil, 'Reward end')
      ) {
        throw new LoyaltyRedemptionError(
          'reward-ended',
          'This reward is no longer available.',
        );
      }
      if (reward.memberOnly === true && !user.isYouTubeMember) {
        throw new LoyaltyRedemptionError(
          'members-only',
          'This reward is for verified members.',
        );
      }

      const cost = configuredInteger(
        reward.cost,
        'Reward cost',
        0,
        1,
        1_000_000,
      );
      const perUserLimit = configuredInteger(
        reward.perUserLimit,
        'Per-user limit',
        1,
        1,
        100,
      );
      const claimCount = configuredInteger(
        claim?.claimCount,
        'Claim count',
        0,
        0,
        100,
      );
      const unlimitedStock = reward.unlimitedStock === true;
      if (!unlimitedStock && reward.stock == null) {
        throw new LoyaltyRedemptionError(
          'invalid-configuration',
          'Reward stock configuration is invalid.',
        );
      }
      const stock = unlimitedStock
        ? null
        : configuredInteger(
            reward.stock,
            'Reward stock',
            0,
            0,
            1_000_000,
          );
      const next = calculateLoyaltyRedemption({
        balance: postgresBalance,
        cost,
        stock,
        claimCount,
        perUserLimit,
      });
      if (typeof reward.title !== 'string' || !reward.title.trim()) {
        throw new LoyaltyRedemptionError(
          'invalid-configuration',
          'Reward title configuration is invalid.',
        );
      }

      const rewardTitle = reward.title.trim().slice(0, 120);
      const createdAt = firebaseAdmin.firestore.FieldValue.serverTimestamp();
      transaction.set(
        userRef,
        {
          email: user.email ?? legacyUser.email ?? '',
          username: user.username,
          displayName: user.displayName,
          isYouTubeMember: user.isYouTubeMember,
          membershipMultiplier: user.isYouTubeMember ? 2 : 1,
          loyaltyPoints: next.remainingBalance,
          updatedAt: createdAt,
          ...(userDoc.exists ? {} : { createdAt }),
        },
        { merge: true },
      );
      if (next.stockRemaining !== null) {
        transaction.update(rewardRef, {
          stock: next.stockRemaining,
          updatedAt: createdAt,
        });
      }
      transaction.set(
        claimRef,
        {
          userId: user.firebaseUid,
          rewardId,
          claimCount: next.claimCount,
          updatedAt: createdAt,
          ...(claimDoc.exists ? {} : { createdAt }),
        },
        { merge: true },
      );
      transaction.create(redemptionRef, {
        userId: user.firebaseUid,
        userDisplayName: user.displayName.slice(0, 120),
        username: user.username.slice(0, 24),
        userEmail: (user.email ?? '').slice(0, 254),
        rewardId,
        rewardTitle,
        cost,
        status: 'pending',
        deliveryStatus: 'pending',
        idempotencyKey,
        remainingBalance: next.remainingBalance,
        stockRemaining: next.stockRemaining,
        claimCount: next.claimCount,
        createdAt,
      });
      transaction.create(transactionRef, {
        userId: user.firebaseUid,
        rewardId,
        redemptionId,
        type: 'redemption',
        delta: -cost,
        balanceAfter: next.remainingBalance,
        createdAt,
      });
      return {
        ok: true as const,
        duplicate: false,
        redemptionId,
        ...next,
        cost,
      };
    });

    const receipt = await persistPostgresRedemption(
      client,
      user,
      rewardId,
      firestoreReceipt,
    );
    await client.query('COMMIT');
    return receipt;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
