import crypto from 'node:crypto';
import path from 'node:path';
import { getClient, query } from '../db/pool.js';
import {
  YouTubeMembershipLookup,
  youtubeChannelIdPattern,
} from './youtubeChannelId.js';

export const youtubeMembershipSnapshotHeaders = [
  'Member',
  'Link to profile',
  'Current level',
  'Total time on level (months)',
  'Total time as member (months)',
  'Last update',
  'Last update timestamp',
] as const;

export const youtubeMembershipSnapshotMaxBytes = 5 * 1024 * 1024;
export const youtubeMembershipSnapshotMaxRows = 50_000;
export const youtubeMembershipSnapshotDefaultMaxAgeHours = 168;

export class YouTubeMembershipSnapshotError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus = 400,
    message = 'The YouTube membership snapshot is invalid.',
  ) {
    super(message);
    this.name = 'YouTubeMembershipSnapshotError';
  }
}

export type ParsedYouTubeMembershipSnapshotRow = {
  youtubeChannelId: string;
  membershipLevel: string | null;
  totalTimeOnLevelMonths: number | null;
  totalTimeAsMemberMonths: number | null;
  sourceLastUpdate: string | null;
  sourceLastUpdateAt: Date | null;
  /** Current membership period start derived from a Joined/Re-joined event. */
  membershipPeriodStartedAt?: Date | null;
};

export type ParsedYouTubeMembershipSnapshot = {
  format: 'csv' | 'tsv';
  sourceFilename: string;
  sourceSha256: string;
  rows: ParsedYouTubeMembershipSnapshotRow[];
};

export type YouTubeMembershipSnapshotMetadata = {
  importId: string;
  sourceFilename: string;
  sourceFormat: 'csv' | 'tsv';
  sourceSha256: string;
  memberCount: number;
  matchedUserCount: number;
  activatedAt: Date;
  expiresAt?: Date;
};

export type ActiveYouTubeMembershipSnapshot = {
  importId: string;
  activatedAt: Date;
  expiresAt: Date;
  members: Map<string, ParsedYouTubeMembershipSnapshotRow>;
};

export type YouTubeMembershipSnapshotStatus = {
  status: 'active' | 'expired' | 'not_imported';
  importId: string | null;
  sourceFilename: string | null;
  sourceFormat: 'csv' | 'tsv' | null;
  sourceSha256: string | null;
  memberCount: number;
  matchedUserCount: number;
  activatedAt: string | null;
  expiresAt: string | null;
  maxAgeHours: number;
};

export interface YouTubeMembershipSnapshotStore {
  replaceSnapshot(input: {
    importedByUserId: string;
    parsed: ParsedYouTubeMembershipSnapshot;
    activatedAt: Date;
    expiresAt: Date;
    allowLargeDecrease?: boolean;
    ipAddress?: string | null;
    userAgent?: string | null;
  }): Promise<YouTubeMembershipSnapshotMetadata>;
  getActiveMetadata(): Promise<YouTubeMembershipSnapshotMetadata | null>;
  getMembers(
    importId: string,
    channelIds: string[],
  ): Promise<ParsedYouTubeMembershipSnapshotRow[]>;
}

function safeSnapshotFilename(value: string): string {
  const basename = path.basename(value.trim() || 'youtube-members.csv');
  const sanitized = basename
    .normalize('NFKC')
    .replace(/[^A-Za-z0-9._-]+/g, '_')
    .replace(/^\.+/, '')
    .slice(0, 180);
  return sanitized || 'youtube-members.csv';
}

function snapshotFormat(fileName: string, bytes: Buffer): 'csv' | 'tsv' {
  const extension = path.extname(fileName).toLowerCase();
  const oleHeader = bytes.subarray(0, 4).equals(
    Buffer.from([0xd0, 0xcf, 0x11, 0xe0]),
  );
  const zipHeader = bytes.subarray(0, 4).equals(
    Buffer.from([0x50, 0x4b, 0x03, 0x04]),
  );
  if (['.xls', '.xlsx', '.xlsm'].includes(extension) || oleHeader || zipHeader) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_spreadsheet_unsupported',
      415,
      'Excel files are not accepted. Export the YouTube members sheet as UTF-8 CSV or TSV and upload that file.',
    );
  }
  if (extension === '.csv') return 'csv';
  if (extension === '.tsv') return 'tsv';
  throw new YouTubeMembershipSnapshotError(
    'youtube_snapshot_file_type_unsupported',
    415,
    'Upload a .csv or .tsv export. Excel .xls and .xlsx files must first be exported as UTF-8 CSV.',
  );
}

function decodeUtf8(bytes: Buffer): string {
  if (bytes.length === 0) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_empty',
      400,
      'The uploaded CSV or TSV file is empty.',
    );
  }
  if (bytes.length > youtubeMembershipSnapshotMaxBytes) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_too_large',
      413,
      'The membership snapshot must be 5 MB or smaller.',
    );
  }
  if (
    (bytes[0] === 0xff && bytes[1] === 0xfe) ||
    (bytes[0] === 0xfe && bytes[1] === 0xff)
  ) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_encoding_unsupported',
      415,
      'Export the membership snapshot as UTF-8 CSV or TSV.',
    );
  }
  try {
    return new TextDecoder('utf-8', { fatal: true })
      .decode(bytes)
      .replace(/^\uFEFF/, '');
  } catch (_) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_encoding_unsupported',
      415,
      'The membership snapshot is not valid UTF-8. Export it as UTF-8 CSV or TSV.',
    );
  }
}

function parseDelimited(text: string, delimiter: ',' | '\t'): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"') {
        if (text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          quoted = false;
        }
      } else {
        field += character;
      }
      continue;
    }

    if (character === '"' && field.length === 0) {
      quoted = true;
    } else if (character === delimiter) {
      row.push(field);
      field = '';
    } else if (character === '\n' || character === '\r') {
      if (character === '\r' && text[index + 1] === '\n') index += 1;
      row.push(field);
      if (row.some((value) => value.length > 0)) rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
    if (field.length > 10_000) {
      throw new YouTubeMembershipSnapshotError(
        'youtube_snapshot_field_too_long',
        400,
        'A membership snapshot field is unexpectedly long.',
      );
    }
  }
  if (quoted) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_unclosed_quote',
      400,
      'The CSV or TSV contains an unclosed quoted field.',
    );
  }
  row.push(field);
  if (row.some((value) => value.length > 0)) rows.push(row);
  return rows;
}

export function extractYouTubeChannelIdFromProfileLink(value: string): string {
  let uri: URL;
  try {
    uri = new URL(value.trim());
  } catch (_) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_profile_link_invalid',
      400,
      'Each “Link to profile” value must be a complete YouTube channel URL.',
    );
  }
  const host = uri.hostname.toLowerCase();
  if (
    !['http:', 'https:'].includes(uri.protocol) ||
    !(host === 'youtube.com' || host.endsWith('.youtube.com'))
  ) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_profile_link_invalid',
      400,
      'Each “Link to profile” value must use a youtube.com channel URL.',
    );
  }
  const segments = uri.pathname.split('/').filter(Boolean);
  const channelId = segments[0] === 'channel' ? segments[1] ?? '' : '';
  if (segments.length !== 2 || !youtubeChannelIdPattern.test(channelId)) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_channel_id_missing',
      400,
      'A profile link does not contain a valid /channel/UC… YouTube channel ID.',
    );
  }
  return channelId;
}

function optionalMonths(value: string, rowNumber: number): number | null {
  const normalized = value.trim();
  if (!normalized) return null;
  const parsed = Number(normalized);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1000) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_duration_invalid',
      400,
      `Row ${rowNumber} contains an invalid membership duration.`,
    );
  }
  return parsed;
}

function optionalTimestamp(value: string, rowNumber: number): Date | null {
  const normalized = value.trim();
  if (!normalized) return null;
  let date: Date;
  if (/^\d{10,13}$/.test(normalized)) {
    const numeric = Number(normalized);
    date = new Date(normalized.length === 10 ? numeric * 1000 : numeric);
  } else {
    date = new Date(normalized);
  }
  if (!Number.isFinite(date.getTime())) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_timestamp_invalid',
      400,
      `Row ${rowNumber} contains an invalid “Last update timestamp”.`,
    );
  }
  return date;
}

export function parseYouTubeMembershipSnapshot(input: {
  bytes: Buffer;
  fileName: string;
}): ParsedYouTubeMembershipSnapshot {
  const format = snapshotFormat(input.fileName, input.bytes);
  const text = decodeUtf8(input.bytes);
  const table = parseDelimited(text, format === 'csv' ? ',' : '\t');
  const header = table.shift();
  if (
    !header ||
    header.length !== youtubeMembershipSnapshotHeaders.length ||
    youtubeMembershipSnapshotHeaders.some((expected, index) =>
      header[index] !== expected)
  ) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_headers_invalid',
      400,
      `The file must contain exactly these columns in order: ${youtubeMembershipSnapshotHeaders.join(', ')}.`,
    );
  }
  if (table.length > youtubeMembershipSnapshotMaxRows) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_too_many_rows',
      413,
      `The membership snapshot cannot exceed ${youtubeMembershipSnapshotMaxRows} member rows.`,
    );
  }

  const seen = new Set<string>();
  const rows = table.map((values, index) => {
    const rowNumber = index + 2;
    if (values.length !== youtubeMembershipSnapshotHeaders.length) {
      throw new YouTubeMembershipSnapshotError(
        'youtube_snapshot_columns_invalid',
        400,
        `Row ${rowNumber} does not contain exactly seven columns.`,
      );
    }
    // The exported display label is useful only to validate that this is a
    // complete YouTube Studio row. It is deliberately never returned or
    // persisted; channel ID is the sole matching key.
    const memberLabel = values[0].trim();
    if (!memberLabel || memberLabel.length > 500) {
      throw new YouTubeMembershipSnapshotError(
        'youtube_snapshot_member_label_invalid',
        400,
        `Row ${rowNumber} contains an invalid “Member” value.`,
      );
    }
    const channelId = extractYouTubeChannelIdFromProfileLink(values[1]);
    if (seen.has(channelId)) {
      throw new YouTubeMembershipSnapshotError(
        'youtube_snapshot_duplicate_channel',
        400,
        `Row ${rowNumber} repeats a YouTube channel already present in the snapshot.`,
      );
    }
    seen.add(channelId);
    const membershipLevel = values[2].trim();
    const sourceLastUpdate = values[5].trim();
    if (membershipLevel.length > 200 || sourceLastUpdate.length > 500) {
      throw new YouTubeMembershipSnapshotError(
        'youtube_snapshot_field_too_long',
        400,
        `Row ${rowNumber} contains an unexpectedly long field.`,
      );
    }
    return {
      youtubeChannelId: channelId,
      membershipLevel: membershipLevel || null,
      totalTimeOnLevelMonths: optionalMonths(values[3], rowNumber),
      totalTimeAsMemberMonths: optionalMonths(values[4], rowNumber),
      sourceLastUpdate: sourceLastUpdate || null,
      sourceLastUpdateAt: optionalTimestamp(values[6], rowNumber),
    };
  });

  return {
    format,
    sourceFilename: safeSnapshotFilename(input.fileName),
    sourceSha256: crypto.createHash('sha256').update(input.bytes).digest('hex'),
    rows,
  };
}

export function youtubeMembershipSnapshotMaxAgeHours(
  environment: NodeJS.ProcessEnv = process.env,
): number {
  const raw = environment.YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS ??
    String(youtubeMembershipSnapshotDefaultMaxAgeHours);
  const hours = Number(raw);
  if (!Number.isInteger(hours) || hours < 1 || hours > 720) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_ttl_invalid',
      500,
      'YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS must be an integer from 1 to 720.',
    );
  }
  return hours;
}

function snapshotExpiry(activatedAt: Date, maxAgeHours: number): Date {
  return new Date(activatedAt.getTime() + maxAgeHours * 60 * 60 * 1000);
}

export function youtubeSnapshotRequiresLargeDecreaseConfirmation(
  previousCount: number,
  nextCount: number,
): boolean {
  return nextCount === 0 || (
    previousCount > 0 && nextCount < Math.ceil(previousCount * 0.8)
  );
}

function membershipPeriodStartedAt(
  row: ParsedYouTubeMembershipSnapshotRow,
): Date | null {
  const event = row.sourceLastUpdate
    ?.trim()
    .toLocaleLowerCase('en-US')
    .replace(/[\s_-]+/g, '');
  return (event === 'joined' || event === 'rejoined')
    ? row.sourceLastUpdateAt
    : null;
}

export class PostgresYouTubeMembershipSnapshotStore
implements YouTubeMembershipSnapshotStore {
  async replaceSnapshot(input: {
    importedByUserId: string;
    parsed: ParsedYouTubeMembershipSnapshot;
    activatedAt: Date;
    expiresAt: Date;
    allowLargeDecrease?: boolean;
    ipAddress?: string | null;
    userAgent?: string | null;
  }): Promise<YouTubeMembershipSnapshotMetadata> {
    const client = await getClient();
    try {
      await client.query('BEGIN');
      await client.query(
        `SELECT pg_advisory_xact_lock(
           hashtextextended('youtube-membership-snapshot-import', 0)
         )`,
      );
      const previous = await client.query(
        `SELECT snapshot_state.active_import_id,
                snapshot_import.member_count
         FROM youtube_membership_snapshot_state snapshot_state
         JOIN youtube_membership_snapshot_imports snapshot_import
           ON snapshot_import.id = snapshot_state.active_import_id
         WHERE snapshot_state.singleton = TRUE
         FOR UPDATE OF snapshot_state, snapshot_import`,
      );
      const previousImportId = previous.rows[0]?.active_import_id ?? null;
      const lockedPreviousCount = Number(previous.rows[0]?.member_count ?? 0);
      const lockedNextCount = input.parsed.rows.length;
      if (
        youtubeSnapshotRequiresLargeDecreaseConfirmation(
          lockedPreviousCount,
          lockedNextCount,
        ) && input.allowLargeDecrease !== true
      ) {
        throw new YouTubeMembershipSnapshotError(
          'youtube_snapshot_large_decrease_confirmation_required',
          409,
          lockedPreviousCount > 0
            ? `The new export has ${lockedNextCount} members while the current snapshot has ${lockedPreviousCount}. Confirm that this is a complete export before replacing it.`
            : 'The export contains no members. Confirm that this complete empty export is intentional before replacing the snapshot.',
        );
      }
      const imported = await client.query(
        `INSERT INTO youtube_membership_snapshot_imports
           (imported_by_user_id, source_filename, source_format,
            source_sha256, member_count, activated_at, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          input.importedByUserId,
          input.parsed.sourceFilename,
          input.parsed.format,
          input.parsed.sourceSha256,
          input.parsed.rows.length,
          input.activatedAt,
          input.expiresAt,
        ],
      );
      const importId = imported.rows[0].id as string;
      if (previousImportId) {
        await client.query(
          `UPDATE youtube_membership_snapshot_imports
           SET superseded_at = $2
           WHERE id = $1 AND superseded_at IS NULL`,
          [previousImportId, input.activatedAt],
        );
      }

      // A full export is authoritative. Present channel IDs become active and
      // missing active IDs lapse at the import time. Only minimized channel
      // lifecycle data is retained; the uploaded file and display names are not.
      if (input.parsed.rows.length > 0) {
        await client.query(
          `INSERT INTO youtube_membership_snapshot_members
             (youtube_channel_id, import_id, membership_level,
              total_time_on_level_months, total_time_as_member_months,
              source_last_update, source_last_update_at, status, joined_at,
              last_seen_at, left_at, updated_at)
           SELECT row.youtube_channel_id, $1, row.membership_level,
                  row.total_time_on_level_months,
                  row.total_time_as_member_months,
                  row.source_last_update, row.source_last_update_at,
                  'active', row.membership_period_started_at,
                  $3, NULL, CURRENT_TIMESTAMP
           FROM jsonb_to_recordset($2::jsonb) AS row(
             youtube_channel_id VARCHAR(24),
             membership_level VARCHAR(200),
             total_time_on_level_months NUMERIC,
             total_time_as_member_months NUMERIC,
             source_last_update VARCHAR(500),
             source_last_update_at TIMESTAMPTZ,
             membership_period_started_at TIMESTAMPTZ
           )
           ON CONFLICT (youtube_channel_id) DO UPDATE SET
             import_id = EXCLUDED.import_id,
             membership_level = EXCLUDED.membership_level,
             total_time_on_level_months = EXCLUDED.total_time_on_level_months,
             total_time_as_member_months = EXCLUDED.total_time_as_member_months,
             source_last_update = EXCLUDED.source_last_update,
             source_last_update_at = EXCLUDED.source_last_update_at,
             status = 'active',
             joined_at = CASE
               WHEN youtube_membership_snapshot_members.status = 'lapsed'
                 THEN EXCLUDED.joined_at
               WHEN EXCLUDED.joined_at IS NOT NULL
                    AND (
                      youtube_membership_snapshot_members.joined_at IS NULL
                      OR EXCLUDED.joined_at >
                         youtube_membership_snapshot_members.joined_at
                    )
                 THEN EXCLUDED.joined_at
               ELSE youtube_membership_snapshot_members.joined_at
             END,
             last_seen_at = EXCLUDED.last_seen_at,
             left_at = NULL,
             updated_at = CURRENT_TIMESTAMP`,
          [
            importId,
            JSON.stringify(input.parsed.rows.map((row) => ({
              youtube_channel_id: row.youtubeChannelId,
              membership_level: row.membershipLevel,
              total_time_on_level_months: row.totalTimeOnLevelMonths,
              total_time_as_member_months: row.totalTimeAsMemberMonths,
              source_last_update: row.sourceLastUpdate,
              source_last_update_at: row.sourceLastUpdateAt?.toISOString() ?? null,
              membership_period_started_at:
                membershipPeriodStartedAt(row)?.toISOString() ?? null,
            }))),
            input.activatedAt,
          ],
        );
      }
      await client.query(
        `UPDATE youtube_membership_snapshot_members
         SET status = 'lapsed',
             -- The export has no cancellation timestamp. Import time is the
             -- first moment we can prove that this channel is no longer active.
             left_at = $2,
             updated_at = CURRENT_TIMESTAMP
         WHERE status = 'active'
           AND import_id <> $1`,
        [importId, input.activatedAt],
      );
      await client.query(
        `INSERT INTO youtube_membership_snapshot_state
           (singleton, active_import_id, updated_at)
         VALUES (TRUE, $1, $2)
         ON CONFLICT (singleton) DO UPDATE SET
           active_import_id = EXCLUDED.active_import_id,
           updated_at = EXCLUDED.updated_at`,
        [importId, input.activatedAt],
      );

      await client.query(
        `WITH observed AS (
           SELECT l.user_id, l.youtube_channel_id,
                  l.is_member AS was_member,
                  (
                    approved_claim.id IS NOT NULL
                    AND m.youtube_channel_id IS NOT NULL
                  ) AS is_member,
                  m.membership_level
           FROM youtube_account_links l
           LEFT JOIN youtube_channel_claims approved_claim
             ON approved_claim.user_id = l.user_id
            AND approved_claim.youtube_channel_id = l.youtube_channel_id
            AND approved_claim.status = 'approved'
           LEFT JOIN youtube_membership_snapshot_members m
             ON m.youtube_channel_id = l.youtube_channel_id
            AND m.import_id = $1
            AND m.status = 'active'
         )
         INSERT INTO membership_history
           (user_id, status, verified_at, expires_at, metadata)
         SELECT user_id,
                CASE WHEN is_member THEN 'active' ELSE 'inactive' END,
                $2, $3,
                jsonb_build_object(
                  'source', 'admin_snapshot',
                  'snapshotImportId', $1::text,
                  'youtubeChannelId', youtube_channel_id,
                  'membershipLevelId', membership_level
                )
         FROM observed
         WHERE was_member IS DISTINCT FROM is_member`,
        [importId, input.activatedAt, input.expiresAt],
      );

      await client.query(
        `WITH observed AS (
           SELECT l.user_id,
                  (
                    approved_claim.id IS NOT NULL
                    AND m.youtube_channel_id IS NOT NULL
                  ) AS is_member,
                  m.membership_level,
                  m.joined_at
           FROM youtube_account_links l
           LEFT JOIN youtube_channel_claims approved_claim
             ON approved_claim.user_id = l.user_id
            AND approved_claim.youtube_channel_id = l.youtube_channel_id
            AND approved_claim.status = 'approved'
           LEFT JOIN youtube_membership_snapshot_members m
             ON m.youtube_channel_id = l.youtube_channel_id
            AND m.import_id = $1
            AND m.status = 'active'
         )
         UPDATE youtube_account_links l
         SET is_member = observed.is_member,
             membership_level_id = CASE
               WHEN observed.is_member THEN observed.membership_level ELSE NULL
             END,
             member_since = CASE
               WHEN NOT observed.is_member THEN NULL
               ELSE observed.joined_at
             END,
             last_verified_at = $2,
             last_attempted_at = $2,
             last_error_code = NULL,
             verification_source = 'admin_snapshot',
             snapshot_import_id = CASE
               WHEN observed.is_member THEN $1 ELSE NULL
             END,
             updated_at = CURRENT_TIMESTAMP
         FROM observed
         WHERE l.user_id = observed.user_id`,
        [importId, input.activatedAt],
      );
      await client.query(
        `UPDATE users u
         SET is_youtube_member = l.is_member,
             youtube_channel_id = l.youtube_channel_id,
             youtube_member_since = CASE
               WHEN l.is_member THEN l.member_since ELSE NULL
             END,
             youtube_membership_verified_at = l.last_verified_at,
             updated_at = CURRENT_TIMESTAMP
         FROM youtube_account_links l
         WHERE l.user_id = u.id`,
      );
      await client.query(
        `INSERT INTO user_roles (user_id, role_id)
         SELECT link.user_id, 'member'
         FROM youtube_account_links link
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = link.user_id
          AND approved_claim.youtube_channel_id = link.youtube_channel_id
          AND approved_claim.status = 'approved'
         WHERE link.is_member = TRUE
         ON CONFLICT DO NOTHING`,
      );
      await client.query(
        `DELETE FROM user_roles r
         USING youtube_account_links l
         WHERE r.user_id = l.user_id
           AND r.role_id = 'member'
           AND l.is_member = FALSE`,
      );
      const matched = await client.query(
        `SELECT COUNT(*)::integer AS matched
         FROM youtube_account_links l
         JOIN youtube_channel_claims approved_claim
           ON approved_claim.user_id = l.user_id
          AND approved_claim.youtube_channel_id = l.youtube_channel_id
          AND approved_claim.status = 'approved'
         JOIN youtube_membership_snapshot_members m
           ON m.youtube_channel_id = l.youtube_channel_id
          AND m.import_id = $1
          AND m.status = 'active'`,
        [importId],
      );
      const matchedUserCount = Number(matched.rows[0]?.matched ?? 0);
      await client.query(
        `UPDATE youtube_membership_snapshot_imports
         SET matched_user_count = $2
         WHERE id = $1`,
        [importId, matchedUserCount],
      );
      await client.query(
        `INSERT INTO admin_audit_logs
           (admin_user_id, action, target_entity, target_id,
            before_state, after_state, ip_address, user_agent)
         VALUES ($1, 'youtube_membership_snapshot_imported',
                 'youtube_membership_snapshot', $2, $3::jsonb, $4::jsonb,
                 $5, $6)`,
        [
          input.importedByUserId,
          importId,
          JSON.stringify({ previousImportId }),
          JSON.stringify({
            sourceFormat: input.parsed.format,
            sourceSha256: input.parsed.sourceSha256,
            memberCount: input.parsed.rows.length,
            matchedUserCount,
            expiresAt: input.expiresAt.toISOString(),
          }),
          input.ipAddress?.slice(0, 50) ?? null,
          input.userAgent?.slice(0, 1000) ?? null,
        ],
      );
      await client.query('COMMIT');
      return {
        importId,
        sourceFilename: input.parsed.sourceFilename,
        sourceFormat: input.parsed.format,
        sourceSha256: input.parsed.sourceSha256,
        memberCount: input.parsed.rows.length,
        matchedUserCount,
        activatedAt: input.activatedAt,
        expiresAt: input.expiresAt,
      };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async getActiveMetadata(): Promise<YouTubeMembershipSnapshotMetadata | null> {
    const result = await query(
      `SELECT i.id, i.source_filename, i.source_format, i.source_sha256,
              i.member_count, i.matched_user_count, i.activated_at,
              i.expires_at
       FROM youtube_membership_snapshot_state s
       JOIN youtube_membership_snapshot_imports i
         ON i.id = s.active_import_id
       WHERE s.singleton = TRUE`,
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      importId: row.id,
      sourceFilename: row.source_filename,
      sourceFormat: row.source_format,
      sourceSha256: row.source_sha256,
      memberCount: Number(row.member_count),
      matchedUserCount: Number(row.matched_user_count),
      activatedAt: new Date(row.activated_at),
      expiresAt: row.expires_at ? new Date(row.expires_at) : undefined,
    };
  }

  async getMembers(
    importId: string,
    channelIds: string[],
  ): Promise<ParsedYouTubeMembershipSnapshotRow[]> {
    const uniqueChannelIds = [...new Set(channelIds)].filter((channelId) =>
      youtubeChannelIdPattern.test(channelId)
    );
    if (uniqueChannelIds.length === 0) return [];
    const result = await query(
      `SELECT youtube_channel_id, membership_level,
              total_time_on_level_months, total_time_as_member_months,
              source_last_update, source_last_update_at, joined_at
       FROM youtube_membership_snapshot_members
       WHERE import_id = $1
         AND status = 'active'
         AND youtube_channel_id = ANY($2::varchar[])`,
      [importId, uniqueChannelIds],
    );
    return result.rows.map((row) => ({
      youtubeChannelId: row.youtube_channel_id,
      membershipLevel: row.membership_level ?? null,
      totalTimeOnLevelMonths: row.total_time_on_level_months == null
        ? null
        : Number(row.total_time_on_level_months),
      totalTimeAsMemberMonths: row.total_time_as_member_months == null
        ? null
        : Number(row.total_time_as_member_months),
      sourceLastUpdate: row.source_last_update ?? null,
      sourceLastUpdateAt: row.source_last_update_at
        ? new Date(row.source_last_update_at)
        : null,
      membershipPeriodStartedAt: row.joined_at
        ? new Date(row.joined_at)
        : null,
    }));
  }
}

export async function getYouTubeMembershipSnapshotStatus(
  options: {
    store?: YouTubeMembershipSnapshotStore;
    now?: Date;
    environment?: NodeJS.ProcessEnv;
  } = {},
): Promise<YouTubeMembershipSnapshotStatus> {
  const store = options.store ?? new PostgresYouTubeMembershipSnapshotStore();
  const now = options.now ?? new Date();
  const maxAgeHours = youtubeMembershipSnapshotMaxAgeHours(options.environment);
  const metadata = await store.getActiveMetadata();
  if (!metadata) {
    return {
      status: 'not_imported',
      importId: null,
      sourceFilename: null,
      sourceFormat: null,
      sourceSha256: null,
      memberCount: 0,
      matchedUserCount: 0,
      activatedAt: null,
      expiresAt: null,
      maxAgeHours,
    };
  }
  const expiresAt = metadata.expiresAt ??
    snapshotExpiry(metadata.activatedAt, maxAgeHours);
  return {
    status: expiresAt.getTime() > now.getTime() ? 'active' : 'expired',
    importId: metadata.importId,
    sourceFilename: metadata.sourceFilename,
    sourceFormat: metadata.sourceFormat,
    sourceSha256: metadata.sourceSha256,
    memberCount: metadata.memberCount,
    matchedUserCount: metadata.matchedUserCount,
    activatedAt: metadata.activatedAt.toISOString(),
    expiresAt: expiresAt.toISOString(),
    maxAgeHours,
  };
}

/**
 * Enforce the currently configured maximum age at process startup. Import
 * rows retain their original expiry, but can never outlive a stricter policy
 * applied later. This also safely clamps pre-037 rows backfilled by migration.
 */
export async function clampYouTubeMembershipSnapshotExpiryToPolicy(
  options: {
    environment?: NodeJS.ProcessEnv;
    runQuery?: (text: string, params?: unknown[]) => Promise<unknown>;
  } = {},
): Promise<void> {
  const maxAgeHours = youtubeMembershipSnapshotMaxAgeHours(
    options.environment,
  );
  const runQuery = options.runQuery ?? query;
  await runQuery(
    `UPDATE youtube_membership_snapshot_imports
     SET expires_at = LEAST(
       expires_at,
       activated_at + ($1::integer * INTERVAL '1 hour')
     )
     WHERE expires_at >
       activated_at + ($1::integer * INTERVAL '1 hour')`,
    [maxAgeHours],
  );
}

export async function getActiveYouTubeMembershipSnapshot(
  channelIds: string[],
  options: {
    store?: YouTubeMembershipSnapshotStore;
    now?: Date;
    environment?: NodeJS.ProcessEnv;
  } = {},
): Promise<ActiveYouTubeMembershipSnapshot | null> {
  const store = options.store ?? new PostgresYouTubeMembershipSnapshotStore();
  const now = options.now ?? new Date();
  const metadata = await store.getActiveMetadata();
  if (!metadata) return null;
  const maxAgeHours = youtubeMembershipSnapshotMaxAgeHours(options.environment);
  const expiresAt = metadata.expiresAt ??
    snapshotExpiry(metadata.activatedAt, maxAgeHours);
  // Staff approval and the latest full export are both required. Once that
  // export expires it fails closed to x1 until staff uploads a current file.
  if (expiresAt.getTime() <= now.getTime()) return null;
  const rows = await store.getMembers(metadata.importId, channelIds);
  return {
    importId: metadata.importId,
    activatedAt: metadata.activatedAt,
    expiresAt,
    members: new Map(rows.map((row) => [row.youtubeChannelId, row])),
  };
}

export function membershipLookupFromSnapshot(
  channelIds: string[],
  snapshot: ActiveYouTubeMembershipSnapshot,
): YouTubeMembershipLookup {
  const matches = [...new Set(channelIds)]
    .map((channelId) => snapshot.members.get(channelId))
    .filter((row): row is ParsedYouTubeMembershipSnapshotRow => row != null);
  if (matches.length > 1) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_channel_ambiguous',
      409,
      'More than one channel owned by this account is present in the membership snapshot.',
    );
  }
  const match = matches[0];
  if (!match) {
    return {
      isMember: false,
      channelId: null,
      membershipLevelId: null,
      memberSince: null,
    };
  }
  return {
    isMember: true,
    channelId: match.youtubeChannelId,
    membershipLevelId: match.membershipLevel,
    // YouTube's total-time field is cumulative across churn and therefore is
    // not a current-period join date. Prefer the stored lifecycle value, then
    // a Joined/Re-joined event timestamp, and otherwise leave it unknown.
    memberSince: match.membershipPeriodStartedAt ??
      membershipPeriodStartedAt(match),
  };
}

export async function importYouTubeMembershipSnapshot(input: {
  bytes: Buffer;
  fileName: string;
  importedByUserId: string;
  allowLargeDecrease?: boolean;
  ipAddress?: string | null;
  userAgent?: string | null;
}, options: {
  store?: YouTubeMembershipSnapshotStore;
  now?: Date;
  environment?: NodeJS.ProcessEnv;
} = {}): Promise<YouTubeMembershipSnapshotStatus> {
  const store = options.store ?? new PostgresYouTubeMembershipSnapshotStore();
  const now = options.now ?? new Date();
  const maxAgeHours = youtubeMembershipSnapshotMaxAgeHours(options.environment);
  const parsed = parseYouTubeMembershipSnapshot({
    bytes: input.bytes,
    fileName: input.fileName,
  });
  const previous = await store.getActiveMetadata();
  const previousCount = previous?.memberCount ?? 0;
  const nextCount = parsed.rows.length;
  const wouldRemoveManyMembers =
    youtubeSnapshotRequiresLargeDecreaseConfirmation(previousCount, nextCount);
  if (wouldRemoveManyMembers && input.allowLargeDecrease !== true) {
    throw new YouTubeMembershipSnapshotError(
      'youtube_snapshot_large_decrease_confirmation_required',
      409,
      previousCount > 0
        ? `The new export has ${nextCount} members while the current snapshot has ${previousCount}. Confirm that this is a complete export before replacing it.`
        : 'The export contains no members. Confirm that this complete empty export is intentional before replacing the snapshot.',
    );
  }
  const expiresAt = snapshotExpiry(now, maxAgeHours);
  const imported = await store.replaceSnapshot({
    importedByUserId: input.importedByUserId,
    parsed,
    activatedAt: now,
    expiresAt,
    allowLargeDecrease: input.allowLargeDecrease,
    ipAddress: input.ipAddress,
    userAgent: input.userAgent,
  });
  return {
    status: 'active',
    importId: imported.importId,
    sourceFilename: imported.sourceFilename,
    sourceFormat: imported.sourceFormat,
    sourceSha256: imported.sourceSha256,
    memberCount: imported.memberCount,
    matchedUserCount: imported.matchedUserCount,
    activatedAt: imported.activatedAt.toISOString(),
    expiresAt: snapshotExpiry(imported.activatedAt, maxAgeHours).toISOString(),
    maxAgeHours,
  };
}
