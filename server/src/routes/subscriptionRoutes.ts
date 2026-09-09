import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  isValidRevenueCatWebhookAuthorization,
  processRevenueCatWebhook,
  readSubscriptionStatus,
  SubscriptionError,
  syncSubscriptionStatus,
} from '../services/subscriptionService.js';

const emptyBody = z.object({}).strict();
const webhookSchema = z.object({
  event: z.object({
    id: z.string().min(1).max(255),
    type: z.string().min(1).max(100),
  }).passthrough(),
}).passthrough();

export async function subscriptionRoutes(
  fastify: FastifyInstance,
  dependencies: {
    authenticate?: typeof authenticateUser;
    sync?: typeof syncSubscriptionStatus;
    read?: typeof readSubscriptionStatus;
    authorizeWebhook?: typeof isValidRevenueCatWebhookAuthorization;
    processWebhook?: typeof processRevenueCatWebhook;
  } = {},
) {
  const authenticate = dependencies.authenticate ?? authenticateUser;
  const sync = dependencies.sync ?? syncSubscriptionStatus;
  const read = dependencies.read ?? readSubscriptionStatus;
  fastify.get('/subscriptions/status', { preHandler: [authenticate] }, async (request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    try {
      return { data: await read(request.user!.id) };
    } catch (error) {
      request.log.error({ err: error }, 'Subscription status lookup failed');
      return reply.status(503).send({
        error: 'SubscriptionUnavailable', code: 'subscription_verification_unavailable',
        message: 'Subscription verification is temporarily unavailable.',
      });
    }
  });
  fastify.post('/subscriptions/sync', {
    preHandler: [authenticate],
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    if (!emptyBody.safeParse(request.body ?? {}).success) {
      return reply.status(400).send({ error: 'ValidationError', message: 'This endpoint accepts no customer or entitlement fields.' });
    }
    try {
      return { data: await sync(request.user!.id) };
    } catch (error) {
      if (error instanceof SubscriptionError) {
        // A store outage must not hide any independently/currently valid
        // member access. The read path revalidates YouTube snapshots, admin
        // overrides and cached store expiry.
        // Keep this fallback out of webhook sync: failed verification there
        // must remain retryable and must not record a processed receipt.
        try {
          const effective = await read(request.user!.id);
          if (effective.hasMemberAccess) return { data: effective };
        } catch { /* Preserve the original safe verification error. */ }
        return reply.status(error.statusCode).send({ error: 'SubscriptionUnavailable', code: error.code, message: error.message });
      }
      request.log.error({ err: error }, 'Subscription synchronization failed');
      return reply.status(503).send({ error: 'SubscriptionUnavailable', message: 'Subscription verification is temporarily unavailable.' });
    }
  });
  fastify.post('/subscriptions/webhook', {
    bodyLimit: 128 * 1024,
    config: { rateLimit: { max: 120, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const authorize = dependencies.authorizeWebhook ?? isValidRevenueCatWebhookAuthorization;
    if (!authorize(request.headers.authorization)) return reply.status(401).send({ error: 'Unauthorized' });
    const parsed = webhookSchema.safeParse(request.body);
    if (!parsed.success) return reply.status(400).send({ error: 'ValidationError' });
    try {
      await (dependencies.processWebhook ?? processRevenueCatWebhook)(parsed.data.event);
      return { success: true };
    } catch (error) {
      request.log.error({ err: error }, 'RevenueCat webhook synchronization failed');
      // A non-2xx response allows RevenueCat to retry. No receipt is recorded
      // until every affected account has successfully refreshed.
      return reply.status(503).send({ error: 'SubscriptionUnavailable' });
    }
  });
}
