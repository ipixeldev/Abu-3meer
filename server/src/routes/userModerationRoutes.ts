import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  blockUser,
  isSelfModerationTarget,
  listBlockedUsers,
  reportUser,
  unblockUser,
  UserModerationError,
} from '../services/userModerationService.js';

export const moderationUserIdSchema = z.string().trim().min(1).max(128);

export const userReportReasons = [
  'inappropriate_content',
  'harassment',
  'hate_speech',
  'impersonation',
  'spam',
  'other',
] as const;

export const userReportBodySchema = z.object({
  reason: z.preprocess(
    value => typeof value === 'string' ? value.trim().toLowerCase() : value,
    z.enum(userReportReasons),
  ),
  details: z.string().trim().max(1000).optional(),
}).strict();

function moderationError(reply: FastifyReply, error: unknown) {
  if (error instanceof UserModerationError) {
    return reply.status(error.statusCode).send({
      error: error.code,
      message: error.message,
    });
  }
  throw error;
}

function parsedTarget(request: { params: unknown }, reply: FastifyReply) {
  const parsed = z.object({ userId: moderationUserIdSchema }).safeParse(
    request.params,
  );
  if (!parsed.success) {
    reply.status(400).send({
      error: 'ValidationError',
      message: 'The user identifier is invalid.',
      issues: parsed.error.issues,
    });
    return null;
  }
  return parsed.data.userId;
}

function rejectSelfTarget(
  request: { user: NonNullable<import('fastify').FastifyRequest['user']> },
  reply: FastifyReply,
  target: string,
): boolean {
  if (!isSelfModerationTarget(target, request.user)) return false;
  reply.status(400).send({
    error: 'SelfModerationNotAllowed',
    message: 'You cannot report, block, or unblock your own account.',
  });
  return true;
}

export async function userModerationRoutes(fastify: FastifyInstance) {
  fastify.post('/users/:userId/report', {
    preHandler: [authenticateUser],
    config: {
      rateLimit: {
        max: 10,
        timeWindow: '1 hour',
        hook: 'preHandler',
        keyGenerator: request =>
          `user-report:user:${request.user?.id ?? request.ip}`,
      },
    },
  }, async (request, reply) => {
    const target = parsedTarget(request, reply);
    if (!target || rejectSelfTarget({ user: request.user! }, reply, target)) {
      return;
    }
    const parsed = userReportBodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'The report reason or details are invalid.',
        issues: parsed.error.issues,
      });
    }
    try {
      const report = await reportUser(request.user!.id, target, parsed.data);
      return reply.status(201).send({ data: report });
    } catch (error) {
      return moderationError(reply, error);
    }
  });

  fastify.post('/users/:userId/block', {
    preHandler: [authenticateUser],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const target = parsedTarget(request, reply);
    if (!target || rejectSelfTarget({ user: request.user! }, reply, target)) {
      return;
    }
    try {
      return { data: {
        blocked: true,
        user: await blockUser(request.user!.id, target),
      } };
    } catch (error) {
      return moderationError(reply, error);
    }
  });

  fastify.delete('/users/:userId/block', {
    preHandler: [authenticateUser],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const target = parsedTarget(request, reply);
    if (!target || rejectSelfTarget({ user: request.user! }, reply, target)) {
      return;
    }
    try {
      const result = await unblockUser(request.user!.id, target);
      return { data: {
        blocked: false,
        removed: result.removed,
        user: result.user,
      } };
    } catch (error) {
      return moderationError(reply, error);
    }
  });

  fastify.get('/users/blocked', {
    preHandler: [authenticateUser],
    config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    reply.header('Cache-Control', 'private, no-store');
    return { data: await listBlockedUsers(request.user!.id) };
  });
}
