import { FastifyInstance } from 'fastify';
import { authenticateUser } from '../middleware/auth.js';
import { query } from '../db/pool.js';

export async function authRoutes(fastify: FastifyInstance) {
  fastify.post('/auth/sync', { preHandler: [authenticateUser] }, async (request, reply) => {
    const user = request.user!;
    const profileRes = await query('SELECT * FROM user_profiles WHERE user_id = $1', [user.id]);
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
        accountStatus: user.accountStatus,
        roles: user.roles,
        permissions: [...user.permissions],
        isAdmin: user.isAdmin,
        isSuperAdmin: user.isSuperAdmin,
        isGuest: user.isGuest,
      },
      profile: profileRes.rows[0],
    };
  });
}
