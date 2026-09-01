import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import {
  authenticateUser,
  requirePermission,
} from '../middleware/auth.js';
import {
  getCreatorYouTubeConnectionStatus,
  getYouTubeOAuthFlowStatus,
  handleYouTubeOAuthCallback,
  refreshLinkedYouTubeMembership,
  startYouTubeOAuthFlow,
} from '../services/youtubeMembershipService.js';
import { YouTubeIntegrationError } from '../services/youtubeOAuthService.js';

const flowIdSchema = z.string().uuid();
const callbackSchema = z.object({
  state: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/),
  code: z.string().min(1).max(4096).optional(),
  error: z.string().regex(/^[A-Za-z0-9_.-]{1,80}$/).optional(),
}).refine((value) => Boolean(value.code || value.error), {
  message: 'The OAuth callback is incomplete.',
});

function sendYouTubeError(reply: FastifyReply, error: unknown) {
  if (error instanceof YouTubeIntegrationError) {
    return reply.status(error.httpStatus).send({
      error: error.code,
      message: error.message,
    });
  }
  throw error;
}

function callbackPage(success: boolean): string {
  const title = success ? 'YouTube connected' : 'YouTube connection failed';
  const message = success
    ? 'Return to ABU 3MEER. The app will finish verification automatically.'
    : 'Return to ABU 3MEER and try the connection again.';
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title>
</head>
<body>
  <main>
    <h1>${title}</h1>
    <p>${message}</p>
    <p>You can close this page.</p>
  </main>
</body>
</html>`;
}

export async function youtubeMembershipRoutes(fastify: FastifyInstance) {
  fastify.post(
    '/profile/youtube/connect/start',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      try {
        return await startYouTubeOAuthFlow({
          requestedByUserId: request.user!.id,
          purpose: 'member_link',
          expectedGoogleSubject: request.user!.googleProviderUid,
        });
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  fastify.get(
    '/profile/youtube/connect/:flowId/status',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = flowIdSchema.safeParse(
        (request.params as { flowId?: string }).flowId,
      );
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'InvalidFlowId',
          message: 'The YouTube connection identifier is invalid.',
        });
      }
      try {
        return await getYouTubeOAuthFlowStatus({
          flowId: parsed.data,
          requestedByUserId: request.user!.id,
          purpose: 'member_link',
        });
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  // Compatibility endpoint for already-linked releases. It can only refresh
  // the server-owned channel link; no client-supplied channel or member flag
  // is accepted.
  fastify.post(
    '/profile/verify-yt-member',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 4, timeWindow: '15 minutes' } },
    },
    async (request, reply) => {
      try {
        return await refreshLinkedYouTubeMembership(request.user!.id);
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  fastify.get(
    '/admin/youtube/creator/status',
    { preHandler: [requirePermission('settings.manage')] },
    async (_request, reply) => {
      try {
        return await getCreatorYouTubeConnectionStatus();
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  fastify.post(
    '/admin/youtube/creator/connect/start',
    {
      preHandler: [requirePermission('settings.manage')],
      config: { rateLimit: { max: 3, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      try {
        return await startYouTubeOAuthFlow({
          requestedByUserId: request.user!.id,
          purpose: 'creator_connect',
        });
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  fastify.get(
    '/admin/youtube/creator/connect/:flowId/status',
    {
      preHandler: [requirePermission('settings.manage')],
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = flowIdSchema.safeParse(
        (request.params as { flowId?: string }).flowId,
      );
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'InvalidFlowId',
          message: 'The YouTube connection identifier is invalid.',
        });
      }
      try {
        return await getYouTubeOAuthFlowStatus({
          flowId: parsed.data,
          requestedByUserId: request.user!.id,
          purpose: 'creator_connect',
        });
      } catch (error) {
        return sendYouTubeError(reply, error);
      }
    },
  );

  // Google redirects here in the system browser. The app polls its opaque
  // flowId, so this public callback never needs a Firebase token or deep link.
  fastify.get(
    '/youtube/oauth/callback',
    { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } },
    async (request, reply) => {
      reply.header('Cache-Control', 'no-store');
      reply.header('Pragma', 'no-cache');
      const parsed = callbackSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply
          .status(400)
          .type('text/html; charset=utf-8')
          .send(callbackPage(false));
      }
      try {
        const result = await handleYouTubeOAuthCallback(parsed.data);
        return reply
          .status(result.status === 'error' ? 400 : 200)
          .type('text/html; charset=utf-8')
          .send(callbackPage(result.status !== 'error'));
      } catch (error) {
        if (error instanceof YouTubeIntegrationError) {
          return reply
            .status(error.httpStatus)
            .type('text/html; charset=utf-8')
            .send(callbackPage(false));
        }
        throw error;
      }
    },
  );
}
