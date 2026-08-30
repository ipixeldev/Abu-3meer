import { query } from '../db/pool.js';
import { getCachedJson, setCachedJson } from '../redis/client.js';

export interface LeaderboardEntry {
  userId: string;
  rank: number;
  points: number;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  supportedTeam: string;
  isYouTubeMember: boolean;
}

export async function getTopLeaderboard(period: 'monthly' | 'season', limit: number = 100): Promise<LeaderboardEntry[]> {
  const cacheKey = `cache:leaderboard:${period}:top${limit}`;
  const cached = await getCachedJson<LeaderboardEntry[]>(cacheKey);
  if (cached) return cached;

  const orderCol = period === 'monthly' ? 'p.monthly_points' : 'p.season_points';

  const res = await query(
    `SELECT u.id as "userId", u.username, u.display_name as "displayName",
            u.avatar_url as "avatarUrl", u.supported_team as "supportedTeam",
            u.is_youtube_member as "isYouTubeMember",
            ${orderCol} as "points",
            ROW_NUMBER() OVER (ORDER BY ${orderCol} DESC, u.created_at ASC) as "rank"
     FROM users u
     JOIN user_profiles p ON p.user_id = u.id
     WHERE u.account_status = 'active'
     ORDER BY ${orderCol} DESC, u.created_at ASC
     LIMIT $1`,
    [limit]
  );

  const results: LeaderboardEntry[] = res.rows.map(r => ({
    ...r,
    rank: Number(r.rank),
    points: Number(r.points),
  }));

  // Cache for 60 seconds
  await setCachedJson(cacheKey, results, 60);
  return results;
}

export async function getUserRank(userId: string, period: 'monthly' | 'season'): Promise<{ rank: number; points: number }> {
  const orderCol = period === 'monthly' ? 'monthly_points' : 'season_points';

  const res = await query(
    `WITH ranked_users AS (
       SELECT user_id, ${orderCol} as points,
              ROW_NUMBER() OVER (ORDER BY ${orderCol} DESC) as rank
       FROM user_profiles
     )
     SELECT rank, points FROM ranked_users WHERE user_id = $1`,
    [userId]
  );

  if (res.rows.length === 0) return { rank: 0, points: 0 };
  return { rank: Number(res.rows[0].rank), points: Number(res.rows[0].points) };
}
