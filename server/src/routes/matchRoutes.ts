import { FastifyInstance } from 'fastify';
import { query } from '../db/pool.js';
import { getCachedJson, setCachedJson } from '../redis/client.js';
import {
  ExternalMatchDetails,
  fetchExternalMatchDetails,
} from '../services/footballDetailsService.js';

function emptyDetails(): ExternalMatchDetails {
  return {
    timeline: [],
    lineup: [],
    statistics: [],
    standings: [],
    venue: '',
    season: '',
    provider: 'Abu 3meer',
    isProviderLimited: false,
    status: '',
    homeScore: null,
    awayScore: null,
  };
}

const publishedDetailsTtlSeconds = 7 * 24 * 60 * 60;

function identityText(value: unknown): string {
  return String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function mergeDetailRecord<T extends object>(previous: T, incoming: T): T {
  const result = { ...previous } as Record<string, unknown>;
  for (const [key, value] of Object.entries(incoming)) {
    if (
      (value === null || value === undefined ||
        (typeof value === 'string' && value.trim().length === 0)) &&
      result[key] !== null && result[key] !== undefined &&
      !(typeof result[key] === 'string' && String(result[key]).trim().length === 0)
    ) {
      continue;
    }
    result[key] = value;
  }
  return result as T;
}

/**
 * Provider replicas can return a shorter but non-empty snapshot after a more
 * complete one. Merge by a stable domain identity so published collections
 * only grow, while still accepting richer fields for an existing item.
 */
function stableUnion<T extends object>(
  previous: T[],
  incoming: T[],
  identity: (item: T) => string,
): T[] {
  const previousByIdentity = new Map<string, T>();
  for (const item of previous) previousByIdentity.set(identity(item), item);

  const seen = new Set<string>();
  const result: T[] = [];
  for (const item of incoming) {
    const key = identity(item);
    if (seen.has(key)) continue;
    const prior = previousByIdentity.get(key);
    result.push(prior ? mergeDetailRecord(prior, item) : item);
    seen.add(key);
  }
  for (const item of previous) {
    const key = identity(item);
    if (seen.has(key)) continue;
    result.push(item);
    seen.add(key);
  }
  return result;
}

function timelineMinute(value: string): number {
  const [minute, extra] = value.split('+').map(part => Number.parseInt(part, 10));
  return (Number.isFinite(minute) ? minute : Number.MAX_SAFE_INTEGER) * 1000 +
    (Number.isFinite(extra) ? extra : 0);
}

function retainedStatus(
  incoming: ExternalMatchDetails['status'],
  previous: ExternalMatchDetails['status'],
): ExternalMatchDetails['status'] {
  // Completed is terminal; a delayed provider replica must not turn a final
  // result back into an upcoming/live fixture.
  if (previous === 'completed' && incoming !== 'cancelled') return previous;
  return incoming || previous;
}

/** Delayed provider refreshes must not retract already-published official data. */
export function retainPublishedMatchDetails(
  previous: ExternalMatchDetails | null,
  incoming: ExternalMatchDetails,
): ExternalMatchDetails {
  if (!previous) return incoming;
  return {
    ...incoming,
    timeline: stableUnion(
      previous.timeline,
      incoming.timeline,
      item => [
        identityText(item.minute),
        identityText(item.type),
        identityText(item.team),
        identityText(item.player),
        item.isHome ? 'home' : 'away',
      ].join('|'),
    ).sort((left, right) => timelineMinute(left.minute) - timelineMinute(right.minute)),
    lineup: stableUnion(
      previous.lineup,
      incoming.lineup,
      item => [
        identityText(item.team),
        identityText(item.player),
        item.isHome ? 'home' : 'away',
        item.isSubstitute ? 'substitute' : 'starter',
      ].join('|'),
    ),
    statistics: stableUnion(
      previous.statistics,
      incoming.statistics,
      item => identityText(item.label),
    ),
    standings: stableUnion(
      previous.standings,
      incoming.standings,
      item => identityText(item.teamId) || identityText(item.team),
    ).sort((left, right) => left.rank - right.rank),
    venue: incoming.venue || previous.venue,
    season: incoming.season || previous.season,
    provider: incoming.provider || previous.provider,
    status: retainedStatus(incoming.status, previous.status),
    homeScore: incoming.homeScore ?? previous.homeScore,
    awayScore: incoming.awayScore ?? previous.awayScore,
  };
}

const matchDetailPublicationChains = new Map<string, Promise<unknown>>();

/** Serialize read/merge/write for one match inside this API process. */
export async function serializeMatchDetailPublication<T>(
  matchId: string,
  publish: () => Promise<T>,
): Promise<T> {
  const previous = matchDetailPublicationChains.get(matchId) ?? Promise.resolve();
  const current = previous.catch(() => undefined).then(publish);
  matchDetailPublicationChains.set(matchId, current);
  try {
    return await current;
  } finally {
    if (matchDetailPublicationChains.get(matchId) === current) {
      matchDetailPublicationChains.delete(matchId);
    }
  }
}

function normalizeTeam(value: unknown): string {
  return value == null ? '' : String(value).trim().toLowerCase();
}

function normalizeStatus(value: unknown): ExternalMatchDetails['status'] {
  const status = String(value ?? '').trim().toLowerCase();
  if (status === 'finished') return 'completed';
  if (status === 'scheduled' || status === 'open') return 'upcoming';
  if (['upcoming', 'live', 'completed', 'postponed', 'cancelled'].includes(status)) {
    return status as ExternalMatchDetails['status'];
  }
  return '';
}

export function matchDetailsCacheTtlSeconds(
  matchId: string,
  status: string = '',
): number {
  // External detail sections already have provider-specific shared caches.
  // Keeping a second long-lived envelope here made an empty pre-match lineup
  // or timeline remain visible after API-Football had published the data.
  return matchId.startsWith('external_') || status.toLowerCase() === 'live'
    ? 20
    : 120;
}

export async function matchRoutes(fastify: FastifyInstance) {
  fastify.get('/matches/upcoming', async (request, reply) => {
    reply.header(
      'Cache-Control',
      'public, max-age=15, s-maxage=30, stale-while-revalidate=120',
    );
    const cacheKey = 'cache:matches:upcoming';
    const cached = await getCachedJson(cacheKey);
    if (cached) return cached;

    const res = await query(
      `SELECT * FROM matches
       WHERE status IN ('scheduled', 'open', 'live')
       ORDER BY kickoff_at ASC
       LIMIT 20`
    );

    await setCachedJson(cacheKey, res.rows, 30);
    return res.rows;
  });

  fastify.get('/matches/recent', async (request, reply) => {
    reply.header(
      'Cache-Control',
      'public, max-age=30, s-maxage=60, stale-while-revalidate=300',
    );
    const res = await query(
      `SELECT * FROM matches
       WHERE status = 'finished'
       ORDER BY kickoff_at DESC
       LIMIT 20`
    );
    return res.rows;
  });

  fastify.get('/matches/:id/details', async (request, reply) => {
    const { id } = request.params as { id: string };
    const cacheKey = `cache:matches:v3:${id}:details`;
    const publishedCacheKey = `cache:matches:v3:${id}:details:published`;
    const cached = await getCachedJson(cacheKey);
    if (cached) return cached;

    let match: Record<string, unknown> | undefined;
    let databaseTimeline: Record<string, unknown>[] = [];
    try {
      const matchRes = await query('SELECT * FROM matches WHERE id = $1', [id]);
      match = matchRes.rows[0] as Record<string, unknown> | undefined;
      if (match) {
        const timelineRes = await query(
          'SELECT * FROM match_timeline_events WHERE match_id = $1 ORDER BY minute ASC, extra_minute ASC',
          [id],
        );
        databaseTimeline = timelineRes.rows as Record<string, unknown>[];
      }
    } catch (error) {
      // External events can still be served while PostgreSQL is restarting.
      if (!id.startsWith('external_')) throw error;
    }

    if (!match && !id.startsWith('external_')) {
      return reply.status(404).send({ error: 'Match not found' });
    }

    const published = await getCachedJson<ExternalMatchDetails>(publishedCacheKey);
    let external: ExternalMatchDetails;
    try {
      external = id.startsWith('external_')
        ? await fetchExternalMatchDetails(id)
        : emptyDetails();
    } catch (error) {
      // A provider outage must not blank a match that was already published.
      if (!published) throw error;
      return await serializeMatchDetailPublication(id, async () => {
        const latestPublished =
          await getCachedJson<ExternalMatchDetails>(publishedCacheKey) ?? published;
        await setCachedJson(
          cacheKey,
          latestPublished,
          matchDetailsCacheTtlSeconds(id),
        );
        return latestPublished;
      });
    }
    const homeTeam = normalizeTeam(match?.home_team);
    const timeline = databaseTimeline.length > 0
      ? databaseTimeline.map((item) => {
          const minute = Number(item.minute ?? 0);
          const extraMinute = Number(item.extra_minute ?? 0);
          return {
            minute: extraMinute > 0 ? `${minute}+${extraMinute}` : String(minute),
            type: String(item.type ?? 'event'),
            player: String(item.player ?? ''),
            assist: '',
            detail: String(item.detail ?? ''),
            team: String(item.team ?? ''),
            isHome: normalizeTeam(item.team) === homeTeam,
          };
        })
      : external.timeline;

    const incoming: ExternalMatchDetails = {
      ...external,
      timeline,
      venue: String(match?.venue ?? external.venue ?? ''),
      season: String(match?.season_id ?? external.season ?? ''),
      provider: external.provider || 'Abu 3meer',
      status: external.status || normalizeStatus(match?.status),
      homeScore: external.homeScore ?? (match?.home_score == null ? null : Number(match.home_score)),
      awayScore: external.awayScore ?? (match?.away_score == null ? null : Number(match.away_score)),
    };
    const result = await serializeMatchDetailPublication(id, async () => {
      // Re-read after acquiring the per-match publication turn. Concurrent
      // requests may both have missed the short cache and fetched different
      // provider replicas; merging against the latest published value avoids
      // the slower, shorter response winning the race.
      const latestPublished = await getCachedJson<ExternalMatchDetails>(
        publishedCacheKey,
      );
      const retained = retainPublishedMatchDetails(latestPublished, incoming);
      await setCachedJson(
        publishedCacheKey,
        retained,
        publishedDetailsTtlSeconds,
      );
      await setCachedJson(
        cacheKey,
        retained,
        matchDetailsCacheTtlSeconds(id, String(match?.status ?? '')),
      );
      return retained;
    });
    return result;
  });

  fastify.get('/matches/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const matchRes = await query('SELECT * FROM matches WHERE id = $1', [id]);
    if (matchRes.rows.length === 0) return reply.status(404).send({ error: 'Match not found' });

    const timelineRes = await query(
      'SELECT * FROM match_timeline_events WHERE match_id = $1 ORDER BY minute ASC, extra_minute ASC',
      [id]
    );

    return {
      match: matchRes.rows[0],
      timeline: timelineRes.rows,
    };
  });
}
