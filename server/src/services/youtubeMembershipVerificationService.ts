import { getClient } from '../db/pool.js';
import { resolveYouTubeProfileChannelId, YouTubeProfileResolutionError } from './youtubeProfileResolver.js';
import {
  invalidatePointCaches,
  recordMembershipRewardCycleInTransaction,
} from './pointsService.js';

export type YouTubeMembershipCheckStatus =
  | 'active'
  | 'not_in_snapshot'
  | 'snapshot_unavailable';

export type YouTubeMembershipCheckResult = {
  membership: {
    status: YouTubeMembershipCheckStatus;
    isMember: boolean;
    youtubeChannelId: string;
    membershipLevelId?: string | null;
    memberSince?: string | null;
    verifiedAt: string;
    snapshotExpiresAt?: string;
    /** Manual YouTube membership is access, never an auto-renewing store sale. */
    accessSource: 'youtube' | 'none';
    willRenew: false;
    recheckRequiredAt?: string | null;
    /** A profile link establishes CSV eligibility, not proof of ownership. */
    verificationMethod: 'manual_profile_link';
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

type SnapshotMember = {
  youtube_channel_id: string;
  membership_level: string | null;
  joined_at: Date | null;
  total_time_as_member_months: string | number | null;
};

type MembershipDatabaseClient = Awaited<ReturnType<typeof getClient>>;

/**
 * Match a user-supplied stable channel link against the latest complete CSV.
 * The product deliberately permits self-declared links: this does not prove
 * that the signed-in user owns the YouTube channel. Keep that distinction in
 * every persisted receipt, while retaining one-channel/one-account uniqueness.
 * Named profile links are resolved on trusted public YouTube endpoints first.
 * No Google sign-in credential or membership API is used.
 */
export async function checkYouTubeMembership(input: {
  userId: string;
  profileLink: string;
}, options: {
  now?: Date;
  clientFactory?: () => Promise<MembershipDatabaseClient>;
  channelResolver?: (profileLink: string) => Promise<string>;
  recordMembershipCycle?: typeof recordMembershipRewardCycleInTransaction;
  invalidateCaches?: () => Promise<void>;
} = {}): Promise<YouTubeMembershipCheckResult> {
  let channelId: string;
  try {
    channelId = await (options.channelResolver ?? resolveYouTubeProfileChannelId)(input.profileLink);
  } catch (error) {
    if (error instanceof YouTubeProfileResolutionError) {
      throw new YouTubeMembershipVerificationError(error.code, error.httpStatus, error.message);
    }
    throw error;
  }
  const now = options.now ?? new Date();
  const client = await (options.clientFactory ?? getClient)();
  let pointsChanged = false;
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`,
      [`youtube-membership-check:user:${input.userId}`],
    );
    // A CSV import takes the exclusive version of this lock. Preserve one
    // snapshot through every entitlement, role, and audit write.
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
      [now],
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
          youtubeChannelId: channelId,
          verifiedAt: now.toISOString(),
          accessSource: 'none',
          willRenew: false,
          recheckRequiredAt: null,
          verificationMethod: 'manual_profile_link',
        },
      };
    }

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
        'This YouTube channel is already linked to another Abu 3meer account. Contact support if this is your channel.',
      );
    }

    const memberResult = await client.query<SnapshotMember>(
      `SELECT youtube_channel_id, membership_level, joined_at,
              total_time_as_member_months
       FROM youtube_membership_snapshot_members
       WHERE import_id = $1
         AND status = 'active'
         AND youtube_channel_id = $2
       FOR SHARE`,
      [snapshot.id, channelId],
    );
    const activeMember = memberResult.rows[0];
    const isMember = Boolean(activeMember);
    const parsedMembershipMonths = activeMember?.total_time_as_member_months == null
      ? null
      : Number(activeMember.total_time_as_member_months);
    const totalTimeAsMemberMonths = parsedMembershipMonths !== null
      && Number.isFinite(parsedMembershipMonths)
      && parsedMembershipMonths >= 0
      ? parsedMembershipMonths
      : null;
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
             review_reason = 'Superseded by a newer user-submitted channel profile link.',
             approved_snapshot_import_id = NULL,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = ANY($1::uuid[])`,
        [supersededIds, now],
      );
    }
    // "approved" is the legacy schema's accepted-link state, not a staff or
    // OAuth ownership decision. CSV presence still determines all benefits.
    if (selectedClaim) {
      await client.query(
        `UPDATE youtube_channel_claims
         SET status = 'approved', reviewed_at = $2,
             reviewed_by_user_id = NULL,
             review_reason = 'User-submitted profile link checked against the current CSV; channel ownership not independently verified.',
             approved_snapshot_import_id = $3,
             ownership_verification_source = 'manual_profile_link',
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [selectedClaim.id, now, snapshot.id],
      );
    } else {
      await client.query(
        `INSERT INTO youtube_channel_claims
           (user_id, youtube_channel_id, status, reviewed_at,
            reviewed_by_user_id, review_reason, approved_snapshot_import_id,
            ownership_verification_source)
         VALUES ($1, $2, 'approved', $3, NULL,
                 'User-submitted profile link checked against the current CSV; channel ownership not independently verified.',
                 $4, 'manual_profile_link')`,
        [input.userId, channelId, now, snapshot.id],
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
        now,
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
        now,
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
                   'source', 'manual_profile_link_csv_check',
                   'ownershipVerified', FALSE,
                   'snapshotImportId', $5::text,
                   'youtubeChannelId', $6::text,
                   'previousYoutubeChannelId', $7::text
                 ))`,
        [
          input.userId,
          isMember ? 'active' : 'inactive',
          now,
          isMember ? snapshot.expires_at : now,
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
          AND approved_claim.approved_snapshot_import_id = snapshot_import.id
         WHERE link.is_member = TRUE
           AND link.snapshot_import_id = snapshot_import.id
       )
       WHERE snapshot_import.id = $1`,
      [snapshot.id],
    );
    const recordMembershipCycle = options.recordMembershipCycle
      // Unit/data-repair callers can inject an isolated client. Production
      // uses the real ledger in this same transaction by default.
      ?? (options.clientFactory === undefined
        ? recordMembershipRewardCycleInTransaction
        : undefined);
    if (isMember && recordMembershipCycle) {
      const reward = await recordMembershipCycle(client, {
        userId: input.userId,
        provider: 'youtube',
        // A replacement CSV is only a new verification lease. Renewal XP
        // requires YouTube's cumulative tenure to increase; when that field is
        // unavailable, the stable zero baseline permits activation only.
        cycleKey: totalTimeAsMemberMonths === null
          ? 'tenure:unknown'
          : `tenure:months:${totalTimeAsMemberMonths}`,
        cycleSequence: totalTimeAsMemberMonths ?? 0,
        observedAt: now,
      });
      pointsChanged = reward.activationPoints > 0 || reward.renewalPoints > 0;
    }
    await client.query('COMMIT');
    if (pointsChanged) {
      await (options.invalidateCaches ?? invalidatePointCaches)();
    }
    return {
      membership: {
        status: isMember ? 'active' : 'not_in_snapshot',
        isMember,
        youtubeChannelId: channelId,
        membershipLevelId: activeMember?.membership_level ?? null,
        memberSince: activeMember?.joined_at
          ? new Date(activeMember.joined_at).toISOString()
          : null,
        verifiedAt: now.toISOString(),
        snapshotExpiresAt: new Date(snapshot.expires_at).toISOString(),
        accessSource: isMember ? 'youtube' : 'none',
        willRenew: false,
        recheckRequiredAt: isMember
          ? new Date(snapshot.expires_at).toISOString()
          : null,
        verificationMethod: 'manual_profile_link',
      },
    };
  } catch (error: any) {
    await client.query('ROLLBACK').catch(() => undefined);
    if (error instanceof YouTubeMembershipVerificationError) throw error;
    if (error?.code === '23505') {
      throw new YouTubeMembershipVerificationError(
        'youtube_channel_already_linked',
        409,
        'This YouTube channel is already linked to another Abu 3meer account. Contact support if this is your channel.',
      );
    }
    throw error;
  } finally {
    client.release();
  }
}
