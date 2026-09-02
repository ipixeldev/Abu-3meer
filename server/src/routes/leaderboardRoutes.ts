import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  getLeaderboardSnapshot,
  getUserRankForScope,
  listLeaderboardSeasons,
} from '../services/leaderboardService.js';
import { query } from '../db/pool.js';

const monthlyQuerySchema = z.object({
  period: z.enum(['current', 'previous']).default('current'),
});

const seasonQuerySchema = z.object({
  seasonId: z.string().trim().min(1).max(50).optional(),
});

async function authenticateLeaderboardViewer(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  if (request.headers.authorization == null) return;
  return authenticateUser(request, reply);
}

export async function leaderboardRoutes(fastify: FastifyInstance) {
  fastify.get(
    '/leaderboards/monthly',
    { preHandler: [authenticateLeaderboardViewer] },
    async (request, reply) => {
      const parsed = monthlyQuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'The leaderboard month is invalid.',
          issues: parsed.error.issues,
        });
      }
      if (request.user) reply.header('Cache-Control', 'private, no-store');
      return getLeaderboardSnapshot(
        parsed.data.period === 'previous' ? 'previous_month' : 'current_month',
        { databaseUserId: request.user?.id },
      );
    },
  );

  // Explicit endpoint used by the current mobile tabs. The query-string form
  // above remains available to older clients during the rollout.
  fastify.get(
    '/leaderboards/previous-month',
    { preHandler: [authenticateLeaderboardViewer] },
    async (request, reply) => {
      if (request.user) reply.header('Cache-Control', 'private, no-store');
      return getLeaderboardSnapshot('previous_month', {
        databaseUserId: request.user?.id,
      });
    },
  );

  fastify.get(
    '/leaderboards/season',
    { preHandler: [authenticateLeaderboardViewer] },
    async (request, reply) => {
      const parsed = seasonQuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'The leaderboard season is invalid.',
          issues: parsed.error.issues,
        });
      }
      if (request.user) reply.header('Cache-Control', 'private, no-store');
      return getLeaderboardSnapshot('season', {
        seasonId: parsed.data.seasonId,
        databaseUserId: request.user?.id,
      });
    },
  );

  fastify.get('/leaderboards/seasons', async () => {
    const seasons = await listLeaderboardSeasons();
    return {
      seasons,
      activeSeasonId: seasons.find(season => season.active)?.id ?? null,
    };
  });

  fastify.get('/leaderboards/my-rank', { preHandler: [authenticateUser] }, async (request, reply) => {
    const parsed = seasonQuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'The leaderboard season is invalid.',
        issues: parsed.error.issues,
      });
    }
    const user = request.user!;
    const [monthly, previousMonth, season, seasons] = await Promise.all([
      getUserRankForScope(user.id, 'current_month'),
      getUserRankForScope(user.id, 'previous_month'),
      getUserRankForScope(user.id, 'season', { seasonId: parsed.data.seasonId }),
      listLeaderboardSeasons(),
    ]);
    return {
      publicId: user.username,
      monthlyRank: monthly.rank,
      monthlyPoints: monthly.points,
      previousMonthRank: previousMonth.rank,
      previousMonthPoints: previousMonth.points,
      seasonRank: season.rank,
      seasonPoints: season.points,
      activeSeasonId: seasons.find(item => item.active)?.id ?? null,
    };
  });

  fastify.get('/leaderboards/teams', async () => {
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
