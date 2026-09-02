import { getClient, query } from '../db/pool.js';
import { normalizeYouTubeChannelId } from './youtubeChannelId.js';

export type YouTubeChannelClaimDecision = 'approve' | 'reject' | 'revoke';
export type YouTubeChannelClaimStatus =
  | 'pending'
  | 'active'
  | 'lapsed'
  | 'rejected'
  | 'revoked'
  | 'superseded';

export type YouTubeChannelClaim = {
  id: string;
  userId: string;
  youtubeChannelId: string;
  status: YouTubeChannelClaimStatus;
  submittedAt: string;
  reviewedAt: string | null;
  reviewedByUserId: string | null;
  reviewReason: string | null;
  displayName?: string;
  username?: string;
  email?: string | null;
};

export class YouTubeChannelClaimError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus = 400,
    message = 'The YouTube channel claim could not be completed.',
  ) {
    super(message);
    this.name = 'YouTubeChannelClaimError';
  }
}

const claimProjection = `
  c.id, c.user_id, c.youtube_channel_id, c.submitted_at,
  c.reviewed_at, c.reviewed_by_user_id, c.review_reason,
  u.display_name, u.username, u.email,
  CASE
    WHEN c.status = 'approved' THEN
      CASE WHEN EXISTS (
        SELECT 1
        FROM youtube_membership_snapshot_state snapshot_state
        JOIN youtube_membership_snapshot_imports snapshot_import
          ON snapshot_import.id = snapshot_state.active_import_id
         AND snapshot_import.expires_at > CURRENT_TIMESTAMP
        JOIN youtube_membership_snapshot_members snapshot_member
          ON snapshot_member.import_id = snapshot_state.active_import_id
         AND snapshot_member.youtube_channel_id = c.youtube_channel_id
         AND snapshot_member.status = 'active'
        WHERE snapshot_state.singleton = TRUE
      ) THEN 'active' ELSE 'lapsed' END
    ELSE c.status
  END AS effective_status`;

function mapClaim(
  row: any,
  options: { includeReviewDetails?: boolean } = {},
): YouTubeChannelClaim {
  const includeReviewDetails = options.includeReviewDetails !== false;
  return {
    id: row.id,
    userId: row.user_id,
    youtubeChannelId: row.youtube_channel_id,
    status: row.effective_status,
    submittedAt: new Date(row.submitted_at).toISOString(),
    reviewedAt: row.reviewed_at
      ? new Date(row.reviewed_at).toISOString()
      : null,
    reviewedByUserId: includeReviewDetails
      ? row.reviewed_by_user_id ?? null
      : null,
    reviewReason: includeReviewDetails ? row.review_reason ?? null : null,
    ...(row.display_name == null ? {} : { displayName: row.display_name }),
    ...(row.username == null ? {} : { username: row.username }),
    ...(row.email === undefined ? {} : { email: row.email ?? null }),
  };
}

async function readLatestClaim(userId: string): Promise<YouTubeChannelClaim | null> {
  const result = await query(
    `SELECT ${claimProjection}
     FROM youtube_channel_claims c
     JOIN users u ON u.id = c.user_id
     WHERE c.user_id = $1
     ORDER BY
       CASE c.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
       c.submitted_at DESC
     LIMIT 1`,
    [userId],
  );
  // Staff audit notes and reviewer identities are not claimant-visible.
  return result.rows[0]
    ? mapClaim(result.rows[0], { includeReviewDetails: false })
    : null;
}

/**
 * Records an untrusted user claim. This function deliberately never writes a
 * membership flag or the account-links table.
 */
export async function submitYouTubeChannelClaim(input: {
  userId: string;
  channel: string;
}): Promise<YouTubeChannelClaim> {
  const channelId = normalizeYouTubeChannelId(input.channel);
  if (!channelId) {
    throw new YouTubeChannelClaimError(
      'youtube_channel_invalid',
      400,
      'Enter a YouTube channel ID beginning with UC or its full youtube.com/channel/UC… URL.',
    );
  }

  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-channel-claim:user:${input.userId}`],
    );
    // Submitting a replacement can revoke an already-approved link, so it
    // uses the same exclusive lock as staff decisions and snapshot imports.
    await client.query(
      `SELECT pg_advisory_xact_lock(
         hashtextextended('youtube-membership-snapshot-import', 0)
       )`,
    );
    const channelOwner = await client.query(
      `SELECT user_id
       FROM youtube_channel_claims
       WHERE youtube_channel_id = $1 AND status = 'approved'
       FOR UPDATE`,
      [channelId],
    );
    if (
      channelOwner.rows[0] &&
      channelOwner.rows[0].user_id !== input.userId
    ) {
      throw new YouTubeChannelClaimError(
        'youtube_channel_already_claimed',
        409,
        'This YouTube channel is already approved for another account.',
      );
    }

    const current = await client.query(
      `SELECT id, youtube_channel_id, status
       FROM youtube_channel_claims
       WHERE user_id = $1 AND status IN ('pending', 'approved')
       ORDER BY submitted_at DESC
       FOR UPDATE`,
      [input.userId],
    );
    const identical = current.rows.find(
      (row) => row.youtube_channel_id === channelId,
    );
    if (identical) {
      await client.query('COMMIT');
      const existing = await readLatestClaim(input.userId);
      if (existing) return existing;
      throw new YouTubeChannelClaimError('youtube_claim_not_found', 404);
    }

    const approvedClaim = current.rows.find((row) => row.status === 'approved');
    if (current.rowCount) {
      await client.query(
        `UPDATE youtube_channel_claims
         SET status = 'superseded',
             reviewed_at = CURRENT_TIMESTAMP,
             review_reason = 'Superseded by a newer user claim.',
             approved_snapshot_import_id = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $1 AND status IN ('pending', 'approved')`,
        [input.userId],
      );
      await client.query(
        `DELETE FROM youtube_account_links WHERE user_id = $1`,
        [input.userId],
      );
      await client.query(
        `UPDATE users
         SET is_youtube_member = FALSE,
             youtube_channel_id = NULL,
             youtube_member_since = NULL,
             youtube_membership_verified_at = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [input.userId],
      );
      await client.query(
        `DELETE FROM user_roles WHERE user_id = $1 AND role_id = 'member'`,
        [input.userId],
      );
      if (approvedClaim) {
        await client.query(
          `INSERT INTO membership_history
             (user_id, status, verified_at, expires_at, metadata)
           VALUES ($1, 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
                   jsonb_build_object(
                     'source', 'youtube_channel_claim_replaced',
                     'previousYoutubeChannelId', $2::text,
                     'replacementYoutubeChannelId', $3::text
                   ))`,
          [input.userId, approvedClaim.youtube_channel_id, channelId],
        );
      }
    }

    await client.query(
      `INSERT INTO youtube_channel_claims (user_id, youtube_channel_id)
       VALUES ($1, $2)`,
      [input.userId, channelId],
    );
    await client.query(
      `UPDATE youtube_membership_snapshot_imports snapshot_import
       SET matched_user_count = (
         SELECT COUNT(*)::integer
         FROM youtube_account_links link
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = link.user_id
          AND approved_claim.youtube_channel_id = link.youtube_channel_id
          AND approved_claim.status = 'approved'
         WHERE link.is_member = TRUE
           AND link.snapshot_import_id = snapshot_import.id
       )
       WHERE snapshot_import.id = (
         SELECT active_import_id
         FROM youtube_membership_snapshot_state
         WHERE singleton = TRUE
       )`,
    );
    await client.query('COMMIT');
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (error instanceof YouTubeChannelClaimError) throw error;
    if (error?.code === '23505') {
      throw new YouTubeChannelClaimError(
        'youtube_channel_already_claimed',
        409,
        'This YouTube channel is already approved for another account.',
      );
    }
    throw error;
  } finally {
    client.release();
  }

  const claim = await readLatestClaim(input.userId);
  if (!claim) throw new YouTubeChannelClaimError('youtube_claim_not_found', 404);
  return claim;
}

export function getMyYouTubeChannelClaim(
  userId: string,
): Promise<YouTubeChannelClaim | null> {
  return readLatestClaim(userId);
}

export async function listYouTubeChannelClaims(input: {
  status?: 'pending' | 'approved' | 'rejected' | 'revoked' | 'superseded';
  limit?: number;
} = {}): Promise<YouTubeChannelClaim[]> {
  const limit = Math.min(200, Math.max(1, input.limit ?? 100));
  const result = await query(
    `SELECT ${claimProjection}
     FROM youtube_channel_claims c
     JOIN users u ON u.id = c.user_id
     WHERE ($1::varchar IS NULL OR c.status = $1)
     ORDER BY
       CASE c.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,
       c.submitted_at ASC
     LIMIT $2`,
    [input.status ?? null, limit],
  );
  return result.rows.map((row) => mapClaim(row));
}

/**
 * Staff approval is the ownership-verification boundary. Approval, the unique
 * account link, member role, and audit receipt commit atomically.
 */
export async function decideYouTubeChannelClaim(input: {
  claimId: string;
  decision: YouTubeChannelClaimDecision;
  reason: string;
  reviewedByUserId: string;
  ipAddress?: string | null;
  userAgent?: string | null;
}): Promise<YouTubeChannelClaim> {
  const reason = input.reason.trim();
  if (reason.length < 3 || reason.length > 500) {
    throw new YouTubeChannelClaimError(
      'youtube_claim_reason_required',
      400,
      'Enter an audit reason between 3 and 500 characters.',
    );
  }
  const client = await getClient();
  let claimUserId = '';
  try {
    await client.query('BEGIN');
    // Serialize claim decisions with full snapshot replacements. Otherwise a
    // decision could approve against a snapshot while another transaction is
    // superseding it.
    await client.query(
      `SELECT pg_advisory_xact_lock(
         hashtextextended('youtube-membership-snapshot-import', 0)
       )`,
    );
    const claimResult = await client.query(
      `SELECT id, user_id, youtube_channel_id, status
       FROM youtube_channel_claims
       WHERE id = $1
       FOR UPDATE`,
      [input.claimId],
    );
    const claim = claimResult.rows[0];
    if (!claim) {
      throw new YouTubeChannelClaimError('youtube_claim_not_found', 404);
    }
    claimUserId = claim.user_id;
    if (claim.user_id === input.reviewedByUserId) {
      throw new YouTubeChannelClaimError(
        'youtube_claim_self_review_forbidden',
        403,
        'A different authorized staff account must review this channel claim.',
      );
    }

    if (input.decision === 'revoke') {
      if (claim.status !== 'approved') {
        throw new YouTubeChannelClaimError(
          'youtube_claim_not_approved',
          409,
          'Only an approved claim can be revoked.',
        );
      }
      await client.query(
        `UPDATE youtube_channel_claims
         SET status = 'revoked', reviewed_at = CURRENT_TIMESTAMP,
             reviewed_by_user_id = $2, review_reason = $3,
             approved_snapshot_import_id = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [claim.id, input.reviewedByUserId, reason],
      );
      await client.query(
        `DELETE FROM youtube_account_links
         WHERE user_id = $1 AND youtube_channel_id = $2`,
        [claim.user_id, claim.youtube_channel_id],
      );
      await client.query(
        `UPDATE users
         SET is_youtube_member = FALSE, youtube_channel_id = NULL,
             youtube_member_since = NULL,
             youtube_membership_verified_at = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [claim.user_id],
      );
      await client.query(
        `DELETE FROM user_roles WHERE user_id = $1 AND role_id = 'member'`,
        [claim.user_id],
      );
      await client.query(
        `INSERT INTO membership_history
           (user_id, status, verified_at, expires_at, metadata)
         VALUES ($1, 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
                 jsonb_build_object(
                   'source', 'admin_snapshot_claim',
                   'youtubeChannelId', $2::text,
                   'reason', $3::text
                 ))`,
        [claim.user_id, claim.youtube_channel_id, reason],
      );
    } else {
      if (claim.status !== 'pending') {
        throw new YouTubeChannelClaimError(
          'youtube_claim_already_reviewed',
          409,
          'This claim has already been reviewed.',
        );
      }
      if (input.decision === 'reject') {
        await client.query(
          `UPDATE youtube_channel_claims
           SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP,
               reviewed_by_user_id = $2, review_reason = $3,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [claim.id, input.reviewedByUserId, reason],
        );
      } else {
        const membership = await client.query(
          `SELECT snapshot_state.active_import_id,
                  snapshot_import.expires_at,
                  snapshot_member.membership_level,
                  snapshot_member.joined_at
           FROM youtube_membership_snapshot_state snapshot_state
           JOIN youtube_membership_snapshot_imports snapshot_import
             ON snapshot_import.id = snapshot_state.active_import_id
            AND snapshot_import.expires_at > CURRENT_TIMESTAMP
           JOIN youtube_membership_snapshot_members snapshot_member
             ON snapshot_member.import_id = snapshot_state.active_import_id
            AND snapshot_member.youtube_channel_id = $1
            AND snapshot_member.status = 'active'
           WHERE snapshot_state.singleton = TRUE
           FOR UPDATE OF snapshot_import, snapshot_member`,
          [claim.youtube_channel_id],
        );
        const activeMember = membership.rows[0];
        if (!activeMember) {
          throw new YouTubeChannelClaimError(
            'youtube_claim_not_active_member',
            409,
            'Approval requires this channel to be active in the latest unexpired membership CSV.',
          );
        }
        const conflictingLink = await client.query(
          `SELECT user_id FROM youtube_account_links
           WHERE youtube_channel_id = $1 AND user_id <> $2
           FOR UPDATE`,
          [claim.youtube_channel_id, claim.user_id],
        );
        if (conflictingLink.rowCount) {
          throw new YouTubeChannelClaimError(
            'youtube_channel_already_claimed',
            409,
            'This YouTube channel is already approved for another account.',
          );
        }
        await client.query(
          `INSERT INTO youtube_account_links
             (user_id, youtube_channel_id, is_member, membership_level_id,
              member_since, last_verified_at, last_attempted_at,
              last_error_code, verification_source, snapshot_import_id)
           VALUES ($1, $2, TRUE, $3, $4, CURRENT_TIMESTAMP,
                   CURRENT_TIMESTAMP, NULL, 'admin_snapshot', $5)
           ON CONFLICT (user_id) DO UPDATE SET
             youtube_channel_id = EXCLUDED.youtube_channel_id,
             is_member = TRUE,
             membership_level_id = EXCLUDED.membership_level_id,
             member_since = EXCLUDED.member_since,
             last_verified_at = CURRENT_TIMESTAMP,
             last_attempted_at = CURRENT_TIMESTAMP,
             last_error_code = NULL,
             verification_source = 'admin_snapshot',
             snapshot_import_id = EXCLUDED.snapshot_import_id,
             updated_at = CURRENT_TIMESTAMP`,
          [
            claim.user_id,
            claim.youtube_channel_id,
            activeMember.membership_level,
            activeMember.joined_at,
            activeMember.active_import_id,
          ],
        );
        await client.query(
          `UPDATE youtube_channel_claims
           SET status = 'approved', reviewed_at = CURRENT_TIMESTAMP,
               reviewed_by_user_id = $2, review_reason = $3,
               approved_snapshot_import_id = $4,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [claim.id, input.reviewedByUserId, reason, activeMember.active_import_id],
        );
        await client.query(
          `UPDATE users
           SET is_youtube_member = TRUE, youtube_channel_id = $2,
               youtube_member_since = $3,
               youtube_membership_verified_at = CURRENT_TIMESTAMP,
               updated_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [claim.user_id, claim.youtube_channel_id, activeMember.joined_at],
        );
        await client.query(
          `INSERT INTO user_roles (user_id, role_id)
           VALUES ($1, 'member') ON CONFLICT DO NOTHING`,
          [claim.user_id],
        );
        await client.query(
          `INSERT INTO membership_history
             (user_id, status, verified_at, expires_at, metadata)
           VALUES ($1, 'active', CURRENT_TIMESTAMP, $3,
                   jsonb_build_object(
                     'source', 'admin_snapshot_claim',
                     'snapshotImportId', $2::text,
                     'youtubeChannelId', $4::text
                   ))`,
          [
            claim.user_id,
            activeMember.active_import_id,
            activeMember.expires_at,
            claim.youtube_channel_id,
          ],
        );
      }
    }

    // Keep the snapshot card accurate when claims are approved or revoked,
    // rather than waiting for the next full CSV replacement.
    await client.query(
      `UPDATE youtube_membership_snapshot_imports snapshot_import
       SET matched_user_count = (
         SELECT COUNT(*)::integer
         FROM youtube_account_links link
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = link.user_id
          AND approved_claim.youtube_channel_id = link.youtube_channel_id
          AND approved_claim.status = 'approved'
         WHERE link.is_member = TRUE
           AND link.snapshot_import_id = snapshot_import.id
       )
       WHERE snapshot_import.id = (
         SELECT active_import_id
         FROM youtube_membership_snapshot_state
         WHERE singleton = TRUE
       )`,
    );

    await client.query(
      `INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id,
          before_state, after_state, ip_address, user_agent)
       VALUES ($1, $2, 'youtube_channel_claim', $3,
               $4::jsonb, $5::jsonb, $6, $7)`,
      [
        input.reviewedByUserId,
        `youtube_channel_claim_${input.decision}`,
        claim.id,
        JSON.stringify({ status: claim.status }),
        JSON.stringify({
          decision: input.decision,
          reviewedByUserId: input.reviewedByUserId,
          userId: claim.user_id,
          youtubeChannelId: claim.youtube_channel_id,
          reason,
        }),
        input.ipAddress?.slice(0, 50) ?? null,
        input.userAgent?.slice(0, 1000) ?? null,
      ],
    );
    await client.query('COMMIT');
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (error instanceof YouTubeChannelClaimError) throw error;
    if (error?.code === '23505') {
      throw new YouTubeChannelClaimError(
        'youtube_channel_already_claimed',
        409,
        'This YouTube channel is already approved for another account.',
      );
    }
    throw error;
  } finally {
    client.release();
  }

  const result = await query(
    `SELECT ${claimProjection}
     FROM youtube_channel_claims c
     JOIN users u ON u.id = c.user_id
     WHERE c.id = $1`,
    [input.claimId],
  );
  if (!result.rows[0]) {
    throw new YouTubeChannelClaimError('youtube_claim_not_found', 404);
  }
  return mapClaim(result.rows[0]);
}
