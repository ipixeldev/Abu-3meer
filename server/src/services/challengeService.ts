import { getClient } from '../db/pool.js';
import {
  awardPointsInTransaction,
  invalidatePointCaches,
  memberMultiplierForSource,
  PointSourceType,
} from './pointsService.js';

export class ChallengeSubmissionError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode = 400,
  ) {
    super(message);
    this.name = 'ChallengeSubmissionError';
  }
}

export function normalizeChallengeAnswer(text: string): string {
  return text
    .trim()
    .replace(/[\u064B-\u065F\u0670]/g, '') // Strip Arabic diacritics / tashkeel
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/\s+/g, ' ')
    .toLowerCase();
}

/** Exact normalized matching prevents short/partial guesses from passing. */
export function isChallengeAnswerAccepted(
  rawAnswer: string,
  acceptedAnswers: unknown,
  legacyAnswer = '',
): boolean {
  const normalizedInput = normalizeChallengeAnswer(rawAnswer);
  if (!normalizedInput) return false;

  const candidates = Array.isArray(acceptedAnswers)
    ? acceptedAnswers
        .filter((answer): answer is string => typeof answer === 'string')
        .map(normalizeChallengeAnswer)
        .filter(Boolean)
    : [];
  if (candidates.length === 0 && legacyAnswer) {
    candidates.push(normalizeChallengeAnswer(legacyAnswer));
  }
  return new Set(candidates).has(normalizedInput);
}

export async function submitChallengeAnswer(
  challengeId: string,
  userId: string,
  rawAnswer: string,
  isYouTubeMember: boolean,
): Promise<{ correct: boolean; pointsAwarded: number; message?: string }> {
  const client = await getClient();
  let shouldInvalidatePointCaches = false;

  try {
    await client.query('BEGIN');

    // Serialize attempts for one user/challenge without requiring a separate
    // lock row to exist first. This closes concurrent double-claim and attempt
    // number races while allowing unrelated users to submit in parallel.
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`challenge:${challengeId}:user:${userId}`],
    );

    const challengeRes = await client.query(
      `SELECT c.id, c.title, c.kind, c.status, c.reward_points,
              c.correct_answer, c.normalized_correct_answer, c.starts_at,
              c.ends_at, c.maximum_attempts, c.member_only,
              COALESCE(question.normalized_accepted_answers, '[]'::jsonb)
                AS accepted_answers
       FROM challenges c
       LEFT JOIN LATERAL (
         SELECT q.normalized_accepted_answers
         FROM challenge_questions q
         WHERE q.challenge_id = c.id
         ORDER BY q.position, q.id
         LIMIT 1
       ) question ON TRUE
       WHERE c.id = $1
       FOR UPDATE OF c`,
      [challengeId],
    );

    if (challengeRes.rows.length === 0) {
      throw new ChallengeSubmissionError('ChallengeNotFound', 'Challenge not found', 404);
    }

    const challenge = challengeRes.rows[0];
    const now = new Date();
    if (
      !['open', 'scheduled'].includes(challenge.status) ||
      now < new Date(challenge.starts_at) ||
      now > new Date(challenge.ends_at)
    ) {
      throw new ChallengeSubmissionError(
        'ChallengeClosed',
        'Challenge is currently closed',
      );
    }
    if (challenge.member_only && !isYouTubeMember) {
      throw new ChallengeSubmissionError(
        'MembershipRequired',
        'This challenge is available to verified YouTube members only.',
        403,
      );
    }

    const submissionsRes = await client.query(
      `SELECT id, is_correct, attempt_number
       FROM challenge_submissions
       WHERE challenge_id = $1 AND user_id = $2
       ORDER BY attempt_number DESC`,
      [challengeId, userId],
    );

    if (submissionsRes.rows.some((submission: any) => submission.is_correct)) {
      await client.query('COMMIT');
      return {
        correct: true,
        pointsAwarded: 0,
        message: 'Already solved and claimed!',
      };
    }

    if (submissionsRes.rows.length >= challenge.maximum_attempts) {
      throw new ChallengeSubmissionError(
        'MaximumAttemptsReached',
        `Maximum attempts reached (${challenge.maximum_attempts})`,
      );
    }

    const normalizedInput = normalizeChallengeAnswer(rawAnswer);
    const legacyAnswer =
      challenge.normalized_correct_answer || challenge.correct_answer || '';
    const isCorrect = isChallengeAnswerAccepted(
      rawAnswer,
      challenge.accepted_answers,
      legacyAnswer,
    );
    const attemptNumber = submissionsRes.rows.reduce(
      (maximum: number, row: any) =>
        Math.max(maximum, Number(row.attempt_number) || 0),
      0,
    ) + 1;

    let pointsEarned = 0;
    let newlyCompleted = 0;
    let newlyClaimedCards = 0;
    if (isCorrect) {
      const basePoints = Number(challenge.reward_points) || 10;
      const sourceType: PointSourceType =
        challenge.kind === 'playerCard' ? 'player_card' : 'video_phrase';
      const award = await awardPointsInTransaction(client, {
        userId,
        sourceType,
        sourceId: challengeId,
        basePoints,
        multiplier: memberMultiplierForSource(sourceType, isYouTubeMember),
        description: `Solved Challenge: ${challenge.title}`,
        idempotencyKey: `challenge:${challengeId}:user:${userId}`,
      });

      // A legacy partial write may already own the award key. Do not present
      // old points as newly earned or increment the completion counter twice.
      pointsEarned = award.alreadyAwarded ? 0 : award.pointsAwarded;
      newlyCompleted = award.alreadyAwarded ? 0 : 1;
      shouldInvalidatePointCaches = !award.alreadyAwarded;

      const claims = await client.query(
        `INSERT INTO player_card_claims
           (player_card_id, user_id, points_awarded)
         SELECT pc.id, $2, $3
         FROM player_cards pc
         WHERE pc.enabled = TRUE
           AND (
             pc.challenge_id = $1 OR
             NULLIF(pc.source_challenge_id, '') = $1
           )
         ON CONFLICT (user_id, player_card_id) DO NOTHING
         RETURNING player_card_id`,
        [challengeId, userId, pointsEarned],
      );
      newlyClaimedCards = claims.rowCount ?? 0;
    }

    await client.query(
      `INSERT INTO challenge_submissions
         (challenge_id, user_id, raw_answer, normalized_answer, is_correct,
          attempt_number, points_awarded)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        challengeId,
        userId,
        rawAnswer,
        normalizedInput,
        isCorrect,
        attemptNumber,
        pointsEarned,
      ],
    );

    if (newlyCompleted > 0 || newlyClaimedCards > 0) {
      const profileUpdate = await client.query(
        `UPDATE user_profiles
         SET challenges_completed_count = challenges_completed_count + $1,
             player_cards_collected_count = player_cards_collected_count + $2,
             updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $3`,
        [newlyCompleted, newlyClaimedCards, userId],
      );
      if (profileUpdate.rowCount !== 1) {
        throw new Error(`Challenge profile not found for user ${userId}`);
      }
    }

    await client.query('COMMIT');
    if (shouldInvalidatePointCaches) await invalidatePointCaches();
    return { correct: isCorrect, pointsAwarded: pointsEarned };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
