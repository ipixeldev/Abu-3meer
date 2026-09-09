import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import Fastify, { FastifyRequest } from 'fastify';
import {
  AuthenticatedUser,
  SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS,
  hasRecentFirebaseAuthentication,
} from '../middleware/auth.js';
import { profileRoutes } from '../routes/profileRoutes.js';

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
    /dependencies\.authenticateAccountDeletion \?\? authenticateUser/,
  );
  assert.match(
    route,
    /dependencies\.requireRecentAccountDeletionAuthentication\s*\?\? requireRecentFirebaseAuthentication/,
  );
  assert.match(route, /AccountDeletionCleanupUnavailable/);
  assert.match(
    route,
    /Your sign-in account is still active; please try again shortly\./,
  );
});

test('legacy Firebase cleanup failure keeps PostgreSQL and sign-in account intact', async (t) => {
  const userId = '11111111-1111-4111-8111-111111111111';
  const firebaseUid = 'firebase-user-1';
  let firebaseCleanupCalls = 0;
  let postgresDeletionCalls = 0;
  const app = Fastify({ logger: false });

  await app.register(profileRoutes, {
    authenticateAccountDeletion: async (request: FastifyRequest) => {
      request.user = {
        id: userId,
        firebaseUid,
        authTime: Math.floor(Date.now() / 1000),
      } as AuthenticatedUser;
    },
    deleteFirebaseMirror: async (actualFirebaseUid: string) => {
      firebaseCleanupCalls += 1;
      assert.equal(actualFirebaseUid, firebaseUid);
      throw new Error('forced legacy Firebase cleanup failure');
    },
    deletePostgresAccount: async () => {
      postgresDeletionCalls += 1;
      return true;
    },
  });
  t.after(() => app.close());

  const response = await app.inject({
    method: 'DELETE',
    url: '/profile/me',
  });

  const body = response.json();
  assert.equal(response.statusCode, 503);
  assert.deepEqual(body, {
    error: 'AccountDeletionCleanupUnavailable',
    message:
      'We could not safely remove all account data. Your sign-in account is still active; please try again shortly.',
    requestId: body.requestId,
  });
  assert.equal(typeof body.requestId, 'string');
  assert.equal(firebaseCleanupCalls, 1);
  assert.equal(postgresDeletionCalls, 0);
});
