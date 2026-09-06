import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { mapPublicFanProfile } from '../routes/profileRoutes.js';
import { mapPublicLeaderboardEntry } from '../services/leaderboardService.js';
import { activeSubscriptionSql } from '../services/subscriptionAccess.js';

test('subscriber badges are independent from CSV membership on public identities', () => {
  for (const isProSubscriber of [false, true]) {
    for (const isYouTubeMember of [false, true]) {
      const entry = mapPublicLeaderboardEntry({
        publicId: 'fan', username: 'fan', displayName: 'Fan',
        avatarUrl: null, supportedTeam: 'Barcelona',
        isYouTubeMember, isProSubscriber,
        points: 15, rank: 1, totalPlayers: 1,
      });
      const profile = mapPublicFanProfile({
        username: 'fan', display_name: 'Fan', avatar_url: null,
        supported_team: 'Barcelona', supported_team_logo: null,
        country: null, country_code: null,
        is_youtube_member: isYouTubeMember,
        is_pro_subscriber: isProSubscriber,
        total_points: 15, monthly_points: 15, season_points: 15,
        loyalty_points: 0, streak_count: 1, streak_best: 1, level: 1,
        exact_predictions_count: 0, challenges_completed_count: 0,
        player_cards_collected_count: 0,
      });

      for (const identity of [entry, profile]) {
        assert.equal(identity.isProSubscriber, isProSubscriber);
        assert.equal(identity.isYouTubeMember, isYouTubeMember);
        for (const privateField of [
          'productId', 'expiresAt', 'verifiedAt', 'willRenew',
          'isSandbox', 'entitlements', 'subscription',
        ]) {
          assert.equal(privateField in identity, false);
        }
      }
    }
  }
});

test('badge lookup uses the same unexpired, recently verified entitlement as access checks', () => {
  const sql = activeSubscriptionSql('u.id');
  assert.match(sql, /subscription_access\.user_id = u\.id/);
  assert.match(sql, /entitlement_id = 'abu_3meer_pro'/);
  assert.match(sql, /is_active = TRUE/);
  assert.match(sql, /expires_at > clock_timestamp\(\)/);
  assert.match(sql, /verified_at > clock_timestamp\(\) - INTERVAL '24 hours'/);
  assert.match(sql, /is_sandbox = FALSE/);
  assert.doesNotMatch(sql, /youtube|member_since|user_roles/);
  assert.throws(() => activeSubscriptionSql('u.id; SELECT 1'));
});

test('all current public profile, leaderboard, and staff user-list queries expose verified badge state', async () => {
  for (const file of [
    'services/leaderboardService.ts',
    'routes/profileRoutes.ts',
    'routes/adminRoutes.ts',
  ]) {
    const source = await readFile(path.resolve(process.cwd(), 'src', file), 'utf8');
    assert.match(source, /activeSubscriptionSql\('u\.id'\).*AS is_pro_subscriber/);
    assert.match(source, /isProSubscriber: row\.(?:isProSubscriber|is_pro_subscriber) === true/);
  }
});

test('points-audit labels receive current verified badge state in the existing joined query', async () => {
  const source = await readFile(
    path.resolve(process.cwd(), 'src/routes/adminRoutes.ts'),
    'utf8',
  );
  for (const role of ['admin', 'target']) {
    assert.ok(source.includes(`activeSubscriptionSql('${role}.id')} AS ${role}_is_pro_subscriber`));
    assert.ok(source.includes(`${role}IsProSubscriber: row.${role}_is_pro_subscriber === true`));
  }
});
