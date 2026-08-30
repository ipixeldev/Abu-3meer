export const adminChallengeStatuses = [
  'draft',
  'scheduled',
  'open',
  'disabled',
  'ended',
  'closed',
  'archived',
] as const;

export type AdminChallengeStatus = typeof adminChallengeStatuses[number];

export const redemptionStatuses = [
  'pending',
  'contacted',
  'fulfilled',
  'cancelled',
] as const;

export type AdminRedemptionStatus = typeof redemptionStatuses[number];

export function canTransitionRedemptionStatus(
  from: AdminRedemptionStatus,
  to: AdminRedemptionStatus,
): boolean {
  if (from === to) return true;
  if (from === 'pending') {
    return to === 'contacted' || to === 'fulfilled' || to === 'cancelled';
  }
  if (from === 'contacted') {
    return to === 'pending' || to === 'fulfilled' || to === 'cancelled';
  }
  return false;
}

export interface LoyaltyRefundState {
  balance: number;
  cost: number;
  stock: number | null;
  claimCount: number;
}

export interface LoyaltyRefundResult {
  balance: number;
  stock: number | null;
  claimCount: number;
}

export function calculateLoyaltyRefund(
  state: LoyaltyRefundState,
): LoyaltyRefundResult {
  const integers = [state.balance, state.cost, state.claimCount];
  if (
    !integers.every(Number.isSafeInteger) ||
    state.balance < 0 ||
    state.cost < 1 ||
    state.claimCount < 1 ||
    (state.stock !== null &&
      (!Number.isSafeInteger(state.stock) || state.stock < 0))
  ) {
    throw new Error('Invalid loyalty refund state.');
  }
  const balance = state.balance + state.cost;
  const stock = state.stock === null ? null : state.stock + 1;
  if (
    !Number.isSafeInteger(balance) ||
    (stock !== null && !Number.isSafeInteger(stock))
  ) {
    throw new Error('Loyalty refund exceeds the supported range.');
  }
  return { balance, stock, claimCount: state.claimCount - 1 };
}

export function finiteInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number {
  const number = typeof value === 'number' ? value : Number(value);
  if (
    !Number.isSafeInteger(number) ||
    number < minimum ||
    number > maximum
  ) {
    throw new Error(`${field} is invalid.`);
  }
  return number;
}

export function safeDocumentId(value: string, field = 'Document'): string {
  const id = value.trim();
  if (!id || id.length > 150 || id.includes('/')) {
    throw new Error(`${field} ID is invalid.`);
  }
  return id;
}

export type AdminContentQueryExecutor = (
  text: string,
  params?: unknown[],
) => Promise<{
  rowCount: number | null;
  rows: Array<Record<string, unknown>>;
}>;

export type PlayerCardDeletionResult =
  | { status: 'deleted'; card: Record<string, unknown> }
  | { status: 'linked'; challengeId: string; challengeStatus: string }
  | { status: 'claimed'; claimCount: number }
  | { status: 'missing' };

export type PlayerCardStatusUpdateResult =
  | { status: 'updated'; card: Record<string, unknown> }
  | { status: 'linked'; challengeId: string; challengeStatus: string }
  | { status: 'missing' };

export type ChallengeRetirementResult =
  | {
      status: 'retired';
      challenge: Record<string, unknown>;
      playerCardIds: string[];
    }
  | { status: 'in_use'; submissionCount: number; claimCount: number }
  | { status: 'missing' };

export type PlayerCardDefinitionInput = {
  id: string;
  playerName: string;
  normalizedPlayerName: string;
  playerNameAr: string;
  imageUrl: string;
  teamName: string;
  teamLogoUrl: string;
  position: string;
  rating: number;
  rarity: string;
  stats: Record<string, number>;
  description: string;
  descriptionAr: string;
  enabled: boolean;
};

/**
 * Creates or edits a Player Card without accepting a challenge relationship.
 * Challenge creation is the only operation allowed to establish that link.
 * Existing enabled/linkage state is also preserved during an edit so lifecycle
 * changes must pass through the guarded status endpoint.
 */
export async function upsertPlayerCardDefinition(
  execute: AdminContentQueryExecutor,
  card: PlayerCardDefinitionInput,
): Promise<Record<string, unknown>> {
  const result = await execute(
    `INSERT INTO player_cards
       (id, challenge_id, player_name, normalized_player_name, team,
        position, card_tier, card_image_url, player_name_ar, team_logo_url,
        rating, rarity, stats, description, description_ar, enabled,
        source_challenge_id, updated_at)
     VALUES
       ($1, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $6, $11, $12,
        $13, $14, '', CURRENT_TIMESTAMP)
     ON CONFLICT (id) DO UPDATE SET
       player_name = EXCLUDED.player_name,
       normalized_player_name = EXCLUDED.normalized_player_name,
       team = EXCLUDED.team,
       position = EXCLUDED.position,
       card_tier = EXCLUDED.card_tier,
       card_image_url = EXCLUDED.card_image_url,
       player_name_ar = EXCLUDED.player_name_ar,
       team_logo_url = EXCLUDED.team_logo_url,
       rating = EXCLUDED.rating,
       rarity = EXCLUDED.rarity,
       stats = EXCLUDED.stats,
       description = EXCLUDED.description,
       description_ar = EXCLUDED.description_ar,
       updated_at = CURRENT_TIMESTAMP
     RETURNING id, enabled, source_challenge_id`,
    [
      card.id,
      card.playerName,
      card.normalizedPlayerName,
      card.teamName,
      card.position,
      card.rarity,
      card.imageUrl,
      card.playerNameAr,
      card.teamLogoUrl,
      card.rating,
      JSON.stringify(card.stats),
      card.description,
      card.descriptionAr,
      card.enabled,
    ],
  );
  return result.rows[0];
}

/**
 * Disabling a card assigned to any challenge would let a later status change
 * republish a challenge whose reward can no longer be collected. Preserve the
 * relationship for the whole challenge lifecycle and keep the guard atomic so
 * concurrent challenge creation cannot bypass it.
 */
export async function setPlayerCardEnabledState(
  execute: AdminContentQueryExecutor,
  playerCardId: string,
  enabled: boolean,
): Promise<PlayerCardStatusUpdateResult> {
  const result = await execute(
    `UPDATE player_cards pc
     SET enabled = $1, updated_at = CURRENT_TIMESTAMP
     WHERE pc.id = $2
       AND (
         $1 = TRUE
         OR NOT EXISTS (
           SELECT 1
           FROM challenges challenge
           WHERE (
             challenge.id = NULLIF(pc.source_challenge_id, '')
             OR challenge.id = pc.challenge_id
           )
         )
       )
     RETURNING pc.id, pc.enabled, pc.source_challenge_id`,
    [enabled, playerCardId],
  );
  if ((result.rowCount ?? 0) > 0) {
    return { status: 'updated', card: result.rows[0] };
  }

  const retained = await execute(
    `SELECT pc.id,
            challenge.id AS active_challenge_id,
            challenge.status AS active_challenge_status
     FROM player_cards pc
     LEFT JOIN LATERAL (
       SELECT linked.id, linked.status
       FROM challenges linked
       WHERE (
         linked.id = NULLIF(pc.source_challenge_id, '')
         OR linked.id = pc.challenge_id
       )
       LIMIT 1
     ) challenge ON TRUE
     WHERE pc.id = $1`,
    [playerCardId],
  );
  if (!(retained.rowCount ?? 0)) return { status: 'missing' };
  const challengeId = String(retained.rows[0].active_challenge_id ?? '');
  if (challengeId) {
    return {
      status: 'linked',
      challengeId,
      challengeStatus: String(retained.rows[0].active_challenge_status ?? ''),
    };
  }
  return { status: 'missing' };
}

/**
 * Deletes an unclaimed, unlinked Player Card. Claimed cards must be retained,
 * and linked cards must survive every challenge state so an archived/closed
 * challenge can never be reopened without its collectible reward.
 */
export async function deletePlayerCardDefinition(
  execute: AdminContentQueryExecutor,
  playerCardId: string,
): Promise<PlayerCardDeletionResult> {
  const result = await execute(
    `DELETE FROM player_cards
     WHERE id = $1
       AND NOT EXISTS (
         SELECT 1 FROM player_card_claims
         WHERE player_card_id = player_cards.id
       )
       AND NOT EXISTS (
         SELECT 1
         FROM challenges challenge
         WHERE (
           challenge.id = NULLIF(player_cards.source_challenge_id, '')
           OR challenge.id = player_cards.challenge_id
           )
       )
     RETURNING id, player_name, enabled, source_challenge_id`,
    [playerCardId],
  );
  if ((result.rowCount ?? 0) > 0) {
    return { status: 'deleted', card: result.rows[0] };
  }
  const retained = await execute(
    `SELECT pc.id,
            COUNT(claim.id)::integer AS claim_count,
            MAX(challenge.id) AS active_challenge_id,
            MAX(challenge.status) AS active_challenge_status
     FROM player_cards pc
     LEFT JOIN player_card_claims claim ON claim.player_card_id = pc.id
     LEFT JOIN challenges challenge
       ON (
         challenge.id = NULLIF(pc.source_challenge_id, '')
         OR challenge.id = pc.challenge_id
       )
     WHERE pc.id = $1
     GROUP BY pc.id`,
    [playerCardId],
  );
  if (!(retained.rowCount ?? 0)) return { status: 'missing' };
  const challengeId = String(retained.rows[0].active_challenge_id ?? '');
  if (challengeId) {
    return {
      status: 'linked',
      challengeId,
      challengeStatus: String(retained.rows[0].active_challenge_status ?? ''),
    };
  }
  return {
    status: 'claimed',
    claimCount: Number(retained.rows[0].claim_count ?? 0),
  };
}

/**
 * Permanently retires unused challenge content and releases its Player Card.
 *
 * A challenge row is locked first; submissions take the same row lock, so the
 * usage check and deletion cannot race a fan answer. Content with history is
 * retained for points/audit integrity and can be archived instead.
 */
export async function retireChallengeDefinition(
  execute: AdminContentQueryExecutor,
  challengeId: string,
): Promise<ChallengeRetirementResult> {
  const challenge = await execute(
    `SELECT id, title, kind, status
     FROM challenges
     WHERE id = $1
     FOR UPDATE`,
    [challengeId],
  );
  if (!(challenge.rowCount ?? 0)) return { status: 'missing' };

  const linkedCards = await execute(
    `SELECT id
     FROM player_cards
     WHERE source_challenge_id = $1 OR challenge_id = $1
     ORDER BY id
     FOR UPDATE`,
    [challengeId],
  );
  const usage = await execute(
    `SELECT
       (SELECT COUNT(*)::integer
        FROM challenge_submissions
        WHERE challenge_id = $1) AS submission_count,
       (SELECT COUNT(*)::integer
        FROM player_card_claims claim
        JOIN player_cards card ON card.id = claim.player_card_id
        WHERE card.source_challenge_id = $1 OR card.challenge_id = $1)
         AS claim_count`,
    [challengeId],
  );
  const submissionCount = Number(usage.rows[0]?.submission_count ?? 0);
  const claimCount = Number(usage.rows[0]?.claim_count ?? 0);
  if (submissionCount > 0 || claimCount > 0) {
    return { status: 'in_use', submissionCount, claimCount };
  }

  await execute(
    `UPDATE player_cards
     SET source_challenge_id = '',
         challenge_id = NULL,
         updated_at = CURRENT_TIMESTAMP
     WHERE source_challenge_id = $1 OR challenge_id = $1`,
    [challengeId],
  );
  await execute('DELETE FROM challenges WHERE id = $1', [challengeId]);
  return {
    status: 'retired',
    challenge: challenge.rows[0],
    playerCardIds: linkedCards.rows.map((row) => String(row.id)),
  };
}

/** Removes the launch-popup campaign instead of leaving a disabled ghost row. */
export async function resetLaunchAnnouncementSetting(
  execute: AdminContentQueryExecutor,
): Promise<Record<string, unknown> | null> {
  const result = await execute(
    `DELETE FROM platform_settings
     WHERE key = 'launchAnnouncement'
     RETURNING key, value`,
  );
  return (result.rowCount ?? 0) > 0 ? result.rows[0] : null;
}

function legacyIdComponent(value: string): string {
  const encoded = encodeURIComponent(value);
  return `${encoded.length}-${encoded}`;
}

/** Matches the IDs created by the existing Firebase loyalty callable. */
export function loyaltyRewardClaimId(userId: string, rewardId: string): string {
  return `claim_${[userId, rewardId].map(legacyIdComponent).join('_')}`;
}

/** Matches the idempotent refund receipt used by the Firebase callable. */
export function loyaltyRefundTransactionId(redemptionId: string): string {
  return `refund_${legacyIdComponent(redemptionId)}`;
}
