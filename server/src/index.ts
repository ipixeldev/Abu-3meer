import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import crypto from 'crypto';
import fs from 'fs';
import { config } from './config.js';
import { runMigrations } from './db/migrate.js';
import { closeDatabasePools } from './db/pool.js';
import { startWorkers } from './queues/workers.js';
import { redis } from './redis/client.js';
import { authRoutes } from './routes/authRoutes.js';
import { profileRoutes } from './routes/profileRoutes.js';
import { matchRoutes } from './routes/matchRoutes.js';
import { footballRoutes } from './routes/footballRoutes.js';
import { predictionRoutes } from './routes/predictionRoutes.js';
import { challengeRoutes } from './routes/challengeRoutes.js';
import { leaderboardRoutes } from './routes/leaderboardRoutes.js';
import { streakRoutes } from './routes/streakRoutes.js';
import { deviceRoutes } from './routes/deviceRoutes.js';
import { adminRoutes } from './routes/adminRoutes.js';
import { adminContentRoutes } from './routes/adminContentRoutes.js';
import { healthRoutes } from './routes/healthRoutes.js';
import { videoRoutes } from './routes/videoRoutes.js';
import { publicMediaRoutes, uploadRoutes } from './routes/uploadRoutes.js';
import { rewardRoutes } from './routes/rewardRoutes.js';

const fastify = Fastify({
  genReqId: () => crypto.randomUUID(),
  logger: {
    level: config.env === 'production' ? 'info' : 'debug',
    serializers: {
      req(req) {
        return {
          id: req.id,
          method: req.method,
          url: req.url,
          ip: req.ip,
        };
      },
    },
  },
  trustProxy: true,
  bodyLimit: 1048576, // 1MB maximum payload
});

let stopWorkers: (() => Promise<void>) | null = null;
let shuttingDown = false;

async function main() {
  console.log('=== Starting Abu 3meer Production Backend (Hardened) ===');

  // Security Headers
  await fastify.register(helmet, {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'https:'],
      },
    },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true,
    },
    noSniff: true,
    frameguard: { action: 'deny' },
  });

  // CORS - Mobile clients use Authorization header; restrict browser methods
  await fastify.register(cors, {
    origin: config.env === 'production' ? config.corsOrigins : true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  // Rate Limiting (Redis-backed)
  await fastify.register(rateLimit, {
    // Several signed-in phones can legitimately share one home/work/public
    // IP. Key authenticated traffic by an irreversible token digest so one
    // busy device cannot exhaust the whole network's allowance. Public
    // traffic keeps an IP key and sensitive routes retain their lower,
    // route-specific limits.
    keyGenerator: (request) => {
      const authorization = request.headers.authorization?.trim();
      if (authorization?.startsWith('Bearer ')) {
        const digest = crypto
          .createHash('sha256')
          .update(authorization)
          .digest('hex');
        return `auth:${digest}`;
      }
      return `ip:${request.ip}`;
    },
    // Health probes are operational checks, not user traffic. Keeping them
    // outside the user buckets prevents Docker/uptime monitoring from
    // consuming capacity or making a healthy server report a false 429.
    allowList: (request) =>
      request.url === '/health' || request.url === '/ready',
    max: 1000,
    timeWindow: '1 minute',
    redis: redis,
    errorResponseBuilder: (req, context) => ({
      error: 'TooManyRequests',
      message: `Rate limit exceeded. Try again in ${context.after}`,
      statusCode: 429,
    }),
  });

  // User/admin media is stored on the self-hosted machine. The Docker volume
  // mounted at this path makes uploads survive image rebuilds and restarts.
  fs.mkdirSync(config.uploads.directory, { recursive: true });
  await fastify.register(multipart, {
    limits: {
      files: 1,
      fileSize: config.uploads.maxImageBytes,
      fields: 4,
      parts: 5,
    },
  });
  await fastify.register(publicMediaRoutes);

  // Global Error Handler - Never leak stack traces to untrusted clients
  fastify.setErrorHandler((error: any, request, reply) => {
    request.log.error({ err: error, reqId: request.id }, 'Unhandled request error');

    if (error?.statusCode) {
      return reply.status(error.statusCode).send({
        error: error.name || 'RequestError',
        message: error.message,
        statusCode: error.statusCode,
      });
    }

    return reply.status(500).send({
      error: 'InternalServerError',
      message: 'An unexpected internal server error occurred.',
      requestId: request.id,
    });
  });

  // Register all API routes under /api/v1
  await fastify.register(healthRoutes);
  await fastify.register(async (v1) => {
    await v1.register(authRoutes);
    await v1.register(profileRoutes);
    await v1.register(matchRoutes);
    await v1.register(footballRoutes);
    await v1.register(predictionRoutes);
    await v1.register(challengeRoutes);
    await v1.register(leaderboardRoutes);
    await v1.register(streakRoutes);
    await v1.register(deviceRoutes);
    await v1.register(adminRoutes);
    await v1.register(adminContentRoutes);
    await v1.register(videoRoutes);
    await v1.register(rewardRoutes);
    await v1.register(uploadRoutes);
  }, { prefix: '/api/v1' });

  // A server with a stale schema must never advertise itself as healthy. Let
  // startup fail so Docker restarts it and the operator sees the migration
  // error instead of silent profile/prediction write failures.
  await runMigrations();

  // Start BullMQ background workers
  stopWorkers = await startWorkers();

  // Listen
  try {
    await fastify.listen({ port: config.port, host: config.host });
    console.log(`[Fastify] Hardened Server listening on http://${config.host}:${config.port}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
}

// Graceful shutdown handling
const signals: NodeJS.Signals[] = ['SIGINT', 'SIGTERM'];
for (const signal of signals) {
  process.on(signal, async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    console.log(`[Process] Received ${signal}, shutting down gracefully...`);
    await fastify.close();
    await stopWorkers?.();
    await redis.quit();
    await closeDatabasePools();
    process.exit(0);
  });
}

main();
