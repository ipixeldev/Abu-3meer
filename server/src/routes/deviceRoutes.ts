import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  getNotificationPreferences,
  registerDeviceToken,
  revokeDeviceInstallation,
  unregisterDeviceToken,
  updateNotificationPreferences,
} from '../services/notificationService.js';

const registerDeviceSchema = z.object({
  fcmToken: z.string().trim().min(10).max(500),
  installationId: z.string().trim().min(16).max(128)
    .regex(/^[A-Za-z0-9_-]+$/).optional(),
  platform: z.enum(['ios', 'android', 'web']),
  appVersion: z.string().trim().max(30).optional(),
  deviceModel: z.string().trim().max(100).optional(),
  osVersion: z.string().trim().max(50).optional(),
  locale: z.string().trim().min(2).max(20).optional(),
});

const notificationPreferencesSchema = z.object({
  enabled: z.boolean(),
  matchEnabled: z.boolean(),
  challengeEnabled: z.boolean(),
  rewardEnabled: z.boolean(),
  newsEnabled: z.boolean(),
});

const revokeDeviceSchema = z.object({
  fcmToken: z.string().trim().min(10).max(500),
  installationId: z.string().trim().min(16).max(128)
    .regex(/^[A-Za-z0-9_-]+$/),
});

export async function deviceRoutes(fastify: FastifyInstance) {
  // A logout can outlive its Firebase session. Requiring both opaque device
  // secrets permits only revocation and avoids leaving the old account's
  // token active when connectivity returns after sign-out.
  fastify.post('/devices/revoke', async (request, reply) => {
    const parsed = revokeDeviceSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }
    await revokeDeviceInstallation(
      parsed.data.fcmToken,
      parsed.data.installationId,
    );
    return { success: true };
  });

  fastify.post('/devices/register', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const parsed = registerDeviceSchema.safeParse(request.body);

    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const res = await registerDeviceToken(user.id, parsed.data);
    return { success: true, deviceId: res.id };
  });

  fastify.post('/devices/unregister', { preHandler: [authenticateUser] }, async (request, reply) => {
    const schema = z.object({ fcmToken: z.string().trim().min(10).max(500) });
    const parsed = schema.safeParse(request.body);

    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    await unregisterDeviceToken(request.user!.id, parsed.data.fcmToken);
    return { success: true };
  });

  fastify.get('/notifications/preferences', { preHandler: [authenticateUser] }, async (request) => {
    return await getNotificationPreferences(request.user!.id);
  });

  fastify.put('/notifications/preferences', { preHandler: [authenticateUser] }, async (request, reply) => {
    const parsed = notificationPreferencesSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }
    return await updateNotificationPreferences(request.user!.id, parsed.data);
  });
}
