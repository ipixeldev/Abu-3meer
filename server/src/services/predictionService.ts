import { query, getClient } from '../db/pool.js';
import { awardPoints, getPointRules } from './pointsService.js';
import { normalizeChallengeAnswer } from './challengeService.js';
import { config } from '../config.js';

export interface SubmitPredictionParams {
  userId: string;
  matchId: string;
  homeScore: number;
  awayScore: number;
  firstScorer: string;
  homeTeam?: string;
  awayTeam?: string;
  competition?: string;
  kickoffAt?: string | Date;
  homeLogoUrl?: string | null;
  awayLogoUrl?: string | null;
}

export interface DerivedMatchWindow {
  kickoffAt: Date;
  predictionsOpenAt: Date;
  predictionsCloseAt: Date;
  status: 'open';
}

export interface PredictionEvaluation {
  isExact: boolean;
  isFirstScorer: boolean;
  isWinner: boolean;
}

export function evaluatePrediction(input: {
  predictedHome: number;
  predictedAway: number;
  predictedFirstScorer?: string | null;
  actualHome: number;
  actualAway: number;
  actualFirstScorer?: string | null;
}): PredictionEvaluation {
  const isExact =
    input.predictedHome === input.actualHome &&
    input.predictedAway === input.actualAway;

  const predictedScorer = normalizeChallengeAnswer(
    input.predictedFirstScorer || '',
  );
  const actualScorer = normalizeChallengeAnswer(input.actualFirstScorer || '');
  const isFirstScorer =
    predictedScorer.length > 0 &&
    actualScorer.length > 0 &&
    (actualScorer === predictedScorer ||
      actualScorer.includes(predictedScorer) ||
      predictedScorer.includes(actualScorer));

  const predictedWinner =
    input.predictedHome > input.predictedAway
      ? 'home'
      : input.predictedAway > input.predictedHome
        ? 'away'
        : 'draw';
  const actualWinner =
    input.actualHome > input.actualAway
      ? 'home'
      : input.actualAway > input.actualHome
        ? 'away'
        : 'draw';

  return {
    isExact,
    isFirstScorer,
    isWinner: predictedWinner === actualWinner,
  };
}

export function deriveMatchWindow(
  kickoffInput: string | Date | undefined,
  now = new Date(),
): DerivedMatchWindow {
  if (!kickoffInput) {
    throw new Error('Match kickoff time is required before a prediction can be saved');
  }
  const kickoffAt = new Date(kickoffInput);
  if (Number.isNaN(kickoffAt.getTime())) {
    throw new Error('Match kickoff time is invalid');
  }

  const predictionsCloseAt = new Date(kickoffAt.getTime() - 5 * 60 * 1000);
  if (now >= predictionsCloseAt) {
    throw new Error('Prediction window is closed for this match');
  }

  return {
    kickoffAt,
    predictionsOpenAt: new Date(now.getTime() - 1000),
    predictionsCloseAt,
    status: 'open',
  };
}

export async function submitPrediction(params: SubmitPredictionParams) {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    let matchRes = await client.query(
      `SELECT id, home_team, away_team, kickoff_at, predictions_open_at,
              predictions_close_at, status
       FROM matches
       WHERE id = $1
       FOR UPDATE`,
      [params.matchId],
    );

    // External fixture feeds can show a match before it has been imported by a
    // background job. Persist its complete, required match record atomically
    // with the first prediction so the FK and all NOT NULL constraints hold.
    if (matchRes.rows.length === 0) {
      if (!params.homeTeam || !params.awayTeam || !params.competition) {
        throw new Error('Match details are required before a prediction can be saved');
      }
      const window = deriveMatchWindow(params.kickoffAt);
      await client.query(
        `INSERT INTO matches (
           id, competition_name, home_team, away_team, kickoff_at,
           predictions_open_at, predictions_close_at, home_logo_url,
           away_logo_url, status
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (id) DO NOTHING`,
        [
          params.matchId,
          params.competition,
          params.homeTeam,
          params.awayTeam,
          window.kickoffAt,
          window.predictionsOpenAt,
          window.predictionsCloseAt,
          params.homeLogoUrl || null,
          params.awayLogoUrl || null,
          window.status,
        ],
      );
      matchRes = await client.query(
        `SELECT id, home_team, away_team, kickoff_at, predictions_open_at,
                predictions_close_at, status
         FROM matches
         WHERE id = $1
         FOR UPDATE`,
        [params.matchId],
      );
    }

    if (matchRes.rows.length === 0) {
      throw new Error('Match could not be prepared for predictions');
    }

    const match = matchRes.rows[0];
    const now = new Date();
    const opensAt = new Date(match.predictions_open_at);
    const deadline = new Date(match.predictions_close_at);
    const closedStatuses = new Set([
      'closed',
      'live',
      'finished',
      'cancelled',
      'postponed',
    ]);

    if (now < opensAt) {
      throw new Error('Prediction window has not opened for this match');
    }
    if (now >= deadline || closedStatuses.has(match.status)) {
      throw new Error('Prediction window is closed for this match');
    }

    const res = await client.query(
      `INSERT INTO predictions
         (user_id, match_id, home_score, away_score, first_scorer)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id, match_id) DO UPDATE SET
         home_score = EXCLUDED.home_score,
         away_score = EXCLUDED.away_score,
         first_scorer = EXCLUDED.first_scorer,
         updated_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [
        params.userId,
        params.matchId,
        params.homeScore,
        params.awayScore,
        params.firstScorer.trim(),
      ],
    );

    await client.query('COMMIT');
    return res.rows[0];
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export async function settleMatchPredictions(matchId: string): Promise<{ processedCount: number; pointsDistributed: number }> {
  const matchRes = await query(
    `SELECT id, home_team, away_team, home_score, away_score, first_scorer, reward_processed
     FROM matches
     WHERE id = $1`,
    [matchId]
  );

  if (matchRes.rows.length === 0) throw new Error('Match not found');
  const match = matchRes.rows[0];

  if (match.home_score === null || match.away_score === null) {
    throw new Error('Match does not have official final scores yet');
  }

  const predictionsRes = await query(
    `SELECT p.id, p.user_id, p.home_score, p.away_score, p.first_scorer,
            p.rewarded,
            u.is_youtube_member
     FROM predictions p
     JOIN users u ON u.id = p.user_id
     WHERE p.match_id = $1 AND NOT p.rewarded`,
    [matchId]
  );

  const rules = await getPointRules();
  const pointValues = {
    exact: rules.exactPrediction ?? config.pointDefaults.exactScore,
    scorer: rules.firstScorer ?? config.pointDefaults.firstScorer,
    winner: rules.winnerOutcome ?? config.pointDefaults.winnerOutcome,
  };

  let processedCount = 0;
  let pointsDistributed = 0;

  const actualHome = match.home_score;
  const actualAway = match.away_score;
  for (const pred of predictionsRes.rows) {
    const result = evaluatePrediction({
      predictedHome: pred.home_score,
      predictedAway: pred.away_score,
      predictedFirstScorer: pred.first_scorer,
      actualHome,
      actualAway,
      actualFirstScorer: match.first_scorer,
    });
    const multiplier = pred.is_youtube_member ? 2.0 : 1.0;

    const components = [
      {
        correct: result.isExact,
        key: 'exact',
        sourceType: 'prediction_exact' as const,
        basePoints: pointValues.exact,
        label: 'Exact score',
      },
      {
        correct: result.isFirstScorer,
        key: 'scorer',
        sourceType: 'prediction_scorer' as const,
        basePoints: pointValues.scorer,
        label: 'First scorer',
      },
      {
        correct: result.isWinner,
        key: 'winner',
        sourceType: 'prediction_winner' as const,
        basePoints: pointValues.winner,
        label: 'Winner outcome',
      },
    ];

    let totalAward = 0;
    for (const component of components) {
      if (!component.correct) continue;
      const award = await awardPoints({
        userId: pred.user_id,
        sourceType: component.sourceType,
        sourceId: matchId,
        basePoints: component.basePoints,
        multiplier,
        description: `${component.label}: ${match.home_team} vs ${match.away_team}`,
        idempotencyKey: `pred_reward:${pred.id}:${component.key}`,
      });
      totalAward += award.pointsAwarded;
      if (!award.alreadyAwarded) {
        pointsDistributed += award.pointsAwarded;
      }
    }

    await query(
      `UPDATE predictions
       SET points_awarded = $1,
           rewarded = true,
           seen_result = false,
           is_exact_match = $2,
           is_first_scorer_match = $3,
           is_winner_match = $4
       WHERE id = $5`,
      [
        totalAward,
        result.isExact,
        result.isFirstScorer,
        result.isWinner,
        pred.id,
      ]
    );

    processedCount++;
  }

  await query('UPDATE matches SET reward_processed = true, reward_processed_at = CURRENT_TIMESTAMP WHERE id = $1', [matchId]);

  return { processedCount, pointsDistributed };
}
