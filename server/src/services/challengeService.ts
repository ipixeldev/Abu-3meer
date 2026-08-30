import { query } from '../db/pool.js';
import { awardPoints } from './pointsService.js';

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

export async function submitChallengeAnswer(
  challengeId: string,
  userId: string,
  rawAnswer: string,
  isYouTubeMember: boolean
): Promise<{ correct: boolean; pointsAwarded: number; message?: string }> {
  // Check if challenge is active
  const challengeRes = await query(
    `SELECT id, title, kind, status, reward_points, member_points, correct_answer,
            normalized_correct_answer, starts_at, ends_at, maximum_attempts
     FROM challenges
     WHERE id = $1`,
    [challengeId]
  );

  if (challengeRes.rows.length === 0) {
    throw new Error('Challenge not found');
  }

  const challenge = challengeRes.rows[0];
  const now = new Date();
  if (challenge.status !== 'open' || now < new Date(challenge.starts_at) || now > new Date(challenge.ends_at)) {
    throw new Error('Challenge is currently closed');
  }

  // Check past attempts
  const submissionsRes = await query(
    `SELECT id, is_correct, attempt_number FROM challenge_submissions WHERE challenge_id = $1 AND user_id = $2`,
    [challengeId, userId]
  );

  if (submissionsRes.rows.some((s: any) => s.is_correct)) {
    return { correct: true, pointsAwarded: 0, message: 'Already solved and claimed!' };
  }

  if (submissionsRes.rows.length >= challenge.maximum_attempts) {
    throw new Error(`Maximum attempts reached (${challenge.maximum_attempts})`);
  }

  const normalizedInput = normalizeChallengeAnswer(rawAnswer);
  const normalizedTarget = challenge.normalized_correct_answer || normalizeChallengeAnswer(challenge.correct_answer);

  const isCorrect = normalizedInput === normalizedTarget ||
                    (normalizedInput.length > 2 && (normalizedTarget.includes(normalizedInput) || normalizedInput.includes(normalizedTarget)));

  const attemptNumber = submissionsRes.rows.length + 1;
  let pointsEarned = 0;

  if (isCorrect) {
    const basePoints = challenge.reward_points || 10;
    const multiplier = isYouTubeMember ? 2.0 : 1.0;
    const idempotencyKey = `challenge:${challengeId}:user:${userId}`;

    const awardRes = await awardPoints({
      userId,
      sourceType: challenge.kind === 'playerCard' ? 'player_card' : 'video_phrase',
      sourceId: challengeId,
      basePoints,
      multiplier,
      description: `Solved Challenge: ${challenge.title}`,
      idempotencyKey,
    });

    pointsEarned = awardRes.pointsAwarded;

    // Increment user challenge count
    await query(
      `UPDATE user_profiles SET challenges_completed_count = challenges_completed_count + 1 WHERE user_id = $1`,
      [userId]
    );
  }

  await query(
    `INSERT INTO challenge_submissions (challenge_id, user_id, raw_answer, normalized_answer, is_correct, attempt_number, points_awarded)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (user_id, challenge_id) DO UPDATE SET
       raw_answer = EXCLUDED.raw_answer,
       normalized_answer = EXCLUDED.normalized_answer,
       is_correct = EXCLUDED.is_correct,
       points_awarded = EXCLUDED.points_awarded`,
    [challengeId, userId, rawAnswer, normalizedInput, isCorrect, attemptNumber, pointsEarned]
  );

  return { correct: isCorrect, pointsAwarded: pointsEarned };
}
