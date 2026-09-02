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
): Promise<{
  correct: boolean;
  pointsAwarded: number;
  attemptsUsed: number;
  remainingAttempts: number;
  solved: boolean;
  alreadyAwarded?: boolean;
  message?: string;
}> {
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
    // Snapshot imports and claim approval/revocation take the exclusive form
    // of this lock. A shared lock lets unrelated submissions stay concurrent
    // while making the membership decision stable through the points write.
    await client.query(
      `SELECT pg_advisory_xact_lock_shared(
         hashtextextended('youtube-membership-snapshot-import', 0)
       )`,
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
    const membershipRes = await client.query(
      `SELECT COALESCE(
                member_link.is_member = TRUE
                AND member_link.verification_source = 'admin_snapshot'
                AND member_link.snapshot_import_id = snapshot_state.active_import_id
                AND snapshot_import.id IS NOT NULL
                AND approved_claim.id IS NOT NULL,
                FALSE
              ) AS is_youtube_member
       FROM users user_account
       LEFT JOIN youtube_account_links member_link
         ON member_link.user_id = user_account.id
       LEFT JOIN youtube_membership_snapshot_state snapshot_state
         ON snapshot_state.singleton = TRUE
       LEFT JOIN youtube_membership_snapshot_imports snapshot_import
         ON snapshot_import.id = snapshot_state.active_import_id
        AND snapshot_import.expires_at > clock_timestamp()
       LEFT JOIN youtube_channel_claims approved_claim
         ON approved_claim.user_id = user_account.id
        AND approved_claim.youtube_channel_id = member_link.youtube_channel_id
        AND approved_claim.status = 'approved'
       WHERE user_account.id = $1`,
      [userId],
    );
    const isYouTubeMember =
      membershipRes.rows[0]?.is_youtube_member === true;
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

    const sourceType: PointSourceType =
      challenge.kind === 'playerCard' ? 'player_card' : 'video_phrase';
    const basePoints = Number(challenge.reward_points) || 10;
    const awardParams = {
      userId,
      sourceType,
      sourceId: challengeId,
      basePoints,
      multiplier: memberMultiplierForSource(sourceType, isYouTubeMember),
      description: `Solved Challenge: ${challenge.title}`,
      idempotencyKey: `challenge:${challengeId}:user:${userId}`,
    };

    const submissionsRes = await client.query(
      `SELECT id, is_correct, attempt_number, points_awarded
       FROM challenge_submissions
       WHERE challenge_id = $1 AND user_id = $2
       ORDER BY attempt_number DESC`,
      [challengeId, userId],
    );

    const existingCorrect = submissionsRes.rows.find(
      (submission: any) => submission.is_correct,
    );
    if (existingCorrect) {
      // Replaying a successful request must report the canonical award, not
      // "0 points". Calling the idempotent award operation also repairs the
      // rare legacy state where a correct submission was saved without its
      // ledger transaction.
      const award = await awardPointsInTransaction(client, awardParams);
      const canonicalPoints = award.pointsAwarded;
      if (Number(existingCorrect.points_awarded) !== canonicalPoints) {
        await client.query(
          `UPDATE challenge_submissions
           SET points_awarded = $1
           WHERE id = $2`,
          [canonicalPoints, existingCorrect.id],
        );
      }
      await client.query('COMMIT');
      if (!award.alreadyAwarded) await invalidatePointCaches();
      return {
        correct: true,
        pointsAwarded: canonicalPoints,
        attemptsUsed: submissionsRes.rows.length,
        remainingAttempts: 0,
        solved: true,
        alreadyAwarded: award.alreadyAwarded === true,
        message: award.alreadyAwarded
          ? 'Already solved; your points were awarded earlier.'
          : 'Your missing challenge points were restored.',
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
    let alreadyAwarded = false;
    if (isCorrect) {
      const award = await awardPointsInTransaction(client, awardParams);

      // A legacy partial write may already own the award key. Do not present
      // old points as newly earned or increment the completion counter twice,
      // but still return/store the canonical amount instead of a misleading 0.
      pointsEarned = award.pointsAwarded;
      alreadyAwarded = award.alreadyAwarded === true;
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
    return {
      correct: isCorrect,
      pointsAwarded: pointsEarned,
      attemptsUsed: attemptNumber,
      remainingAttempts: isCorrect
        ? 0
        : Math.max(0, Number(challenge.maximum_attempts) - attemptNumber),
      solved: isCorrect,
      ...(isCorrect ? { alreadyAwarded } : {}),
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
