import {
  FieldValue,
  Timestamp,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {
  parseFootballSeasonId,
  resolveLeaderboardSeasonId,
  rewardLedgerId,
} from "./domain.js";
import {
  AdminPointAdjustmentPolicyError,
  MAX_ADMIN_POINT_ADJUSTMENT,
  adminPointAdjustmentFingerprint,
  adminPointAdjustmentId,
  applyAdminPointAdjustment,
} from "./phase3_admin_points_domain.js";

const region = "europe-west1";

function requiredText(value: unknown, field: string, max: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > max) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return normalized;
}

function documentId(value: unknown, field: string): string {
  const result = requiredText(value, field, 512);
  if (result.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return result;
}

function requestedDelta(value: unknown): number {
  if (!Number.isSafeInteger(value) || value === 0 ||
      Math.abs(value as number) > MAX_ADMIN_POINT_ADJUSTMENT) {
    throw new HttpsError(
      "invalid-argument",
      `Adjustment must be a non-zero integer between -${MAX_ADMIN_POINT_ADJUSTMENT} and ${MAX_ADMIN_POINT_ADJUSTMENT}.`,
    );
  }
  return value as number;
}

function idempotencyKey(value: unknown): string {
  const result = requiredText(value, "Idempotency key", 128);
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(result)) {
    throw new HttpsError("invalid-argument", "Idempotency key is invalid.");
  }
  return result;
}

function storedBalance(value: unknown, field: string): number {
  const parsed = value ?? 0;
  if (!Number.isSafeInteger(parsed) || (parsed as number) < 0 ||
      (parsed as number) > 1_000_000_000) {
    throw new HttpsError(
      "failed-precondition",
      `${field} balance is invalid. No points were changed.`,
    );
  }
  return parsed as number;
}

function monthId(value: Date): string {
  return `${value.getUTCFullYear()}-${String(value.getUTCMonth() + 1).padStart(2, "0")}`;
}

async function currentSeasonId(activityAt: Timestamp): Promise<string> {
  const db = getFirestore();
  const snapshot = await db.collection("leaderboardSeasons")
    .where("active", "==", true)
    .get();
  return resolveLeaderboardSeasonId(
    activityAt.toDate(),
    snapshot.docs.map((doc) => ({
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
    leaderboard: Record<string, unknown>;
    archivedAt: Timestamp;
  },
): void {
  if (typeof params.previousSeasonId !== "string") return;
  const previousSeasonId = params.previousSeasonId.trim();
  if (!previousSeasonId || previousSeasonId === params.currentSeasonId ||
      previousSeasonId.includes("/") || previousSeasonId.length > 512) {
    return;
  }
  const db = getFirestore();
  const previous = parseFootballSeasonId(previousSeasonId);
  const current = parseFootballSeasonId(params.currentSeasonId);
  const seasonRef = db.collection("leaderboardSeasons").doc(previousSeasonId);
  transaction.set(seasonRef, {
    active: false,
    archiveMode: "lazy-rollover",
    lastArchivedAt: params.archivedAt,
    updatedAt: params.archivedAt,
    ...(previous == null ? {} : {
      automatic: true,
      displayName: previous.displayName,
      startsAt: Timestamp.fromDate(previous.startsAt),
      endsAt: Timestamp.fromDate(previous.endsAt),
    }),
  }, {merge: true});
  transaction.set(seasonRef.collection("entries").doc(params.userId), {
    username: params.user.username ?? params.leaderboard.username ?? "",
    avatarUrl: params.user.avatarUrl ?? params.leaderboard.avatarUrl ?? "",
    supportedTeam:
      params.user.supportedTeam ?? params.leaderboard.supportedTeam ?? "",
    monthlyPoints:
      params.user.monthlyPoints ?? params.leaderboard.monthlyPoints ?? 0,
    seasonPoints:
      params.user.seasonPoints ?? params.leaderboard.seasonPoints ?? 0,
    totalPoints: params.user.totalPoints ?? params.leaderboard.totalPoints ?? 0,
    isMember: Number(params.user.membershipMultiplier ?? 1) > 1,
    monthlyPeriod:
      params.user.monthlyPeriod ?? params.leaderboard.monthlyPeriod ?? "",
    seasonId: previousSeasonId,
    archivedAt: params.archivedAt,
    updatedAt: params.archivedAt,
  }, {merge: true});
  if (current != null) {
    transaction.set(
      db.collection("leaderboardSeasons").doc(params.currentSeasonId),
      {
        active: true,
        automatic: true,
        displayName: current.displayName,
        startsAt: Timestamp.fromDate(current.startsAt),
        endsAt: Timestamp.fromDate(current.endsAt),
        updatedAt: params.archivedAt,
      },
      {merge: true},
    );
  }
}

export const adminAdjustPoints = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in is required.");
  }
  throw new HttpsError(
    "failed-precondition",
    "Manual XP adjustments are not part of Abu 3meer.",
  );
  /* Legacy implementation retained only until the disabled callable has been
   * deployed over any older live version. It is intentionally unreachable.
  const adminId = request.auth.uid;
  const targetUserId = documentId(request.data?.targetUserId, "Target user");
  const delta = requestedDelta(request.data?.delta);
  const reason = requiredText(request.data?.reason, "Reason", 240);
  if (reason.length < 3) {
    throw new HttpsError(
      "invalid-argument",
      "Reason must contain at least 3 characters.",
    );
  }
  const retryKey = idempotencyKey(request.data?.idempotencyKey);
  const adjustmentId = adminPointAdjustmentId(adminId, retryKey);
  const requestFingerprint = adminPointAdjustmentFingerprint({
    targetUserId,
    delta,
    reason,
  });
  const db = getFirestore();
  const adjustedAt = Timestamp.now();
  const currentMonth = monthId(adjustedAt.toDate());
  const currentSeason = await currentSeasonId(adjustedAt);
  const adminRef = db.collection("users").doc(adminId);
  const userRef = db.collection("users").doc(targetUserId);
  const leaderboardRef = db.collection("leaderboardEntries").doc(targetUserId);
  const auditRef = db.collection("adminPointAdjustments").doc(adjustmentId);
  const ledgerRef = db.collection("pointTransactions").doc(
    rewardLedgerId("adminAdjustment", adjustmentId, targetUserId),
  );
  const generalAuditRef = db.collection("adminAuditLogs").doc();

  try {
    return await db.runTransaction(async (transaction) => {
      const [adminSnapshot, userSnapshot, leaderboardSnapshot, existingAudit] =
        await Promise.all([
          transaction.get(adminRef),
          transaction.get(userRef),
          transaction.get(leaderboardRef),
          transaction.get(auditRef),
        ]);
      if (!adminSnapshot.exists) {
        throw new HttpsError("permission-denied", "Administrator profile is missing.");
      }
      const admin = adminSnapshot.data()!;
      if (!["admin", "superAdmin"].includes(String(admin.role ?? ""))) {
        throw new HttpsError(
          "permission-denied",
          "Administrator access is required.",
        );
      }
      if (admin.suspended === true) {
        throw new HttpsError("permission-denied", "This administrator is suspended.");
      }
      if (existingAudit.exists) {
        const existing = existingAudit.data()!;
        if (existing.adminId !== adminId ||
            existing.requestFingerprint !== requestFingerprint) {
          throw new HttpsError(
            "already-exists",
            "This idempotency key was already used for another adjustment.",
          );
        }
        return {
          ok: true,
          duplicate: true,
          adjustmentId,
          targetUserId: existing.targetUserId,
          delta: existing.delta,
          totalPoints: existing.totalAfter,
          monthlyPoints: existing.monthlyAfter,
          seasonPoints: existing.seasonAfter,
          periodFloorApplied: existing.periodFloorApplied === true,
        };
      }
      if (!userSnapshot.exists) {
        throw new HttpsError("not-found", "Target user profile was not found.");
      }
      const user = userSnapshot.data()!;
      if (user.suspended === true) {
        throw new HttpsError(
          "failed-precondition",
          "Points cannot be adjusted while the target account is suspended.",
        );
      }
      const leaderboard = leaderboardSnapshot.data() ?? {};
      const storedTotal = storedBalance(
        user.totalPoints ?? leaderboard.totalPoints,
        "All-time points",
      );
      const storedMonthly = storedBalance(
        user.monthlyPoints ?? leaderboard.monthlyPoints,
        "Monthly points",
      );
      const storedSeason = storedBalance(
        user.seasonPoints ?? leaderboard.seasonPoints,
        "Season points",
      );
      const sameMonth = user.monthlyPeriod === currentMonth;
      const sameSeason = !user.seasonId || user.seasonId === currentSeason;
      const result = applyAdminPointAdjustment({
        totalPoints: storedTotal,
        monthlyPoints: sameMonth ? storedMonthly : 0,
        seasonPoints: sameSeason ? storedSeason : 0,
      }, delta);

      if (!sameSeason) {
        archivePreviousSeason(transaction, {
          userId: targetUserId,
          previousSeasonId: user.seasonId,
          currentSeasonId: currentSeason,
          user,
          leaderboard,
          archivedAt: adjustedAt,
        });
      }

      transaction.update(userRef, {
        totalPoints: result.after.totalPoints,
        monthlyPoints: result.after.monthlyPoints,
        seasonPoints: result.after.seasonPoints,
        monthlyPeriod: currentMonth,
        seasonId: currentSeason,
        updatedAt: adjustedAt,
      });
      transaction.set(leaderboardRef, {
        username: user.username ?? leaderboard.username ?? "",
        avatarUrl: user.avatarUrl ?? leaderboard.avatarUrl ?? "",
        supportedTeam:
          user.supportedTeam ?? leaderboard.supportedTeam ?? "",
        monthlyPoints: result.after.monthlyPoints,
        seasonPoints: result.after.seasonPoints,
        totalPoints: result.after.totalPoints,
        isMember: Number(user.membershipMultiplier ?? 1) > 1,
        monthlyPeriod: currentMonth,
        seasonId: currentSeason,
        updatedAt: adjustedAt,
      }, {merge: true});
      transaction.create(ledgerRef, {
        userId: targetUserId,
        sourceType: "adminAdjustment",
        sourceId: adjustmentId,
        basePoints: delta,
        multiplier: 1,
        finalPoints: delta,
        reason,
        adminId,
        monthlyPeriod: currentMonth,
        seasonId: currentSeason,
        totalBefore: result.before.totalPoints,
        totalAfter: result.after.totalPoints,
        monthlyBefore: result.before.monthlyPoints,
        monthlyAfter: result.after.monthlyPoints,
        seasonBefore: result.before.seasonPoints,
        seasonAfter: result.after.seasonPoints,
        createdAt: adjustedAt,
      });
      transaction.create(auditRef, {
        adminId,
        adminDisplayName: admin.displayName ?? admin.username ?? "Administrator",
        targetUserId,
        targetDisplayName: user.displayName ?? user.username ?? targetUserId,
        targetUsername: user.username ?? "",
        delta,
        reason,
        requestFingerprint,
        idempotencyKey: retryKey,
        totalBefore: result.before.totalPoints,
        totalAfter: result.after.totalPoints,
        monthlyBefore: result.before.monthlyPoints,
        monthlyAfter: result.after.monthlyPoints,
        seasonBefore: result.before.seasonPoints,
        seasonAfter: result.after.seasonPoints,
        appliedMonthlyDelta: result.appliedMonthlyDelta,
        appliedSeasonDelta: result.appliedSeasonDelta,
        periodFloorApplied: result.periodFloorApplied,
        monthlyRolledOver: !sameMonth,
        seasonRolledOver: !sameSeason,
        previousMonthlyPeriod: user.monthlyPeriod ?? "",
        previousSeasonId: user.seasonId ?? "",
        monthlyPeriod: currentMonth,
        seasonId: currentSeason,
        loyaltyPointsUnchanged: true,
        balancePolicy: "reject-negative-total-clamp-periods",
        pointTransactionId: ledgerRef.id,
        createdAt: adjustedAt,
      });
      transaction.create(generalAuditRef, {
        adminId,
        action: "ADJUST_USER_POINTS",
        targetId: targetUserId,
        pointAdjustmentId: adjustmentId,
        delta,
        reason,
        createdAt: adjustedAt,
      });
      return {
        ok: true,
        duplicate: false,
        adjustmentId,
        targetUserId,
        delta,
        totalPoints: result.after.totalPoints,
        monthlyPoints: result.after.monthlyPoints,
        seasonPoints: result.after.seasonPoints,
        periodFloorApplied: result.periodFloorApplied,
      };
    });
  } catch (error) {
    if (error instanceof AdminPointAdjustmentPolicyError) {
      if (error.code === "total-floor") {
        throw new HttpsError(
          "failed-precondition",
          "This deduction exceeds the user's all-time point balance.",
        );
      }
      throw new HttpsError(
        "failed-precondition",
        error.code === "overflow" ?
          "The adjusted balance exceeds the supported limit." :
          "Stored point balances are invalid. No points were changed.",
      );
    }
    throw error;
  }
  */
});
