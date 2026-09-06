import test from 'node:test';
import assert from 'node:assert/strict';
import Fastify, { FastifyRequest } from 'fastify';
import {
  emptySubscriptionStatus,
  enforceSubscriptionAccess,
  isValidRevenueCatWebhookAuthorization,
  processRevenueCatWebhook,
  SubscriptionError,
  subscriptionFromRevenueCat,
  syncSubscriptionStatus,
} from '../services/subscriptionService.js';
import { subscriptionRoutes } from '../routes/subscriptionRoutes.js';
import { resolveChallengeMembership } from '../services/challengeMembershipService.js';
import type { AuthenticatedUser } from '../middleware/auth.js';

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

test('expiry and verification lease are enforced without a client refresh or webhook', () => {
  const active = subscriptionFromRevenueCat(response(), now);
  assert.equal(enforceSubscriptionAccess(active, now + 24 * 60 * 60_000).isActive, false);
  assert.equal(enforceSubscriptionAccess({ ...active, expiresAt: new Date(now).toISOString() }, now).isActive, false);
  assert.equal(enforceSubscriptionAccess({ ...active, expiresAt: null }, now).isActive, false);
});

test('sandbox and Test Store purchases need an explicit backend opt-in', () => {
  const sandbox = subscriptionFromRevenueCat(response({ is_sandbox: true }), now);
  assert.equal(enforceSubscriptionAccess(sandbox, now, false).isActive, false);
  assert.equal(enforceSubscriptionAccess(sandbox, now, true).isActive, true);
  const testStore = subscriptionFromRevenueCat(response({ store: 'test_store' }), now);
  assert.equal(enforceSubscriptionAccess(testStore, now, false).isActive, false);
  assert.equal(subscriptionFromRevenueCat(response({ is_sandbox: undefined }), now).isActive, false);
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
        saved = { is_active: parameters[1], product_id: parameters[2], expires_at: parameters[3],
          will_renew: parameters[4], is_sandbox: parameters[5], verified_at: parameters[6] };
        return { rows: [] };
      }
      return { rows: saved ? [saved] : [] };
    },
  });
  assert.equal(result.isActive, false);
  assert.equal(statements.length, 2);
  for (const statement of statements) assert.doesNotMatch(statement, /youtube|user_roles|UPDATE users/);
});

test('a paid member with no YouTube channel receives member content; valid CSV survives paid expiry', async () => {
  const paid = await resolveChallengeMembership(ownerId, {
    queryMembership: async () => ({ rows: [{ linked: false, current_member: false, is_pro_subscriber: true }] }),
    refreshMembership: async () => { throw new Error('Must not require CSV for a subscriber'); },
  });
  assert.equal(paid, true);
  const csv = await resolveChallengeMembership(ownerId, {
    queryMembership: async () => ({ rows: [{ linked: true, current_member: true, is_pro_subscriber: false }] }),
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
