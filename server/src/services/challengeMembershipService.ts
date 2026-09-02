import { query } from '../db/pool.js';
import { refreshLinkedYouTubeMembership } from './csvMembershipService.js';

type QueryMembership = (
  text: string,
  params: unknown[],
) => Promise<{ rows: Array<{ linked: boolean; current_member: boolean }> }>;

/** Resolve membership before member-gated content or an XP award. */
export async function resolveChallengeMembership(
  userId: string,
  dependencies: {
    queryMembership?: QueryMembership;
    refreshMembership?: typeof refreshLinkedYouTubeMembership;
  } = {},
): Promise<boolean> {
  const queryMembership = dependencies.queryMembership ?? query;
  const refreshMembership = dependencies.refreshMembership ??
    refreshLinkedYouTubeMembership;
  const read = () => queryMembership(
    `SELECT (yl.user_id IS NOT NULL) AS linked,
            COALESCE(
              yl.is_member = TRUE
              AND yl.verification_source = 'admin_snapshot'
              AND EXISTS (
                SELECT 1
                FROM youtube_membership_snapshot_state snapshot_state
                JOIN youtube_membership_snapshot_imports snapshot_import
                  ON snapshot_import.id = snapshot_state.active_import_id
                 AND snapshot_import.expires_at > CURRENT_TIMESTAMP
                WHERE snapshot_state.singleton = TRUE
                  AND snapshot_state.active_import_id = yl.snapshot_import_id
              )
              AND EXISTS (
                SELECT 1 FROM youtube_channel_claims claim
                WHERE claim.user_id = u.id
                  AND claim.youtube_channel_id = yl.youtube_channel_id
                  AND claim.status = 'approved'
              ),
              FALSE
            ) AS current_member
     FROM users u
     LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
     WHERE u.id = $1`,
    [userId],
  );

  const before = (await read()).rows[0];
  if (!before?.linked) return false;
  if (before.current_member) return true;

  try {
    await refreshMembership(userId);
  } catch {
    // A missing/expired CSV or reconciliation failure never blocks ordinary
    // fan XP. It fails closed to non-member/x1 for this request.
    return false;
  }

  const after = (await read()).rows[0];
  if (!after?.linked) return false;
  return after.current_member === true;
}
