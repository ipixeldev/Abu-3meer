import { getClient, query } from '../db/pool.js';
import {
  FetchLike,
  YouTubeIntegrationError,
  YouTubeMembershipLookup,
  YouTubeOAuthPurpose,
  YouTubeRuntimeConfig,
  decryptOAuthCodeVerifier,
  exchangeGoogleAuthorizationCode,
  fetchOwnedYouTubeChannelIds,
  generateYouTubeOAuthFlow,
  googleOpenIdScope,
  loadYouTubeRuntimeConfig,
  sha256Hex,
  verifyGoogleAccountBinding,
  youtubeMembershipRefreshIntervalSeconds,
  youtubeReadonlyScope,
} from './youtubeOAuthService.js';
import {
  PostgresYouTubeMembershipSnapshotStore,
  YouTubeMembershipSnapshotError,
  YouTubeMembershipSnapshotStore,
  getActiveYouTubeMembershipSnapshot,
  getYouTubeMembershipSnapshotStatus,
  membershipLookupFromSnapshot,
} from './youtubeMembershipSnapshotService.js';

export type YouTubeMembershipVerificationSource =
  | 'youtube_api'
  | 'admin_snapshot';

export type YouTubeFlowStatus =
  | 'pending'
  | 'verified'
  | 'not_member'
  | 'connected'
  | 'error';

export type StoredYouTubeOAuthFlow = {
  id: string;
  purpose: YouTubeOAuthPurpose;
  requestedByUserId: string;
  expectedGoogleSubject: string | null;
  pkceVerifierCiphertext: string;
  oidcNonceHash: string;
};

export type StoredYouTubeFlowStatus = {
  status: YouTubeFlowStatus;
  errorCode: string | null;
  youtubeChannelId: string | null;
  expiresAt: Date;
};

export type StoredCreatorCredential = {
  creatorChannelId: string;
  refreshTokenCiphertext: string;
  authorizedAt: Date;
};

export type StoredYouTubeAccountLink = {
  youtubeChannelId: string;
  isMember: boolean;
  membershipLevelId: string | null;
  memberSince: Date | null;
  lastVerifiedAt: Date;
};

export type StoredStaleYouTubeAccountLink = StoredYouTubeAccountLink & {
  userId: string;
};

export interface YouTubeMembershipStore {
  createOAuthFlow(input: {
    id: string;
    stateHash: string;
    purpose: YouTubeOAuthPurpose;
    requestedByUserId: string;
    expectedGoogleSubject: string | null;
    pkceVerifierCiphertext: string;
    oidcNonceHash: string;
    expiresAt: Date;
  }): Promise<void>;
  consumeOAuthFlow(stateHash: string): Promise<StoredYouTubeOAuthFlow | null>;
  completeOAuthFlow(
    flowId: string,
    status: Exclude<YouTubeFlowStatus, 'pending'>,
    errorCode?: string | null,
    youtubeChannelId?: string | null,
  ): Promise<void>;
  getOAuthFlowStatus(
    flowId: string,
    requestedByUserId: string,
    purpose: YouTubeOAuthPurpose,
  ): Promise<StoredYouTubeFlowStatus | null>;
  saveCreatorCredential(input: {
    creatorChannelId: string;
    refreshTokenCiphertext: string;
    authorizedByUserId: string;
    completedOAuthFlowId?: string;
  }): Promise<void>;
  getCreatorCredential(): Promise<StoredCreatorCredential | null>;
  getYouTubeAccountLink(userId: string): Promise<StoredYouTubeAccountLink | null>;
  getStaleYouTubeAccountLinks(
    userIds: string[],
    staleBefore: Date,
  ): Promise<StoredStaleYouTubeAccountLink[]>;
  applyMembershipVerification(input: {
    userId: string;
    youtubeChannelId: string;
    lookup: YouTubeMembershipLookup;
    verifiedAt: Date;
    freshnessSeconds: number;
    verificationSource?: YouTubeMembershipVerificationSource;
    snapshotImportId?: string | null;
    expectedLastVerifiedAt?: Date;
    completedOAuthFlow?: {
      flowId: string;
      status: 'verified' | 'not_member';
    };
  }): Promise<void>;
  recordMembershipVerificationFailure(
    userId: string,
    errorCode: string,
    attemptedAt: Date,
    expectedLastVerifiedAt?: Date,
  ): Promise<void>;
}

function safeStatusErrorCode(value: string | null | undefined): string | null {
  if (!value) return null;
  return /^[a-z0-9_]{1,80}$/.test(value)
    ? value
    : 'youtube_verification_failed';
}

export class PostgresYouTubeMembershipStore implements YouTubeMembershipStore {
  async createOAuthFlow(input: {
    id: string;
    stateHash: string;
    purpose: YouTubeOAuthPurpose;
    requestedByUserId: string;
    expectedGoogleSubject: string | null;
    pkceVerifierCiphertext: string;
    oidcNonceHash: string;
    expiresAt: Date;
  }): Promise<void> {
    await query(
      `DELETE FROM youtube_oauth_flows
       WHERE expires_at < CURRENT_TIMESTAMP - INTERVAL '1 day'`,
    );
    await query(
      `INSERT INTO youtube_oauth_flows
         (id, state_hash, purpose, requested_by_user_id,
          expected_google_subject, pkce_verifier_ciphertext,
          oidc_nonce_hash, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        input.id,
        input.stateHash,
        input.purpose,
        input.requestedByUserId,
        input.expectedGoogleSubject,
        input.pkceVerifierCiphertext,
        input.oidcNonceHash,
        input.expiresAt,
      ],
    );
  }

  async consumeOAuthFlow(
    stateHash: string,
  ): Promise<StoredYouTubeOAuthFlow | null> {
    const result = await query(
      `UPDATE youtube_oauth_flows
       SET consumed_at = CURRENT_TIMESTAMP
       WHERE state_hash = $1
         AND status = 'pending'
         AND consumed_at IS NULL
         AND expires_at > CURRENT_TIMESTAMP
       RETURNING id, purpose, requested_by_user_id,
                 expected_google_subject, pkce_verifier_ciphertext,
                 oidc_nonce_hash`,
      [stateHash],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      id: row.id,
      purpose: row.purpose,
      requestedByUserId: row.requested_by_user_id,
      expectedGoogleSubject: row.expected_google_subject,
      pkceVerifierCiphertext: row.pkce_verifier_ciphertext,
      oidcNonceHash: row.oidc_nonce_hash,
    };
  }

  async completeOAuthFlow(
    flowId: string,
    status: Exclude<YouTubeFlowStatus, 'pending'>,
    errorCode: string | null = null,
    youtubeChannelId: string | null = null,
  ): Promise<void> {
    await query(
      `UPDATE youtube_oauth_flows
       SET status = $2,
           error_code = $3,
           youtube_channel_id = $4,
           pkce_verifier_ciphertext = '',
           expected_google_subject = NULL,
           completed_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [flowId, status, safeStatusErrorCode(errorCode), youtubeChannelId],
    );
  }

  async getOAuthFlowStatus(
    flowId: string,
    requestedByUserId: string,
    purpose: YouTubeOAuthPurpose,
  ): Promise<StoredYouTubeFlowStatus | null> {
    const result = await query(
      `SELECT status, error_code, youtube_channel_id, expires_at
       FROM youtube_oauth_flows
       WHERE id = $1
         AND requested_by_user_id = $2
         AND purpose = $3`,
      [flowId, requestedByUserId, purpose],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      status: row.status,
      errorCode: row.error_code,
      youtubeChannelId: row.youtube_channel_id,
      expiresAt: new Date(row.expires_at),
    };
  }

  async saveCreatorCredential(input: {
    creatorChannelId: string;
    refreshTokenCiphertext: string;
    authorizedByUserId: string;
    completedOAuthFlowId?: string;
  }): Promise<void> {
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO youtube_creator_credentials
         (singleton, creator_channel_id, refresh_token_ciphertext,
          authorized_by_user_id, authorized_at, updated_at)
         VALUES (TRUE, $1, $2, $3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT (singleton) DO UPDATE SET
         creator_channel_id = EXCLUDED.creator_channel_id,
         refresh_token_ciphertext = EXCLUDED.refresh_token_ciphertext,
         authorized_by_user_id = EXCLUDED.authorized_by_user_id,
         authorized_at = CURRENT_TIMESTAMP,
         updated_at = CURRENT_TIMESTAMP`,
        [
          input.creatorChannelId,
          input.refreshTokenCiphertext,
          input.authorizedByUserId,
        ],
      );
      if (input.completedOAuthFlowId) {
        await client.query(
          `UPDATE youtube_oauth_flows
           SET status = 'connected',
               error_code = NULL,
               youtube_channel_id = $2,
               pkce_verifier_ciphertext = '',
               expected_google_subject = NULL,
               completed_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [input.completedOAuthFlowId, input.creatorChannelId],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async getCreatorCredential(): Promise<StoredCreatorCredential | null> {
    const result = await query(
      `SELECT creator_channel_id, refresh_token_ciphertext, authorized_at
       FROM youtube_creator_credentials
       WHERE singleton = TRUE`,
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      creatorChannelId: row.creator_channel_id,
      refreshTokenCiphertext: row.refresh_token_ciphertext,
      authorizedAt: new Date(row.authorized_at),
    };
  }

  async getYouTubeAccountLink(
    userId: string,
  ): Promise<StoredYouTubeAccountLink | null> {
    const result = await query(
      `SELECT youtube_channel_id,
              COALESCE(
                is_member = TRUE
                AND verification_source = 'admin_snapshot'
                AND snapshot_import_id = (
                  SELECT active_import_id
                  FROM youtube_membership_snapshot_state
                  WHERE singleton = TRUE
                ),
                FALSE
              ) AS is_member,
              membership_level_id,
              member_since, last_verified_at
       FROM youtube_account_links
       WHERE user_id = $1`,
      [userId],
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      youtubeChannelId: row.youtube_channel_id,
      isMember: row.is_member === true,
      membershipLevelId: row.membership_level_id ?? null,
      memberSince: row.member_since ? new Date(row.member_since) : null,
      lastVerifiedAt: new Date(row.last_verified_at),
    };
  }

  async getStaleYouTubeAccountLinks(
    userIds: string[],
    staleBefore: Date,
  ): Promise<StoredStaleYouTubeAccountLink[]> {
    const uniqueUserIds = [...new Set(userIds)];
    if (uniqueUserIds.length === 0) return [];
    const result = await query(
      `SELECT user_id, youtube_channel_id,
              COALESCE(
                is_member = TRUE
                AND verification_source = 'admin_snapshot'
                AND snapshot_import_id = (
                  SELECT active_import_id
                  FROM youtube_membership_snapshot_state
                  WHERE singleton = TRUE
                ),
                FALSE
              ) AS is_member,
              membership_level_id,
              member_since, last_verified_at
       FROM youtube_account_links
       WHERE user_id = ANY($1::uuid[])
         AND last_verified_at < $2
       ORDER BY user_id`,
      [uniqueUserIds, staleBefore],
    );
    return result.rows.map((row) => ({
      userId: row.user_id,
      youtubeChannelId: row.youtube_channel_id,
      isMember: row.is_member === true,
      membershipLevelId: row.membership_level_id ?? null,
      memberSince: row.member_since ? new Date(row.member_since) : null,
      lastVerifiedAt: new Date(row.last_verified_at),
    }));
  }

  async applyMembershipVerification(input: {
    userId: string;
    youtubeChannelId: string;
    lookup: YouTubeMembershipLookup;
    verifiedAt: Date;
    freshnessSeconds: number;
    verificationSource?: YouTubeMembershipVerificationSource;
    snapshotImportId?: string | null;
    expectedLastVerifiedAt?: Date;
    completedOAuthFlow?: {
      flowId: string;
      status: 'verified' | 'not_member';
    };
  }): Promise<void> {
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT is_youtube_member, youtube_channel_id
         FROM users
         WHERE id = $1
         FOR UPDATE`,
        [input.userId],
      );
      if (!existing.rowCount) {
        throw new YouTubeIntegrationError('youtube_user_missing', 404);
      }
      const wasMember = existing.rows[0].is_youtube_member === true;
      const previousChannelId = existing.rows[0].youtube_channel_id ?? null;
      if (input.expectedLastVerifiedAt) {
        const link = await client.query(
          `SELECT last_verified_at
           FROM youtube_account_links
           WHERE user_id = $1
           FOR UPDATE`,
          [input.userId],
        );
        const currentVerifiedAt = link.rows[0]?.last_verified_at
          ? new Date(link.rows[0].last_verified_at)
          : null;
        if (
          !currentVerifiedAt ||
          currentVerifiedAt.getTime() !== input.expectedLastVerifiedAt.getTime()
        ) {
          await client.query('COMMIT');
          return;
        }
      }
      await client.query(
        `INSERT INTO youtube_account_links
           (user_id, youtube_channel_id, is_member, membership_level_id,
            member_since, last_verified_at, last_attempted_at,
            last_error_code, verification_source, snapshot_import_id,
            updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $6, NULL, $7, $8,
                 CURRENT_TIMESTAMP)
         ON CONFLICT (user_id) DO UPDATE SET
           youtube_channel_id = EXCLUDED.youtube_channel_id,
           is_member = EXCLUDED.is_member,
           membership_level_id = EXCLUDED.membership_level_id,
           member_since = EXCLUDED.member_since,
           last_verified_at = EXCLUDED.last_verified_at,
           last_attempted_at = EXCLUDED.last_attempted_at,
           last_error_code = NULL,
           verification_source = EXCLUDED.verification_source,
           snapshot_import_id = EXCLUDED.snapshot_import_id,
           updated_at = CURRENT_TIMESTAMP`,
        [
          input.userId,
          input.youtubeChannelId,
          input.lookup.isMember,
          input.lookup.membershipLevelId,
          input.lookup.memberSince,
          input.verifiedAt,
          input.verificationSource ?? 'youtube_api',
          input.verificationSource === 'admin_snapshot'
            ? input.snapshotImportId ?? null
            : null,
        ],
      );
      await client.query(
        `UPDATE users
         SET is_youtube_member = $2,
             youtube_channel_id = $3,
             youtube_member_since = CASE
               WHEN $2 THEN COALESCE($4, youtube_member_since, $5)
               ELSE NULL
             END,
             youtube_membership_verified_at = $5,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [
          input.userId,
          input.lookup.isMember,
          input.youtubeChannelId,
          input.lookup.memberSince,
          input.verifiedAt,
        ],
      );
      if (input.lookup.isMember) {
        await client.query(
          `INSERT INTO user_roles (user_id, role_id)
           VALUES ($1, 'member')
           ON CONFLICT DO NOTHING`,
          [input.userId],
        );
      } else {
        await client.query(
          `DELETE FROM user_roles
           WHERE user_id = $1 AND role_id = 'member'`,
          [input.userId],
        );
      }
      if (
        wasMember !== input.lookup.isMember ||
        previousChannelId !== input.youtubeChannelId
      ) {
        const expiresAt = new Date(
          input.verifiedAt.getTime() + input.freshnessSeconds * 1000,
        );
        await client.query(
          `INSERT INTO membership_history
             (user_id, status, verified_at, expires_at, metadata)
           VALUES ($1, $2, $3, $4, $5::jsonb)`,
          [
            input.userId,
            input.lookup.isMember ? 'active' : 'inactive',
            input.verifiedAt,
            expiresAt,
            JSON.stringify({
              source: input.verificationSource === 'admin_snapshot'
                ? 'admin_snapshot'
                : 'youtube_members_api',
              youtubeChannelId: input.youtubeChannelId,
              membershipLevelId: input.lookup.membershipLevelId,
              ...(input.verificationSource === 'admin_snapshot' &&
                  input.snapshotImportId
                ? { snapshotImportId: input.snapshotImportId }
                : {}),
            }),
          ],
        );
      }
      if (input.completedOAuthFlow) {
        await client.query(
          `UPDATE youtube_oauth_flows
           SET status = $2,
               error_code = NULL,
               youtube_channel_id = $3,
               pkce_verifier_ciphertext = '',
               expected_google_subject = NULL,
               completed_at = CURRENT_TIMESTAMP
           WHERE id = $1`,
          [
            input.completedOAuthFlow.flowId,
            input.completedOAuthFlow.status,
            input.youtubeChannelId,
          ],
        );
      }
      await client.query('COMMIT');
    } catch (error: any) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (error?.code === '23505') {
        throw new YouTubeIntegrationError(
          'youtube_channel_already_linked',
          409,
          'This YouTube channel is already linked to another account.',
        );
      }
      throw error;
    } finally {
      client.release();
    }
  }

  async recordMembershipVerificationFailure(
    userId: string,
    errorCode: string,
    attemptedAt: Date,
    expectedLastVerifiedAt?: Date,
  ): Promise<void> {
    const safeError = safeStatusErrorCode(errorCode) ??
      'youtube_verification_failed';
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const existing = await client.query(
        `SELECT is_youtube_member
         FROM users
         WHERE id = $1
         FOR UPDATE`,
        [userId],
      );
      if (!existing.rowCount) {
        throw new YouTubeIntegrationError('youtube_user_missing', 404);
      }
      if (expectedLastVerifiedAt) {
        const link = await client.query(
          `SELECT last_verified_at
           FROM youtube_account_links
           WHERE user_id = $1
           FOR UPDATE`,
          [userId],
        );
        const currentVerifiedAt = link.rows[0]?.last_verified_at
          ? new Date(link.rows[0].last_verified_at)
          : null;
        if (
          !currentVerifiedAt ||
          currentVerifiedAt.getTime() !== expectedLastVerifiedAt.getTime()
        ) {
          await client.query('COMMIT');
          return;
        }
      }
      await client.query(
        `UPDATE youtube_account_links
         SET last_attempted_at = $2,
             last_error_code = $3,
             updated_at = CURRENT_TIMESTAMP
         WHERE user_id = $1`,
        [userId, attemptedAt, safeError],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }
}

type YouTubeServiceDependencies = {
  store?: YouTubeMembershipStore;
  snapshotStore?: YouTubeMembershipSnapshotStore;
  snapshotEnvironment?: NodeJS.ProcessEnv;
  config?: YouTubeRuntimeConfig;
  fetchImpl?: FetchLike;
  idTokenVerifier?: Parameters<typeof verifyGoogleAccountBinding>[4];
  now?: Date;
};

type MembershipRefreshResult = {
  status: 'verified' | 'not_member';
  isYouTubeMember: boolean;
  cached: boolean;
  verifiedAt: string;
};

function dependencies(options: YouTubeServiceDependencies) {
  return {
    store: options.store ?? new PostgresYouTubeMembershipStore(),
    // A custom membership store is normally a test/in-process adapter. Do not
    // silently pair it with the production PostgreSQL snapshot store unless a
    // matching snapshot adapter is explicitly supplied.
    snapshotStore: options.snapshotStore ?? (options.store
      ? null
      : new PostgresYouTubeMembershipSnapshotStore()),
    snapshotEnvironment: options.snapshotEnvironment,
    config: options.config ?? loadYouTubeRuntimeConfig(),
    fetchImpl: options.fetchImpl ?? fetch,
    idTokenVerifier: options.idTokenVerifier,
    now: options.now ?? new Date(),
  };
}

export async function startYouTubeOAuthFlow(
  input: {
    requestedByUserId: string;
    purpose: YouTubeOAuthPurpose;
    expectedGoogleSubject?: string | null;
  },
  options: YouTubeServiceDependencies = {},
): Promise<{ authorizationUrl: string; flowId: string }> {
  const runtime = dependencies(options);
  const expectedGoogleSubject = input.expectedGoogleSubject?.trim() ?? null;
  if (input.purpose === 'member_link' && !expectedGoogleSubject) {
    throw new YouTubeIntegrationError(
      'google_account_link_required',
      409,
      'Link Google to this app account before verifying YouTube membership.',
    );
  }
  const flow = generateYouTubeOAuthFlow(input.purpose, runtime.config);
  await runtime.store.createOAuthFlow({
    id: flow.flowId,
    stateHash: flow.stateHash,
    purpose: input.purpose,
    requestedByUserId: input.requestedByUserId,
    expectedGoogleSubject,
    pkceVerifierCiphertext: flow.pkceVerifierCiphertext,
    oidcNonceHash: flow.oidcNonceHash,
    expiresAt: new Date(runtime.now.getTime() + 10 * 60 * 1000),
  });
  return {
    authorizationUrl: flow.authorizationUrl,
    flowId: flow.flowId,
  };
}

function requireGrantedScopes(
  grantedScopes: Set<string>,
  requiredScopes: string[],
): void {
  if (
    grantedScopes.size > 0 &&
    requiredScopes.some((scope) => !grantedScopes.has(scope))
  ) {
    throw new YouTubeIntegrationError('youtube_scope_missing', 403);
  }
}

async function lookupMembershipFromLatestSnapshot(
  candidateChannelIds: string[],
  runtime: ReturnType<typeof dependencies>,
): Promise<ResolvedMembershipLookup> {
  const nonMember: ResolvedMembershipLookup = {
    lookup: {
      isMember: false,
      channelId: null,
      membershipLevelId: null,
      memberSince: null,
    },
    verificationSource: 'admin_snapshot',
    snapshotImportId: null,
  };
  if (!runtime.snapshotStore) {
    return nonMember;
  }
  const status = await getYouTubeMembershipSnapshotStatus({
    store: runtime.snapshotStore,
    now: runtime.now,
    environment: runtime.snapshotEnvironment,
  });
  if (status.status === 'not_imported') return nonMember;
  const snapshot = await getActiveYouTubeMembershipSnapshot(
    candidateChannelIds,
    {
      store: runtime.snapshotStore,
      now: runtime.now,
      environment: runtime.snapshotEnvironment,
    },
  );
  if (!snapshot) return nonMember;
  return {
    lookup: membershipLookupFromSnapshot(candidateChannelIds, snapshot),
    verificationSource: 'admin_snapshot',
    snapshotImportId: snapshot.importId,
  };
}

type ResolvedMembershipLookup = {
  lookup: YouTubeMembershipLookup;
  verificationSource: YouTubeMembershipVerificationSource;
  snapshotImportId: string | null;
};

export async function handleYouTubeOAuthCallback(
  input: { state: string; code?: string; error?: string },
  options: YouTubeServiceDependencies = {},
): Promise<{ status: Exclude<YouTubeFlowStatus, 'pending'> }> {
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(input.state)) {
    throw new YouTubeIntegrationError('invalid_oauth_state', 400);
  }
  const runtime = dependencies(options);
  const flow = await runtime.store.consumeOAuthFlow(sha256Hex(input.state));
  if (!flow) {
    throw new YouTubeIntegrationError('invalid_or_expired_oauth_state', 400);
  }

  try {
    if (input.error) {
      throw new YouTubeIntegrationError('oauth_authorization_denied', 403);
    }
    if (flow.purpose === 'creator_connect') {
      throw new YouTubeIntegrationError(
        'creator_membership_oauth_disabled',
        410,
        'Creator membership OAuth is disabled. Import the members CSV in Admin Studio.',
      );
    }
    const codeVerifier = decryptOAuthCodeVerifier(
      flow.id,
      flow.pkceVerifierCiphertext,
      runtime.config,
    );
    const tokens = await exchangeGoogleAuthorizationCode(
      input.code ?? '',
      codeVerifier,
      runtime.config,
      runtime.fetchImpl,
    );
    requireGrantedScopes(tokens.grantedScopes, [
      googleOpenIdScope,
      youtubeReadonlyScope,
    ]);
    if (!flow.expectedGoogleSubject) {
      throw new YouTubeIntegrationError('google_account_link_required', 409);
    }
    await verifyGoogleAccountBinding(
      tokens.idToken,
      flow.expectedGoogleSubject,
      flow.oidcNonceHash,
      runtime.config,
      runtime.idTokenVerifier,
    );
    // Resolve the channel only after the cryptographically verified Google
    // subject is proven to be the provider already linked in Firebase. This
    // prevents a user from connecting a friend's/member's YouTube identity.
    const channels = await fetchOwnedYouTubeChannelIds(
      tokens.accessToken,
      runtime.fetchImpl,
    );
    if (channels.length === 0) {
      throw new YouTubeIntegrationError('youtube_channel_missing', 409);
    }
    const resolvedMembership = await lookupMembershipFromLatestSnapshot(
      channels,
      runtime,
    );
    const membership = resolvedMembership.lookup;
    if (!membership.isMember && channels.length > 1) {
      throw new YouTubeIntegrationError('youtube_channel_ambiguous', 409);
    }
    const channelId = membership.channelId ?? channels[0];
    const status = membership.isMember ? 'verified' : 'not_member';
    await runtime.store.applyMembershipVerification({
      userId: flow.requestedByUserId,
      youtubeChannelId: channelId,
      lookup: membership,
      verifiedAt: runtime.now,
      freshnessSeconds: runtime.config.membershipRefreshIntervalSeconds,
      verificationSource: resolvedMembership.verificationSource,
      snapshotImportId: resolvedMembership.snapshotImportId,
      completedOAuthFlow: { flowId: flow.id, status },
    });
    return { status };
  } catch (error) {
    const integrationError = error instanceof YouTubeIntegrationError
      ? error
      : new YouTubeIntegrationError('youtube_verification_failed', 502);
    if (
      flow.purpose === 'member_link' &&
      integrationError.code.startsWith('youtube_snapshot_')
    ) {
      await runtime.store.recordMembershipVerificationFailure(
        flow.requestedByUserId,
        integrationError.code,
        runtime.now,
      );
    }
    await runtime.store.completeOAuthFlow(
      flow.id,
      'error',
      integrationError.code,
    );
    return { status: 'error' };
  }
}

export async function getYouTubeOAuthFlowStatus(
  input: {
    flowId: string;
    requestedByUserId: string;
    purpose: YouTubeOAuthPurpose;
  },
  store: YouTubeMembershipStore = new PostgresYouTubeMembershipStore(),
  now = new Date(),
): Promise<{
  status: YouTubeFlowStatus;
  errorCode?: string;
  isYouTubeMember?: boolean;
}> {
  const flow = await store.getOAuthFlowStatus(
    input.flowId,
    input.requestedByUserId,
    input.purpose,
  );
  if (!flow) {
    throw new YouTubeIntegrationError('youtube_flow_not_found', 404);
  }
  if (flow.status === 'pending' && flow.expiresAt.getTime() <= now.getTime()) {
    return { status: 'error', errorCode: 'oauth_flow_expired' };
  }
  return {
    status: flow.status,
    ...(flow.errorCode ? { errorCode: flow.errorCode } : {}),
    ...(input.purpose === 'member_link' &&
      ['verified', 'not_member'].includes(flow.status)
      ? { isYouTubeMember: flow.status === 'verified' }
      : {}),
  };
}

export async function getCreatorYouTubeConnectionStatus(
  store: YouTubeMembershipStore = new PostgresYouTubeMembershipStore(),
  environment: NodeJS.ProcessEnv = process.env,
): Promise<{
  status: 'connected' | 'not_connected';
  creatorChannelId: string | null;
  authorizedAt: string | null;
}> {
  const configuredChannel = environment.YOUTUBE_CREATOR_CHANNEL_ID?.trim() ?? '';
  const credential = await store.getCreatorCredential();
  const connected = Boolean(
    credential &&
    configuredChannel &&
    credential.creatorChannelId === configuredChannel,
  );
  return {
    status: connected ? 'connected' : 'not_connected',
    creatorChannelId: connected ? credential!.creatorChannelId : null,
    authorizedAt: connected ? credential!.authorizedAt.toISOString() : null,
  };
}

export async function refreshLinkedYouTubeMembership(
  userId: string,
  options: YouTubeServiceDependencies = {},
): Promise<MembershipRefreshResult> {
  const store = options.store ?? new PostgresYouTubeMembershipStore();
  const now = options.now ?? new Date();
  const freshnessSeconds = options.config?.membershipRefreshIntervalSeconds ??
    youtubeMembershipRefreshIntervalSeconds();
  const link = await store.getYouTubeAccountLink(userId);
  if (!link) {
    throw new YouTubeIntegrationError(
      'youtube_link_required',
      409,
      'Connect the Google account that owns your YouTube channel first.',
    );
  }
  const ageMilliseconds = now.getTime() - link.lastVerifiedAt.getTime();
  if (
    ageMilliseconds >= 0 &&
    ageMilliseconds < freshnessSeconds * 1000
  ) {
    return {
      status: link.isMember ? 'verified' : 'not_member',
      isYouTubeMember: link.isMember,
      cached: true,
      verifiedAt: link.lastVerifiedAt.toISOString(),
    };
  }

  let runtime: ReturnType<typeof dependencies>;
  try {
    runtime = dependencies({ ...options, store, now });
  } catch (error) {
    const integrationError = error instanceof YouTubeIntegrationError
      ? error
      : new YouTubeIntegrationError('youtube_verification_failed', 502);
    await store.recordMembershipVerificationFailure(
      userId,
      integrationError.code,
      now,
      link.lastVerifiedAt,
    );
    throw integrationError;
  }

  try {
    const resolvedMembership = await lookupMembershipFromLatestSnapshot(
      [link.youtubeChannelId],
      runtime,
    );
    const lookup = resolvedMembership.lookup;
    await runtime.store.applyMembershipVerification({
      userId,
      youtubeChannelId: link.youtubeChannelId,
      lookup,
      verifiedAt: runtime.now,
      freshnessSeconds: runtime.config.membershipRefreshIntervalSeconds,
      verificationSource: resolvedMembership.verificationSource,
      snapshotImportId: resolvedMembership.snapshotImportId,
      expectedLastVerifiedAt: link.lastVerifiedAt,
    });
    return {
      status: lookup.isMember ? 'verified' : 'not_member',
      isYouTubeMember: lookup.isMember,
      cached: false,
      verifiedAt: runtime.now.toISOString(),
    };
  } catch (error) {
    const integrationError = error instanceof YouTubeIntegrationError
      ? error
      : new YouTubeIntegrationError('youtube_verification_failed', 502);
    await store.recordMembershipVerificationFailure(
      userId,
      integrationError.code,
      now,
      link.lastVerifiedAt,
    );
    throw integrationError;
  }
}

async function withPostgresMembershipRefreshLock<T>(
  userId: string,
  work: () => Promise<T>,
): Promise<T | null> {
  const client = await getClient();
  const lockName = `youtube-membership-refresh:${userId}`;
  let acquired = false;
  try {
    const lock = await client.query(
      `SELECT pg_try_advisory_lock(hashtextextended($1, 0)) AS acquired`,
      [lockName],
    );
    acquired = lock.rows[0]?.acquired === true;
    return acquired ? await work() : null;
  } finally {
    if (acquired) {
      await client.query(
        `SELECT pg_advisory_unlock(hashtextextended($1, 0))`,
        [lockName],
      ).catch(() => undefined);
    }
    client.release();
  }
}

/**
 * Refreshes a stale linked membership on the first authenticated request.
 * A session-level PostgreSQL advisory lock prevents several API processes
 * from spending quota on the same user concurrently. A caller that loses the
 * lock safely treats the stale membership as inactive for that request.
 *
 * The latest complete CSV remains authoritative until replaced, even after
 * the dashboard freshness warning. With no imported CSV, a linked channel is
 * safely treated as a non-member so ordinary base-XP activity is never blocked.
 */
export async function refreshStaleLinkedYouTubeMembership(
  userId: string,
  options: YouTubeServiceDependencies & {
    withRefreshLock?: <T>(work: () => Promise<T>) => Promise<T | null>;
  } = {},
): Promise<MembershipRefreshResult | null> {
  const store = options.store ?? new PostgresYouTubeMembershipStore();
  const now = options.now ?? new Date();
  const freshnessSeconds = options.config?.membershipRefreshIntervalSeconds ??
    youtubeMembershipRefreshIntervalSeconds();
  const link = await store.getYouTubeAccountLink(userId);
  if (!link) return null;

  const ageMilliseconds = now.getTime() - link.lastVerifiedAt.getTime();
  if (ageMilliseconds >= 0 && ageMilliseconds < freshnessSeconds * 1000) {
    return {
      status: link.isMember ? 'verified' : 'not_member',
      isYouTubeMember: link.isMember,
      cached: true,
      verifiedAt: link.lastVerifiedAt.toISOString(),
    };
  }

  const work = async () => {
    // Re-read freshness inside refreshLinkedYouTubeMembership after winning
    // the lock; another process may have refreshed just before this one.
    return refreshLinkedYouTubeMembership(userId, {
      ...options,
      store,
      now,
    });
  };

  if (options.withRefreshLock) return options.withRefreshLock(work);
  if (options.store) return work();
  return withPostgresMembershipRefreshLock(userId, work);
}

export type YouTubeBatchRefreshResult = {
  requestedUsers: number;
  staleLinkedUsers: number;
  verified: number;
  notMember: number;
  unavailable: number;
  membershipApiRequests: number;
};

async function recordFailedVerificationAttempts(
  store: YouTubeMembershipStore,
  links: StoredStaleYouTubeAccountLink[],
  errorCode: string,
  attemptedAt: Date,
): Promise<void> {
  let firstError: unknown;
  for (const link of links) {
    try {
      await store.recordMembershipVerificationFailure(
        link.userId,
        errorCode,
        attemptedAt,
        link.lastVerifiedAt,
      );
    } catch (error) {
      firstError ??= error;
    }
  }
  if (firstError) throw firstError;
}

async function applySnapshotRefreshForLinks(
  store: YouTubeMembershipStore,
  snapshotStore: YouTubeMembershipSnapshotStore,
  links: StoredStaleYouTubeAccountLink[],
  now: Date,
  freshnessSeconds: number,
  result: YouTubeBatchRefreshResult,
  environment?: NodeJS.ProcessEnv,
): Promise<boolean> {
  const snapshot = await getActiveYouTubeMembershipSnapshot(
    links.map((link) => link.youtubeChannelId),
    { store: snapshotStore, now, environment },
  );
  if (!snapshot) return false;

  let firstDatabaseError: unknown;
  for (const link of links) {
    const lookup = membershipLookupFromSnapshot(
      [link.youtubeChannelId],
      snapshot,
    );
    try {
      await store.applyMembershipVerification({
        userId: link.userId,
        youtubeChannelId: link.youtubeChannelId,
        lookup,
        verifiedAt: now,
        freshnessSeconds,
        verificationSource: 'admin_snapshot',
        snapshotImportId: snapshot.importId,
        expectedLastVerifiedAt: link.lastVerifiedAt,
      });
      if (lookup.isMember) result.verified += 1;
      else result.notMember += 1;
    } catch (error) {
      firstDatabaseError ??= error;
    }
  }
  if (firstDatabaseError) throw firstDatabaseError;
  return true;
}

async function applyNoSnapshotForLinks(
  store: YouTubeMembershipStore,
  links: StoredStaleYouTubeAccountLink[],
  now: Date,
  freshnessSeconds: number,
  result: YouTubeBatchRefreshResult,
): Promise<void> {
  let firstDatabaseError: unknown;
  for (const link of links) {
    try {
      await store.applyMembershipVerification({
        userId: link.userId,
        youtubeChannelId: link.youtubeChannelId,
        lookup: {
          isMember: false,
          channelId: null,
          membershipLevelId: null,
          memberSince: null,
        },
        verifiedAt: now,
        freshnessSeconds,
        verificationSource: 'admin_snapshot',
        snapshotImportId: null,
        expectedLastVerifiedAt: link.lastVerifiedAt,
      });
      result.notMember += 1;
    } catch (error) {
      firstDatabaseError ??= error;
    }
  }
  if (firstDatabaseError) throw firstDatabaseError;
}

/** Refreshes stale links exclusively from the current administrator CSV. */
export async function refreshStaleYouTubeMembershipsForUsers(
  userIds: string[],
  options: YouTubeServiceDependencies = {},
): Promise<YouTubeBatchRefreshResult> {
  const store = options.store ?? new PostgresYouTubeMembershipStore();
  const snapshotStore = options.snapshotStore ?? (options.store
    ? null
    : new PostgresYouTubeMembershipSnapshotStore());
  const now = options.now ?? new Date();
  const freshnessSeconds = options.config?.membershipRefreshIntervalSeconds ??
    youtubeMembershipRefreshIntervalSeconds();
  const uniqueUserIds = [...new Set(userIds)];
  const result: YouTubeBatchRefreshResult = {
    requestedUsers: uniqueUserIds.length,
    staleLinkedUsers: 0,
    verified: 0,
    notMember: 0,
    unavailable: 0,
    membershipApiRequests: 0,
  };
  if (uniqueUserIds.length === 0) return result;

  const staleBefore = new Date(now.getTime() - freshnessSeconds * 1000);
  const staleLinks = await store.getStaleYouTubeAccountLinks(
    uniqueUserIds,
    staleBefore,
  );
  result.staleLinkedUsers = staleLinks.length;
  if (staleLinks.length === 0) return result;

  if (!snapshotStore) {
    await applyNoSnapshotForLinks(
      store, staleLinks, now, freshnessSeconds, result,
    );
    return result;
  }
  try {
    const status = await getYouTubeMembershipSnapshotStatus({
      store: snapshotStore,
      now,
      environment: options.snapshotEnvironment,
    });
    if (status.status === 'not_imported') {
      await applyNoSnapshotForLinks(
        store, staleLinks, now, freshnessSeconds, result,
      );
      return result;
    }
    const applied = await applySnapshotRefreshForLinks(
      store,
      snapshotStore,
      staleLinks,
      now,
      freshnessSeconds,
      result,
      options.snapshotEnvironment,
    );
    if (!applied) {
      await recordFailedVerificationAttempts(
        store, staleLinks, 'youtube_snapshot_unavailable', now,
      );
      result.unavailable = staleLinks.length;
    }
    return result;
  } catch (error) {
    const code = error instanceof YouTubeMembershipSnapshotError
      ? error.code
      : 'youtube_snapshot_unavailable';
    await recordFailedVerificationAttempts(
      store, staleLinks, code, now,
    );
    result.unavailable = staleLinks.length;
    return result;
  }
}
