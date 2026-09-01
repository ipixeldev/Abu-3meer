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
  generateYouTubeOAuthFlow,
  googleOpenIdScope,
  youtubeReadonlyScope,
} from '../services/youtubeOAuthService.js';
import {
  ParsedYouTubeMembershipSnapshotRow,
  YouTubeMembershipSnapshotMetadata,
  YouTubeMembershipSnapshotStore,
} from '../services/youtubeMembershipSnapshotService.js';

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

class FakeSnapshotStore implements YouTubeMembershipSnapshotStore {
  constructor(
    readonly metadata: YouTubeMembershipSnapshotMetadata | null,
    readonly members: ParsedYouTubeMembershipSnapshotRow[] = [],
  ) {}

  async replaceSnapshot(
    _input: Parameters<YouTubeMembershipSnapshotStore['replaceSnapshot']>[0],
  ): Promise<YouTubeMembershipSnapshotMetadata> {
    throw new Error('not used');
  }

  async getActiveMetadata() {
    return this.metadata;
  }

  async getMembers(_importId: string, channelIds: string[]) {
    const requested = new Set(channelIds);
    return this.members.filter((member) =>
      requested.has(member.youtubeChannelId));
  }
}

function activeSnapshotStore(
  members: ParsedYouTubeMembershipSnapshotRow[] = [],
  activatedAt = now,
) {
  return new FakeSnapshotStore({
    importId: '94f5ff5f-e5c7-4540-a557-609641631008',
    sourceFilename: 'members.csv',
    sourceFormat: 'csv',
    sourceSha256: 'a'.repeat(64),
    memberCount: members.length,
    matchedUserCount: 0,
    activatedAt,
  }, members);
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

  it('links as a fan when no CSV snapshot exists and never calls members.list', async () => {
    const store = new FakeStore();
    const flow = storedFlow('member_link', 'linked-google-subject');
    store.consumed = flow.stored;
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
        throw new Error('creator token must not be requested');
      }
      if (url.pathname.endsWith('/channels')) {
        return jsonResponse({ items: [{ id: memberChannelId }] });
      }
      throw new Error('members.list must not be called');
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

    assert.deepEqual(result, { status: 'not_member' });
    assert.equal(store.applied.length, 1);
    assert.equal(store.applied[0].lookup.isMember, false);
    assert.equal(store.completions[0].status, 'not_member');
    assert.doesNotMatch(
      JSON.stringify({ applied: store.applied, completions: store.completions }),
      /short-lived-user-token|signed-id-token|one-time-code/,
    );
  });

  it('links the OAuth-owned channel through an active snapshot while creator OAuth is disconnected', async () => {
    const store = new FakeStore();
    const flow = storedFlow('member_link', 'linked-google-subject');
    store.consumed = flow.stored;
    // Intentionally leave store.credential null: creator OAuth is disconnected.
    const snapshotStore = new FakeSnapshotStore(
      {
        importId: '94f5ff5f-e5c7-4540-a557-609641631008',
        sourceFilename: 'members.csv',
        sourceFormat: 'csv',
        sourceSha256: 'a'.repeat(64),
        memberCount: 1,
        matchedUserCount: 0,
        activatedAt: now,
      },
      [{
        youtubeChannelId: memberChannelId,
        membershipLevel: 'المستوى الذهبي',
        totalTimeOnLevelMonths: 2,
        totalTimeAsMemberMonths: 8,
        sourceLastUpdate: null,
        sourceLastUpdateAt: null,
      }],
    );
    const nonce = new URL(flow.generated.authorizationUrl)
      .searchParams.get('nonce')!;
    const fetchImpl: FetchLike = async (input, init) => {
      const url = new URL(input.toString());
      if (url.hostname === 'oauth2.googleapis.com') {
        const body = new URLSearchParams(String(init?.body ?? ''));
        assert.equal(body.get('grant_type'), 'authorization_code');
        return jsonResponse({
          access_token: 'short-lived-user-token',
          id_token: 'signed-id-token',
          scope: `${googleOpenIdScope} ${youtubeReadonlyScope}`,
        });
      }
      if (url.pathname.endsWith('/channels')) {
        return jsonResponse({ items: [{ id: memberChannelId }] });
      }
      throw new Error('creator members API must not be called');
    };

    const result = await handleYouTubeOAuthCallback(
      { state: flow.generated.state, code: 'one-time-code' },
      {
        store,
        snapshotStore,
        config: config(),
        now,
        fetchImpl,
        idTokenVerifier: idTokenVerifier('linked-google-subject', nonce),
      },
    );

    assert.deepEqual(result, { status: 'verified' });
    assert.equal(store.applied.length, 1);
    assert.equal(store.applied[0].lookup.isMember, true);
    assert.equal(store.applied[0].verificationSource, 'admin_snapshot');
    assert.equal(
      store.applied[0].snapshotImportId,
      '94f5ff5f-e5c7-4540-a557-609641631008',
    );
  });

  it('disables the private creator-membership OAuth flow', async () => {
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
          scope: `${googleOpenIdScope} ${youtubeReadonlyScope}`,
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
    assert.equal(store.completions[0].errorCode, 'creator_membership_oauth_disabled');
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
    const result = await refreshStaleLinkedYouTubeMembership('user-1', {
      store,
      snapshotStore: activeSnapshotStore(),
      config: config(),
      now,
      fetchImpl: async () => { throw new Error('network must not be used'); },
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

  it('uses the latest snapshot after its weekly freshness warning', async () => {
    const store = new FakeStore();
    store.link = {
      youtubeChannelId: memberChannelId,
      isMember: true,
      membershipLevelId: 'gold',
      memberSince: new Date('2026-01-01T00:00:00Z'),
      lastVerifiedAt: new Date(now.getTime() - 24 * 60 * 60 * 1000),
    };
    const result = await refreshStaleLinkedYouTubeMembership('user-1', {
      store,
      snapshotStore: activeSnapshotStore(
        [],
        new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000),
      ),
      snapshotEnvironment: { YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '24' },
      config: config(),
      now,
    });
    assert.equal(result?.isYouTubeMember, false);
    assert.equal(store.verificationFailures.length, 0);
    assert.equal(store.applied.length, 1);
    assert.equal(store.link?.isMember, false);
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

  it('batch-refreshes 205 users from one CSV snapshot without network calls', async () => {
    const store = new FakeStore();
    store.staleLinks = Array.from({ length: 205 }, (_, index) =>
      staleBatchLink(index));
    const snapshotMembers = store.staleLinks
      .filter((_, index) => index % 2 === 0)
      .map((link) => ({
        youtubeChannelId: link.youtubeChannelId,
        membershipLevel: 'current-level',
        totalTimeOnLevelMonths: 1,
        totalTimeAsMemberMonths: 2,
        sourceLastUpdate: null,
        sourceLastUpdateAt: null,
      }));
    let networkCalls = 0;
    const fetchImpl: FetchLike = async () => {
      networkCalls += 1;
      throw new Error('membership refresh must be snapshot-only');
    };

    const result = await refreshStaleYouTubeMembershipsForUsers(
      [
        ...store.staleLinks.map((link) => link.userId),
        store.staleLinks[0].userId,
      ],
      {
        store,
        snapshotStore: activeSnapshotStore(snapshotMembers),
        config: config(),
        now,
        fetchImpl,
      },
    );

    assert.equal(networkCalls, 0);
    assert.equal(result.requestedUsers, 205);
    assert.equal(result.staleLinkedUsers, 205);
    assert.equal(result.membershipApiRequests, 0);
    assert.equal(result.verified + result.notMember, 205);
    assert.equal(result.unavailable, 0);
    assert.equal(store.applied.length, 205);
    assert.equal(store.applied.every((update) =>
      update.expectedLastVerifiedAt?.getTime() ===
        store.staleLinks[0].lastVerifiedAt.getTime()), true);
  });

  it('falls back to base XP when the snapshot is missing', async () => {
    const store = new FakeStore();
    store.staleLinks = Array.from({ length: 105 }, (_, index) =>
      staleBatchLink(index));
    const fetchImpl: FetchLike = async () => {
      throw new Error('membership refresh must not use Google');
    };

    const result = await refreshStaleYouTubeMembershipsForUsers(
      store.staleLinks.map((link) => link.userId),
      { store, config: config(), now, fetchImpl },
    );

    assert.equal(result.membershipApiRequests, 0);
    assert.equal(result.unavailable, 0);
    assert.equal(result.notMember, 105);
    assert.equal(store.verificationFailures.length, 0);
    assert.equal(store.applied.length, 105);
    assert.equal(store.applied.every((update) =>
      update.lookup.isMember === false &&
      update.expectedLastVerifiedAt?.getTime() ===
        store.staleLinks[0].lastVerifiedAt.getTime()), true);
  });

  it('continues using all rows when the latest CSV has expired', async () => {
    const store = new FakeStore();
    store.staleLinks = [staleBatchLink(1), staleBatchLink(2)];
    const result = await refreshStaleYouTubeMembershipsForUsers(
      store.staleLinks.map((link) => link.userId),
      {
        store,
        snapshotStore: activeSnapshotStore(
          [],
          new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000),
        ),
        snapshotEnvironment: { YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS: '24' },
        config: config(),
        now,
        fetchImpl: async () => jsonResponse({ error: 'invalid_grant' }, 400),
      },
    );
    assert.equal(result.unavailable, 0);
    assert.equal(result.notMember, 2);
    assert.equal(result.membershipApiRequests, 0);
    assert.equal(store.verificationFailures.length, 0);
    assert.equal(store.applied.length, 2);
  });

  it('keeps route paths/status contracts and prediction settlement snapshot-aware', async () => {
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
    assert.match(routes, /'\/admin\/youtube\/membership\/snapshot'/);
    assert.match(routes, /CreatorMembershipOAuthDisabled/);
    assert.match(routes, /requirePermission\('settings\.manage'\)/);
    assert.match(routes, /'\/youtube\/oauth\/callback'/);
    assert.doesNotMatch(predictions, /yl\.last_verified_at >=/);
    assert.match(predictions, /yl\.is_member = TRUE/);
    assert.match(predictions, /yl\.verification_source = 'admin_snapshot'/);
    assert.match(predictions, /yl\.snapshot_import_id = \(/);
    assert.match(predictions, /refreshStaleYouTubeMembershipsForUsers\(/);
    assert.match(predictions, /membershipRefresh\.unavailable > 0/);
    assert.match(
      predictions,
      /memberMultiplierForSource\(\s*component\.sourceType,\s*pred\.is_youtube_member,/,
    );
  });

  it('has no active private members API or creator-membership scope path', async () => {
    const membership = await readFile(
      path.resolve(process.cwd(), 'src/services/youtubeMembershipService.ts'),
      'utf8',
    );
    assert.doesNotMatch(membership, /fetchYouTubeMembershipForChannels/);
    assert.doesNotMatch(membership, /fetchYouTubeMembershipBatch/);
    assert.doesNotMatch(membership, /creatorAccessToken/);
    const oauthSource = await readFile(
      path.resolve(process.cwd(), 'src/services/youtubeOAuthService.ts'),
      'utf8',
    );
    assert.doesNotMatch(oauthSource, /youtube\/v3\/members/);
    assert.doesNotMatch(oauthSource, /filterByMemberChannelId/);
    for (const purpose of ['member_link', 'creator_connect'] as const) {
      const flow = generateYouTubeOAuthFlow(purpose, config());
      const scope = new URL(flow.authorizationUrl).searchParams.get('scope') ?? '';
      assert.match(scope, /youtube\.readonly/);
      assert.doesNotMatch(scope, /youtube\.channel-memberships\.creator/);
    }
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
    assert.doesNotMatch(auth, /yl\.last_verified_at >=/);
    assert.match(auth, /yl\.is_member = TRUE/);
    assert.match(auth, /yl\.verification_source = 'admin_snapshot'/);
    assert.match(auth, /yl\.snapshot_import_id = \(/);
  });

  it('rejects legacy member flags unless the current CSV snapshot supports them', async () => {
    const migration = await readFile(
      path.resolve(
        process.cwd(),
        'migrations/036_enforce_current_snapshot_membership.sql',
      ),
      'utf8',
    );
    assert.match(migration, /verification_source = 'admin_snapshot'/);
    assert.match(migration, /snapshot_import_id = \([\s\S]*active_import_id/);
    assert.match(migration, /SET is_member = FALSE/);
    assert.match(migration, /DELETE FROM user_roles/);
    assert.match(migration, /DELETE FROM youtube_creator_credentials/);

    for (const relativePath of [
      'src/middleware/auth.ts',
      'src/routes/profileRoutes.ts',
      'src/routes/adminRoutes.ts',
      'src/services/leaderboardService.ts',
      'src/services/predictionService.ts',
      'src/services/challengeMembershipService.ts',
      'src/services/notificationService.ts',
    ]) {
      const source = await readFile(path.resolve(process.cwd(), relativePath), 'utf8');
      assert.match(
        source,
        /verification_source = 'admin_snapshot'/,
        `${relativePath} must reject legacy membership flags`,
      );
      assert.match(
        source,
        /snapshot_import_id = \([\s\S]*active_import_id/,
        `${relativePath} must require the active snapshot import`,
      );
    }
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
