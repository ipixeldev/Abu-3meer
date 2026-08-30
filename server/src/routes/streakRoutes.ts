import { FastifyInstance } from 'fastify';
import { authenticateUser } from '../middleware/auth.js';
import { checkInDailyStreak } from '../services/streakService.js';

export async function streakRoutes(fastify: FastifyInstance) {
  fastify.post('/streaks/check-in', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    try {
      const result = await checkInDailyStreak(user.id, user.isYouTubeMember);
      return result;
    } catch (err: any) {
      const statusCode = Number(err?.statusCode || 500);
      request.log.error({ err, userId: user.id }, 'Daily streak check-in failed');
      return reply.status(statusCode).send({
        error: statusCode >= 500 ? 'PersistenceError' : 'StreakError',
        message: statusCode >= 500
          ? 'Unable to save the daily streak right now. Please try again.'
          : err.message,
        requestId: request.id,
      });
    }
  });
}
