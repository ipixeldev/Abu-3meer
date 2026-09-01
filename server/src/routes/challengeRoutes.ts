import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  ChallengeSubmissionError,
  submitChallengeAnswer,
} from '../services/challengeService.js';
import { query } from '../db/pool.js';
import { getCachedJson, setCachedJson } from '../redis/client.js';
import { listPlayerCardsForUser } from '../services/playerCardService.js';
import {
  ChallengeMembershipUnavailableError,
  resolveChallengeMembership,
} from '../services/challengeMembershipService.js';

const submitSchema = z.object({
  answer: z.string().trim().min(1).max(200),
});

type ChallengeFeedRow = Record<string, unknown>;

export function mergeChallengeActivity(
  challenges: ChallengeFeedRow[],
  activityRows: ChallengeFeedRow[],
): ChallengeFeedRow[] {
  const activityByChallenge = new Map(
    activityRows.map((row) => [String(row.challenge_id), row]),
  );
  return challenges.map((challenge) => {
    const activity = activityByChallenge.get(String(challenge.id));
    return {
      ...challenge,
      attempts_used: Number(activity?.attempts_used ?? 0),
      solved: activity?.solved === true,
    };
  });
}

export async function challengeRoutes(fastify: FastifyInstance) {
  // GET /api/v1/challenges/active - Returns active challenges without answer keys
  fastify.get(
    '/challenges/active',
    { preHandler: [authenticateUser] },
    async (request, reply) => {
      let canAccessMemberContent = false;
      try {
        canAccessMemberContent = await resolveChallengeMembership(request.user!.id);
      } catch (error) {
        request.log.warn({ err: error }, 'Member challenge visibility unavailable');
      }
      reply.header(
        'Cache-Control',
        'private, max-age=30, stale-while-revalidate=120',
      );
      const cacheKey = `cache:challenges:active:${canAccessMemberContent ? 'member' : 'public'}`;
      let challenges = await getCachedJson<ChallengeFeedRow[]>(cacheKey);
      if (!challenges) {
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
        challenges = res.rows;
        await setCachedJson(cacheKey, challenges, 60);
      }

      const challengeIds = challenges.map((challenge) => String(challenge.id));
      if (challengeIds.length === 0) return challenges;
      const activity = await query(
        `SELECT challenge_id,
                COUNT(*)::integer AS attempts_used,
                BOOL_OR(is_correct) AS solved
         FROM challenge_submissions
         WHERE user_id = $1
           AND challenge_id = ANY($2::varchar[])
         GROUP BY challenge_id`,
        [request.user!.id, challengeIds],
      );
      return mergeChallengeActivity(challenges, activity.rows);
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

    let isYouTubeMember: boolean;
    try {
      // Resolve before any attempt or award write. An outage consumes nothing.
      isYouTubeMember = await resolveChallengeMembership(user.id);
    } catch (error) {
      if (error instanceof ChallengeMembershipUnavailableError) {
        return reply.status(503).send({
          error: 'YouTubeMembershipUnavailable',
          message: error.message,
          retryable: true,
        });
      }
      throw error;
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
      const result = await submitChallengeAnswer(
        id,
        user.id,
        parsed.data.answer,
        isYouTubeMember,
      );

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
              JSON.stringify({
                challengeId: id,
                totalFailures: failedRes.rows[0].failed_attempts,
              }),
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
    return listPlayerCardsForUser(
      (text, params) => query(text, params),
      request.user!.id,
    );
  });
}
