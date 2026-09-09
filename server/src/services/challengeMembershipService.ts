import { query } from '../db/pool.js';
import { refreshLinkedYouTubeMembership } from './csvMembershipService.js';
import {
  activeMemberAccessSql,
  currentYouTubeMembershipSql,
} from './subscriptionAccess.js';

type QueryMembership = (
  text: string,
  params: unknown[],
) => Promise<{ rows: Array<{
  linked: boolean;
  current_member: boolean;
  has_member_access: boolean;
}> }>;

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
            ${currentYouTubeMembershipSql('u.id')} AS current_member,
            ${activeMemberAccessSql('u.id')} AS has_member_access
     FROM users u
     LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
     WHERE u.id = $1`,
    [userId],
  );

  const before = (await read()).rows[0];
  if (before?.has_member_access === true) return true;
  if (!before?.linked) return false;

  try {
    await refreshMembership(userId);
  } catch {
    // A missing/expired CSV or reconciliation failure never blocks ordinary
    // fan XP. It fails closed to non-member/x1 for this request.
    return false;
  }

  const after = (await read()).rows[0];
  if (!after?.linked) return false;
  return after.has_member_access === true;
}
