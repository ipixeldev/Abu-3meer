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
} from '../services/youtubeMembershipVerificationService.js';
import { YouTubeProfileResolutionError } from '../services/youtubeProfileResolver.js';

const channelId = `UC${'aB_9-'.repeat(5).slice(0, 22)}`;
const otherChannelId = `UC${'bC_8-'.repeat(5).slice(0, 22)}`;
const userId = '00000000-0000-4000-8000-000000000001';
const snapshotId = '00000000-0000-4000-8000-000000000002';
const now = new Date('2026-09-05T12:00:00.000Z');
const snapshotExpiresAt = new Date('2026-09-12T12:00:00.000Z');

test('accepts stable IDs and exact HTTPS YouTube profile links, including mobile/share links', () => {
  assert.equal(youtubeChannelIdPattern.test(channelId), true);
  for (const link of [
    channelId,
    `https://www.youtube.com/channel/${channelId}`,
    `https://m.youtube.com/channel/${channelId}/?si=share-token`,
    ` https://youtube.com/channel/${channelId} `,
  ]) {
    assert.equal(normalizeYouTubeChannelId(link), channelId);
  }
});

test('rejects ambiguous channel links, credentials, unexpected ports, and non-YouTube hosts', () => {
  for (const link of [
    'https://youtube.com/@someone',
    `https://m.youtube.com/channel/${channelId}/videos`,
    `https://youtube.example/channel/${channelId}`,
    `https://www.youtube.com.example.com/channel/${channelId}`,
    `http://youtube.com/channel/${channelId}`,
    `https://attacker@youtube.com/channel/${channelId}`,
    `https://youtube.com:8443/channel/${channelId}`,
    `https://youtube.com//channel/${channelId}`,
    `https://youtube.com/channel/UCshort`,
    'Jane Smith',
    'javascript:alert(1)',
  ]) {
    assert.equal(normalizeYouTubeChannelId(link), null, link);
  }
});

type RecordedQuery = { sql: string; params: unknown[] };
function databaseScenario(options: {
  snapshot?: boolean;
  member?: boolean;
  claimConflict?: boolean;
  linkConflict?: boolean;
  prior?: { youtube_channel_id: string; is_member: boolean };
  claims?: Array<{ id: string; youtube_channel_id: string; status: string }>;
  failLinkWrite?: boolean;
} = {}) {
  const statements: RecordedQuery[] = [];
  let released = false;
  const client = {
    async query(sql: string, params: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      statements.push({ sql: normalized, params });
      if (normalized.startsWith('SELECT snapshot_import.id')) {
        assert.ok(normalized.includes('snapshot_import.expires_at > $1'));
        assert.deepEqual(params, [now]);
        return {
          rows: options.snapshot === false ? [] : [{ id: snapshotId, expires_at: snapshotExpiresAt }],
          rowCount: options.snapshot === false ? 0 : 1,
        };
      }
      if (normalized.startsWith('SELECT user_id')) {
        const conflict = normalized.includes('youtube_channel_claims')
          ? options.claimConflict
          : options.linkConflict;
        return { rows: conflict ? [{ user_id: 'another-user' }] : [], rowCount: conflict ? 1 : 0 };
      }
      if (normalized.startsWith('SELECT youtube_channel_id, membership_level')) {
        assert.deepEqual(params, [snapshotId, channelId]);
        return {
          rows: options.member === false ? [] : [{
            youtube_channel_id: channelId,
            membership_level: 'الأستوووراع',
            joined_at: new Date('2026-09-01T10:00:00.000Z'),
          }],
          rowCount: options.member === false ? 0 : 1,
        };
      }
      if (normalized.startsWith('SELECT youtube_channel_id, is_member')) {
        return { rows: options.prior ? [options.prior] : [], rowCount: options.prior ? 1 : 0 };
      }
      if (normalized.startsWith('SELECT id, youtube_channel_id, status')) {
        return { rows: options.claims ?? [], rowCount: options.claims?.length ?? 0 };
      }
      if (normalized.startsWith('INSERT INTO youtube_account_links') && options.failLinkWrite) {
        throw Object.assign(new Error('unique channel constraint'), { code: '23505' });
      }
      return { rows: [], rowCount: 0 };
    },
    release() { released = true; },
  };
  return {
    clientFactory: async () => client as any,
    statements,
    wasReleased: () => released,
  };
}

test('manual CSV check grants current matching membership without a Google account or credential', async () => {
  const db = databaseScenario();
  const result = await checkYouTubeMembership({
    userId,
    profileLink: `https://youtube.com/channel/${channelId}`,
  }, { now, clientFactory: db.clientFactory });
  assert.deepEqual(result.membership, {
    status: 'active',
    isMember: true,
    youtubeChannelId: channelId,
    membershipLevelId: 'الأستوووراع',
    memberSince: '2026-09-01T10:00:00.000Z',
    verifiedAt: now.toISOString(),
    snapshotExpiresAt: snapshotExpiresAt.toISOString(),
    verificationMethod: 'manual_profile_link',
  });
  const claim = db.statements.find(({ sql }) => sql.startsWith('INSERT INTO youtube_channel_claims'));
  assert.ok(claim);
  assert.match(claim.sql, /manual_profile_link/);
  assert.doesNotMatch(claim.sql, /google_oauth/);
  assert.match(claim.sql, /ownership not independently verified/);
  const savedLink = db.statements.find(({ sql }) => sql.startsWith('INSERT INTO youtube_account_links'));
  assert.deepEqual(savedLink?.params.slice(0, 3), [userId, channelId, true]);
  assert.equal(savedLink?.params[6], snapshotId);
  assert.ok(db.statements.some(({ sql }) => sql.startsWith('INSERT INTO user_roles')));
  assert.equal(db.statements.at(-1)?.sql, 'COMMIT');
  assert.equal(db.wasReleased(), true);
});

test('a non-matching link removes former member access and records inactive history', async () => {
  const db = databaseScenario({
    member: false,
    prior: { youtube_channel_id: channelId, is_member: true },
    claims: [{ id: 'claim-id', youtube_channel_id: channelId, status: 'approved' }],
  });
  const result = await checkYouTubeMembership({ userId, profileLink: channelId }, {
    now, clientFactory: db.clientFactory,
  });
  assert.equal(result.membership.status, 'not_in_snapshot');
  assert.equal(result.membership.isMember, false);
  const savedLink = db.statements.find(({ sql }) => sql.startsWith('INSERT INTO youtube_account_links'));
  assert.equal(savedLink?.params[2], false);
  assert.equal(savedLink?.params[6], null);
  assert.ok(db.statements.some(({ sql }) => sql.startsWith('DELETE FROM user_roles')));
  const history = db.statements.find(({ sql }) => sql.startsWith('INSERT INTO membership_history'));
  assert.equal(history?.params[1], 'inactive');
  assert.equal(history?.params[3], now);
});

test('no usable snapshot returns unavailable and does not create a link or grant a role', async () => {
  const db = databaseScenario({ snapshot: false });
  const result = await checkYouTubeMembership({ userId, profileLink: channelId }, {
    now, clientFactory: db.clientFactory,
  });
  assert.equal(result.membership.status, 'snapshot_unavailable');
  assert.equal(result.membership.isMember, false);
  assert.equal(db.statements.some(({ sql }) => /^(INSERT|UPDATE|DELETE)/.test(sql)), false);
  assert.equal(db.statements.at(-1)?.sql, 'COMMIT');
  assert.equal(db.wasReleased(), true);
});

test('another user cannot claim an already accepted or linked channel', async () => {
  for (const conflict of [{ claimConflict: true }, { linkConflict: true }]) {
    const db = databaseScenario(conflict);
    await assert.rejects(
      () => checkYouTubeMembership({ userId, profileLink: channelId }, {
        now, clientFactory: db.clientFactory,
      }),
      (error: unknown) =>
        error instanceof YouTubeMembershipVerificationError &&
        error.code === 'youtube_channel_already_linked' &&
        error.httpStatus === 409,
    );
    assert.equal(db.statements.some(({ sql }) => /^(INSERT|UPDATE|DELETE)/.test(sql)), false);
    assert.equal(db.statements.at(-1)?.sql, 'ROLLBACK');
    assert.equal(db.wasReleased(), true);
  }
});

test('switching channel releases previous approval before saving the new channel', async () => {
  const db = databaseScenario({
    prior: { youtube_channel_id: otherChannelId, is_member: true },
    claims: [{ id: 'old-claim-id', youtube_channel_id: otherChannelId, status: 'approved' }],
  });
  await checkYouTubeMembership({ userId, profileLink: channelId }, {
    now, clientFactory: db.clientFactory,
  });
  const supersededAt = db.statements.findIndex(({ sql }) =>
    sql.startsWith('UPDATE youtube_channel_claims') && sql.includes("status = 'superseded'")
  );
  const newClaimAt = db.statements.findIndex(({ sql }) => sql.startsWith('INSERT INTO youtube_channel_claims'));
  assert.ok(supersededAt >= 0 && supersededAt < newClaimAt);
  assert.deepEqual(db.statements[supersededAt].params[0], ['old-claim-id']);
  const history = db.statements.find(({ sql }) => sql.startsWith('INSERT INTO membership_history'));
  assert.equal(history?.params[6], otherChannelId);
});

test('unique constraint races roll back membership writes and become a channel conflict', async () => {
  const db = databaseScenario({ failLinkWrite: true });
  await assert.rejects(
    () => checkYouTubeMembership({ userId, profileLink: channelId }, {
      now, clientFactory: db.clientFactory,
    }),
    (error: unknown) =>
      error instanceof YouTubeMembershipVerificationError &&
      error.code === 'youtube_channel_already_linked',
  );
  assert.equal(db.statements.at(-1)?.sql, 'ROLLBACK');
  assert.equal(db.statements.some(({ sql }) => sql.startsWith('UPDATE users')), false);
  assert.equal(db.wasReleased(), true);
});

test('malformed profile links fail before accessing the database', async () => {
  let accessed = false;
  await assert.rejects(
    () => checkYouTubeMembership({ userId, profileLink: 'https://youtube.com/watch?v=someone' }, {
      clientFactory: async () => { accessed = true; throw new Error('must not run'); },
    }),
    (error: unknown) =>
      error instanceof YouTubeMembershipVerificationError &&
      error.code === 'youtube_profile_link_invalid',
  );
  assert.equal(accessed, false);
});

test('handle links resolve to stable IDs before the same CSV eligibility check', async () => {
  for (const member of [true, false]) {
    const db = databaseScenario({ member });
    const result = await checkYouTubeMembership({ userId, profileLink: 'https://youtube.com/@aeyaall?si=share' }, {
      now,
      clientFactory: db.clientFactory,
      channelResolver: async (link) => {
        assert.equal(link, 'https://youtube.com/@aeyaall?si=share');
        return channelId;
      },
    });
    assert.equal(result.membership.youtubeChannelId, channelId);
    assert.equal(result.membership.status, member ? 'active' : 'not_in_snapshot');
    assert.equal(result.membership.isMember, member);
  }
});

test('resolver outages remain retriable errors and never change membership', async () => {
  let accessed = false;
  await assert.rejects(() => checkYouTubeMembership({ userId, profileLink: 'https://youtube.com/@aeyaall' }, {
    clientFactory: async () => { accessed = true; throw new Error('must not run'); },
    channelResolver: async () => {
      throw new YouTubeProfileResolutionError('youtube_profile_lookup_unavailable', 503, 'Try again later.');
    },
  }), (error: unknown) => error instanceof YouTubeMembershipVerificationError && error.httpStatus === 503);
  assert.equal(accessed, false);
});

test('routes accept profile links with a stable per-user quota and no OAuth credential', () => {
  const routes = fs.readFileSync(
    path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
    'utf8',
  );
  assert.match(routes, /profileLink: parsed\.data\.profileLink/);
  assert.match(routes, /hook: 'preHandler'/);
  assert.match(routes, /youtube-membership-check:user:\$\{request\.user\?\.id \?\? request\.ip\}/);
  assert.match(routes, /membership_snapshots\.manage/);
  assert.doesNotMatch(routes, /expectedGoogleSubject|accessToken|creator\/connect/);
});

test('manual-link migration preserves existing ownership history and adds a distinct accepted source', () => {
  const migration = fs.readFileSync(
    path.resolve(process.cwd(), 'migrations/040_manual_profile_membership.sql'),
    'utf8',
  );
  assert.match(migration, /'legacy_manual', 'google_oauth', 'manual_profile_link'/);
  assert.match(migration, /status <> 'approved'/);
  assert.doesNotMatch(migration, /DELETE FROM|TRUNCATE|UPDATE youtube_channel_claims/i);
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
