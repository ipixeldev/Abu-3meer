import { FastifyInstance } from 'fastify';
import { query } from '../db/pool.js';
import { redis } from '../redis/client.js';
import { firebaseMessagingIsConfigured } from '../firebase/admin.js';

export async function healthRoutes(fastify: FastifyInstance) {
  fastify.get('/health', async (request, reply) => {
    return { status: 'alive', timestamp: new Date().toISOString() };
  });

  fastify.get('/ready', async (request, reply) => {
    try {
      await query('SELECT 1');
      const redisPing = await redis.ping();
      if (redisPing !== 'PONG') throw new Error('Redis not ready');
      return {
        status: 'ready',
        database: 'connected',
        redis: 'connected',
        pushNotifications: firebaseMessagingIsConfigured()
          ? 'configured'
          : 'credentials_required',
      };
    } catch (err: any) {
      return reply.status(503).send({ status: 'unhealthy', error: err.message });
    }
  });
}
