import { FastifyInstance } from 'fastify';
import { authenticateUser } from '../middleware/auth.js';
import { getTopLeaderboard, getUserRank } from '../services/leaderboardService.js';
import { query } from '../db/pool.js';

export async function leaderboardRoutes(fastify: FastifyInstance) {
  fastify.get('/leaderboards/monthly', async (request, reply) => {
    const topUsers = await getTopLeaderboard('monthly', 100);
    return { leaderboard: topUsers };
  });

  fastify.get('/leaderboards/season', async (request, reply) => {
    const topUsers = await getTopLeaderboard('season', 100);
    return { leaderboard: topUsers };
  });

  fastify.get('/leaderboards/my-rank', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const monthly = await getUserRank(user.id, 'monthly');
    const season = await getUserRank(user.id, 'season');
    return {
      monthlyRank: monthly.rank,
      monthlyPoints: monthly.points,
      seasonRank: season.rank,
      seasonPoints: season.points,
    };
  });

  fastify.get('/leaderboards/teams', async (request, reply) => {
    const res = await query(
      `SELECT supported_team as "teamName", supported_team_logo as "teamLogo",
              COUNT(*) as "fanCount", SUM(p.total_points) as "totalPoints"
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       WHERE u.supported_team IS NOT NULL AND u.supported_team != 'General Fan'
       GROUP BY supported_team, supported_team_logo
       ORDER BY SUM(p.total_points) DESC
       LIMIT 20`
    );
    return res.rows;
  });
}
