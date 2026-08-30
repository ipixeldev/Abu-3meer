import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticateUser, requirePermission } from '../middleware/auth.js';
import { query } from '../db/pool.js';

const updateProfileSchema = z.object({
  displayName: z.string().trim().min(2).max(50).optional(),
  username: z.string().trim().min(3).max(30).regex(/^[a-zA-Z0-9_]+$/).optional(),
  avatarUrl: z.string().url().max(500).optional().nullable(),
  country: z.string().trim().max(100).optional().nullable(),
  countryCode: z.string().trim().length(2).transform(value => value.toUpperCase()).optional().nullable(),
  supportedTeam: z.string().trim().min(2).max(100).optional(),
  supportedTeamLogo: z.string().url().max(500).optional().nullable(),
  // Completion is one-way. A client may not reset a durable account to an
  // onboarding state, and completion requires the selected identity fields in
  // the same validated request.
  onboardingCompleted: z.literal(true).optional(),
}).superRefine((value, ctx) => {
  if (!value.onboardingCompleted) return;
  const requiredFields: Array<keyof typeof value> = [
    'displayName',
    'username',
    'country',
    'supportedTeam',
  ];
  for (const field of requiredFields) {
    const fieldValue = value[field];
    if (typeof fieldValue !== 'string' || fieldValue.trim().length === 0) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: [field],
        message: `${field} is required to complete onboarding.`,
      });
    }
  }
});

export async function profileRoutes(fastify: FastifyInstance) {
  // GET /api/v1/profile/me - Fetch authenticated user's own profile
  fastify.get('/profile/me', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const profileRes = await query(
      `SELECT total_points, monthly_points, season_points, loyalty_points,
              streak_count, streak_best, streak_last_checkin, level,
              exact_predictions_count, challenges_completed_count, player_cards_collected_count,
              is_guest
       FROM user_profiles
       WHERE user_id = $1`,
      [user.id]
    );

    return {
      user: {
        id: user.id,
        firebaseUid: user.firebaseUid,
        email: user.email,
        username: user.username,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        supportedTeam: user.supportedTeam,
        supportedTeamLogo: user.supportedTeamLogo,
        country: user.country,
        countryCode: user.countryCode,
        onboardingCompleted: user.onboardingCompleted,
        isYouTubeMember: user.isYouTubeMember,
        roles: user.roles,
        isAdmin: user.isAdmin,
        isSuperAdmin: user.isSuperAdmin,
        accountStatus: user.accountStatus,
      },
      profile: profileRes.rows[0] || null,
    };
  });

  // GET /api/v1/profile/:id - Fetch public fan profile (by user ID or Firebase UID)
  fastify.get('/profile/:id', async (request, reply) => {
    const { id } = request.params as { id: string };
    const res = await query(
      `SELECT u.id, u.firebase_uid, u.username, u.display_name, u.avatar_url,
              u.supported_team, u.supported_team_logo, u.country, u.country_code,
              u.is_youtube_member,
              p.total_points, p.monthly_points, p.season_points, p.loyalty_points,
              p.streak_count, p.streak_best, p.level, p.exact_predictions_count,
              p.challenges_completed_count, p.player_cards_collected_count
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       WHERE u.id::text = $1 OR u.firebase_uid = $1 OR LOWER(u.username) = LOWER($1)
       LIMIT 1`,
      [id]
    );

    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: 'Fan profile not found' });
    }

    const row = res.rows[0];
    return {
      id: row.id,
      firebaseUid: row.firebase_uid,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      supportedTeam: row.supported_team,
      supportedTeamLogo: row.supported_team_logo,
      country: row.country,
      countryCode: row.country_code,
      isYouTubeMember: row.is_youtube_member,
      totalPoints: Number(row.total_points || 0),
      monthlyPoints: Number(row.monthly_points || 0),
      seasonPoints: Number(row.season_points || 0),
      loyaltyPoints: Number(row.loyalty_points || 0),
      streakCount: Number(row.streak_count || 0),
      streakBest: Number(row.streak_best || 0),
      level: Number(row.level || 1),
      exactPredictionsCount: Number(row.exact_predictions_count || 0),
      challengesCompletedCount: Number(row.challenges_completed_count || 0),
      playerCardsCollectedCount: Number(row.player_cards_collected_count || 0),
    };
  });

  // GET /api/v1/profile/point-history - Fetch user's verified point ledger history
  fastify.get('/profile/point-history', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    let res = await query(
      `SELECT id, source_type, base_points, multiplier, final_points, description, created_at
       FROM point_transactions
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [user.id]
    );

    const signupRule = await query(
      `SELECT base_points FROM point_rules WHERE key = 'signUpBonus'`,
    );
    const signupPoints = Number(signupRule.rows[0]?.base_points || 50);
    await query(
      `INSERT INTO point_transactions
         (user_id, source_type, source_id, base_points, multiplier,
          final_points, description, idempotency_key)
       VALUES ($1, 'signup_bonus', 'signup', $2, 1.0, $2,
               'Signup bonus', $3)
       ON CONFLICT (idempotency_key) DO NOTHING`,
      [user.id, signupPoints, `signup_bonus_${user.id}`],
    );
    // Re-read so legacy accounts see their backfilled sign-up entry on this
    // very response, alongside the newly durable daily-streak transactions.
    res = await query(
      `SELECT id, source_type, base_points, multiplier, final_points, description, created_at
       FROM point_transactions
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [user.id]
    );
    return res.rows;
  });

  // PUT /api/v1/profile/me - Update user's own profile with strict allowlisting
  fastify.put('/profile/me', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const parseResult = updateProfileSchema.safeParse(request.body);

    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'ValidationError',
        message: 'Invalid profile update parameters',
        issues: parseResult.error.issues,
      });
    }

    const {
      displayName,
      username,
      avatarUrl,
      country,
      countryCode,
      supportedTeam,
      supportedTeamLogo,
      onboardingCompleted,
    } = parseResult.data;

    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (displayName !== undefined) {
      updates.push(`display_name = $${idx++}`);
      values.push(displayName);
    }
    if (username !== undefined) {
      const existing = await query(`SELECT id FROM users WHERE LOWER(username) = LOWER($1) AND id != $2`, [username, user.id]);
      if (existing.rows.length > 0) {
        return reply.status(409).send({ error: 'Conflict', message: 'Username is already taken' });
      }
      updates.push(`username = $${idx++}`);
      values.push(username);
      updates.push(`normalized_username = $${idx++}`);
      values.push(username.toLowerCase());
    }
    if (avatarUrl !== undefined) {
      updates.push(`avatar_url = $${idx++}`);
      values.push(avatarUrl);
    }
    if (country !== undefined) {
      updates.push(`country = $${idx++}`);
      values.push(country);
    }
    if (countryCode !== undefined) {
      updates.push(`country_code = $${idx++}`);
      values.push(countryCode);
    }
    if (country !== undefined || countryCode !== undefined) {
      updates.push(`location_updated_at = CURRENT_TIMESTAMP`);
    }
    if (supportedTeam !== undefined) {
      updates.push(`supported_team = $${idx++}`);
      values.push(supportedTeam);
    }
    if (supportedTeamLogo !== undefined) {
      updates.push(`supported_team_logo = $${idx++}`);
      values.push(supportedTeamLogo);
    }
    if (onboardingCompleted === true) {
      updates.push(`onboarding_completed = TRUE`);
    }

    if (updates.length === 0) {
      return reply.status(400).send({ error: 'No valid fields to update' });
    }

    updates.push(`updated_at = CURRENT_TIMESTAMP`);
    values.push(user.id);

    const updatedUserRes = await query(
      `UPDATE users
       SET ${updates.join(', ')}
       WHERE id = $${idx}
       RETURNING id, firebase_uid, email, username, display_name, avatar_url,
                 supported_team, supported_team_logo, country, country_code,
                 location_updated_at, onboarding_completed,
                 is_youtube_member, account_status`,
      values,
    );

    if (updatedUserRes.rows.length === 0) {
      return reply.status(404).send({
        error: 'NotFound',
        message: 'Profile no longer exists.',
      });
    }

    const row = updatedUserRes.rows[0];

    return {
      success: true,
      message: 'Profile updated successfully.',
      user: {
        id: row.id,
        firebaseUid: row.firebase_uid,
        email: row.email,
        username: row.username,
        displayName: row.display_name,
        avatarUrl: row.avatar_url,
        supportedTeam: row.supported_team,
        supportedTeamLogo: row.supported_team_logo,
        country: row.country,
        countryCode: row.country_code,
        onboardingCompleted: row.onboarding_completed,
        locationUpdatedAt: row.location_updated_at,
        isYouTubeMember: row.is_youtube_member,
        accountStatus: row.account_status,
      },
    };
  });

  // PUT /api/v1/profile/team - Select/update supported team
  fastify.put('/profile/team', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const schema = z.object({
      teamName: z.string().trim().min(2).max(100),
      teamLogo: z.string().url().max(500).optional().nullable(),
    });

    const parsed = schema.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ error: 'Invalid team parameters', issues: parsed.error.issues });
    }

    await query(
      `UPDATE users
       SET supported_team = $1, supported_team_logo = $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $3`,
      [parsed.data.teamName, parsed.data.teamLogo || null, user.id]
    );

    return { success: true, supportedTeam: parsed.data.teamName, supportedTeamLogo: parsed.data.teamLogo };
  });

  // Admin-only membership management: Normal users CANNOT self-promote to YouTube Member
  fastify.post(
    '/admin/users/:id/membership',
    { preHandler: [requirePermission('users.suspend')] },
    async (request, reply) => {
      const { id: identifier } = request.params as { id: string };
      const schema = z.object({
        isMember: z.boolean(),
        channelId: z.string().trim().max(100).optional(),
        reason: z.string().trim().min(3).max(200),
      });

      const parsed = schema.safeParse(request.body);
      if (!parsed.success) {
        return reply.status(400).send({ error: 'Invalid parameters', issues: parsed.error.issues });
      }

      const targetResult = await query(
        `SELECT id
         FROM users
         WHERE id::text = $1 OR firebase_uid = $1
         ORDER BY (id::text = $1) DESC
         LIMIT 1`,
        [identifier],
      );
      const id = targetResult.rows[0]?.id;
      if (!id) {
        return reply.status(404).send({ error: 'NotFound', message: 'User not found.' });
      }

      await query(
        `UPDATE users
         SET is_youtube_member = $1, youtube_channel_id = $2, youtube_member_since = CASE WHEN $1 THEN CURRENT_TIMESTAMP ELSE NULL END, updated_at = CURRENT_TIMESTAMP
         WHERE id = $3`,
        [parsed.data.isMember, parsed.data.channelId || null, id]
      );

      await query(
        `INSERT INTO admin_audit_logs (admin_user_id, action, target_entity, target_id, after_state)
         VALUES ($1, 'membership.update', 'user', $2, $3)`,
        [
          request.user!.id,
          id,
          JSON.stringify({ isMember: parsed.data.isMember, reason: parsed.data.reason }),
        ]
      );

      return { success: true, isYouTubeMember: parsed.data.isMember };
    }
  );
}
