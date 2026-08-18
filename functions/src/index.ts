import {initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  QueryDocumentSnapshot,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  DEFAULT_POINTS,
  PointSource,
  calculatePoints,
  didBothTeamsScore,
  predictionIsOpen,
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

async function awardPoints(params: {
  userId: string;
  sourceType: PointSource;
  sourceId: string;
  basePoints: number;
  reason: string;
  adminId?: string;
}): Promise<{awarded: boolean; finalPoints: number}> {
  const ledgerId = rewardLedgerId(params.sourceType, params.sourceId, params.userId);
  const userRef = db.collection("users").doc(params.userId);
  const ledgerRef = db.collection("pointTransactions").doc(ledgerId);
  const leaderboardRef = db.collection("leaderboardEntries").doc(params.userId);
  const currentPeriod = periodId();

  return db.runTransaction(async (transaction) => {
    const [existing, userSnapshot, leaderboardSnapshot] = await Promise.all([
      transaction.get(ledgerRef),
      transaction.get(userRef),
      transaction.get(leaderboardRef),
    ]);
    if (existing.exists) return {awarded: false, finalPoints: 0};
    if (!userSnapshot.exists) {
      throw new HttpsError("failed-precondition", "User profile is missing.");
    }
    const user = userSnapshot.data()!;
    if (user.suspended === true) {
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
    const multiplier = Number(user.membershipMultiplier ?? 1);
    const finalPoints = calculatePoints(params.basePoints, multiplier);
    const sameMonth = user.monthlyPeriod === currentPeriod;
    const monthlyPoints = (sameMonth ? Number(user.monthlyPoints ?? 0) : 0) + finalPoints;
    const seasonPoints = Number(user.seasonPoints ?? 0) + finalPoints;
    const totalPoints = Number(user.totalPoints ?? 0) + finalPoints;
    const activityAt = Timestamp.now();
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
    });
    transaction.update(userRef, {
      totalPoints,
      monthlyPoints,
      seasonPoints,
      currentStreak,
      longestStreak,
      lastActivityAt: activityAt,
      monthlyPeriod: currentPeriod,
      updatedAt: createdAt,
    });
    const entry = {
      username: user.username ?? "",
      avatarUrl: user.avatarUrl ?? "",
      supportedTeam: user.supportedTeam ?? "",
      monthlyPoints,
      seasonPoints,
      isMember: multiplier > 1,
      monthlyPeriod: currentPeriod,
      updatedAt: createdAt,
    };
    leaderboardSnapshot.exists ? transaction.update(leaderboardRef, entry) : transaction.create(leaderboardRef, entry);
    return {awarded: true, finalPoints};
  });
}

export const completeOnboarding = onCall({region}, async (request) => {
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
  await db.runTransaction(async (transaction) => {
    const [claimed, existing] = await Promise.all([
      transaction.get(usernameRef),
      transaction.get(userRef),
    ]);
    if (claimed.exists && claimed.data()?.uid !== auth.uid) {
      throw new HttpsError("already-exists", "That username is already taken.");
    }
    const oldUsername = existing.data()?.username;
    if (oldUsername && oldUsername !== username) {
      transaction.delete(db.collection("usernames").doc(oldUsername));
    }
    const now = FieldValue.serverTimestamp();
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
      totalPoints: existing.data()?.totalPoints ?? 0,
      monthlyPoints: existing.data()?.monthlyPoints ?? 0,
      seasonPoints: existing.data()?.seasonPoints ?? 0,
      currentStreak: existing.data()?.currentStreak ?? 0,
      longestStreak: existing.data()?.longestStreak ?? 0,
      lastActivityAt: existing.data()?.lastActivityAt ?? null,
      monthlyPeriod: existing.data()?.monthlyPeriod ?? periodId(),
      onboardingComplete: true,
      createdAt: existing.data()?.createdAt ?? now,
      updatedAt: now,
    }, {merge: true});
    transaction.set(leaderboardRef, {
      username,
      avatarUrl,
      supportedTeam,
      monthlyPoints: existing.data()?.monthlyPoints ?? 0,
      seasonPoints: existing.data()?.seasonPoints ?? 0,
      isMember: Number(existing.data()?.membershipMultiplier ?? 1) > 1,
      monthlyPeriod: existing.data()?.monthlyPeriod ?? periodId(),
      updatedAt: now,
    }, {merge: true});
  });
  return {ok: true};
});

export const submitPrediction = onCall({region, enforceAppCheck: false}, async (request) => {
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
  await db.runTransaction(async (transaction) => {
    const [matchSnapshot, userSnapshot] = await Promise.all([
      transaction.get(matchRef),
      transaction.get(db.collection("users").doc(auth.uid)),
    ]);
    if (!matchSnapshot.exists) throw new HttpsError("not-found", "Match not found.");
    if (userSnapshot.data()?.suspended === true) throw new HttpsError("permission-denied", "Account suspended.");
    const match = matchSnapshot.data()!;
    const now = Timestamp.now().toMillis();
    if (match.status !== "open" || !predictionIsOpen(now, match.predictionOpensAt.toMillis(), match.predictionClosesAt.toMillis())) {
      throw new HttpsError("failed-precondition", "Predictions are closed for this match.");
    }
    const options = textList(match.firstScorerOptions, "First scorer options");
    const firstScorerKey = normalizedLabel(firstScorerInput);
    const canonicalFirstScorer = options.find((option) => normalizedLabel(option) === firstScorerKey) ?? firstScorerInput;
    if (options.length > 0 && !options.some((option) => normalizedLabel(option) === firstScorerKey)) {
      throw new HttpsError("invalid-argument", "Choose a first scorer from this match's options.");
    }
    transaction.set(predictionRef, {
      userId: auth.uid,
      matchId,
      homeScore,
      awayScore,
      firstScorer: canonicalFirstScorer,
      firstScorerKey,
      bothTeamsScore,
      submittedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      rewarded: false,
    }, {merge: true});
  });
  return {ok: true};
});

export const adminCreateMatch = onCall({region}, async (request) => {
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

export const adminPublishMatchResult = onCall({region, timeoutSeconds: 540}, async (request) => {
  const auth = requireAuth(request.auth);
  await requireAdmin(auth.uid);
  const matchId = text(request.data?.matchId, "Match", 128);
  const homeScore = integer(request.data?.homeScore, "Home score");
  const awayScore = integer(request.data?.awayScore, "Away score");
  const firstScorerInput = text(request.data?.firstScorer, "First scorer", 80).replace(/\s+/g, " ");
  const firstScorerKey = normalizedLabel(firstScorerInput);
  const bothTeamsScored = didBothTeamsScore(homeScore, awayScore);
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
      throw new HttpsError(
        "already-exists",
        sameResult ?
          "This result was already processed." :
          "This result was already processed with a different score.",
      );
    }
    transaction.update(matchRef, {
      homeScore,
      awayScore,
      firstScorer: firstScorerInput,
      firstScorerKey,
      bothTeamsScored,
      status: "completed",
      resultProcessing: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  const settings = await pointSettings();
  const [exactWinners, firstScorerWinners, bothTeamsWinners] = await Promise.all([
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
  ): Promise<number> => {
    let awarded = 0;
    for (let index = 0; index < docs.length; index += 40) {
      const chunk = docs.slice(index, index + 40);
      const results = await Promise.all(chunk.map((doc) => awardPoints({
        userId: doc.data().userId,
        sourceType,
        sourceId: matchId,
        basePoints,
        reason,
      })));
      awarded += results.filter((result) => result.awarded).length;
    }
    return awarded;
  };
  const [exactAwarded, firstScorerAwarded, bothTeamsAwarded] = await Promise.all([
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
  const awarded = exactAwarded + firstScorerAwarded + bothTeamsAwarded;
  await matchRef.update({
    resultProcessed: true,
    resultProcessing: false,
    rewardedUsers: awarded,
    exactRewardedUsers: exactAwarded,
    firstScorerRewardedUsers: firstScorerAwarded,
    bothTeamsRewardedUsers: bothTeamsAwarded,
    processedAt: FieldValue.serverTimestamp(),
  });
  await db.collection("adminAuditLogs").add({
    adminId: auth.uid,
    action: "PUBLISH_MATCH_RESULT",
    targetId: matchId,
    awardedUsers: awarded,
    exactAwarded,
    firstScorerAwarded,
    bothTeamsAwarded,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {ok: true, awardedUsers: awarded, exactAwarded, firstScorerAwarded, bothTeamsAwarded};
});

export const adminUpdatePointRules = onCall({region}, async (request) => {
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

async function submitSecretAnswer(params: {uid: string; collection: "videoQuestions" | "playerCards"; sourceType: "videoQuestion" | "playerCard"; id: string; answer: string}) {
  const publicRef = db.collection(params.collection).doc(params.id);
  const secretRef = publicRef.collection("private").doc("answer");
  const attemptRef = publicRef.collection("attempts").doc(params.uid);
  const [publicDoc, secretDoc, settings] = await Promise.all([publicRef.get(), secretRef.get(), pointSettings()]);
  if (!publicDoc.exists || !secretDoc.exists) throw new HttpsError("not-found", "Challenge not found.");
  const challenge = publicDoc.data()!;
  const now = Timestamp.now();
  if (challenge.status !== "open" || now.toMillis() < challenge.availableFrom.toMillis() || now.toMillis() >= challenge.availableUntil.toMillis()) {
    throw new HttpsError("failed-precondition", "This challenge is not open.");
  }
  const attempt = await attemptRef.get();
  if (attempt.data()?.correct === true) throw new HttpsError("already-exists", "You already completed this challenge.");
  const attemptCount = Number(attempt.data()?.attemptCount ?? 0);
  if (attemptCount >= 5) throw new HttpsError("resource-exhausted", "Too many attempts. Contact support if this is a mistake.");
  const expected = String(secretDoc.data()?.normalizedAnswer ?? "").trim().toLowerCase();
  const correct = params.answer.trim().toLowerCase() === expected;
  await attemptRef.set({userId: params.uid, answer: params.answer.trim().slice(0, 120), correct, attemptCount: attemptCount + 1, submittedAt: FieldValue.serverTimestamp()}, {merge: true});
  if (!correct) return {correct: false, points: 0};
  const basePoints = Number(settings[params.sourceType]);
  const result = await awardPoints({userId: params.uid, sourceType: params.sourceType, sourceId: params.id, basePoints, reason: params.sourceType === "videoQuestion" ? "Correct video answer" : "Player Card found"});
  if (params.sourceType === "playerCard") {
    await db.collection("users").doc(params.uid).collection("playerCards").doc(params.id).set({cardId: params.id, pointsEarned: result.finalPoints, foundAt: FieldValue.serverTimestamp()});
  }
  return {correct: true, points: result.finalPoints};
}

export const submitVideoAnswer = onCall({region}, async (request) => {
  const auth = requireAuth(request.auth);
  return submitSecretAnswer({uid: auth.uid, collection: "videoQuestions", sourceType: "videoQuestion", id: text(request.data?.questionId, "Question", 128), answer: text(request.data?.answer, "Answer", 120)});
});

export const claimPlayerCard = onCall({region}, async (request) => {
  const auth = requireAuth(request.auth);
  return submitSecretAnswer({uid: auth.uid, collection: "playerCards", sourceType: "playerCard", id: text(request.data?.cardId, "Player Card", 128), answer: text(request.data?.answer, "Answer", 120)});
});
