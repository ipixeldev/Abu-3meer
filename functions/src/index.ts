import {initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {createPhase3SchedulingHandlers, OfficialMatchResult} from "./phase3_scheduling.js";
import {phase3CallableOptions} from "./phase3_security.js";
import {
  DEFAULT_POINTS,
  LoyaltyRedemptionError,
  PointSource,
  RedemptionStatus,
  adminMembershipState,
  achievementClaimId,
  achievementProgressValue,
  calculateLoyaltyRefund,
  calculateLoyaltyRedemption,
  calculatePoints,
  canTransitionRedemptionStatus,
  challengeIsOpen,
  didBothTeamsScore,
  evaluateChallengeAnswers,
  memberMultiplierForSource,
  parseFootballSeasonId,
  playerCardOwnershipId,
  predictionIsOpen,
  redemptionLedgerId,
  redemptionRefundLedgerId,
  resolveLeaderboardSeasonId,
  rewardIsAvailableConfiguration,
  rewardClaimId,
  rewardLedgerId,
} from "./domain.js";

initializeApp();
const db = getFirestore();
const region = "europe-west1";

type AuthContext = {
  uid: string;
  token: Record<string, unknown>;
};

function requireAuth(auth: AuthContext | undefined): AuthContext {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  return auth;
}

async function requireAdmin(uid: string): Promise<void> {
  const profile = await db.collection("users").doc(uid).get();
  const role = profile.data()?.role;
  if (role !== "admin" && role !== "superAdmin") {
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
  if (profile.data()?.suspended === true) {
    throw new HttpsError("permission-denied", "This account is suspended.");
  }
}

async function requireContentManager(uid: string): Promise<void> {
  const profile = await db.collection("users").doc(uid).get();
  const role = profile.data()?.role;
  if (!["admin", "superAdmin", "editor", "contentManager"].includes(role)) {
    throw new HttpsError("permission-denied", "Content manager access is required.");
  }
  if (profile.data()?.suspended === true) {
    throw new HttpsError("permission-denied", "This account is suspended.");
  }
}

function text(value: unknown, field: string, max = 120): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const result = value.trim();
  if (!result || result.length > max) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}

function textList(value: unknown, field: string, maxItems = 60, maxLength = 80): string[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > maxItems) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  const unique = new Map<string, string>();
  for (const item of value) {
    const label = text(item, field, maxLength).replace(/\s+/g, " ");
    unique.set(normalizedLabel(label), label);
  }
  return [...unique.values()];
}

function normalizedLabel(value: string): string {
  return value.normalize("NFKC").trim().replace(/\s+/g, " ").toLocaleLowerCase("en-US");
}

function integer(value: unknown, field: string, min = 0, max = 20): number {
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value as number;
}

function identifier(value: unknown, field: string, max = 128): string {
  const result = text(value, field, max);
  if (!/^[A-Za-z0-9_-]+$/.test(result)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}

function documentId(value: unknown, field: string, max = 512): string {
  const result = text(value, field, max);
  if (result.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}

function storedDocumentId(value: unknown, field: string, max = 512): string {
  if (typeof value !== "string" || !value.trim() ||
      value.includes("/") || value.length > max) {
    throw new HttpsError("failed-precondition", `${field} configuration is invalid.`);
  }
  return value;
}

function optionalText(value: unknown, field: string, max = 240): string {
  if (value == null) return "";
  if (typeof value !== "string" || value.trim().length > max) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value.trim();
}

function configuredInteger(
  value: unknown,
  field: string,
  fallback: number,
  min: number,
  max: number,
): number {
  if (value == null) return fallback;
  if (!Number.isInteger(value) || (value as number) < min || (value as number) > max) {
    throw new HttpsError("failed-precondition", `${field} configuration is invalid.`);
  }
  return value as number;
}

function storedTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new HttpsError("failed-precondition", `${field} configuration is invalid.`);
  }
  return value;
}

function hasVerifiedMembership(user: Record<string, unknown>): boolean {
  const multiplier = Number(user.membershipMultiplier ?? 1);
  return Number.isFinite(multiplier) && multiplier > 1;
}

function millis(value: unknown, field: string): Timestamp {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return Timestamp.fromMillis(value);
}

function periodId(date = new Date()): string {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

function utcDayNumber(value: Date): number {
  return Math.floor(Date.UTC(
    value.getUTCFullYear(),
    value.getUTCMonth(),
    value.getUTCDate(),
  ) / 86_400_000);
}

async function pointSettings(): Promise<Record<string, number>> {
  const snapshot = await db.collection("platformSettings").doc("points").get();
  return {...DEFAULT_POINTS, ...(snapshot.data() ?? {})};
}

async function currentLeaderboardSeasonId(now = Timestamp.now()): Promise<string> {
  const activeSeasons = await db.collection("leaderboardSeasons")
    .where("active", "==", true)
    .get();
  // A single active season is the expected state. If configuration briefly
  // contains more than one, prefer the newest start and then the document ID
  // so every function invocation still resolves the same season.
  return resolveLeaderboardSeasonId(
    now.toDate(),
    activeSeasons.docs.map((doc) => ({
      id: doc.id,
      startsAtMs: doc.data().startsAt instanceof Timestamp ?
        (doc.data().startsAt as Timestamp).toMillis() : null,
    })),
  );
}

function archivePreviousSeason(
  transaction: Transaction,
  params: {
    userId: string;
    previousSeasonId: unknown;
    currentSeasonId: string;
    user: Record<string, unknown>;
    leaderboard?: Record<string, unknown>;
  },
): void {
  if (typeof params.previousSeasonId !== "string") return;
  const previousSeasonId = params.previousSeasonId.trim();
  if (!previousSeasonId || previousSeasonId === params.currentSeasonId ||
      previousSeasonId.includes("/") || previousSeasonId.length > 512) {
    return;
  }

  const archivedAt = FieldValue.serverTimestamp();
  const parsed = parseFootballSeasonId(previousSeasonId);
  const currentParsed = parseFootballSeasonId(params.currentSeasonId);
  const seasonRef = db.collection("leaderboardSeasons").doc(previousSeasonId);
  const archivedEntryRef = seasonRef.collection("entries").doc(params.userId);
  const leaderboard = params.leaderboard ?? {};
  transaction.set(seasonRef, {
    active: false,
    archiveMode: "lazy-rollover",
    lastArchivedAt: archivedAt,
    updatedAt: archivedAt,
    ...(parsed == null ? {} : {
      automatic: true,
      displayName: parsed.displayName,
      startsAt: Timestamp.fromDate(parsed.startsAt),
      endsAt: Timestamp.fromDate(parsed.endsAt),
    }),
  }, {merge: true});
  if (currentParsed != null) {
    transaction.set(
      db.collection("leaderboardSeasons").doc(params.currentSeasonId),
      {
        active: true,
        automatic: true,
        displayName: currentParsed.displayName,
        startsAt: Timestamp.fromDate(currentParsed.startsAt),
        endsAt: Timestamp.fromDate(currentParsed.endsAt),
        updatedAt: archivedAt,
      },
      {merge: true},
    );
  }
  transaction.set(archivedEntryRef, {
    username: params.user.username ?? leaderboard.username ?? "",
    avatarUrl: params.user.avatarUrl ?? leaderboard.avatarUrl ?? "",
    supportedTeam: params.user.supportedTeam ?? leaderboard.supportedTeam ?? "",
    monthlyPoints: params.user.monthlyPoints ?? leaderboard.monthlyPoints ?? 0,
    seasonPoints: params.user.seasonPoints ?? leaderboard.seasonPoints ?? 0,
    totalPoints: params.user.totalPoints ?? leaderboard.totalPoints ?? 0,
    isMember: Number(params.user.membershipMultiplier ?? 1) > 1,
    monthlyPeriod: params.user.monthlyPeriod ?? leaderboard.monthlyPeriod ?? "",
    seasonId: previousSeasonId,
    archivedAt,
    updatedAt: archivedAt,
  }, {merge: true});
}

async function awardPoints(params: {
  userId: string;
  sourceType: PointSource;
  sourceId: string;
  basePoints: number;
  reason: string;
  adminId?: string;
  applyMembershipMultiplier?: boolean;
}): Promise<{awarded: boolean; finalPoints: number}> {
  const ledgerId = rewardLedgerId(params.sourceType, params.sourceId, params.userId);
  const userRef = db.collection("users").doc(params.userId);
  const ledgerRef = db.collection("pointTransactions").doc(ledgerId);
  const leaderboardRef = db.collection("leaderboardEntries").doc(params.userId);
  const currentPeriod = periodId();
  const activityAt = Timestamp.now();
  const currentSeason = await currentLeaderboardSeasonId(activityAt);

  return db.runTransaction(async (transaction) => {
    const [existing, userSnapshot, leaderboardSnapshot] = await Promise.all([
      transaction.get(ledgerRef),
      transaction.get(userRef),
      transaction.get(leaderboardRef),
    ]);
    if (existing.exists) {
      const existingPoints = Number(existing.data()?.finalPoints ?? 0);
      return {
        awarded: false,
        finalPoints: Number.isSafeInteger(existingPoints) && existingPoints >= 0 ? existingPoints : 0,
      };
    }
    if (!userSnapshot.exists) {
      throw new HttpsError("failed-precondition", "User profile is missing.");
    }
    const user = userSnapshot.data()!;
    if (user.suspended === true) {
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
    const membershipMultiplier = Number(user.membershipMultiplier ?? 1);
    const multiplier = memberMultiplierForSource(
      params.sourceType,
      membershipMultiplier,
      params.applyMembershipMultiplier !== false,
    );
    const finalPoints = calculatePoints(params.basePoints, multiplier);
    const sameMonth = user.monthlyPeriod === currentPeriod;
    // Empty season IDs are legacy/current-season records. Preserve their
    // points once, then stamp the deterministic server-owned season ID.
    const sameSeason = !user.seasonId || user.seasonId === currentSeason;
    const monthlyPoints = (sameMonth ? Number(user.monthlyPoints ?? 0) : 0) + finalPoints;
    const seasonPoints = (sameSeason ? Number(user.seasonPoints ?? 0) : 0) + finalPoints;
    const totalPoints = Number(user.totalPoints ?? 0) + finalPoints;
    const loyaltyPoints = Number(user.loyaltyPoints ?? user.seasonPoints ?? 0) + finalPoints;
    const lastActivity = user.lastActivityAt instanceof Timestamp
      ? user.lastActivityAt as Timestamp
      : null;
    const dayGap = lastActivity == null
      ? null
      : utcDayNumber(activityAt.toDate()) - utcDayNumber(lastActivity.toDate());
    const previousStreak = Number(user.currentStreak ?? 0);
    const currentStreak = dayGap === 0
      ? Math.max(previousStreak, 1)
      : dayGap === 1
        ? previousStreak + 1
        : 1;
    const longestStreak = Math.max(Number(user.longestStreak ?? 0), currentStreak);
    const createdAt = FieldValue.serverTimestamp();

    if (!sameSeason) {
      archivePreviousSeason(transaction, {
        userId: params.userId,
        previousSeasonId: user.seasonId,
        currentSeasonId: currentSeason,
        user,
        leaderboard: leaderboardSnapshot.data(),
      });
    }

    transaction.create(ledgerRef, {
      userId: params.userId,
      sourceType: params.sourceType,
      sourceId: params.sourceId,
      basePoints: params.basePoints,
      multiplier,
      finalPoints,
      reason: params.reason,
      adminId: params.adminId ?? null,
      createdAt,
      monthlyPeriod: currentPeriod,
      seasonId: currentSeason,
    });
    transaction.update(userRef, {
      totalPoints,
      monthlyPoints,
      seasonPoints,
      loyaltyPoints,
      currentStreak,
      longestStreak,
      lastActivityAt: activityAt,
      monthlyPeriod: currentPeriod,
      seasonId: currentSeason,
      updatedAt: createdAt,
    });
    const entry = {
      username: user.username ?? "",
      avatarUrl: user.avatarUrl ?? "",
      supportedTeam: user.supportedTeam ?? "",
      monthlyPoints,
      seasonPoints,
      totalPoints,
      isMember: membershipMultiplier > 1,
      monthlyPeriod: currentPeriod,
      seasonId: currentSeason,
      updatedAt: createdAt,
    };
    leaderboardSnapshot.exists ? transaction.update(leaderboardRef, entry) : transaction.create(leaderboardRef, entry);
    return {awarded: true, finalPoints};
  });
}

export const completeOnboarding = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const username = text(request.data?.username, "Username", 24).toLowerCase();
  if (!/^[a-z0-9_]{3,24}$/.test(username)) {
    throw new HttpsError("invalid-argument", "Username must be 3–24 letters, numbers, or underscores.");
  }
  const displayName = text(request.data?.displayName, "Display name", 60);
  const country = text(request.data?.country, "Country", 60);
  const supportedTeam = text(request.data?.supportedTeam, "Supported team", 20);
  if (!["Barcelona", "Real Madrid"].includes(supportedTeam)) {
    throw new HttpsError("invalid-argument", "Choose Barcelona or Real Madrid.");
  }
  const avatarUrl = typeof request.data?.avatarUrl === "string" ? request.data.avatarUrl.trim() : "";
  const usernameRef = db.collection("usernames").doc(username);
  const userRef = db.collection("users").doc(auth.uid);
  const leaderboardRef = db.collection("leaderboardEntries").doc(auth.uid);
  const currentSeason = await currentLeaderboardSeasonId();
  await db.runTransaction(async (transaction) => {
    const [claimed, existing, leaderboardSnapshot] = await Promise.all([
      transaction.get(usernameRef),
      transaction.get(userRef),
      transaction.get(leaderboardRef),
    ]);
    if (claimed.exists && claimed.data()?.uid !== auth.uid) {
      throw new HttpsError("already-exists", "That username is already taken.");
    }
    const oldUsername = existing.data()?.username;
    if (oldUsername && oldUsername !== username) {
      transaction.delete(db.collection("usernames").doc(oldUsername));
    }
    const existingSeasonId = String(existing.data()?.seasonId ?? "");
    const seasonPoints = !existingSeasonId || existingSeasonId === currentSeason ?
      existing.data()?.seasonPoints ?? 0 :
      0;
    const totalPoints = existing.data()?.totalPoints ?? 0;
    const now = FieldValue.serverTimestamp();
    if (existing.exists && existingSeasonId && existingSeasonId !== currentSeason) {
      archivePreviousSeason(transaction, {
        userId: auth.uid,
        previousSeasonId: existingSeasonId,
        currentSeasonId: currentSeason,
        user: existing.data()!,
        leaderboard: leaderboardSnapshot.data(),
      });
    }
    transaction.set(usernameRef, {uid: auth.uid, createdAt: now});
    transaction.set(userRef, {
      email: auth.token.email ?? "",
      username,
      displayName,
      country,
      supportedTeam,
      avatarUrl,
      role: existing.data()?.role ?? "user",
      membershipMultiplier: existing.data()?.membershipMultiplier ?? 1,
      suspended: existing.data()?.suspended ?? false,
      totalPoints,
      monthlyPoints: existing.data()?.monthlyPoints ?? 0,
      seasonPoints,
      loyaltyPoints: existing.data()?.loyaltyPoints ?? existing.data()?.seasonPoints ?? 0,
      currentStreak: existing.data()?.currentStreak ?? 0,
      longestStreak: existing.data()?.longestStreak ?? 0,
      lastActivityAt: existing.data()?.lastActivityAt ?? null,
      monthlyPeriod: existing.data()?.monthlyPeriod ?? periodId(),
      seasonId: currentSeason,
      onboardingComplete: true,
      createdAt: existing.data()?.createdAt ?? now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(leaderboardRef, {
      username,
      avatarUrl,
      supportedTeam,
      monthlyPoints: existing.data()?.monthlyPoints ?? 0,
      seasonPoints,
      totalPoints,
      isMember: Number(existing.data()?.membershipMultiplier ?? 1) > 1,
      monthlyPeriod: existing.data()?.monthlyPeriod ?? periodId(),
      seasonId: currentSeason,
      updatedAt: now,
    }, {merge: true});
  });
  return {ok: true};
});

export const submitPrediction = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const matchId = text(request.data?.matchId, "Match", 128);
  const homeScore = integer(request.data?.homeScore, "Home score");
  const awayScore = integer(request.data?.awayScore, "Away score");
  const firstScorerInput = text(request.data?.firstScorer, "First scorer", 80).replace(/\s+/g, " ");
  if (typeof request.data?.bothTeamsScore !== "boolean") {
    throw new HttpsError("invalid-argument", "Both teams score prediction is required.");
  }
  const bothTeamsScore = request.data.bothTeamsScore as boolean;
  const matchRef = db.collection("matches").doc(matchId);
  const predictionRef = db.collection("predictions").doc(`${matchId}_${auth.uid}`);

  const passedHomeTeam = typeof request.data?.homeTeam === "string" ? String(request.data.homeTeam).trim() : "";
  const passedAwayTeam = typeof request.data?.awayTeam === "string" ? String(request.data.awayTeam).trim() : "";
  const passedCompetition = typeof request.data?.competition === "string" ? String(request.data.competition).trim() : "La Liga";
  const passedHomeLogo = typeof request.data?.homeLogoUrl === "string" ? String(request.data.homeLogoUrl).trim() : "";
  const passedAwayLogo = typeof request.data?.awayLogoUrl === "string" ? String(request.data.awayLogoUrl).trim() : "";

  const pointsEarned = 10;

  await db.runTransaction(async (transaction) => {
    const [matchSnapshot, userSnapshot, existingPrediction] = await Promise.all([
      transaction.get(matchRef),
      transaction.get(db.collection("users").doc(auth.uid)),
      transaction.get(predictionRef),
    ]);

    if (userSnapshot.data()?.suspended === true) throw new HttpsError("permission-denied", "Account suspended.");
    if (existingPrediction.exists) {
      throw new HttpsError("already-exists", "You have already locked your prediction for this match.");
    }

    let matchHomeTeam = passedHomeTeam;
    let matchAwayTeam = passedAwayTeam;

    if (!matchSnapshot.exists) {
      const kickoffAt = request.data?.kickoffAt ? millis(request.data.kickoffAt, "Kickoff") : Timestamp.fromMillis(Date.now() + 86400000);
      const predictionOpensAt = Timestamp.fromMillis(Date.now() - 86400000);
      const predictionClosesAt = kickoffAt;
      transaction.set(matchRef, {
        homeTeam: passedHomeTeam || "Home",
        awayTeam: passedAwayTeam || "Away",
        competition: passedCompetition,
        homeLogoUrl: passedHomeLogo,
        awayLogoUrl: passedAwayLogo,
        firstScorerOptions: [firstScorerInput, "No scorer"],
        kickoffAt,
        predictionOpensAt,
        predictionClosesAt,
        status: "open",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      matchHomeTeam = passedHomeTeam || "Home";
      matchAwayTeam = passedAwayTeam || "Away";
    } else {
      const match = matchSnapshot.data()!;
      matchHomeTeam = match.homeTeam ?? passedHomeTeam;
      matchAwayTeam = match.awayTeam ?? passedAwayTeam;
      const now = Timestamp.now().toMillis();
      const kickoffMs = match.kickoffAt ? match.kickoffAt.toMillis() : (match.predictionClosesAt ? match.predictionClosesAt.toMillis() : now + 86400000);
      if (match.status !== "open" && match.status !== "upcoming") {
        throw new HttpsError("failed-precondition", "Predictions are currently closed for this match.");
      }
      if (now >= kickoffMs && match.status !== "open") {
        throw new HttpsError("failed-precondition", "Match has already kicked off.");
      }
    }

    const firstScorerKey = normalizedLabel(firstScorerInput);

    transaction.set(predictionRef, {
      userId: auth.uid,
      matchId,
      homeTeam: matchHomeTeam,
      awayTeam: matchAwayTeam,
      homeScore,
      awayScore,
      firstScorer: firstScorerInput,
      firstScorerKey,
      bothTeamsScore,
      submittedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      rewarded: false,
    }, {merge: true});

    const userData = userSnapshot.data() ?? {};
    const totalPoints = (userData.totalPoints ?? 0) + pointsEarned;
    const monthlyPoints = (userData.monthlyPoints ?? 0) + pointsEarned;
    const seasonPoints = (userData.seasonPoints ?? 0) + pointsEarned;
    const loyaltyPoints = (userData.loyaltyPoints ?? 0) + pointsEarned;

    transaction.update(db.collection("users").doc(auth.uid), {
      totalPoints,
      monthlyPoints,
      seasonPoints,
      loyaltyPoints,
      lastActivityAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const leaderboardRef = db.collection("leaderboardEntries").doc(auth.uid);
    transaction.set(leaderboardRef, {
      totalPoints,
      monthlyPoints,
      seasonPoints,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const txRef = db.collection("pointTransactions").doc();
    transaction.set(txRef, {
      userId: auth.uid,
      type: "prediction_participation",
      points: pointsEarned,
      description: `Prediction locked: ${matchHomeTeam} vs ${matchAwayTeam}`,
      sourceId: matchId,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {ok: true, pointsEarned};
});

export const adminToggleMatchPredictions = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const matchId = text(request.data?.matchId, "Match", 128);
  const open = Boolean(request.data?.open);
  const matchRef = db.collection("matches").doc(matchId);
  const snapshot = await matchRef.get();
  if (!snapshot.exists) {
    const homeTeam = typeof request.data?.homeTeam === "string" ? String(request.data.homeTeam).trim() : "Home";
    const awayTeam = typeof request.data?.awayTeam === "string" ? String(request.data.awayTeam).trim() : "Away";
    const competition = typeof request.data?.competition === "string" ? String(request.data.competition).trim() : "La Liga";
    const homeLogoUrl = typeof request.data?.homeLogoUrl === "string" ? String(request.data.homeLogoUrl).trim() : "";
    const awayLogoUrl = typeof request.data?.awayLogoUrl === "string" ? String(request.data.awayLogoUrl).trim() : "";
    const kickoffAt = request.data?.kickoffAt ? millis(request.data.kickoffAt, "Kickoff") : Timestamp.fromMillis(Date.now() + 86400000);
    await matchRef.set({
      homeTeam,
      awayTeam,
      competition,
      homeLogoUrl,
      awayLogoUrl,
      firstScorerOptions: ["No scorer"],
      kickoffAt,
      predictionOpensAt: Timestamp.fromMillis(Date.now() - 86400000),
      predictionClosesAt: open ? Timestamp.fromMillis(Date.now() + 7 * 86400000) : Timestamp.now(),
      status: open ? "open" : "locked",
      createdBy: auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    await matchRef.update({
      status: open ? "open" : "locked",
      predictionClosesAt: open ? Timestamp.fromMillis(Date.now() + 7 * 86400000) : Timestamp.now(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await db.collection("adminAuditLogs").add({
    adminId: auth.uid,
    action: open ? "OPEN_PREDICTIONS" : "CLOSE_PREDICTIONS",
    targetId: matchId,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, status: open ? "open" : "locked"};
});

export const adminCreateMatch = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const kickoffAt = millis(request.data?.kickoffAt, "Kickoff");
  const predictionOpensAt = millis(request.data?.predictionOpensAt, "Prediction opening");
  const predictionClosesAt = millis(request.data?.predictionClosesAt, "Prediction closing");
  if (!(predictionOpensAt.toMillis() < predictionClosesAt.toMillis() && predictionClosesAt.toMillis() <= kickoffAt.toMillis())) {
    throw new HttpsError("invalid-argument", "Prediction times must be ordered before kickoff.");
  }
  const ref = db.collection("matches").doc();
  const firstScorerOptions = textList(request.data?.firstScorerOptions, "First scorer options", 59);
  if (firstScorerOptions.length > 0 && !firstScorerOptions.some((option) => normalizedLabel(option) === "no scorer")) {
    firstScorerOptions.push("No scorer");
  }
  await ref.create({
    homeTeam: text(request.data?.homeTeam, "Home team", 60),
    awayTeam: text(request.data?.awayTeam, "Away team", 60),
    competition: text(request.data?.competition, "Competition", 80),
    homeLogoUrl: typeof request.data?.homeLogoUrl === "string" ? request.data.homeLogoUrl.trim() : "",
    awayLogoUrl: typeof request.data?.awayLogoUrl === "string" ? request.data.awayLogoUrl.trim() : "",
    firstScorerOptions,
    kickoffAt,
    predictionOpensAt,
    predictionClosesAt,
    status: "open",
    createdBy: auth.uid,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("adminAuditLogs").add({adminId: auth.uid, action: "CREATE_MATCH", targetId: ref.id, createdAt: FieldValue.serverTimestamp()});
  return {ok: true, matchId: ref.id};
});


async function internalSettleMatchResult(result: OfficialMatchResult, adminId: string | null = null, jobId?: string) {
  const matchId = result.matchId;
  const homeScore = result.homeScore;
  const awayScore = result.awayScore;
  const firstScorerInput = result.firstScorer;
  const firstScorerKey = normalizedLabel(firstScorerInput);
  const bothTeamsScored = didBothTeamsScore(homeScore, awayScore);
  const resultHash = JSON.stringify([homeScore, awayScore, firstScorerKey]);
  const matchRef = db.collection("matches").doc(matchId);
  await db.runTransaction(async (transaction) => {
    const match = await transaction.get(matchRef);
    if (!match.exists) throw new HttpsError("not-found", "Match not found.");
    const data = match.data()!;
    const options = textList(data.firstScorerOptions, "First scorer options");
    if (options.length > 0 && !options.some((option) => normalizedLabel(option) === firstScorerKey)) {
      throw new HttpsError("invalid-argument", "Choose the official first scorer from the match options.");
    }
    if (data.resultProcessed === true) {
      const sameResult = data.homeScore === homeScore &&
        data.awayScore === awayScore &&
        normalizedLabel(String(data.firstScorer ?? "")) === firstScorerKey;
      if (sameResult) return; // Duplicate
      throw new HttpsError(
        "already-exists",
        "This result was already processed with a different score."
      );
    }
    if (data.resultProcessing === true) {
      const processingHash = typeof data.resultProcessingHash === "string" ?
        data.resultProcessingHash :
        JSON.stringify([
          Number(data.homeScore),
          Number(data.awayScore),
          normalizedLabel(String(data.firstScorer ?? "")),
        ]);
      if (processingHash !== resultHash) {
        throw new HttpsError(
          "failed-precondition",
          "A different result is already being processed for this match."
        );
      }
    }
    transaction.update(matchRef, {
      homeScore,
      awayScore,
      firstScorer: firstScorerInput,
      firstScorerKey,
      bothTeamsScored,
      status: "completed",
      resultProcessing: true,
      resultProcessingHash: resultHash,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  // If it returned early from transaction (meaning it was a duplicate and same result),
  // we check if it is already processed to avoid re-processing.
  const matchAfterTx = await matchRef.get();
  if (matchAfterTx.data()?.resultProcessed === true && matchAfterTx.data()?.resultProcessing === false) {
    return { duplicate: true };
  }

  const settings = await pointSettings();
  const [allPredictions, exactWinners, firstScorerWinners, bothTeamsWinners] = await Promise.all([
    db.collection("predictions")
      .where("matchId", "==", matchId)
      .get(),
    db.collection("predictions")
      .where("matchId", "==", matchId)
      .where("homeScore", "==", homeScore)
      .where("awayScore", "==", awayScore)
      .get(),
    db.collection("predictions")
      .where("matchId", "==", matchId)
      .where("firstScorerKey", "==", firstScorerKey)
      .get(),
    db.collection("predictions")
      .where("matchId", "==", matchId)
      .where("bothTeamsScore", "==", bothTeamsScored)
      .get(),
  ]);
  const awardWinners = async (
    docs: QueryDocumentSnapshot[],
    sourceType: PointSource,
    basePoints: number,
    reason: string,
  ): Promise<Map<string, number>> => {
    const pointsByPrediction = new Map<string, number>();
    for (let index = 0; index < docs.length; index += 40) {
      const chunk = docs.slice(index, index + 40);
      const results = await Promise.all(chunk.map((doc) => awardPoints({
        userId: doc.data().userId,
        sourceType,
        sourceId: matchId,
        basePoints,
        reason,
      })));
      results.forEach((result, resultIndex) => {
        pointsByPrediction.set(chunk[resultIndex].id, result.finalPoints);
      });
    }
    return pointsByPrediction;
  };
  const [exactPoints, firstScorerPoints, bothTeamsPoints] = await Promise.all([
    awardWinners(
      exactWinners.docs,
      "exactPrediction",
      Number(settings.exactPrediction),
      `Exact prediction: ${homeScore}–${awayScore}`,
    ),
    awardWinners(
      firstScorerWinners.docs,
      "firstScorer",
      Number(settings.firstScorer),
      `First scorer: ${firstScorerInput}`,
    ),
    awardWinners(
      bothTeamsWinners.docs,
      "bothTeamsScore",
      Number(settings.bothTeamsScore),
      `Both teams score: ${bothTeamsScored ? "Yes" : "No"}`,
    ),
  ]);
  const predictionWriter = db.bulkWriter();
  for (const prediction of allPredictions.docs) {
    const exact = exactPoints.get(prediction.id) ?? 0;
    const scorer = firstScorerPoints.get(prediction.id) ?? 0;
    const bothTeams = bothTeamsPoints.get(prediction.id) ?? 0;
    const pointsAwarded = exact + scorer + bothTeams;
    predictionWriter.update(prediction.ref, {
      rewarded: pointsAwarded > 0,
      pointsAwarded,
      rewardBreakdown: {
        exactPrediction: exact,
        firstScorer: scorer,
        bothTeamsScore: bothTeams,
      },
      resultEvaluatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await predictionWriter.close();
  const exactAwarded = exactWinners.size;
  const firstScorerAwarded = firstScorerWinners.size;
  const bothTeamsAwarded = bothTeamsWinners.size;
  const awarded = exactAwarded + firstScorerAwarded + bothTeamsAwarded;
  await matchRef.update({
    resultProcessed: true,
    resultProcessing: false,
    resultProcessingHash: null,
    resultHash,
    rewardedUsers: awarded,
    exactRewardedUsers: exactAwarded,
    firstScorerRewardedUsers: firstScorerAwarded,
    bothTeamsRewardedUsers: bothTeamsAwarded,
    processedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("adminAuditLogs").add({
    adminId: adminId ?? "SYSTEM",
    action: "PUBLISH_MATCH_RESULT",
    targetId: matchId,
    awardedUsers: awarded,
    exactAwarded,
    firstScorerAwarded,
    bothTeamsAwarded,
    jobId: jobId ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, awardedUsers: awarded, exactAwarded, firstScorerAwarded, bothTeamsAwarded, duplicate: false};
}

export const adminPublishMatchResult = onCall({ ...phase3CallableOptions(region), timeoutSeconds: 540 }, async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const matchId = text(request.data?.matchId, "Match", 128);
  const homeScore = integer(request.data?.homeScore, "Home score");
  const awayScore = integer(request.data?.awayScore, "Away score");
  const firstScorerInput = text(request.data?.firstScorer, "First scorer", 80).replace(/\s+/g, " ");

  const result = await internalSettleMatchResult({ matchId, homeScore, awayScore, firstScorer: firstScorerInput }, auth.uid);
  if (result.duplicate) {
      throw new HttpsError("already-exists", "This result was already processed.");
  }
  return result;
});
export const adminUpdatePointRules = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const exactPrediction = integer(request.data?.exactPrediction, "Exact prediction points", 0, 10000);
  const firstScorer = integer(request.data?.firstScorer, "First scorer points", 0, 10000);
  const bothTeamsScore = integer(request.data?.bothTeamsScore, "Both teams score points", 0, 10000);
  const videoQuestion = integer(request.data?.videoQuestion, "Video question points", 0, 10000);
  const playerCard = integer(request.data?.playerCard, "Player Card points", 0, 10000);
  const memberMultiplier = Number(request.data?.memberMultiplier);
  if (!Number.isFinite(memberMultiplier) || memberMultiplier < 1 || memberMultiplier > 10) {
    throw new HttpsError("invalid-argument", "Member multiplier must be between 1 and 10.");
  }
  await db.collection("platformSettings").doc("points").set({exactPrediction, firstScorer, bothTeamsScore, videoQuestion, playerCard, memberMultiplier, updatedBy: auth.uid, updatedAt: FieldValue.serverTimestamp()});
  await db.collection("adminAuditLogs").add({adminId: auth.uid, action: "UPDATE_POINT_RULES", changes: {exactPrediction, firstScorer, bothTeamsScore, videoQuestion, playerCard, memberMultiplier}, createdAt: FieldValue.serverTimestamp()});
  return {ok: true};
});

type ChallengeCollection = "videoQuestions" | "playerCards";
type ChallengeType =
  | "videoPhrase"
  | "playerCard"
  | "multipleChoice"
  | "trueFalse"
  | "multiQuestion";

type ChallengeAttemptOutcome = {
  correct: boolean;
  basePoints: number;
  attemptCount: number;
  maximumAttempts: number;
  remainingAttempts: number;
  challengeType: ChallengeType;
};

function canonicalChallengeType(
  value: unknown,
  collection: ChallengeCollection,
): ChallengeType {
  const raw = String(value ?? (collection === "playerCards" ? "playerCard" : "videoPhrase"));
  const canonical = raw === "quiz"
    ? "multiQuestion"
    : raw === "videoQuestion" || raw === "secretPhrase"
      ? "videoPhrase"
      : raw;
  if (!["videoPhrase", "playerCard", "multipleChoice", "trueFalse", "multiQuestion"].includes(canonical)) {
    throw new HttpsError("failed-precondition", "Challenge type configuration is invalid.");
  }
  return canonical as ChallengeType;
}

async function submitChallengeAttempt(params: {
  uid: string;
  collection: ChallengeCollection;
  id: string;
  answers: unknown;
}): Promise<{
  correct: boolean;
  points: number;
  awarded: boolean;
  attemptCount: number;
  remainingAttempts: number;
  completed: boolean;
  challengeType: ChallengeType;
}> {
  const sourceType: "videoQuestion" | "playerCard" =
    params.collection === "playerCards" ? "playerCard" : "videoQuestion";
  const publicRef = db.collection(params.collection).doc(params.id);
  const secretRef = publicRef.collection("private").doc("answer");
  const attemptRef = publicRef.collection("attempts").doc(params.uid);
  const userRef = db.collection("users").doc(params.uid);
  const settings = await pointSettings();
  const fallbackPoints = configuredInteger(
    settings[sourceType],
    `${sourceType} points`,
    DEFAULT_POINTS[sourceType],
    0,
    10_000,
  );

  const outcome = await db.runTransaction(async (transaction): Promise<ChallengeAttemptOutcome> => {
    const [publicDoc, secretDoc, attemptDoc, userDoc] = await Promise.all([
      transaction.get(publicRef),
      transaction.get(secretRef),
      transaction.get(attemptRef),
      transaction.get(userRef),
    ]);
    if (!publicDoc.exists) throw new HttpsError("not-found", "Challenge not found.");
    if (!userDoc.exists) throw new HttpsError("failed-precondition", "User profile is missing.");
    const challenge = publicDoc.data()!;
    const user = userDoc.data()!;
    if (user.suspended === true) {
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
    const challengeType = canonicalChallengeType(
      challenge.challengeType ?? challenge.kind,
      params.collection,
    );
    const maximumAttempts = configuredInteger(
      challenge.maximumAttempts,
      "Maximum attempts",
      5,
      1,
      100,
    );
    const configuredPoints = configuredInteger(
      challenge.rewardPoints,
      "Reward points",
      fallbackPoints,
      0,
      10_000,
    );
    const attempt = attemptDoc.data();
    const attemptCount = configuredInteger(
      attempt?.attemptCount,
      "Attempt count",
      0,
      0,
      100,
    );

    // A successful attempt is immutable. Replaying it outside the transaction
    // lets a previous partial failure recover the deterministic point award.
    if (attempt?.correct === true) {
      const basePoints = configuredInteger(
        attempt.basePoints,
        "Attempt reward points",
        configuredPoints,
        0,
        10_000,
      );
      return {
        correct: true,
        basePoints,
        attemptCount,
        maximumAttempts,
        remainingAttempts: Math.max(0, maximumAttempts - attemptCount),
        challengeType,
      };
    }

    if (challenge.memberOnly === true && !hasVerifiedMembership(user)) {
      throw new HttpsError("permission-denied", "This challenge is for verified members.");
    }
    const availableFrom = storedTimestamp(challenge.availableFrom, "Challenge start");
    const availableUntil = storedTimestamp(challenge.availableUntil, "Challenge end");
    if (!challengeIsOpen(
      challenge.status,
      Timestamp.now().toMillis(),
      availableFrom.toMillis(),
      availableUntil.toMillis(),
    )) {
      throw new HttpsError("failed-precondition", "This challenge is not open.");
    }
    if (!secretDoc.exists) {
      throw new HttpsError("failed-precondition", "Challenge answer configuration is missing.");
    }
    if (attemptCount >= maximumAttempts) {
      throw new HttpsError("resource-exhausted", "No challenge attempts remain.");
    }
    let evaluation;
    try {
      evaluation = evaluateChallengeAnswers(params.answers, secretDoc.data());
    } catch (error) {
      const message = error instanceof Error ? error.message : "Challenge answers are invalid.";
      throw new HttpsError("invalid-argument", message);
    }
    const nextAttemptCount = attemptCount + 1;
    const remainingAttempts = Math.max(0, maximumAttempts - nextAttemptCount);
    const submittedAt = FieldValue.serverTimestamp();
    transaction.set(attemptRef, {
      userId: params.uid,
      challengeId: params.id,
      challengeType,
      answers: evaluation.normalizedAnswers,
      correct: evaluation.correct,
      attemptCount: nextAttemptCount,
      maximumAttempts,
      remainingAttempts,
      basePoints: configuredPoints,
      submittedAt,
      completedAt: evaluation.correct ? submittedAt : null,
      pointsEarned: 0,
      rewarded: false,
    }, {merge: true});
    transaction.update(publicRef, {
      lastAttemptAt: submittedAt,
      updatedAt: submittedAt,
    });
    return {
      correct: evaluation.correct,
      basePoints: configuredPoints,
      attemptCount: nextAttemptCount,
      maximumAttempts,
      remainingAttempts,
      challengeType,
    };
  });

  if (!outcome.correct) {
    return {
      correct: false,
      points: 0,
      awarded: false,
      attemptCount: outcome.attemptCount,
      remainingAttempts: outcome.remainingAttempts,
      completed: false,
      challengeType: outcome.challengeType,
    };
  }

  let playerCardId: string | null = null;
  if (sourceType === "playerCard") {
    const [privateLink, legacyCatalogue] = await Promise.all([
      db.collection("playerCardChallengeLinks").doc(params.id).get(),
      // Read compatibility for cards created before links were moved out of
      // documents that every signed-in user can inspect.
      db.collection("playerCards")
        .where("sourceChallengeId", "==", params.id)
        .get(),
    ]);
    const configuredCardId = String(privateLink.data()?.cardId ?? "").trim();
    const mappedCardIds = /^[A-Za-z0-9_-]{1,128}$/.test(configuredCardId) ?
      [configuredCardId] :
      legacyCatalogue.docs.map((doc) => doc.id);
    if (mappedCardIds.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "This Player Card challenge is not linked to a catalogue card.",
      );
    }
    playerCardId = playerCardOwnershipId(params.id, mappedCardIds);
    const catalogueCard = await db.collection("playerCards").doc(playerCardId).get();
    if (!catalogueCard.exists || catalogueCard.data()?.documentType === "challenge") {
      throw new HttpsError(
        "failed-precondition",
        "The linked Player Card catalogue entry is missing.",
      );
    }
  }

  const award = await awardPoints({
    userId: params.uid,
    sourceType,
    sourceId: params.id,
    basePoints: outcome.basePoints,
    reason: sourceType === "videoQuestion" ? "Challenge completed" : "Player Card found",
  });
  await attemptRef.set({
    pointsEarned: award.finalPoints,
    rewarded: true,
    rewardedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  if (playerCardId !== null) {
    await userRef.collection("playerCards").doc(playerCardId).set({
      cardId: playerCardId,
      sourceChallengeId: params.id,
      challengeType: outcome.challengeType,
      pointsEarned: award.finalPoints,
      foundAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  return {
    correct: true,
    points: award.finalPoints,
    awarded: award.awarded,
    attemptCount: outcome.attemptCount,
    remainingAttempts: outcome.remainingAttempts,
    completed: true,
    challengeType: outcome.challengeType,
  };
}

export const submitChallenge = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const collection = request.data?.collection;
  if (collection !== "videoQuestions" && collection !== "playerCards") {
    throw new HttpsError("invalid-argument", "Challenge collection is invalid.");
  }
  return submitChallengeAttempt({
    uid: auth.uid,
    collection,
    id: identifier(request.data?.challengeId, "Challenge", 128),
    answers: request.data?.answers,
  });
});

// Backward-compatible name used by released Flutter builds for the advanced
// challenge UI. Keep the payload translation server-side so those builds do
// not fail with functions/not-found while newer clients use submitChallenge.
export const submitChallengeAnswers = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const challengeKind = String(request.data?.kind ?? "");
  if (![
    "videoPhrase",
    "videoQuestion",
    "secretPhrase",
    "multipleChoice",
    "trueFalse",
    "multiQuestion",
    "quiz",
    "playerCard",
  ].includes(challengeKind)) {
    throw new HttpsError("invalid-argument", "Challenge type is invalid.");
  }
  return submitChallengeAttempt({
    uid: auth.uid,
    collection: challengeKind === "playerCard" ? "playerCards" : "videoQuestions",
    id: identifier(request.data?.challengeId, "Challenge", 128),
    answers: request.data?.answers,
  });
});

export const submitVideoAnswer = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  return submitChallengeAttempt({
    uid: auth.uid,
    collection: "videoQuestions",
    id: identifier(request.data?.questionId, "Question", 128),
    answers: {main: text(request.data?.answer, "Answer", 240)},
  });
});

export const claimPlayerCard = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  return submitChallengeAttempt({
    uid: auth.uid,
    collection: "playerCards",
    id: identifier(request.data?.cardId, "Player Card", 128),
    answers: {main: text(request.data?.answer, "Answer", 240)},
  });
});

export const claimAchievement = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const achievementId = documentId(
    request.data?.achievementId,
    "Achievement",
    256,
  );
  const definitionRef = db.collection("achievementDefinitions").doc(achievementId);
  const userRef = db.collection("users").doc(auth.uid);
  const progressRef = userRef.collection("achievementProgress").doc(achievementId);
  const claimRef = db.collection("achievementClaims")
    .doc(achievementClaimId(auth.uid, achievementId));

  // These collections are server-owned/immutable to ordinary clients. Their
  // aggregate counts are used only after the definition and user are reread
  // transactionally below.
  const [ownedCardsCount, predictionsCount] = await Promise.all([
    userRef.collection("playerCards").count().get(),
    db.collection("predictions").where("userId", "==", auth.uid).count().get(),
  ]);
  const serverCounts = {
    playerCards: ownedCardsCount.data().count,
    predictions: predictionsCount.data().count,
  };

  const claim = await db.runTransaction(async (transaction) => {
    const [definitionDoc, userDoc, existingClaim] = await Promise.all([
      transaction.get(definitionRef),
      transaction.get(userRef),
      transaction.get(claimRef),
    ]);
    if (!userDoc.exists) {
      throw new HttpsError("failed-precondition", "User profile is missing.");
    }
    const user = userDoc.data()!;
    if (user.suspended === true) {
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
    if (existingClaim.exists) {
      const data = existingClaim.data()!;
      const status = String(data.status ?? "");
      if (status !== "processing" && status !== "completed") {
        throw new HttpsError(
          "failed-precondition",
          "Stored achievement claim status is invalid.",
        );
      }
      return {
        duplicate: true,
        completed: status === "completed",
        current: configuredInteger(data.current, "Achievement progress", 0, 0, 1_000_000_000),
        target: configuredInteger(data.target, "Achievement target", 1, 1, 1_000_000_000),
        rewardPoints: configuredInteger(data.rewardPoints, "Achievement reward", 0, 0, 1_000_000),
        pointsEarned: configuredInteger(data.pointsEarned, "Achievement points", 0, 0, 1_000_000),
        title: typeof data.title === "string" ? data.title.slice(0, 120) : achievementId,
      };
    }
    if (!definitionDoc.exists) {
      throw new HttpsError("not-found", "Achievement not found.");
    }
    const definition = definitionDoc.data()!;
    if (definition.enabled !== true) {
      throw new HttpsError("failed-precondition", "This achievement is not enabled.");
    }
    const target = configuredInteger(
      definition.requirementTarget,
      "Achievement target",
      0,
      1,
      1_000_000_000,
    );
    const rewardPoints = configuredInteger(
      definition.rewardPoints,
      "Achievement reward",
      0,
      0,
      1_000_000,
    );
    const totalPoints = configuredInteger(
      user.totalPoints,
      "Total points",
      0,
      0,
      1_000_000_000,
    );
    if (typeof definition.levelUnlock === "string" &&
        definition.levelUnlock.trim()) {
      const levelId = storedDocumentId(
        definition.levelUnlock.trim(),
        "Achievement level",
      );
      const levelDoc = await transaction.get(
        db.collection("levelDefinitions").doc(levelId),
      );
      if (!levelDoc.exists || levelDoc.data()?.enabled === false) {
        throw new HttpsError(
          "failed-precondition",
          "The achievement's required level is not available.",
        );
      }
      const minimumPoints = configuredInteger(
        levelDoc.data()?.minimumPoints,
        "Required level points",
        0,
        0,
        1_000_000_000,
      );
      if (totalPoints < minimumPoints) {
        throw new HttpsError(
          "failed-precondition",
          `This achievement requires ${minimumPoints} total points.`,
        );
      }
    }
    let current: number;
    try {
      current = achievementProgressValue(String(definition.requirementType ?? ""), {
        totalPoints,
        seasonPoints: configuredInteger(user.seasonPoints, "Season points", 0, 0, 1_000_000_000),
        monthlyPoints: configuredInteger(user.monthlyPoints, "Monthly points", 0, 0, 1_000_000_000),
        streak: configuredInteger(user.currentStreak, "Streak", 0, 0, 1_000_000),
        playerCards: configuredInteger(serverCounts.playerCards, "Player Card count", 0, 0, 1_000_000),
        predictions: configuredInteger(serverCounts.predictions, "Prediction count", 0, 0, 1_000_000),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message :
        "Achievement configuration is invalid.";
      throw new HttpsError("failed-precondition", message);
    }
    if (current < target) {
      throw new HttpsError(
        "failed-precondition",
        `Achievement progress is ${current} of ${target}.`,
      );
    }

    const claimedAt = FieldValue.serverTimestamp();
    const title = typeof definition.title === "string" && definition.title.trim() ?
      definition.title.trim().slice(0, 120) : achievementId;
    const receipt = {
      userId: auth.uid,
      achievementId,
      title,
      requirementType: String(definition.requirementType),
      current,
      target,
      rewardPoints,
      status: "processing",
      claimedAt,
      updatedAt: claimedAt,
    };
    transaction.create(claimRef, receipt);
    transaction.set(progressRef, {
      achievementId,
      current,
      target,
      unlocked: true,
      claimStatus: "processing",
      rewardPoints,
      claimedAt,
      updatedAt: claimedAt,
    }, {merge: true});
    return {
      duplicate: false,
      completed: false,
      current,
      target,
      rewardPoints,
      pointsEarned: 0,
      title,
    };
  });

  if (claim.completed) {
    return {
      ok: true,
      duplicate: true,
      achievementId,
      current: claim.current,
      target: claim.target,
      points: claim.pointsEarned,
      awarded: false,
    };
  }

  const award = claim.rewardPoints > 0 ? await awardPoints({
    userId: auth.uid,
    sourceType: "achievement",
    sourceId: achievementId,
    basePoints: claim.rewardPoints,
    reason: `Achievement: ${claim.title}`,
    applyMembershipMultiplier: false,
  }) : {awarded: false, finalPoints: 0};
  const pointsEarned = await db.runTransaction(async (transaction) => {
    const currentClaim = await transaction.get(claimRef);
    if (!currentClaim.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Achievement claim receipt is missing.",
      );
    }
    const data = currentClaim.data()!;
    const status = String(data.status ?? "");
    if (status === "completed") {
      return configuredInteger(
        data.pointsEarned,
        "Achievement points",
        0,
        0,
        1_000_000,
      );
    }
    if (status !== "processing") {
      throw new HttpsError(
        "failed-precondition",
        "Stored achievement claim status is invalid.",
      );
    }
    const rewardedAt = FieldValue.serverTimestamp();
    transaction.set(claimRef, {
      status: "completed",
      pointsEarned: award.finalPoints,
      rewardedAt,
      updatedAt: rewardedAt,
    }, {merge: true});
    transaction.set(progressRef, {
      unlocked: true,
      unlockedAt: rewardedAt,
      claimStatus: "completed",
      pointsEarned: award.finalPoints,
      updatedAt: rewardedAt,
    }, {merge: true});
    return award.finalPoints;
  });
  return {
    ok: true,
    duplicate: claim.duplicate,
    achievementId,
    current: claim.current,
    target: claim.target,
    points: pointsEarned,
    awarded: award.awarded,
  };
});

export const redeemLoyaltyReward = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  const rewardId = identifier(request.data?.rewardId, "Reward", 128);
  const idempotencyKey = identifier(request.data?.idempotencyKey, "Idempotency key", 128);
  const redemptionId = redemptionLedgerId(auth.uid, rewardId, idempotencyKey);
  const redemptionRef = db.collection("loyaltyRedemptions").doc(redemptionId);
  const transactionRef = db.collection("loyaltyTransactions").doc(redemptionId);
  const claimRef = db.collection("loyaltyRewardClaims").doc(rewardClaimId(auth.uid, rewardId));
  const rewardRef = db.collection("loyaltyRewards").doc(rewardId);
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(redemptionRef);
    if (existing.exists) {
      const data = existing.data()!;
      return {
        ok: true,
        duplicate: true,
        redemptionId,
        remainingBalance: Number(data.remainingBalance ?? 0),
        stockRemaining: data.stockRemaining == null ? null : Number(data.stockRemaining),
        claimCount: Number(data.claimCount ?? 1),
      };
    }

    const [rewardDoc, userDoc, claimDoc] = await Promise.all([
      transaction.get(rewardRef),
      transaction.get(userRef),
      transaction.get(claimRef),
    ]);
    if (!rewardDoc.exists) throw new HttpsError("not-found", "Reward not found.");
    if (!userDoc.exists) throw new HttpsError("failed-precondition", "User profile is missing.");
    const reward = rewardDoc.data()!;
    const user = userDoc.data()!;
    const claim = claimDoc.data();
    if (user.suspended === true) {
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
    // Keep server redemption eligibility identical to the catalogue shown by
    // the app. New documents must be enabled and active/live. Legacy documents
    // may omit either field, but an explicit disabled value always wins.
    const rewardEnabled = rewardIsAvailableConfiguration(
      reward.enabled,
      reward.status,
    );
    if (!rewardEnabled) {
      throw new HttpsError("failed-precondition", "This reward is not available.");
    }
    const nowMs = Timestamp.now().toMillis();
    const availableFromValue = reward.availableFrom ?? reward.startsAt;
    const availableUntilValue = reward.availableUntil ?? reward.endsAt;
    if (availableFromValue != null &&
        nowMs < storedTimestamp(availableFromValue, "Reward start").toMillis()) {
      throw new HttpsError("failed-precondition", "This reward is not available yet.");
    }
    if (availableUntilValue != null &&
        nowMs >= storedTimestamp(availableUntilValue, "Reward end").toMillis()) {
      throw new HttpsError("failed-precondition", "This reward is no longer available.");
    }
    if (reward.memberOnly === true && !hasVerifiedMembership(user)) {
      throw new HttpsError("permission-denied", "This reward is for verified members.");
    }
    const cost = configuredInteger(reward.cost, "Reward cost", 0, 1, 1_000_000);
    const perUserLimit = configuredInteger(
      reward.perUserLimit,
      "Per-user limit",
      1,
      1,
      100,
    );
    const claimCount = configuredInteger(claim?.claimCount, "Claim count", 0, 0, 100);
    const balance = configuredInteger(
      user.loyaltyPoints ?? user.seasonPoints,
      "Loyalty balance",
      0,
      0,
      1_000_000_000,
    );
    const unlimitedStock = reward.unlimitedStock === true;
    if (!unlimitedStock && reward.stock == null) {
      throw new HttpsError("failed-precondition", "Reward stock configuration is invalid.");
    }
    const stock = unlimitedStock
      ? null
      : configuredInteger(reward.stock, "Reward stock", 0, 0, 1_000_000);
    let next;
    try {
      next = calculateLoyaltyRedemption({
        balance,
        cost,
        stock,
        claimCount,
        perUserLimit,
      });
    } catch (error) {
      if (!(error instanceof LoyaltyRedemptionError)) throw error;
      switch (error.reason) {
      case "claim-limit":
        throw new HttpsError("failed-precondition", "You reached this reward's redemption limit.");
      case "out-of-stock":
        throw new HttpsError("resource-exhausted", "This reward is out of stock.");
      case "insufficient-balance":
        throw new HttpsError("failed-precondition", "You do not have enough loyalty points.");
      default:
        throw new HttpsError("failed-precondition", "Reward configuration is invalid.");
      }
    }
    if (typeof reward.title !== "string" || !reward.title.trim()) {
      throw new HttpsError("failed-precondition", "Reward title configuration is invalid.");
    }
    const rewardTitle = reward.title.trim().slice(0, 120);
    const createdAt = FieldValue.serverTimestamp();
    transaction.update(userRef, {
      loyaltyPoints: next.remainingBalance,
      updatedAt: createdAt,
    });
    if (next.stockRemaining !== null) {
      transaction.update(rewardRef, {
        stock: next.stockRemaining,
        updatedAt: createdAt,
      });
    }
    transaction.set(claimRef, {
      userId: auth.uid,
      rewardId,
      claimCount: next.claimCount,
      updatedAt: createdAt,
      ...(claimDoc.exists ? {} : {createdAt}),
    }, {merge: true});
    transaction.create(redemptionRef, {
      userId: auth.uid,
      userDisplayName: String(user.displayName ?? user.username ?? "").slice(0, 120),
      username: String(user.username ?? "").slice(0, 24),
      userEmail: String(user.email ?? "").slice(0, 254),
      rewardId,
      rewardTitle,
      cost,
      status: "pending",
      deliveryStatus: "pending",
      idempotencyKey,
      remainingBalance: next.remainingBalance,
      stockRemaining: next.stockRemaining,
      claimCount: next.claimCount,
      createdAt,
    });
    transaction.create(transactionRef, {
      userId: auth.uid,
      rewardId,
      redemptionId,
      type: "redemption",
      delta: -cost,
      balanceAfter: next.remainingBalance,
      createdAt,
    });
    return {
      ok: true,
      duplicate: false,
      redemptionId,
      remainingBalance: next.remainingBalance,
      stockRemaining: next.stockRemaining,
      claimCount: next.claimCount,
    };
  });
});

export const updateRedemptionStatus = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  await requireContentManager(auth.uid);
  const redemptionId = documentId(request.data?.redemptionId, "Redemption");
  const requestedStatus = text(request.data?.status, "Status", 20);
  if (!["pending", "contacted", "fulfilled", "cancelled"].includes(requestedStatus)) {
    throw new HttpsError("invalid-argument", "Redemption status is invalid.");
  }
  const status = requestedStatus as RedemptionStatus;
  const note = optionalText(request.data?.note, "Status note");
  const cancellationReason = optionalText(
    request.data?.reason ?? request.data?.note,
    "Cancellation reason",
  );
  const redemptionRef = db.collection("loyaltyRedemptions").doc(redemptionId);
  const auditRef = db.collection("adminAuditLogs").doc();
  return db.runTransaction(async (transaction) => {
    const redemptionDoc = await transaction.get(redemptionRef);
    if (!redemptionDoc.exists) {
      throw new HttpsError("not-found", "Redemption not found.");
    }
    const redemption = redemptionDoc.data()!;
    const currentRaw = String(redemption.status ?? redemption.deliveryStatus ?? "pending");
    if (!["pending", "contacted", "fulfilled", "cancelled"].includes(currentRaw)) {
      throw new HttpsError(
        "failed-precondition",
        "Stored redemption status is invalid.",
      );
    }
    const currentStatus = currentRaw as RedemptionStatus;
    if (currentStatus === status) {
      return {
        ok: true,
        duplicate: true,
        redemptionId,
        status,
        refunded: redemption.refunded === true,
        balanceAfter: redemption.remainingBalanceAfterRefund ?? null,
      };
    }
    if (!canTransitionRedemptionStatus(currentStatus, status)) {
      throw new HttpsError(
        "failed-precondition",
        `Redemption cannot move from ${currentStatus} to ${status}.`,
      );
    }

    const transitionAt = FieldValue.serverTimestamp();
    let refunded = false;
    let balanceAfter: number | null = null;
    let stockRestored = false;
    let claimCountAfterRefund: number | null = null;
    let refundTransactionId: string | null = null;

    if (status === "cancelled") {
      if (!cancellationReason) {
        throw new HttpsError(
          "invalid-argument",
          "A cancellation reason is required before refunding points.",
        );
      }
      const userId = storedDocumentId(redemption.userId, "Redemption user");
      const rewardId = storedDocumentId(redemption.rewardId, "Redemption reward");
      const userRef = db.collection("users").doc(userId);
      const rewardRef = db.collection("loyaltyRewards").doc(rewardId);
      const claimRef = db.collection("loyaltyRewardClaims")
        .doc(rewardClaimId(userId, rewardId));
      refundTransactionId = redemptionRefundLedgerId(redemptionId);
      const refundRef = db.collection("loyaltyTransactions").doc(refundTransactionId);
      const [userDoc, rewardDoc, claimDoc, refundDoc] = await Promise.all([
        transaction.get(userRef),
        transaction.get(rewardRef),
        transaction.get(claimRef),
        transaction.get(refundRef),
      ]);
      if (!userDoc.exists) {
        throw new HttpsError("failed-precondition", "Redemption user is missing.");
      }
      if (!claimDoc.exists) {
        throw new HttpsError("failed-precondition", "Reward claim counter is missing.");
      }
      if (refundDoc.exists) {
        throw new HttpsError(
          "failed-precondition",
          "A refund ledger exists but this redemption is not cancelled.",
        );
      }

      const cost = configuredInteger(redemption.cost, "Redemption cost", 0, 1, 1_000_000);
      const loyaltyBalance = configuredInteger(
        userDoc.data()?.loyaltyPoints,
        "Loyalty balance",
        0,
        0,
        1_000_000_000,
      );
      const claimCount = configuredInteger(
        claimDoc.data()?.claimCount,
        "Claim count",
        0,
        1,
        100,
      );
      let currentStock: number | null = null;
      if (redemption.stockRemaining != null) {
        if (!rewardDoc.exists) {
          throw new HttpsError(
            "failed-precondition",
            "The finite-stock reward is missing and cannot be restored safely.",
          );
        }
        currentStock = configuredInteger(
          rewardDoc.data()?.stock,
          "Reward stock",
          0,
          0,
          1_000_000,
        );
      }
      let refund;
      try {
        refund = calculateLoyaltyRefund({
          balance: loyaltyBalance,
          cost,
          stock: currentStock,
          claimCount,
        });
      } catch (error) {
        if (!(error instanceof LoyaltyRedemptionError)) throw error;
        throw new HttpsError(
          "failed-precondition",
          "The redemption cannot be refunded from its current balance, stock, or claim state.",
        );
      }
      balanceAfter = refund.remainingBalance;
      if (balanceAfter > 1_000_000_000 ||
          (refund.stockRemaining !== null && refund.stockRemaining > 1_000_000)) {
        throw new HttpsError("failed-precondition", "Refunded loyalty state is invalid.");
      }
      claimCountAfterRefund = refund.claimCount;

      transaction.update(userRef, {
        loyaltyPoints: balanceAfter,
        updatedAt: transitionAt,
      });
      transaction.update(claimRef, {
        claimCount: claimCountAfterRefund,
        updatedAt: transitionAt,
      });

      if (refund.stockRemaining !== null) {
        transaction.update(rewardRef, {
          stock: refund.stockRemaining,
          updatedAt: transitionAt,
        });
        stockRestored = true;
      }

      transaction.create(refundRef, {
        userId,
        rewardId,
        redemptionId,
        type: "redemptionRefund",
        delta: cost,
        balanceAfter,
        reason: cancellationReason,
        adminId: auth.uid,
        createdAt: transitionAt,
      });
      refunded = true;
    }

    transaction.update(redemptionRef, {
      status,
      deliveryStatus: status,
      statusChangedAt: transitionAt,
      statusChangedBy: auth.uid,
      note,
      adminNote: note,
      statusNote: note,
      updatedAt: transitionAt,
      ...(status === "pending" ? {
        pendingAt: transitionAt,
        pendingBy: auth.uid,
      } : {}),
      ...(status === "contacted" ? {
        contactedAt: transitionAt,
        contactedBy: auth.uid,
      } : {}),
      ...(status === "fulfilled" ? {
        fulfilledAt: transitionAt,
        fulfilledBy: auth.uid,
      } : {}),
      ...(status === "cancelled" ? {
        cancelledAt: transitionAt,
        cancelledBy: auth.uid,
        cancellationReason,
        refunded,
        refundedAt: transitionAt,
        refundTransactionId,
        claimCount: claimCountAfterRefund,
        remainingBalanceAfterRefund: balanceAfter,
        stockRestored,
        claimCountAfterRefund,
      } : {}),
    });
    transaction.create(auditRef, {
      adminId: auth.uid,
      action: "UPDATE_REDEMPTION_STATUS",
      targetId: redemptionId,
      userId: redemption.userId ?? null,
      rewardId: redemption.rewardId ?? null,
      previousStatus: currentStatus,
      status,
      note,
      refunded,
      refundTransactionId,
      createdAt: transitionAt,
    });
    return {
      ok: true,
      duplicate: false,
      redemptionId,
      status,
      refunded,
      balanceAfter,
    };
  });
});

export {adminAdjustPoints} from "./phase3_admin_points.js";


const schedulingHandlers = createPhase3SchedulingHandlers({
  db,
  settleMatchResult: async (result, context) => {
    await internalSettleMatchResult(result, null, context.jobId);
  }
});

export const processAutomaticMatchResults = onSchedule("*/10 * * * *", async (event) => {
  await schedulingHandlers.processAutomaticMatchResults(`scheduler-matches-${event.scheduleTime}`);
});

export const sweepScheduledEvents = onSchedule("*/5 * * * *", async (event) => {
  await schedulingHandlers.sweepScheduledEvents();
});

export const cacheLatestYouTubeVideo = onSchedule("0 * * * *", async (event) => {
  const feedUrl = "https://www.youtube.com/feeds/videos.xml?channel_id=UCtetMtDxaZv1Fun1Ff85h4w";
  try {
    const response = await fetch(`https://api.rss2json.com/v1/api.json?rss_url=${encodeURIComponent(feedUrl)}`);
    if (!response.ok) {
      console.error("Failed to fetch RSS feed");
      return;
    }
    const payload = await response.json();
    if (payload.status !== "ok" || !payload.items || payload.items.length === 0) return;
    const item = payload.items[0];
    const url = item.link || "";
    let id = "";
    try {
      const parsedUrl = new URL(url);
      id = parsedUrl.searchParams.get("v") || "";
    } catch(e) {}
    if (!id) return;
    const latestVideo = {
      id,
      title: item.title || "Latest Abu 3meer video",
      url,
      thumbnailUrl: item.thumbnail || `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
      publishedAt: item.pubDate ? new Date(item.pubDate + "Z").getTime() : 0,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await db.collection("platformSettings").doc("latestVideo").set(latestVideo, { merge: true });
  } catch (error) {
    console.error("Error caching latest YouTube video", error);
  }
});

export const deleteAccountData = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  // Optional: check if auth.uid is deleted in Firebase Auth already, or delete user data.
  // Actually, usually it's cleaner to use auth trigger (functions.auth.user().onDelete), but since we are doing a callable:
  const uid = auth.uid;
  await db.runTransaction(async (t) => {
     t.update(db.collection("users").doc(uid), {
         suspended: true,
         deleted: true,
         updatedAt: FieldValue.serverTimestamp(),
         username: `deleted_${uid.slice(0,8)}`,
         displayName: "Deleted User"
     });
     t.delete(db.collection("leaderboardEntries").doc(uid));
  });
  return {ok: true};
});

export const verifyYouTubeMembership = onCall(phase3CallableOptions(region), async (request) => {
  requireAuth(request.auth);
  throw new HttpsError(
    "failed-precondition",
    "Automatic YouTube channel-member verification is not configured. Membership must be verified independently and assigned by an administrator.",
  );
});

/**
 * Manual compatibility path for Firebase-backed challenge rewards. The
 * PostgreSQL API has its own audited admin endpoint; this callable keeps the
 * legacy Firebase user mirror aligned without allowing user self-promotion.
 */
export const adminSetYouTubeMembership = onCall(phase3CallableOptions(region), async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const targetUserId = documentId(request.data?.targetUserId, "Target user", 128);
  if (typeof request.data?.isMember !== "boolean") {
    throw new HttpsError("invalid-argument", "Membership status is required.");
  }
  const reason = text(request.data?.reason, "Reason", 240);
  if (reason.length < 3) {
    throw new HttpsError("invalid-argument", "Reason must contain at least 3 characters.");
  }

  const membership = adminMembershipState(request.data.isMember);
  const targetRef = db.collection("users").doc(targetUserId);
  const auditRef = db.collection("adminAuditLogs").doc();
  await db.runTransaction(async (transaction) => {
    const target = await transaction.get(targetRef);
    if (!target.exists) {
      throw new HttpsError("not-found", "User profile is missing.");
    }
    const changedAt = FieldValue.serverTimestamp();
    transaction.update(targetRef, {
      ...membership,
      youtubeMembershipVerifiedAt: membership.isYouTubeMember ? changedAt : null,
      youtubeVerifiedAt: membership.isYouTubeMember ? changedAt : null,
      updatedAt: changedAt,
    });
    transaction.create(auditRef, {
      adminId: auth.uid,
      action: membership.isYouTubeMember ? "GRANT_YOUTUBE_MEMBERSHIP" : "REVOKE_YOUTUBE_MEMBERSHIP",
      targetUserId,
      reason,
      changes: membership,
      createdAt: changedAt,
    });
  });
  return {ok: true, ...membership};
});
