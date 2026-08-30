import crypto from 'crypto';
import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getClient, query } from '../db/pool.js';
import { getAdminFirestore, firebaseAdmin, firestoreTimestampToIso } from '../firebase/firestore.js';
import { requirePermission } from '../middleware/auth.js';
import { redis } from '../redis/client.js';
import {
  adminChallengeStatuses,
  calculateLoyaltyRefund,
  canTransitionRedemptionStatus,
  finiteInteger,
  loyaltyRefundTransactionId,
  loyaltyRewardClaimId,
  redemptionStatuses,
  safeDocumentId,
} from '../services/adminContentDomain.js';
import { normalizeChallengeAnswer } from '../services/challengeService.js';
import {
  cancelNotificationCampaignBySource,
  createNotificationCampaign,
  type CreatedNotificationCampaign,
} from '../services/notificationService.js';
import {
  challengeNotificationCampaign,
  shouldScheduleChallengeNotification,
} from '../services/challengeNotification.js';
import {
  cancelNotificationCampaignJob,
  enqueueNotificationCampaign,
} from '../queues/workers.js';

const optionalUrl = z.string().trim().max(1000).refine((value) => {
  if (!value) return true;
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}, 'URL must be a complete http or https URL.');

const challengeQuestionSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/),
  prompt: z.string().trim().min(1).max(1000),
  type: z.enum(['text', 'multipleChoice', 'trueFalse']).default('text'),
  options: z.array(z.string().trim().min(1).max(300)).max(20).default([]),
  correctAnswer: z.string().trim().min(1).max(300),
  acceptedAnswers: z.array(z.string().trim().min(1).max(300)).max(20).default([]),
});

const challengeCreateSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/).optional(),
  kind: z.enum(['videoPhrase', 'playerCard']),
  title: z.string().trim().min(1).max(255),
  description: z.string().trim().max(5000).default(''),
  videoUrl: optionalUrl.default(''),
  imageUrl: optionalUrl.default(''),
  rewardPoints: z.number().int().min(1).max(1_000_000),
  availableFrom: z.string().datetime(),
  availableUntil: z.string().datetime(),
  status: z.enum(adminChallengeStatuses).default('open'),
  maximumAttempts: z.number().int().min(1).max(20).default(3),
  memberOnly: z.boolean().default(false),
  notifyOnLive: z.boolean().default(false),
  // The current app presents one answer field and the submission endpoint
  // validates one answer. Reject hidden/legacy multi-question payloads rather
  // than publishing questions that cannot be scored correctly.
  questions: z.array(challengeQuestionSchema).length(1),
}).superRefine((value, context) => {
  if (new Date(value.availableUntil) <= new Date(value.availableFrom)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['availableUntil'],
      message: 'Challenge end time must be after its start time.',
    });
  }
  value.questions.forEach((question, index) => {
    if (question.type === 'multipleChoice') {
      const options = question.options.map((option) => option.toLowerCase());
      if (options.length < 2 || !options.includes(question.correctAnswer.toLowerCase())) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['questions', index, 'correctAnswer'],
          message: 'A multiple-choice answer must match one of at least two options.',
        });
      }
    }
  });
});

const challengeStatusSchema = z.object({
  status: z.enum(adminChallengeStatuses),
});

const playerCardSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/).optional(),
  playerName: z.string().trim().min(1).max(150),
  playerNameAr: z.string().trim().max(150).default(''),
  imageUrl: optionalUrl.default(''),
  teamName: z.string().trim().max(150).default(''),
  teamLogoUrl: optionalUrl.default(''),
  position: z.string().trim().max(50).default(''),
  rating: z.number().int().min(1).max(99),
  rarity: z.enum(['common', 'rare', 'epic', 'legendary', 'silver', 'gold']).default('common'),
  stats: z.record(z.string().trim().min(1).max(50), z.number().int().min(0).max(999)).default({}),
  description: z.string().trim().max(5000).default(''),
  descriptionAr: z.string().trim().max(5000).default(''),
  enabled: z.boolean().default(true),
  sourceChallengeId: z.string().trim().max(100).default(''),
});

const playerCardStatusSchema = z.object({ enabled: z.boolean() });

const announcementSchema = z.object({
  enabled: z.boolean(),
  title: z.string().trim().min(1).max(200),
  body: z.string().trim().min(1).max(3000),
  imageUrl: optionalUrl.default(''),
  linkUrl: optionalUrl.default(''),
  buttonLabel: z.string().trim().max(80).default('OPEN'),
  frequency: z.enum(['once', 'daily', 'session', 'always']),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
}).superRefine((value, context) => {
  if (new Date(value.endsAt) <= new Date(value.startsAt)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endsAt'],
      message: 'Popup end time must be after its start time.',
    });
  }
});

const redemptionStatusSchema = z.object({
  status: z.enum(redemptionStatuses),
  note: z.string().trim().max(2000).default(''),
});

const achievementSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/).optional(),
  title: z.string().trim().min(1).max(200),
  titleAr: z.string().trim().max(200).default(''),
  description: z.string().trim().max(3000).default(''),
  descriptionAr: z.string().trim().max(3000).default(''),
  iconName: z.string().trim().min(1).max(100).default('emoji_events'),
  category: z.string().trim().min(1).max(100).default('points'),
  requirementType: z.string().trim().min(1).max(100).default('totalPoints'),
  requirementTarget: z.number().int().min(0).max(1_000_000_000),
  rewardPoints: z.number().int().min(0).max(1_000_000),
  levelUnlock: z.string().trim().max(100).default(''),
  isSecret: z.boolean().default(false),
  enabled: z.boolean().default(true),
  sortOrder: z.number().int().min(-1_000_000).max(1_000_000).default(0),
});

const levelSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/).optional(),
  name: z.string().trim().min(1).max(200),
  nameAr: z.string().trim().max(200).default(''),
  minimumPoints: z.number().int().min(0).max(1_000_000_000),
  maximumPoints: z.number().int().min(0).max(1_000_000_000).nullable().default(null),
  perks: z.array(z.string().trim().min(1).max(300)).max(100).default([]),
  perksAr: z.array(z.string().trim().min(1).max(300)).max(100).default([]),
  iconName: z.string().trim().min(1).max(100).default('military_tech'),
  color: z.string().trim().regex(/^[A-Fa-f0-9]{6,8}$/).default('C8FF38'),
  enabled: z.boolean().default(true),
  sortOrder: z.number().int().min(-1_000_000).max(1_000_000).default(0),
}).superRefine((value, context) => {
  if (value.maximumPoints != null && value.maximumPoints < value.minimumPoints) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['maximumPoints'],
      message: 'Maximum points cannot be lower than minimum points.',
    });
  }
});

const rewardSchema = z.object({
  id: z.string().trim().min(1).max(100).regex(/^[A-Za-z0-9_-]+$/).optional(),
  title: z.string().trim().min(1).max(200),
  titleAr: z.string().trim().max(200).default(''),
  description: z.string().trim().max(3000).default(''),
  descriptionAr: z.string().trim().max(3000).default(''),
  imageUrl: optionalUrl.default(''),
  category: z.string().trim().min(1).max(100).default('general'),
  cost: z.number().int().min(0).max(1_000_000_000),
  stock: z.number().int().min(0).max(1_000_000),
  unlimitedStock: z.boolean().default(false),
  perUserLimit: z.number().int().min(1).max(100),
  memberOnly: z.boolean().default(false),
  enabled: z.boolean().default(true),
  startsAt: z.string().datetime().nullable().default(null),
  endsAt: z.string().datetime().nullable().default(null),
  fulfilmentType: z.string().trim().min(1).max(100).default('manual'),
}).superRefine((value, context) => {
  if (value.startsAt && value.endsAt && new Date(value.endsAt) <= new Date(value.startsAt)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['endsAt'],
      message: 'Reward end time must be after its start time.',
    });
  }
});

const enabledSchema = z.object({ enabled: z.boolean() });

const challengeSelect = `
  SELECT c.id, c.video_id, c.title, c.description, c.kind, c.status,
         c.reward_points, c.reward_points * 2 AS member_points,
         c.video_url, c.image_url, c.maximum_attempts, c.member_only,
         c.notify_on_live, c.starts_at, c.ends_at,
         COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id', q.id,
               'prompt', q.prompt,
               'type', q.answer_type,
               'options', q.options
             ) ORDER BY q.position
           ) FILTER (WHERE q.id IS NOT NULL),
           '[]'::jsonb
         ) AS questions
  FROM challenges c
  LEFT JOIN challenge_questions q ON q.challenge_id = c.id`;

function redemptionToJson(id: string, data: Record<string, unknown>) {
  const userLabel = [
    data.userDisplayName,
    data.displayName,
    data.userEmail,
    data.email,
    data.userId,
  ].find((value) => typeof value === 'string' && value.trim());
  return {
    id,
    rewardId: String(data.rewardId ?? ''),
    rewardTitle: String(data.rewardTitle ?? ''),
    cost: Number(data.cost ?? 0),
    status: String(data.status ?? data.deliveryStatus ?? 'pending'),
    userId: String(data.userId ?? ''),
    userDisplayName: String(userLabel ?? ''),
    note: String(data.statusNote ?? data.adminNote ?? data.note ?? ''),
    createdAt: firestoreTimestampToIso(data.createdAt),
    fulfilledAt: firestoreTimestampToIso(data.fulfilledAt),
    updatedAt: firestoreTimestampToIso(data.updatedAt),
  };
}

async function audit(
  adminUserId: string,
  action: string,
  targetEntity: string,
  targetId: string,
  afterState: unknown,
) {
  await query(
    `INSERT INTO admin_audit_logs
       (admin_user_id, action, target_entity, target_id, after_state)
     VALUES ($1, $2, $3, $4, $5)`,
    [adminUserId, action, targetEntity, targetId, JSON.stringify(afterState)],
  );
}

export async function adminContentRoutes(fastify: FastifyInstance) {
  fastify.get(
    '/admin/challenges',
    { preHandler: [requirePermission('challenges.manage')] },
    async () => {
      const result = await query(
        `${challengeSelect}
         GROUP BY c.id
         ORDER BY c.created_at DESC
         LIMIT 200`,
      );
      return result.rows;
    },
  );

  fastify.post(
    '/admin/challenges',
    { preHandler: [requirePermission('challenges.manage')] },
    async (request, reply) => {
      const parsed = challengeCreateSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the challenge fields and try again.',
          issues: parsed.error.issues,
        });
      }
      const body = parsed.data;
      const id = body.id ?? `challenge_${crypto.randomUUID().replaceAll('-', '')}`;
      const primaryAnswer = body.questions[0].correctAnswer;
      let notificationCampaign: CreatedNotificationCampaign | null = null;
      const client = await getClient();
      try {
        await client.query('BEGIN');
        await client.query(
          `INSERT INTO challenges
             (id, title, description, kind, status, reward_points, member_points,
              correct_answer, normalized_correct_answer, video_url, image_url,
              maximum_attempts, member_only, notify_on_live, starts_at, ends_at)
           VALUES
             ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
          [
            id,
            body.title,
            body.description,
            body.kind,
            body.status,
            body.rewardPoints,
            body.rewardPoints * 2,
            primaryAnswer,
            normalizeChallengeAnswer(primaryAnswer),
            body.videoUrl || null,
            body.imageUrl || null,
            body.maximumAttempts,
            body.memberOnly,
            body.notifyOnLive,
            new Date(body.availableFrom),
            new Date(body.availableUntil),
          ],
        );
        for (let position = 0; position < body.questions.length; position += 1) {
          const question = body.questions[position];
          const answers = [question.correctAnswer, ...question.acceptedAnswers]
            .map(normalizeChallengeAnswer)
            .filter((answer, index, values) => answer && values.indexOf(answer) === index);
          await client.query(
            `INSERT INTO challenge_questions
               (id, challenge_id, prompt, answer_type, options,
                normalized_accepted_answers, position)
             VALUES ($1, $2, $3, $4, $5, $6, $7)`,
            [
              question.id,
              id,
              question.prompt,
              question.type,
              JSON.stringify(question.options),
              JSON.stringify(answers),
              position,
            ],
          );
        }
        await client.query(
          `INSERT INTO admin_audit_logs
             (admin_user_id, action, target_entity, target_id, after_state)
           VALUES ($1, 'challenges.create', 'challenge', $2, $3)`,
          [
            request.user!.id,
            id,
            JSON.stringify({
              kind: body.kind,
              title: body.title,
              status: body.status,
              rewardPoints: body.rewardPoints,
              questionCount: body.questions.length,
            }),
          ],
        );
        if (shouldScheduleChallengeNotification(body.notifyOnLive, body.status)) {
          notificationCampaign = await createNotificationCampaign(
            challengeNotificationCampaign({
              challengeId: id,
              title: body.title,
              imageUrl: body.imageUrl,
              startsAt: new Date(body.availableFrom),
              status: body.status,
              memberOnly: body.memberOnly,
              createdBy: request.user!.id,
            }),
            (text, params) => client.query(text, params),
          );
        }
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
      await redis.del(
        'cache:challenges:active',
        'cache:challenges:active:public',
        'cache:challenges:active:member',
      ).catch((error) => {
        fastify.log.warn({ err: error, challengeId: id }, 'Challenge cache invalidation deferred');
      });
      let notificationQueued = false;
      if (notificationCampaign?.campaignId) {
        try {
          await enqueueNotificationCampaign(
            notificationCampaign.campaignId,
            notificationCampaign.scheduledFor,
          );
          notificationQueued = true;
        } catch (error) {
          // The PostgreSQL campaign is the durable outbox. Periodic recovery
          // will enqueue it without turning a committed content save into an
          // apparent failure for the administrator.
          fastify.log.error(
            { err: error, campaignId: notificationCampaign.campaignId },
            'Challenge notification left pending for outbox recovery',
          );
        }
      }
      return reply.status(201).send({
        success: true,
        id,
        notificationScheduled: Boolean(notificationCampaign?.campaignId),
        notificationQueued,
      });
    },
  );

  fastify.put(
    '/admin/challenges/:id/status',
    { preHandler: [requirePermission('challenges.manage')] },
    async (request, reply) => {
      const parsed = challengeStatusSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const id = safeDocumentId((request.params as { id: string }).id, 'Challenge');
      let updated: Record<string, unknown> | null = null;
      let notificationCampaign: CreatedNotificationCampaign | null = null;
      let cancelledCampaignIds: string[] = [];
      const client = await getClient();
      try {
        await client.query('BEGIN');
        const result = await client.query(
          `UPDATE challenges
           SET status = $1, updated_at = CURRENT_TIMESTAMP
           WHERE id = $2
           RETURNING id, status, title, image_url, starts_at,
                     member_only, notify_on_live`,
          [parsed.data.status, id],
        );
        if (!result.rowCount) {
          await client.query('ROLLBACK');
          return reply.status(404).send({ error: 'NotFound', message: 'Challenge not found.' });
        }
        const row = result.rows[0] as Record<string, unknown>;
        updated = row;
        if (shouldScheduleChallengeNotification(
          row.notify_on_live === true,
          String(row.status),
        )) {
          notificationCampaign = await createNotificationCampaign(
            challengeNotificationCampaign({
              challengeId: id,
              title: String(row.title ?? ''),
              imageUrl: String(row.image_url ?? ''),
              startsAt: new Date(row.starts_at as Date),
              status: String(row.status),
              memberOnly: row.member_only === true,
              createdBy: request.user!.id,
            }),
            (text, params) => client.query(text, params),
          );
        } else {
          cancelledCampaignIds = await cancelNotificationCampaignBySource(
            'challenge',
            id,
            (text, params) => client.query(text, params),
          );
        }
        await client.query(
          `INSERT INTO admin_audit_logs
             (admin_user_id, action, target_entity, target_id, after_state)
           VALUES ($1, 'challenges.status_update', 'challenge', $2, $3)`,
          [
            request.user!.id,
            id,
            JSON.stringify({
              status: parsed.data.status,
              notificationCampaignId: notificationCampaign?.campaignId ?? null,
              notificationsCancelled: cancelledCampaignIds.length,
            }),
          ],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }

      await redis.del(
        'cache:challenges:active',
        'cache:challenges:active:public',
        'cache:challenges:active:member',
      ).catch((error) => {
        fastify.log.warn({ err: error, challengeId: id }, 'Challenge cache invalidation deferred');
      });
      let notificationQueued = false;
      if (notificationCampaign?.campaignId) {
        try {
          await enqueueNotificationCampaign(
            notificationCampaign.campaignId,
            notificationCampaign.scheduledFor,
          );
          notificationQueued = true;
        } catch (error) {
          fastify.log.error(
            { err: error, campaignId: notificationCampaign.campaignId },
            'Challenge notification left pending for outbox recovery',
          );
        }
      }
      for (const campaignId of cancelledCampaignIds) {
        try {
          await cancelNotificationCampaignJob(campaignId);
        } catch (error) {
          fastify.log.warn(
            { err: error, campaignId },
            'Cancelled challenge notification job will no-op if it reaches a worker',
          );
        }
      }
      return {
        success: true,
        ...updated,
        notificationScheduled: Boolean(notificationCampaign?.campaignId),
        notificationQueued,
        notificationsCancelled: cancelledCampaignIds.length,
      };
    },
  );

  fastify.get(
    '/admin/player-cards',
    { preHandler: [requirePermission('player_cards.manage')] },
    async () => {
      const result = await query(
        `SELECT id, player_name, player_name_ar, card_image_url, team,
                team_logo_url, position, rating, rarity, stats, description,
                description_ar, enabled, source_challenge_id, updated_at
         FROM player_cards
         ORDER BY updated_at DESC
         LIMIT 200`,
      );
      return result.rows;
    },
  );

  fastify.post(
    '/admin/player-cards',
    { preHandler: [requirePermission('player_cards.manage')] },
    async (request, reply) => {
      const parsed = playerCardSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the Player Card fields and try again.',
          issues: parsed.error.issues,
        });
      }
      const body = parsed.data;
      const id = body.id ?? `card_${crypto.randomUUID().replaceAll('-', '')}`;
      await query(
        `INSERT INTO player_cards
           (id, challenge_id, player_name, normalized_player_name, team,
            position, card_tier, card_image_url, player_name_ar, team_logo_url,
            rating, rarity, stats, description, description_ar, enabled,
            source_challenge_id, updated_at)
         VALUES
           ($1, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $6, $11, $12,
            $13, $14, $15, CURRENT_TIMESTAMP)
         ON CONFLICT (id) DO UPDATE SET
           player_name = EXCLUDED.player_name,
           normalized_player_name = EXCLUDED.normalized_player_name,
           team = EXCLUDED.team,
           position = EXCLUDED.position,
           card_tier = EXCLUDED.card_tier,
           card_image_url = EXCLUDED.card_image_url,
           player_name_ar = EXCLUDED.player_name_ar,
           team_logo_url = EXCLUDED.team_logo_url,
           rating = EXCLUDED.rating,
           rarity = EXCLUDED.rarity,
           stats = EXCLUDED.stats,
           description = EXCLUDED.description,
           description_ar = EXCLUDED.description_ar,
           enabled = EXCLUDED.enabled,
           source_challenge_id = EXCLUDED.source_challenge_id,
           updated_at = CURRENT_TIMESTAMP`,
        [
          id,
          body.playerName,
          normalizeChallengeAnswer(body.playerName),
          body.teamName,
          body.position,
          body.rarity,
          body.imageUrl,
          body.playerNameAr,
          body.teamLogoUrl,
          body.rating,
          JSON.stringify(body.stats),
          body.description,
          body.descriptionAr,
          body.enabled,
          body.sourceChallengeId,
        ],
      );
      await audit(request.user!.id, 'player_cards.upsert', 'player_card', id, {
        playerName: body.playerName,
        enabled: body.enabled,
        rating: body.rating,
        rarity: body.rarity,
      });
      return reply.status(body.id ? 200 : 201).send({ success: true, id });
    },
  );

  fastify.put(
    '/admin/player-cards/:id/status',
    { preHandler: [requirePermission('player_cards.manage')] },
    async (request, reply) => {
      const parsed = playerCardStatusSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const id = safeDocumentId((request.params as { id: string }).id, 'Player Card');
      const result = await query(
        `UPDATE player_cards
         SET enabled = $1, updated_at = CURRENT_TIMESTAMP
         WHERE id = $2
         RETURNING id, enabled`,
        [parsed.data.enabled, id],
      );
      if (!result.rowCount) {
        return reply.status(404).send({ error: 'NotFound', message: 'Player Card not found.' });
      }
      await audit(request.user!.id, 'player_cards.status_update', 'player_card', id, parsed.data);
      return { success: true, ...result.rows[0] };
    },
  );

  fastify.get('/settings/launch-announcement', async (_request, reply) => {
    const result = await query(
      `SELECT value FROM platform_settings WHERE key = 'launchAnnouncement'`,
    );
    if (!result.rowCount) return reply.status(200).send(null);
    return result.rows[0].value;
  });

  fastify.put(
    '/admin/settings/launch-announcement',
    { preHandler: [requirePermission('settings.manage')] },
    async (request, reply) => {
      const parsed = announcementSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the popup content and schedule and try again.',
          issues: parsed.error.issues,
        });
      }
      const value = {
        ...parsed.data,
        revision: Date.now(),
        updatedAt: new Date().toISOString(),
      };
      await query(
        `INSERT INTO platform_settings (key, value, description, updated_by)
         VALUES ('launchAnnouncement', $1, 'Home-screen launch popup', $2)
         ON CONFLICT (key) DO UPDATE SET
           value = EXCLUDED.value,
           updated_at = CURRENT_TIMESTAMP,
           updated_by = EXCLUDED.updated_by`,
        [JSON.stringify(value), request.user!.id],
      );
      await audit(
        request.user!.id,
        'settings.launch_announcement_update',
        'platform_setting',
        'launchAnnouncement',
        value,
      );
      return { success: true, announcement: value };
    },
  );

  fastify.post(
    '/admin/achievements',
    { preHandler: [requirePermission('settings.manage')] },
    async (request, reply) => {
      const parsed = achievementSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the achievement fields and try again.',
          issues: parsed.error.issues,
        });
      }
      const { id: requestedId, ...definition } = parsed.data;
      const collection = getAdminFirestore().collection('achievementDefinitions');
      const reference = requestedId
        ? collection.doc(safeDocumentId(requestedId, 'Achievement'))
        : collection.doc();
      await reference.set(
        {
          ...definition,
          updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.user!.firebaseUid,
        },
        { merge: true },
      );
      await audit(request.user!.id, 'achievements.upsert', 'achievement', reference.id, {
        ...definition,
        updatedBy: request.user!.firebaseUid,
      });
      return reply.status(requestedId ? 200 : 201).send({ success: true, id: reference.id });
    },
  );

  fastify.put(
    '/admin/achievements/:id/status',
    { preHandler: [requirePermission('settings.manage')] },
    async (request, reply) => {
      const parsed = enabledSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const id = safeDocumentId((request.params as { id: string }).id, 'Achievement');
      const reference = getAdminFirestore().collection('achievementDefinitions').doc(id);
      if (!(await reference.get()).exists) {
        return reply.status(404).send({ error: 'NotFound', message: 'Achievement not found.' });
      }
      await reference.update({
        enabled: parsed.data.enabled,
        updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.user!.firebaseUid,
      });
      await audit(request.user!.id, 'achievements.status_update', 'achievement', id, parsed.data);
      return { success: true, id, enabled: parsed.data.enabled };
    },
  );

  fastify.post(
    '/admin/levels',
    { preHandler: [requirePermission('settings.manage')] },
    async (request, reply) => {
      const parsed = levelSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the level fields and try again.',
          issues: parsed.error.issues,
        });
      }
      const { id: requestedId, ...definition } = parsed.data;
      const collection = getAdminFirestore().collection('levelDefinitions');
      const reference = requestedId
        ? collection.doc(safeDocumentId(requestedId, 'Level'))
        : collection.doc();
      await reference.set(
        {
          ...definition,
          updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.user!.firebaseUid,
        },
        { merge: true },
      );
      await audit(request.user!.id, 'levels.upsert', 'level', reference.id, {
        ...definition,
        updatedBy: request.user!.firebaseUid,
      });
      return reply.status(requestedId ? 200 : 201).send({ success: true, id: reference.id });
    },
  );

  fastify.put(
    '/admin/levels/:id/status',
    { preHandler: [requirePermission('settings.manage')] },
    async (request, reply) => {
      const parsed = enabledSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const id = safeDocumentId((request.params as { id: string }).id, 'Level');
      const reference = getAdminFirestore().collection('levelDefinitions').doc(id);
      if (!(await reference.get()).exists) {
        return reply.status(404).send({ error: 'NotFound', message: 'Level not found.' });
      }
      await reference.update({
        enabled: parsed.data.enabled,
        updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.user!.firebaseUid,
      });
      await audit(request.user!.id, 'levels.status_update', 'level', id, parsed.data);
      return { success: true, id, enabled: parsed.data.enabled };
    },
  );

  fastify.post(
    '/admin/rewards',
    { preHandler: [requirePermission('prizes.manage')] },
    async (request, reply) => {
      const parsed = rewardSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the reward fields and try again.',
          issues: parsed.error.issues,
        });
      }
      const { id: requestedId, startsAt, endsAt, ...definition } = parsed.data;
      const collection = getAdminFirestore().collection('loyaltyRewards');
      const reference = requestedId
        ? collection.doc(safeDocumentId(requestedId, 'Reward'))
        : collection.doc();
      await reference.set(
        {
          ...definition,
          status: definition.enabled ? 'active' : 'disabled',
          availableFrom: startsAt
            ? firebaseAdmin.firestore.Timestamp.fromDate(new Date(startsAt))
            : null,
          availableUntil: endsAt
            ? firebaseAdmin.firestore.Timestamp.fromDate(new Date(endsAt))
            : null,
          updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.user!.firebaseUid,
        },
        { merge: true },
      );
      await audit(request.user!.id, 'rewards.upsert', 'reward', reference.id, {
        ...definition,
        startsAt,
        endsAt,
        updatedBy: request.user!.firebaseUid,
      });
      return reply.status(requestedId ? 200 : 201).send({ success: true, id: reference.id });
    },
  );

  fastify.put(
    '/admin/rewards/:id/status',
    { preHandler: [requirePermission('prizes.manage')] },
    async (request, reply) => {
      const parsed = enabledSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const id = safeDocumentId((request.params as { id: string }).id, 'Reward');
      const reference = getAdminFirestore().collection('loyaltyRewards').doc(id);
      if (!(await reference.get()).exists) {
        return reply.status(404).send({ error: 'NotFound', message: 'Reward not found.' });
      }
      await reference.update({
        enabled: parsed.data.enabled,
        status: parsed.data.enabled ? 'active' : 'disabled',
        updatedAt: firebaseAdmin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.user!.firebaseUid,
      });
      await audit(request.user!.id, 'rewards.status_update', 'reward', id, parsed.data);
      return { success: true, id, enabled: parsed.data.enabled };
    },
  );

  fastify.get(
    '/admin/redemptions',
    { preHandler: [requirePermission('redemptions.manage')] },
    async (_request, reply) => {
      try {
        const snapshot = await getAdminFirestore()
          .collection('loyaltyRedemptions')
          .orderBy('createdAt', 'desc')
          .limit(200)
          .get();
        return snapshot.docs.map((document) =>
          redemptionToJson(document.id, document.data() as Record<string, unknown>),
        );
      } catch (error) {
        fastify.log.error({ err: error }, 'Could not load loyalty redemptions from Firestore');
        return reply.status(503).send({
          error: 'RedemptionsUnavailable',
          message: 'Redemption storage is temporarily unavailable. Check the server Firebase credentials.',
        });
      }
    },
  );

  fastify.put(
    '/admin/redemptions/:id/status',
    { preHandler: [requirePermission('redemptions.manage')] },
    async (request, reply) => {
      const parsed = redemptionStatusSchema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
      }
      const redemptionId = safeDocumentId(
        (request.params as { id: string }).id,
        'Redemption',
      );
      const { status, note } = parsed.data;
      if (status === 'cancelled' && !note) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'A cancellation reason is required so the refund is auditable.',
        });
      }
      const db = getAdminFirestore();
      const redemptionRef = db.collection('loyaltyRedemptions').doc(redemptionId);
      let previousStatus = '';
      let refunded = false;
      try {
        await db.runTransaction(async (transaction) => {
          const redemptionDoc = await transaction.get(redemptionRef);
          if (!redemptionDoc.exists) throw new Error('Redemption not found.');
          const redemption = redemptionDoc.data()!;
          const current = String(redemption.status ?? redemption.deliveryStatus ?? 'pending');
          if (!redemptionStatuses.includes(current as (typeof redemptionStatuses)[number])) {
            throw new Error('Stored redemption status is invalid.');
          }
          previousStatus = current;
          if (!canTransitionRedemptionStatus(
            current as (typeof redemptionStatuses)[number],
            status,
          )) {
            throw new Error(`Redemption cannot move from ${current} to ${status}.`);
          }
          if (current === status) return;

          const changedAt = firebaseAdmin.firestore.FieldValue.serverTimestamp();
          const update: Record<string, unknown> = {
            status,
            deliveryStatus: status,
            statusChangedAt: changedAt,
            statusChangedBy: request.user!.firebaseUid,
            note,
            adminNote: note,
            statusNote: note,
            updatedAt: changedAt,
          };

          if (status === 'cancelled') {
            const userId = safeDocumentId(String(redemption.userId ?? ''), 'Redemption user');
            const rewardId = safeDocumentId(String(redemption.rewardId ?? ''), 'Redemption reward');
            const userRef = db.collection('users').doc(userId);
            const rewardRef = db.collection('loyaltyRewards').doc(rewardId);
            const claimRef = db.collection('loyaltyRewardClaims').doc(
              loyaltyRewardClaimId(userId, rewardId),
            );
            const refundRef = db.collection('loyaltyTransactions').doc(
              loyaltyRefundTransactionId(redemptionId),
            );
            const [userDoc, rewardDoc, claimDoc, refundDoc] = await Promise.all([
              transaction.get(userRef),
              transaction.get(rewardRef),
              transaction.get(claimRef),
              transaction.get(refundRef),
            ]);
            if (!userDoc.exists || !claimDoc.exists || refundDoc.exists) {
              throw new Error('The redemption cannot be refunded from its current state.');
            }
            const cost = finiteInteger(redemption.cost, 'Redemption cost', 1, 1_000_000);
            const balance = finiteInteger(
              userDoc.data()?.loyaltyPoints,
              'Loyalty balance',
              0,
              1_000_000_000,
            );
            const claimCount = finiteInteger(
              claimDoc.data()?.claimCount,
              'Reward claim count',
              1,
              100,
            );
            const finiteStock = redemption.stockRemaining != null;
            if (finiteStock && !rewardDoc.exists) {
              throw new Error('The finite-stock reward is missing and cannot be restored.');
            }
            const stock = finiteStock
              ? finiteInteger(rewardDoc.data()?.stock, 'Reward stock', 0, 1_000_000)
              : null;
            const refund = calculateLoyaltyRefund({ balance, cost, stock, claimCount });
            transaction.update(userRef, {
              loyaltyPoints: refund.balance,
              updatedAt: changedAt,
            });
            transaction.update(claimRef, {
              claimCount: refund.claimCount,
              updatedAt: changedAt,
            });
            if (refund.stock !== null) {
              transaction.update(rewardRef, { stock: refund.stock, updatedAt: changedAt });
            }
            transaction.create(refundRef, {
              userId,
              rewardId,
              redemptionId,
              type: 'redemptionRefund',
              delta: cost,
              balanceAfter: refund.balance,
              reason: note,
              adminId: request.user!.firebaseUid,
              createdAt: changedAt,
            });
            Object.assign(update, {
              cancelledAt: changedAt,
              cancelledBy: request.user!.firebaseUid,
              cancellationReason: note,
              refunded: true,
              refundedAt: changedAt,
              refundTransactionId: refundRef.id,
              remainingBalanceAfterRefund: refund.balance,
              stockRestored: refund.stock !== null,
              claimCountAfterRefund: refund.claimCount,
            });
            refunded = true;
          } else if (status === 'fulfilled') {
            update.fulfilledAt = changedAt;
            update.fulfilledBy = request.user!.firebaseUid;
          } else if (status === 'contacted') {
            update.contactedAt = changedAt;
            update.contactedBy = request.user!.firebaseUid;
          } else {
            update.pendingAt = changedAt;
            update.pendingBy = request.user!.firebaseUid;
          }
          transaction.update(redemptionRef, update);
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Redemption update failed.';
        const clientError =
          message === 'Redemption not found.' ||
          message.includes('cannot') ||
          message.includes('invalid') ||
          message.includes('missing');
        if (clientError) {
          return reply.status(message === 'Redemption not found.' ? 404 : 409).send({
            error: 'RedemptionUpdateError',
            message,
          });
        }
        fastify.log.error({ err: error }, 'Could not update loyalty redemption');
        return reply.status(503).send({
          error: 'RedemptionsUnavailable',
          message: 'Redemption storage is temporarily unavailable.',
        });
      }
      await audit(
        request.user!.id,
        'redemptions.status_update',
        'redemption',
        redemptionId,
        { previousStatus, status, note, refunded },
      );
      return { success: true, id: redemptionId, status, refunded };
    },
  );
}
