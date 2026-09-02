import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  normalizeYouTubeChannelId,
  youtubeChannelIdPattern,
} from '../services/youtubeChannelId.js';

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

test('a typed claim cannot grant membership before an audited staff decision', () => {
  const service = fs.readFileSync(
    path.resolve(process.cwd(), 'src/services/youtubeChannelClaimService.ts'),
    'utf8',
  );
  const submit = service.slice(
    service.indexOf('export async function submitYouTubeChannelClaim'),
    service.indexOf('export function getMyYouTubeChannelClaim'),
  );
  assert.doesNotMatch(submit, /is_youtube_member\s*=\s*TRUE/);
  assert.doesNotMatch(submit, /INSERT INTO youtube_account_links/);

  const decision = service.slice(
    service.indexOf('export async function decideYouTubeChannelClaim'),
  );
  assert.match(decision, /snapshot_import\.expires_at > CURRENT_TIMESTAMP/);
  assert.match(decision, /snapshot_member\.status = 'active'/);
  assert.match(decision, /youtube_channel_already_claimed/);
  assert.match(decision, /youtube_claim_self_review_forbidden/);
  assert.match(decision, /INSERT INTO admin_audit_logs/);
  assert.match(decision, /reviewedByUserId: input\.reviewedByUserId/);
  assert.match(decision, /membership_snapshots\.manage|reviewedByUserId/);
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

test('routes expose claims and snapshots without member OAuth callbacks', () => {
  const routes = fs.readFileSync(
    path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
    'utf8',
  );
  assert.match(routes, /'\/profile\/youtube\/claim'/);
  assert.match(routes, /'\/admin\/youtube\/membership\/claims'/);
  assert.match(routes, /membership_snapshots\.manage/);
  assert.doesNotMatch(routes, /oauth|creator\/connect|connect\/start/i);
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
