/**
 * Read-only support report. Can be streamed into an older running API image:
 * docker compose exec -T api node --input-type=module - --username dev < scripts/diagnose_subscriptions.mjs
 * Never fetches RevenueCat, changes entitlements, or prints credentials.
 */
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export function parseUsername(args) {
  if (args.length !== 2 || args[0] !== '--username') {
    throw new Error('usage');
  }
  const username = args[1].trim().replace(/^@/, '');
  if (!username || username.length > 50 || /[\s\p{C}]/u.test(username)) {
    throw new Error('usage');
  }
  return username.toLowerCase();
}

function dateValue(value) {
  if (value == null) return null;
  const timestamp = value instanceof Date ? value.getTime() : Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function legacyReason(source, now, allowSandbox) {
  const expires = dateValue(source.expiresAt);
  const verified = dateValue(source.verifiedAt);
  if (!source.productId) return 'no_entitlement';
  if (expires !== null && expires <= now) return 'expired';
  if (!source.isActive || expires === null) return 'inactive';
  if (verified === null || verified > now + 60_000) {
    return 'verification_required';
  }
  if (source.isSandbox
      && source.store !== 'app_store'
      && source.store !== 'play_store'
      && !allowSandbox) return 'sandbox_not_allowed';
  return 'active';
}

export async function diagnoseSubscription({ username, execute, enforce, policy, now = Date.now() }) {
  const report = {
    checkedAt: new Date(now).toISOString(),
    username,
    runtimeSupportsAccessReasons: policy.runtimeSupportsAccessReasons === true,
    serverKeyConfigured: policy.serverKeyConfigured === true,
    sandboxAllowed: policy.allowSandbox === true,
    readOnly: true,
  };
  // Restrict the report to one exact username, never dump the members/users
  // table. Parameter binding prevents a supplied username becoming SQL.
  const result = await execute(
    `SELECT u.id, s.user_id AS subscription_user_id, s.is_active, s.product_id, s.store_name,
            s.expires_at, s.will_renew, s.is_sandbox, s.verified_at
     FROM users u
     LEFT JOIN user_subscription_entitlements s
       ON s.user_id = u.id AND s.entitlement_id = 'abu_3meer_pro'
     WHERE u.normalized_username = $1
     LIMIT 1`,
    [username],
  );
  const row = result.rows[0];
  if (!row) return { ...report, accountFound: false };
  const expires = dateValue(row.expires_at);
  const verified = dateValue(row.verified_at);
  const source = {
    entitlementId: 'abu_3meer_pro',
    isActive: row.is_active === true,
    productId: typeof row.product_id === 'string' ? row.product_id : null,
    store: ['app_store', 'play_store', 'test_store'].includes(row.store_name)
      ? row.store_name : null,
    expiresAt: expires === null ? null : new Date(expires).toISOString(),
    willRenew: row.will_renew === true,
    isSandbox: row.is_sandbox === true,
    verifiedAt: verified === null ? null : new Date(verified).toISOString(),
  };
  const sandboxAllowed = policy.allowSandbox === true
    || (Array.isArray(policy.sandboxAllowedUserIds)
      && policy.sandboxAllowedUserIds.some(id => typeof id === 'string'
        && id.toLowerCase() === String(row.id).toLowerCase()));
  const status = enforce(source, now, sandboxAllowed);
  const knownReasons = new Set([
    'active', 'sandbox_not_allowed', 'no_entitlement', 'expired', 'verification_required', 'inactive',
  ]);
  const derivedReason = legacyReason(source, now, sandboxAllowed);
  return {
    ...report,
    sandboxAllowed,
    accountFound: true,
    snapshotPresent: row.subscription_user_id != null,
    entitlementId: source.entitlementId,
    productId: source.productId,
    store: source.store,
    sourceEntitlementActive: source.isActive,
    isSandbox: source.isSandbox,
    expiresAt: source.expiresAt,
    verifiedAt: source.verifiedAt,
    expired: expires !== null && expires <= now,
    verificationTimestampValid: verified !== null && verified <= now + 60_000,
    verificationAgeSeconds: verified === null
      ? null : Math.max(0, Math.floor((now - verified) / 1000)),
    accessActive: status.isActive === true,
    accessReason: knownReasons.has(status.accessReason) ? status.accessReason
      : status.isActive === true ? 'active'
      : derivedReason === 'active' ? 'runtime_denied' : derivedReason,
    reasonSource: knownReasons.has(status.accessReason) ? 'server-runtime' : 'derived-for-legacy-runtime',
  };
}

async function main() {
  let username;
  try {
    username = parseUsername(process.argv.slice(2));
  } catch {
    console.error('Usage: node --input-type=module - --username dev < scripts/diagnose_subscriptions.mjs');
    process.exitCode = 2;
    return;
  }
  let client;
  let database;
  try {
    // Read only the running container's configuration, not a host .env file.
    const { config } = await import(pathToFileURL(resolve('dist/config.js')).href);
    const service = await import(pathToFileURL(resolve('dist/services/subscriptionService.js')).href);
    database = await import(pathToFileURL(resolve('dist/db/pool.js')).href);
    client = await database.pool.connect();
    await client.query('BEGIN READ ONLY');
    const report = await diagnoseSubscription({
      username,
      execute: (sql, params) => client.query(sql, params),
      enforce: service.enforceSubscriptionAccess,
      policy: {
        serverKeyConfigured: config.revenueCat.secretApiKey.startsWith('sk_'),
        allowSandbox: config.revenueCat.allowSandbox,
        sandboxAllowedUserIds: config.revenueCat.sandboxAllowedUserIds,
        runtimeSupportsAccessReasons: typeof service.emptySubscriptionStatus().accessReason === 'string',
      },
    });
    console.log(JSON.stringify(report, null, 2));
  } catch (error) {
    const code = error && typeof error === 'object' ? error.code : null;
    console.error(code === '42P01'
      ? 'Subscription diagnostics unavailable: the subscription tables are missing. Check migrations 040/041.'
      : 'Subscription diagnostics unavailable: check the running API build and database connectivity privately.');
    // Never print the exception, connection string, full config, or a key.
    process.exitCode = 1;
  } finally {
    if (client) {
      try { await client.query('ROLLBACK'); } catch { /* read-only cleanup */ }
      client.release();
    }
    if (database) await database.closeDatabasePools();
  }
}

if (process.argv[1] === '-' || (process.argv[1]
  && resolve(process.argv[1]) === fileURLToPath(import.meta.url))) {
  await main();
}
