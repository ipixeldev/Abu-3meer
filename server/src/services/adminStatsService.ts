import { query } from '../db/pool.js';

export const adminDashboardStatsPath = '/admin/dashboard/stats';

type QueryResult = {
  rows: Array<Record<string, unknown>>;
};

export type AdminStatsQuery = (sql: string) => Promise<QueryResult>;

function count(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : 0;
}

/**
 * Aggregate-only dashboard data. “Active user” is deliberately defined as an
 * active account whose server-maintained users.last_active_at timestamp falls
 * within the stated rolling window. No user identity or private profile data
 * is returned by this endpoint.
 */
export async function getAdminDashboardStats(
  runQuery: AdminStatsQuery = query,
) {
  const result = await runQuery(
    `WITH user_counts AS (
       SELECT
         COUNT(*) AS total_users,
         COUNT(*) FILTER (WHERE account_status = 'active') AS active_accounts,
         COUNT(*) FILTER (
           WHERE account_status = 'active'
             AND last_active_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
         ) AS active_users_24h,
         COUNT(*) FILTER (
           WHERE account_status = 'active'
             AND last_active_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
         ) AS active_users_7d,
         COUNT(*) FILTER (
           WHERE account_status = 'active'
             AND last_active_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
         ) AS active_users_30d,
         COUNT(*) FILTER (
           WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
         ) AS new_users_30d,
         COUNT(*) FILTER (WHERE account_status = 'suspended') AS suspended_users,
         COUNT(*) FILTER (WHERE account_status = 'banned') AS banned_users
       FROM users
     ),
     role_flags AS (
       SELECT
         u.id AS user_id,
         COALESCE(
           yl.is_member = TRUE
           AND yl.verification_source = 'admin_snapshot'
           AND yl.snapshot_import_id = snapshot_state.active_import_id
           AND snapshot_import.id IS NOT NULL
           AND approved_claim.id IS NOT NULL,
           FALSE
         ) AS is_member,
         COALESCE(bool_or(ur.role_id = 'moderator'), FALSE) AS is_moderator,
         COALESCE(bool_or(ur.role_id = 'admin'), FALSE) AS is_admin,
         COALESCE(bool_or(ur.role_id = 'super_admin'), FALSE) AS is_super_admin
       FROM users u
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
       LEFT JOIN youtube_membership_snapshot_state snapshot_state
         ON snapshot_state.singleton = TRUE
       LEFT JOIN youtube_membership_snapshot_imports snapshot_import
         ON snapshot_import.id = snapshot_state.active_import_id
        AND snapshot_import.expires_at > CURRENT_TIMESTAMP
       LEFT JOIN youtube_channel_claims approved_claim
         ON approved_claim.user_id = u.id
        AND approved_claim.youtube_channel_id = yl.youtube_channel_id
        AND approved_claim.status = 'approved'
       GROUP BY u.id, yl.user_id, snapshot_state.active_import_id,
                snapshot_import.id, approved_claim.id
     ),
     role_counts AS (
       SELECT
         COUNT(*) FILTER (
           WHERE NOT is_member
             AND NOT is_moderator
             AND NOT is_admin
             AND NOT is_super_admin
         ) AS fans,
         COUNT(*) FILTER (WHERE is_member) AS members,
         COUNT(*) FILTER (WHERE is_moderator) AS moderators,
         COUNT(*) FILTER (WHERE is_admin) AS admins,
         COUNT(*) FILTER (WHERE is_super_admin) AS super_admins
       FROM role_flags
     ),
     membership_counts AS (
       SELECT
         (SELECT COUNT(*)
          FROM youtube_account_links
          WHERE youtube_channel_id IS NOT NULL) AS linked_youtube_channels,
         (SELECT COUNT(*)
          FROM youtube_account_links link
          JOIN youtube_channel_claims approved_claim
            ON approved_claim.user_id = link.user_id
           AND approved_claim.youtube_channel_id = link.youtube_channel_id
           AND approved_claim.status = 'approved'
          JOIN youtube_membership_snapshot_state snapshot_state
            ON snapshot_state.singleton = TRUE
          JOIN youtube_membership_snapshot_imports snapshot_import
            ON snapshot_import.id = snapshot_state.active_import_id
           AND snapshot_import.expires_at > CURRENT_TIMESTAMP
          JOIN youtube_membership_snapshot_members snapshot_member
            ON snapshot_member.import_id = snapshot_state.active_import_id
           AND snapshot_member.youtube_channel_id = link.youtube_channel_id
           AND snapshot_member.status = 'active'
          WHERE link.is_member = TRUE
            AND link.verification_source = 'admin_snapshot'
            AND link.snapshot_import_id = snapshot_state.active_import_id
         ) AS active_memberships
     ),
     engagement_counts AS (
       SELECT
         (SELECT COUNT(*) FROM predictions) AS predictions,
         (SELECT COUNT(*) FROM challenge_submissions) AS challenge_submissions,
         (SELECT COUNT(*) FROM challenge_submissions WHERE is_correct = TRUE)
           AS correct_challenge_submissions
     ),
     content_counts AS (
       SELECT
         (SELECT COUNT(*) FROM matches) AS matches,
         (SELECT COUNT(*) FROM challenges) AS challenges,
         (SELECT COUNT(*)
          FROM videos
          WHERE is_unlisted = TRUE OR member_only = TRUE) AS exclusive_videos
     )
     SELECT *
     FROM user_counts, role_counts, membership_counts,
          engagement_counts, content_counts`,
  );

  const row = result.rows[0] ?? {};
  const totalUsers = count(row.total_users);
  const activeUsersToday = count(row.active_users_24h);
  const activeUsers = count(row.active_users_30d);
  const fans = count(row.fans);
  const members = count(row.members);
  const moderators = count(row.moderators);
  const admins = count(row.admins);
  const superAdmins = count(row.super_admins);
  const suspendedUsers = count(row.suspended_users);
  const linkedYouTubeChannels = count(row.linked_youtube_channels);
  const activeMemberships = count(row.active_memberships);

  return {
    generatedAt: new Date().toISOString(),
    // Canonical compact fields used by the Admin Studio dashboard.
    totalUsers,
    activeUsers,
    activeToday: activeUsersToday,
    activeUsersToday,
    fans,
    members,
    moderators,
    admins,
    superAdmins,
    suspendedUsers,
    linkedYouTubeChannels,
    activeMemberships,
    activeUserDefinition: {
      source: 'users.last_active_at',
      accountStatus: 'active',
      primaryWindowDays: 30,
    },
    users: {
      total: totalUsers,
      activeAccounts: count(row.active_accounts),
      active24h: activeUsersToday,
      active7d: count(row.active_users_7d),
      active30d: activeUsers,
      new30d: count(row.new_users_30d),
      suspended: suspendedUsers,
      banned: count(row.banned_users),
    },
    roles: {
      fans,
      members,
      moderators,
      admins,
      superAdmins,
    },
    engagement: {
      predictions: count(row.predictions),
      challengeSubmissions: count(row.challenge_submissions),
      correctChallengeSubmissions: count(row.correct_challenge_submissions),
    },
    content: {
      matches: count(row.matches),
      challenges: count(row.challenges),
      exclusiveVideos: count(row.exclusive_videos),
    },
  };
}
