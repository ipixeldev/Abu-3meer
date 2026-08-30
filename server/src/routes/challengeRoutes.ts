import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import { submitChallengeAnswer } from '../services/challengeService.js';
import { query } from '../db/pool.js';
import { getCachedJson, setCachedJson } from '../redis/client.js';

const submitSchema = z.object({
  answer: z.string().trim().min(1).max(200),
});

export async function challengeRoutes(fastify: FastifyInstance) {
  // GET /api/v1/challenges/active - Returns active challenges without answer keys
  fastify.get('/challenges/active', async (request, reply) => {
    reply.header(
      'Cache-Control',
      'public, max-age=30, s-maxage=60, stale-while-revalidate=300',
    );
    const cacheKey = 'cache:challenges:active';
    const cached = await getCachedJson(cacheKey);
    if (cached) return cached;

    const res = await query(
      `SELECT id, video_id, title, description, kind, status, reward_points,
              reward_points * 2 AS member_points,
              video_url, image_url, maximum_attempts, member_only, starts_at, ends_at
       FROM challenges
       WHERE status = 'open' AND starts_at <= CURRENT_TIMESTAMP AND ends_at >= CURRENT_TIMESTAMP
       ORDER BY starts_at DESC`
    );
    await setCachedJson(cacheKey, res.rows, 60);
    return res.rows;
  });

  // POST /api/v1/challenges/:id/submit - Submit challenge answer with anti-brute force lock
  fastify.post('/challenges/:id/submit', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const { id } = request.params as { id: string };

    const parsed = submitSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'Invalid answer parameter',
        issues: parsed.error.issues,
      });
    }

    // Check anti-brute force lock
    const lockRes = await query(
      `SELECT failed_attempts, locked_until FROM challenge_attempt_locks WHERE user_id = $1 AND challenge_id = $2`,
      [user.id, id]
    );

    if (lockRes.rows.length > 0) {
      const lock = lockRes.rows[0];
      if (lock.locked_until && new Date() < new Date(lock.locked_until)) {
        const remainingSecs = Math.ceil((new Date(lock.locked_until).getTime() - Date.now()) / 1000);
        return reply.status(429).send({
          error: 'TooManyAttempts',
          message: `Too many failed attempts. Please wait ${remainingSecs} seconds before trying again.`,
        });
      }
    }

    try {
      const result = await submitChallengeAnswer(id, user.id, parsed.data.answer, user.isYouTubeMember);

      if (!result.correct) {
        // Record failed attempt
        const failedRes = await query(
          `INSERT INTO challenge_attempt_locks (user_id, challenge_id, failed_attempts, last_attempt_at)
           VALUES ($1, $2, 1, CURRENT_TIMESTAMP)
           ON CONFLICT (user_id, challenge_id) DO UPDATE SET
             failed_attempts = challenge_attempt_locks.failed_attempts + 1,
             last_attempt_at = CURRENT_TIMESTAMP,
             locked_until = CASE
               WHEN challenge_attempt_locks.failed_attempts + 1 >= 5 THEN CURRENT_TIMESTAMP + INTERVAL '10 minutes'
               ELSE NULL
             END
           RETURNING failed_attempts, locked_until`,
          [user.id, id]
        );

        if (failedRes.rows[0]?.locked_until) {
          // Log brute force warning
          await query(
            `INSERT INTO suspicious_activity_logs (user_id, type, details, severity)
             VALUES ($1, 'challenge_brute_force', $2, 'warning')`,
            [
              user.id,
              JSON.stringify({ challengeId: id, totalFailures: failedRes.rows[0].failed_attempts, ip: request.ip }),
            ]
          ).catch(() => {});
        }
      } else {
        // Reset lock on correct solve
        await query('DELETE FROM challenge_attempt_locks WHERE user_id = $1 AND challenge_id = $2', [user.id, id]);
      }

      return result;
    } catch (err: any) {
      return reply.status(400).send({ error: 'ChallengeSubmissionError', message: err.message });
    }
  });

  // GET /api/v1/player-cards - Public list of available player card clues
  fastify.get('/player-cards', async (request, reply) => {
    const res = await query(
      `SELECT pc.id, pc.challenge_id, pc.player_name, pc.team, pc.position, pc.card_tier,
              pc.card_image_url, pc.secret_hint, c.reward_points
       FROM player_cards pc
       JOIN challenges c ON c.id = pc.challenge_id
       WHERE c.status = 'open'`
    );
    return res.rows;
  });
}
