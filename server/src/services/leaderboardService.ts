import { getClient, query } from '../db/pool.js';

export const eligibleLeaderboardSourceTypes = [
  'prediction_exact',
  'prediction_scorer',
  'prediction_winner',
  'prediction_win',
  'video_phrase',
  'player_card',
] as const;

export type LeaderboardScope = 'current_month' | 'previous_month' | 'season';

export interface LeaderboardEntry {
  /** Firebase identity used by the Flutter client and public-profile route. */
  userId: string;
  firebaseUid: string;
  /** Internal PostgreSQL identity retained for diagnostics and migrations. */
  databaseUserId: string;
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

interface RankedRow {
  databaseUserId: string;
  firebaseUid: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  supportedTeam: string;
  isYouTubeMember: boolean;
  points: string | number;
  rank: string | number;
  totalPlayers: string | number;
}

interface SeasonRow {
  id: string;
  displayName: string;
  startsAt: Date | string;
  endsAt: Date | string | null;
  active: boolean;
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
      await client.query(
        `INSERT INTO leaderboard_periods
           (id, type, name, starts_at, ends_at, is_current)
         VALUES ($1, 'season', $2, $3, NULL, FALSE)
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
         AND starts_at >= $1
         AND is_current = TRUE`,
      [new Date(initialLeaderboardSeasonStart)],
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
       SET ends_at = ordered.next_start
       FROM ordered
       WHERE period.id = ordered.id
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
           AND starts_at >= $1
           AND starts_at <= CURRENT_TIMESTAMP
         ORDER BY starts_at DESC, id DESC
         LIMIT 1
       )`,
      [new Date(initialLeaderboardSeasonStart)],
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
            is_current AS active
     FROM leaderboard_periods
     WHERE type = 'season'
     ORDER BY starts_at DESC, id DESC`,
  );
  return result.rows.map(row => ({
    id: row.id,
    displayName: row.displayName,
    startsAt: iso(row.startsAt),
    endsAt: row.endsAt == null ? null : iso(row.endsAt),
    active: row.active,
  }));
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

function rankedEntry(row: RankedRow): LeaderboardEntry {
  return {
    // Existing app versions read `userId`; new versions can use the explicit
    // Firebase field. Both deliberately identify the same public account.
    userId: row.firebaseUid,
    firebaseUid: row.firebaseUid,
    databaseUserId: row.databaseUserId,
    rank: Number(row.rank),
    points: Number(row.points),
    username: row.username,
    displayName: row.displayName,
    avatarUrl: row.avatarUrl,
    supportedTeam: row.supportedTeam,
    isYouTubeMember: row.isYouTubeMember,
  };
}

async function rankedRows(
  window: PeriodWindow,
  limit: number,
): Promise<{ entries: LeaderboardEntry[]; totalPlayers: number }> {
  const safeLimit = Math.min(100, Math.max(1, Math.trunc(limit)));
  const result = await query<RankedRow>(
    `WITH scored AS (
       SELECT u.id::text AS database_user_id,
              u.firebase_uid,
              u.username,
              u.display_name,
              u.avatar_url,
              u.supported_team,
              u.is_youtube_member,
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
       SELECT database_user_id AS "databaseUserId",
              firebase_uid AS "firebaseUid",
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
     SELECT *
     FROM ranked
     ORDER BY rank
     LIMIT $3`,
    [window.startsAt, window.endsAt, safeLimit],
  );
  return {
    entries: result.rows.map(rankedEntry),
    totalPlayers: result.rows.length === 0 ? 0 : Number(result.rows[0].totalPlayers),
  };
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
  options: { seasonId?: string; limit?: number; now?: Date } = {},
): Promise<LeaderboardSnapshot> {
  const seasons = await listLeaderboardSeasons();
  const window = scope === 'season'
    ? resolveSeasonWindow(seasons, options.seasonId)
    : utcMonthWindow(scope, options.now);
  const ranked = await rankedRows(window, options.limit ?? 100);
  return {
    leaderboard: ranked.entries,
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
