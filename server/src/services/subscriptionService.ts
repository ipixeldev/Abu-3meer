import { timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';
import { query } from '../db/pool.js';

export interface SubscriptionStatus {
  entitlementId: 'abu_3meer_pro';
  isActive: boolean;
  productId: string | null;
  expiresAt: string | null;
  willRenew: boolean;
  isSandbox: boolean;
  verifiedAt: string | null;
  accessReason: 'active' | 'sandbox_not_allowed' | 'no_entitlement'
    | 'expired' | 'verification_required' | 'inactive' | 'admin_granted' | 'admin_revoked';
  environment: 'production' | 'sandbox' | 'unknown';
  accessSource: 'admin' | 'store' | 'none';
  subscriptionAccessMode: 'active' | 'inactive' | 'store';
  subscriptionAccessExpiresAt: string | null;
}

// Policy decisions are derived when reading. Persist the verified upstream
// subscription, not a sandbox-policy denial that would hide why access stopped.
type VerifiedSubscriptionStatus = Omit<SubscriptionStatus,
  'accessReason' | 'environment' | 'accessSource' | 'subscriptionAccessMode' | 'subscriptionAccessExpiresAt'>;

export class SubscriptionError extends Error {
  constructor(public code: string, message: string, public statusCode = 503) {
    super(message);
  }
}

type JsonObject = Record<string, unknown>;
const object = (value: unknown): JsonObject | undefined =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonObject : undefined;
const validDate = (value: unknown): number | null => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
};

export function emptySubscriptionStatus(): SubscriptionStatus {
  return {
    entitlementId: 'abu_3meer_pro', isActive: false, productId: null,
    expiresAt: null, willRenew: false, isSandbox: false, verifiedAt: null,
    accessReason: 'no_entitlement', environment: 'unknown',
    accessSource: 'none', subscriptionAccessMode: 'store', subscriptionAccessExpiresAt: null,
  };
}

/** Parse only the server-to-server customer response, never a client payload. */
export function subscriptionFromRevenueCat(
  value: unknown,
  now = Date.now(),
): VerifiedSubscriptionStatus {
  const subscriber = object(object(value)?.subscriber);
  if (!subscriber || !object(subscriber.entitlements)) {
    throw new SubscriptionError('subscription_response_invalid', 'Subscription verification is temporarily unavailable.');
  }
  const status = { ...emptySubscriptionStatus(), verifiedAt: new Date(now).toISOString() };
  const entitlement = object(object(subscriber.entitlements)?.abu_3meer_pro);
  if (!entitlement) return status;
  const productId = entitlement.product_identifier;
  if (typeof productId !== 'string' || productId.length > 255) return status;
  const subscription = object(object(subscriber.subscriptions)?.[productId]);
  if (!subscription) return status;
  // These products are recurring subscriptions. Missing expiry or unknown
  // sandbox provenance is never interpreted as perpetual paid access.
  const expiration = validDate(entitlement.expires_date);
  const graceExpiration = validDate(entitlement.grace_period_expires_date);
  const effectiveExpiration = expiration === null ? null : Math.max(expiration, graceExpiration ?? 0);
  const isSandbox = subscription.is_sandbox !== false || subscription.store === 'test_store';
  const active = effectiveExpiration !== null && effectiveExpiration > now
    && typeof subscription.is_sandbox === 'boolean'
    && subscription.refunded_at == null;
  return {
    ...status,
    isActive: active,
    productId,
    expiresAt: effectiveExpiration === null ? null : new Date(effectiveExpiration).toISOString(),
    willRenew: active && subscription.unsubscribe_detected_at == null
      && subscription.billing_issues_detected_at == null,
    isSandbox,
  };
}

export function enforceSubscriptionAccess(
  status: VerifiedSubscriptionStatus,
  now = Date.now(),
  allowSandbox = config.revenueCat.allowSandbox,
): SubscriptionStatus {
  const expires = validDate(status.expiresAt);
  const verified = validDate(status.verifiedAt);
  // An inactive legacy row may not contain enough upstream provenance to
  // distinguish a refund from malformed data. Do not label that as production.
  const environment = status.isActive && status.productId && expires !== null && verified !== null
    ? (status.isSandbox ? 'sandbox' : 'production') : 'unknown';
  let accessReason: SubscriptionStatus['accessReason'];
  if (!status.productId) accessReason = 'no_entitlement';
  else if (expires !== null && expires <= now) accessReason = 'expired';
  else if (!status.isActive || expires === null) accessReason = 'inactive';
  else if (verified === null || verified > now + 60_000
    || verified <= now - config.revenueCat.verificationMaxAgeSeconds * 1000) {
    accessReason = 'verification_required';
  } else if (status.isSandbox && !allowSandbox) accessReason = 'sandbox_not_allowed';
  else accessReason = 'active';
  const active = accessReason === 'active';
  return {
    ...status, isActive: active, willRenew: active && status.willRenew, accessReason, environment,
    accessSource: status.productId ? 'store' : 'none',
    subscriptionAccessMode: 'store', subscriptionAccessExpiresAt: null,
  };
}

export function sandboxAccessAllowedForUser(
  userId: string,
  allowSandbox = config.revenueCat.allowSandbox,
  allowedUserIds = config.revenueCat.sandboxAllowedUserIds,
): boolean {
  if (allowSandbox) return true;
  const normalized = userId.trim().toLowerCase();
  return allowedUserIds.some(value => value.toLowerCase() === normalized);
}

/** Overrides grant app access only; store product, expiry and provenance remain truthful. */
export function applySubscriptionAccessOverride(
  status: SubscriptionStatus,
  override: { mode?: unknown; expiresAt?: unknown },
  now = Date.now(),
): SubscriptionStatus {
  const mode = override.mode === 'active' || override.mode === 'inactive' ? override.mode : 'store';
  const expiry = validDate(override.expiresAt);
  const base: SubscriptionStatus = { ...status, subscriptionAccessMode: mode,
    subscriptionAccessExpiresAt: expiry === null ? null : new Date(expiry).toISOString() };
  if (mode === 'inactive') {
    return { ...base, isActive: false, accessReason: 'admin_revoked', accessSource: 'admin' };
  }
  if (mode === 'active' && (override.expiresAt == null || (expiry !== null && expiry > now))) {
    return { ...base, isActive: true, accessReason: 'admin_granted', accessSource: 'admin' };
  }
  return base;
}

type SubscriptionQuery = (text: string, params?: unknown[]) => Promise<{rows: JsonObject[]}>;

export async function readSubscriptionStatus(
  userId: string,
  execute: SubscriptionQuery = query,
): Promise<SubscriptionStatus> {
  const result = await execute(
    `SELECT s.is_active, s.product_id, s.expires_at, s.will_renew, s.is_sandbox, s.verified_at,
            o.mode AS access_override_mode, o.expires_at AS access_override_expires_at
     FROM (SELECT $1::uuid AS user_id) selected
     LEFT JOIN user_subscription_entitlements s ON s.user_id = selected.user_id
       AND s.entitlement_id = 'abu_3meer_pro'
     LEFT JOIN user_subscription_access_overrides o ON o.user_id = selected.user_id`,
    [userId],
  );
  const row = result.rows[0];
  if (!row) return emptySubscriptionStatus();
  const storeStatus = enforceSubscriptionAccess({
    entitlementId: 'abu_3meer_pro',
    isActive: row.is_active === true,
    productId: typeof row.product_id === 'string' ? row.product_id : null,
    expiresAt: row.expires_at ? new Date(row.expires_at as string).toISOString() : null,
    willRenew: row.will_renew === true,
    isSandbox: row.is_sandbox === true,
    verifiedAt: row.verified_at ? new Date(row.verified_at as string).toISOString() : null,
  }, Date.now(), sandboxAccessAllowedForUser(userId));
  return applySubscriptionAccessOverride(storeStatus, {
    mode: row.access_override_mode,
    expiresAt: row.access_override_expires_at
      ? new Date(row.access_override_expires_at as string).toISOString() : null,
  });
}

export async function syncSubscriptionStatus(
  userId: string,
  dependencies: {
    execute?: SubscriptionQuery;
    fetchCustomer?: (userId: string) => Promise<unknown>;
  } = {},
): Promise<SubscriptionStatus> {
  const execute = dependencies.execute ?? query;
  const response = await (dependencies.fetchCustomer ?? fetchRevenueCatCustomer)(userId);
  const now = Date.now();
  const verified = subscriptionFromRevenueCat(response, now);
  const sourceRequestedAt = validDate(object(response)?.request_date) ?? now;
  if (sourceRequestedAt > now + 60_000) {
    throw new SubscriptionError('subscription_response_invalid', 'Subscription verification is temporarily unavailable.');
  }
  // A delayed response must not overwrite a more recent renewal/refund sync.
  await execute(
    `INSERT INTO user_subscription_entitlements
       (user_id, entitlement_id, is_active, product_id, expires_at, will_renew,
        is_sandbox, verified_at, source_requested_at)
     VALUES ($1, 'abu_3meer_pro', $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (user_id, entitlement_id) DO UPDATE SET
       is_active = EXCLUDED.is_active, product_id = EXCLUDED.product_id,
       expires_at = EXCLUDED.expires_at, will_renew = EXCLUDED.will_renew,
       is_sandbox = EXCLUDED.is_sandbox, verified_at = EXCLUDED.verified_at,
       source_requested_at = EXCLUDED.source_requested_at
     WHERE EXCLUDED.source_requested_at >= user_subscription_entitlements.source_requested_at`,
    [userId, verified.isActive, verified.productId, verified.expiresAt,
      verified.willRenew, verified.isSandbox, verified.verifiedAt,
      new Date(sourceRequestedAt).toISOString()],
  );
  return readSubscriptionStatus(userId, execute);
}

type RevenueCatRequest = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

async function fetchRevenueCatCustomerEnvironment(
  userId: string,
  sandbox: boolean,
  request: RevenueCatRequest,
): Promise<unknown> {
  const secret = config.revenueCat.secretApiKey;
  if (!secret.startsWith('sk_')) {
    throw new SubscriptionError('subscriptions_not_configured', 'Subscriptions are not configured on the server yet.');
  }
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secret}`,
    Accept: 'application/json',
  };
  // RevenueCat v1 separates sandbox subscribers behind this explicit header.
  // Never send it on the first/production lookup.
  if (sandbox) headers['X-Is-Sandbox'] = 'true';
  let response: Response;
  try {
    response = await request(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
      headers,
      signal: AbortSignal.timeout(8_000),
    });
  } catch {
    throw new SubscriptionError('subscription_verification_unavailable', 'Unable to verify your subscription. Please try again.');
  }
  if (!response.ok) {
    throw new SubscriptionError('subscription_verification_unavailable', 'Unable to verify your subscription. Please try again.');
  }
  try { return await response.json(); } catch {
    throw new SubscriptionError('subscription_response_invalid', 'Subscription verification is temporarily unavailable.');
  }
}

/**
 * Resolve the production customer first. A sandbox lookup is permitted only
 * for an explicitly allowed app account and only when production has no active
 * entitlement. Consequently, test data can never shadow a valid paid receipt.
 */
export async function fetchRevenueCatCustomer(
  userId: string,
  dependencies: {
    request?: RevenueCatRequest;
    now?: number;
  } = {},
): Promise<unknown> {
  const request = dependencies.request ?? fetch;
  const now = dependencies.now ?? Date.now();
  const production = await fetchRevenueCatCustomerEnvironment(userId, false, request);
  const productionStatus = subscriptionFromRevenueCat(production, now);
  if (productionStatus.isActive && !productionStatus.isSandbox) return production;
  if (!sandboxAccessAllowedForUser(userId)) return production;

  const sandbox = await fetchRevenueCatCustomerEnvironment(userId, true, request);
  const sandboxStatus = subscriptionFromRevenueCat(sandbox, now);
  return sandboxStatus.isActive && sandboxStatus.isSandbox ? sandbox : production;
}

export function isValidRevenueCatWebhookAuthorization(
  supplied: string | undefined,
  expected = config.revenueCat.webhookAuthorization,
): boolean {
  if (!expected || !supplied) return false;
  const expectedBytes = Buffer.from(expected);
  const suppliedBytes = Buffer.from(supplied);
  return expectedBytes.length === suppliedBytes.length
    && timingSafeEqual(expectedBytes, suppliedBytes);
}

// Events can be retried, reordered, or transferred. Treat them as a signal to
// re-fetch current state, never as authority for the event's entitlement list.
export async function processRevenueCatWebhook(
  event: JsonObject,
  dependencies: {
    execute?: SubscriptionQuery;
    sync?: typeof syncSubscriptionStatus;
  } = {},
): Promise<void> {
  const execute = dependencies.execute ?? query;
  const sync = dependencies.sync ?? syncSubscriptionStatus;
  const eventId = event.id as string;
  const existing = await execute('SELECT event_id FROM revenuecat_webhook_receipts WHERE event_id = $1', [eventId]);
  if (existing.rows.length > 0) return;
  const candidates = [event.app_user_id, event.original_app_user_id,
    ...(Array.isArray(event.aliases) ? event.aliases : []),
    ...(Array.isArray(event.transferred_from) ? event.transferred_from : []),
    ...(Array.isArray(event.transferred_to) ? event.transferred_to : [])];
  const userIds = [...new Set(candidates.filter((id): id is string =>
    typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id),
  ))];
  if (userIds.length > 100) throw new SubscriptionError('webhook_invalid', 'Too many customer identifiers.', 400);
  if (userIds.length > 0) {
    const users = await execute('SELECT id FROM users WHERE id = ANY($1::uuid[])', [userIds]);
    await Promise.all(users.rows.map(row => sync(row.id as string)));
  }
  await execute(
    `INSERT INTO revenuecat_webhook_receipts(event_id) VALUES ($1) ON CONFLICT DO NOTHING`,
    [eventId],
  );
}
