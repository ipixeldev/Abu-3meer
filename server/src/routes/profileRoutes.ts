import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import {
  authenticateUser,
  requireRecentFirebaseAuthentication,
} from '../middleware/auth.js';
import { query } from '../db/pool.js';
import { deleteAccountData } from '../services/accountDeletionService.js';
import { deleteFirebaseMirrorData } from '../services/firebaseMirrorDeletionService.js';
import {
  eligibleLeaderboardSourceTypes,
  listLeaderboardSeasons,
} from '../services/leaderboardService.js';

const eligibleXpSources = [...eligibleLeaderboardSourceTypes];

interface PublicFanProfileRow {
  username: string;
  display_name: string;
  avatar_url: string | null;
  supported_team: string;
  supported_team_logo: string | null;
  country: string | null;
  country_code: string | null;
  is_youtube_member: boolean;
  total_points: string | number;
  monthly_points: string | number;
  season_points: string | number;
  loyalty_points: string | number;
  streak_count: string | number;
  streak_best: string | number;
  level: string | number;
  exact_predictions_count: string | number;
  challenges_completed_count: string | number;
  player_cards_collected_count: string | number;
}

export function mapPublicFanProfile(row: PublicFanProfileRow) {
  const publicId = row.username;
  return {
    // `id` remains for released clients, but now contains the public username
    // handle rather than the internal PostgreSQL UUID.
    id: publicId,
    publicId,
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
}

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
    await listLeaderboardSeasons();
    const profileRes = await query(
      `SELECT COALESCE(xp.total_points, 0)::integer AS total_points,
              COALESCE(xp.monthly_points, 0)::integer AS monthly_points,
              COALESCE(xp.season_points, 0)::integer AS season_points,
              0::integer AS loyalty_points,
              CASE
                WHEN profile.streak_last_checkin IS NOT NULL
                 AND CURRENT_TIMESTAMP >= profile.streak_last_checkin + INTERVAL '24 hours'
                THEN 0
                ELSE profile.streak_count
              END::integer AS streak_count,
              profile.streak_best,
              profile.streak_last_checkin,
              profile.streak_last_checkin + INTERVAL '24 hours' AS streak_expires_at,
              (
                profile.streak_last_checkin IS NOT NULL
                AND CURRENT_TIMESTAMP >= profile.streak_last_checkin + INTERVAL '24 hours'
              ) AS streak_expired,
              profile.level,
              profile.exact_predictions_count,
              profile.challenges_completed_count,
              profile.player_cards_collected_count,
              profile.is_guest
       FROM user_profiles profile
       LEFT JOIN LATERAL (
         SELECT COALESCE(SUM(pt.final_points), 0) AS total_points,
                COALESCE(SUM(pt.final_points) FILTER (
                  WHERE pt.created_at >= (
                    date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                    AT TIME ZONE 'UTC'
                  )
                ), 0) AS monthly_points,
                COALESCE(SUM(pt.final_points) FILTER (
                  WHERE pt.created_at >= season.starts_at
                    AND (season.ends_at IS NULL OR pt.created_at < season.ends_at)
                ), 0) AS season_points
         FROM point_transactions pt
         LEFT JOIN LATERAL (
           SELECT starts_at, ends_at
           FROM leaderboard_periods
           WHERE type = 'season' AND is_current = TRUE
           LIMIT 1
         ) season ON TRUE
         WHERE pt.user_id = profile.user_id
           AND pt.source_type = ANY($2::varchar[])
       ) xp ON TRUE
       WHERE profile.user_id = $1`,
      [user.id, eligibleXpSources]
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
    await listLeaderboardSeasons();
    const res = await query(
      `SELECT u.username, u.display_name, u.avatar_url,
              u.supported_team, u.supported_team_logo, u.country, u.country_code,
              (yl.is_member = TRUE) AS is_youtube_member,
              COALESCE(xp.total_points, 0)::integer AS total_points,
              COALESCE(xp.monthly_points, 0)::integer AS monthly_points,
              COALESCE(xp.season_points, 0)::integer AS season_points,
              0::integer AS loyalty_points,
              CASE
                WHEN p.streak_last_checkin IS NOT NULL
                 AND CURRENT_TIMESTAMP >= p.streak_last_checkin + INTERVAL '24 hours'
                THEN 0
                ELSE p.streak_count
              END::integer AS streak_count,
              p.streak_best,
              p.level, p.exact_predictions_count,
              p.challenges_completed_count, p.player_cards_collected_count
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
       LEFT JOIN LATERAL (
         SELECT COALESCE(SUM(pt.final_points), 0) AS total_points,
                COALESCE(SUM(pt.final_points) FILTER (
                  WHERE pt.created_at >= (
                    date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                    AT TIME ZONE 'UTC'
                  )
                ), 0) AS monthly_points,
                COALESCE(SUM(pt.final_points) FILTER (
                  WHERE pt.created_at >= season.starts_at
                    AND (season.ends_at IS NULL OR pt.created_at < season.ends_at)
                ), 0) AS season_points
         FROM point_transactions pt
         LEFT JOIN LATERAL (
           SELECT starts_at, ends_at
           FROM leaderboard_periods
           WHERE type = 'season' AND is_current = TRUE
           LIMIT 1
         ) season ON TRUE
         WHERE pt.user_id = p.user_id
           AND pt.source_type = ANY($2::varchar[])
       ) xp ON TRUE
       WHERE u.id::text = $1 OR u.firebase_uid = $1 OR LOWER(u.username) = LOWER($1)
       LIMIT 1`,
      [id, eligibleXpSources]
    );

    if (res.rows.length === 0) {
      return reply.status(404).send({ error: 'NotFound', message: 'Fan profile not found' });
    }

    return mapPublicFanProfile(res.rows[0] as PublicFanProfileRow);
  });

  // GET /api/v1/profile/point-history - Fetch user's verified point ledger history
  fastify.get('/profile/point-history', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const res = await query(
      `SELECT id, source_type, base_points, multiplier, final_points, description, created_at
       FROM point_transactions
       WHERE user_id = $1
         AND source_type = ANY($2::varchar[])
       ORDER BY created_at DESC
       LIMIT 50`,
      [
        user.id,
        eligibleXpSources,
      ]
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
        isYouTubeMember: user.isYouTubeMember,
        accountStatus: row.account_status,
      },
    };
  });

  // DELETE /api/v1/profile/me - Permanently delete the signed-in fan and all
  // PostgreSQL-owned account data. User-scoped tables reference users with
  // ON DELETE CASCADE; the service wraps the complete cascade and its
  // non-identifying audit marker in one transaction.
  fastify.delete(
    '/profile/me',
    {
      preHandler: [authenticateUser, requireRecentFirebaseAuthentication],
      config: { rateLimit: { max: 5, timeWindow: '1 hour' } },
    },
    async (request, reply) => {
      // Remove legacy Firestore/Storage data first. If Firebase is unavailable,
      // PostgreSQL remains intact and the authenticated user can safely retry.
      // Firebase Auth itself is deleted by Flutter after this endpoint returns.
      await deleteFirebaseMirrorData(request.user!.firebaseUid);
      const deleted = await deleteAccountData(
        request.user!.id,
        request.id,
      );
      if (!deleted) {
        return reply.status(404).send({
          error: 'NotFound',
          message: 'Profile no longer exists.',
        });
      }
      return {
        success: true,
        message: 'Account data permanently deleted.',
        requestId: request.id,
      };
    },
  );

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

}
