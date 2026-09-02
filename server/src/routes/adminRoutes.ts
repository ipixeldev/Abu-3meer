import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requirePermission, requireSuperAdmin } from '../middleware/auth.js';
import { getClient, query } from '../db/pool.js';
import {
  enqueueMatchSettlement,
  enqueueNotificationCampaign,
} from '../queues/workers.js';
import { notificationCategories } from '../services/notificationDomain.js';
import {
  createNotificationCampaign,
  MAX_NOTIFICATION_DELIVERY_ATTEMPTS,
} from '../services/notificationService.js';
import { config } from '../config.js';
import { redis } from '../redis/client.js';
import {
  listLeaderboardSeasons,
  saveManualLeaderboardSeason,
} from '../services/leaderboardService.js';

const manageableRoles = ['fan', 'member', 'moderator', 'admin', 'super_admin'] as const;
const adminAssignableRoles = ['fan', 'moderator', 'admin', 'super_admin'] as const;
const leaderboardSeasonBodySchema = z.object({
  displayName: z.string().trim().min(1).max(100),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  reason: z.string().trim().min(3).max(255).default('Configured from Admin Studio.'),
});
const leaderboardSeasonIdSchema = z.string()
  .trim()
  .min(1)
  .max(50)
  .regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/);

async function resolveUserId(identifier: string): Promise<string | null> {
  const result = await query(
    `SELECT id
     FROM users
     WHERE id::text = $1 OR firebase_uid = $1
     ORDER BY (id::text = $1) DESC
     LIMIT 1`,
    [identifier],
  );
  return result.rows[0]?.id ?? null;
}

function primaryRole(roles: string[]): string {
  for (const role of ['super_admin', 'admin', 'moderator', 'member', 'fan']) {
    if (roles.includes(role)) return role;
  }
  return 'fan';
}

export async function adminRoutes(fastify: FastifyInstance) {
  // PostgreSQL is the account source of truth. Returning both the database ID
  // and Firebase UID lets migrated clients move to the stable database ID
  // without hiding users that never had a Firestore profile document.
  fastify.get('/admin/users', { preHandler: [requirePermission('users.view')] }, async (request, reply) => {
    const schema = z.object({
      search: z.string().trim().max(100).optional(),
      q: z.string().trim().max(100).optional(),
      role: z.enum(manageableRoles).optional(),
      status: z.enum(['active', 'suspended', 'banned', 'pending_deletion']).optional(),
      limit: z.coerce.number().int().min(1).max(200).default(100),
      offset: z.coerce.number().int().min(0).default(0),
    });
    const parsed = schema.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const search = parsed.data.search || parsed.data.q || null;
    const result = await query(
      `SELECT u.id, u.firebase_uid, u.email, u.username, u.display_name,
              u.avatar_url, u.country, u.country_code, u.supported_team,
              u.supported_team_logo,
              COALESCE(
                yl.is_member = TRUE
                AND yl.verification_source = 'admin_snapshot'
                AND EXISTS (
                  SELECT 1
                  FROM youtube_membership_snapshot_state snapshot_state
                  JOIN youtube_membership_snapshot_imports snapshot_import
                    ON snapshot_import.id = snapshot_state.active_import_id
                   AND snapshot_import.expires_at > CURRENT_TIMESTAMP
                  WHERE snapshot_state.singleton = TRUE
                    AND snapshot_state.active_import_id = yl.snapshot_import_id
                )
                AND EXISTS (
                  SELECT 1 FROM youtube_channel_claims claim
                  WHERE claim.user_id = u.id
                    AND claim.youtube_channel_id = yl.youtube_channel_id
                    AND claim.status = 'approved'
                ),
                FALSE
              ) AS is_youtube_member,
              yl.youtube_channel_id, yl.membership_level_id,
              yl.last_verified_at AS youtube_membership_verified_at,
              yl.last_attempted_at AS youtube_membership_last_attempted_at,
              yl.last_error_code AS youtube_membership_error_code,
              yl.member_since AS youtube_member_since,
              u.account_status,
              u.onboarding_completed, u.created_at, u.last_active_at,
              p.total_points, p.monthly_points, p.season_points,
              p.loyalty_points, p.level, p.is_guest,
              COALESCE(
                array_agg(DISTINCT ur.role_id) FILTER (WHERE ur.role_id IS NOT NULL),
                '{}'
              ) AS roles,
              COUNT(*) OVER() AS total_count
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
       LEFT JOIN user_roles ur ON ur.user_id = u.id
         AND (
           ur.role_id <> 'member'
           OR COALESCE(
             yl.is_member = TRUE
             AND yl.verification_source = 'admin_snapshot'
             AND EXISTS (
               SELECT 1
               FROM youtube_membership_snapshot_state snapshot_state
               JOIN youtube_membership_snapshot_imports snapshot_import
                 ON snapshot_import.id = snapshot_state.active_import_id
                AND snapshot_import.expires_at > CURRENT_TIMESTAMP
               WHERE snapshot_state.singleton = TRUE
                 AND snapshot_state.active_import_id = yl.snapshot_import_id
             )
             AND EXISTS (
               SELECT 1 FROM youtube_channel_claims claim
               WHERE claim.user_id = u.id
                 AND claim.youtube_channel_id = yl.youtube_channel_id
                 AND claim.status = 'approved'
             ),
             FALSE
           )
         )
       WHERE (
         $1::text IS NULL OR
         u.email ILIKE '%' || $1 || '%' OR
         u.username ILIKE '%' || $1 || '%' OR
         u.display_name ILIKE '%' || $1 || '%' OR
         u.firebase_uid = $1 OR
         u.id::text = $1
       )
       AND (
         $2::text IS NULL
         OR (
           $2 = 'member'
           AND yl.is_member = TRUE
           AND yl.verification_source = 'admin_snapshot'
           AND EXISTS (
             SELECT 1
             FROM youtube_membership_snapshot_state snapshot_state
             JOIN youtube_membership_snapshot_imports snapshot_import
               ON snapshot_import.id = snapshot_state.active_import_id
              AND snapshot_import.expires_at > CURRENT_TIMESTAMP
             WHERE snapshot_state.singleton = TRUE
               AND snapshot_state.active_import_id = yl.snapshot_import_id
           )
           AND EXISTS (
             SELECT 1 FROM youtube_channel_claims claim
             WHERE claim.user_id = u.id
               AND claim.youtube_channel_id = yl.youtube_channel_id
               AND claim.status = 'approved'
           )
         )
         OR (
           $2 <> 'member'
           AND EXISTS (
             SELECT 1 FROM user_roles filtered_role
             WHERE filtered_role.user_id = u.id
               AND filtered_role.role_id = $2
           )
         )
       )
       AND ($3::text IS NULL OR u.account_status = $3)
       GROUP BY u.id, p.user_id, yl.user_id
       ORDER BY u.created_at DESC, u.id
       LIMIT $4 OFFSET $5`,
      [
        search,
        parsed.data.role ?? null,
        parsed.data.status ?? null,
        parsed.data.limit,
        parsed.data.offset,
      ],
    );

    const users = result.rows.map((row) => {
      const roles = Array.isArray(row.roles) ? row.roles : [];
      return {
        id: row.id,
        uid: row.firebase_uid,
        firebaseUid: row.firebase_uid,
        email: row.email,
        username: row.username,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        country: row.country,
        countryCode: row.country_code,
        supportedTeam: row.supported_team,
        supportedTeamLogo: row.supported_team_logo,
        isYouTubeMember: row.is_youtube_member,
        youtubeChannelLinked: Boolean(row.youtube_channel_id),
        youtubeChannelId: row.youtube_channel_id ?? null,
        youtubeMembershipLevelId: row.membership_level_id ?? null,
        youtubeMembershipVerifiedAt: row.youtube_membership_verified_at ?? null,
        youtubeMembershipLastAttemptedAt:
          row.youtube_membership_last_attempted_at ?? null,
        youtubeMembershipErrorCode: row.youtube_membership_error_code ?? null,
        youtubeMemberSince: row.youtube_member_since ?? null,
        accountStatus: row.account_status,
        suspended: row.account_status === 'suspended' || row.account_status === 'banned',
        onboardingCompleted: row.onboarding_completed,
        roles,
        role: primaryRole(roles),
        totalPoints: Number(row.total_points || 0),
        monthlyPoints: Number(row.monthly_points || 0),
        seasonPoints: Number(row.season_points || 0),
        loyaltyPoints: Number(row.loyalty_points || 0),
        level: Number(row.level || 1),
        isGuest: row.is_guest,
        createdAt: row.created_at,
        lastActiveAt: row.last_active_at,
      };
    });
    const total = Number(result.rows[0]?.total_count || 0);
    return {
      users,
      total,
      limit: parsed.data.limit,
      offset: parsed.data.offset,
      hasMore: parsed.data.offset + users.length < total,
    };
  });

  fastify.get(
    '/admin/leaderboard-seasons',
    { preHandler: [requirePermission('leaderboards.manage')] },
    async () => {
      const seasons = await listLeaderboardSeasons();
      return {
        seasons,
        activeSeasonId: seasons.find(season => season.active)?.id ?? null,
      };
    },
  );

  fastify.post(
    '/admin/leaderboard-seasons',
    { preHandler: [requirePermission('leaderboards.manage')] },
    async (request, reply) => {
      const parsed = leaderboardSeasonBodySchema.extend({
        id: leaderboardSeasonIdSchema,
      }).safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the season name and dates, then try again.',
          issues: parsed.error.issues,
        });
      }
      const season = await saveManualLeaderboardSeason(
        parsed.data,
        request.user!.id,
      );
      return reply.status(201).send({ success: true, season });
    },
  );

  fastify.put(
    '/admin/leaderboard-seasons/:id',
    { preHandler: [requirePermission('leaderboards.manage')] },
    async (request, reply) => {
      const id = leaderboardSeasonIdSchema.safeParse(
        (request.params as { id?: string }).id,
      );
      const body = leaderboardSeasonBodySchema.safeParse(request.body);
      if (!id.success || !body.success) {
        return reply.status(400).send({
          error: 'ValidationError',
          message: 'Check the season name and dates, then try again.',
          issues: [
            ...(!id.success ? id.error.issues : []),
            ...(!body.success ? body.error.issues : []),
          ],
        });
      }
      const season = await saveManualLeaderboardSeason(
        { id: id.data, ...body.data },
        request.user!.id,
        id.data,
      );
      return { success: true, season };
    },
  );

  // 1. Matches & Settlement (Permission: matches.manage)
  // Admin Studio needs terminal and locked rows too. The public upcoming feed
  // intentionally excludes those statuses and must not be reused here.
  fastify.get('/admin/matches', { preHandler: [requirePermission('matches.manage')] }, async () => {
    const result = await query(
      `SELECT *
       FROM matches
       WHERE kickoff_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
          OR status IN ('scheduled', 'open', 'closed', 'live', 'postponed')
       ORDER BY (kickoff_at < CURRENT_TIMESTAMP) ASC,
                CASE WHEN kickoff_at >= CURRENT_TIMESTAMP THEN kickoff_at END ASC,
                kickoff_at DESC
       LIMIT 200`,
    );
    return result.rows;
  });

  fastify.post('/admin/matches', { preHandler: [requirePermission('matches.manage')] }, async (request, reply) => {
    const schema = z.object({
      id: z.string().trim().min(1).max(100),
      competitionName: z.string().trim().min(1).max(150).default('La Liga'),
      homeTeam: z.string().trim().min(1).max(150),
      awayTeam: z.string().trim().min(1).max(150),
      homeLogoUrl: z.string().url().max(500).optional().nullable(),
      awayLogoUrl: z.string().url().max(500).optional().nullable(),
      kickoffAt: z.string().datetime(),
      predictionsOpenAt: z.string().datetime(),
      predictionsCloseAt: z.string().datetime(),
      firstScorerOptions: z.array(z.string()).default([]),
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const b = parsed.data;
    const res = await query(
      `INSERT INTO matches (id, competition_name, home_team, away_team, home_logo_url, away_logo_url, kickoff_at, predictions_open_at, predictions_close_at, first_scorer_options)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (id) DO UPDATE SET
         competition_name = EXCLUDED.competition_name,
         home_team = EXCLUDED.home_team,
         away_team = EXCLUDED.away_team,
         home_logo_url = EXCLUDED.home_logo_url,
         away_logo_url = EXCLUDED.away_logo_url,
         kickoff_at = EXCLUDED.kickoff_at,
         predictions_open_at = EXCLUDED.predictions_open_at,
         predictions_close_at = EXCLUDED.predictions_close_at,
         first_scorer_options = EXCLUDED.first_scorer_options,
         updated_at = CURRENT_TIMESTAMP
       WHERE matches.status <> 'finished'
         AND matches.reward_processed = false
       RETURNING *`,
      [
        b.id,
        b.competitionName,
        b.homeTeam,
        b.awayTeam,
        b.homeLogoUrl || null,
        b.awayLogoUrl || null,
        new Date(b.kickoffAt),
        new Date(b.predictionsOpenAt),
        new Date(b.predictionsCloseAt),
        JSON.stringify(b.firstScorerOptions),
      ]
    );
    if (res.rowCount === 0) {
      return reply.status(409).send({
        error: 'MatchAlreadySettled',
        message: 'A settled match cannot be edited without an audited reward reversal.',
      });
    }

    // Audit log
    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'matches.upsert', 'match', $2, $3)`,
      [request.user!.id, b.id, JSON.stringify(res.rows[0])]
    );

    await redis.del('cache:matches:upcoming').catch(() => undefined);
    return { success: true, match: res.rows[0] };
  });

  fastify.post('/admin/matches/:id/settle', { preHandler: [requirePermission('matches.manage')] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const schema = z.object({
      homeScore: z.number().int().min(0).max(30),
      awayScore: z.number().int().min(0).max(30),
      firstScorer: z.string().trim().min(1).max(150).default('No scorer'),
    }).refine(
      value =>
        (value.homeScore === 0 && value.awayScore === 0) ||
        value.firstScorer.toLowerCase() !== 'no scorer',
      {
        path: ['firstScorer'],
        message: 'First scorer is required for a match with goals.',
      },
    );

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const { homeScore, awayScore, firstScorer } = parsed.data;

    const updated = await query(
      `UPDATE matches
       SET home_score = $1, away_score = $2, first_scorer = $3, status = 'finished', updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
         AND status <> 'finished'
         AND status NOT IN ('cancelled', 'postponed')
         AND reward_processed = false
       RETURNING id`,
      [homeScore, awayScore, firstScorer, id]
    );
    if (updated.rowCount === 0) {
      const existing = await query<{ status: string; reward_processed: boolean }>(
        `SELECT status, reward_processed
         FROM matches
         WHERE id = $1`,
        [id],
      );
      if (existing.rowCount === 0) {
        return reply.status(404).send({ error: 'NotFound', message: 'Match not found.' });
      }
      if (['cancelled', 'postponed'].includes(existing.rows[0].status)) {
        return reply.status(409).send({
          error: 'MatchUnavailable',
          message: 'Reopen this disabled match before publishing a result.',
        });
      }
      return reply.status(409).send({
        error: 'MatchAlreadySettled',
        message: 'This result is already final. Settled scores cannot be changed without an audited reward reversal.',
      });
    }

    // Audit log
    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'matches.settle', 'match', $2, $3)`,
      [request.user!.id, id, JSON.stringify({ homeScore, awayScore, firstScorer })]
    );

    // Queue settlement worker
    await enqueueMatchSettlement(id);
    await redis.del(
      'cache:matches:upcoming',
      `cache:matches:v3:${id}:details`,
    ).catch(() => undefined);
    return { success: true, message: 'Match settlement job queued.' };
  });

  fastify.put('/admin/matches/:id/status', { preHandler: [requirePermission('matches.manage')] }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const parsed = z.object({
      // Terminal completion must go through /settle so an official score,
      // prediction settlement job, and audit receipt are created together.
      status: z.enum(['draft', 'open', 'locked', 'disabled']),
    }).safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }
    const databaseStatus = {
      draft: 'scheduled',
      open: 'open',
      locked: 'closed',
      disabled: 'cancelled',
    }[parsed.data.status];
    const result = await query(
      `UPDATE matches
       SET status = $2,
           predictions_open_at = CASE
             WHEN $2 = 'open' THEN LEAST(predictions_open_at, CURRENT_TIMESTAMP)
             ELSE predictions_open_at
           END,
           predictions_close_at = CASE
             WHEN $2 = 'open' THEN GREATEST(
               predictions_close_at,
               kickoff_at - INTERVAL '5 minutes'
             )
             WHEN $2 = 'closed' THEN LEAST(predictions_close_at, CURRENT_TIMESTAMP)
             ELSE predictions_close_at
           END,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1
         AND status <> 'finished'
         AND reward_processed = false
       RETURNING *`,
      [id, databaseStatus],
    );
    if (result.rowCount === 0) {
      const existing = await query<{ status: string; reward_processed: boolean }>(
        'SELECT status, reward_processed FROM matches WHERE id = $1',
        [id],
      );
      if (
        existing.rows[0]?.status === 'finished' ||
        existing.rows[0]?.reward_processed === true
      ) {
        return reply.status(409).send({
          error: 'MatchAlreadySettled',
          message: 'A settled match cannot be reopened or changed through the status control.',
        });
      }
      return reply.status(404).send({ error: 'NotFound', message: 'Match not found.' });
    }
    await query(
      `INSERT INTO admin_audit_logs
         (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'matches.status_update', 'match', $2, $3)`,
      [
        request.user!.id,
        id,
        JSON.stringify({ status: parsed.data.status, databaseStatus }),
      ],
    );
    await redis.del(
      'cache:matches:upcoming',
      `cache:matches:v3:${id}:details`,
    ).catch(() => undefined);
    return { success: true, match: result.rows[0] };
  });

  // 2. Manual Point Adjustments (Permission: points.adjust) - Requires Mandatory Reason & Audit Trail
  fastify.post('/admin/users/:id/points', { preHandler: [requirePermission('points.adjust')] }, async (request, reply) => {
    return reply.status(410).send({
      error: 'XpAdjustmentsDisabled',
      message: 'XP is earned from signup, daily login, correct predictions, and correct video-question answers; manual XP awards are disabled.',
    });
  });

  fastify.get(
    '/admin/point-adjustments',
    { preHandler: [requirePermission('points.adjust')] },
    async () => {
      const result = await query(
        `SELECT a.id, a.target_id, a.created_at, a.after_state,
                admin.firebase_uid AS admin_uid,
                admin.display_name AS admin_display_name,
                target.firebase_uid AS target_uid,
                target.display_name AS target_display_name,
                target.username AS target_username
         FROM admin_audit_logs a
         JOIN users admin ON admin.id = a.admin_user_id
         LEFT JOIN users target ON target.id::text = a.target_id
         WHERE a.action = 'points.adjust'
         ORDER BY a.created_at DESC
         LIMIT 50`,
      );
      return result.rows.map((row) => {
        const state = row.after_state || {};
        const delta = Number(state.amount || state.pointsAwarded || 0);
        const totalAfter = Number(state.totalPoints || 0);
        const monthlyAfter = Number(state.monthlyPoints || 0);
        const seasonAfter = Number(state.seasonPoints || 0);
        return {
          id: row.id,
          adminId: row.admin_uid || '',
          adminDisplayName: row.admin_display_name || '',
          targetUserId: row.target_uid || row.target_id || '',
          targetDisplayName: row.target_display_name || '',
          targetUsername: row.target_username || '',
          delta,
          reason: String(state.reason || ''),
          totalBefore: Math.max(0, totalAfter - delta),
          totalAfter,
          monthlyBefore: Math.max(0, monthlyAfter - delta),
          monthlyAfter,
          seasonBefore: Math.max(0, seasonAfter - delta),
          seasonAfter,
          periodFloorApplied: false,
          monthlyRolledOver: false,
          seasonRolledOver: false,
          monthlyPeriod: '',
          seasonId: '',
          createdAt: row.created_at,
        };
      });
    },
  );

  // 3. User Moderation (Ban / Suspend / Activate) (Permission: users.ban / users.suspend)
  fastify.post('/admin/users/:id/status', { preHandler: [requirePermission('users.suspend')] }, async (request, reply) => {
    const { id: identifier } = request.params as { id: string };
    const schema = z.object({
      status: z.enum(['active', 'suspended', 'banned']),
      reason: z.string().trim().min(5).max(255),
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const { status, reason } = parsed.data;
    const id = await resolveUserId(identifier);
    if (!id) {
      return reply.status(404).send({ error: 'NotFound', message: 'User not found.' });
    }

    // Check if banning an admin (only Super Admin can ban admins)
    const targetRolesRes = await query('SELECT role_id FROM user_roles WHERE user_id = $1', [id]);
    const targetRoles = targetRolesRes.rows.map(r => r.role_id);
    if ((targetRoles.includes('admin') || targetRoles.includes('super_admin')) && !request.user!.isSuperAdmin) {
      return reply.status(403).send({ error: 'Forbidden', message: 'Only Super Administrators can moderate admin accounts.' });
    }

    await query('UPDATE users SET account_status = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2', [status, id]);

    // Audit log
    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'user.status_update', 'user', $2, $3)`,
      [request.user!.id, id, JSON.stringify({ status, reason })]
    );

    return { success: true, status };
  });

  // 4. Role Management (SUPER_ADMIN ONLY)
  fastify.post('/admin/users/:id/roles', { preHandler: [requireSuperAdmin] }, async (request, reply) => {
    const { id: identifier } = request.params as { id: string };
    const schema = z.object({
      // `member` is exclusively derived from the verified YouTube account
      // link and cannot be granted or revoked through role administration.
      roles: z.array(z.enum(adminAssignableRoles))
        .min(1)
        .max(adminAssignableRoles.length),
      reason: z.string().trim().min(5).max(255),
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const roles = [...new Set(parsed.data.roles)];
    if (!roles.includes('fan')) roles.unshift('fan');
    const client = await getClient();
    try {
      await client.query('BEGIN');
      // Serialize role mutations so two simultaneous demotions cannot both
      // pass the final-super-admin check.
      await client.query(`SELECT pg_advisory_xact_lock(hashtext('abu3meer.role-management'))`);
      const targetRes = await client.query(
        `SELECT id, email
         FROM users
         WHERE id::text = $1 OR firebase_uid = $1
         ORDER BY (id::text = $1) DESC
         LIMIT 1
         FOR UPDATE`,
        [identifier],
      );
      if (targetRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return reply.status(404).send({ error: 'NotFound', message: 'User not found.' });
      }
      const id = targetRes.rows[0].id;
      const targetEmail = String(targetRes.rows[0].email || '').toLowerCase();
      if (targetEmail === config.adminEmails[0] && !roles.includes('super_admin')) {
        await client.query('ROLLBACK');
        return reply.status(400).send({
          error: 'SafetyError',
          message: 'The configured bootstrap Super Administrator cannot be demoted.',
        });
      }
      const existingRes = await client.query(
        'SELECT role_id FROM user_roles WHERE user_id = $1 ORDER BY role_id',
        [id],
      );
      const previousRoles = existingRes.rows.map((row) => String(row.role_id));

      if (previousRoles.includes('super_admin') && !roles.includes('super_admin')) {
        const superAdminCountRes = await client.query(
          `SELECT COUNT(*) FROM user_roles WHERE role_id = 'super_admin' AND user_id != $1`,
          [id],
        );
        if (Number(superAdminCountRes.rows[0].count) === 0) {
          await client.query('ROLLBACK');
          return reply.status(400).send({
            error: 'SafetyError',
            message: 'Cannot remove the last remaining Super Administrator.',
          });
        }
      }

      await client.query(
        `DELETE FROM user_roles
         WHERE user_id = $1 AND role_id <> 'member'`,
        [id],
      );
      await client.query(
        `INSERT INTO user_roles (user_id, role_id, assigned_by)
         SELECT $1, role_id, $3
         FROM unnest($2::varchar[]) AS role_id
         ON CONFLICT DO NOTHING`,
        [id, roles, request.user!.id],
      );
      const resultingRoles = previousRoles.includes('member')
        ? [...roles, 'member']
        : roles;
      await client.query(
        `INSERT INTO admin_audit_logs
           (admin_user_id, action, target_entity, target_id, before_state, after_state)
         VALUES ($1, 'roles.assign', 'user', $2, $3, $4)`,
        [
          request.user!.id,
          id,
          JSON.stringify({ roles: previousRoles }),
          JSON.stringify({ roles: resultingRoles, reason: parsed.data.reason }),
        ],
      );
      await client.query('COMMIT');
      return { success: true, userId: id, roles: resultingRoles };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  });

  // 5. Point Rules Configuration (Permission: settings.manage)
  fastify.put('/admin/point-rules', { preHandler: [requirePermission('settings.manage')] }, async (request, reply) => {
    const schema = z.record(z.string(), z.number().int().min(1).max(500));
    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    for (const [key, basePoints] of Object.entries(parsed.data)) {
      await query(
        `UPDATE point_rules SET base_points = $1, updated_at = CURRENT_TIMESTAMP WHERE key = $2`,
        [basePoints, key]
      );
    }

    // Audit log
    await query(
      `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
       VALUES ($1, 'point_rules.update', 'settings', 'point_rules', $2)`,
      [request.user!.id, JSON.stringify(parsed.data)]
    );

    return { success: true, updatedRules: parsed.data };
  });

  // 6. Security & Audit Logs (Permission: audit.view)
  fastify.get('/admin/audit-logs', { preHandler: [requirePermission('audit.view')] }, async (request, reply) => {
    const res = await query(
      `SELECT a.*, u.display_name as admin_name, u.email as admin_email
       FROM admin_audit_logs a
       JOIN users u ON u.id = a.admin_user_id
       ORDER BY a.created_at DESC
       LIMIT 50`
    );
    return res.rows;
  });

  fastify.get('/admin/suspicious-activity', { preHandler: [requirePermission('audit.view')] }, async (request, reply) => {
    const res = await query(
      `SELECT s.*, u.username, u.display_name, u.account_status
       FROM suspicious_activity_logs s
       LEFT JOIN users u ON u.id = s.user_id
       ORDER BY s.created_at DESC
       LIMIT 50`
    );
    return res.rows;
  });

  // 7. Notification Broadcast (Permission: notifications.send)
  fastify.post('/admin/notifications/broadcast', { preHandler: [requirePermission('notifications.send')] }, async (request, reply) => {
    const schema = z.object({
      title: z.string().trim().min(2).max(100),
      body: z.string().trim().min(2).max(500),
      idempotencyKey: z.string().trim().min(16).max(128)
        .regex(/^[A-Za-z0-9:_-]+$/),
      data: z.record(z.string(), z.string()).optional(),
      category: z.enum(notificationCategories).default('general'),
      targetAudience: z.enum(['all', 'members_only', 'team_specific', 'inactive_users']).default('all'),
      targetTeam: z.string().trim().min(2).max(100).optional(),
      imageUrl: z.string().url().max(1000).refine(
        value => value.startsWith('https://'),
        'Notification images must use HTTPS.'
      ).optional(),
      scheduledAt: z.string().datetime().optional(),
    }).superRefine((value, ctx) => {
      if (value.targetAudience === 'team_specific' && !value.targetTeam) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['targetTeam'],
          message: 'targetTeam is required for a team_specific notification.',
        });
      }
      if (value.scheduledAt) {
        const scheduledAt = new Date(value.scheduledAt);
        const maximum = Date.now() + 366 * 24 * 60 * 60 * 1000;
        if (scheduledAt.getTime() > maximum) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['scheduledAt'],
            message: 'Notifications can be scheduled up to one year ahead.',
          });
        }
      }
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'ValidationError', issues: parsed.error.issues });
    }

    const scheduledFor = parsed.data.scheduledAt
      ? new Date(parsed.data.scheduledAt)
      : new Date();
    const sourceType = 'admin_broadcast';
    const sourceId = `${request.user!.id}:${parsed.data.idempotencyKey}`;
    const client = await getClient();
    let campaignId = '';
    let persistedScheduledFor = scheduledFor;
    let persistedStatus = 'pending';
    let persistedAttemptCount = 0;
    try {
      await client.query('BEGIN');
      const campaign = await createNotificationCampaign(
        {
          title: parsed.data.title,
          body: parsed.data.body,
          targetAudience: parsed.data.targetAudience,
          targetTeam: parsed.data.targetTeam,
          category: parsed.data.category,
          data: parsed.data.data,
          imageUrl: parsed.data.imageUrl,
          scheduledFor,
          createdBy: request.user!.id,
          sourceType,
          sourceId,
        },
        (text, params) => client.query(text, params),
        { rearmCancelled: false },
      );
      const existing = await client.query(
        `SELECT id, scheduled_for, status, attempt_count
         FROM notification_campaigns
         WHERE source_type = $1 AND source_id = $2
         FOR UPDATE`,
        [sourceType, sourceId],
      );
      if (existing.rowCount === 0) {
        throw new Error('The idempotent notification campaign could not be persisted.');
      }
      campaignId = String(existing.rows[0].id);
      persistedScheduledFor = new Date(existing.rows[0].scheduled_for);
      persistedStatus = String(existing.rows[0].status);
      persistedAttemptCount = Number(existing.rows[0].attempt_count ?? 0);

      // Only the transaction that inserted the logical campaign writes its
      // audit event. Replaying the client key returns the original campaign.
      if (campaign.created) {
        await client.query(
          `INSERT INTO admin_audit_logs
             (admin_user_id, action, target_entity, target_id, after_state)
           VALUES ($1, 'notifications.broadcast', 'campaign', $2, $3)`,
          [
            request.user!.id,
            campaignId,
            JSON.stringify({ campaignId, ...parsed.data }),
          ],
        );
      }
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }

    let notificationQueued = false;
    const shouldQueue =
      (persistedStatus === 'pending' || persistedStatus === 'failed') &&
      persistedAttemptCount < MAX_NOTIFICATION_DELIVERY_ATTEMPTS;
    if (shouldQueue) {
      try {
        await enqueueNotificationCampaign(campaignId, persistedScheduledFor);
        notificationQueued = true;
      } catch (error) {
        fastify.log.error(
          { err: error, campaignId },
          'Broadcast notification left pending for outbox recovery',
        );
      }
    }

    const replayedPersistedStatus =
      ['completed', 'cancelled', 'processing'].includes(persistedStatus) ||
      (persistedStatus === 'failed' &&
        persistedAttemptCount >= MAX_NOTIFICATION_DELIVERY_ATTEMPTS);

    return {
      success: true,
      campaignId,
      scheduledAt: persistedScheduledFor.toISOString(),
      status: replayedPersistedStatus
        ? persistedStatus
        : !notificationQueued
        ? 'pending_recovery'
        : persistedScheduledFor.getTime() > Date.now() + 1000
          ? 'scheduled'
          : 'queued',
      message: replayedPersistedStatus
        ? `Broadcast already ${persistedStatus}.`
        : !notificationQueued
        ? 'Broadcast saved and awaiting queue recovery.'
        : persistedScheduledFor.getTime() > Date.now() + 1000
        ? 'Broadcast notification scheduled.'
        : 'Broadcast notification queued.',
    };
  });
}
