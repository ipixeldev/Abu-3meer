import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS,
  hasRecentFirebaseAuthentication,
} from '../middleware/auth.js';

test('recent authentication accepts only a signed auth_time within five minutes', () => {
  const now = 2_000_000_000;
  assert.equal(hasRecentFirebaseAuthentication(now, now), true);
  assert.equal(
    hasRecentFirebaseAuthentication(
      now - SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS,
      now,
    ),
    true,
  );
  assert.equal(
    hasRecentFirebaseAuthentication(
      now - SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS - 1,
      now,
    ),
    false,
  );
  assert.equal(hasRecentFirebaseAuthentication(undefined, now), false);
  assert.equal(hasRecentFirebaseAuthentication(Number.NaN, now), false);
  assert.equal(hasRecentFirebaseAuthentication(now + 1, now), false);
});

test('account deletion is wired behind authentication and recent-auth checks', () => {
  const source = readFileSync(
    resolve(process.cwd(), 'src/routes/profileRoutes.ts'),
    'utf8',
  );
  const start = source.indexOf("fastify.delete(\n    '/profile/me'");
  const end = source.indexOf("\n  );", start);
  assert.notEqual(start, -1);
  assert.notEqual(end, -1);
  const route = source.slice(start, end);
  assert.match(
    route,
    /preHandler:\s*\[authenticateUser, requireRecentFirebaseAuthentication\]/,
  );
});
