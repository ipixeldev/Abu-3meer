import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { mapPublicFanProfile } from '../routes/profileRoutes.js';
import { mapPublicLeaderboardEntry } from '../services/leaderboardService.js';
import {
  redactRequestUrl,
  serializeRequestForLog,
} from '../security/logRedaction.js';

describe('Public API privacy boundaries', () => {
  it('uses the public username handle without returning internal identities', () => {
    const entry = mapPublicLeaderboardEntry({
      publicId: 'fan_handle',
      username: 'fan_handle',
      displayName: 'Fan',
      avatarUrl: null,
      supportedTeam: 'Real Madrid',
      isYouTubeMember: false,
      points: 85,
      rank: 4,
      totalPlayers: 42,
    });

    assert.equal(entry.userId, 'fan_handle');
    assert.equal(entry.publicId, 'fan_handle');
    assert.equal('firebaseUid' in entry, false);
    assert.equal('databaseUserId' in entry, false);
  });

  it('keeps released profile clients compatible without leaking IDs or activity timestamps', () => {
    const profile = mapPublicFanProfile({
      username: 'fan_handle',
      display_name: 'Fan',
      avatar_url: null,
      supported_team: 'Real Madrid',
      supported_team_logo: null,
      country: 'Morocco',
      country_code: 'MA',
      is_youtube_member: false,
      total_points: 100,
      monthly_points: 40,
      season_points: 60,
      loyalty_points: 0,
      streak_count: 2,
      streak_best: 5,
      level: 1,
      exact_predictions_count: 3,
      challenges_completed_count: 4,
      player_cards_collected_count: 2,
    });

    assert.equal(profile.id, 'fan_handle');
    assert.equal(profile.publicId, 'fan_handle');
    assert.equal('firebaseUid' in profile, false);
    assert.equal('streakLastCheckIn' in profile, false);
    assert.equal('streakExpiresAt' in profile, false);
  });
});

describe('Request log privacy', () => {
  it('drops all query values before a URL reaches logs', () => {
    const raw = '/api/v1/admin/users?q=private%40example.com&role=fan';
    const redacted = redactRequestUrl(raw);

    assert.equal(redacted, '/api/v1/admin/users');
    assert.doesNotMatch(redacted, /private|example|role|fan/i);
  });

  it('does not serialize client IP addresses', () => {
    const request = {
      id: 'request-1',
      method: 'GET',
      url: '/api/v1/football/teams/search?q=private-search',
      ip: '203.0.113.99',
    };
    const serialized = serializeRequestForLog(request);

    assert.deepEqual(serialized, {
      id: 'request-1',
      method: 'GET',
      url: '/api/v1/football/teams/search',
    });
    assert.doesNotMatch(JSON.stringify(serialized), /203\.0\.113\.99|private-search/);
  });

  it('replaces a sensitive public-profile identifier with the route placeholder', () => {
    for (const raw of [
      '/api/v1/profile/firebase-secret-uid',
      '/api/v1/profile/private%40example.com?from=leaderboard',
      '/api/v1/profile/4bff16c1-b990-4a3f-8129-f42eafb120a8#fan',
    ]) {
      const redacted = redactRequestUrl(raw);
      assert.equal(redacted, '/api/v1/profile/:id');
      assert.doesNotMatch(
        redacted,
        /firebase-secret|private|example|4bff16c1|leaderboard|fan/i,
      );
    }
  });

  it('preserves static profile operations and unrelated operational routes', () => {
    for (const safePath of [
      '/api/v1/profile/me',
      '/api/v1/profile/point-history',
      '/api/v1/profile/team',
      '/api/v1/leaderboard/monthly',
      '/health',
      '/ready',
    ]) {
      assert.equal(redactRequestUrl(safePath), safePath);
    }
  });
});
