import { query } from '../db/pool.js';
import { refreshLinkedYouTubeMembership } from './youtubeMembershipService.js';

type QueryMembership = (
  text: string,
  params: unknown[],
) => Promise<{ rows: Array<{ linked: boolean; current_member: boolean }> }>;

export class ChallengeMembershipUnavailableError extends Error {
  constructor() {
    super('YouTube membership could not be verified right now. Please try again.');
    this.name = 'ChallengeMembershipUnavailableError';
  }
}

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
              AND yl.snapshot_import_id = (
                SELECT active_import_id
                FROM youtube_membership_snapshot_state
                WHERE singleton = TRUE
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
    throw new ChallengeMembershipUnavailableError();
  }

  const after = (await read()).rows[0];
  if (!after?.linked) return false;
  return after.current_member === true;
}
