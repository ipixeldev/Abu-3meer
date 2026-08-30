import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser } from '../middleware/auth.js';
import {
  LoyaltyRedemptionError,
  redeemLoyaltyReward,
} from '../services/rewardRedemptionService.js';

const rewardIdSchema = z
  .string()
  .trim()
  .min(1)
  .max(128)
  .regex(/^[A-Za-z0-9_-]+$/);

const redeemSchema = z.object({
  idempotencyKey: z
    .string()
    .trim()
    .min(1)
    .max(128)
    .regex(/^[A-Za-z0-9_-]+$/),
});

function redemptionStatus(reason: LoyaltyRedemptionError['reason']): number {
  switch (reason) {
    case 'reward-not-found':
      return 404;
    case 'account-suspended':
    case 'members-only':
      return 403;
    case 'invalid-configuration':
      return 422;
    default:
      return 409;
  }
}

export async function rewardRoutes(fastify: FastifyInstance) {
  fastify.post(
    '/rewards/:id/redeem',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const rewardId = rewardIdSchema.safeParse(
        (request.params as { id?: unknown }).id,
      );
      const body = redeemSchema.safeParse(request.body);
      if (!rewardId.success || !body.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'The reward redemption request is invalid.',
          issues: [
            ...(!rewardId.success ? rewardId.error.issues : []),
            ...(!body.success ? body.error.issues : []),
          ],
        });
      }

      const user = request.user!;
      try {
        return await redeemLoyaltyReward(
          {
            postgresUserId: user.id,
            firebaseUid: user.firebaseUid,
            email: user.email,
            username: user.username,
            displayName: user.displayName,
            isYouTubeMember: user.isYouTubeMember,
          },
          rewardId.data,
          body.data.idempotencyKey,
        );
      } catch (error) {
        if (error instanceof LoyaltyRedemptionError) {
          return reply.status(redemptionStatus(error.reason)).send({
            error: 'LoyaltyRedemptionError',
            reason: error.reason,
            message: error.message,
          });
        }
        request.log.error(
          { err: error, rewardId: rewardId.data },
          'Loyalty reward redemption failed',
        );
        return reply.status(503).send({
          error: 'RedemptionUnavailable',
          message: 'The reward could not be redeemed right now. Please try again.',
        });
      }
    },
  );
}
