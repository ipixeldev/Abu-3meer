import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  PostgresYouTubeMembershipStore,
  StoredCreatorCredential,
  StoredYouTubeAccountLink,
  StoredYouTubeFlowStatus,
  StoredYouTubeOAuthFlow,
  StoredStaleYouTubeAccountLink,
  YouTubeMembershipStore,
  getYouTubeOAuthFlowStatus,
  handleYouTubeOAuthCallback,
  refreshStaleLinkedYouTubeMembership,
  refreshStaleYouTubeMembershipsForUsers,
  startYouTubeOAuthFlow,
} from '../services/youtubeMembershipService.js';
import {
  FetchLike,
  YouTubeIntegrationError,
  YouTubeOAuthPurpose,
  YouTubeRuntimeConfig,
  encryptCreatorRefreshToken,
  generateYouTubeOAuthFlow,
  googleOpenIdScope,
  youtubeCreatorMembershipScope,
  youtubeReadonlyScope,
} from '../services/youtubeOAuthService.js';

const creatorChannelId = `UC${'c'.repeat(22)}`;
const memberChannelId = `UC${'m'.repeat(22)}`;
const otherChannelId = `UC${'o'.repeat(22)}`;
const now = new Date('2026-09-01T12:00:00Z');

function config(): YouTubeRuntimeConfig {
  return {
    clientId: '123-test.apps.googleusercontent.com',
    clientSecret: 'server-client-secret',
    redirectUri: 'https://api.example.test/api/v1/youtube/oauth/callback',
    creatorChannelId,
    tokenEncryptionKey: Buffer.alloc(32, 9),
    membershipRefreshIntervalSeconds: 21600,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

class FakeStore implements YouTubeMembershipStore {
  created: Parameters<YouTubeMembershipStore['createOAuthFlow']>[0][] = [];
  consumed: StoredYouTubeOAuthFlow | null = null;
  completions: Array<{
    flowId: string;
    status: string;
    errorCode: string | null | undefined;
    channelId: string | null | undefined;
  }> = [];
  flowStatus: StoredYouTubeFlowStatus | null = null;
  credential: StoredCreatorCredential | null = null;
  savedCredentials: Parameters<YouTubeMembershipStore['saveCreatorCredential']>[0][] = [];
  link: StoredYouTubeAccountLink | null = null;
  staleLinks: StoredStaleYouTubeAccountLink[] = [];
  staleBefore: Date | null = null;
  applied: Parameters<YouTubeMembershipStore['applyMembershipVerification']>[0][] = [];
  verificationFailures: Array<{
    userId: string;
    errorCode: string;
    attemptedAt: Date;
    expectedLastVerifiedAt?: Date;
  }> = [];
  requestedStatusOwner: string | null = null;

  async createOAuthFlow(
    input: Parameters<YouTubeMembershipStore['createOAuthFlow']>[0],
  ) {
    this.created.push(input);
  }

  async consumeOAuthFlow(_stateHash: string) {
    return this.consumed;
  }

  async completeOAuthFlow(
    flowId: string,
    status: Parameters<YouTubeMembershipStore['completeOAuthFlow']>[1],
    errorCode?: string | null,
    youtubeChannelId?: string | null,
  ) {
    this.completions.push({
      flowId,
      status,
      errorCode,
      channelId: youtubeChannelId,
    });
  }

  async getOAuthFlowStatus(
    _flowId: string,
    requestedByUserId: string,
    _purpose: YouTubeOAuthPurpose,
  ) {
    this.requestedStatusOwner = requestedByUserId;
    return this.flowStatus;
  }

  async saveCreatorCredential(
    input: Parameters<YouTubeMembershipStore['saveCreatorCredential']>[0],
  ) {
    this.savedCredentials.push(input);
    this.credential = {
      creatorChannelId: input.creatorChannelId,
      refreshTokenCiphertext: input.refreshTokenCiphertext,
      authorizedAt: now,
    };
    if (input.completedOAuthFlowId) {
      this.completions.push({
        flowId: input.completedOAuthFlowId,
        status: 'connected',
        errorCode: null,
        channelId: input.creatorChannelId,
      });
    }
  }

  async getCreatorCredential() {
    return this.credential;
  }

  async getYouTubeAccountLink(_userId: string) {
    return this.link;
  }

  async getStaleYouTubeAccountLinks(userIds: string[], staleBefore: Date) {
    this.staleBefore = staleBefore;
    const requested = new Set(userIds);
    return this.staleLinks.filter((link) => requested.has(link.userId));
  }

  async applyMembershipVerification(
    input: Parameters<YouTubeMembershipStore['applyMembershipVerification']>[0],
  ) {
    this.applied.push(input);
    this.link = {
      youtubeChannelId: input.youtubeChannelId,
      isMember: input.lookup.isMember,
      membershipLevelId: input.lookup.membershipLevelId,
      memberSince: input.lookup.memberSince,
      lastVerifiedAt: input.verifiedAt,
    };
    if (input.completedOAuthFlow) {
      this.completions.push({
        flowId: input.completedOAuthFlow.flowId,
        status: input.completedOAuthFlow.status,
        errorCode: null,
        channelId: input.youtubeChannelId,
      });
    }
  }

  async recordMembershipVerificationFailure(
    userId: string,
    errorCode: string,
    attemptedAt: Date,
    expectedLastVerifiedAt?: Date,
  ) {
    this.verificationFailures.push({
      userId,
      errorCode,
      attemptedAt,
      expectedLastVerifiedAt,
    });
  }
}

function storedFlow(
  purpose: YouTubeOAuthPurpose,
  expectedGoogleSubject: string | null,
) {
  const generated = generateYouTubeOAuthFlow(purpose, config());
  return {
    generated,
    stored: {
      id: generated.flowId,
      purpose,
      requestedByUserId: 'user-1',
      expectedGoogleSubject,
      pkceVerifierCiphertext: generated.pkceVerifierCiphertext,
      oidcNonceHash: generated.oidcNonceHash,
    } satisfies StoredYouTubeOAuthFlow,
  };
}

function idTokenVerifier(subject: string, nonce: string) {
  return {
    verifyIdToken: async () => ({
      getPayload: () => ({
        iss: 'https://accounts.google.com',
        sub: subject,
        exp: 2_000_000_000,
        nonce,
      }),
    }),
  } as any;
}

function batchChannelId(index: number): string {
  return `UC${index.toString(36).padStart(22, '0')}`;
}

function staleBatchLink(index: number): StoredStaleYouTubeAccountLink {
  return {
    userId: `user-${index}`,
    youtubeChannelId: batchChannelId(index),
    isMember: true,
    membershipLevelId: 'old-level',
    memberSince: new Date('2026-01-01T00:00:00Z'),
    lastVerifiedAt: new Date(now.getTime() - 24 * 60 * 60 * 1000),
  };
}

describe('YouTube account-link OAuth orchestration', () => {
  it('requires Google to already be linked in the verified Firebase token', async () => {
    const store = new FakeStore();
    await assert.rejects(
      startYouTubeOAuthFlow(
        { requestedByUserId: 'user-1', purpose: 'member_link' },
        { store, config: config(), now },
      ),
      (error: unknown) => error instanceof YouTubeIntegrationError &&
        error.code === 'google_account_link_required',
    );
    assert.equal(store.created.length, 0);
  });

  it('stores only hashed state and encrypted PKCE while returning an opaque flow ID', async () => {
    const store = new FakeStore();
    const result = await startYouTubeOAuthFlow(
      {
        requestedByUserId: 'user-1',
        purpose: 'member_link',
        expectedGoogleSubject: 'linked-google-subject',
      },
      { store, config: config(), now },
    );

    assert.equal(store.created.length, 1);
    assert.equal(store.created[0].id, result.flowId);
    assert.match(store.created[0].stateHash, /^[a-f0-9]{64}$/);
    assert.match(store.created[0].pkceVerifierCiphertext, /^v1\./);
    assert.doesNotMatch(
      JSON.stringify(store.created[0]),
      /server-client-secret/,
    );
    assert.equal(new URL(result.authorizationUrl).searchParams.has('client_secret'), false);
  });

  it('consumes an OAuth denial safely without making a Google request', async () => {
    const store = new FakeStore();
    const flow = storedFlow('member_link', 'linked-google-subject');
    store.consumed = flow.stored;
    let fetchCalls = 0;

    const result = await handleYouTubeOAuthCallback(
      { state: flow.generated.state, error: 'access_denied' },
      {
        store,
        config: config(),
        now,
        fetchImpl: async () => {
          fetchCalls += 1;
          throw new Error('must not be called');
        },
      },
    );

    assert.deepEqual(result, { status: 'error' });
    assert.equal(fetchCalls, 0);
    assert.deepEqual(store.completions[0], {
      flowId: flow.generated.flowId,
      status: 'error',
      errorCode: 'oauth_authorization_denied',
      channelId: undefined,
    });
  });

  it('checks the signed Google subject before requesting owned channels', async () => {
    const store = new FakeStore();
    const flow = storedFlow('member_link', 'linked-google-subject');
    store.consumed = flow.stored;
    let fetchCalls = 0;
    const fetchImpl: FetchLike = async () => {
      fetchCalls += 1;
      return jsonResponse({
        access_token: 'short-lived-user-token',
        id_token: 'signed-id-token',
        scope: `${googleOpenIdScope} ${youtubeReadonlyScope}`,
      });
    };

    const result = await handleYouTubeOAuthCallback(
      { state: flow.generated.state, code: 'one-time-code' },
      {
        store,
        config: config(),
        now,
        fetchImpl,
        idTokenVerifier: idTokenVerifier(
          'different-google-subject',
          new URL(flow.generated.authorizationUrl).searchParams.get('nonce')!,
        ),
      },
    );

    assert.deepEqual(result, { status: 'error' });
    assert.equal(fetchCalls, 1, 'only the OAuth code exchange may run');
    assert.equal(store.applied.length, 0);
    assert.equal(store.verificationFailures.length, 0);
    assert.equal(store.completions[0].errorCode, 'google_account_mismatch');
  });

  it('verifies membership using the bound channel without storing user tokens', async () => {
    const store = new FakeStore();
    const flow = storedFlow('member_link', 'linked-google-subject');
    store.consumed = flow.stored;
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'encrypted-at-rest-creator-refresh',
        config(),
      ),
      authorizedAt: now,
    };
    const nonce = new URL(flow.generated.authorizationUrl).searchParams.get('nonce')!;
    const fetchImpl: FetchLike = async (input, init) => {
      const url = new URL(input.toString());
      if (url.hostname === 'oauth2.googleapis.com') {
        const body = new URLSearchParams(String(init?.body ?? ''));
        if (body.get('grant_type') === 'authorization_code') {
          return jsonResponse({
            access_token: 'short-lived-user-token',
            id_token: 'signed-id-token',
            scope: `${googleOpenIdScope} ${youtubeReadonlyScope}`,
          });
        }
        return jsonResponse({ access_token: 'short-lived-creator-token' });
      }
      if (url.pathname.endsWith('/channels')) {
        return jsonResponse({ items: [{ id: memberChannelId }] });
      }
      return jsonResponse({
        items: [{
          snippet: {
            creatorChannelId,
            memberDetails: { channelId: memberChannelId },
            membershipsDetails: {
              highestAccessibleLevel: 'gold',
              membershipsDuration: { memberSince: '2026-01-01T00:00:00Z' },
            },
          },
        }],
      });
    };

    const result = await handleYouTubeOAuthCallback(
      { state: flow.generated.state, code: 'one-time-code' },
      {
        store,
        config: config(),
        now,
        fetchImpl,
        idTokenVerifier: idTokenVerifier('linked-google-subject', nonce),
      },
    );

    assert.deepEqual(result, { status: 'verified' });
    assert.equal(store.applied.length, 1);
    assert.equal(store.applied[0].youtubeChannelId, memberChannelId);
    assert.equal(store.applied[0].lookup.isMember, true);
    assert.equal(store.completions[0].status, 'verified');
    assert.doesNotMatch(
      JSON.stringify({ applied: store.applied, completions: store.completions }),
      /short-lived-user-token|signed-id-token|one-time-code/,
    );
  });

  it('requires the creator OAuth account to own the configured channel', async () => {
    const store = new FakeStore();
    const flow = storedFlow('creator_connect', null);
    store.consumed = flow.stored;
    const fetchImpl: FetchLike = async (input) => {
      const url = new URL(input.toString());
      if (url.hostname === 'oauth2.googleapis.com') {
        return jsonResponse({
          access_token: 'short-lived-creator-token',
          refresh_token: 'creator-refresh-token',
          id_token: 'creator-id-token',
          scope: `${googleOpenIdScope} ${youtubeReadonlyScope} ${youtubeCreatorMembershipScope}`,
        });
      }
      return jsonResponse({ items: [{ id: otherChannelId }] });
    };

    const result = await handleYouTubeOAuthCallback(
      { state: flow.generated.state, code: 'one-time-code' },
      { store, config: config(), now, fetchImpl },
    );

    assert.deepEqual(result, { status: 'error' });
    assert.equal(store.savedCredentials.length, 0);
    assert.equal(store.completions[0].errorCode, 'creator_channel_mismatch');
  });

  it('polls a flow only through its authenticated owner', async () => {
    const store = new FakeStore();
    store.flowStatus = {
      status: 'verified',
      errorCode: null,
      youtubeChannelId: memberChannelId,
      expiresAt: new Date(now.getTime() + 60_000),
    };
    const result = await getYouTubeOAuthFlowStatus(
      {
        flowId: 'a5b0ec99-0799-46a1-bbc3-579d791d2aac',
        requestedByUserId: 'authenticated-owner',
        purpose: 'member_link',
      },
      store,
      now,
    );
    assert.equal(store.requestedStatusOwner, 'authenticated-owner');
    assert.deepEqual(result, { status: 'verified', isYouTubeMember: true });
  });
});

describe('membership freshness enforcement', () => {
  it('returns a fresh cached verification without using Google quota', async () => {
    const store = new FakeStore();
    store.link = {
      youtubeChannelId: memberChannelId,
      isMember: true,
      membershipLevelId: 'gold',
      memberSince: new Date('2026-01-01T00:00:00Z'),
      lastVerifiedAt: new Date(now.getTime() - 60_000),
    };
    const result = await refreshStaleLinkedYouTubeMembership('user-1', {
      store,
      config: config(),
      now,
      fetchImpl: async () => {
        throw new Error('must not be called');
      },
    });
    assert.equal(result?.cached, true);
    assert.equal(result?.isYouTubeMember, true);
  });

  it('refreshes a stale link and transactionally revokes cancelled membership', async () => {
    const store = new FakeStore();
    store.link = {
      youtubeChannelId: memberChannelId,
      isMember: true,
      membershipLevelId: 'gold',
      memberSince: new Date('2026-01-01T00:00:00Z'),
      lastVerifiedAt: new Date(now.getTime() - 24 * 60 * 60 * 1000),
    };
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'creator-refresh-token',
        config(),
      ),
      authorizedAt: now,
    };
    const fetchImpl: FetchLike = async (input) => {
      const url = new URL(input.toString());
      return url.hostname === 'oauth2.googleapis.com'
        ? jsonResponse({ access_token: 'short-lived-creator-token' })
        : jsonResponse({ items: [] });
    };

    const result = await refreshStaleLinkedYouTubeMembership('user-1', {
      store,
      config: config(),
      now,
      fetchImpl,
    });

    assert.deepEqual(result, {
      status: 'not_member',
      isYouTubeMember: false,
      cached: false,
      verifiedAt: now.toISOString(),
    });
    assert.equal(store.applied.length, 1);
    assert.equal(store.link?.isMember, false);
  });

  it('records a failed attempt without replacing the last successful result', async () => {
    const store = new FakeStore();
    store.link = {
      youtubeChannelId: memberChannelId,
      isMember: true,
      membershipLevelId: 'gold',
      memberSince: new Date('2026-01-01T00:00:00Z'),
      lastVerifiedAt: new Date(now.getTime() - 24 * 60 * 60 * 1000),
    };
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'creator-refresh-token',
        config(),
      ),
      authorizedAt: now,
    };

    await assert.rejects(
      refreshStaleLinkedYouTubeMembership('user-1', {
        store,
        config: config(),
        now,
        fetchImpl: async () => jsonResponse({ error: 'invalid_grant' }, 400),
      }),
      (error: unknown) => error instanceof YouTubeIntegrationError &&
        error.code === 'creator_reauthorization_required',
    );
    assert.equal(store.verificationFailures.length, 1);
    assert.equal(store.link?.isMember, true);
    assert.equal(
      store.link?.lastVerifiedAt.toISOString(),
      new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString(),
    );
    assert.equal(
      store.verificationFailures[0].expectedLastVerifiedAt?.toISOString(),
      store.link?.lastVerifiedAt.toISOString(),
    );
  });

  it('does not grant stale membership when another process owns the refresh lock', async () => {
    const store = new FakeStore();
    store.link = {
      youtubeChannelId: memberChannelId,
      isMember: true,
      membershipLevelId: null,
      memberSince: null,
      lastVerifiedAt: new Date(now.getTime() - 24 * 60 * 60 * 1000),
    };
    let workRan = false;
    const result = await refreshStaleLinkedYouTubeMembership('user-1', {
      store,
      config: config(),
      now,
      withRefreshLock: async () => {
        workRan = true;
        return null;
      },
    });
    assert.equal(result, null);
    assert.equal(workRan, true);
    assert.equal(store.applied.length, 0);
  });

  it('batch-refreshes 205 users with one token exchange and three members.list calls', async () => {
    const store = new FakeStore();
    store.staleLinks = Array.from({ length: 205 }, (_, index) =>
      staleBatchLink(index));
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'creator-refresh-token',
        config(),
      ),
      authorizedAt: now,
    };
    let tokenRequests = 0;
    const membershipBatchSizes: number[] = [];
    const fetchImpl: FetchLike = async (input) => {
      const url = new URL(input.toString());
      if (url.hostname === 'oauth2.googleapis.com') {
        tokenRequests += 1;
        return jsonResponse({ access_token: 'one-short-lived-creator-token' });
      }
      const channels = (url.searchParams.get('filterByMemberChannelId') ?? '')
        .split(',')
        .filter(Boolean);
      membershipBatchSizes.push(channels.length);
      return jsonResponse({
        items: channels
          .filter((_, index) => index % 2 === 0)
          .map((channelId) => ({
            snippet: {
              creatorChannelId,
              memberDetails: { channelId },
              membershipsDetails: {
                highestAccessibleLevel: 'current-level',
                membershipsDuration: { memberSince: '2026-02-01T00:00:00Z' },
              },
            },
          })),
      });
    };

    const result = await refreshStaleYouTubeMembershipsForUsers(
      [
        ...store.staleLinks.map((link) => link.userId),
        store.staleLinks[0].userId,
      ],
      { store, config: config(), now, fetchImpl },
    );

    assert.equal(tokenRequests, 1);
    assert.deepEqual(membershipBatchSizes, [100, 100, 5]);
    assert.equal(result.requestedUsers, 205);
    assert.equal(result.staleLinkedUsers, 205);
    assert.equal(result.membershipApiRequests, 3);
    assert.equal(result.verified + result.notMember, 205);
    assert.equal(result.unavailable, 0);
    assert.equal(store.applied.length, 205);
    assert.equal(store.applied.every((update) =>
      update.expectedLastVerifiedAt?.getTime() ===
        store.staleLinks[0].lastVerifiedAt.getTime()), true);
  });

  it('records one unavailable batch and continues with later batches', async () => {
    const store = new FakeStore();
    store.staleLinks = Array.from({ length: 105 }, (_, index) =>
      staleBatchLink(index));
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'creator-refresh-token',
        config(),
      ),
      authorizedAt: now,
    };
    let membershipRequests = 0;
    const fetchImpl: FetchLike = async (input) => {
      const url = new URL(input.toString());
      if (url.hostname === 'oauth2.googleapis.com') {
        return jsonResponse({ access_token: 'short-lived-creator-token' });
      }
      membershipRequests += 1;
      return membershipRequests === 1
        ? jsonResponse({ error: { errors: [{ reason: 'backendError' }] } }, 503)
        : jsonResponse({ items: [] });
    };

    const result = await refreshStaleYouTubeMembershipsForUsers(
      store.staleLinks.map((link) => link.userId),
      { store, config: config(), now, fetchImpl },
    );

    assert.equal(result.membershipApiRequests, 2);
    assert.equal(result.unavailable, 100);
    assert.equal(result.notMember, 5);
    assert.equal(store.verificationFailures.length, 100);
    assert.equal(store.applied.length, 5);
    assert.equal(store.verificationFailures.every((update) =>
      update.expectedLastVerifiedAt?.getTime() ===
        store.staleLinks[0].lastVerifiedAt.getTime()), true);
  });

  it('marks all stale snapshots unavailable when the creator token cannot refresh', async () => {
    const store = new FakeStore();
    store.staleLinks = [staleBatchLink(1), staleBatchLink(2)];
    store.credential = {
      creatorChannelId,
      refreshTokenCiphertext: encryptCreatorRefreshToken(
        'creator-refresh-token',
        config(),
      ),
      authorizedAt: now,
    };
    const result = await refreshStaleYouTubeMembershipsForUsers(
      store.staleLinks.map((link) => link.userId),
      {
        store,
        config: config(),
        now,
        fetchImpl: async () => jsonResponse({ error: 'invalid_grant' }, 400),
      },
    );
    assert.equal(result.unavailable, 2);
    assert.equal(result.membershipApiRequests, 0);
    assert.equal(store.verificationFailures.length, 2);
    assert.equal(store.applied.length, 0);
  });

  it('keeps route paths/status contracts and prediction settlement freshness-aware', async () => {
    const routes = await readFile(
      path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
      'utf8',
    );
    const predictions = await readFile(
      path.resolve(process.cwd(), 'src/services/predictionService.ts'),
      'utf8',
    );
    assert.match(routes, /'\/profile\/youtube\/connect\/start'/);
    assert.match(routes, /'\/profile\/youtube\/connect\/:flowId\/status'/);
    assert.match(routes, /'\/admin\/youtube\/creator\/status'/);
    assert.match(routes, /'\/admin\/youtube\/creator\/connect\/start'/);
    assert.match(routes, /'\/admin\/youtube\/creator\/connect\/:flowId\/status'/);
    assert.match(routes, /'\/youtube\/oauth\/callback'/);
    assert.match(predictions, /yl\.last_verified_at >=/);
    assert.match(predictions, /refreshStaleYouTubeMembershipsForUsers\(/);
    assert.match(predictions, /membershipRefresh\.unavailable > 0/);
    assert.match(
      predictions,
      /memberMultiplierForSource\(\s*component\.sourceType,\s*pred\.is_youtube_member,/,
    );
  });

  it('keeps membership authority in OAuth links instead of manual admin flags', async () => {
    const profileRoutes = await readFile(
      path.resolve(process.cwd(), 'src/routes/profileRoutes.ts'),
      'utf8',
    );
    const adminRoutes = await readFile(
      path.resolve(process.cwd(), 'src/routes/adminRoutes.ts'),
      'utf8',
    );
    const auth = await readFile(
      path.resolve(process.cwd(), 'src/middleware/auth.ts'),
      'utf8',
    );
    assert.doesNotMatch(profileRoutes, /admin\/users\/:id\/membership/);
    assert.doesNotMatch(profileRoutes, /membership\.update/);
    assert.match(
      adminRoutes,
      /adminAssignableRoles = \['fan', 'moderator', 'admin', 'super_admin'\]/,
    );
    assert.match(adminRoutes, /role_id <> 'member'/);
    assert.match(adminRoutes, /youtubeMembershipLastAttemptedAt/);
    assert.match(adminRoutes, /youtubeMembershipErrorCode/);
    assert.doesNotMatch(auth, /refreshStaleLinkedYouTubeMembership/);
    assert.match(auth, /yl\.last_verified_at >=/);
  });

  it('uses a PostgreSQL advisory lock in the production store path', async () => {
    const source = await readFile(
      path.resolve(process.cwd(), 'src/services/youtubeMembershipService.ts'),
      'utf8',
    );
    assert.match(source, /pg_try_advisory_lock\(hashtextextended/);
    assert.match(source, /pg_advisory_unlock\(hashtextextended/);
    assert.ok(PostgresYouTubeMembershipStore);
  });
});
