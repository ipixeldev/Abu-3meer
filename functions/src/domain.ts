export type PointSource =
  | "exactPrediction"
  | "firstScorer"
  | "bothTeamsScore"
  | "videoQuestion"
  | "playerCard"
  | "adminAdjustment";

export const DEFAULT_POINTS = Object.freeze({
  exactPrediction: 100,
  firstScorer: 250,
  bothTeamsScore: 150,
  videoQuestion: 40,
  playerCard: 20,
  memberMultiplier: 2,
});

export function calculatePoints(basePoints: number, multiplier: number): number {
  if (!Number.isFinite(basePoints) || !Number.isFinite(multiplier)) {
    throw new Error("Points must be finite numbers.");
  }
  if (basePoints < 0 || multiplier < 0) {
    throw new Error("Points and multiplier must be non-negative.");
  }
  return Math.round(basePoints * multiplier);
}

export function rewardLedgerId(
  source: PointSource,
  sourceId: string,
  userId: string,
): string {
  return `${source}_${sourceId}_${userId}`;
}

export function predictionIsOpen(
  serverNowMs: number,
  opensAtMs: number,
  closesAtMs: number,
): boolean {
  return serverNowMs >= opensAtMs && serverNowMs < closesAtMs;
}

export function didBothTeamsScore(homeScore: number, awayScore: number): boolean {
  if (!Number.isInteger(homeScore) || !Number.isInteger(awayScore) || homeScore < 0 || awayScore < 0) {
    throw new Error("Scores must be non-negative integers.");
  }
  return homeScore > 0 && awayScore > 0;
}
