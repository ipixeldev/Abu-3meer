import type { CreateNotificationCampaignInput } from './notificationService.js';

export interface PredictionResultNotificationInput {
  predictionId: string;
  userId: string;
  matchId: string;
  homeTeam: string;
  awayTeam: string;
  homeScore: number;
  awayScore: number;
  pointsAwarded: number;
}

/**
 * Builds one durable result alert per prediction. The source key prevents a
 * worker retry or a second settlement request from notifying the same fan
 * twice, while user-specific targeting prevents result leakage to others.
 */
export function predictionResultNotificationCampaign(
  input: PredictionResultNotificationInput,
): CreateNotificationCampaignInput {
  const score = `${input.homeTeam} ${input.homeScore}–${input.awayScore} ${input.awayTeam}`;
  const outcome = input.pointsAwarded > 0
    ? `You earned ${input.pointsAwarded} XP.`
    : 'Your prediction result is ready.';
  return {
    title: 'Prediction result',
    body: `${score} · ${outcome}`,
    category: 'match',
    targetAudience: 'user_specific',
    targetUserId: input.userId,
    sourceType: 'prediction_result',
    sourceId: input.predictionId,
    data: {
      route: '/predict',
      matchId: input.matchId,
      predictionId: input.predictionId,
    },
  };
}
