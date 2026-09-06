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
}

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
  };
}

/** Parse only the server-to-server customer response, never a client payload. */
export function subscriptionFromRevenueCat(
  value: unknown,
  now = Date.now(),
): SubscriptionStatus {
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
  status: SubscriptionStatus,
  now = Date.now(),
  allowSandbox = config.revenueCat.allowSandbox,
): SubscriptionStatus {
  const expires = validDate(status.expiresAt);
  const verified = validDate(status.verifiedAt);
  const active = status.isActive && expires !== null && expires > now
    && verified !== null && verified <= now + 60_000
    && verified > now - config.revenueCat.verificationMaxAgeSeconds * 1000
    && (!status.isSandbox || allowSandbox);
  return { ...status, isActive: active, willRenew: active && status.willRenew };
}

type SubscriptionQuery = (text: string, params?: unknown[]) => Promise<{rows: JsonObject[]}>;

export async function readSubscriptionStatus(
  userId: string,
  execute: SubscriptionQuery = query,
): Promise<SubscriptionStatus> {
  const result = await execute(
    `SELECT is_active, product_id, expires_at, will_renew, is_sandbox, verified_at
     FROM user_subscription_entitlements
     WHERE user_id = $1 AND entitlement_id = 'abu_3meer_pro'`,
    [userId],
  );
  const row = result.rows[0];
  if (!row) return emptySubscriptionStatus();
  return enforceSubscriptionAccess({
    entitlementId: 'abu_3meer_pro',
    isActive: row.is_active === true,
    productId: typeof row.product_id === 'string' ? row.product_id : null,
    expiresAt: row.expires_at ? new Date(row.expires_at as string).toISOString() : null,
    willRenew: row.will_renew === true,
    isSandbox: row.is_sandbox === true,
    verifiedAt: row.verified_at ? new Date(row.verified_at as string).toISOString() : null,
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

export async function fetchRevenueCatCustomer(userId: string): Promise<unknown> {
  const secret = config.revenueCat.secretApiKey;
  if (!secret.startsWith('sk_')) {
    throw new SubscriptionError('subscriptions_not_configured', 'Subscriptions are not configured on the server yet.');
  }
  let response: Response;
  try {
    response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`, {
      headers: { Authorization: `Bearer ${secret}`, Accept: 'application/json' },
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
