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
  };
}

function normalizeTeam(value: unknown): string {
  return value == null ? '' : String(value).trim().toLowerCase();
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
    // v2 drops pre-fix detail snapshots that could contain a long-cached empty
    // lineup/table after the provider had already published those sections.
    const cacheKey = `cache:matches:v2:${id}:details`;
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

    const external = id.startsWith('external_')
      ? await fetchExternalMatchDetails(id)
      : emptyDetails();
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

    const result: ExternalMatchDetails = {
      ...external,
      timeline,
      venue: String(match?.venue ?? external.venue ?? ''),
      season: String(match?.season_id ?? external.season ?? ''),
      provider: external.provider || 'Abu 3meer',
    };
    await setCachedJson(cacheKey, result, match?.status === 'live' ? 20 : 120);
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
