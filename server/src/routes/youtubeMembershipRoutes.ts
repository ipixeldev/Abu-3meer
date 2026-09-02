import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { authenticateUser, requirePermission } from '../middleware/auth.js';
import {
  getMyYouTubeChannelClaim,
} from '../services/youtubeChannelClaimService.js';
import {
  YouTubeMembershipVerificationError,
  checkYouTubeMembership,
} from '../services/youtubeMembershipVerificationService.js';
import {
  YouTubeMembershipSnapshotError,
  getYouTubeMembershipSnapshotStatus,
  importYouTubeMembershipSnapshot,
  youtubeMembershipSnapshotMaxBytes,
} from '../services/youtubeMembershipSnapshotService.js';

const snapshotImportQuerySchema = z.object({
  confirmLargeDecrease: z.enum(['true']).optional(),
});
const membershipCheckSchema = z.object({
  accessToken: z.string()
    .min(20)
    .max(4096)
    .regex(/^[\x21-\x7e]+$/),
}).strict();

function sendVerificationError(reply: FastifyReply, error: unknown) {
  if (error instanceof YouTubeMembershipVerificationError) {
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
    '/profile/youtube/membership/check',
    {
      preHandler: [authenticateUser],
      config: {
        rateLimit: {
          max: 6,
          timeWindow: '1 hour',
          // Run after authentication so refreshed Firebase bearer tokens still
          // share one stable per-user quota bucket.
          hook: 'preHandler',
          keyGenerator: (request) =>
            `youtube-membership-check:user:${request.user?.id ?? request.ip}`,
        },
      },
    },
    async (request, reply) => {
      const parsed = membershipCheckSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'A valid short-lived Google access token is required.',
        });
      }
      try {
        return await checkYouTubeMembership({
          userId: request.user!.id,
          expectedGoogleSubject: request.user!.googleProviderUid,
          accessToken: parsed.data.accessToken,
        });
      } catch (error) {
        return sendVerificationError(reply, error);
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
