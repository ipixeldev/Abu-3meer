import {
  DocumentData,
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";
import {randomUUID} from "node:crypto";

export type OfficialMatchResult = {
  matchId: string;
  homeScore: number;
  awayScore: number;
  firstScorer: string;
};

export type MatchResultSettlement = (
  result: OfficialMatchResult,
  context: {
    jobId: string;
    source: string;
    workerId: string;
  },
) => Promise<{duplicate?: boolean} | void>;

export type ScheduleFamily = "match" | "challenge" | "reward";

export type Phase3SchedulingOptions = {
  db: Firestore;
  settleMatchResult: MatchResultSettlement;
  now?: () => Timestamp;
  resultBatchSize?: number;
  schedulePageSize?: number;
  leaseDurationMs?: number;
  maxResultAttempts?: number;
  resultQueueCollection?: string;
};

export type AutomaticResultRun = {
  candidates: number;
  claimed: number;
  completed: number;
  retried: number;
  failed: number;
  skipped: number;
};

export type ScheduleSweepRun = {
  scanned: number;
  transitioned: number;
  skippedInvalid: number;
  byCollection: Record<string, number>;
};

type ResultJobStatus = "pending" | "retry" | "processing" | "completed" | "failed";

type ClaimedResultJob = {
  ref: DocumentReference<DocumentData>;
  jobId: string;
  source: string;
  workerId: string;
  attemptCount: number;
  result: OfficialMatchResult;
};

type ScheduleTarget = {
  collection: string;
  family: ScheduleFamily;
  statuses: string[];
};

const DEFAULT_RESULT_BATCH_SIZE = 3;
const DEFAULT_SCHEDULE_PAGE_SIZE = 250;
const DEFAULT_LEASE_DURATION_MS = 15 * 60 * 1000;
const DEFAULT_MAX_RESULT_ATTEMPTS = 8;
const MAX_RESULT_ERROR_LENGTH = 1_000;

const SCHEDULE_TARGETS: ScheduleTarget[] = [
  {
    collection: "matches",
    family: "match",
    statuses: ["scheduled", "open"],
  },
  {
    collection: "videoQuestions",
    family: "challenge",
    statuses: ["scheduled", "open", "live"],
  },
  {
    collection: "playerCards",
    family: "challenge",
    statuses: ["scheduled", "open", "live"],
  },
  {
    collection: "loyaltyRewards",
    family: "reward",
    statuses: ["scheduled", "active", "live"],
  },
];

function safePositiveInteger(value: number | undefined, fallback: number, max: number): number {
  if (value == null) return fallback;
  if (!Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new Error(`Expected an integer between 1 and ${max}.`);
  }
  return value;
}

function timestampMillis(value: unknown): number | null {
  return value instanceof Timestamp ? value.toMillis() : null;
}

function normalizedFirstScorer(value: string): string {
  return value
    .normalize("NFKC")
    .trim()
    .replace(/\s+/g, " ")
    .toLocaleLowerCase("en-US");
}

/** Stable audit hash. Point idempotency remains owned by the existing ledger. */
export function automaticMatchResultHash(result: OfficialMatchResult): string {
  return JSON.stringify([
    result.homeScore,
    result.awayScore,
    normalizedFirstScorer(result.firstScorer),
  ]);
}

/** Confirms an ambiguous settlement retry without relying on an error string. */
export function storedMatchHasProcessedResult(
  data: Record<string, unknown>,
  result: OfficialMatchResult,
): boolean {
  if (data.resultProcessed !== true) return false;
  const expectedHash = automaticMatchResultHash(result);
  if (typeof data.resultHash === "string") return data.resultHash === expectedHash;
  return data.homeScore === result.homeScore &&
    data.awayScore === result.awayScore &&
    typeof data.firstScorer === "string" &&
    normalizedFirstScorer(data.firstScorer) === normalizedFirstScorer(result.firstScorer);
}

/** Validates the server-only result job before it can acquire a lease. */
export function parseOfficialMatchResult(value: unknown): OfficialMatchResult {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Match result job is invalid.");
  }
  const data = value as Record<string, unknown>;
  const matchId = typeof data.matchId === "string" ? data.matchId.trim() : "";
  const firstScorer = typeof data.firstScorer === "string" ?
    data.firstScorer.trim().replace(/\s+/g, " ") : "";
  const homeScore = data.homeScore;
  const awayScore = data.awayScore;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(matchId)) {
    throw new Error("Match result job has an invalid match ID.");
  }
  if (!Number.isSafeInteger(homeScore) || (homeScore as number) < 0 ||
      (homeScore as number) > 20 || !Number.isSafeInteger(awayScore) ||
      (awayScore as number) < 0 || (awayScore as number) > 20) {
    throw new Error("Match result job has an invalid score.");
  }
  if (!firstScorer || firstScorer.length > 80) {
    throw new Error("Match result job has an invalid first scorer.");
  }
  return {
    matchId,
    homeScore: homeScore as number,
    awayScore: awayScore as number,
    firstScorer,
  };
}

/**
 * Returns the next persisted status at a time-window boundary. All comparisons
 * use epoch milliseconds from Firestore Timestamps, never a process timezone.
 */
export function scheduledTargetStatus(params: {
  family: ScheduleFamily;
  currentStatus: string;
  nowMs: number;
  startsAtMs: number | null;
  endsAtMs: number | null;
  enabled?: boolean;
}): string | null {
  const {family, currentStatus, nowMs, startsAtMs, endsAtMs} = params;
  if (!Number.isFinite(nowMs)) return null;
  if (startsAtMs != null && !Number.isFinite(startsAtMs)) return null;
  if (endsAtMs != null && !Number.isFinite(endsAtMs)) return null;
  if (startsAtMs != null && endsAtMs != null && startsAtMs >= endsAtMs) return null;
  if (family !== "reward" && (startsAtMs == null || endsAtMs == null)) return null;
  if (family === "reward" && params.enabled === false) return null;

  let target: string;
  if (endsAtMs != null && nowMs >= endsAtMs) {
    target = family === "match" ? "locked" : family === "challenge" ? "ended" : "expired";
  } else if (startsAtMs != null && nowMs < startsAtMs) {
    target = "scheduled";
  } else {
    target = family === "match" ? "open" : family === "challenge" ? "live" : "active";
  }
  // `live` is an intentional supported reward alias, not a transitional
  // state. Preserve it while the configured window remains active.
  if (family === "reward" && currentStatus === "live" && target === "active") return null;
  return target === currentStatus ? null : target;
}

/** Deterministic exponential retry with a one-hour cap. */
export function matchResultRetryDelayMs(attemptCount: number): number {
  if (!Number.isSafeInteger(attemptCount) || attemptCount < 1) {
    throw new Error("Attempt count must be a positive integer.");
  }
  return Math.min(60 * 60 * 1000, 30_000 * (2 ** Math.min(7, attemptCount - 1)));
}

export function resultJobCanBeClaimed(
  data: Record<string, unknown>,
  nowMs: number,
): boolean {
  const status = String(data.status ?? "") as ResultJobStatus;
  if (status === "pending" || status === "retry") {
    const nextAttemptAtMs = timestampMillis(data.nextAttemptAt);
    return nextAttemptAtMs != null && nextAttemptAtMs <= nowMs;
  }
  if (status === "processing") {
    const leaseExpiresAtMs = timestampMillis(data.leaseExpiresAt);
    return leaseExpiresAtMs != null && leaseExpiresAtMs <= nowMs;
  }
  return false;
}

function jobError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.trim().slice(0, MAX_RESULT_ERROR_LENGTH) || "Unknown settlement error.";
}

function scheduleFields(
  family: ScheduleFamily,
  data: Record<string, unknown>,
): {startsAtMs: number | null; endsAtMs: number | null} {
  if (family === "match") {
    return {
      startsAtMs: timestampMillis(data.predictionOpensAt),
      endsAtMs: timestampMillis(data.predictionClosesAt),
    };
  }
  return {
    startsAtMs: timestampMillis(data.availableFrom ?? data.startsAt),
    endsAtMs: timestampMillis(data.availableUntil ?? data.endsAt),
  };
}

function transitionAuditFields(family: ScheduleFamily, target: string): Record<string, unknown> {
  if (family === "match" && target === "open") {
    return {predictionOpenedAt: FieldValue.serverTimestamp()};
  }
  if (family === "match" && target === "locked") {
    return {predictionLockedAt: FieldValue.serverTimestamp()};
  }
  if ((family === "challenge" && target === "live") ||
      (family === "reward" && target === "active")) {
    return {activatedAt: FieldValue.serverTimestamp()};
  }
  if ((family === "challenge" && target === "ended") ||
      (family === "reward" && target === "expired")) {
    return {expiredAt: FieldValue.serverTimestamp()};
  }
  return {};
}

/**
 * Builds testable handlers. `settleMatchResult` must be the same shared
 * settlement routine used by the admin callable so point-ledger logic remains
 * single-sourced and duplicate scheduler delivery is safe.
 */
export function createPhase3SchedulingHandlers(options: Phase3SchedulingOptions): {
  processAutomaticMatchResults: (workerId: string) => Promise<AutomaticResultRun>;
  sweepScheduledEvents: () => Promise<ScheduleSweepRun>;
} {
  const db = options.db;
  const now = options.now ?? (() => Timestamp.now());
  const resultBatchSize = safePositiveInteger(
    options.resultBatchSize,
    DEFAULT_RESULT_BATCH_SIZE,
    20,
  );
  const schedulePageSize = safePositiveInteger(
    options.schedulePageSize,
    DEFAULT_SCHEDULE_PAGE_SIZE,
    500,
  );
  const leaseDurationMs = safePositiveInteger(
    options.leaseDurationMs,
    DEFAULT_LEASE_DURATION_MS,
    60 * 60 * 1000,
  );
  const maxResultAttempts = safePositiveInteger(
    options.maxResultAttempts,
    DEFAULT_MAX_RESULT_ATTEMPTS,
    100,
  );
  const resultQueueCollection = options.resultQueueCollection ?? "matchResultJobs";

  async function resultCandidates(at: Timestamp): Promise<DocumentReference<DocumentData>[]> {
    const collection = db.collection(resultQueueCollection);
    const [ready, expiredLeases] = await Promise.all([
      collection
        .where("status", "in", ["pending", "retry"])
        .where("nextAttemptAt", "<=", at)
        .orderBy("nextAttemptAt")
        .limit(resultBatchSize)
        .get(),
      collection
        .where("status", "==", "processing")
        .where("leaseExpiresAt", "<=", at)
        .orderBy("leaseExpiresAt")
        .limit(resultBatchSize)
        .get(),
    ]);
    const unique = new Map<string, DocumentReference<DocumentData>>();
    // Recover abandoned work before accepting fresh jobs. Otherwise a steady
    // stream of new results could starve expired leases forever.
    for (const doc of [...expiredLeases.docs, ...ready.docs]) {
      if (unique.size >= resultBatchSize) break;
      unique.set(doc.id, doc.ref);
    }
    return [...unique.values()];
  }

  async function claimResultJob(
    ref: DocumentReference<DocumentData>,
    workerId: string,
  ): Promise<ClaimedResultJob | null> {
    const claimedAt = now();
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return null;
      const data = snapshot.data()!;
      if (!resultJobCanBeClaimed(data, claimedAt.toMillis())) return null;
      const previousAttempts = Number(data.attemptCount ?? 0);
      if (!Number.isSafeInteger(previousAttempts) || previousAttempts < 0 ||
          previousAttempts >= maxResultAttempts) {
        transaction.update(ref, {
          status: "failed",
          lastError: "Result job exceeded its retry limit or has an invalid attempt count.",
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          leaseOwner: null,
          leaseExpiresAt: null,
        });
        return null;
      }
      let result: OfficialMatchResult;
      try {
        result = parseOfficialMatchResult(data);
      } catch (error) {
        transaction.update(ref, {
          status: "failed",
          lastError: jobError(error),
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          leaseOwner: null,
          leaseExpiresAt: null,
        });
        return null;
      }
      const attemptCount = previousAttempts + 1;
      transaction.update(ref, {
        status: "processing",
        attemptCount,
        leaseOwner: workerId,
        leaseExpiresAt: Timestamp.fromMillis(claimedAt.toMillis() + leaseDurationMs),
        resultHash: automaticMatchResultHash(result),
        processingStartedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        ref,
        jobId: snapshot.id,
        source: typeof data.source === "string" ? data.source.slice(0, 120) : "unknown",
        workerId,
        attemptCount,
        result,
      };
    });
  }

  async function completeResultJob(job: ClaimedResultJob): Promise<boolean> {
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(job.ref);
      const data = snapshot.data();
      if (!snapshot.exists || data?.status !== "processing" || data.leaseOwner !== job.workerId) {
        return false;
      }
      transaction.update(job.ref, {
        status: "completed",
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        leaseOwner: null,
        leaseExpiresAt: null,
        lastError: null,
      });
      return true;
    });
  }

  async function failResultJob(job: ClaimedResultJob, error: unknown): Promise<ResultJobStatus> {
    const retryAt = now();
    const terminal = job.attemptCount >= maxResultAttempts;
    const nextStatus: ResultJobStatus = terminal ? "failed" : "retry";
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(job.ref);
      const data = snapshot.data();
      if (!snapshot.exists || data?.status !== "processing" || data.leaseOwner !== job.workerId) {
        return String(data?.status ?? "failed") as ResultJobStatus;
      }
      transaction.update(job.ref, {
        status: nextStatus,
        lastError: jobError(error),
        lastErrorAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        leaseOwner: null,
        leaseExpiresAt: null,
        nextAttemptAt: terminal ? null : Timestamp.fromMillis(
          retryAt.toMillis() + matchResultRetryDelayMs(job.attemptCount),
        ),
        ...(terminal ? {failedAt: FieldValue.serverTimestamp()} : {}),
      });
      return nextStatus;
    });
  }

  async function resultWasAlreadySettled(job: ClaimedResultJob): Promise<boolean> {
    const match = await db.collection("matches").doc(job.result.matchId).get();
    return match.exists && storedMatchHasProcessedResult(match.data()!, job.result);
  }

  async function processAutomaticMatchResults(workerId: string): Promise<AutomaticResultRun> {
    const invocationLabel = workerId.trim().slice(0, 180);
    if (!invocationLabel) throw new Error("A scheduler worker ID is required.");
    // scheduleTime/jobName identify a logical delivery, not an individual
    // attempt. Add entropy so an expired lease reclaimed by a retry can never
    // be completed or released by the original still-running invocation.
    const normalizedWorkerId = `${randomUUID()}:${invocationLabel}`;
    const refs = await resultCandidates(now());
    const run: AutomaticResultRun = {
      candidates: refs.length,
      claimed: 0,
      completed: 0,
      retried: 0,
      failed: 0,
      skipped: 0,
    };
    // Settlement can touch many predictions. Keep the batch deliberately
    // small and sequential so one scheduler invocation does not fan out an
    // unbounded number of point-award transactions.
    for (const ref of refs) {
      const job = await claimResultJob(ref, normalizedWorkerId);
      if (job == null) {
        run.skipped += 1;
        continue;
      }
      run.claimed += 1;
      try {
        await options.settleMatchResult(job.result, {
          jobId: job.jobId,
          source: job.source,
          workerId: normalizedWorkerId,
        });
        if (await completeResultJob(job)) run.completed += 1;
        else run.skipped += 1;
      } catch (error) {
        // Settlement may have committed before its caller lost the response,
        // or the shared routine may report a same-result replay. Confirm the
        // stored result before scheduling another attempt.
        if (await resultWasAlreadySettled(job)) {
          if (await completeResultJob(job)) run.completed += 1;
          else run.skipped += 1;
          continue;
        }
        const status = await failResultJob(job, error);
        if (status === "retry") run.retried += 1;
        else if (status === "failed") run.failed += 1;
        else run.skipped += 1;
      }
    }
    return run;
  }

  async function transitionScheduledDocument(
    ref: DocumentReference<DocumentData>,
    target: ScheduleTarget,
    at: Timestamp,
  ): Promise<"transitioned" | "unchanged" | "invalid"> {
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) return "unchanged";
      const data = snapshot.data()!;
      const currentStatus = String(data.status ?? "");
      if (!target.statuses.includes(currentStatus)) return "unchanged";
      const schedule = scheduleFields(target.family, data);
      if ((target.family !== "reward" &&
          (schedule.startsAtMs == null || schedule.endsAtMs == null)) ||
          (schedule.startsAtMs != null && schedule.endsAtMs != null &&
            schedule.startsAtMs >= schedule.endsAtMs)) {
        return "invalid";
      }
      const nextStatus = scheduledTargetStatus({
        family: target.family,
        currentStatus,
        nowMs: at.toMillis(),
        startsAtMs: schedule.startsAtMs,
        endsAtMs: schedule.endsAtMs,
        enabled: data.enabled !== false,
      });
      if (nextStatus == null) return "unchanged";
      const updatedAt = FieldValue.serverTimestamp();
      transaction.update(ref, {
        status: nextStatus,
        scheduleUpdatedAt: updatedAt,
        updatedAt,
        ...transitionAuditFields(target.family, nextStatus),
      });
      return "transitioned";
    });
  }

  async function sweepTarget(
    target: ScheduleTarget,
    at: Timestamp,
  ): Promise<{scanned: number; transitioned: number; skippedInvalid: number}> {
    let scanned = 0;
    let transitioned = 0;
    let skippedInvalid = 0;
    let cursor: string | null = null;
    while (true) {
      let query = db.collection(target.collection)
        .where("status", "in", target.statuses)
        .orderBy(FieldPath.documentId())
        .limit(schedulePageSize);
      if (cursor != null) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      scanned += page.size;
      for (let index = 0; index < page.docs.length; index += 20) {
        const chunk = page.docs.slice(index, index + 20);
        const outcomes = await Promise.all(chunk.map((doc) =>
          transitionScheduledDocument(doc.ref, target, at),
        ));
        transitioned += outcomes.filter((outcome) => outcome === "transitioned").length;
        skippedInvalid += outcomes.filter((outcome) => outcome === "invalid").length;
      }
      cursor = page.docs.at(-1)!.id;
      if (page.size < schedulePageSize) break;
    }
    return {scanned, transitioned, skippedInvalid};
  }

  async function sweepScheduledEvents(): Promise<ScheduleSweepRun> {
    const at = now();
    const run: ScheduleSweepRun = {
      scanned: 0,
      transitioned: 0,
      skippedInvalid: 0,
      byCollection: {},
    };
    // A partial invocation is safe: completed transitions are idempotent, and
    // Cloud Scheduler may retry the whole handler after a later target fails.
    for (const target of SCHEDULE_TARGETS) {
      const result = await sweepTarget(target, at);
      run.scanned += result.scanned;
      run.transitioned += result.transitioned;
      run.skippedInvalid += result.skippedInvalid;
      run.byCollection[target.collection] = result.transitioned;
    }
    return run;
  }

  return {processAutomaticMatchResults, sweepScheduledEvents};
}
