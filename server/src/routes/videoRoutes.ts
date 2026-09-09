import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser, requirePermission } from '../middleware/auth.js';
import { getClient, query } from '../db/pool.js';
import {
  cancelNotificationCampaignBySource,
  createNotificationCampaign,
} from '../services/notificationService.js';
import { exclusiveVideoNotificationCampaign } from '../services/exclusiveVideoNotification.js';
import {
  cancelNotificationCampaignJob,
  enqueueNotificationCampaign,
} from '../queues/workers.js';
import {
  isValidYoutubeVideoId,
  listExclusiveVideos,
} from '../services/videoDomain.js';
import { resolveChallengeMembership } from '../services/challengeMembershipService.js';

export async function videoRoutes(fastify: FastifyInstance) {
  // GET /api/v1/videos/latest - Latest normal public channel upload for Home.
  // This record is deliberately separate from the Exclusive catalogue.
  fastify.get('/videos/latest', async (_request, reply) => {
    const result = await query(
      `SELECT youtube_id, title, thumbnail_url, video_url, published_at
       FROM youtube_latest_public_video
       WHERE singleton = TRUE
       LIMIT 1`,
    );
    const video = result.rows[0];
    if (!video) {
      return reply.status(404).send({
        error: 'LatestVideoUnavailable',
        message: 'The latest public YouTube video has not been synchronized yet.',
      });
    }
    reply.header('Cache-Control', 'public, max-age=300, stale-while-revalidate=3600');
    return {
      id: video.youtube_id,
      title: video.title,
      url: video.video_url,
      thumbnailUrl: video.thumbnail_url,
      publishedAt: video.published_at,
    };
  });

  // GET /api/v1/videos/exclusive - List published exclusive videos for app users
  fastify.get(
    '/videos/exclusive',
    { preHandler: [authenticateUser] },
    async (request, reply) => {
      reply.header('Cache-Control', 'private, no-store');
      let canAccessMemberOnly = false;
      try {
        canAccessMemberOnly = await resolveChallengeMembership(request.user!.id);
      } catch (error) {
        request.log.warn({ err: error }, 'Member video visibility unavailable');
      }
      return listExclusiveVideos(
        (text, params) => query(text, params),
        {
          includeScheduled: false,
          canAccessMemberOnly,
        },
      );
    },
  );

  // GET /api/v1/admin/videos - Include scheduled entries in Admin Studio.
  fastify.get(
    '/admin/videos',
    { preHandler: [requirePermission('challenges.manage')] },
    async (_request, reply) => {
      reply.header('Cache-Control', 'no-store');
      return listExclusiveVideos(
        (text, params) => query(text, params),
        { includeScheduled: true, canAccessMemberOnly: true },
      );
    },
  );

  // POST /api/v1/admin/videos - Add/schedule special YouTube video (Admin only)
  fastify.post('/admin/videos', { preHandler: [requirePermission('challenges.manage')] }, async (request, reply) => {
    const schema = z.object({
      youtubeId: z.string().trim().refine(
        isValidYoutubeVideoId,
        'Enter a valid 11-character YouTube video ID.',
      ),
      title: z.string().trim().min(3).max(255),
      description: z.string().trim().max(2000).optional(),
      thumbnailUrl: z.string().url().max(500).optional(),
      publishedAt: z.string().datetime().optional(),
      isUnlisted: z.boolean().default(true),
      memberOnly: z.boolean().default(false),
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const { youtubeId, title, description, thumbnailUrl, publishedAt, isUnlisted, memberOnly } = parsed.data;
    const autoThumbnail = thumbnailUrl || `https://img.youtube.com/vi/${youtubeId}/hqdefault.jpg`;
    const videoUrl = `https://www.youtube.com/watch?v=${youtubeId}`;
    const pubDate = publishedAt ? new Date(publishedAt) : new Date();
    const id = `vid_${youtubeId}`;
    let video: Record<string, unknown>;
    let campaignId: string | null = null;
    let campaignScheduledFor: Date | null = null;
    let notificationScheduled = false;
    let notificationQueued = false;
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const existingVideo = await client.query(
        'SELECT id FROM videos WHERE youtube_id = $1 LIMIT 1 FOR UPDATE',
        [youtubeId],
      );

      const res = await client.query(
        `INSERT INTO videos (id, youtube_id, title, description, thumbnail_url, video_url, published_at, is_unlisted, member_only)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (youtube_id) DO UPDATE SET
           title = EXCLUDED.title,
           description = EXCLUDED.description,
           thumbnail_url = EXCLUDED.thumbnail_url,
           video_url = EXCLUDED.video_url,
           published_at = EXCLUDED.published_at,
           is_unlisted = EXCLUDED.is_unlisted,
           member_only = EXCLUDED.member_only
         RETURNING *`,
        [id, youtubeId, title, description || null, autoThumbnail, videoUrl, pubDate, isUnlisted, memberOnly],
      );
      video = res.rows[0] as Record<string, unknown>;

      await client.query(
        `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
         VALUES ($1, 'video.upsert', 'video', $2, $3)`,
        [request.user!.id, id, JSON.stringify(video)],
      );

      // Editing an existing entry must not notify everyone again. The video,
      // audit receipt, and durable outbox row commit as one unit.
      if (existingVideo.rowCount === 0) {
        const campaign = await createNotificationCampaign(
          exclusiveVideoNotificationCampaign({
            videoId: id,
            youtubeId,
            title,
            thumbnailUrl: autoThumbnail,
            publishedAt: pubDate,
            memberOnly,
            createdBy: request.user!.id,
          }),
          (text, params) => client.query(text, params),
        );
        campaignId = campaign.campaignId;
        campaignScheduledFor = campaign.scheduledFor;
        notificationScheduled = campaignId !== null;
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }

    // BullMQ is intentionally touched only after PostgreSQL commits. If Redis
    // is unavailable, the durable outbox recovery loop will enqueue it later.
    if (campaignId && campaignScheduledFor) {
      try {
        await enqueueNotificationCampaign(campaignId, campaignScheduledFor);
        notificationQueued = true;
      } catch (error) {
        fastify.log.error(
          { err: error, campaignId },
          'Exclusive-video notification left pending for outbox recovery',
        );
      }
    }

    return {
      success: true,
      video,
      notificationScheduled,
      notificationQueued,
    };
  });

  // DELETE /api/v1/admin/videos/:id - Remove video
  fastify.delete('/admin/videos/:id', { preHandler: [requirePermission('challenges.manage')] }, async (request, reply) => {
    const rawId = (request.params as { id: string }).id.trim();
    if (!/^[A-Za-z0-9_.-]{1,100}$/.test(rawId)) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'Video ID is invalid.',
      });
    }
    const id = rawId;
    let cancelledCampaignIds: string[] = [];
    const client = await getClient();
    try {
      await client.query('BEGIN');
      const deleted = await client.query(
        `DELETE FROM videos
         WHERE id = $1
         RETURNING id, youtube_id, title, published_at`,
        [id],
      );
      if (!deleted.rowCount) {
        await client.query('ROLLBACK');
        return reply.status(404).send({
          error: 'NotFound',
          message: 'Exclusive video not found.',
        });
      }

      cancelledCampaignIds = await cancelNotificationCampaignBySource(
        'exclusive_video',
        id,
        (text, params) => client.query(text, params),
      );

      await client.query(
        `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
         VALUES ($1, 'video.delete', 'video', $2, $3)`,
        [request.user!.id, id, JSON.stringify(deleted.rows[0])],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }

    for (const cancelledCampaignId of cancelledCampaignIds) {
      try {
        await cancelNotificationCampaignJob(cancelledCampaignId);
      } catch (error) {
        fastify.log.warn(
          { err: error, campaignId: cancelledCampaignId },
          'Cancelled Exclusive-video notification job will no-op if it reaches a worker',
        );
      }
    }

    return {
      success: true,
      id,
      notificationsCancelled: cancelledCampaignIds.length,
    };
  });
}
