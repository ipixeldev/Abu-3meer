import { query, getClient, getDirectClient } from '../db/pool.js';
import {
  awardPoints,
  getPointRules,
  memberMultiplierForSource,
} from './pointsService.js';
import { refreshStaleYouTubeMembershipsForUsers } from './csvMembershipService.js';
import { normalizeChallengeAnswer } from './challengeService.js';
import { config } from '../config.js';
import {
  createNotificationCampaign,
  type CreatedNotificationCampaign,
} from './notificationService.js';
import { predictionResultNotificationCampaign } from './predictionResultNotification.js';

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
    actualScorer === predictedScorer;

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

export interface MatchPredictionSettlementResult {
  processedCount: number;
  pointsDistributed: number;
  notificationCampaigns: CreatedNotificationCampaign[];
  alreadyProcessing?: boolean;
}

async function settleMatchPredictionsUnlocked(
  matchId: string,
): Promise<MatchPredictionSettlementResult> {
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

  const pendingPredictionUsers = await query<{ user_id: string }>(
    `SELECT DISTINCT user_id
     FROM predictions
     WHERE match_id = $1 AND NOT rewarded`,
    [matchId],
  );
  await refreshStaleYouTubeMembershipsForUsers(
    pendingPredictionUsers.rows.map((row) => row.user_id),
  );

  const predictionsRes = await query(
    `SELECT p.id, p.user_id, p.home_score, p.away_score, p.first_scorer,
            p.rewarded,
            COALESCE(
              yl.is_member = TRUE
              AND yl.verification_source = 'admin_snapshot'
              AND EXISTS (
                SELECT 1
                FROM youtube_membership_snapshot_state snapshot_state
                JOIN youtube_membership_snapshot_imports snapshot_import
                  ON snapshot_import.id = snapshot_state.active_import_id
                 AND snapshot_import.expires_at > CURRENT_TIMESTAMP
                WHERE snapshot_state.singleton = TRUE
                  AND snapshot_state.active_import_id = yl.snapshot_import_id
              )
              AND EXISTS (
                SELECT 1
                FROM youtube_channel_claims approved_claim
                WHERE approved_claim.user_id = p.user_id
                  AND approved_claim.youtube_channel_id = yl.youtube_channel_id
                  AND approved_claim.status = 'approved'
              ),
              FALSE
            ) AS is_youtube_member
     FROM predictions p
     LEFT JOIN youtube_account_links yl ON yl.user_id = p.user_id
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
        multiplier: memberMultiplierForSource(
          component.sourceType,
          pred.is_youtube_member,
        ),
        description: `${component.label}: ${match.home_team} vs ${match.away_team}`,
        idempotencyKey: `pred_reward:${pred.id}:${component.key}`,
      });
      totalAward += award.pointsAwarded;
      if (!award.alreadyAwarded) {
        pointsDistributed += award.pointsAwarded;
      }
    }

    const updated = await query(
      `UPDATE predictions
       SET points_awarded = $1,
           rewarded = true,
           seen_result = false,
           is_exact_match = $2,
           is_first_scorer_match = $3,
           is_winner_match = $4
       WHERE id = $5 AND rewarded = false
       RETURNING id`,
      [
        totalAward,
        result.isExact,
        result.isFirstScorer,
        result.isWinner,
        pred.id,
      ]
    );

    if (updated.rowCount === 1) processedCount++;
  }

  // Recompute the denormalized counter from the durable settled rows. This is
  // idempotent and also repairs a process interruption that happened after a
  // prediction was marked rewarded but before its profile counter changed.
  await query(
    `UPDATE user_profiles profile
     SET exact_predictions_count = (
           SELECT COUNT(*)::INTEGER
           FROM predictions prediction
           WHERE prediction.user_id = profile.user_id
             AND prediction.rewarded = TRUE
             AND prediction.is_exact_match = TRUE
         ),
         updated_at = CURRENT_TIMESTAMP
     WHERE profile.user_id IN (
       SELECT prediction.user_id
       FROM predictions prediction
       WHERE prediction.match_id = $1
     )`,
    [matchId],
  );

  // Result notifications are rebuilt from the settled rows, not only this
  // invocation's in-memory loop. If campaign persistence failed after points
  // were committed, a BullMQ retry can safely backfill the missing alert.
  const settledPredictions = await query(
    `SELECT id, user_id, points_awarded
     FROM predictions
     WHERE match_id = $1 AND rewarded = true`,
    [matchId],
  );
  const notificationCampaigns: CreatedNotificationCampaign[] = [];
  for (const prediction of settledPredictions.rows) {
    const campaign = await createNotificationCampaign(
      predictionResultNotificationCampaign({
        predictionId: String(prediction.id),
        userId: String(prediction.user_id),
        matchId,
        homeTeam: String(match.home_team),
        awayTeam: String(match.away_team),
        homeScore: Number(actualHome),
        awayScore: Number(actualAway),
        pointsAwarded: Number(prediction.points_awarded || 0),
      }),
    );
    if (campaign.campaignId) notificationCampaigns.push(campaign);
  }

  // This is the durable completion marker for the whole settlement, including
  // denormalized repairs and campaign persistence. If the process dies before
  // here, periodic PostgreSQL recovery rebuilds the settlement job even when
  // every prediction row was already marked rewarded.
  await query(
    `UPDATE matches
     SET reward_processed = true,
         reward_processed_at = CURRENT_TIMESTAMP
     WHERE id = $1`,
    [matchId],
  );

  return { processedCount, pointsDistributed, notificationCampaigns };
}

export async function settleMatchPredictions(
  matchId: string,
): Promise<MatchPredictionSettlementResult> {
  // Manual result publishing, provider reconciliation and a retried BullMQ
  // job can converge on the same match. A session advisory lock gives the
  // settlement one owner while point-ledger and notification source keys
  // provide durable idempotency across restarts.
  const lockClient = await getDirectClient();
  try {
    const lock = await lockClient.query<{ acquired: boolean }>(
      'SELECT pg_try_advisory_lock(hashtext($1)) AS acquired',
      [`prediction-settlement:${matchId}`],
    );
    if (lock.rows[0]?.acquired !== true) {
      return {
        processedCount: 0,
        pointsDistributed: 0,
        notificationCampaigns: [],
        alreadyProcessing: true,
      };
    }
    return await settleMatchPredictionsUnlocked(matchId);
  } finally {
    await lockClient.query(
      'SELECT pg_advisory_unlock(hashtext($1))',
      [`prediction-settlement:${matchId}`],
    ).catch(() => undefined);
    lockClient.release();
  }
}
