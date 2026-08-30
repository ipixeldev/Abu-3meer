import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requirePermission } from '../middleware/auth.js';
import { query } from '../db/pool.js';

export async function videoRoutes(fastify: FastifyInstance) {
  // GET /api/v1/videos/exclusive - List published exclusive videos for app users
  fastify.get('/videos/exclusive', async (request, reply) => {
    const res = await query(
      `SELECT id, youtube_id, title, description, thumbnail_url, video_url, published_at, is_unlisted, member_only, view_count
       FROM videos
       WHERE published_at <= CURRENT_TIMESTAMP
       ORDER BY published_at DESC
       LIMIT 50`
    );
    return res.rows;
  });

  // POST /api/v1/admin/videos - Add/schedule special YouTube video (Admin only)
  fastify.post('/admin/videos', { preHandler: [requirePermission('challenges.manage')] }, async (request, reply) => {
    const schema = z.object({
      youtubeId: z.string().trim().min(5).max(50),
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

    const res = await query(
      `INSERT INTO videos (id, youtube_id, title, description, thumbnail_url, video_url, published_at, is_unlisted, member_only)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       ON CONFLICT (youtube_id) DO UPDATE SET
         title = EXCLUDED.title,
         description = EXCLUDED.description,
         thumbnail_url = EXCLUDED.thumbnail_url,
         published_at = EXCLUDED.published_at,
         is_unlisted = EXCLUDED.is_unlisted,
         member_only = EXCLUDED.member_only
       RETURNING *`,
      [id, youtubeId, title, description || null, autoThumbnail, videoUrl, pubDate, isUnlisted, memberOnly]
    );

    // Audit log
    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'video.upsert', 'video', $2, $3)`,
      [request.user!.id, id, JSON.stringify(res.rows[0])]
    );

    return { success: true, video: res.rows[0] };
  });

  // DELETE /api/v1/admin/videos/:id - Remove video
  fastify.delete('/admin/videos/:id', { preHandler: [requirePermission('challenges.manage')] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    await query('DELETE FROM videos WHERE id = $1', [id]);

    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'video.delete', 'video', $2, '{}')`,
      [request.user!.id, id]
    );

    return { success: true };
  });
}
