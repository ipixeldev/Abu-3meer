import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  normalizeYouTubeChannelId,
  youtubeChannelIdPattern,
} from '../services/youtubeChannelId.js';
import {
  YouTubeMembershipVerificationError,
  checkYouTubeMembership,
  fetchOwnedYouTubeChannelIds,
  inspectGoogleAccessToken,
  planUnmatchedPriorLink,
  reconcileUnmatchedOwnedChannels,
  selectYouTubeChannelForSnapshot,
  youtubeReadonlyScope,
} from '../services/youtubeMembershipVerificationService.js';

const channelId = `UC${'aB_9-'.repeat(5).slice(0, 22)}`;

test('accepts only stable UC IDs and exact HTTPS /channel/ URLs', () => {
  assert.equal(youtubeChannelIdPattern.test(channelId), true);
  assert.equal(normalizeYouTubeChannelId(channelId), channelId);
  assert.equal(
    normalizeYouTubeChannelId(`https://www.youtube.com/channel/${channelId}`),
    channelId,
  );
  assert.equal(
    normalizeYouTubeChannelId(`https://m.youtube.com/channel/${channelId}/videos`),
    null,
  );
  assert.equal(normalizeYouTubeChannelId('https://youtube.com/@someone'), null);
  assert.equal(
    normalizeYouTubeChannelId(`https://youtube.example/channel/${channelId}`),
    null,
  );
  assert.equal(normalizeYouTubeChannelId(`http://youtube.com/channel/${channelId}`), null);
});

test('token inspection uses a form body, requires readonly scope, and returns the Google subject', async () => {
  const token = 'ya29.test-token-that-must-not-enter-the-url';
  let requestUrl = '';
  let requestBody = '';
  const tokenInfo = await inspectGoogleAccessToken(token, {
    fetchImplementation: async (input, init) => {
      requestUrl = String(input);
      requestBody = String(init?.body ?? '');
      assert.equal(init?.method, 'POST');
      return new Response(JSON.stringify({
        sub: 'google-subject-123',
        scope: `openid email ${youtubeReadonlyScope}`,
        expires_in: '3599',
      }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  assert.equal(tokenInfo.subject, 'google-subject-123');
  assert.equal(tokenInfo.scopes.has(youtubeReadonlyScope), true);
  assert.doesNotMatch(requestUrl, /ya29|access_token/i);
  assert.match(requestBody, /^access_token=/);

  await assert.rejects(
    () => inspectGoogleAccessToken(token, {
      fetchImplementation: async () => new Response(JSON.stringify({
        sub: 'google-subject-123',
        scope: 'openid email',
        expires_in: 3599,
      }), { status: 200 }),
    }),
    (error: unknown) =>
      error instanceof YouTubeMembershipVerificationError &&
      error.code === 'youtube_readonly_scope_required' &&
      error.httpStatus === 403,
  );
});

test('owned-channel lookup uses channels.list mine=true and never puts the token in the URL', async () => {
  const token = 'ya29.another-private-access-token';
  let requestUrl = '';
  let authorization = '';
  const ids = await fetchOwnedYouTubeChannelIds(token, {
    fetchImplementation: async (input, init) => {
      requestUrl = String(input);
      authorization = new Headers(init?.headers).get('authorization') ?? '';
      return new Response(JSON.stringify({
        items: [
          { id: channelId },
          { id: channelId },
          { id: 'not-a-channel' },
        ],
      }), { status: 200 });
    },
  });
  const url = new URL(requestUrl);
  assert.equal(url.origin + url.pathname, 'https://www.googleapis.com/youtube/v3/channels');
  assert.equal(url.searchParams.get('part'), 'id');
  assert.equal(url.searchParams.get('mine'), 'true');
  assert.equal(url.searchParams.get('maxResults'), '50');
  assert.doesNotMatch(requestUrl, /ya29|access_token/i);
  assert.equal(authorization, `Bearer ${token}`);
  assert.deepEqual(ids, [channelId]);
});

test('membership check binds the access token subject to the Firebase Google identity', async () => {
  let calls = 0;
  await assert.rejects(
    () => checkYouTubeMembership({
      userId: '00000000-0000-4000-8000-000000000001',
      expectedGoogleSubject: 'firebase-google-subject',
      accessToken: 'ya29.private-access-token-for-test',
    }, {
      fetchImplementation: async () => {
        calls += 1;
        return new Response(JSON.stringify({
          sub: 'different-google-subject',
          scope: youtubeReadonlyScope,
          expires_in: 3599,
        }), { status: 200 });
      },
    }),
    (error: unknown) =>
      error instanceof YouTubeMembershipVerificationError &&
      error.code === 'youtube_google_identity_mismatch' &&
      error.httpStatus === 403,
  );
  // Identity mismatch fails before any YouTube API or database operation.
  assert.equal(calls, 1);
});

test('multiple owned channels need no manual selection when none is in the CSV', () => {
  const secondChannelId = `UC${'zY_8-'.repeat(5).slice(0, 22)}`;
  assert.deepEqual(
    selectYouTubeChannelForSnapshot([channelId, secondChannelId], []),
    { kind: 'not_in_snapshot', channelId: null, isMember: false },
  );
  assert.deepEqual(
    selectYouTubeChannelForSnapshot(
      [channelId, secondChannelId],
      [secondChannelId],
    ),
    { kind: 'selected', channelId: secondChannelId, isMember: true },
  );
  assert.throws(
    () => selectYouTubeChannelForSnapshot(
      [channelId, secondChannelId],
      [channelId, secondChannelId],
    ),
    (error: unknown) =>
      error instanceof YouTubeMembershipVerificationError &&
      error.code === 'youtube_channel_ambiguous',
  );
});

test('prior active channel A is released when Google now owns only B and C', async () => {
  const priorChannelA = channelId;
  const currentChannelB = `UC${'bB_7-'.repeat(5).slice(0, 22)}`;
  const currentChannelC = `UC${'cC_6-'.repeat(5).slice(0, 22)}`;
  assert.deepEqual(
    planUnmatchedPriorLink(
      priorChannelA,
      [currentChannelB, currentChannelC],
    ),
    { action: 'revoke', channelId: priorChannelA },
  );
  assert.deepEqual(
    planUnmatchedPriorLink(
      priorChannelA,
      [priorChannelA, currentChannelB],
    ),
    { action: 'preserve', channelId: priorChannelA },
  );

  const statements: Array<{ sql: string; params: unknown[] }> = [];
  const legacyClaimId = '11111111-1111-4111-8111-111111111111';
  const fakeClient = {
    async query(sql: string, params: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      statements.push({ sql: normalized, params });
      if (normalized.includes('UNION')) {
        return { rows: [{ youtube_channel_id: priorChannelA }], rowCount: 1 };
      }
      if (
        normalized.startsWith('SELECT youtube_channel_id, is_member') &&
        normalized.includes('FROM youtube_account_links')
      ) {
        return {
          rows: [{ youtube_channel_id: priorChannelA, is_member: true }],
          rowCount: 1,
        };
      }
      if (
        normalized.startsWith('SELECT id, youtube_channel_id') &&
        normalized.includes('FROM youtube_channel_claims')
      ) {
        return {
          rows: [{ id: legacyClaimId, youtube_channel_id: priorChannelA }],
          rowCount: 1,
        };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const reconciliationPlan = await reconcileUnmatchedOwnedChannels({
    client: fakeClient as any,
    userId: '22222222-2222-4222-8222-222222222222',
    ownedChannelIds: [currentChannelB, currentChannelC],
    snapshotId: '33333333-3333-4333-8333-333333333333',
    now: new Date('2026-09-02T10:00:00.000Z'),
  });
  assert.deepEqual(reconciliationPlan, {
    action: 'revoke',
    channelId: priorChannelA,
  });
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('UPDATE youtube_channel_claims') &&
    sql.includes("status = 'revoked'") &&
    (params[0] as string[]).includes(legacyClaimId)
  ));
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('DELETE FROM youtube_account_links') &&
    params[1] === priorChannelA
  ));
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('UPDATE users') && params[1] === null
  ));
  assert.ok(statements.some(({ sql }) =>
    sql.startsWith('DELETE FROM user_roles')
  ));
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('INSERT INTO membership_history') &&
    params.includes('google_oauth_owned_channels_changed')
  ));

  const service = fs.readFileSync(
    path.resolve(
      process.cwd(),
      'src/services/youtubeMembershipVerificationService.ts',
    ),
    'utf8',
  );
  const reconciliation = service.slice(
    service.indexOf('async function reconcileUnmatchedOwnedChannels'),
    service.indexOf('async function linkVerifiedChannelAgainstSnapshot'),
  );
  assert.match(reconciliation, /status = 'revoked'/);
  assert.match(reconciliation, /approved_snapshot_import_id = NULL/);
  assert.match(reconciliation, /DELETE FROM youtube_account_links/);
  assert.match(reconciliation, /SET is_youtube_member = FALSE/);
  assert.match(reconciliation, /DELETE FROM user_roles/);
  assert.match(reconciliation, /INSERT INTO membership_history/);
  assert.match(reconciliation, /google_oauth_owned_channels_changed/);

  const unmatchedBranch = service.slice(
    service.indexOf("if (selection.kind === 'not_in_snapshot')"),
    service.indexOf('const channelId = selection.channelId'),
  );
  assert.match(unmatchedBranch, /reconcileUnmatchedOwnedChannels/);
  assert.match(unmatchedBranch, /await client\.query\('COMMIT'\)/);
});

test('an unmatched prior link is preserved when Google still reports it as owned', async () => {
  const priorChannelA = channelId;
  const currentChannelB = `UC${'dD_5-'.repeat(5).slice(0, 22)}`;
  const claimId = '44444444-4444-4444-8444-444444444444';
  const statements: Array<{ sql: string; params: unknown[] }> = [];
  const fakeClient = {
    async query(sql: string, params: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      statements.push({ sql: normalized, params });
      if (normalized.includes('UNION')) {
        return { rows: [{ youtube_channel_id: priorChannelA }], rowCount: 1 };
      }
      if (normalized.startsWith('SELECT youtube_channel_id, is_member')) {
        return {
          rows: [{ youtube_channel_id: priorChannelA, is_member: true }],
          rowCount: 1,
        };
      }
      if (normalized.startsWith('SELECT id, youtube_channel_id')) {
        return {
          rows: [{ id: claimId, youtube_channel_id: priorChannelA }],
          rowCount: 1,
        };
      }
      return { rows: [], rowCount: 0 };
    },
  };
  const plan = await reconcileUnmatchedOwnedChannels({
    client: fakeClient as any,
    userId: '55555555-5555-4555-8555-555555555555',
    ownedChannelIds: [priorChannelA, currentChannelB],
    snapshotId: '66666666-6666-4666-8666-666666666666',
    now: new Date('2026-09-02T10:05:00.000Z'),
  });
  assert.deepEqual(plan, { action: 'preserve', channelId: priorChannelA });
  assert.equal(
    statements.some(({ sql }) =>
      sql.startsWith('DELETE FROM youtube_account_links')
    ),
    false,
  );
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('UPDATE youtube_account_links') &&
    sql.includes('SET is_member = FALSE') &&
    params[2] === priorChannelA
  ));
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('UPDATE users') && params[1] === priorChannelA
  ));
  assert.ok(statements.some(({ sql, params }) =>
    sql.startsWith('UPDATE youtube_channel_claims') &&
    sql.includes('Ownership reverified by Google') &&
    params[0] === claimId
  ));
});

test('automatic channel linking is serialized against CSV replacement and commits authority atomically', () => {
  const service = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/youtubeMembershipVerificationService.ts'),
    'utf8',
  );
  assert.match(service, /pg_advisory_xact_lock_shared\([\s\S]*youtube-membership-snapshot-import/);
  assert.match(service, /snapshot_import\.expires_at > \$1/);
  assert.match(service, /youtube_channel_id = ANY\(\$2::varchar\[\]\)/);
  assert.match(service, /INSERT INTO youtube_channel_claims/);
  assert.match(service, /'Channel ownership verified by Google OAuth\.'/);
  assert.match(service, /ownership_verification_source = 'google_oauth'/);
  assert.match(service, /INSERT INTO youtube_account_links/);
  assert.match(service, /UPDATE users/);
  assert.match(service, /INSERT INTO user_roles/);
  assert.match(service, /INSERT INTO membership_history/);
  assert.match(service, /await client\.query\('COMMIT'\)/);
  assert.doesNotMatch(service, /accessToken[^\n]*INSERT|accessToken[^\n]*UPDATE/);
});

test('migration revokes legacy OAuth trust and enforces unique approvals', () => {
  const migration = fs.readFileSync(
    path.resolve(process.cwd(), 'migrations/037_youtube_channel_claims.sql'),
    'utf8',
  );
  assert.match(migration, /CREATE TABLE IF NOT EXISTS youtube_channel_claims/);
  assert.match(migration, /WHERE status = 'approved'/);
  assert.match(migration, /youtube_channel_id\)\s*\n\s*WHERE status = 'approved'/);
  assert.match(migration, /DELETE FROM youtube_account_links/);
  assert.match(
    migration,
    /WHERE youtube_channel_id ~ '\^UC\[A-Za-z0-9_-\]\{22\}\$'/,
  );
  assert.match(migration, /verification_source = 'admin_snapshot'/);
  assert.match(migration, /admin_user_id DROP NOT NULL/);
  assert.match(migration, /ON DELETE SET NULL/);
  assert.match(migration, /DELETE FROM youtube_creator_credentials/);
  assert.match(migration, /DELETE FROM youtube_oauth_flows/);
  assert.doesNotMatch(migration, /DROP TABLE IF EXISTS youtube_(?:creator_credentials|oauth_flows)/);
});

test('Google ownership migration revokes every legacy manual link before enabling automatic approvals', () => {
  const migration = fs.readFileSync(
    path.resolve(
      process.cwd(),
      'migrations/039_google_verified_youtube_channels.sql',
    ),
    'utf8',
  );
  assert.match(migration, /ownership_verification_source/);
  assert.match(migration, /WHERE status IN \('pending', 'approved'\)/);
  assert.match(migration, /DELETE FROM youtube_account_links/);
  assert.match(migration, /DELETE FROM user_roles WHERE role_id = 'member'/);
  assert.match(migration, /SET matched_user_count = 0/);
  assert.match(
    migration,
    /status <> 'approved'[\s\S]*ownership_verification_source = 'google_oauth'/,
  );
});

test('routes expose automatic checks and snapshots but no manual claim mutation or staff decision', () => {
  const routes = fs.readFileSync(
    path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
    'utf8',
  );
  assert.match(routes, /'\/profile\/youtube\/membership\/check'/);
  assert.match(routes, /expectedGoogleSubject: request\.user!\.googleProviderUid/);
  assert.match(routes, /accessToken: parsed\.data\.accessToken/);
  assert.match(routes, /hook: 'preHandler'/);
  assert.match(
    routes,
    /youtube-membership-check:user:\$\{request\.user\?\.id \?\? request\.ip\}/,
  );
  assert.match(routes, /fastify\.get\([\s\S]*'\/profile\/youtube\/claim'/);
  assert.match(routes, /membership_snapshots\.manage/);
  assert.doesNotMatch(routes, /fastify\.post\([\s\S]{0,80}'\/profile\/youtube\/claim'/);
  assert.doesNotMatch(routes, /claims\/:claimId\/decision/);
  assert.doesNotMatch(routes, /creator\/connect|connect\/start/i);
});

test('CSV reconciliation requires approval and expires safely to x1', () => {
  const service = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/csvMembershipService.ts'),
    'utf8',
  );
  assert.match(service, /claim\.status = 'approved'/);
  assert.match(service, /snapshot_import\.expires_at > \$2/);
  assert.match(service, /snapshot_import_id = CASE[\s\S]*ELSE NULL/);
  assert.match(service, /INSERT INTO membership_history/);
  assert.match(service, /admin_snapshot_reconciliation/);
  assert.match(service, /unavailable: 0/);
  assert.match(service, /membershipApiRequests: 0/);
});

test('every award and leaderboard read rechecks approved unexpired authority', () => {
  const prediction = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/predictionService.ts'),
    'utf8',
  );
  const challenge = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/challengeService.ts'),
    'utf8',
  );
  const leaderboard = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/leaderboardService.ts'),
    'utf8',
  );
  assert.match(prediction, /snapshot_import\.expires_at > CURRENT_TIMESTAMP/);
  assert.match(prediction, /approved_claim\.status = 'approved'/);
  assert.match(
    prediction,
    /pg_advisory_lock_shared\([\s\S]*youtube-membership-snapshot-import[\s\S]*settleMatchPredictionsUnlocked/,
  );
  assert.match(prediction, /pg_advisory_unlock_shared/);
  assert.match(challenge, /pg_advisory_xact_lock_shared/);
  assert.match(challenge, /snapshot_import\.expires_at > clock_timestamp\(\)/);
  assert.match(challenge, /approved_claim\.status = 'approved'/);
  assert.match(leaderboard, /snapshot_import\.expires_at > CURRENT_TIMESTAMP/);
  assert.match(leaderboard, /approved_claim\.status = 'approved'/);
});

test('deployment configuration contains no membership OAuth secret', () => {
  const environment = fs.readFileSync(
    path.resolve(process.cwd(), '.env.example'),
    'utf8',
  );
  const compose = fs.readFileSync(
    path.resolve(process.cwd(), 'docker-compose.yml'),
    'utf8',
  );
  for (const source of [environment, compose]) {
    assert.doesNotMatch(source, /YOUTUBE_OAUTH_CLIENT/);
    assert.doesNotMatch(source, /YOUTUBE_OAUTH_REDIRECT/);
    assert.doesNotMatch(source, /YOUTUBE_TOKEN_ENCRYPTION/);
    assert.match(source, /YOUTUBE_CREATOR_CHANNEL_ID/);
    assert.match(source, /YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS/);
  }
});
