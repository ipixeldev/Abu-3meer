import { query } from '../db/pool.js';

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
     role_counts AS (
       SELECT
         COUNT(DISTINCT user_id) FILTER (WHERE role_id = 'fan') AS fans,
         COUNT(DISTINCT user_id) FILTER (WHERE role_id = 'member') AS members,
         COUNT(DISTINCT user_id) FILTER (WHERE role_id = 'moderator') AS moderators,
         COUNT(DISTINCT user_id) FILTER (WHERE role_id = 'admin') AS admins,
         COUNT(DISTINCT user_id) FILTER (WHERE role_id = 'super_admin') AS super_admins
       FROM user_roles
     ),
     membership_counts AS (
       SELECT
         (SELECT COUNT(*)
          FROM youtube_account_links
          WHERE youtube_channel_id IS NOT NULL) AS linked_youtube_channels,
         (SELECT COUNT(*)
          FROM youtube_membership_snapshot_members
          WHERE status = 'active') AS active_memberships
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
         (SELECT COUNT(*) FROM exclusive_videos) AS exclusive_videos
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
