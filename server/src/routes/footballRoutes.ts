import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  fetchExternalRecentMatches,
  fetchExternalWeekMatches,
  fetchFootballTeamPlayers,
  searchFootballPlayers,
  searchFootballTeams,
} from '../services/footballDetailsService.js';

const weekQuerySchema = z.object({
  days: z.coerce.number().int().min(1).max(14).default(7),
});

const teamSearchSchema = z.object({
  q: z.string().trim().min(2).max(80),
});

const playerSearchSchema = z.object({
  q: z.string().trim().min(3).max(100),
});

const teamParamsSchema = z.object({
  teamId: z.string().regex(/^\d{3,20}$/),
});

export async function footballRoutes(fastify: FastifyInstance) {
  // Public match cards are assembled once on the server from the configured
  // featured teams. Every device receives the normalized shared result while
  // the provider calls themselves remain Redis cached and coalesced.
  fastify.get(
    '/football/matches/week',
    { config: { rateLimit: { max: 10000, timeWindow: '1 minute' } } },
    async (request, reply) => {
      const parsed = weekQuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          issues: parsed.error.issues,
        });
      }
      // This response is identical for every user. The short browser TTL
      // avoids stale screens while the shared/edge TTL collapses a large
      // audience into one server request per minute.
      reply.header(
        'Cache-Control',
        'public, max-age=30, s-maxage=60, stale-while-revalidate=300',
      );
      return fetchExternalWeekMatches(parsed.data.days);
    },
  );

  fastify.get(
    '/football/matches/recent',
    { config: { rateLimit: { max: 10000, timeWindow: '1 minute' } } },
    async (_request, reply) => {
      reply.header(
        'Cache-Control',
        'public, max-age=60, s-maxage=300, stale-while-revalidate=600',
      );
      return fetchExternalRecentMatches();
    },
  );

  // Catalog searches consume the paid provider allowance, so require a real
  // app session in addition to the global and per-route rate limits.
  fastify.get(
    '/football/teams/search',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = teamSearchSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          issues: parsed.error.issues,
        });
      }
      return searchFootballTeams(parsed.data.q);
    },
  );

  fastify.get(
    '/football/teams/:teamId/players',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = teamParamsSchema.safeParse(request.params);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          issues: parsed.error.issues,
        });
      }
      return fetchFootballTeamPlayers(parsed.data.teamId);
    },
  );

  fastify.get(
    '/football/players/search',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = playerSearchSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          issues: parsed.error.issues,
        });
      }
      return searchFootballPlayers(parsed.data.q);
    },
  );
}
