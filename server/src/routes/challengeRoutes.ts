import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  ChallengeSubmissionError,
  submitChallengeAnswer,
} from '../services/challengeService.js';
import { query } from '../db/pool.js';
import { getCachedJson, setCachedJson } from '../redis/client.js';

const submitSchema = z.object({
  answer: z.string().trim().min(1).max(200),
});

export async function challengeRoutes(fastify: FastifyInstance) {
  // GET /api/v1/challenges/active - Returns active challenges without answer keys
  fastify.get(
    '/challenges/active',
    { preHandler: [authenticateUser] },
    async (request, reply) => {
      const canAccessMemberContent = request.user!.isYouTubeMember;
      reply.header(
        'Cache-Control',
        'private, max-age=30, stale-while-revalidate=120',
      );
      const cacheKey = `cache:challenges:active:${canAccessMemberContent ? 'member' : 'public'}`;
      const cached = await getCachedJson(cacheKey);
      if (cached) return cached;

      const res = await query(
        `SELECT c.id, c.video_id, c.title, c.description, c.kind, c.status,
              c.reward_points, c.reward_points * 2 AS member_points,
              c.video_url, c.image_url, c.maximum_attempts, c.member_only,
              c.notify_on_live, c.starts_at, c.ends_at,
              COALESCE(
                jsonb_agg(
                  jsonb_build_object(
                    'id', q.id,
                    'prompt', q.prompt,
                    'type', q.answer_type,
                    'options', q.options
                  ) ORDER BY q.position
                ) FILTER (WHERE q.id IS NOT NULL),
                '[]'::jsonb
              ) AS questions
       FROM challenges c
       LEFT JOIN challenge_questions q ON q.challenge_id = c.id
       WHERE c.status IN ('open', 'scheduled')
         AND c.starts_at <= CURRENT_TIMESTAMP
         AND c.ends_at >= CURRENT_TIMESTAMP
         AND (c.member_only = FALSE OR $1 = TRUE)
       GROUP BY c.id
       ORDER BY c.starts_at DESC`,
        [canAccessMemberContent],
      );
      await setCachedJson(cacheKey, res.rows, 60);
      return res.rows;
    },
  );

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
      if (err instanceof ChallengeSubmissionError) {
        return reply.status(err.statusCode).send({
          error: err.code,
          message: err.message,
        });
      }
      request.log.error({ err, challengeId: id }, 'Challenge submission failed');
      return reply.status(500).send({
        error: 'ChallengeSubmissionError',
        message: 'The challenge answer could not be saved. Please try again.',
      });
    }
  });

  // GET /api/v1/player-cards - Per-user collection. Locked cards deliberately
  // omit answer-bearing player/team/image/stat fields.
  fastify.get('/player-cards', { preHandler: [authenticateUser] }, async (request, reply) => {
    reply.header(
      'Cache-Control',
      'private, no-store',
    );
    const res = await query(
      `SELECT pc.id,
              CASE WHEN claim.id IS NOT NULL THEN pc.player_name ELSE '' END AS player_name,
              CASE WHEN claim.id IS NOT NULL THEN pc.player_name_ar ELSE '' END AS player_name_ar,
              CASE WHEN claim.id IS NOT NULL THEN pc.card_image_url ELSE '' END AS card_image_url,
              CASE WHEN claim.id IS NOT NULL THEN pc.team ELSE '' END AS team,
              CASE WHEN claim.id IS NOT NULL THEN pc.team_logo_url ELSE '' END AS team_logo_url,
              CASE WHEN claim.id IS NOT NULL THEN COALESCE(pc.position, '') ELSE '' END AS position,
              CASE WHEN claim.id IS NOT NULL THEN pc.rating ELSE 0 END AS rating,
              pc.rarity,
              CASE WHEN claim.id IS NOT NULL THEN pc.stats ELSE '{}'::jsonb END AS stats,
              CASE WHEN claim.id IS NOT NULL THEN pc.description ELSE '' END AS description,
              CASE WHEN claim.id IS NOT NULL THEN pc.description_ar ELSE '' END AS description_ar,
              pc.enabled,
              COALESCE(NULLIF(pc.source_challenge_id, ''), pc.challenge_id, '')
                AS source_challenge_id,
              claim.id IS NOT NULL AS unlocked,
              claim.claimed_at AS unlocked_at,
              pc.updated_at
       FROM player_cards pc
       LEFT JOIN player_card_claims claim
         ON claim.player_card_id = pc.id AND claim.user_id = $1
       WHERE pc.enabled = TRUE
       ORDER BY pc.updated_at DESC
       LIMIT 200`,
      [request.user!.id],
    );
    return res.rows;
  });
}
