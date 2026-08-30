import {createHash} from "node:crypto";

import {
  FieldValue,
  Firestore,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import {
  CallableOptions,
  CallableRequest,
  HttpsError,
} from "firebase-functions/v2/https";

export type AppCheckMode = "off" | "monitor" | "enforce";
export type SuspiciousSeverity = "low" | "medium" | "high" | "critical";
export type SecuritySubjectType = "user" | "ip" | "device";

export const securityHashPepper = defineSecret("SECURITY_HASH_PEPPER");

const DEFAULT_WINDOW_SECONDS = 60;
const DEFAULT_USER_LIMIT = 20;
const DEFAULT_DEVICE_LIMIT = 30;
const DEFAULT_IP_LIMIT = 100;
const MAX_ACTION_LENGTH = 80;
const severityRank: Record<SuspiciousSeverity, number> = {
  low: 0,
  medium: 1,
  high: 2,
  critical: 3,
};

export interface SecurityEnvironment {
  FUNCTIONS_EMULATOR?: string;
  FIREBASE_EMULATOR_HUB?: string;
  ABU3MEER_APP_CHECK_MODE?: string;
  GCLOUD_PROJECT?: string;
  GCP_PROJECT?: string;
}

export interface CallableSecurityPolicy {
  action: string;
  requireAuth?: boolean;
  requireActiveProfile?: boolean;
  windowSeconds?: number;
  perUserLimit?: number | null;
  perDeviceLimit?: number | null;
  perIpLimit?: number | null;
  rejectConsumedAppCheckToken?: boolean;
  logMissingAppCheck?: boolean;
}

export interface CallableSecurityContext {
  uid: string | null;
  userHash: string | null;
  action: string;
  appId: string | null;
  ipHash: string;
  deviceHash: string | null;
  appCheckMode: AppCheckMode;
}

export interface RateLimitSubject {
  type: SecuritySubjectType;
  hash: string;
  limit: number;
}

export interface RateLimitDecision {
  allowed: boolean;
  count: number;
  limit: number;
  retryAfterSeconds: number;
  subject: RateLimitSubject;
}

export interface IdempotencyReservation {
  state: "created" | "duplicate" | "conflict";
  documentId: string;
  payloadHash: string;
  previousStatus?: string;
}

/** App Check is deliberately disabled in local emulators. */
export function isFirebaseEmulator(
  environment: SecurityEnvironment = process.env,
): boolean {
  return environment.FUNCTIONS_EMULATOR === "true" ||
    Boolean(environment.FIREBASE_EMULATOR_HUB);
}

export function resolveAppCheckMode(
  environment: SecurityEnvironment = process.env,
): AppCheckMode {
  if (isFirebaseEmulator(environment)) return "off";
  const configured = environment.ABU3MEER_APP_CHECK_MODE?.trim().toLowerCase();
  return configured === "enforce" || configured === "monitor" ? configured : "off";
}

/**
 * Reusable callable options for the staged App Check rollout.
 *
 * `replayProtected` should only be enabled for low-volume, security-critical
 * mutations because token consumption adds an App Check network round trip.
 */
export function phase3CallableOptions(
  region: string,
  options: {replayProtected?: boolean; environment?: SecurityEnvironment} = {},
): CallableOptions {
  const mode = resolveAppCheckMode(options.environment);
  return {
    region,
    enforceAppCheck: mode === "enforce",
    consumeAppCheckToken: mode === "enforce" && options.replayProtected === true,
    secrets: [securityHashPepper],
  };
}

function normalizedAction(action: string): string {
  const value = action.trim();
  if (!value || value.length > MAX_ACTION_LENGTH || !/^[A-Za-z0-9_.:-]+$/.test(value)) {
    throw new Error("Security action names must be short stable identifiers.");
  }
  return value;
}

function pepperValue(environment: SecurityEnvironment = process.env): string {
  if (isFirebaseEmulator(environment)) return "abu3meer-emulator-only-pepper";
  const secret = securityHashPepper.value().trim();
  if (secret.length < 32) {
    throw new Error("SECURITY_HASH_PEPPER must contain at least 32 characters.");
  }
  return secret;
}

export function securityHash(value: string, pepper: string): string {
  return createHash("sha256").update(`${pepper}\u0000${value}`).digest("hex");
}

export function clientIp(request: CallableRequest<unknown>): string {
  // Express resolves the trusted Cloud Functions proxy chain into `ip`.
  // Never trust a caller-supplied x-forwarded-for value directly.
  const value = request.rawRequest.ip?.trim();
  return value && value.length <= 128 ? value : "unknown";
}

export function fixedWindowBucket(nowMillis: number, windowSeconds: number): number {
  if (!Number.isFinite(nowMillis) || !Number.isInteger(windowSeconds) || windowSeconds < 1) {
    throw new Error("Invalid fixed-window rate limit input.");
  }
  return Math.floor(nowMillis / (windowSeconds * 1000));
}

export function fixedWindowRetryAfterSeconds(
  nowMillis: number,
  windowSeconds: number,
): number {
  const bucket = fixedWindowBucket(nowMillis, windowSeconds);
  const nextWindow = (bucket + 1) * windowSeconds * 1000;
  return Math.max(1, Math.ceil((nextWindow - nowMillis) / 1000));
}

function stableValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, entry]) => [key, stableValue(entry)]),
    );
  }
  if (["string", "number", "boolean"].includes(typeof value) || value == null) {
    return value;
  }
  throw new Error("Idempotency payloads must be JSON-compatible.");
}

export function idempotencyPayloadHash(payload: unknown): string {
  return createHash("sha256").update(JSON.stringify(stableValue(payload))).digest("hex");
}

function firestoreFor(database?: Firestore): Firestore {
  return database ?? getFirestore();
}

function eventDocumentId(params: {
  action: string;
  reason: string;
  subjectHash: string;
  nowMillis: number;
}): string {
  const hour = Math.floor(params.nowMillis / 3_600_000);
  return createHash("sha256")
    .update(`${params.action}|${params.reason}|${params.subjectHash}|${hour}`)
    .digest("hex");
}

export async function recordSuspiciousEvent(params: {
  action: string;
  reason: string;
  severity: SuspiciousSeverity;
  uid?: string | null;
  appId?: string | null;
  ipHash?: string | null;
  deviceHash?: string | null;
  subjectType: SecuritySubjectType;
  subjectHash: string;
  metadata?: Record<string, string | number | boolean | null>;
  nowMillis?: number;
  database?: Firestore;
}): Promise<string> {
  const database = firestoreFor(params.database);
  const action = normalizedAction(params.action);
  const nowMillis = params.nowMillis ?? Date.now();
  const documentId = eventDocumentId({
    action,
    reason: params.reason,
    subjectHash: params.subjectHash,
    nowMillis,
  });
  const reference = database.collection("suspiciousEvents").doc(documentId);
  await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const timestamp = Timestamp.fromMillis(nowMillis);
    if (existing.exists) {
      const previousSeverity = existing.data()?.severity as SuspiciousSeverity | undefined;
      const nextSeverity = previousSeverity && severityRank[previousSeverity] > severityRank[params.severity]
        ? previousSeverity
        : params.severity;
      const closed = ["resolved", "dismissed"].includes(String(existing.data()?.status));
      transaction.update(reference, {
        occurrences: FieldValue.increment(1),
        lastSeen: timestamp,
        severity: nextSeverity,
        ...(closed ? {
          status: "open",
          resolutionNote: FieldValue.delete(),
          resolvedAt: FieldValue.delete(),
          resolvedBy: FieldValue.delete(),
        } : {}),
        metadata: params.metadata ?? {},
      });
      return;
    }
    transaction.create(reference, {
      action,
      reason: params.reason.slice(0, 120),
      severity: params.severity,
      status: "open",
      userId: params.uid ?? null,
      appId: params.appId ?? null,
      ipHash: params.ipHash ?? null,
      deviceHash: params.deviceHash ?? null,
      subjectType: params.subjectType,
      subjectHash: params.subjectHash,
      occurrences: 1,
      metadata: params.metadata ?? {},
      firstSeen: timestamp,
      lastSeen: timestamp,
      createdAt: timestamp,
    });
  });
  return documentId;
}

export async function consumeRateLimits(params: {
  action: string;
  subjects: RateLimitSubject[];
  windowSeconds?: number;
  nowMillis?: number;
  database?: Firestore;
}): Promise<RateLimitDecision[]> {
  const action = normalizedAction(params.action);
  const database = firestoreFor(params.database);
  const nowMillis = params.nowMillis ?? Date.now();
  const windowSeconds = params.windowSeconds ?? DEFAULT_WINDOW_SECONDS;
  const bucket = fixedWindowBucket(nowMillis, windowSeconds);
  const retryAfterSeconds = fixedWindowRetryAfterSeconds(nowMillis, windowSeconds);
  const uniqueSubjects = new Map(
    params.subjects
      .filter((subject) => subject.limit > 0)
      .map((subject) => [`${subject.type}:${subject.hash}`, subject]),
  );
  const entries = [...uniqueSubjects.values()].map((subject) => {
    const id = securityHash(`${action}|${subject.type}|${subject.hash}|${bucket}`, "rate-limit-document");
    return {
      subject,
      reference: database.collection("securityRateLimits").doc(id),
    };
  });
  if (entries.length === 0) return [];

  return database.runTransaction(async (transaction) => {
    const snapshots = await Promise.all(entries.map((entry) => transaction.get(entry.reference)));
    return entries.map((entry, index) => {
      const count = Number(snapshots[index].data()?.count ?? 0) + 1;
      transaction.set(entry.reference, {
        action,
        subjectType: entry.subject.type,
        subjectHash: entry.subject.hash,
        bucket,
        count,
        limit: entry.subject.limit,
        windowSeconds,
        updatedAt: Timestamp.fromMillis(nowMillis),
        expireAt: Timestamp.fromMillis((bucket + 2) * windowSeconds * 1000),
      }, {merge: true});
      return {
        allowed: count <= entry.subject.limit,
        count,
        limit: entry.subject.limit,
        retryAfterSeconds,
        subject: entry.subject,
      };
    });
  });
}

function requestSubjects(
  request: CallableRequest<unknown>,
  policy: CallableSecurityPolicy,
  pepper: string,
): {subjects: RateLimitSubject[]; ipHash: string; deviceHash: string | null} {
  const ipHash = securityHash(clientIp(request), pepper);
  const deviceHash = request.instanceIdToken
    ? securityHash(request.instanceIdToken, pepper)
    : null;
  const subjects: RateLimitSubject[] = [];
  if (request.auth?.uid && policy.perUserLimit !== null) {
    subjects.push({
      type: "user",
      hash: securityHash(request.auth.uid, pepper),
      limit: policy.perUserLimit ?? DEFAULT_USER_LIMIT,
    });
  }
  if (policy.perIpLimit !== null) {
    subjects.push({
      type: "ip",
      hash: ipHash,
      limit: policy.perIpLimit ?? DEFAULT_IP_LIMIT,
    });
  }
  if (deviceHash && policy.perDeviceLimit !== null) {
    subjects.push({
      type: "device",
      hash: deviceHash,
      limit: policy.perDeviceLimit ?? DEFAULT_DEVICE_LIMIT,
    });
  }
  return {subjects, ipHash, deviceHash};
}

/**
 * Handler-level security gate to call before reading or mutating business data.
 * App Check trigger enforcement must additionally use `phase3CallableOptions`.
 */
export async function enforceCallableSecurity(
  request: CallableRequest<unknown>,
  policy: CallableSecurityPolicy,
  options: {
    database?: Firestore;
    environment?: SecurityEnvironment;
    nowMillis?: number;
    pepper?: string;
  } = {},
): Promise<CallableSecurityContext> {
  const database = firestoreFor(options.database);
  const action = normalizedAction(policy.action);
  const mode = resolveAppCheckMode(options.environment);
  const uid = request.auth?.uid ?? null;
  const appId = request.app?.appId ?? null;
  const pepper = options.pepper ?? pepperValue(options.environment);
  const {subjects, ipHash, deviceHash} = requestSubjects(request, policy, pepper);
  const primarySubject = subjects.find((subject) => subject.type === "user") ??
    subjects.find((subject) => subject.type === "device") ??
    subjects[0] ?? {type: "ip" as const, hash: ipHash, limit: DEFAULT_IP_LIMIT};
  const eventBase = {
    action,
    uid,
    appId,
    ipHash,
    deviceHash,
    subjectType: primarySubject.type,
    subjectHash: primarySubject.hash,
    nowMillis: options.nowMillis,
    database,
  };

  if ((policy.requireAuth ?? true) && !uid) {
    throw new HttpsError("unauthenticated", "Sign in is required.");
  }

  if (mode === "enforce" && !request.app) {
    await recordSuspiciousEvent({
      ...eventBase,
      reason: "missing_app_check",
      severity: "high",
    });
    throw new HttpsError("failed-precondition", "App verification is required.");
  }
  if (mode === "monitor" && !request.app && policy.logMissingAppCheck !== false) {
    await recordSuspiciousEvent({
      ...eventBase,
      reason: "missing_app_check",
      severity: "low",
    });
  }
  if (request.app?.alreadyConsumed === true && policy.rejectConsumedAppCheckToken === true) {
    await recordSuspiciousEvent({
      ...eventBase,
      reason: "replayed_app_check_token",
      severity: "high",
    });
    throw new HttpsError("failed-precondition", "This verified request was already used.");
  }

  if (uid && (policy.requireActiveProfile ?? true)) {
    const profile = await database.collection("users").doc(uid).get();
    if (!profile.exists) {
      throw new HttpsError("failed-precondition", "User profile is missing.");
    }
    if (profile.data()?.suspended === true) {
      await recordSuspiciousEvent({
        ...eventBase,
        reason: "suspended_account_attempt",
        severity: "medium",
      });
      throw new HttpsError("permission-denied", "This account is suspended.");
    }
  }

  const decisions = await consumeRateLimits({
    action,
    subjects,
    windowSeconds: policy.windowSeconds,
    nowMillis: options.nowMillis,
    database,
  });
  const denied = decisions.find((decision) => !decision.allowed);
  if (denied) {
    await recordSuspiciousEvent({
      ...eventBase,
      subjectType: denied.subject.type,
      subjectHash: denied.subject.hash,
      reason: `rate_limit_${denied.subject.type}`,
      severity: denied.count > denied.limit * 2 ? "high" : "medium",
      metadata: {
        count: denied.count,
        limit: denied.limit,
        windowSeconds: policy.windowSeconds ?? DEFAULT_WINDOW_SECONDS,
      },
    });
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Try again shortly.",
      {retryAfterSeconds: denied.retryAfterSeconds},
    );
  }

  return {
    uid,
    userHash: subjects.find((subject) => subject.type === "user")?.hash ?? null,
    action,
    appId,
    ipHash,
    deviceHash,
    appCheckMode: mode,
  };
}

export async function reserveIdempotencyKey(params: {
  uid: string;
  action: string;
  key: string;
  payload: unknown;
  ttlSeconds?: number;
  nowMillis?: number;
  database?: Firestore;
}): Promise<IdempotencyReservation> {
  const action = normalizedAction(params.action);
  const key = params.key.trim();
  if (key.length < 8 || key.length > 128 || !/^[A-Za-z0-9._:-]+$/.test(key)) {
    throw new HttpsError("invalid-argument", "A valid idempotency key is required.");
  }
  const database = firestoreFor(params.database);
  const nowMillis = params.nowMillis ?? Date.now();
  const ttlSeconds = params.ttlSeconds ?? 86_400;
  if (!Number.isInteger(ttlSeconds) || ttlSeconds < 60 || ttlSeconds > 604_800) {
    throw new Error("Idempotency TTL must be between one minute and seven days.");
  }
  const payloadHash = idempotencyPayloadHash(params.payload);
  const documentId = securityHash(`${params.uid}|${action}|${key}`, "idempotency-document");
  const reference = database.collection("securityIdempotency").doc(documentId);
  return database.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const existingExpiry = snapshot.data()?.expireAt;
    const expired = existingExpiry instanceof Timestamp && existingExpiry.toMillis() <= nowMillis;
    if (snapshot.exists && !expired) {
      const samePayload = snapshot.data()?.payloadHash === payloadHash;
      return {
        state: samePayload ? "duplicate" : "conflict",
        documentId,
        payloadHash,
        previousStatus: String(snapshot.data()?.status ?? "processing"),
      };
    }
    transaction.set(reference, {
      userId: params.uid,
      action,
      keyHash: securityHash(key, "idempotency-key"),
      payloadHash,
      status: "processing",
      createdAt: Timestamp.fromMillis(nowMillis),
      updatedAt: Timestamp.fromMillis(nowMillis),
      expireAt: Timestamp.fromMillis(nowMillis + ttlSeconds * 1000),
    });
    return {state: "created", documentId, payloadHash};
  });
}

export async function rejectIdempotencyConflict(params: {
  reservation: IdempotencyReservation;
  context: CallableSecurityContext;
  database?: Firestore;
}): Promise<void> {
  if (params.reservation.state !== "conflict") return;
  const subjectHash = params.context.userHash ??
    params.context.deviceHash ??
    params.context.ipHash;
  await recordSuspiciousEvent({
    action: params.context.action,
    reason: "idempotency_key_payload_conflict",
    severity: "high",
    uid: params.context.uid,
    appId: params.context.appId,
    ipHash: params.context.ipHash,
    deviceHash: params.context.deviceHash,
    subjectType: params.context.uid ? "user" : params.context.deviceHash ? "device" : "ip",
    subjectHash,
    metadata: {reservationId: params.reservation.documentId},
    database: params.database,
  });
  throw new HttpsError(
    "already-exists",
    "This idempotency key was already used for a different request.",
  );
}

export async function completeIdempotencyKey(params: {
  reservation: IdempotencyReservation;
  status?: "succeeded" | "failed";
  database?: Firestore;
}): Promise<void> {
  if (params.reservation.state !== "created") return;
  await firestoreFor(params.database)
    .collection("securityIdempotency")
    .doc(params.reservation.documentId)
    .update({
      status: params.status ?? "succeeded",
      updatedAt: FieldValue.serverTimestamp(),
    });
}
