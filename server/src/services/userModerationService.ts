import { query } from '../db/pool.js';

export type ModerationQuery = (
  text: string,
  params?: any[],
) => Promise<{ rows: any[]; rowCount?: number | null }>;

export class UserModerationError extends Error {
  constructor(
    public readonly code: 'moderation_target_not_found' | 'report_not_found',
    message: string,
    public readonly statusCode = 404,
  ) {
    super(message);
    this.name = 'UserModerationError';
  }
}

export interface ModerationPublicUser {
  publicId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

export interface BlockedUser extends ModerationPublicUser {
  blockedAt: string;
}

export interface UserReport {
  id: string;
  target: ModerationPublicUser;
  reason: string;
  details: string | null;
  status: 'open' | 'resolved' | 'dismissed';
  createdAt: string;
  updatedAt: string;
}

export interface AdminUserReport extends UserReport {
  reporterUserId: string;
  reportedUserId: string;
  reporter: ModerationPublicUser;
  resolvedAt: string | null;
  resolvedBy: ModerationPublicUser | null;
  resolutionNote: string | null;
}

function iso(value: unknown): string {
  const parsed = new Date(value as string | number | Date);
  if (!Number.isFinite(parsed.getTime())) {
    throw new Error('A moderation timestamp is invalid.');
  }
  return parsed.toISOString();
}

function publicUser(row: Record<string, any>, prefix = ''): ModerationPublicUser {
  return {
    publicId: String(row[`${prefix}username`]),
    username: String(row[`${prefix}username`]),
    displayName: String(row[`${prefix}display_name`]),
    // A report/block acknowledgement is still an end-user surface. Return a
    // neutral avatar there even if an older query supplies an uploaded URL.
    avatarUrl: null,
  };
}

function adminUser(row: Record<string, any>, prefix = ''): ModerationPublicUser {
  return {
    publicId: String(row[`${prefix}username`]),
    username: String(row[`${prefix}username`]),
    displayName: String(row[`${prefix}display_name`]),
    avatarUrl: row[`${prefix}avatar_url`] == null
      ? null
      : String(row[`${prefix}avatar_url`]),
  };
}

function targetLookupSql(parameter: string): string {
  return `SELECT id, username, display_name
          FROM users
          WHERE id::text = ${parameter}::text
             OR firebase_uid = ${parameter}::text
             OR LOWER(username) = LOWER(${parameter}::text)
          ORDER BY (id::text = ${parameter}::text) DESC,
                   (firebase_uid = ${parameter}::text) DESC
          LIMIT 1`;
}

/**
 * SQL predicate for personalized public reads. A relationship is hidden in
 * both directions: people cannot use a leaderboard/profile lookup to bypass a
 * block placed by either account.
 */
export function mutualBlockVisibilitySql(
  candidateUserSql: string,
  viewerParameterSql: string,
): string {
  return `(
    ${viewerParameterSql}::uuid IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM user_blocks visibility_block
      WHERE (
        visibility_block.blocker_user_id = ${viewerParameterSql}::uuid
        AND visibility_block.blocked_user_id = ${candidateUserSql}
      ) OR (
        visibility_block.blocker_user_id = ${candidateUserSql}
        AND visibility_block.blocked_user_id = ${viewerParameterSql}::uuid
      )
    )
  )`;
}

export function isSelfModerationTarget(
  identifier: string,
  user: { id: string; firebaseUid: string; username: string },
): boolean {
  const normalized = identifier.trim().toLowerCase();
  return normalized === user.id.toLowerCase()
    || normalized === user.firebaseUid.toLowerCase()
    || normalized === user.username.toLowerCase();
}

export async function reportUser(
  reporterUserId: string,
  targetIdentifier: string,
  input: { reason: string; details?: string },
  runQuery: ModerationQuery = query,
): Promise<UserReport> {
  const result = await runQuery(
    `WITH target AS (
       ${targetLookupSql('$2')}
     ), saved AS (
       INSERT INTO user_reports
         (reporter_user_id, reported_user_id, reason, details)
       SELECT $1::uuid, target.id, $3::varchar, $4::text
       FROM target
       WHERE TRUE
       ON CONFLICT (reporter_user_id, reported_user_id)
         WHERE status = 'open'
       DO UPDATE SET
         reason = EXCLUDED.reason,
         details = EXCLUDED.details,
         updated_at = CURRENT_TIMESTAMP
       RETURNING id, reported_user_id, reason, details, status,
                 created_at, updated_at
     )
     SELECT saved.*,
            target.username,
            target.display_name
     FROM saved
     JOIN target ON target.id = saved.reported_user_id`,
    [
      reporterUserId,
      targetIdentifier,
      input.reason,
      input.details?.trim() || null,
    ],
  );
  const row = result.rows[0];
  if (!row) {
    throw new UserModerationError(
      'moderation_target_not_found',
      'The user you are trying to report was not found.',
    );
  }
  return {
    id: String(row.id),
    target: publicUser(row),
    reason: String(row.reason),
    details: row.details == null ? null : String(row.details),
    status: row.status,
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at),
  };
}

export async function blockUser(
  blockerUserId: string,
  targetIdentifier: string,
  runQuery: ModerationQuery = query,
): Promise<BlockedUser> {
  const result = await runQuery(
    `WITH target AS (
       ${targetLookupSql('$2')}
     ), saved AS (
       INSERT INTO user_blocks (blocker_user_id, blocked_user_id)
       SELECT $1::uuid, target.id
       FROM target
       WHERE TRUE
       ON CONFLICT (blocker_user_id, blocked_user_id)
       DO UPDATE SET blocked_user_id = EXCLUDED.blocked_user_id
       RETURNING blocked_user_id, created_at
     )
     SELECT target.username, target.display_name,
            saved.created_at AS blocked_at
     FROM saved
     JOIN target ON target.id = saved.blocked_user_id`,
    [blockerUserId, targetIdentifier],
  );
  const row = result.rows[0];
  if (!row) {
    throw new UserModerationError(
      'moderation_target_not_found',
      'The user you are trying to block was not found.',
    );
  }
  return {
    ...publicUser(row),
    blockedAt: iso(row.blocked_at),
  };
}

export async function unblockUser(
  blockerUserId: string,
  targetIdentifier: string,
  runQuery: ModerationQuery = query,
): Promise<{ removed: boolean; user: ModerationPublicUser }> {
  const result = await runQuery(
    `WITH target AS (
       ${targetLookupSql('$2')}
     ), removed AS (
       DELETE FROM user_blocks user_block
       USING target
       WHERE user_block.blocker_user_id = $1::uuid
         AND user_block.blocked_user_id = target.id
       RETURNING user_block.blocked_user_id
     )
     SELECT target.username, target.display_name,
            EXISTS (SELECT 1 FROM removed) AS removed
     FROM target`,
    [blockerUserId, targetIdentifier],
  );
  const row = result.rows[0];
  if (!row) {
    throw new UserModerationError(
      'moderation_target_not_found',
      'The user you are trying to unblock was not found.',
    );
  }
  return {
    removed: row.removed === true,
    user: publicUser(row),
  };
}

export async function listBlockedUsers(
  blockerUserId: string,
  runQuery: ModerationQuery = query,
): Promise<BlockedUser[]> {
  const result = await runQuery(
    `SELECT blocked.username, blocked.display_name,
            user_block.created_at AS blocked_at
     FROM user_blocks user_block
     JOIN users blocked ON blocked.id = user_block.blocked_user_id
     WHERE user_block.blocker_user_id = $1::uuid
     ORDER BY user_block.created_at DESC, blocked.username`,
    [blockerUserId],
  );
  return result.rows.map(row => ({
    ...publicUser(row),
    blockedAt: iso(row.blocked_at),
  }));
}

function adminReport(row: Record<string, any>): AdminUserReport {
  const resolvedBy = row.resolver_username == null
    ? null
    : adminUser(row, 'resolver_');
  return {
    id: String(row.id),
    reporterUserId: String(row.reporter_user_id),
    reportedUserId: String(row.reported_user_id),
    reporter: adminUser(row, 'reporter_'),
    target: adminUser(row, 'reported_'),
    reason: String(row.reason),
    details: row.details == null ? null : String(row.details),
    status: row.status,
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at),
    resolvedAt: row.resolved_at == null ? null : iso(row.resolved_at),
    resolvedBy,
    resolutionNote: row.resolution_note == null
      ? null
      : String(row.resolution_note),
  };
}

const adminReportSelect = `
  report.id, report.reason, report.details, report.status,
  report.created_at, report.updated_at, report.resolved_at,
  report.resolution_note, report.reporter_user_id, report.reported_user_id,
  reporter.username AS reporter_username,
  reporter.display_name AS reporter_display_name,
  reporter.avatar_url AS reporter_avatar_url,
  reported.username AS reported_username,
  reported.display_name AS reported_display_name,
  reported.avatar_url AS reported_avatar_url,
  resolver.username AS resolver_username,
  resolver.display_name AS resolver_display_name,
  resolver.avatar_url AS resolver_avatar_url`;

export async function listUserReports(
  options: {
    status?: 'open' | 'resolved' | 'dismissed';
    limit: number;
    offset: number;
  },
  runQuery: ModerationQuery = query,
): Promise<{
  reports: AdminUserReport[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}> {
  const result = await runQuery(
    `WITH filtered_reports AS MATERIALIZED (
       SELECT ${adminReportSelect}
       FROM user_reports report
       JOIN users reporter ON reporter.id = report.reporter_user_id
       JOIN users reported ON reported.id = report.reported_user_id
       LEFT JOIN users resolver ON resolver.id = report.resolved_by_user_id
       WHERE ($1::varchar IS NULL OR report.status = $1::varchar)
     ), report_page AS (
       SELECT *
       FROM filtered_reports
       ORDER BY created_at DESC, id
       LIMIT $2::integer OFFSET $3::integer
     ), report_total AS (
       SELECT COUNT(*) AS total_count
       FROM filtered_reports
     )
     SELECT report_page.*, report_total.total_count
     FROM report_total
     LEFT JOIN report_page ON TRUE
     ORDER BY report_page.created_at DESC NULLS LAST, report_page.id`,
    [options.status ?? null, options.limit, options.offset],
  );
  // The LEFT JOIN deliberately returns one total-only row when the requested
  // offset is past the final report. Exclude that sentinel from the page.
  const reports = result.rows
    .filter(row => row.id != null)
    .map(adminReport);
  const total = Number(result.rows[0]?.total_count ?? 0);
  const safeTotal = Number.isSafeInteger(total) && total >= 0 ? total : 0;
  return {
    reports,
    total: safeTotal,
    limit: options.limit,
    offset: options.offset,
    hasMore: options.offset + reports.length < safeTotal,
  };
}

export async function resolveUserReport(
  adminUserId: string,
  reportId: string,
  input: {
    status: 'resolved' | 'dismissed';
    resolutionNote?: string;
  },
  runQuery: ModerationQuery = query,
): Promise<AdminUserReport> {
  const result = await runQuery(
    `WITH previous AS MATERIALIZED (
       SELECT *
       FROM user_reports
       WHERE id = $1::uuid
       FOR UPDATE
     ), updated AS (
       UPDATE user_reports report
       SET status = $2::varchar,
           resolved_at = COALESCE(previous.resolved_at, CURRENT_TIMESTAMP),
           resolved_by_user_id = $4::uuid,
           resolution_note = $3::text,
           updated_at = CURRENT_TIMESTAMP
       FROM previous
       WHERE report.id = previous.id
       RETURNING report.*
     ), audited AS (
       INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id,
          before_state, after_state)
       SELECT $4::uuid, 'user_report.resolve', 'user_report', updated.id::text,
              jsonb_build_object(
                'status', previous.status,
                'resolutionNote', previous.resolution_note
              ),
              jsonb_build_object(
                'status', updated.status,
                'resolutionNote', updated.resolution_note
              )
       FROM updated
       JOIN previous ON previous.id = updated.id
       RETURNING id
     )
     SELECT ${adminReportSelect}
     FROM updated report
     JOIN users reporter ON reporter.id = report.reporter_user_id
     JOIN users reported ON reported.id = report.reported_user_id
     LEFT JOIN users resolver ON resolver.id = report.resolved_by_user_id
     CROSS JOIN audited`,
    [
      reportId,
      input.status,
      input.resolutionNote?.trim() || null,
      adminUserId,
    ],
  );
  const row = result.rows[0];
  if (!row) {
    throw new UserModerationError(
      'report_not_found',
      'The report was not found.',
    );
  }
  return adminReport(row);
}
