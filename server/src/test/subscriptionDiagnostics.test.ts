import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { enforceSubscriptionAccess } from '../services/subscriptionService.js';

const diagnostics = import(pathToFileURL(path.resolve('scripts/diagnose_subscriptions.mjs')).href);
const now = Date.parse('2026-09-06T12:00:00Z');
const policy = {
  serverKeyConfigured: true, allowSandbox: false,
  runtimeSupportsAccessReasons: true,
};
const row = {
  id: 'private-account-id', subscription_user_id: 'private-account-id',
  is_active: true, product_id: 'Ostoora3_Pro_Max', is_sandbox: true, will_renew: true,
  expires_at: new Date(now + 60 * 60_000), verified_at: new Date(now),
};

test('read-only subscription diagnostics validate and normalize one username', async () => {
  const { parseUsername } = await diagnostics;
  assert.equal(parseUsername(['--username', '@Dev']), 'dev');
  for (const args of [[], ['dev'], ['--username', ''], ['--username', 'two users'], ['--username', 'x'.repeat(51)]]) {
    assert.throws(() => parseUsername(args));
  }
});

test('diagnostics use parameterized SELECT only and do not expose account or credential fields', async () => {
  const { diagnoseSubscription } = await diagnostics;
  const statements: string[] = [];
  const report = await diagnoseSubscription({
    username: "dev'; DROP TABLE users; --", policy, now, enforce: enforceSubscriptionAccess,
    execute: async (sql: string, params: unknown[]) => {
      statements.push(sql);
      assert.match(sql.trim(), /^SELECT /);
      assert.doesNotMatch(sql, /INSERT|UPDATE|DELETE|DROP/);
      assert.match(sql, /WHERE u\.normalized_username = \$1/);
      assert.deepEqual(params, ["dev'; DROP TABLE users; --"]);
      return { rows: [{ ...row, email: 'private@example.test', secretApiKey: 'not-for-output' }] };
    },
  });
  assert.equal(statements.length, 1);
  assert.equal(report.accessActive, false);
  assert.equal(report.accessReason, 'sandbox_not_allowed');
  assert.equal(report.reasonSource, 'server-runtime');
  assert.equal(report.sourceEntitlementActive, true);
  assert.equal(report.readOnly, true);
  const serialized = JSON.stringify(report);
  assert.doesNotMatch(serialized, /private-account-id|private@example|not-for-output|secretApiKey/);
});

test('legacy image reports the current policy reason without requiring an image upgrade', async () => {
  const { diagnoseSubscription } = await diagnostics;
  const report = await diagnoseSubscription({
    username: 'dev', policy: { ...policy, runtimeSupportsAccessReasons: false }, now,
    enforce: (source: Parameters<typeof enforceSubscriptionAccess>[0], clock: number, allow: boolean) => {
      const { accessReason: _reason, environment: _environment, ...legacy } = enforceSubscriptionAccess(source, clock, allow);
      return legacy;
    },
    execute: async () => ({ rows: [row] }),
  });
  assert.equal(report.runtimeSupportsAccessReasons, false);
  assert.equal(report.accessActive, false);
  assert.equal(report.accessReason, 'sandbox_not_allowed');
  assert.equal(report.reasonSource, 'derived-for-legacy-runtime');
});

test('diagnostics distinguish expired, malformed, absent and durable active production subscriptions', async () => {
  const { diagnoseSubscription } = await diagnostics;
  for (const [changes, reason] of [
    [{ expires_at: new Date(now) }, 'expired'],
    [{ verified_at: new Date(now - 48 * 60 * 60_000), is_sandbox: false }, 'active'],
    [{ verified_at: new Date(now + 60_001) }, 'verification_required'],
    [{ is_active: false, product_id: null, subscription_user_id: null }, 'no_entitlement'],
    [{ is_sandbox: false }, 'active'],
  ] as const) {
    const report = await diagnoseSubscription({
      username: 'dev', policy, now, enforce: enforceSubscriptionAccess,
      execute: async () => ({ rows: [{ ...row, ...changes }] }),
    });
    assert.equal(report.accessReason, reason);
    assert.equal(report.accessActive, reason === 'active');
    if (reason === 'active') assert.equal(report.verificationTimestampValid, true);
  }
  const missing = await diagnoseSubscription({
    username: 'dev', policy, now, enforce: enforceSubscriptionAccess,
    execute: async () => ({ rows: [] }),
  });
  assert.equal(missing.accountFound, false);
  assert.equal(missing.accessActive, undefined);
});

test('diagnostics apply the sandbox allowlist only to the matching private account UUID', async () => {
  const { diagnoseSubscription } = await diagnostics;
  const allowedPolicy = {
    ...policy,
    sandboxAllowedUserIds: ['private-account-id'],
  };
  const allowed = await diagnoseSubscription({
    username: 'reviewer', policy: allowedPolicy, now,
    enforce: enforceSubscriptionAccess,
    execute: async () => ({ rows: [row] }),
  });
  assert.equal(allowed.sandboxAllowed, true);
  assert.equal(allowed.accessReason, 'active');
  const denied = await diagnoseSubscription({
    username: 'tester', policy: allowedPolicy, now,
    enforce: enforceSubscriptionAccess,
    execute: async () => ({ rows: [{ ...row, id: 'different-private-id' }] }),
  });
  assert.equal(denied.sandboxAllowed, false);
  assert.equal(denied.accessReason, 'sandbox_not_allowed');
  assert.doesNotMatch(JSON.stringify(allowed), /private-account-id/);
});
