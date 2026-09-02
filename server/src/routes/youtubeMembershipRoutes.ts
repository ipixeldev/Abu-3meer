import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { authenticateUser, requirePermission } from '../middleware/auth.js';
import {
  YouTubeChannelClaimError,
  decideYouTubeChannelClaim,
  getMyYouTubeChannelClaim,
  listYouTubeChannelClaims,
  submitYouTubeChannelClaim,
} from '../services/youtubeChannelClaimService.js';
import {
  YouTubeMembershipSnapshotError,
  getYouTubeMembershipSnapshotStatus,
  importYouTubeMembershipSnapshot,
  youtubeMembershipSnapshotMaxBytes,
} from '../services/youtubeMembershipSnapshotService.js';

const snapshotImportQuerySchema = z.object({
  confirmLargeDecrease: z.enum(['true']).optional(),
});
const channelClaimSchema = z.object({
  channel: z.string().trim().min(1).max(300),
}).strict();
const claimListSchema = z.object({
  status: z.enum([
    'pending',
    'approved',
    'rejected',
    'revoked',
    'superseded',
  ]).optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
});
const claimDecisionSchema = z.object({
  decision: z.enum(['approve', 'reject', 'revoke']),
  reason: z.string().trim().min(3).max(500),
}).strict();

function sendClaimError(reply: FastifyReply, error: unknown) {
  if (error instanceof YouTubeChannelClaimError) {
    return reply.status(error.httpStatus).send({
      error: error.code,
      message: error.message,
    });
  }
  throw error;
}

function sendSnapshotError(reply: FastifyReply, error: unknown) {
  if (error instanceof YouTubeMembershipSnapshotError) {
    return reply.status(error.httpStatus).send({
      error: error.code,
      message: error.message,
    });
  }
  throw error;
}

export async function youtubeMembershipRoutes(fastify: FastifyInstance) {
  fastify.get(
    '/profile/youtube/claim',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request) => ({
      claim: await getMyYouTubeChannelClaim(request.user!.id),
    }),
  );

  fastify.post(
    '/profile/youtube/claim',
    {
      preHandler: [authenticateUser],
      config: { rateLimit: { max: 4, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      const parsed = channelClaimSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Enter a valid YouTube channel ID or /channel/ URL.',
        });
      }
      try {
        const claim = await submitYouTubeChannelClaim({
          userId: request.user!.id,
          channel: parsed.data.channel,
        });
        return reply.status(201).send({ claim });
      } catch (error) {
        return sendClaimError(reply, error);
      }
    },
  );

  fastify.get(
    '/admin/youtube/membership/claims',
    {
      preHandler: [requirePermission('membership_snapshots.manage')],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const parsed = claimListSchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'The claim filter is invalid.',
        });
      }
      return { claims: await listYouTubeChannelClaims(parsed.data) };
    },
  );

  fastify.post(
    '/admin/youtube/membership/claims/:claimId/decision',
    {
      preHandler: [requirePermission('membership_snapshots.manage')],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (request, reply) => {
      const claimId = z.string().uuid().safeParse(
        (request.params as { claimId?: string }).claimId,
      );
      const decision = claimDecisionSchema.safeParse(request.body);
      if (!claimId.success || !decision.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'The claim decision or audit reason is invalid.',
        });
      }
      try {
        const claim = await decideYouTubeChannelClaim({
          claimId: claimId.data,
          decision: decision.data.decision,
          reason: decision.data.reason,
          reviewedByUserId: request.user!.id,
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'] ?? null,
        });
        return { claim };
      } catch (error) {
        return sendClaimError(reply, error);
      }
    },
  );

  fastify.get(
    '/admin/youtube/membership/snapshot',
    {
      preHandler: [requirePermission('membership_snapshots.manage')],
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (_request, reply) => {
      try {
        return await getYouTubeMembershipSnapshotStatus();
      } catch (error) {
        return sendSnapshotError(reply, error);
      }
    },
  );

  fastify.post(
    '/admin/youtube/membership/snapshot',
    {
      preHandler: [requirePermission('membership_snapshots.manage')],
      config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      try {
        const parsedQuery = snapshotImportQuerySchema.safeParse(request.query);
        if (!parsedQuery.success) {
          return reply.status(400).send({
            error: 'ValidationError',
            message: 'The snapshot confirmation value is invalid.',
          });
        }
        const part = await request.file({
          limits: { files: 1, fileSize: youtubeMembershipSnapshotMaxBytes },
        });
        if (!part || part.fieldname !== 'file') {
          throw new YouTubeMembershipSnapshotError(
            'youtube_snapshot_file_required',
            400,
            'Attach one .csv or .tsv membership export using the “file” field.',
          );
        }
        const bytes = await part.toBuffer();
        if (
          part.file.truncated ||
          bytes.length > youtubeMembershipSnapshotMaxBytes
        ) {
          throw new YouTubeMembershipSnapshotError(
            'youtube_snapshot_too_large',
            413,
            'The membership snapshot must be 5 MB or smaller.',
          );
        }
        const status = await importYouTubeMembershipSnapshot({
          bytes,
          fileName: part.filename,
          importedByUserId: request.user!.id,
          allowLargeDecrease:
            parsedQuery.data.confirmLargeDecrease === 'true',
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'] ?? null,
        });
        return reply.status(201).send(status);
      } catch (error: any) {
        if (error?.code === 'FST_REQ_FILE_TOO_LARGE') {
          return reply.status(413).send({
            error: 'youtube_snapshot_too_large',
            message: 'The membership snapshot must be 5 MB or smaller.',
          });
        }
        return sendSnapshotError(reply, error);
      }
    },
  );
}
