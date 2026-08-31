export type PointSource =
  | "exactPrediction"
  | "firstScorer"
  | "winnerOutcome"
  | "bothTeamsScore"
  | "videoQuestion"
  | "playerCard"
  | "dailyStreak"
  | "signUpBonus"
  | "achievement"
  | "adminAdjustment";

export const DEFAULT_POINTS = Object.freeze({
  exactPrediction: 30,
  firstScorer: 20,
  winnerOutcome: 10,
  videoQuestion: 10,
  playerCard: 10,
  dailyStreak: 0,
  signUpBonus: 0,
  memberMultiplier: 2,
});

const MEMBER_MULTIPLIER_SOURCES = new Set<PointSource>([
  "exactPrediction",
  "firstScorer",
  "winnerOutcome",
  // This legacy prediction source remains active in the Firebase settlement
  // path, so it follows the same policy as every other prediction reward.
  "bothTeamsScore",
  "videoQuestion",
  "playerCard",
]);

export function isMemberMultiplierEligible(source: PointSource): boolean {
  return MEMBER_MULTIPLIER_SOURCES.has(source);
}

/**
 * Channel membership doubles prediction rewards and video-challenge answers,
 * including Player Cards. All other activities remain at their base value even
 * if a caller accidentally asks to apply the member multiplier.
 */
export function memberMultiplierForSource(
  source: PointSource,
  membershipMultiplier: number,
  applyMembershipMultiplier = true,
): number {
  return applyMembershipMultiplier && isMemberMultiplierEligible(source) ?
    membershipMultiplier :
    1;
}

export type AdminMembershipState = {
  isYouTubeMember: boolean;
  membershipMultiplier: number;
};

/** Membership state can only be produced by a trusted admin/server action. */
export function adminMembershipState(isMember: boolean): AdminMembershipState {
  return {
    isYouTubeMember: isMember,
    membershipMultiplier: isMember ? DEFAULT_POINTS.memberMultiplier : 1,
  };
}

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
  return `points_${[source, sourceId, userId].map(idComponent).join("_")}`;
}

/**
 * Returns the football season containing the supplied UTC date. Abu 3meer
 * fallback seasons turn over on 1 July and use stable Firestore-safe IDs.
 */
export function footballSeasonId(value = new Date()): string {
  if (!Number.isFinite(value.getTime())) {
    throw new Error("Season date is invalid.");
  }
  const year = value.getUTCFullYear();
  const startYear = value.getUTCMonth() >= 6 ? year : year - 1;
  return `${startYear}-${startYear + 1}`;
}

/** Resolves an explicitly active season before falling back to the UTC date. */
export function resolveLeaderboardSeasonId(
  value: Date,
  activeSeasons: Array<{id: string; startsAtMs?: number | null}>,
): string {
  if (!Number.isFinite(value.getTime())) {
    throw new Error("Season date is invalid.");
  }
  const configured = activeSeasons
    .map((season) => ({
      id: season.id.trim(),
      startsAtMs: Number.isFinite(season.startsAtMs) ?
        season.startsAtMs as number :
        Number.NEGATIVE_INFINITY,
    }))
    .filter((season) => {
      if (!season.id) return false;
      const automatic = parseFootballSeasonId(season.id);
      return automatic == null ||
        (automatic.startsAt <= value && value < automatic.endsAt);
    })
    .sort((left, right) =>
      right.startsAtMs - left.startsAtMs || left.id.localeCompare(right.id));
  return configured[0]?.id ?? footballSeasonId(value);
}

/** Chooses a stable catalogue ownership ID for a Player Card challenge. */
export function playerCardOwnershipId(
  challengeId: string,
  catalogueIds: string[],
): string {
  const candidates = catalogueIds
    .map((value) => value.trim())
    .filter(Boolean)
    .sort();
  return candidates[0] ?? challengeId;
}

export type AchievementRequirementType =
  | "totalPoints"
  | "seasonPoints"
  | "monthlyPoints"
  | "streak"
  | "playerCards"
  | "predictions";

export type AchievementMetrics = Record<AchievementRequirementType, number>;

/** Resolves progress from server-owned counters for a configured achievement. */
export function achievementProgressValue(
  requirementType: string,
  metrics: AchievementMetrics,
): number {
  if (![
    "totalPoints",
    "seasonPoints",
    "monthlyPoints",
    "streak",
    "playerCards",
    "predictions",
  ].includes(requirementType)) {
    throw new Error("Achievement requirement type is invalid.");
  }
  const value = metrics[requirementType as AchievementRequirementType];
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("Achievement progress is invalid.");
  }
  return value;
}

/** Deterministic receipt ID for one achievement claim per user. */
export function achievementClaimId(userId: string, achievementId: string): string {
  return `achievement_${[userId, achievementId].map(idComponent).join("_")}`;
}

export type RedemptionStatus =
  | "pending"
  | "contacted"
  | "fulfilled"
  | "cancelled";

/** Restricts fulfillment to auditable forward transitions plus one safe reset. */
export function canTransitionRedemptionStatus(
  from: RedemptionStatus,
  to: RedemptionStatus,
): boolean {
  if (from === to) return true;
  if (from === "pending") {
    return to === "contacted" || to === "fulfilled" || to === "cancelled";
  }
  if (from === "contacted") {
    return to === "pending" || to === "fulfilled" || to === "cancelled";
  }
  return false;
}

/** Deterministic positive loyalty-ledger row for a cancelled redemption. */
export function redemptionRefundLedgerId(redemptionId: string): string {
  return `refund_${idComponent(redemptionId)}`;
}

export type ParsedFootballSeason = {
  displayName: string;
  startsAt: Date;
  endsAt: Date;
};

/** Parses automatic season IDs so archived season metadata remains selectable. */
export function parseFootballSeasonId(seasonId: string): ParsedFootballSeason | null {
  const match = /^(\d{4})-(\d{4})$/.exec(seasonId.trim());
  if (!match) return null;
  const startYear = Number(match[1]);
  const endYear = Number(match[2]);
  if (!Number.isSafeInteger(startYear) || endYear !== startYear + 1) return null;
  return {
    displayName: `Season ${startYear}/${endYear}`,
    startsAt: new Date(Date.UTC(startYear, 6, 1)),
    endsAt: new Date(Date.UTC(endYear, 6, 1)),
  };
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

export type ChallengeQuestionType = "text" | "multipleChoice" | "trueFalse";

export type ChallengeEvaluation = {
  correct: boolean;
  questionCount: number;
  answeredCount: number;
  normalizedAnswers: Record<string, string>;
};

export type LoyaltyRedemptionState = {
  balance: number;
  cost: number;
  stock: number | null;
  claimCount: number;
  perUserLimit: number;
};

export type LoyaltyRedemptionResult = {
  remainingBalance: number;
  stockRemaining: number | null;
  claimCount: number;
};

export type LoyaltyRefundState = {
  balance: number;
  cost: number;
  stock: number | null;
  claimCount: number;
};

export type LoyaltyRedemptionFailure =
  | "invalid-state"
  | "claim-limit"
  | "out-of-stock"
  | "insufficient-balance";

export class LoyaltyRedemptionError extends Error {
  constructor(readonly reason: LoyaltyRedemptionFailure) {
    super(reason);
    this.name = "LoyaltyRedemptionError";
  }
}

type SecretQuestion = {
  id: string;
  type: ChallengeQuestionType;
  acceptedAnswers: unknown[];
};

const TRUE_ANSWERS = new Set(["true", "yes", "1", "y", "نعم", "صح", "صحيح"]);
const FALSE_ANSWERS = new Set(["false", "no", "0", "n", "لا", "خطأ", "خاطئ"]);

/** Normalizes user/admin answer text without leaking private answer data. */
export function normalizeChallengeAnswer(
  value: unknown,
  type: ChallengeQuestionType = "text",
): string {
  if (typeof value !== "string" && typeof value !== "boolean") {
    throw new Error("Challenge answers must be strings or booleans.");
  }
  const normalized = String(value)
    .normalize("NFKC")
    .trim()
    .replace(/[\u064B-\u065F\u0670]/g, "") // remove Arabic tashkeel / harakat
    .replace(/[أإآ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/\s+/g, " ")
    .toLowerCase();
  if (!normalized || normalized.length > 240) {
    throw new Error("Challenge answer is empty or too long.");
  }
  if (type !== "trueFalse") return normalized;
  if (TRUE_ANSWERS.has(normalized)) return "true";
  if (FALSE_ANSWERS.has(normalized)) return "false";
  throw new Error("True/false answers must be boolean, yes, or no.");
}

/**
 * Evaluates legacy one-answer secrets and schema-v2 multi-question secrets.
 * The returned structure contains normalized user input only, never expected
 * answers, so callers can safely persist it in an attempt document.
 */
export function evaluateChallengeAnswers(
  answers: unknown,
  secret: unknown,
): ChallengeEvaluation {
  if (!answers || typeof answers !== "object" || Array.isArray(answers)) {
    throw new Error("Challenge answers must be an object.");
  }
  const answerEntries = Object.entries(answers as Record<string, unknown>);
  if (answerEntries.length === 0 || answerEntries.length > 20) {
    throw new Error("Challenge answers must contain 1–20 entries.");
  }
  for (const [id] of answerEntries) validateQuestionId(id);

  const secretQuestions = parseSecretQuestions(secret);
  const normalizedAnswers: Record<string, string> = {};
  let answeredCount = 0;
  let correct = true;

  for (const question of secretQuestions) {
    const raw = (answers as Record<string, unknown>)[question.id];
    if (raw === undefined || raw === null) {
      correct = false;
      continue;
    }
    const normalized = normalizeChallengeAnswer(raw, question.type);
    normalizedAnswers[question.id] = normalized;
    answeredCount += 1;
    const accepted = question.acceptedAnswers.map((candidate) =>
      normalizeChallengeAnswer(candidate, question.type),
    );
    if (!accepted.includes(normalized)) correct = false;
  }

  return {
    correct,
    questionCount: secretQuestions.length,
    answeredCount,
    normalizedAnswers,
  };
}

/** Allows scheduled content only while its server-controlled window is live. */
export function challengeIsOpen(
  status: unknown,
  nowMs: number,
  availableFromMs: number,
  availableUntilMs: number,
): boolean {
  if (![nowMs, availableFromMs, availableUntilMs].every(Number.isFinite)) {
    return false;
  }
  return ["open", "live", "scheduled"].includes(String(status)) &&
    availableFromMs <= nowMs && nowMs < availableUntilMs;
}

/** Mirrors the catalogue's enabled/status contract for server redemptions. */
export function rewardIsAvailableConfiguration(
  enabled: unknown,
  status: unknown,
): boolean {
  if (enabled === false) return false;
  const normalizedStatus = typeof status === "string" ? status.trim() : "";
  if (normalizedStatus) return ["active", "live"].includes(normalizedStatus);
  return enabled === true;
}

/** Stable document ID used by idempotent loyalty redemption transactions. */
export function redemptionLedgerId(
  userId: string,
  rewardId: string,
  idempotencyKey: string,
): string {
  return `redemption_${[userId, rewardId, idempotencyKey].map(idComponent).join("_")}`;
}

/** Stable per-user/per-reward counter ID for enforcing redemption limits. */
export function rewardClaimId(userId: string, rewardId: string): string {
  return `claim_${[userId, rewardId].map(idComponent).join("_")}`;
}

/** Computes the single atomic balance, stock, and claim-counter transition. */
export function calculateLoyaltyRedemption(
  state: LoyaltyRedemptionState,
): LoyaltyRedemptionResult {
  const integers = [
    state.balance,
    state.cost,
    state.claimCount,
    state.perUserLimit,
  ];
  if (!integers.every(Number.isSafeInteger) ||
      state.balance < 0 || state.cost < 1 || state.claimCount < 0 ||
      state.perUserLimit < 1 ||
      (state.stock !== null && (!Number.isSafeInteger(state.stock) || state.stock < 0))) {
    throw new LoyaltyRedemptionError("invalid-state");
  }
  if (state.claimCount >= state.perUserLimit) {
    throw new LoyaltyRedemptionError("claim-limit");
  }
  if (state.stock === 0) {
    throw new LoyaltyRedemptionError("out-of-stock");
  }
  if (state.balance < state.cost) {
    throw new LoyaltyRedemptionError("insufficient-balance");
  }
  return {
    remainingBalance: state.balance - state.cost,
    stockRemaining: state.stock === null ? null : state.stock - 1,
    claimCount: state.claimCount + 1,
  };
}

/** Reverses one completed redemption without allowing counter underflow. */
export function calculateLoyaltyRefund(
  state: LoyaltyRefundState,
): LoyaltyRedemptionResult {
  const integers = [state.balance, state.cost, state.claimCount];
  if (!integers.every(Number.isSafeInteger) ||
      state.balance < 0 || state.cost < 1 || state.claimCount < 1 ||
      (state.stock !== null && (!Number.isSafeInteger(state.stock) || state.stock < 0))) {
    throw new LoyaltyRedemptionError("invalid-state");
  }
  const remainingBalance = state.balance + state.cost;
  const stockRemaining = state.stock === null ? null : state.stock + 1;
  if (!Number.isSafeInteger(remainingBalance) ||
      (stockRemaining !== null && !Number.isSafeInteger(stockRemaining))) {
    throw new LoyaltyRedemptionError("invalid-state");
  }
  return {
    remainingBalance,
    stockRemaining,
    claimCount: state.claimCount - 1,
  };
}

function parseSecretQuestions(secret: unknown): SecretQuestion[] {
  if (!secret || typeof secret !== "object" || Array.isArray(secret)) {
    throw new Error("Challenge secret is missing.");
  }
  const data = secret as Record<string, unknown>;
  if (typeof data.normalizedAnswer === "string" && data.normalizedAnswer.trim()) {
    return [{id: "main", type: "text", acceptedAnswers: [data.normalizedAnswer]}];
  }
  if (!Array.isArray(data.questions) || data.questions.length === 0 || data.questions.length > 20) {
    throw new Error("Challenge secret questions are invalid.");
  }
  const seen = new Set<string>();
  return data.questions.map((raw): SecretQuestion => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error("Challenge secret question is invalid.");
    }
    const question = raw as Record<string, unknown>;
    const id = String(question.id ?? "").trim();
    validateQuestionId(id);
    if (seen.has(id)) throw new Error("Challenge question IDs must be unique.");
    seen.add(id);
    const type = String(question.type ?? "text") as ChallengeQuestionType;
    if (!["text", "multipleChoice", "trueFalse"].includes(type)) {
      throw new Error("Challenge question type is invalid.");
    }
    const candidates = Array.isArray(question.acceptedAnswers)
      ? question.acceptedAnswers
      : question.correctAnswer !== undefined
        ? [question.correctAnswer]
        : [];
    if (candidates.length === 0 || candidates.length > 20) {
      throw new Error("Challenge accepted answers are invalid.");
    }
    return {id, type, acceptedAnswers: candidates};
  });
}

function validateQuestionId(id: string): void {
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(id)) {
    throw new Error("Challenge question ID is invalid.");
  }
}

function idComponent(value: string): string {
  const encoded = encodeURIComponent(value);
  return `${encoded.length}-${encoded}`;
}
