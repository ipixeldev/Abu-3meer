import { getClient } from '../db/pool.js';
import { youtubeChannelIdPattern } from './youtubeChannelId.js';

export const youtubeReadonlyScope =
  'https://www.googleapis.com/auth/youtube.readonly';

const googleTokenInfoUrl = 'https://oauth2.googleapis.com/tokeninfo';
const youtubeChannelsUrl = 'https://www.googleapis.com/youtube/v3/channels';
const googleResponseMaxBytes = 256 * 1024;

export type YouTubeMembershipCheckStatus =
  | 'active'
  | 'not_in_snapshot'
  | 'snapshot_unavailable'
  | 'no_youtube_channel';

export type YouTubeMembershipCheckResult = {
  membership: {
    status: YouTubeMembershipCheckStatus;
    isMember: boolean;
    youtubeChannelId?: string;
    membershipLevelId?: string | null;
    memberSince?: string | null;
    verifiedAt: string;
    snapshotExpiresAt?: string;
  };
};

export class YouTubeMembershipVerificationError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus = 400,
    message = 'YouTube membership could not be checked.',
  ) {
    super(message);
    this.name = 'YouTubeMembershipVerificationError';
  }
}

type FetchImplementation = typeof fetch;

type GoogleAccessTokenInfo = {
  subject: string;
  scopes: Set<string>;
};

async function readBoundedJson(
  response: Response,
  errorCode: string,
): Promise<unknown> {
  const declaredLength = Number(response.headers.get('content-length') ?? '0');
  if (declaredLength > googleResponseMaxBytes) {
    throw new YouTubeMembershipVerificationError(errorCode, 502);
  }
  const text = await response.text();
  if (Buffer.byteLength(text, 'utf8') > googleResponseMaxBytes) {
    throw new YouTubeMembershipVerificationError(errorCode, 502);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new YouTubeMembershipVerificationError(errorCode, 502);
  }
}

async function googleRequest(
  operation: () => Promise<Response>,
  unavailableCode: string,
): Promise<Response> {
  try {
    return await operation();
  } catch {
    // Never attach the fetch error: some HTTP implementations include request
    // headers in transport diagnostics, and the Google access token is a
    // short-lived bearer credential.
    throw new YouTubeMembershipVerificationError(
      unavailableCode,
      503,
      'Google verification is temporarily unavailable. Try again shortly.',
    );
  }
}

/**
 * Validate the short-lived credential before using it. The token is sent in a
 * form body instead of a URL so it cannot enter proxy/query-string logs.
 */
export async function inspectGoogleAccessToken(
  accessToken: string,
  options: {
    fetchImplementation?: FetchImplementation;
    timeoutMs?: number;
  } = {},
): Promise<GoogleAccessTokenInfo> {
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const response = await googleRequest(
    () => fetchImplementation(googleTokenInfoUrl, {
      method: 'POST',
      headers: {
        accept: 'application/json',
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ access_token: accessToken }).toString(),
      redirect: 'error',
      signal: AbortSignal.timeout(options.timeoutMs ?? 8_000),
    }),
    'youtube_google_tokeninfo_unavailable',
  );

  if (response.status === 400 || response.status === 401) {
    throw new YouTubeMembershipVerificationError(
      'youtube_access_token_invalid',
      401,
      'Google authorization expired or is invalid. Sign in with Google again.',
    );
  }
  if (!response.ok) {
    throw new YouTubeMembershipVerificationError(
      'youtube_google_tokeninfo_unavailable',
      response.status === 429 ? 503 : 502,
      'Google verification is temporarily unavailable. Try again shortly.',
    );
  }

  const payload = await readBoundedJson(
    response,
    'youtube_google_tokeninfo_invalid_response',
  ) as Record<string, unknown>;
  const subject = typeof payload.sub === 'string'
    ? payload.sub
    : typeof payload.user_id === 'string'
      ? payload.user_id
      : '';
  const scopes = new Set(
    typeof payload.scope === 'string'
      ? payload.scope.split(/\s+/).filter(Boolean)
      : [],
  );
  const expiresIn = Number(payload.expires_in);

  if (!subject || !Number.isFinite(expiresIn) || expiresIn <= 0) {
    throw new YouTubeMembershipVerificationError(
      'youtube_access_token_invalid',
      401,
      'Google authorization expired or is invalid. Sign in with Google again.',
    );
  }
  if (!scopes.has(youtubeReadonlyScope)) {
    throw new YouTubeMembershipVerificationError(
      'youtube_readonly_scope_required',
      403,
      'Allow read-only YouTube access to check the channel membership list.',
    );
  }
  return { subject, scopes };
}

/** Retrieve only IDs for channels owned by the authorized Google account. */
export async function fetchOwnedYouTubeChannelIds(
  accessToken: string,
  options: {
    fetchImplementation?: FetchImplementation;
    timeoutMs?: number;
  } = {},
): Promise<string[]> {
  const fetchImplementation = options.fetchImplementation ?? fetch;
  const url = new URL(youtubeChannelsUrl);
  url.searchParams.set('part', 'id');
  url.searchParams.set('mine', 'true');
  url.searchParams.set('maxResults', '50');

  const response = await googleRequest(
    () => fetchImplementation(url, {
      method: 'GET',
      headers: {
        accept: 'application/json',
        authorization: `Bearer ${accessToken}`,
      },
      redirect: 'error',
      signal: AbortSignal.timeout(options.timeoutMs ?? 8_000),
    }),
    'youtube_channels_unavailable',
  );

  if (response.status === 401) {
    throw new YouTubeMembershipVerificationError(
      'youtube_access_token_invalid',
      401,
      'Google authorization expired or is invalid. Sign in with Google again.',
    );
  }
  if (response.status === 403) {
    throw new YouTubeMembershipVerificationError(
      'youtube_channels_access_denied',
      403,
      'YouTube channel access was denied. Confirm the requested permission and try again.',
    );
  }
  if (!response.ok) {
    throw new YouTubeMembershipVerificationError(
      'youtube_channels_unavailable',
      response.status === 429 ? 503 : 502,
      'YouTube channel verification is temporarily unavailable.',
    );
  }

  const payload = await readBoundedJson(
    response,
    'youtube_channels_invalid_response',
  ) as { items?: unknown };
  if (!Array.isArray(payload.items)) {
    throw new YouTubeMembershipVerificationError(
      'youtube_channels_invalid_response',
      502,
    );
  }
  return [...new Set(payload.items
    .map((item) => {
      if (!item || typeof item !== 'object') return '';
      const id = (item as { id?: unknown }).id;
      return typeof id === 'string' && youtubeChannelIdPattern.test(id)
        ? id
        : '';
    })
    .filter(Boolean))];
}

type SnapshotMember = {
  youtube_channel_id: string;
  membership_level: string | null;
  joined_at: Date | null;
};

export type YouTubeSnapshotChannelSelection =
  | { kind: 'selected'; channelId: string; isMember: boolean }
  | { kind: 'not_in_snapshot'; channelId: null; isMember: false };

export type UnmatchedPriorLinkPlan =
  | { action: 'none'; channelId: null }
  | { action: 'preserve' | 'revoke'; channelId: string };

/**
 * Resolve only from Google-owned IDs and the current full CSV. Multiple owned
 * channels need no UI picker when none matches: the answer is non-member and
 * no arbitrary ownership link is persisted. Only multiple CSV matches are
 * genuinely ambiguous.
 */
export function selectYouTubeChannelForSnapshot(
  ownedChannelIds: string[],
  activeSnapshotChannelIds: string[],
): YouTubeSnapshotChannelSelection {
  const owned = [...new Set(ownedChannelIds)].filter((channelId) =>
    youtubeChannelIdPattern.test(channelId)
  );
  const active = new Set(activeSnapshotChannelIds);
  const matches = owned.filter((channelId) => active.has(channelId));
  if (matches.length > 1) {
    throw new YouTubeMembershipVerificationError(
      'youtube_channel_ambiguous',
      409,
      'More than one channel owned by this Google account appears in the membership list.',
    );
  }
  if (matches.length === 1) {
    return { kind: 'selected', channelId: matches[0], isMember: true };
  }
  if (owned.length === 1) {
    return { kind: 'selected', channelId: owned[0], isMember: false };
  }
  return { kind: 'not_in_snapshot', channelId: null, isMember: false };
}

/** Decide whether a previously linked channel is still proven by Google. */
export function planUnmatchedPriorLink(
  priorChannelId: string | null | undefined,
  ownedChannelIds: string[],
): UnmatchedPriorLinkPlan {
  if (!priorChannelId) return { action: 'none', channelId: null };
  return [...new Set(ownedChannelIds)].includes(priorChannelId)
    ? { action: 'preserve', channelId: priorChannelId }
    : { action: 'revoke', channelId: priorChannelId };
}

async function clearVerifiedYouTubeLink(input: {
  userId: string;
  now: Date;
  reason: string;
}): Promise<void> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-membership-check:user:${input.userId}`],
    );
    await client.query(
      `SELECT pg_advisory_xact_lock_shared(
         hashtextextended('youtube-membership-snapshot-import', 0)
       )`,
    );
    const previous = await client.query(
      `SELECT youtube_channel_id, is_member
       FROM youtube_account_links
       WHERE user_id = $1
       FOR UPDATE`,
      [input.userId],
    );
    const prior = previous.rows[0] as
      | { youtube_channel_id: string; is_member: boolean }
      | undefined;
    await client.query(
      `UPDATE youtube_channel_claims
       SET status = 'revoked', reviewed_at = $2,
           reviewed_by_user_id = NULL, review_reason = $3,
           approved_snapshot_import_id = NULL,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1 AND status IN ('pending', 'approved')`,
      [input.userId, input.now, input.reason],
    );
    await client.query(
      `DELETE FROM youtube_account_links WHERE user_id = $1`,
      [input.userId],
    );
    await client.query(
      `UPDATE users
       SET is_youtube_member = FALSE, youtube_channel_id = NULL,
           youtube_member_since = NULL,
           youtube_membership_verified_at = $2,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [input.userId, input.now],
    );
    await client.query(
      `DELETE FROM user_roles WHERE user_id = $1 AND role_id = 'member'`,
      [input.userId],
    );
    if (prior) {
      await client.query(
        `INSERT INTO membership_history
           (user_id, status, verified_at, expires_at, metadata)
         VALUES ($1, 'inactive', $2, $2,
                 jsonb_build_object(
                   'source', 'google_oauth_channel_unavailable',
                   'youtubeChannelId', $3::text,
                   'reason', $4::text
                 ))`,
        [input.userId, input.now, prior.youtube_channel_id, input.reason],
      );
    }
    await client.query(
      `UPDATE youtube_membership_snapshot_imports snapshot_import
       SET matched_user_count = (
         SELECT COUNT(*)::integer
         FROM youtube_account_links link
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = link.user_id
          AND approved_claim.youtube_channel_id = link.youtube_channel_id
          AND approved_claim.status = 'approved'
         WHERE link.is_member = TRUE
           AND link.snapshot_import_id = snapshot_import.id
       )
       WHERE snapshot_import.id = (
         SELECT active_import_id
         FROM youtube_membership_snapshot_state
         WHERE singleton = TRUE
       )`,
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

type MembershipDatabaseClient = Awaited<ReturnType<typeof getClient>>;

/**
 * Reconcile an existing ownership link when Google returns multiple owned
 * channels but none is present in the current CSV. This runs inside the same
 * transaction and snapshot lock as the membership check.
 */
export async function reconcileUnmatchedOwnedChannels(input: {
  client: MembershipDatabaseClient;
  userId: string;
  ownedChannelIds: string[];
  snapshotId: string;
  now: Date;
}): Promise<UnmatchedPriorLinkPlan> {
  const identityRows = await input.client.query(
    `SELECT youtube_channel_id
     FROM youtube_account_links
     WHERE user_id = $1
     UNION
     SELECT youtube_channel_id
     FROM youtube_channel_claims
     WHERE user_id = $1 AND status = 'approved'`,
    [input.userId],
  );
  const identityChannelIds = [...new Set<string>(identityRows.rows
    .map((row) => row.youtube_channel_id)
    .filter((channelId): channelId is string =>
      typeof channelId === 'string' && youtubeChannelIdPattern.test(channelId)
    ))].sort();
  // Follow the same channel-lock order as ordinary verification before row
  // locks are acquired, preventing cross-account ownership races/deadlocks.
  for (const channelId of identityChannelIds) {
    await input.client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-membership-check:channel:${channelId}`],
    );
  }

  const previousLink = await input.client.query(
    `SELECT youtube_channel_id, is_member
     FROM youtube_account_links
     WHERE user_id = $1
     FOR UPDATE`,
    [input.userId],
  );
  const prior = previousLink.rows[0] as
    | { youtube_channel_id: string; is_member: boolean }
    | undefined;
  const plan = planUnmatchedPriorLink(
    prior?.youtube_channel_id,
    input.ownedChannelIds,
  );
  const activeClaims = await input.client.query(
    `SELECT id, youtube_channel_id
     FROM youtube_channel_claims
     WHERE user_id = $1 AND status = 'approved'
     FOR UPDATE`,
    [input.userId],
  );
  const ownedChannelSet = new Set(input.ownedChannelIds);
  const unownedClaimIds = activeClaims.rows
    .filter((claim) => !ownedChannelSet.has(claim.youtube_channel_id))
    .map((claim) => claim.id);
  if (unownedClaimIds.length > 0) {
    // Releasing the partial unique approval is essential: otherwise the real
    // owner of the old channel could prove ownership yet remain blocked.
    await input.client.query(
      `UPDATE youtube_channel_claims
       SET status = 'revoked', reviewed_at = $2,
           reviewed_by_user_id = NULL,
           review_reason =
             'Google no longer reports this channel as owned by the linked account.',
           approved_snapshot_import_id = NULL,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = ANY($1::uuid[])`,
      [unownedClaimIds, input.now],
    );
  }

  if (plan.action === 'preserve') {
    await input.client.query(
      `UPDATE youtube_account_links
       SET is_member = FALSE, membership_level_id = NULL,
           member_since = NULL, last_verified_at = $2,
           last_attempted_at = $2, last_error_code = NULL,
           verification_source = 'admin_snapshot',
           snapshot_import_id = NULL,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1 AND youtube_channel_id = $3`,
      [input.userId, input.now, plan.channelId],
    );
    const preservedClaim = activeClaims.rows.find(
      (claim) => claim.youtube_channel_id === plan.channelId,
    );
    if (preservedClaim) {
      await input.client.query(
        `UPDATE youtube_channel_claims
         SET reviewed_at = $2,
             review_reason =
               'Ownership reverified by Google; channel is not in the current CSV.',
             approved_snapshot_import_id = $3,
             ownership_verification_source = 'google_oauth',
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [preservedClaim.id, input.now, input.snapshotId],
      );
    } else {
      await input.client.query(
        `INSERT INTO youtube_channel_claims
           (user_id, youtube_channel_id, status, reviewed_at,
            reviewed_by_user_id, review_reason, approved_snapshot_import_id,
            ownership_verification_source)
         VALUES ($1, $2, 'approved', $3, NULL,
                 'Ownership reverified by Google; channel is not in the current CSV.',
                 $4, 'google_oauth')`,
        [input.userId, plan.channelId, input.now, input.snapshotId],
      );
    }
  } else if (plan.action === 'revoke') {
    await input.client.query(
      `DELETE FROM youtube_account_links
       WHERE user_id = $1 AND youtube_channel_id = $2`,
      [input.userId, plan.channelId],
    );
  }

  await input.client.query(
    `UPDATE users
     SET is_youtube_member = FALSE,
         youtube_channel_id = $2,
         youtube_member_since = NULL,
         youtube_membership_verified_at = $3,
         updated_at = CURRENT_TIMESTAMP
     WHERE id = $1`,
    [
      input.userId,
      plan.action === 'preserve' ? plan.channelId : null,
      input.now,
    ],
  );
  await input.client.query(
    `DELETE FROM user_roles WHERE user_id = $1 AND role_id = 'member'`,
    [input.userId],
  );
  if (prior && (prior.is_member || plan.action === 'revoke')) {
    await input.client.query(
      `INSERT INTO membership_history
         (user_id, status, verified_at, expires_at, metadata)
       VALUES ($1, 'inactive', $2, $2,
               jsonb_build_object(
                 'source', $3::text,
                 'youtubeChannelId', $4::text,
                 'ownedChannelCount', $5::integer,
                 'snapshotImportId', $6::text
               ))`,
      [
        input.userId,
        input.now,
        plan.action === 'revoke'
          ? 'google_oauth_owned_channels_changed'
          : 'google_oauth_csv_verification',
        prior.youtube_channel_id,
        input.ownedChannelIds.length,
        input.snapshotId,
      ],
    );
  }
  await input.client.query(
    `UPDATE youtube_membership_snapshot_imports snapshot_import
     SET matched_user_count = (
       SELECT COUNT(*)::integer
       FROM youtube_account_links link
       JOIN youtube_channel_claims approved_claim
         ON approved_claim.user_id = link.user_id
        AND approved_claim.youtube_channel_id = link.youtube_channel_id
        AND approved_claim.status = 'approved'
       WHERE link.is_member = TRUE
         AND link.snapshot_import_id = snapshot_import.id
     )
     WHERE snapshot_import.id = $1`,
    [input.snapshotId],
  );
  return plan;
}

async function linkVerifiedChannelAgainstSnapshot(input: {
  userId: string;
  ownedChannelIds: string[];
  now: Date;
}): Promise<YouTubeMembershipCheckResult> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-membership-check:user:${input.userId}`],
    );
    // Snapshot replacement takes the exclusive form of this lock. A shared
    // transaction lock keeps the selected CSV immutable through the link,
    // membership flag, member role, and history writes below.
    await client.query(
      `SELECT pg_advisory_xact_lock_shared(
         hashtextextended('youtube-membership-snapshot-import', 0)
       )`,
    );

    const snapshotResult = await client.query(
      `SELECT snapshot_import.id, snapshot_import.expires_at
       FROM youtube_membership_snapshot_state snapshot_state
       JOIN youtube_membership_snapshot_imports snapshot_import
         ON snapshot_import.id = snapshot_state.active_import_id
        AND snapshot_import.expires_at > $1
       WHERE snapshot_state.singleton = TRUE
       FOR SHARE OF snapshot_import`,
      [input.now],
    );
    const snapshot = snapshotResult.rows[0] as
      | { id: string; expires_at: Date }
      | undefined;
    if (!snapshot) {
      await client.query('COMMIT');
      return {
        membership: {
          status: 'snapshot_unavailable',
          isMember: false,
          ...(input.ownedChannelIds.length === 1
            ? { youtubeChannelId: input.ownedChannelIds[0] }
            : {}),
          verifiedAt: input.now.toISOString(),
        },
      };
    }

    const memberResult = await client.query<SnapshotMember>(
      `SELECT youtube_channel_id, membership_level, joined_at
       FROM youtube_membership_snapshot_members
       WHERE import_id = $1
         AND status = 'active'
         AND youtube_channel_id = ANY($2::varchar[])
       FOR SHARE`,
      [snapshot.id, input.ownedChannelIds],
    );
    const selection = selectYouTubeChannelForSnapshot(
      input.ownedChannelIds,
      memberResult.rows.map((row) => row.youtube_channel_id),
    );
    if (selection.kind === 'not_in_snapshot') {
      // There is no safe channel to persist and the product deliberately has
      // no manual picker/ID field. The authoritative answer is simply that
      // none of this Google account's owned channels is in the current CSV.
      await reconcileUnmatchedOwnedChannels({
        client,
        userId: input.userId,
        ownedChannelIds: input.ownedChannelIds,
        snapshotId: snapshot.id,
        now: input.now,
      });
      await client.query('COMMIT');
      return {
        membership: {
          status: 'not_in_snapshot',
          isMember: false,
          verifiedAt: input.now.toISOString(),
          snapshotExpiresAt: new Date(snapshot.expires_at).toISOString(),
        },
      };
    }

    const channelId = selection.channelId;
    const activeMember = selection.isMember
      ? memberResult.rows.find((row) => row.youtube_channel_id === channelId)
      : undefined;
    const isMember = selection.isMember;
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-membership-check:channel:${channelId}`],
    );

    const conflict = await client.query(
      `SELECT user_id
       FROM youtube_channel_claims
       WHERE youtube_channel_id = $1
         AND status = 'approved'
         AND user_id <> $2
       FOR UPDATE`,
      [channelId, input.userId],
    );
    const linkConflict = await client.query(
      `SELECT user_id
       FROM youtube_account_links
       WHERE youtube_channel_id = $1 AND user_id <> $2
       FOR UPDATE`,
      [channelId, input.userId],
    );
    if (conflict.rowCount || linkConflict.rowCount) {
      throw new YouTubeMembershipVerificationError(
        'youtube_channel_already_linked',
        409,
        'This YouTube channel is already linked to another Abu 3meer account.',
      );
    }

    const previousLink = await client.query(
      `SELECT youtube_channel_id, is_member
       FROM youtube_account_links
       WHERE user_id = $1
       FOR UPDATE`,
      [input.userId],
    );
    const prior = previousLink.rows[0] as
      | { youtube_channel_id: string; is_member: boolean }
      | undefined;
    const activeClaims = await client.query(
      `SELECT id, youtube_channel_id, status
       FROM youtube_channel_claims
       WHERE user_id = $1 AND status IN ('pending', 'approved')
       ORDER BY CASE status WHEN 'approved' THEN 0 ELSE 1 END, submitted_at DESC
       FOR UPDATE`,
      [input.userId],
    );
    const selectedClaim = activeClaims.rows.find(
      (claim) => claim.youtube_channel_id === channelId,
    );
    const supersededIds = activeClaims.rows
      .filter((claim) => claim.id !== selectedClaim?.id)
      .map((claim) => claim.id);
    if (supersededIds.length > 0) {
      await client.query(
        `UPDATE youtube_channel_claims
         SET status = 'superseded', reviewed_at = $2,
             reviewed_by_user_id = NULL,
             review_reason = 'Superseded by a newer Google-verified channel.',
             approved_snapshot_import_id = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = ANY($1::uuid[])`,
        [supersededIds, input.now],
      );
    }
    if (selectedClaim) {
      await client.query(
        `UPDATE youtube_channel_claims
         SET status = 'approved', reviewed_at = $2,
             reviewed_by_user_id = NULL,
             review_reason = 'Channel ownership verified by Google OAuth.',
             approved_snapshot_import_id = $3,
             ownership_verification_source = 'google_oauth',
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [selectedClaim.id, input.now, snapshot.id],
      );
    } else {
      await client.query(
        `INSERT INTO youtube_channel_claims
           (user_id, youtube_channel_id, status, reviewed_at,
            reviewed_by_user_id, review_reason, approved_snapshot_import_id,
            ownership_verification_source)
         VALUES ($1, $2, 'approved', $3, NULL,
                 'Channel ownership verified by Google OAuth.', $4,
                 'google_oauth')`,
        [input.userId, channelId, input.now, snapshot.id],
      );
    }

    await client.query(
      `INSERT INTO youtube_account_links
         (user_id, youtube_channel_id, is_member, membership_level_id,
          member_since, last_verified_at, last_attempted_at,
          last_error_code, verification_source, snapshot_import_id)
       VALUES ($1, $2, $3, $4, $5, $6, $6, NULL, 'admin_snapshot', $7)
       ON CONFLICT (user_id) DO UPDATE SET
         youtube_channel_id = EXCLUDED.youtube_channel_id,
         is_member = EXCLUDED.is_member,
         membership_level_id = EXCLUDED.membership_level_id,
         member_since = EXCLUDED.member_since,
         last_verified_at = EXCLUDED.last_verified_at,
         last_attempted_at = EXCLUDED.last_attempted_at,
         last_error_code = NULL,
         verification_source = 'admin_snapshot',
         snapshot_import_id = EXCLUDED.snapshot_import_id,
         updated_at = CURRENT_TIMESTAMP`,
      [
        input.userId,
        channelId,
        isMember,
        activeMember?.membership_level ?? null,
        activeMember?.joined_at ?? null,
        input.now,
        isMember ? snapshot.id : null,
      ],
    );
    await client.query(
      `UPDATE users
       SET is_youtube_member = $2,
           youtube_channel_id = $3,
           youtube_member_since = $4,
           youtube_membership_verified_at = $5,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [
        input.userId,
        isMember,
        channelId,
        activeMember?.joined_at ?? null,
        input.now,
      ],
    );
    if (isMember) {
      await client.query(
        `INSERT INTO user_roles (user_id, role_id)
         VALUES ($1, 'member') ON CONFLICT DO NOTHING`,
        [input.userId],
      );
    } else {
      await client.query(
        `DELETE FROM user_roles WHERE user_id = $1 AND role_id = 'member'`,
        [input.userId],
      );
    }

    if (
      !prior ||
      prior.youtube_channel_id !== channelId ||
      prior.is_member !== isMember
    ) {
      await client.query(
        `INSERT INTO membership_history
           (user_id, status, verified_at, expires_at, metadata)
         VALUES ($1, $2, $3, $4,
                 jsonb_build_object(
                   'source', 'google_oauth_csv_verification',
                   'snapshotImportId', $5::text,
                   'youtubeChannelId', $6::text,
                   'previousYoutubeChannelId', $7::text
                 ))`,
        [
          input.userId,
          isMember ? 'active' : 'inactive',
          input.now,
          isMember ? snapshot.expires_at : input.now,
          snapshot.id,
          channelId,
          prior?.youtube_channel_id ?? null,
        ],
      );
    }
    await client.query(
      `UPDATE youtube_membership_snapshot_imports snapshot_import
       SET matched_user_count = (
         SELECT COUNT(*)::integer
         FROM youtube_account_links link
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = link.user_id
          AND approved_claim.youtube_channel_id = link.youtube_channel_id
          AND approved_claim.status = 'approved'
         WHERE link.is_member = TRUE
           AND link.snapshot_import_id = snapshot_import.id
       )
       WHERE snapshot_import.id = $1`,
      [snapshot.id],
    );
    await client.query('COMMIT');

    return {
      membership: {
        status: isMember ? 'active' : 'not_in_snapshot',
        isMember,
        youtubeChannelId: channelId,
        membershipLevelId: activeMember?.membership_level ?? null,
        memberSince: activeMember?.joined_at
          ? new Date(activeMember.joined_at).toISOString()
          : null,
        verifiedAt: input.now.toISOString(),
        snapshotExpiresAt: new Date(snapshot.expires_at).toISOString(),
      },
    };
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (error instanceof YouTubeMembershipVerificationError) throw error;
    if (error?.code === '23505') {
      throw new YouTubeMembershipVerificationError(
        'youtube_channel_already_linked',
        409,
        'This YouTube channel is already linked to another Abu 3meer account.',
      );
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function checkYouTubeMembership(input: {
  userId: string;
  expectedGoogleSubject: string | null;
  accessToken: string;
}, options: {
  fetchImplementation?: FetchImplementation;
  now?: Date;
} = {}): Promise<YouTubeMembershipCheckResult> {
  if (!input.expectedGoogleSubject) {
    throw new YouTubeMembershipVerificationError(
      'youtube_google_account_not_linked',
      403,
      'Sign in to Abu 3meer with Google before checking YouTube membership.',
    );
  }

  const tokenInfo = await inspectGoogleAccessToken(input.accessToken, options);
  if (tokenInfo.subject !== input.expectedGoogleSubject) {
    throw new YouTubeMembershipVerificationError(
      'youtube_google_identity_mismatch',
      403,
      'Use the same Google account linked to your Abu 3meer account.',
    );
  }
  const ownedChannelIds = await fetchOwnedYouTubeChannelIds(
    input.accessToken,
    options,
  );
  const now = options.now ?? new Date();
  if (ownedChannelIds.length === 0) {
    await clearVerifiedYouTubeLink({
      userId: input.userId,
      now,
      reason: 'Google reports that this account owns no YouTube channel.',
    });
    return {
      membership: {
        status: 'no_youtube_channel',
        isMember: false,
        verifiedAt: now.toISOString(),
      },
    };
  }
  return linkVerifiedChannelAgainstSnapshot({
    userId: input.userId,
    ownedChannelIds,
    now,
  });
}
