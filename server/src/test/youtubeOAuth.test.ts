import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  FetchLike,
  YouTubeIntegrationError,
  YouTubeRuntimeConfig,
  decryptOAuthCodeVerifier,
  decryptYouTubeSecret,
  encryptYouTubeSecret,
  fetchOwnedYouTubeChannelIds,
  fetchYouTubeMembershipForChannels,
  generateYouTubeOAuthFlow,
  googleProviderSubjectFromFirebaseIdentities,
  loadYouTubeRuntimeConfig,
  sha256Hex,
  verifyGoogleAccountBinding,
  youtubeChannelIdPattern,
  youtubeCreatorMembershipScope,
  youtubeReadonlyScope,
} from '../services/youtubeOAuthService.js';

const creatorChannelId = `UC${'a'.repeat(22)}`;
const memberChannelId = `UC${'b'.repeat(22)}`;

function runtimeConfig(): YouTubeRuntimeConfig {
  return {
    clientId: '123-test.apps.googleusercontent.com',
    clientSecret: 'server-only-client-secret',
    redirectUri: 'https://api.example.test/api/v1/youtube/oauth/callback',
    creatorChannelId,
    tokenEncryptionKey: Buffer.alloc(32, 7),
    membershipRefreshIntervalSeconds: 21600,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

describe('YouTube OAuth security primitives', () => {
  it('accepts only exact YouTube channel IDs', () => {
    assert.equal(youtubeChannelIdPattern.test(creatorChannelId), true);
    assert.equal(youtubeChannelIdPattern.test(`UC${'a'.repeat(21)}`), false);
    assert.equal(youtubeChannelIdPattern.test(`UC${'a'.repeat(23)}`), false);
    assert.equal(youtubeChannelIdPattern.test(`XX${'a'.repeat(22)}`), false);
  });

  it('requires one already-linked Firebase Google provider subject', () => {
    assert.equal(
      googleProviderSubjectFromFirebaseIdentities({
        'google.com': ['google-subject-123'],
      }),
      'google-subject-123',
    );
    assert.equal(
      googleProviderSubjectFromFirebaseIdentities({
        'google.com': ['first', 'second'],
      }),
      null,
    );
    assert.equal(
      googleProviderSubjectFromFirebaseIdentities({ email: ['address'] }),
      null,
    );
  });

  it('aligns runtime validation with the one registered callback and key format', () => {
    const environment: NodeJS.ProcessEnv = {
      NODE_ENV: 'production',
      YOUTUBE_OAUTH_CLIENT_ID: runtimeConfig().clientId,
      YOUTUBE_OAUTH_CLIENT_SECRET: runtimeConfig().clientSecret,
      YOUTUBE_OAUTH_REDIRECT_URI: runtimeConfig().redirectUri,
      YOUTUBE_CREATOR_CHANNEL_ID: creatorChannelId,
      YOUTUBE_TOKEN_ENCRYPTION_KEY:
        runtimeConfig().tokenEncryptionKey.toString('base64'),
      YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS: '21600',
    };
    assert.equal(loadYouTubeRuntimeConfig(environment).creatorChannelId, creatorChannelId);

    assert.throws(
      () => loadYouTubeRuntimeConfig({
        ...environment,
        YOUTUBE_OAUTH_REDIRECT_URI: 'https://api.example.test/other/callback',
      }),
      (error: unknown) => error instanceof YouTubeIntegrationError &&
        error.code === 'youtube_invalid_redirect_uri',
    );
    assert.throws(
      () => loadYouTubeRuntimeConfig({
        ...environment,
        YOUTUBE_TOKEN_ENCRYPTION_KEY: Buffer.alloc(32, 1).toString('hex'),
      }),
      (error: unknown) => error instanceof YouTubeIntegrationError &&
        error.code === 'youtube_invalid_encryption_key',
    );
  });

  it('generates state, nonce, and S256 PKCE without exposing a secret', () => {
    const config = runtimeConfig();
    const memberFlow = generateYouTubeOAuthFlow('member_link', config);
    const url = new URL(memberFlow.authorizationUrl);

    assert.equal(url.searchParams.get('state'), memberFlow.state);
    assert.equal(sha256Hex(memberFlow.state), memberFlow.stateHash);
    assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
    assert.ok(url.searchParams.get('code_challenge'));
    assert.ok(url.searchParams.get('nonce'));
    assert.match(url.searchParams.get('scope') ?? '', /openid/);
    assert.match(url.searchParams.get('scope') ?? '', new RegExp(youtubeReadonlyScope));
    assert.doesNotMatch(
      url.searchParams.get('scope') ?? '',
      new RegExp(youtubeCreatorMembershipScope),
    );
    assert.equal(url.searchParams.has('client_secret'), false);
    assert.equal(url.searchParams.has('code_verifier'), false);
    assert.equal(
      sha256Hex(url.searchParams.get('nonce') ?? ''),
      memberFlow.oidcNonceHash,
    );
    assert.ok(decryptOAuthCodeVerifier(
      memberFlow.flowId,
      memberFlow.pkceVerifierCiphertext,
      config,
    ).length >= 43);

    const creatorFlow = generateYouTubeOAuthFlow('creator_connect', config);
    const creatorUrl = new URL(creatorFlow.authorizationUrl);
    assert.match(
      creatorUrl.searchParams.get('scope') ?? '',
      new RegExp(youtubeCreatorMembershipScope),
    );
    assert.equal(creatorUrl.searchParams.get('access_type'), 'offline');
  });

  it('authenticates encrypted values and rejects tampering or wrong context', () => {
    const key = runtimeConfig().tokenEncryptionKey;
    const ciphertext = encryptYouTubeSecret('refresh-token', key, 'creator');
    assert.equal(
      decryptYouTubeSecret(ciphertext, key, 'creator'),
      'refresh-token',
    );
    assert.throws(() => decryptYouTubeSecret(ciphertext, key, 'other'));
    const parts = ciphertext.split('.');
    const tampered = Buffer.from(parts[3], 'base64url');
    tampered[0] ^= 1;
    parts[3] = tampered.toString('base64url');
    assert.throws(() => decryptYouTubeSecret(parts.join('.'), key, 'creator'));
  });

  it('cryptographically verifies audience then binds subject, expiry, and nonce', async () => {
    const nonce = 'nonce-from-authorize-url';
    const payload = {
      iss: 'https://accounts.google.com',
      sub: 'firebase-google-subject',
      aud: runtimeConfig().clientId,
      exp: 2_000_000_000,
      nonce,
    };
    const audiences: unknown[] = [];
    const verifier = {
      verifyIdToken: async (options: { audience?: unknown }) => {
        audiences.push(options.audience);
        return { getPayload: () => payload };
      },
    } as any;

    assert.equal(
      await verifyGoogleAccountBinding(
        'signed-id-token',
        payload.sub,
        sha256Hex(nonce),
        runtimeConfig(),
        verifier,
        1_900_000_000,
      ),
      payload.sub,
    );
    assert.deepEqual(audiences, [runtimeConfig().clientId]);
    await assert.rejects(
      verifyGoogleAccountBinding(
        'signed-id-token',
        'different-google-subject',
        sha256Hex(nonce),
        runtimeConfig(),
        verifier,
        1_900_000_000,
      ),
      (error: unknown) => error instanceof YouTubeIntegrationError &&
        error.code === 'google_account_mismatch',
    );
  });
});

describe('official YouTube Data API requests', () => {
  it('uses channels.list(mine=true) and keeps the bearer token out of the URL', async () => {
    let requestedUrl: URL | null = null;
    let authorization = '';
    const fetchImpl: FetchLike = async (input, init) => {
      requestedUrl = new URL(input.toString());
      authorization = new Headers(init?.headers).get('Authorization') ?? '';
      return jsonResponse({ items: [{ id: memberChannelId }] });
    };
    const result = await fetchOwnedYouTubeChannelIds(
      'private-user-access-token',
      fetchImpl,
    );

    assert.deepEqual(result, [memberChannelId]);
    assert.equal(requestedUrl!.searchParams.get('mine'), 'true');
    assert.equal(requestedUrl!.searchParams.get('part'), 'id');
    assert.doesNotMatch(requestedUrl!.toString(), /private-user-access-token/);
    assert.equal(authorization, 'Bearer private-user-access-token');
  });

  it('filters members by channel ID and derives current membership fields', async () => {
    let requestedUrl: URL | null = null;
    const fetchImpl: FetchLike = async (input) => {
      requestedUrl = new URL(input.toString());
      return jsonResponse({
        items: [{
          snippet: {
            creatorChannelId,
            memberDetails: { channelId: memberChannelId },
            membershipsDetails: {
              highestAccessibleLevel: 'level-2',
              membershipsDuration: { memberSince: '2026-01-02T03:04:05Z' },
            },
          },
        }],
      });
    };
    const result = await fetchYouTubeMembershipForChannels(
      'private-creator-access-token',
      [memberChannelId],
      creatorChannelId,
      fetchImpl,
    );

    assert.equal(
      requestedUrl!.searchParams.get('filterByMemberChannelId'),
      memberChannelId,
    );
    assert.equal(requestedUrl!.searchParams.get('mode'), 'all_current');
    assert.deepEqual(result, {
      isMember: true,
      channelId: memberChannelId,
      membershipLevelId: 'level-2',
      memberSince: new Date('2026-01-02T03:04:05Z'),
    });
  });
});
