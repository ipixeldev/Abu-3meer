import { getClient } from '../db/pool.js';

export type CsvMembershipRefreshResult = {
  status: 'verified' | 'not_member';
  isYouTubeMember: boolean;
  cached: false;
  verifiedAt: string;
};

export type YouTubeBatchRefreshResult = {
  requestedUsers: number;
  staleLinkedUsers: number;
  verified: number;
  notMember: number;
  unavailable: number;
  membershipApiRequests: 0;
};

type ReconciledRow = {
  user_id: string;
  is_member: boolean;
  was_member: boolean;
  youtube_channel_id: string;
  snapshot_expires_at: Date | null;
};

/**
 * Reconcile approved channel claims against the latest unexpired full CSV.
 * No external request is made. An absent/expired snapshot fails closed to x1
 * without preventing ordinary point awards.
 */
async function reconcileApprovedClaims(
  userIds: string[],
  now: Date,
): Promise<ReconciledRow[]> {
  const uniqueUserIds = [...new Set(userIds)].filter(Boolean);
  if (uniqueUserIds.length === 0) return [];
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const reconciled = await client.query<ReconciledRow>(
      `WITH active_snapshot AS (
         SELECT snapshot_state.active_import_id,
                snapshot_import.expires_at
         FROM youtube_membership_snapshot_state snapshot_state
         JOIN youtube_membership_snapshot_imports snapshot_import
           ON snapshot_import.id = snapshot_state.active_import_id
          AND snapshot_import.expires_at > $2
         WHERE snapshot_state.singleton = TRUE
       ), observed AS (
         SELECT link.user_id,
                link.youtube_channel_id,
                link.is_member AS was_member,
                active_snapshot.active_import_id,
                active_snapshot.expires_at AS snapshot_expires_at,
                member.membership_level,
                member.joined_at,
                (
                  claim.id IS NOT NULL
                  AND active_snapshot.active_import_id IS NOT NULL
                  AND member.youtube_channel_id IS NOT NULL
                ) AS is_member
         FROM youtube_account_links link
         LEFT JOIN youtube_channel_claims claim
           ON claim.user_id = link.user_id
          AND claim.youtube_channel_id = link.youtube_channel_id
          AND claim.status = 'approved'
         LEFT JOIN active_snapshot ON TRUE
         LEFT JOIN youtube_membership_snapshot_members member
           ON member.import_id = active_snapshot.active_import_id
          AND member.youtube_channel_id = link.youtube_channel_id
          AND member.status = 'active'
         WHERE link.user_id = ANY($1::uuid[])
       ), updated AS (
         UPDATE youtube_account_links link
         SET is_member = observed.is_member,
             membership_level_id = CASE
               WHEN observed.is_member THEN observed.membership_level ELSE NULL
             END,
             member_since = CASE
               WHEN observed.is_member THEN observed.joined_at ELSE NULL
             END,
             last_verified_at = $2,
             last_attempted_at = $2,
             last_error_code = NULL,
             verification_source = 'admin_snapshot',
             snapshot_import_id = CASE
               WHEN observed.is_member THEN observed.active_import_id ELSE NULL
             END,
             updated_at = CURRENT_TIMESTAMP
         FROM observed
         WHERE link.user_id = observed.user_id
         RETURNING link.user_id, link.is_member, observed.was_member,
                   observed.youtube_channel_id,
                   observed.snapshot_expires_at
       )
       SELECT user_id,
              is_member,
              was_member,
              youtube_channel_id,
              snapshot_expires_at
       FROM updated`,
      [uniqueUserIds, now],
    );

    const transitions = reconciled.rows.filter(
      (row) => row.was_member !== row.is_member,
    );
    if (transitions.length > 0) {
      await client.query(
        `INSERT INTO membership_history
           (user_id, status, verified_at, expires_at, metadata)
         SELECT transition.user_id,
                CASE WHEN transition.is_member THEN 'active' ELSE 'inactive' END,
                $2,
                CASE
                  WHEN transition.is_member THEN transition.snapshot_expires_at
                  ELSE $2
                END,
                jsonb_build_object(
                  'source', 'admin_snapshot_reconciliation',
                  'youtubeChannelId', transition.youtube_channel_id
                )
         FROM jsonb_to_recordset($1::jsonb) AS transition(
           user_id UUID,
           is_member BOOLEAN,
           youtube_channel_id VARCHAR(24),
           snapshot_expires_at TIMESTAMPTZ
         )`,
        [JSON.stringify(transitions), now],
      );
    }

    await client.query(
      `UPDATE users user_account
       SET is_youtube_member = link.is_member,
           youtube_channel_id = link.youtube_channel_id,
           youtube_member_since = CASE
             WHEN link.is_member THEN link.member_since ELSE NULL
           END,
           youtube_membership_verified_at = $2,
           updated_at = CURRENT_TIMESTAMP
       FROM youtube_account_links link
       WHERE user_account.id = link.user_id
         AND user_account.id = ANY($1::uuid[])`,
      [uniqueUserIds, now],
    );
    await client.query(
      `INSERT INTO user_roles (user_id, role_id)
       SELECT user_id, 'member'
       FROM youtube_account_links
       WHERE user_id = ANY($1::uuid[]) AND is_member = TRUE
       ON CONFLICT DO NOTHING`,
      [uniqueUserIds],
    );
    await client.query(
      `DELETE FROM user_roles role
       USING youtube_account_links link
       WHERE role.user_id = link.user_id
         AND role.role_id = 'member'
         AND link.user_id = ANY($1::uuid[])
         AND link.is_member = FALSE`,
      [uniqueUserIds],
    );
    await client.query('COMMIT');
    return reconciled.rows;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function refreshLinkedYouTubeMembership(
  userId: string,
  options: { now?: Date } = {},
): Promise<CsvMembershipRefreshResult> {
  const now = options.now ?? new Date();
  const rows = await reconcileApprovedClaims([userId], now);
  const isMember = rows[0]?.is_member === true;
  return {
    status: isMember ? 'verified' : 'not_member',
    isYouTubeMember: isMember,
    cached: false,
    verifiedAt: now.toISOString(),
  };
}

export async function refreshStaleLinkedYouTubeMembership(
  userId: string,
  options: { now?: Date } = {},
): Promise<CsvMembershipRefreshResult> {
  return refreshLinkedYouTubeMembership(userId, options);
}

export async function refreshStaleYouTubeMembershipsForUsers(
  userIds: string[],
  options: { now?: Date } = {},
): Promise<YouTubeBatchRefreshResult> {
  const uniqueUserIds = [...new Set(userIds)].filter(Boolean);
  const rows = await reconcileApprovedClaims(
    uniqueUserIds,
    options.now ?? new Date(),
  );
  const verified = rows.filter((row) => row.is_member === true).length;
  return {
    requestedUsers: uniqueUserIds.length,
    staleLinkedUsers: rows.length,
    verified,
    notMember: rows.length - verified,
    unavailable: 0,
    membershipApiRequests: 0,
  };
}
