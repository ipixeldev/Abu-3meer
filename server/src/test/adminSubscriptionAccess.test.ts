import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import Fastify, { FastifyRequest } from 'fastify';
import type { AuthenticatedUser } from '../middleware/auth.js';
import { adminSubscriptionRoutes, changeSubscriptionAccess, subscriptionAccessBody } from '../routes/adminSubscriptionRoutes.js';
import { subscriptionRoutes } from '../routes/subscriptionRoutes.js';
import {
  activeMemberAccessSql,
  activeSubscriptionSql,
} from '../services/subscriptionAccess.js';
import { config } from '../config.js';
import { applySubscriptionAccessOverride, emptySubscriptionStatus, enforceSubscriptionAccess,
  readSubscriptionStatus, SubscriptionError, syncSubscriptionStatus } from '../services/subscriptionService.js';

const actorId = '11111111-1111-4111-8111-111111111111';
const targetId = '22222222-2222-4222-8222-222222222222';
const now = Date.now();
const future = new Date(now + 3_600_000).toISOString();
const past = new Date(now - 1_000).toISOString();
const storeStatus = () => enforceSubscriptionAccess({
  ...emptySubscriptionStatus(), isActive: true, productId: 'Ostoora3',
  expiresAt: future, verifiedAt: new Date(now).toISOString(), willRenew: true,
}, now, false);

test('admin grants access without inventing a store purchase or sandbox/production receipt', () => {
  const grant = applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'active', expiresAt: future }, now);
  assert.equal(grant.isActive, true);
  assert.equal(grant.accessReason, 'admin_granted');
  assert.equal(grant.accessSource, 'admin');
  assert.equal(grant.productId, null);
  assert.equal(grant.expiresAt, null);
  assert.equal(grant.verifiedAt, null);
  assert.equal(grant.environment, 'unknown');
  assert.equal(grant.willRenew, false);
  assert.equal(grant.subscriptionAccessExpiresAt, future);
  assert.equal(applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'active' }, now).isActive, true);
});

test('admin block takes precedence while store billing metadata remains unchanged', () => {
  const store = storeStatus();
  const blocked = applySubscriptionAccessOverride(store, { mode: 'inactive' }, now);
  assert.equal(blocked.isActive, false);
  assert.equal(blocked.accessReason, 'admin_revoked');
  assert.equal(blocked.accessSource, 'admin');
  assert.equal(blocked.productId, store.productId);
  assert.equal(blocked.expiresAt, store.expiresAt);
  assert.equal(blocked.willRenew, true, 'access block is not cancellation of billing');
  assert.equal(store.isActive, true, 'source status is not mutated');
});

test('expired or malformed grants fall back to store, and resetting mode does not fabricate access', () => {
  for (const expiresAt of [past, new Date(now).toISOString(), 'invalid']) {
    assert.equal(applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'active', expiresAt }, now).isActive, false);
    const paid = applySubscriptionAccessOverride(storeStatus(), { mode: 'active', expiresAt }, now);
    assert.equal(paid.isActive, true);
    assert.equal(paid.accessSource, 'store');
  }
  assert.equal(applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'store' }, now).accessSource, 'none');
  assert.equal(applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'spoof' }, now).isActive, false);
});

test('read status combines an override even when no RevenueCat snapshot exists', async () => {
  const result = await readSubscriptionStatus(targetId, async (sql, params) => {
    assert.match(sql, /LEFT JOIN user_subscription_access_overrides/);
    assert.deepEqual(params, [targetId]);
    return { rows: [{ access_override_mode: 'active', access_override_expires_at: future }] };
  });
  assert.equal(result.accessSource, 'admin');
  assert.equal(result.isActive, true);
});

test('store synchronization never writes an admin override or clears its effective block', async () => {
  let saved: Record<string, unknown> = {};
  const sqls: string[] = [];
  const result = await syncSubscriptionStatus(targetId, {
    fetchCustomer: async () => ({ subscriber: {
      entitlements: { abu_3meer_pro: { product_identifier: 'Ostoora3', expires_date: future } },
      subscriptions: { Ostoora3: { is_sandbox: false, store: 'app_store' } },
    } }),
    execute: async (sql, params = []) => {
      sqls.push(sql);
      if (sql.startsWith('INSERT')) {
        saved = { is_active: params[1], product_id: params[2], store_name: params[3],
          expires_at: params[4], will_renew: params[5],
          is_sandbox: params[6], verified_at: params[7] };
        return { rows: [] };
      }
      return { rows: [{ ...saved, access_override_mode: 'inactive' }] };
    },
  });
  assert.equal(saved.is_active, true);
  assert.equal(result.accessReason, 'admin_revoked');
  assert.equal(result.isActive, false);
  assert.doesNotMatch(sqls.filter(sql => sql.startsWith('INSERT')).join('\n'), /access_overrides|youtube|user_roles/);
});

function fakeTransaction({ mode, failAudit = false, missingTarget = false }: {
  mode?: 'active' | 'inactive'; failAudit?: boolean; missingTarget?: boolean;
} = {}) {
  const statements: { sql: string; params: unknown[] }[] = [];
  let override: Record<string, unknown> | null = mode ? { mode, expires_at: null, reason: 'Old reason' } : null;
  let released = false;
  return {
    statements,
    get released() { return released; },
    connect: async () => ({
      query: async (sql: string, params: unknown[] = []) => {
        statements.push({ sql, params });
        if (sql.startsWith('SELECT id FROM users')) return { rows: missingTarget ? [] : [{ id: targetId }] };
        if (sql.startsWith('SELECT mode')) return { rows: override ? [override] : [] };
        if (sql.startsWith('INSERT INTO user_subscription_access_overrides')) {
          override = { mode: params[1], expires_at: params[2], reason: params[3], updated_by: params[4] };
        }
        if (sql.startsWith('DELETE FROM user_subscription_access_overrides')) override = null;
        if (sql.startsWith('INSERT INTO admin_audit_logs') && failAudit) throw new Error('private db error');
        if (sql.startsWith('SELECT s.is_active')) return { rows: [{
          access_override_mode: override?.mode, access_override_expires_at: override?.expires_at,
        }] };
        return { rows: [] };
      },
      release: () => { released = true; },
    }),
  };
}

test('override transaction locks target and audits actor/target/before/after/reason atomically', async () => {
  const db = fakeTransaction({ mode: 'inactive' });
  const result = await changeSubscriptionAccess(actorId, targetId, { mode: 'active', reason: 'Support approved', expiresAt: future }, db.connect);
  assert.equal(result.accessReason, 'admin_granted');
  assert.equal(db.statements[0].sql, 'BEGIN');
  assert.match(db.statements[1].sql, /FOR UPDATE/);
  const audit = db.statements.find(row => row.sql.startsWith('INSERT INTO admin_audit_logs'))!;
  assert.deepEqual(audit.params.slice(0, 2), [actorId, targetId]);
  assert.equal(JSON.parse(audit.params[2] as string).mode, 'inactive');
  assert.deepEqual(JSON.parse(audit.params[3] as string), {
    mode: 'active', expires_at: future, reason: 'Support approved', billing_changed: false,
  });
  assert.equal(db.statements.at(-1)?.sql, 'COMMIT');
  assert.equal(db.released, true);
  const writes = db.statements
    .map(row => row.sql)
    .filter(sql => /^(INSERT|UPDATE|DELETE)/.test(sql));
  assert.doesNotMatch(
    writes.join('\n'),
    /UPDATE users|INSERT INTO user_subscription_entitlements|youtube|user_roles/,
  );
});

test('store mode deletes only override; audit failure rolls back; unknown targets cannot change access', async () => {
  const reset = fakeTransaction({ mode: 'active' });
  assert.equal((await changeSubscriptionAccess(actorId, targetId, { mode: 'store', reason: 'Use store status' }, reset.connect)).accessSource, 'none');
  assert.ok(reset.statements.some(row => row.sql.startsWith('DELETE FROM user_subscription_access_overrides')));
  for (const db of [fakeTransaction({ failAudit: true }), fakeTransaction({ missingTarget: true })]) {
    await assert.rejects(changeSubscriptionAccess(actorId, targetId, { mode: 'active', reason: 'Support approved' }, db.connect));
    assert.equal(db.statements.at(-1)?.sql, 'ROLLBACK');
    assert.equal(db.statements.some(row => row.sql === 'COMMIT'), false);
    assert.equal(db.released, true);
  }
  const expired = fakeTransaction();
  await assert.rejects(changeSubscriptionAccess(actorId, targetId, { mode: 'active', reason: 'Support approved', expiresAt: past }, expired.connect), /future/);
});

test('validation rejects spoofed identity/billing fields, bad modes, reasons and non-grant expiry', () => {
  for (const body of [
    { mode: 'paid', reason: 'Support' }, { mode: 'active', reason: 'x' },
    { mode: 'active', reason: 'x'.repeat(501) }, { mode: 'active', reason: 'line\nline' },
    { mode: 'inactive', reason: 'Support', expiresAt: future },
    { mode: 'store', reason: 'Support', expiresAt: future },
    { mode: 'active', reason: 'Support', userId: actorId },
    { mode: 'active', reason: 'Support', isSandbox: false },
    { mode: 'active', reason: 'Support', productId: 'Ostoora3' },
  ]) assert.equal(subscriptionAccessBody.safeParse(body).success, false);
  assert.equal(subscriptionAccessBody.safeParse({ mode: 'active', reason: '  هدية عضوية  ', expiresAt: null }).success, true);
});

test('admin endpoint rejects unauthenticated and non-admin actors, accepts admin and super-admin', async t => {
  const unauthenticated = Fastify();
  await unauthenticated.register(adminSubscriptionRoutes);
  t.after(() => unauthenticated.close());
  assert.equal((await unauthenticated.inject({ method: 'PUT', url: `/admin/users/${targetId}/subscription-access`, payload: { mode: 'active', reason: 'Support approved' } })).statusCode, 401);
  for (const role of ['fan', 'member', 'moderator', 'admin', 'super_admin']) {
    const app = Fastify();
    let calls = 0;
    await app.register(adminSubscriptionRoutes, {
      authorize: async (request: FastifyRequest) => { request.user = {
        id: actorId, roles: [role], isAdmin: role === 'admin', isSuperAdmin: role === 'super_admin',
      } as AuthenticatedUser; },
      change: async (actor: string, target: string, body: { mode: string }) => {
        calls++;
        assert.equal(actor, actorId); assert.equal(target, targetId); assert.equal(body.mode, 'active');
        return applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode: 'active' });
      },
    });
    t.after(() => app.close());
    const result = await app.inject({ method: 'PUT', url: `/admin/users/${targetId}/subscription-access`, payload: { mode: 'active', reason: 'Support approved' } });
    const allowed = role === 'admin' || role === 'super_admin';
    assert.equal(result.statusCode, allowed ? 200 : 403);
    assert.equal(calls, allowed ? 1 : 0);
    if (allowed) {
      assert.equal(result.json().data.accessReason, 'admin_granted');
      assert.equal(result.headers['cache-control'], 'private, no-store');
      assert.equal((await app.inject({ method: 'PUT', url: '/admin/users/not-a-uuid/subscription-access', payload: { mode: 'active', reason: 'Support approved' } })).statusCode, 400);
    }
  }
});

test('authenticated sync preserves only effective access during RC failure without weakening webhook retries', async t => {
  for (const mode of ['active', 'inactive', 'store'] as const) {
    const app = Fastify();
    await app.register(subscriptionRoutes, {
      authenticate: async (request: FastifyRequest) => { request.user = { id: targetId } as AuthenticatedUser; },
      sync: async () => { throw new SubscriptionError('subscriptions_not_configured', 'Not configured'); },
      read: async () => applySubscriptionAccessOverride(emptySubscriptionStatus(), { mode }),
      authorizeWebhook: () => true,
      processWebhook: async () => { throw new SubscriptionError('subscription_verification_unavailable', 'Unavailable'); },
    });
    t.after(() => app.close());
    const result = await app.inject({ method: 'POST', url: '/subscriptions/sync', payload: {} });
    assert.equal(result.statusCode, mode === 'active' ? 200 : 503);
    if (mode === 'active') assert.equal(result.json().data.hasMemberAccess, true);
    assert.equal((await app.inject({ method: 'POST', url: '/subscriptions/webhook', payload: { event: { id: 'event-1', type: 'RENEWAL' } } })).statusCode, 503);
  }
});

test('SQL and migration keep overrides separate, expire grants, and never grant moderators management', async () => {
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  config.revenueCat.allowSandbox = false;
  config.revenueCat.sandboxAllowedUserIds = [targetId, "bad') OR TRUE --"];
  const sql = activeSubscriptionSql('u.id');
  try {
    assert.match(sql, /COALESCE\(/);
    assert.match(sql, /mode = 'inactive' THEN FALSE/);
    assert.match(sql, /expires_at IS NULL OR access_override.expires_at > clock_timestamp\(\)/);
    assert.match(sql, /ELSE NULL/);
    assert.match(sql, /subscription_access.is_active = TRUE/);
    assert.match(sql, /subscription_access.product_id IS NOT NULL/);
    assert.match(sql, new RegExp(targetId));
    assert.doesNotMatch(sql, /bad|OR TRUE --/);
    const memberSql = activeMemberAccessSql('u.id');
    assert.match(memberSql, /mode = 'inactive' THEN FALSE/);
    assert.match(memberSql, /youtube_account_links/);
    assert.match(memberSql, /approved_snapshot_import_id = snapshot_state\.active_import_id/);
    assert.match(memberSql, /user_subscription_entitlements/);
  } finally {
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
  const migration = await readFile('migrations/042_admin_subscription_access.sql', 'utf8');
  assert.match(migration, /'admin', 'subscriptions.manage'/);
  assert.match(migration, /'super_admin', 'subscriptions.manage'/);
  assert.match(migration, /role_id NOT IN \('admin', 'super_admin'\)/);
});

test('private profile and Admin Studio responses expose one fresh effective access decision', async () => {
  const profile = await readFile('src/routes/profileRoutes.ts', 'utf8');
  assert.doesNotMatch(profile, /hasMemberAccess: user\.hasMemberAccess/);
  assert.match(profile, /isProSubscriber: subscriptionAccess\.isActive/);
  assert.match(profile, /isYouTubeMember: subscriptionAccess\.youtubeMembershipActive/);
  assert.match(profile, /hasMemberAccess: subscriptionAccess\.hasMemberAccess/);
  assert.match(profile, /memberAccessSource: subscriptionAccess\.memberAccessSource/);
  assert.match(profile, /youtubeMembershipRecheckRequired:/);
  assert.match(profile, /subscriptionAccessReason: subscriptionAccess\.accessReason/);
  assert.match(profile, /subscriptionAccessSource: subscriptionAccess\.accessSource/);

  const admin = await readFile('src/routes/adminRoutes.ts', 'utf8');
  assert.match(admin, /accessReason: subscriptionAccess\.accessReason/);
  assert.match(admin, /accessSource: subscriptionAccess\.accessSource/);
});
