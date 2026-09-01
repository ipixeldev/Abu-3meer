import { FastifyRequest, FastifyReply } from 'fastify';
import { verifyFirebaseToken } from '../firebase/admin.js';
import { getClient, query } from '../db/pool.js';
import { config } from '../config.js';
import {
  awardPointsInTransaction,
  invalidatePointCaches,
  signupBonusIdempotencyKey,
} from '../services/pointsService.js';
import { redactRequestUrl } from '../security/logRedaction.js';
import { googleProviderSubjectFromFirebaseIdentities } from '../services/youtubeOAuthService.js';

export interface AuthenticatedUser {
  id: string;
  firebaseUid: string;
  email: string | null;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  supportedTeam: string;
  supportedTeamLogo: string | null;
  country: string | null;
  countryCode: string | null;
  onboardingCompleted: boolean;
  isYouTubeMember: boolean;
  accountStatus: 'active' | 'suspended' | 'banned' | 'pending_deletion';
  roles: string[];
  permissions: Set<string>;
  isAdmin: boolean;
  isSuperAdmin: boolean;
  isGuest: boolean;
  /** Google provider UID (`sub`) already linked to this Firebase account. */
  googleProviderUid: string | null;
  /** Firebase's signed-in-at time from the verified ID token (epoch seconds). */
  authTime: number;
}

declare module 'fastify' {
  interface FastifyRequest {
    user?: AuthenticatedUser;
    requestId?: string;
  }
}

export async function authenticateUser(request: FastifyRequest, reply: FastifyReply) {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return reply.status(401).send({
      error: 'Unauthorized',
      message: 'Missing or invalid Authorization header. A valid Firebase ID token is required.',
    });
  }

  const token = authHeader.split('Bearer ')[1].trim();
  if (!token) {
    return reply.status(401).send({
      error: 'Unauthorized',
      message: 'Empty Bearer token.',
    });
  }

  let decoded;
  try {
    decoded = await verifyFirebaseToken(token);
  } catch (error) {
    request.log.warn({ err: error }, 'Firebase ID token verification failed');
    return reply.status(401).send({
      error: 'Unauthorized',
      message: 'Invalid, expired, or revoked Firebase authentication token.',
    });
  }

  try {
    const firebaseUid = decoded.uid;
    const email = decoded.email || null;
    const googleProviderUid = googleProviderSubjectFromFirebaseIdentities(
      decoded.firebase?.identities,
    );
    // Lookup user in PostgreSQL
    const userLookupSql =
      `SELECT u.id, u.firebase_uid, u.email, u.username, u.display_name, u.avatar_url,
              u.supported_team, u.supported_team_logo, u.country, u.country_code,
              COALESCE(
                yl.is_member = TRUE
                AND yl.verification_source = 'admin_snapshot'
                AND yl.snapshot_import_id = (
                  SELECT active_import_id
                  FROM youtube_membership_snapshot_state
                  WHERE singleton = TRUE
                ),
                FALSE
              ) AS is_youtube_member,
              u.account_status, u.onboarding_completed,
              p.is_guest,
              COALESCE(
                array_agg(DISTINCT ur.role_id) FILTER (WHERE ur.role_id IS NOT NULL),
                '{}'
              ) as roles,
              COALESCE(
                array_agg(DISTINCT rp.permission_id) FILTER (WHERE rp.permission_id IS NOT NULL),
                '{}'
              ) as permissions
       FROM users u
       JOIN user_profiles p ON p.user_id = u.id
       LEFT JOIN youtube_account_links yl ON yl.user_id = u.id
       LEFT JOIN user_roles ur ON ur.user_id = u.id
         AND (
           ur.role_id <> 'member'
           OR COALESCE(
             yl.is_member = TRUE
             AND yl.verification_source = 'admin_snapshot'
             AND yl.snapshot_import_id = (
               SELECT active_import_id
               FROM youtube_membership_snapshot_state
               WHERE singleton = TRUE
             ),
             FALSE
           )
         )
       LEFT JOIN role_permissions rp ON rp.role_id = ur.role_id
       WHERE u.firebase_uid = $1
       GROUP BY u.id, u.firebase_uid, u.email, u.username, u.display_name, u.avatar_url,
                u.supported_team, u.supported_team_logo, u.country, u.country_code,
                yl.is_member, yl.verification_source, yl.snapshot_import_id,
                u.account_status, u.onboarding_completed,
                p.is_guest`;
    let res = await query(userLookupSql, [firebaseUid]);

    // Firebase assigns a different UID when an app is moved to another
    // Firebase project. Preserve the existing Abu 3meer account (profile,
    // points, roles, etc.) by securely re-linking a verified email address to
    // the new UID instead of attempting to insert a duplicate email row.
    if (res.rows.length === 0 && email && decoded.email_verified === true) {
      const normalizedEmail = email.trim().toLowerCase();
      const relinkedUser = await query(
        `UPDATE users
         SET firebase_uid = $1,
             email = $2,
             last_active_at = CURRENT_TIMESTAMP
         WHERE LOWER(email) = $2
           AND NOT EXISTS (
             SELECT 1
             FROM users conflicting_user
             WHERE conflicting_user.firebase_uid = $1
               AND conflicting_user.id <> users.id
           )
         RETURNING id`,
        [firebaseUid, normalizedEmail],
      );

      if (relinkedUser.rows.length > 0) {
        request.log.info(
          { userId: relinkedUser.rows[0].id },
          'Re-linked verified Firebase identity after Firebase project migration',
        );
        res = await query(userLookupSql, [firebaseUid]);
      }
    }

    if (res.rows.length === 0) {
      // Provision identity, profile, one-time signup award, and roles
      // atomically. This also repairs accounts left half-created by an
      // interrupted older build.
      const initialUsername = (email ? email.split('@')[0] : `fan_${firebaseUid.slice(0, 6)}`)
        .toLowerCase()
        .replace(/[^a-z0-9_]/g, '');
      const uniqueUsername = `${initialUsername}_${Math.floor(100 + Math.random() * 900)}`;
      const displayName = decoded.name || initialUsername;

      // Check if bootstrap super-admin or admin email
      const isSuperAdminEmail = !!(email && config.adminEmails[0] && email.toLowerCase() === config.adminEmails[0]);
      const isAdminEmail = !!(email && config.adminEmails.includes(email.toLowerCase()));

      const assignedRoles: string[] = ['fan'];
      if (isSuperAdminEmail) assignedRoles.push('super_admin');
      else if (isAdminEmail) assignedRoles.push('admin');

      const client = await getClient();
      let didAwardSignupBonus = false;
      try {
        await client.query('BEGIN');
        const newUserRes = await client.query(
          `INSERT INTO users
             (firebase_uid, email, username, normalized_username, display_name,
              avatar_url, supported_team, country, onboarding_completed)
           VALUES ($1, $2, $3, $4, $5, $6, 'Real Madrid', 'Saudi Arabia', FALSE)
           ON CONFLICT (firebase_uid) DO UPDATE SET
             email = COALESCE(users.email, EXCLUDED.email),
             avatar_url = COALESCE(users.avatar_url, EXCLUDED.avatar_url),
             last_active_at = CURRENT_TIMESTAMP
           RETURNING id`,
          [
            firebaseUid,
            email,
            uniqueUsername,
            uniqueUsername,
            displayName,
            decoded.picture || null,
          ],
        );
        const userId = newUserRes.rows[0].id;
        await client.query(
          `INSERT INTO user_profiles
             (user_id, total_points, monthly_points, season_points, loyalty_points)
           VALUES ($1, 0, 0, 0, 0)
           ON CONFLICT (user_id) DO NOTHING`,
          [userId],
        );
        const signupRule = await client.query(
          `SELECT base_points
           FROM point_rules
           WHERE key = 'signUpBonus'`,
        );
        const signupAward = await awardPointsInTransaction(client, {
          userId,
          sourceType: 'signup_bonus',
          sourceId: 'signup',
          basePoints: Number(
            signupRule.rows[0]?.base_points ?? config.pointDefaults.signUpBonus,
          ),
          multiplier: 1,
          description: 'One-time signup XP',
          idempotencyKey: signupBonusIdempotencyKey(userId),
        });
        didAwardSignupBonus =
          signupAward.alreadyAwarded !== true && signupAward.pointsAwarded > 0;
        for (const roleId of assignedRoles) {
          await client.query(
            `INSERT INTO user_roles (user_id, role_id)
             VALUES ($1, $2)
             ON CONFLICT DO NOTHING`,
            [userId, roleId],
          );
        }
        await client.query('COMMIT');
        if (didAwardSignupBonus) await invalidatePointCaches();
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }

      res = await query(userLookupSql, [firebaseUid]);
      if (res.rows.length === 0) {
        throw new Error('The new account could not be loaded after provisioning.');
      }
    }

    const row = res.rows[0];
    if (row.account_status === 'banned') {
      return reply.status(403).send({
        error: 'Forbidden',
        message: 'Your account has been permanently suspended for terms of service violations.',
      });
    }
    if (row.account_status === 'suspended') {
      return reply.status(403).send({
        error: 'Forbidden',
        message: 'Your account is currently temporarily suspended. Please contact support.',
      });
    }

    const roles: string[] = row.roles || [];
    const permissions = new Set<string>(row.permissions || []);

    // Check if configured super-admin or admin email
    const isSuperAdminEmail = !!(email && config.adminEmails[0] && email.toLowerCase() === config.adminEmails[0]);
    const isAdminEmail = !!(email && config.adminEmails.includes(email.toLowerCase()));

    // Persist configured bootstrap roles instead of only decorating the
    // current request. This keeps PostgreSQL-backed Admin Studio listings and
    // later role management consistent with the authorization decision.
    const durableRoles = ['fan'];
    if (isSuperAdminEmail) durableRoles.push('super_admin');
    else if (isAdminEmail) durableRoles.push('admin');
    const missingDurableRoles = durableRoles.filter((role) => !roles.includes(role));
    if (missingDurableRoles.length > 0) {
      await query(
        `INSERT INTO user_roles (user_id, role_id, assigned_by)
         SELECT $1, role_id, $1
         FROM unnest($2::varchar[]) AS role_id
         ON CONFLICT DO NOTHING`,
        [row.id, missingDurableRoles],
      );
      roles.push(...missingDurableRoles);
    }

    if (isSuperAdminEmail) {
      if (!roles.includes('super_admin')) roles.push('super_admin');
      const superPerms = await query(`SELECT permission_id FROM role_permissions WHERE role_id = 'super_admin'`);
      superPerms.rows.forEach(p => permissions.add(p.permission_id));
    } else if (isAdminEmail && !roles.includes('super_admin')) {
      if (!roles.includes('admin')) roles.push('admin');
      const adminPerms = await query(`SELECT permission_id FROM role_permissions WHERE role_id = 'admin'`);
      adminPerms.rows.forEach(p => permissions.add(p.permission_id));
    }

    request.user = {
      id: row.id,
      firebaseUid: row.firebase_uid,
      email: row.email,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      supportedTeam: row.supported_team || 'Real Madrid',
      supportedTeamLogo: row.supported_team_logo || null,
      country: row.country || 'Saudi Arabia',
      countryCode: row.country_code || null,
      onboardingCompleted: row.onboarding_completed === true,
      isYouTubeMember: row.is_youtube_member,
      accountStatus: row.account_status,
      roles,
      permissions,
      isAdmin: roles.includes('admin') || roles.includes('super_admin'),
      isSuperAdmin: roles.includes('super_admin'),
      isGuest: row.is_guest,
      googleProviderUid,
      authTime: decoded.auth_time,
    };
  } catch (err) {
    request.log.error({ err }, 'Authenticated database operation failed');
    return reply.status(503).send({
      error: 'PersistenceUnavailable',
      message: 'Your session is valid, but the account database is temporarily unavailable.',
      requestId: request.id,
    });
  }
}

export const SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS = 5 * 60;

/**
 * Firebase signs `auth_time` into every ID token. Destructive account actions
 * must use that value rather than the token's more recent issuance time, since
 * silently refreshing an old session must not count as reauthentication.
 */
export function hasRecentFirebaseAuthentication(
  authTime: number | undefined,
  nowEpochSeconds = Math.floor(Date.now() / 1000),
): boolean {
  if (!Number.isFinite(authTime) || !Number.isFinite(nowEpochSeconds)) return false;
  const ageSeconds = nowEpochSeconds - Number(authTime);
  return ageSeconds >= 0 && ageSeconds <= SENSITIVE_ACTION_MAX_AUTH_AGE_SECONDS;
}

export async function requireRecentFirebaseAuthentication(
  request: FastifyRequest,
  reply: FastifyReply,
) {
  const authTime = request.user?.authTime;
  if (hasRecentFirebaseAuthentication(authTime)) return;

  return reply.status(401).send({
    error: 'RecentAuthenticationRequired',
    message: 'Sign in again before permanently deleting your account.',
  });
}

/**
 * Middleware requiring specific granular permission
 */
export function requirePermission(permission: string) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    await authenticateUser(request, reply);
    if (reply.sent) return;

    const user = request.user;
    if (!user) {
      return reply.status(401).send({ error: 'Unauthorized', message: 'Authentication required' });
    }

    // Super Admin has all permissions implicitly
    if (user.isSuperAdmin || user.permissions.has(permission)) {
      return;
    }

    // Log unauthorized attempt to suspicious_activity_logs
    await query(
      `INSERT INTO suspicious_activity_logs (user_id, type, details, severity)
       VALUES ($1, 'permission_denied_attempt', $2, 'warning')`,
      [
        user.id,
        JSON.stringify({
          requiredPermission: permission,
          userRoles: user.roles,
          path: redactRequestUrl(request.url),
          method: request.method,
        }),
      ]
    ).catch(() => {});

    return reply.status(403).send({
      error: 'Forbidden',
      message: `Access denied. Required permission: ${permission}`,
    });
  };
}

export const requireAdmin = requirePermission('matches.manage');
export const requireSuperAdmin = async (request: FastifyRequest, reply: FastifyReply) => {
  await authenticateUser(request, reply);
  if (reply.sent) return;

  if (!request.user?.isSuperAdmin) {
    return reply.status(403).send({
      error: 'Forbidden',
      message: 'Super Administrator access required.',
    });
  }
};
