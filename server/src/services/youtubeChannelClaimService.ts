import { query } from '../db/pool.js';

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
};

const claimProjection = `
  c.id, c.user_id, c.youtube_channel_id, c.submitted_at, c.reviewed_at,
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

function mapClaim(row: any): YouTubeChannelClaim {
  return {
    id: row.id,
    userId: row.user_id,
    youtubeChannelId: row.youtube_channel_id,
    status: row.effective_status,
    submittedAt: new Date(row.submitted_at).toISOString(),
    reviewedAt: row.reviewed_at
      ? new Date(row.reviewed_at).toISOString()
      : null,
  };
}

/**
 * Read-only compatibility status for clients upgrading from the claim UI.
 * Channel creation/review mutations are intentionally not exposed: only the
 * Google-token verification service can create an approved ownership link.
 */
export async function getMyYouTubeChannelClaim(
  userId: string,
): Promise<YouTubeChannelClaim | null> {
  const result = await query(
    `SELECT ${claimProjection}
     FROM youtube_channel_claims c
     WHERE c.user_id = $1
     ORDER BY
       CASE c.status WHEN 'approved' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
       c.submitted_at DESC
     LIMIT 1`,
    [userId],
  );
  return result.rows[0] ? mapClaim(result.rows[0]) : null;
}
