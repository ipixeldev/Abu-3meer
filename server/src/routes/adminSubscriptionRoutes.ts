import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { getClient } from '../db/pool.js';
import { requirePermission } from '../middleware/auth.js';
import { readSubscriptionStatus, SubscriptionError } from '../services/subscriptionService.js';

export const subscriptionAccessBody = z.object({
  mode: z.enum(['active', 'inactive', 'store']),
  reason: z.string().trim().min(3).max(500).refine(value => !/\p{C}/u.test(value)),
  expiresAt: z.string().datetime({ offset: true }).optional().nullable(),
}).strict().superRefine((value, ctx) => {
  if (value.mode !== 'active' && value.expiresAt != null) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['expiresAt'], message: 'Only an active grant can have an expiry.' });
  }
});

type AccessChange = z.infer<typeof subscriptionAccessBody>;
type TransactionClient = {
  query: (sql: string, params?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;
  release: () => void;
};

/** A locked target row serializes even concurrent first-time overrides. */
export async function changeSubscriptionAccess(
  actorId: string,
  targetId: string,
  change: AccessChange,
  connect: () => Promise<TransactionClient> = getClient,
) {
  const client = await connect();
  try {
    await client.query('BEGIN');
    const target = await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [targetId]);
    if (!target.rows[0]) throw new SubscriptionError('user_not_found', 'User not found.', 404);
    if (change.expiresAt && Date.parse(change.expiresAt) <= Date.now()) {
      throw new SubscriptionError('invalid_access_expiry', 'Grant expiry must be in the future.', 400);
    }
    const previous = await client.query(
      'SELECT mode, expires_at, reason, updated_by, updated_at FROM user_subscription_access_overrides WHERE user_id = $1',
      [targetId],
    );
    const before = previous.rows[0] ?? { mode: 'store', expires_at: null };
    const expiresAt = change.mode === 'active' && change.expiresAt
      ? new Date(change.expiresAt).toISOString() : null;
    if (change.mode === 'store') {
      await client.query('DELETE FROM user_subscription_access_overrides WHERE user_id = $1', [targetId]);
    } else {
      await client.query(
        `INSERT INTO user_subscription_access_overrides (user_id, mode, expires_at, reason, updated_by)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (user_id) DO UPDATE SET mode = EXCLUDED.mode,
           expires_at = EXCLUDED.expires_at, reason = EXCLUDED.reason,
           updated_by = EXCLUDED.updated_by, updated_at = CURRENT_TIMESTAMP`,
        [targetId, change.mode, expiresAt, change.reason, actorId],
      );
    }
    await client.query(
      `INSERT INTO admin_audit_logs
       (admin_user_id, action, target_entity, target_id, before_state, after_state)
       VALUES ($1, 'subscription_access_changed', 'user_subscription_access', $2, $3::jsonb, $4::jsonb)`,
      [actorId, targetId, JSON.stringify(before), JSON.stringify({
        mode: change.mode, expires_at: expiresAt, reason: change.reason,
        billing_changed: false,
      })],
    );
    const status = await readSubscriptionStatus(targetId, (sql, params) => client.query(sql, params));
    await client.query('COMMIT');
    return status;
  } catch (error) {
    // Preserve the actionable failure even when a broken database connection
    // cannot acknowledge the cleanup command.
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function adminSubscriptionRoutes(
  fastify: FastifyInstance,
  dependencies: {
    authorize?: ReturnType<typeof requirePermission>;
    change?: typeof changeSubscriptionAccess;
  } = {},
) {
  fastify.put('/admin/users/:id/subscription-access', {
    preHandler: [dependencies.authorize ?? requirePermission('subscriptions.manage')],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
  }, async (request: FastifyRequest, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    // Defense in depth: accidentally granting a moderator the permission must
    // never turn this into a self-service or moderator entitlement endpoint.
    const actor = request.user;
    if (!actor || !(actor.isSuperAdmin || actor.isAdmin || actor.roles?.includes('admin'))) {
      return reply.status(actor ? 403 : 401).send({ error: actor ? 'Forbidden' : 'Unauthorized' });
    }
    const target = z.object({ id: z.string().uuid() }).safeParse(request.params);
    const body = subscriptionAccessBody.safeParse(request.body);
    if (!target.success || !body.success) {
      return reply.status(400).send({ error: 'ValidationError', message: 'Supply a user ID, access mode, reason and optional future grant expiry.' });
    }
    try {
      return { data: await (dependencies.change ?? changeSubscriptionAccess)(actor.id, target.data.id, body.data) };
    } catch (error) {
      if (error instanceof SubscriptionError) {
        return reply.status(error.statusCode).send({ error: 'SubscriptionAccessError', code: error.code, message: error.message });
      }
      request.log.error({ err: error }, 'Admin subscription access change failed');
      return reply.status(503).send({ error: 'SubscriptionAccessUnavailable', message: 'Access was not changed. Please try again.' });
    }
  });
}
