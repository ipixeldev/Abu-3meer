import assert from "node:assert/strict";
import test from "node:test";

import {
  fixedWindowBucket,
  fixedWindowRetryAfterSeconds,
  idempotencyPayloadHash,
  isFirebaseEmulator,
  phase3CallableOptions,
  resolveAppCheckMode,
  securityHash,
} from "./phase3_security.js";

test("App Check rollout is forcibly disabled in Firebase emulators", () => {
  const environment = {
    FUNCTIONS_EMULATOR: "true",
    ABU3MEER_APP_CHECK_MODE: "enforce",
  };
  assert.equal(isFirebaseEmulator(environment), true);
  assert.equal(resolveAppCheckMode(environment), "off");
  const options = phase3CallableOptions("europe-west1", {
    replayProtected: true,
    environment,
  });
  assert.equal(options.enforceAppCheck, false);
  assert.equal(options.consumeAppCheckToken, false);
});

test("App Check monitor and enforce modes produce safe callable options", () => {
  const monitor = phase3CallableOptions("europe-west1", {
    replayProtected: true,
    environment: {ABU3MEER_APP_CHECK_MODE: "monitor"},
  });
  assert.equal(monitor.enforceAppCheck, false);
  assert.equal(monitor.consumeAppCheckToken, false);

  const enforce = phase3CallableOptions("europe-west1", {
    replayProtected: true,
    environment: {ABU3MEER_APP_CHECK_MODE: "enforce"},
  });
  assert.equal(enforce.enforceAppCheck, true);
  assert.equal(enforce.consumeAppCheckToken, true);
});

test("fixed rate windows have deterministic buckets and retry delays", () => {
  const minute = 60_000;
  assert.equal(fixedWindowBucket(minute * 10 + 10_000, 60), 10);
  assert.equal(fixedWindowRetryAfterSeconds(minute * 10 + 10_000, 60), 50);
  assert.equal(fixedWindowRetryAfterSeconds(minute * 10 + 59_999, 60), 1);
});

test("security hashes are deterministic, peppered, and do not expose input", () => {
  const first = securityHash("198.51.100.9", "pepper-one");
  const second = securityHash("198.51.100.9", "pepper-one");
  assert.equal(first, second);
  assert.notEqual(first, securityHash("198.51.100.9", "pepper-two"));
  assert.equal(first.includes("198.51.100.9"), false);
  assert.match(first, /^[a-f0-9]{64}$/);
});

test("idempotency payload hashing ignores object key order but detects changes", () => {
  const first = idempotencyPayloadHash({matchId: "one", score: {home: 2, away: 1}});
  const reordered = idempotencyPayloadHash({score: {away: 1, home: 2}, matchId: "one"});
  const changed = idempotencyPayloadHash({score: {away: 2, home: 2}, matchId: "one"});
  assert.equal(first, reordered);
  assert.notEqual(first, changed);
});
