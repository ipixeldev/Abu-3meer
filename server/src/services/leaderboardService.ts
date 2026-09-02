import { getClient, query } from '../db/pool.js';

export const eligibleLeaderboardSourceTypes = [
  'signup_bonus',
  'daily_streak',
  'prediction_exact',
  'prediction_scorer',
  'prediction_winner',
  'prediction_win',
  'video_phrase',
  'player_card',
] as const;

export type LeaderboardScope = 'current_month' | 'previous_month' | 'season';

export interface LeaderboardEntry {
  /** Backward-compatible public profile handle used by existing app builds. */
  userId: string;
  /** Explicit public profile handle for newer app builds. */
  publicId: string;
  rank: number;
  points: number;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  supportedTeam: string;
  isYouTubeMember: boolean;
}

export interface LeaderboardSeason {
  id: string;
  displayName: string;
  startsAt: string;
  endsAt: string | null;
  active: boolean;
  managementMode: 'automatic' | 'manual';
  updatedAt: string;
}

export interface ManualLeaderboardSeasonInput {
  id: string;
  displayName: string;
  startsAt: Date | string;
  endsAt: Date | string;
  reason: string;
}

export interface LeaderboardPeriod {
  id: string;
  type: 'monthly' | 'season';
  displayName: string;
  startsAt: string;
  endsAt: string | null;
}

export interface LeaderboardSnapshot {
  leaderboard: LeaderboardEntry[];
  currentUser: LeaderboardEntry | null;
  totalPlayers: number;
  seasons: LeaderboardSeason[];
  activeSeasonId: string | null;
  period: LeaderboardPeriod;
}

export interface UserPeriodRank {
  rank: number;
  points: number;
}

interface PeriodWindow {
  id: string;
  type: 'monthly' | 'season';
  displayName: string;
  startsAt: Date;
  endsAt: Date | null;
}

export interface RankedRow {
  publicId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  supportedTeam: string;
  isYouTubeMember: boolean;
  points: string | number;
  rank: string | number;
  totalPlayers: string | number;
  isCurrentUser?: boolean;
}

interface SeasonRow {
  id: string;
  displayName: string;
  startsAt: Date | string;
  endsAt: Date | string | null;
  active: boolean;
  managementMode: 'automatic' | 'manual';
  updatedAt: Date | string;
}

export interface FootballSeasonMatchRow {
  seasonId: string;
  seasonName: string;
  seasonStartsAt: Date | string;
  kickoffAt: Date | string;
  status: string | null;
  homeTeam: string;
  awayTeam: string;
}

export interface DiscoveredLeaderboardSeason {
  id: string;
  displayName: string;
  startsAt: Date;
}

export const initialLeaderboardSeasonStart = '2026-08-30T15:00:00.000Z';
const initialLeaderboardSeasonStartMs = Date.parse(initialLeaderboardSeasonStart);
const trackedLeaderboardClubNames = new Set([
  'realmadrid',
  'realmadridcf',
  'realmadridclubdefutbol',
  'barcelona',
  'fcbarcelona',
  'barcelonafc',
  'futbolclubbarcelona',
]);

const eligibleSourceSql = eligibleLeaderboardSourceTypes
  .map(source => `'${source}'`)
  .join(', ');

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function requestError(
  name: string,
  message: string,
  statusCode: number,
): Error & { statusCode: number } {
  return Object.assign(new Error(message), { name, statusCode });
}

function parseFiniteDate(value: Date | string, field: string): Date {
  const parsed = value instanceof Date
    ? new Date(value.getTime())
    : new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw requestError('ValidationError', `${field} must be a valid date.`, 400);
  }
  return parsed;
}

export function validateManualLeaderboardSeasonWindow(
  startsAt: Date | string,
  endsAt: Date | string,
): { startsAt: Date; endsAt: Date } {
  const start = parseFiniteDate(startsAt, 'startsAt');
  const end = parseFiniteDate(endsAt, 'endsAt');
  if (start.getTime() >= end.getTime()) {
    throw requestError(
      'ValidationError',
      'The season start must be before the season end.',
      400,
    );
  }
  return { startsAt: start, endsAt: end };
}

export function leaderboardSeasonWindowsOverlap(
  leftStartsAt: Date | string,
  leftEndsAt: Date | string,
  rightStartsAt: Date | string,
  rightEndsAt: Date | string,
): boolean {
  const left = validateManualLeaderboardSeasonWindow(leftStartsAt, leftEndsAt);
  const right = validateManualLeaderboardSeasonWindow(rightStartsAt, rightEndsAt);
  return left.startsAt < right.endsAt && right.startsAt < left.endsAt;
}

function mappedSeason(row: SeasonRow): LeaderboardSeason {
  return {
    id: row.id,
    displayName: row.displayName,
    startsAt: iso(row.startsAt),
    endsAt: row.endsAt == null ? null : iso(row.endsAt),
    active: row.active,
    managementMode: row.managementMode,
    updatedAt: iso(row.updatedAt),
  };
}

function monthDisplayName(value: Date): string {
  return new Intl.DateTimeFormat('en', {
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(value);
}

function normalizedFootballClubName(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

export function isTrackedLeaderboardClubName(value: string): boolean {
  return trackedLeaderboardClubNames.has(normalizedFootballClubName(value));
}

/**
 * Finds the immutable start for each later football season. A season is not
 * eligible until a configured Real Madrid or Barcelona fixture exists, and a
 * cancelled/postponed fixture can never establish its boundary.
 */
export function discoverFutureLeaderboardSeasons(
  rows: FootballSeasonMatchRow[],
): DiscoveredLeaderboardSeason[] {
  const discovered = new Map<string, DiscoveredLeaderboardSeason>();
  for (const row of rows) {
    const id = row.seasonId.trim();
    const seasonStartsAt = new Date(row.seasonStartsAt).getTime();
    const kickoffAt = new Date(row.kickoffAt);
    const kickoffMs = kickoffAt.getTime();
    const status = row.status?.trim().toLowerCase() ?? '';
    if (!id ||
        !Number.isFinite(seasonStartsAt) ||
        !Number.isFinite(kickoffMs) ||
        seasonStartsAt <= initialLeaderboardSeasonStartMs ||
        kickoffMs <= initialLeaderboardSeasonStartMs ||
        kickoffMs < seasonStartsAt ||
        status === 'cancelled' ||
        status === 'postponed' ||
        (!isTrackedLeaderboardClubName(row.homeTeam) &&
         !isTrackedLeaderboardClubName(row.awayTeam))) {
      continue;
    }

    const previous = discovered.get(id);
    if (previous && previous.startsAt.getTime() <= kickoffMs) continue;
    discovered.set(id, {
      id,
      displayName: row.seasonName.trim() || id,
      startsAt: kickoffAt,
    });
  }

  return [...discovered.values()].sort((left, right) =>
    left.startsAt.getTime() - right.startsAt.getTime() ||
    left.id.localeCompare(right.id));
}

async function refreshDiscoveredLeaderboardSeasons(): Promise<void> {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended('leaderboard-season-discovery', 0))`,
    );
    const footballRows = await client.query<FootballSeasonMatchRow>(
      `SELECT season.id AS "seasonId",
              season.name AS "seasonName",
              season.starts_at AS "seasonStartsAt",
              match.kickoff_at AS "kickoffAt",
              match.status,
              COALESCE(NULLIF(BTRIM(home_team.normalized_name), ''), match.home_team) AS "homeTeam",
              COALESCE(NULLIF(BTRIM(away_team.normalized_name), ''), match.away_team) AS "awayTeam"
       FROM seasons season
       JOIN matches match ON match.season_id = season.id
       LEFT JOIN teams home_team ON home_team.id = match.home_team_id
       LEFT JOIN teams away_team ON away_team.id = match.away_team_id
       WHERE season.starts_at > $1
       ORDER BY season.starts_at, match.kickoff_at, match.id`,
      [new Date(initialLeaderboardSeasonStart)],
    );

    for (const season of discoverFutureLeaderboardSeasons(footballRows.rows)) {
      // Never update starts_at on conflict. Once a period is discovered, later
      // fixture edits or postponements must not rewrite historical XP windows.
      // A manually configured window always wins: discovery will neither
      // mutate it nor insert another automatic period inside it.
      await client.query(
        `INSERT INTO leaderboard_periods
           (id, type, name, starts_at, ends_at, is_current, management_mode)
         SELECT $1, 'season', $2, $3, NULL, FALSE, 'automatic'
         WHERE NOT EXISTS (
           SELECT 1
           FROM leaderboard_periods manual_period
           WHERE manual_period.type = 'season'
             AND manual_period.management_mode = 'manual'
             AND manual_period.starts_at <= $3
             AND manual_period.ends_at > $3
         )
         ON CONFLICT (id) DO NOTHING`,
        [season.id, season.displayName, season.startsAt],
      );
    }

    // Clear first to avoid transient conflicts with the partial unique index
    // when the active season changes in the same transaction.
    await client.query(
      `UPDATE leaderboard_periods
       SET is_current = FALSE
       WHERE type = 'season'
         AND is_current = TRUE`,
    );
    await client.query(
      `WITH ordered AS (
         SELECT id,
                LEAD(starts_at) OVER (ORDER BY starts_at, id) AS next_start
         FROM leaderboard_periods
         WHERE type = 'season'
           AND starts_at >= $1
       )
       UPDATE leaderboard_periods period
       SET ends_at = ordered.next_start,
           updated_at = CURRENT_TIMESTAMP
       FROM ordered
       WHERE period.id = ordered.id
         AND period.management_mode = 'automatic'
         AND period.ends_at IS DISTINCT FROM ordered.next_start`,
      [new Date(initialLeaderboardSeasonStart)],
    );
    // A schedule can be configured in advance. Keep the preceding season
    // active until the first qualifying fixture actually kicks off.
    await client.query(
      `UPDATE leaderboard_periods
       SET is_current = TRUE
       WHERE id = (
         SELECT id
         FROM leaderboard_periods
         WHERE type = 'season'
           AND starts_at <= CURRENT_TIMESTAMP
           AND (ends_at IS NULL OR ends_at > CURRENT_TIMESTAMP)
         ORDER BY (management_mode = 'manual') DESC, starts_at DESC, id DESC
         LIMIT 1
       )`,
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

export function utcMonthWindow(
  scope: 'current_month' | 'previous_month',
  now = new Date(),
): PeriodWindow {
  if (!Number.isFinite(now.getTime())) throw new Error('Leaderboard date is invalid.');
  const offset = scope === 'previous_month' ? -1 : 0;
  const startsAt = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth() + offset,
    1,
  ));
  const endsAt = new Date(Date.UTC(
    startsAt.getUTCFullYear(),
    startsAt.getUTCMonth() + 1,
    1,
  ));
  return {
    id: startsAt.toISOString().slice(0, 7),
    type: 'monthly',
    displayName: monthDisplayName(startsAt),
    startsAt,
    endsAt,
  };
}

export async function listLeaderboardSeasons(): Promise<LeaderboardSeason[]> {
  await refreshDiscoveredLeaderboardSeasons();
  const result = await query<SeasonRow>(
    `SELECT id,
            name AS "displayName",
            starts_at AS "startsAt",
            ends_at AS "endsAt",
            is_current AS active,
            management_mode AS "managementMode",
            updated_at AS "updatedAt"
     FROM leaderboard_periods
     WHERE type = 'season'
     ORDER BY starts_at DESC, id DESC`,
  );
  return result.rows.map(mappedSeason);
}

async function selectSeasonForUpdate(
  client: Awaited<ReturnType<typeof getClient>>,
  id: string,
): Promise<SeasonRow | null> {
  const result = await client.query<SeasonRow>(
    `SELECT id,
            name AS "displayName",
            starts_at AS "startsAt",
            ends_at AS "endsAt",
            is_current AS active,
            management_mode AS "managementMode",
            updated_at AS "updatedAt"
     FROM leaderboard_periods
     WHERE id = $1 AND type = 'season'
     FOR UPDATE`,
    [id],
  );
  return result.rows[0] ?? null;
}

async function assertSeasonWindowDoesNotOverlap(
  client: Awaited<ReturnType<typeof getClient>>,
  startsAt: Date,
  endsAt: Date,
  excludedId?: string,
): Promise<void> {
  const overlap = await client.query<{ id: string; displayName: string }>(
    `SELECT id, name AS "displayName"
     FROM leaderboard_periods
     WHERE type = 'season'
       AND ($3::text IS NULL OR id <> $3)
       AND tstzrange(starts_at, COALESCE(ends_at, 'infinity'::timestamptz), '[)')
           && tstzrange($1::timestamptz, $2::timestamptz, '[)')
     ORDER BY starts_at, id
     LIMIT 1`,
    [startsAt, endsAt, excludedId ?? null],
  );
  if ((overlap.rowCount ?? 0) > 0) {
    throw requestError(
      'SeasonWindowConflict',
      `This season overlaps ${overlap.rows[0].displayName} (${overlap.rows[0].id}). Edit the existing period boundaries first.`,
      409,
    );
  }
}

async function recalculateCurrentSeason(
  client: Awaited<ReturnType<typeof getClient>>,
): Promise<void> {
  await client.query(
    `UPDATE leaderboard_periods
     SET is_current = FALSE
     WHERE type = 'season' AND is_current = TRUE`,
  );
  await client.query(
    `UPDATE leaderboard_periods
     SET is_current = TRUE
     WHERE id = (
       SELECT id
       FROM leaderboard_periods
       WHERE type = 'season'
         AND starts_at <= CURRENT_TIMESTAMP
         AND (ends_at IS NULL OR ends_at > CURRENT_TIMESTAMP)
       ORDER BY (management_mode = 'manual') DESC, starts_at DESC, id DESC
       LIMIT 1
     )`,
  );
}

/**
 * Creates or explicitly edits a season window. Switching an automatically
 * discovered period to manual is intentional and permanent: background
 * discovery only updates rows that remain in automatic mode.
 */
export async function saveManualLeaderboardSeason(
  input: ManualLeaderboardSeasonInput,
  adminUserId: string,
  existingId?: string,
): Promise<LeaderboardSeason> {
  const id = input.id.trim();
  const displayName = input.displayName.trim();
  const reason = input.reason.trim();
  const window = validateManualLeaderboardSeasonWindow(input.startsAt, input.endsAt);
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$/.test(id)) {
    throw requestError(
      'ValidationError',
      'Season ID must use 1-50 letters, numbers, dots, underscores, or hyphens.',
      400,
    );
  }
  if (!displayName || displayName.length > 100) {
    throw requestError('ValidationError', 'Season name must use 1-100 characters.', 400);
  }
  if (reason.length < 3 || reason.length > 255) {
    throw requestError('ValidationError', 'An audit reason of 3-255 characters is required.', 400);
  }

  const client = await getClient();
  try {
    await client.query('BEGIN');
    await client.query(
      `SELECT pg_advisory_xact_lock(hashtextextended('leaderboard-season-discovery', 0))`,
    );
    const currentId = existingId?.trim();
    const before = currentId ? await selectSeasonForUpdate(client, currentId) : null;
    if (currentId && !before) {
      throw requestError('NotFound', 'Leaderboard season not found.', 404);
    }
    if (!currentId) {
      const duplicate = await client.query(
        `SELECT 1 FROM leaderboard_periods WHERE id = $1 FOR UPDATE`,
        [id],
      );
      if ((duplicate.rowCount ?? 0) > 0) {
        throw requestError('Conflict', 'A leaderboard period already uses this ID.', 409);
      }
    } else if (id !== currentId) {
      throw requestError('ValidationError', 'An existing season ID cannot be changed.', 400);
    }

    await assertSeasonWindowDoesNotOverlap(
      client,
      window.startsAt,
      window.endsAt,
      currentId,
    );

    const persisted = currentId
      ? await client.query<SeasonRow>(
          `UPDATE leaderboard_periods
           SET name = $2,
               starts_at = $3,
               ends_at = $4,
               management_mode = 'manual',
               updated_at = CURRENT_TIMESTAMP,
               updated_by = $5
           WHERE id = $1 AND type = 'season'
           RETURNING id,
                     name AS "displayName",
                     starts_at AS "startsAt",
                     ends_at AS "endsAt",
                     is_current AS active,
                     management_mode AS "managementMode",
                     updated_at AS "updatedAt"`,
          [id, displayName, window.startsAt, window.endsAt, adminUserId],
        )
      : await client.query<SeasonRow>(
          `INSERT INTO leaderboard_periods
             (id, type, name, starts_at, ends_at, is_current,
              management_mode, updated_at, updated_by)
           VALUES ($1, 'season', $2, $3, $4, FALSE, 'manual', CURRENT_TIMESTAMP, $5)
           RETURNING id,
                     name AS "displayName",
                     starts_at AS "startsAt",
                     ends_at AS "endsAt",
                     is_current AS active,
                     management_mode AS "managementMode",
                     updated_at AS "updatedAt"`,
          [id, displayName, window.startsAt, window.endsAt, adminUserId],
        );

    await recalculateCurrentSeason(client);
    const saved = await selectSeasonForUpdate(client, id);
    if (!saved || persisted.rowCount === 0) {
      throw new Error('The leaderboard season could not be persisted.');
    }
    const after = mappedSeason(saved);
    await client.query(
      `INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id, before_state, after_state)
       VALUES ($1, $2, 'leaderboard_period', $3, $4, $5)`,
      [
        adminUserId,
        currentId ? 'leaderboard_season.update' : 'leaderboard_season.create',
        id,
        before == null ? null : JSON.stringify(mappedSeason(before)),
        JSON.stringify({ ...after, reason }),
      ],
    );
    await client.query('COMMIT');
    return after;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

function resolveSeasonWindow(
  seasons: LeaderboardSeason[],
  selectedSeasonId?: string,
): PeriodWindow {
  const selected = selectedSeasonId?.trim()
    ? seasons.find(season => season.id === selectedSeasonId.trim())
    : seasons.find(season => season.active) ?? seasons[0];
  if (!selected) {
    throw Object.assign(new Error('Leaderboard season not found.'), {
      name: 'NotFound',
      statusCode: 404,
    });
  }
  return {
    id: selected.id,
    type: 'season',
    displayName: selected.displayName,
    startsAt: new Date(selected.startsAt),
    endsAt: selected.endsAt == null ? null : new Date(selected.endsAt),
  };
}

function publicPeriod(window: PeriodWindow): LeaderboardPeriod {
  return {
    id: window.id,
    type: window.type,
    displayName: window.displayName,
    startsAt: window.startsAt.toISOString(),
    endsAt: window.endsAt?.toISOString() ?? null,
  };
}

export function mapPublicLeaderboardEntry(row: RankedRow): LeaderboardEntry {
  return {
    // Keep the legacy field name for released clients, but make its value the
    // already-public username rather than an authentication/database ID.
    userId: row.publicId,
    publicId: row.publicId,
    rank: Number(row.rank),
    points: Number(row.points),
    username: row.username,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    supportedTeam: row.supportedTeam,
    isYouTubeMember: row.isYouTubeMember,
  };
}

export function assembleRankedLeaderboardRows(
  rows: RankedRow[],
  limit: number,
): {
  entries: LeaderboardEntry[];
  currentUser: LeaderboardEntry | null;
  totalPlayers: number;
} {
  const mapped = rows.map(row => ({
    row,
    entry: mapPublicLeaderboardEntry(row),
  }));
  return {
    entries: mapped
      .filter(item => Number(item.row.rank) <= limit)
      .map(item => item.entry),
    currentUser:
      mapped.find(item => item.row.isCurrentUser)?.entry ?? null,
    totalPlayers: rows.length === 0 ? 0 : Number(rows[0].totalPlayers),
  };
}

async function rankedRows(
  window: PeriodWindow,
  limit: number,
  databaseUserId?: string,
): Promise<{
  entries: LeaderboardEntry[];
  currentUser: LeaderboardEntry | null;
  totalPlayers: number;
}> {
  const safeLimit = Math.min(100, Math.max(1, Math.trunc(limit)));
  const result = await query<RankedRow>(
    `WITH scored AS (
       SELECT u.id::text AS database_user_id,
              u.username,
              u.display_name,
              u.avatar_url,
              u.supported_team,
              COALESCE(
                yl.is_member = TRUE
                AND yl.verification_source = 'admin_snapshot'
                AND yl.snapshot_import_id = snapshot_state.active_import_id
                AND snapshot_import.id IS NOT NULL
                AND approved_claim.id IS NOT NULL,
                FALSE
              ) AS is_youtube_member,
              u.created_at AS account_created_at,
              SUM(pt.final_points)::bigint AS points
       FROM point_transactions pt
       JOIN users u ON u.id = pt.user_id
       LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
       LEFT JOIN youtube_membership_snapshot_state snapshot_state
         ON snapshot_state.singleton = TRUE
       LEFT JOIN youtube_membership_snapshot_imports snapshot_import
         ON snapshot_import.id = snapshot_state.active_import_id
        AND snapshot_import.expires_at > CURRENT_TIMESTAMP
       LEFT JOIN youtube_channel_claims approved_claim
         ON approved_claim.user_id = u.id
        AND approved_claim.youtube_channel_id = yl.youtube_channel_id
        AND approved_claim.status = 'approved'
       WHERE u.account_status = 'active'
         AND pt.source_type IN (${eligibleSourceSql})
         AND pt.created_at >= $1
         AND ($2::timestamptz IS NULL OR pt.created_at < $2)
       GROUP BY u.id, yl.user_id, snapshot_state.active_import_id,
                snapshot_import.id, approved_claim.id
       HAVING SUM(pt.final_points) > 0
     ), ranked AS (
       SELECT database_user_id,
              username AS "publicId",
              username,
              display_name AS "displayName",
              avatar_url AS "avatarUrl",
              supported_team AS "supportedTeam",
              is_youtube_member AS "isYouTubeMember",
              points,
              ROW_NUMBER() OVER (
                ORDER BY points DESC, account_created_at ASC, database_user_id ASC
              ) AS rank,
              COUNT(*) OVER () AS "totalPlayers"
       FROM scored
     )
     SELECT "publicId",
            username,
            "displayName",
            "avatarUrl",
            "supportedTeam",
            "isYouTubeMember",
            points,
            rank,
            "totalPlayers",
            ($4::text IS NOT NULL AND database_user_id = $4::text) AS "isCurrentUser"
     FROM ranked
     WHERE rank <= $3
        OR ($4::text IS NOT NULL AND database_user_id = $4::text)
     ORDER BY rank
    `,
    [
      window.startsAt,
      window.endsAt,
      safeLimit,
      databaseUserId ?? null,
    ],
  );
  return assembleRankedLeaderboardRows(result.rows, safeLimit);
}

async function rankForUser(
  databaseUserId: string,
  window: PeriodWindow,
): Promise<UserPeriodRank> {
  const result = await query<{ rank: string | number; points: string | number }>(
    `WITH scored AS (
       SELECT u.id::text AS database_user_id,
              u.created_at AS account_created_at,
              SUM(pt.final_points)::bigint AS points
       FROM point_transactions pt
       JOIN users u ON u.id = pt.user_id
       WHERE u.account_status = 'active'
         AND pt.source_type IN (${eligibleSourceSql})
         AND pt.created_at >= $1
         AND ($2::timestamptz IS NULL OR pt.created_at < $2)
       GROUP BY u.id
       HAVING SUM(pt.final_points) > 0
     ), ranked AS (
       SELECT database_user_id,
              points,
              ROW_NUMBER() OVER (
                ORDER BY points DESC, account_created_at ASC, database_user_id ASC
              ) AS rank
       FROM scored
     )
     SELECT rank, points
     FROM ranked
     WHERE database_user_id = $3`,
    [window.startsAt, window.endsAt, databaseUserId],
  );
  if (result.rows.length === 0) return { rank: 0, points: 0 };
  return {
    rank: Number(result.rows[0].rank),
    points: Number(result.rows[0].points),
  };
}

export async function getLeaderboardSnapshot(
  scope: LeaderboardScope,
  options: {
    seasonId?: string;
    limit?: number;
    now?: Date;
    databaseUserId?: string;
  } = {},
): Promise<LeaderboardSnapshot> {
  const seasons = await listLeaderboardSeasons();
  const window = scope === 'season'
    ? resolveSeasonWindow(seasons, options.seasonId)
    : utcMonthWindow(scope, options.now);
  const ranked = await rankedRows(
    window,
    options.limit ?? 100,
    options.databaseUserId,
  );
  return {
    leaderboard: ranked.entries,
    currentUser: ranked.currentUser,
    totalPlayers: ranked.totalPlayers,
    seasons,
    activeSeasonId: seasons.find(season => season.active)?.id ?? null,
    period: publicPeriod(window),
  };
}

export async function getUserRankForScope(
  databaseUserId: string,
  scope: LeaderboardScope,
  options: { seasonId?: string; now?: Date } = {},
): Promise<UserPeriodRank> {
  const window = scope === 'season'
    ? resolveSeasonWindow(await listLeaderboardSeasons(), options.seasonId)
    : utcMonthWindow(scope, options.now);
  return rankForUser(databaseUserId, window);
}
