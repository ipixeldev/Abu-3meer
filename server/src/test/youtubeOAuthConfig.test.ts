import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { loadYouTubeOAuthConfig } from '../youtubeOAuthConfig.js';

function completeEnvironment(): NodeJS.ProcessEnv {
  return {
    YOUTUBE_OAUTH_CLIENT_ID:
      '000000000000-testclient.apps.googleusercontent.com',
    YOUTUBE_OAUTH_CLIENT_SECRET: 'test-client-secret-not-a-real-credential',
    YOUTUBE_OAUTH_REDIRECT_URI:
      'https://api.example.test/api/v1/youtube/oauth/callback',
    YOUTUBE_CREATOR_CHANNEL_ID: `UC${'a'.repeat(22)}`,
    YOUTUBE_TOKEN_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
    YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS: '21600',
  };
}

describe('YouTube creator OAuth configuration', () => {
  it('stays bootable and reports only missing variable names when unconfigured', () => {
    const result = loadYouTubeOAuthConfig({});

    assert.equal(result.configured, false);
    assert.equal(result.status.state, 'credentials_required');
    assert.deepEqual(
      result.status.issues.map(issue => issue.variable),
      [
        'YOUTUBE_OAUTH_CLIENT_ID',
        'YOUTUBE_OAUTH_CLIENT_SECRET',
        'YOUTUBE_OAUTH_REDIRECT_URI',
        'YOUTUBE_CREATOR_CHANNEL_ID',
        'YOUTUBE_TOKEN_ENCRYPTION_KEY',
      ],
    );
    assert.equal(result.membershipRefreshIntervalSeconds, 21600);
  });

  it('accepts a complete HTTPS, channel-bound, AES-256 configuration', () => {
    const result = loadYouTubeOAuthConfig(completeEnvironment());

    assert.equal(result.configured, true);
    assert.deepEqual(result.status, { state: 'configured', issues: [] });
    assert.equal(result.membershipRefreshIntervalSeconds, 21600);
  });

  it('rejects unsafe formats without including their values in status output', () => {
    const environment = completeEnvironment();
    environment.YOUTUBE_OAUTH_CLIENT_ID = 'private-client-id';
    environment.YOUTUBE_OAUTH_REDIRECT_URI =
      'http://private.example.test/callback?secret=value';
    environment.YOUTUBE_CREATOR_CHANNEL_ID = 'private-channel';
    environment.YOUTUBE_TOKEN_ENCRYPTION_KEY = 'private-token-key';
    environment.YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS = '30';

    const result = loadYouTubeOAuthConfig(environment);
    const safeStatus = JSON.stringify(result.status);

    assert.equal(result.configured, false);
    assert.equal(result.status.issues.length, 5);
    assert.doesNotMatch(
      safeStatus,
      /private|example|callback|secret=value|token-key/i,
    );
  });

  it('requires the one callback path registered with Google Cloud', () => {
    const environment = completeEnvironment();
    environment.YOUTUBE_OAUTH_REDIRECT_URI =
      'https://api.example.test/api/v1/admin/youtube/oauth/callback';

    const result = loadYouTubeOAuthConfig(environment);

    assert.equal(result.configured, false);
    assert.deepEqual(result.status.issues, [{
      variable: 'YOUTUBE_OAUTH_REDIRECT_URI',
      reason: 'invalid',
    }]);
  });
});
