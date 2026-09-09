import test from 'node:test';
import assert from 'node:assert/strict';
import Fastify, { FastifyRequest } from 'fastify';
import {
  emptySubscriptionStatus,
  enforceSubscriptionAccess,
  fetchRevenueCatCustomer,
  applySubscriptionAccessOverride,
  applyYouTubeMembershipAccess,
  isValidRevenueCatWebhookAuthorization,
  processRevenueCatWebhook,
  readSubscriptionStatus,
  sandboxAccessAllowedForUser,
  SubscriptionError,
  subscriptionFromRevenueCat,
  syncSubscriptionStatus,
} from '../services/subscriptionService.js';
import { subscriptionRoutes } from '../routes/subscriptionRoutes.js';
import { resolveChallengeMembership } from '../services/challengeMembershipService.js';
import type { AuthenticatedUser } from '../middleware/auth.js';
import { config } from '../config.js';

const now = Date.parse('2026-09-05T12:00:00Z');
const ownerId = 'c6e6752e-1ef9-4a7d-a6f3-a9521dadfb88';
const otherId = 'c6e6752e-1ef9-4a7d-a6f3-a9521dadfb99';
const response = (overrides: Record<string, unknown> = {}) => ({
  subscriber: {
    entitlements: { abu_3meer_pro: {
      expires_date: '2026-10-05T12:00:00Z',
      product_identifier: 'ostoora3_monthly',
    } },
    subscriptions: { ostoora3_monthly: {
      is_sandbox: false, store: 'app_store', refunded_at: null,
      unsubscribe_detected_at: null, ...overrides,
    } },
  },
});

test('verified recurring entitlement grants access; cancellation retains paid term and refund revokes', () => {
  const active = subscriptionFromRevenueCat(response(), now);
  assert.equal(enforceSubscriptionAccess(active, now).isActive, true);
  assert.equal(active.willRenew, true);
  const cancelled = subscriptionFromRevenueCat(response({ unsubscribe_detected_at: '2026-09-04T00:00:00Z' }), now);
  assert.equal(cancelled.isActive, true);
  assert.equal(cancelled.willRenew, false);
  assert.equal(subscriptionFromRevenueCat(response({ refunded_at: '2026-09-04T00:00:00Z' }), now).isActive, false);
});

test('an unexpired verified store entitlement remains active beyond 24 hours until its actual expiry', () => {
  const active = subscriptionFromRevenueCat(response(), now);
  const cached = enforceSubscriptionAccess(active, now + 48 * 60 * 60_000);
  assert.equal(cached.isActive, true);
  assert.equal(cached.accessReason, 'active');
  const blocked = applySubscriptionAccessOverride(cached, { mode: 'inactive' }, now);
  assert.equal(blocked.isActive, false);
  assert.equal(blocked.accessReason, 'admin_revoked');
  assert.equal(enforceSubscriptionAccess({ ...active, expiresAt: new Date(now).toISOString() }, now).isActive, false);
  assert.equal(enforceSubscriptionAccess({ ...active, expiresAt: null }, now).isActive, false);
});

test('Apple and Google sandbox purchases grant test-track access while Test Store needs opt-in', () => {
  const sandbox = subscriptionFromRevenueCat(response({ is_sandbox: true }), now);
  assert.equal(enforceSubscriptionAccess(sandbox, now, false).isActive, true);
  assert.equal(enforceSubscriptionAccess(sandbox, now, true).isActive, true);
  const playSandbox = subscriptionFromRevenueCat(response({ is_sandbox: true, store: 'play_store' }), now);
  assert.equal(enforceSubscriptionAccess(playSandbox, now, false).isActive, true);
  const testStore = subscriptionFromRevenueCat(response({ store: 'test_store' }), now);
  assert.equal(enforceSubscriptionAccess(testStore, now, false).isActive, false);
  assert.equal(enforceSubscriptionAccess(testStore, now, true).isActive, true);
  assert.equal(subscriptionFromRevenueCat(response({ is_sandbox: undefined }), now).isActive, false);
});

test('verified YouTube membership grants access without pretending to be a renewable subscription', () => {
  const snapshotExpiry = new Date(now + 7 * 24 * 60 * 60_000).toISOString();
  const deniedSandbox = enforceSubscriptionAccess(
    subscriptionFromRevenueCat(response({ store: 'test_store' }), now),
    now,
    false,
  );
  const effective = applyYouTubeMembershipAccess(deniedSandbox, {
    isActive: true,
    verifiedAt: new Date(now).toISOString(),
    expiresAt: snapshotExpiry,
  }, now);
  assert.equal(effective.isActive, false, 'YouTube must not fabricate a store subscription');
  assert.equal(effective.accessReason, 'sandbox_not_allowed');
  assert.equal(effective.accessSource, 'store');
  assert.equal(effective.willRenew, false);
  assert.equal(effective.hasMemberAccess, true);
  assert.equal(effective.memberAccessSource, 'youtube');
  assert.equal(effective.memberAccessReason, 'youtube_verified');
  assert.equal(effective.memberAccessExpiresAt, snapshotExpiry);
  assert.equal(effective.youtubeMembershipActive, true);
  assert.equal(effective.youtubeMembershipRecheckRequired, false);
});

test('expired YouTube verification requires recheck and cannot outlive its snapshot', () => {
  const expiredAt = new Date(now - 1).toISOString();
  const effective = applyYouTubeMembershipAccess(emptySubscriptionStatus(), {
    isActive: true,
    verifiedAt: new Date(now - 60_000).toISOString(),
    expiresAt: expiredAt,
    recheckRequired: true,
  }, now);
  assert.equal(effective.hasMemberAccess, false);
  assert.equal(effective.memberAccessSource, 'none');
  assert.equal(effective.youtubeMembershipActive, false);
  assert.equal(effective.youtubeMembershipExpiresAt, expiredAt);
  assert.equal(effective.youtubeMembershipRecheckRequired, true);
  assert.equal(effective.willRenew, false);
});

test('an active store or admin decision remains distinct when YouTube is also current', () => {
  const snapshotExpiry = new Date(now + 7 * 24 * 60 * 60_000).toISOString();
  const youtube = {
    isActive: true,
    verifiedAt: new Date(now).toISOString(),
    expiresAt: snapshotExpiry,
  };
  const paid = applyYouTubeMembershipAccess(
    enforceSubscriptionAccess(subscriptionFromRevenueCat(response(), now), now),
    youtube,
    now,
  );
  assert.equal(paid.memberAccessSource, 'store');
  assert.equal(paid.memberAccessReason, 'active');
  assert.equal(paid.youtubeMembershipActive, true);

  const grantExpiry = new Date(now + 60 * 60_000).toISOString();
  const granted = applyYouTubeMembershipAccess(
    { ...emptySubscriptionStatus(), isActive: true, accessReason: 'admin_granted',
      accessSource: 'admin', subscriptionAccessMode: 'active',
      subscriptionAccessExpiresAt: grantExpiry },
    youtube,
    now,
  );
  assert.equal(granted.memberAccessSource, 'admin');
  assert.equal(granted.memberAccessReason, 'admin_granted');
  assert.equal(granted.memberAccessExpiresAt, grantExpiry);

  const blocked = applyYouTubeMembershipAccess(
    { ...emptySubscriptionStatus(), accessReason: 'admin_revoked',
      accessSource: 'admin', subscriptionAccessMode: 'inactive' },
    youtube,
    now,
  );
  assert.equal(blocked.youtubeMembershipActive, true);
  assert.equal(blocked.hasMemberAccess, false);
  assert.equal(blocked.memberAccessSource, 'admin');
  assert.equal(blocked.memberAccessReason, 'admin_revoked');
});

test('access reasons distinguish production policy from expiry and verification failure', () => {
  const active = subscriptionFromRevenueCat(response(), now);
  const production = enforceSubscriptionAccess(active, now, false);
  assert.equal(production.accessReason, 'active');
  assert.equal(production.environment, 'production');

  const sandbox = subscriptionFromRevenueCat(response({ is_sandbox: true }), now);
  const accepted = enforceSubscriptionAccess(sandbox, now, false);
  assert.equal(accepted.accessReason, 'active');
  assert.equal(accepted.environment, 'sandbox');
  assert.equal(accepted.isActive, true);
  assert.equal(accepted.willRenew, true);
  assert.equal(sandbox.isActive, true, 'policy must not mutate the upstream subscription');
  assert.equal(enforceSubscriptionAccess(sandbox, now, true).accessReason, 'active');

  const testStore = enforceSubscriptionAccess(
    subscriptionFromRevenueCat(response({ store: 'test_store' }), now), now, false,
  );
  assert.equal(testStore.accessReason, 'sandbox_not_allowed');
  assert.equal(testStore.environment, 'sandbox');

  assert.equal(enforceSubscriptionAccess({ ...active, expiresAt: new Date(now).toISOString() }, now).accessReason, 'expired');
  assert.equal(enforceSubscriptionAccess({ ...active, verifiedAt: null }, now).accessReason, 'verification_required');
  assert.equal(enforceSubscriptionAccess(active, now + 48 * 60 * 60_000).accessReason, 'active');
  assert.equal(enforceSubscriptionAccess({ ...active, verifiedAt: new Date(now + 60_001).toISOString() }, now).accessReason, 'verification_required');

  const refunded = enforceSubscriptionAccess(
    subscriptionFromRevenueCat(response({ refunded_at: '2026-09-04T00:00:00Z' }), now), now,
  );
  assert.equal(refunded.accessReason, 'inactive');
  assert.equal(refunded.environment, 'unknown');
  const unknown = enforceSubscriptionAccess(subscriptionFromRevenueCat(response({ is_sandbox: undefined }), now), now);
  assert.equal(unknown.accessReason, 'inactive');
  assert.equal(unknown.environment, 'unknown');
  const empty = enforceSubscriptionAccess(emptySubscriptionStatus(), now);
  assert.equal(empty.accessReason, 'no_entitlement');
  assert.equal(empty.environment, 'unknown');
});

test('a cached verified sandbox row is gated by the current policy on every read', async () => {
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const currentTime = Date.now();
  const row = {
    is_active: true, product_id: 'Ostoora3_Pro_Max', will_renew: true, is_sandbox: true,
    expires_at: new Date(currentTime + 60 * 60_000), verified_at: new Date(currentTime),
  };
  const execute = async () => ({ rows: [row] });
  try {
    config.revenueCat.sandboxAllowedUserIds = [];
    config.revenueCat.allowSandbox = true;
    assert.equal((await readSubscriptionStatus(ownerId, execute)).accessReason, 'active');
    config.revenueCat.allowSandbox = false;
    const denied = await readSubscriptionStatus(ownerId, execute);
    assert.equal(denied.accessReason, 'sandbox_not_allowed');
    assert.equal(denied.environment, 'sandbox');
    assert.equal(denied.isActive, false);
    assert.equal(row.is_active, true, 'cached source is not rewritten as a policy denial');
    const missing = await readSubscriptionStatus(ownerId, async () => ({ rows: [] }));
    assert.equal(missing.accessReason, 'no_entitlement');
  } finally {
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('status read reports current manual YouTube access separately from a denied test receipt', async () => {
  const currentTime = Date.now();
  const snapshotExpiry = new Date(currentTime + 7 * 24 * 60 * 60_000);
  const status = await readSubscriptionStatus(ownerId, async sql => {
    assert.match(
      sql,
      /current_check_claim\.approved_snapshot_import_id = snapshot_state\.active_import_id/,
    );
    assert.match(sql, /FROM membership_history history/);
    return { rows: [{
    is_active: true,
    product_id: 'Ostoora3',
    expires_at: new Date(currentTime + 60 * 60_000),
    will_renew: true,
    is_sandbox: true,
    store_name: 'test_store',
    verified_at: new Date(currentTime),
    youtube_membership_active: true,
    youtube_membership_verified_at: new Date(currentTime),
    youtube_membership_expires_at: snapshotExpiry,
    }] };
  });
  assert.equal(status.isActive, false);
  assert.equal(status.accessReason, 'sandbox_not_allowed');
  assert.equal(status.hasMemberAccess, true);
  assert.equal(status.memberAccessSource, 'youtube');
  assert.equal(status.memberAccessReason, 'youtube_verified');
  assert.equal(status.memberAccessExpiresAt, snapshotExpiry.toISOString());
  assert.equal(status.youtubeMembershipActive, true);
  assert.equal(status.youtubeMembershipRecheckRequired, false);
  assert.equal(status.willRenew, false);
});

test('status read keeps recheck visible for expired or replaced membership, but not a current nonmember check', async () => {
  const currentTime = Date.now();
  const expiredAt = new Date(currentTime - 1_000);
  const status = await readSubscriptionStatus(ownerId, async () => ({ rows: [{
    youtube_membership_active: false,
    youtube_membership_verified_at: new Date(currentTime - 60_000),
    youtube_membership_expires_at: expiredAt,
    youtube_membership_had_active_history: true,
    youtube_membership_has_usable_snapshot: false,
    youtube_membership_checked_current_snapshot: true,
  }] }));
  assert.equal(status.hasMemberAccess, false);
  assert.equal(status.memberAccessSource, 'none');
  assert.equal(status.memberAccessReason, 'no_entitlement');
  assert.equal(status.youtubeMembershipActive, false);
  assert.equal(status.youtubeMembershipExpiresAt, expiredAt.toISOString());
  assert.equal(status.youtubeMembershipRecheckRequired, true);

  const replaced = await readSubscriptionStatus(ownerId, async () => ({ rows: [{
    youtube_membership_active: false,
    youtube_membership_had_active_history: true,
    youtube_membership_has_usable_snapshot: true,
    youtube_membership_checked_current_snapshot: false,
  }] }));
  assert.equal(replaced.youtubeMembershipRecheckRequired, true);

  const checkedNonmember = await readSubscriptionStatus(ownerId, async () => ({ rows: [{
    youtube_membership_active: false,
    youtube_membership_had_active_history: true,
    youtube_membership_has_usable_snapshot: true,
    youtube_membership_checked_current_snapshot: true,
  }] }));
  assert.equal(checkedNonmember.youtubeMembershipRecheckRequired, false);
  assert.equal(checkedNonmember.youtubeMembershipExpiresAt, null);
});

test('allowlisted reviewers can use Test Store receipts while other users cannot', async () => {
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const currentTime = Date.now();
  const row = {
    is_active: true, product_id: 'Ostoora3_Pro_Max', will_renew: true,
    is_sandbox: true, store_name: 'test_store', expires_at: new Date(currentTime + 60 * 60_000),
    verified_at: new Date(currentTime),
  };
  try {
    config.revenueCat.allowSandbox = false;
    config.revenueCat.sandboxAllowedUserIds = [ownerId];
    assert.equal(sandboxAccessAllowedForUser(ownerId), true);
    assert.equal(sandboxAccessAllowedForUser(ownerId.toUpperCase()), true);
    assert.equal(sandboxAccessAllowedForUser(otherId), false);
    const allowed = await readSubscriptionStatus(ownerId, async sql => {
      assert.match(sql, /youtube_membership_active/);
      assert.match(sql, /snapshot_import\.expires_at > CURRENT_TIMESTAMP/);
      return { rows: [row] };
    });
    assert.equal(allowed.accessReason, 'active');
    assert.equal(allowed.hasMemberAccess, true);
    assert.equal(allowed.memberAccessSource, 'store');
    assert.equal(allowed.environment, 'sandbox');
    assert.equal((await readSubscriptionStatus(otherId, async () => ({ rows: [row] }))).accessReason, 'sandbox_not_allowed');
  } finally {
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('RevenueCat lookup is production-first and never lets sandbox shadow active production', async () => {
  const previousSecret = config.revenueCat.secretApiKey;
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const calls: Array<{ url: string; headers: Record<string, string> }> = [];
  try {
    config.revenueCat.secretApiKey = 'sk_server_test_only';
    config.revenueCat.allowSandbox = false;
    config.revenueCat.sandboxAllowedUserIds = [ownerId];
    const production = response();
    const selected = await fetchRevenueCatCustomer(ownerId, {
      now,
      request: async (input, init) => {
        const headers = init?.headers as Record<string, string>;
        calls.push({ url: input.toString(), headers });
        return new Response(JSON.stringify(production), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      },
    });
    assert.deepEqual(selected, production);
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, new RegExp(`/v1/subscribers/${ownerId}$`));
    assert.equal(calls[0].headers.Authorization, 'Bearer sk_server_test_only');
    assert.equal(calls[0].headers['X-Is-Sandbox'], undefined);
  } finally {
    config.revenueCat.secretApiKey = previousSecret;
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('every account falls back to sandbox lookup when production has no active entitlement', async () => {
  const previousSecret = config.revenueCat.secretApiKey;
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const production = { subscriber: { entitlements: {} } };
  const sandbox = response({ is_sandbox: true });
  try {
    config.revenueCat.secretApiKey = 'sk_server_test_only';
    config.revenueCat.allowSandbox = false;
    config.revenueCat.sandboxAllowedUserIds = [ownerId];
    const headers: Record<string, string>[] = [];
    const selected = await fetchRevenueCatCustomer(ownerId, {
      now,
      request: async (_input, init) => {
        headers.push(init?.headers as Record<string, string>);
        const body = headers.length === 1 ? production : sandbox;
        return new Response(JSON.stringify(body), { status: 200 });
      },
    });
    assert.equal(headers.length, 2);
    assert.equal(headers[0]['X-Is-Sandbox'], undefined);
    assert.equal(headers[1]['X-Is-Sandbox'], 'true');
    const parsed = subscriptionFromRevenueCat(selected, now);
    assert.equal(parsed.isActive, true);
    assert.equal(parsed.isSandbox, true);

    config.revenueCat.sandboxAllowedUserIds = [];
    let unlistedCalls = 0;
    const unlisted = await fetchRevenueCatCustomer(otherId, {
      now,
      request: async () => {
        unlistedCalls++;
        return new Response(JSON.stringify(unlistedCalls === 1 ? production : sandbox), { status: 200 });
      },
    });
    assert.deepEqual(unlisted, sandbox);
    assert.equal(unlistedCalls, 2);
  } finally {
    config.revenueCat.secretApiKey = previousSecret;
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('sandbox fallback sync persists the verified test receipt, while optional lookup failure preserves production', async () => {
  const previousSecret = config.revenueCat.secretApiKey;
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const currentTime = Date.now();
  const production = { subscriber: { entitlements: {} } };
  const sandbox = response({ is_sandbox: true });
  sandbox.subscriber.entitlements.abu_3meer_pro.expires_date =
    new Date(currentTime + 60 * 60_000).toISOString();
  try {
    config.revenueCat.secretApiKey = 'sk_server_test_only';
    config.revenueCat.allowSandbox = false;
    config.revenueCat.sandboxAllowedUserIds = [ownerId];
    let requestCount = 0;
    let saved: Record<string, unknown> | undefined;
    const status = await syncSubscriptionStatus(ownerId, {
      fetchCustomer: id => fetchRevenueCatCustomer(id, {
        now: currentTime,
        request: async () => new Response(JSON.stringify(
          ++requestCount === 1 ? production : sandbox,
        ), { status: 200 }),
      }),
      execute: async (sql, parameters = []) => {
        if (sql.startsWith('INSERT')) {
          saved = {
            is_active: parameters[1], product_id: parameters[2],
            store_name: parameters[3], expires_at: parameters[4],
            will_renew: parameters[5], is_sandbox: parameters[6],
            verified_at: parameters[7],
          };
          return { rows: [] };
        }
        return { rows: saved ? [saved] : [] };
      },
    });
    assert.equal(requestCount, 2);
    assert.equal(saved?.is_active, true);
    assert.equal(saved?.is_sandbox, true);
    assert.equal(status.isActive, true);
    assert.equal(status.environment, 'sandbox');

    let failedRequestCount = 0;
    const selected = await fetchRevenueCatCustomer(ownerId, {
      now: currentTime,
      request: async () => {
        failedRequestCount++;
        if (failedRequestCount === 1) {
          return new Response(JSON.stringify(production), { status: 200 });
        }
        throw new Error('sandbox endpoint unavailable');
      },
    });
    assert.deepEqual(selected, production);
    assert.equal(failedRequestCount, 2);
  } finally {
    config.revenueCat.secretApiKey = previousSecret;
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('backend RevenueCat lookup rejects public SDK keys before any network request', async () => {
  const previousSecret = config.revenueCat.secretApiKey;
  let calls = 0;
  try {
    config.revenueCat.secretApiKey = 'appl_public_keys_belong_in_the_app';
    await assert.rejects(fetchRevenueCatCustomer(ownerId, {
      now,
      request: async () => {
        calls++;
        return new Response('{}', { status: 200 });
      },
    }), (error: unknown) => error instanceof SubscriptionError
      && error.code === 'subscriptions_not_configured');
    assert.equal(calls, 0);
  } finally {
    config.revenueCat.secretApiKey = previousSecret;
  }
});

test('legacy inactive cached records remain inactive and cannot be relabeled as paid production', async () => {
  const currentTime = Date.now();
  const status = await readSubscriptionStatus(ownerId, async () => ({ rows: [{
    is_active: false, product_id: 'Ostoora3_Pro_Max', is_sandbox: true,
    expires_at: new Date(currentTime + 60 * 60_000), verified_at: new Date(currentTime),
  }] }));
  assert.equal(status.isActive, false);
  assert.equal(status.accessReason, 'inactive');
  assert.equal(status.environment, 'unknown');
});

test('missing entitlement, malformed response, and unknown subscription cannot grant paid access', () => {
  assert.equal(subscriptionFromRevenueCat({ subscriber: { entitlements: {} } }, now).isActive, false);
  assert.throws(() => subscriptionFromRevenueCat({ isActive: true }, now), SubscriptionError);
  const customer = response();
  customer.subscriber.entitlements.abu_3meer_pro.product_identifier = 'unknown';
  assert.equal(subscriptionFromRevenueCat(customer, now).isActive, false);
});

test('subscription sync persists only paid state, preserving the independent CSV link and roles', async () => {
  const statements: string[] = [];
  let saved: Record<string, unknown> | undefined;
  const result = await syncSubscriptionStatus(ownerId, {
    fetchCustomer: async requested => {
      assert.equal(requested, ownerId);
      return { subscriber: { entitlements: {} } };
    },
    execute: async (text, parameters = []) => {
      statements.push(text);
      if (text.startsWith('INSERT')) {
        saved = { is_active: parameters[1], product_id: parameters[2], store_name: parameters[3],
          expires_at: parameters[4], will_renew: parameters[5],
          is_sandbox: parameters[6], verified_at: parameters[7] };
        return { rows: [] };
      }
      return { rows: saved ? [saved] : [] };
    },
  });
  assert.equal(result.isActive, false);
  assert.equal(statements.length, 2);
  for (const statement of statements.filter(sql => /^(INSERT|UPDATE|DELETE)/.test(sql))) {
    assert.doesNotMatch(statement, /youtube|user_roles|UPDATE users/);
  }
});

test('sync preserves a Test Store entitlement upstream while denying unapproved access', async () => {
  const previousPolicy = config.revenueCat.allowSandbox;
  const previousAllowedIds = config.revenueCat.sandboxAllowedUserIds;
  const customer = response({ store: 'test_store' });
  customer.subscriber.entitlements.abu_3meer_pro.expires_date = new Date(Date.now() + 60 * 60_000).toISOString();
  let saved: Record<string, unknown> | undefined;
  try {
    config.revenueCat.allowSandbox = false;
    config.revenueCat.sandboxAllowedUserIds = [];
    const status = await syncSubscriptionStatus(ownerId, {
      fetchCustomer: async () => customer,
      execute: async (text, parameters = []) => {
        if (text.startsWith('INSERT')) {
          saved = { is_active: parameters[1], product_id: parameters[2], store_name: parameters[3],
            expires_at: parameters[4], will_renew: parameters[5],
            is_sandbox: parameters[6], verified_at: parameters[7] };
          return { rows: [] };
        }
        return { rows: saved ? [saved] : [] };
      },
    });
    assert.equal(saved?.is_active, true);
    assert.equal(saved?.is_sandbox, true);
    assert.equal(status.isActive, false);
    assert.equal(status.accessReason, 'sandbox_not_allowed');
    assert.equal(status.environment, 'sandbox');
  } finally {
    config.revenueCat.allowSandbox = previousPolicy;
    config.revenueCat.sandboxAllowedUserIds = previousAllowedIds;
  }
});

test('a paid member with no YouTube channel receives member content; valid CSV survives paid expiry', async () => {
  const paid = await resolveChallengeMembership(ownerId, {
    queryMembership: async () => ({ rows: [{ linked: false, current_member: false, has_member_access: true }] }),
    refreshMembership: async () => { throw new Error('Must not require CSV for a subscriber'); },
  });
  assert.equal(paid, true);
  const csv = await resolveChallengeMembership(ownerId, {
    queryMembership: async () => ({ rows: [{ linked: true, current_member: true, has_member_access: true }] }),
    refreshMembership: async () => { throw new Error('Current CSV needs no refresh'); },
  });
  assert.equal(csv, true);
});

test('sync/status endpoints require authentication and reject spoofed customer-info fields', async t => {
  const unauthenticated = Fastify();
  await unauthenticated.register(subscriptionRoutes);
  t.after(() => unauthenticated.close());
  assert.equal((await unauthenticated.inject({ method: 'POST', url: '/subscriptions/sync', payload: {} })).statusCode, 401);
  assert.equal((await unauthenticated.inject({ method: 'GET', url: '/subscriptions/status' })).statusCode, 401);

  const calledIds: string[] = [];
  const app = Fastify();
  await app.register(subscriptionRoutes, {
    authenticate: async (request: FastifyRequest) => { request.user = { id: ownerId } as AuthenticatedUser; },
    sync: async (userId: string) => { calledIds.push(userId); return emptySubscriptionStatus(); },
  });
  t.after(() => app.close());
  const spoof = await app.inject({ method: 'POST', url: '/subscriptions/sync', payload: { appUserId: otherId, isActive: true } });
  assert.equal(spoof.statusCode, 400);
  assert.deepEqual(calledIds, []);
  const actual = await app.inject({ method: 'POST', url: '/subscriptions/sync', payload: {} });
  assert.equal(actual.statusCode, 200);
  assert.deepEqual(calledIds, [ownerId]);
  assert.equal(actual.json().data.entitlementId, 'abu_3meer_pro');
  assert.equal(actual.json().data.accessReason, 'no_entitlement');
  assert.equal(actual.json().data.environment, 'unknown');
  assert.equal(actual.headers['cache-control'], 'private, no-store');
});

test('sync outage preserves current YouTube or cached store access only while it remains valid', async t => {
  const currentTime = Date.now();
  const storeCustomer = response();
  storeCustomer.subscriber.entitlements.abu_3meer_pro.expires_date =
    new Date(currentTime + 60 * 60_000).toISOString();
  const cases = [
    applyYouTubeMembershipAccess(emptySubscriptionStatus(), {
      isActive: true,
      verifiedAt: new Date(currentTime).toISOString(),
      expiresAt: new Date(currentTime + 60 * 60_000).toISOString(),
    }, currentTime),
    enforceSubscriptionAccess(
      subscriptionFromRevenueCat(storeCustomer, currentTime),
      currentTime,
    ),
    emptySubscriptionStatus(),
  ];

  for (const effective of cases) {
    const app = Fastify();
    await app.register(subscriptionRoutes, {
      authenticate: async (request: FastifyRequest) => {
        request.user = { id: ownerId } as AuthenticatedUser;
      },
      sync: async () => {
        throw new SubscriptionError(
          'subscription_verification_unavailable',
          'Unable to verify your subscription.',
        );
      },
      read: async () => effective,
    });
    t.after(() => app.close());
    const result = await app.inject({
      method: 'POST',
      url: '/subscriptions/sync',
      payload: {},
    });
    assert.equal(result.statusCode, effective.hasMemberAccess ? 200 : 503);
    if (effective.hasMemberAccess) {
      assert.equal(result.json().data.memberAccessSource, effective.memberAccessSource);
    }
  }
});

test('authenticated status exposes a policy reason privately and does not leak lookup failures', async t => {
  const app = Fastify();
  let shouldFail = false;
  await app.register(subscriptionRoutes, {
    authenticate: async (request: FastifyRequest) => { request.user = { id: ownerId } as AuthenticatedUser; },
    read: async (userId: string) => {
      assert.equal(userId, ownerId);
      if (shouldFail) throw new Error('private database details');
      return enforceSubscriptionAccess(subscriptionFromRevenueCat(response({ store: 'test_store' }), now), now, false);
    },
  });
  t.after(() => app.close());
  const result = await app.inject({ method: 'GET', url: '/subscriptions/status' });
  assert.equal(result.statusCode, 200);
  assert.equal(result.headers['cache-control'], 'private, no-store');
  assert.equal(result.json().data.accessReason, 'sandbox_not_allowed');
  assert.equal(result.json().data.environment, 'sandbox');
  assert.equal(result.json().data.isActive, false);
  shouldFail = true;
  const failure = await app.inject({ method: 'GET', url: '/subscriptions/status' });
  assert.equal(failure.statusCode, 503);
  assert.equal(failure.json().code, 'subscription_verification_unavailable');
  assert.doesNotMatch(failure.body, /private database/);
  assert.equal(failure.headers['cache-control'], 'private, no-store');
});

test('webhook authorization denies missing, incorrect, and differently sized secrets', () => {
  assert.equal(isValidRevenueCatWebhookAuthorization(undefined, 'Bearer secret'), false);
  assert.equal(isValidRevenueCatWebhookAuthorization('Bearer secret', ''), false);
  assert.equal(isValidRevenueCatWebhookAuthorization('Bearer wrong!', 'Bearer secret'), false);
  assert.equal(isValidRevenueCatWebhookAuthorization('x', 'Bearer secret'), false);
  assert.equal(isValidRevenueCatWebhookAuthorization('Bearer secret', 'Bearer secret'), true);
});

test('webhook transfers refresh both UUID accounts and a completed retry does not repeat work', async () => {
  let receipt = false;
  const refreshed: string[] = [];
  const dependencies = {
    execute: async (sql: string) => {
      if (sql.startsWith('SELECT event_id')) return { rows: receipt ? [{ event_id: 'event-1' }] : [] };
      if (sql.startsWith('SELECT id FROM users')) return { rows: [{ id: ownerId }, { id: otherId }] };
      receipt = true;
      return { rows: [] };
    },
    sync: async (id: string) => { refreshed.push(id); return emptySubscriptionStatus(); },
  };
  const event = { id: 'event-1', type: 'TRANSFER', transferred_from: [ownerId], transferred_to: [otherId], aliases: ['$RCAnonymousID:abc'] };
  await processRevenueCatWebhook(event, dependencies);
  await processRevenueCatWebhook(event, dependencies);
  assert.deepEqual(refreshed, [ownerId, otherId]);
});

test('failed webhook refresh has no completed receipt and can be retried', async () => {
  let receipt = false;
  await assert.rejects(processRevenueCatWebhook({ id: 'failed', app_user_id: ownerId }, {
    execute: async sql => {
      if (sql.startsWith('SELECT event_id')) return { rows: [] };
      if (sql.startsWith('SELECT id FROM users')) return { rows: [{ id: ownerId }] };
      receipt = true;
      return { rows: [] };
    },
    sync: async () => { throw new Error('temporary RevenueCat outage'); },
  }));
  assert.equal(receipt, false);
});
