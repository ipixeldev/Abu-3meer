import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import Fastify from 'fastify';
import {
  adminDashboardStatsPath,
  getAdminDashboardStats,
} from '../services/adminStatsService.js';
import { adminStatsRoutes } from '../routes/adminStatsRoutes.js';

describe('staff RBAC', () => {
  it('limits moderator capabilities and gives snapshot import to every staff tier', async () => {
    const migration = await readFile(
      path.resolve(process.cwd(), 'migrations/035_admin_rbac_and_dashboard.sql'),
      'utf8',
    );
    assert.match(migration, /role_id = 'moderator'/);
    assert.match(migration, /permission_id NOT IN/);
    assert.match(migration, /'membership_snapshots\.manage'/);
    assert.match(migration, /SELECT 'admin', id[\s\S]*id <> 'roles\.manage'/);
    assert.match(migration, /SELECT 'super_admin', id/);
    const moderatorAssignments = migration.match(
      /INSERT INTO role_permissions \(role_id, permission_id\) VALUES([\s\S]*?)ON CONFLICT DO NOTHING;/,
    )?.[1] ?? '';
    assert.doesNotMatch(moderatorAssignments, /admin_dashboard\.view/);
    assert.match(migration, /'admin_dashboard\.view'/);

    const membershipRoutes = await readFile(
      path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
      'utf8',
    );
    const permissionUses = membershipRoutes.match(
      /requirePermission\('membership_snapshots\.manage'\)/g,
    );
    // Moderators can read/replace the CSV snapshot. Channel ownership is now
    // proven automatically by Google, so there is no staff claim queue or
    // decision endpoint to authorize.
    assert.equal(permissionUses?.length, 2);
    assert.doesNotMatch(membershipRoutes, /claims\/:claimId\/decision/);
  });

  it('keeps role assignment restricted to super administrators', async () => {
    const routes = await readFile(
      path.resolve(process.cwd(), 'src/routes/adminRoutes.ts'),
      'utf8',
    );
    assert.match(
      routes,
      /\/admin\/users\/:id\/roles'[\s\S]{0,120}requireSuperAdmin/,
    );

    const statsRoutes = await readFile(
      path.resolve(process.cwd(), 'src/routes/adminStatsRoutes.ts'),
      'utf8',
    );
    assert.match(
      statsRoutes,
      /adminDashboardStatsPath[\s\S]{0,120}admin_dashboard\.view/,
    );
  });

  it('registers the exact versioned dashboard path before authentication', async () => {
    const index = await readFile(
      path.resolve(process.cwd(), 'src/index.ts'),
      'utf8',
    );
    assert.match(index, /await v1\.register\(adminStatsRoutes\)/);
    assert.match(index, /prefix: '\/api\/v1'/);

    const app = Fastify({ logger: false });
    await app.register(
      async (v1) => {
        await v1.register(adminStatsRoutes);
      },
      { prefix: '/api/v1' },
    );
    await app.ready();
    try {
      const response = await app.inject({
        method: 'GET',
        url: `/api/v1${adminDashboardStatsPath}`,
      });
      // An unauthenticated request must reach the RBAC pre-handler. A 404 here
      // means the production plugin/prefix wiring regressed.
      assert.equal(response.statusCode, 401);
      assert.equal(response.json().error, 'Unauthorized');

      const oldOrInventedPath = await app.inject({
        method: 'GET',
        url: '/api/v1/admin/statistics',
      });
      assert.equal(oldOrInventedPath.statusCode, 404);
    } finally {
      await app.close();
    }
  });
});

describe('admin dashboard statistics', () => {
  it('maps aggregate counts and documents the 30-day active-user definition', async () => {
    let sql = '';
    const stats = await getAdminDashboardStats(async (statement) => {
      sql = statement;
      return {
        rows: [{
          total_users: '120',
          active_accounts: '115',
          active_users_24h: '10',
          active_users_7d: '40',
          active_users_30d: '88',
          new_users_30d: '17',
          suspended_users: '3',
          banned_users: '2',
          fans: '120',
          members: '31',
          moderators: '2',
          admins: '4',
          super_admins: '1',
          linked_youtube_channels: '44',
          active_memberships: '31',
          predictions: '901',
          challenge_submissions: '411',
          correct_challenge_submissions: '302',
          matches: '42',
          challenges: '16',
          exclusive_videos: '8',
        }],
      };
    });

    assert.match(sql, /last_active_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'/);
    assert.match(sql, /role_flags[\s\S]*NOT is_member[\s\S]*AS fans/);
    assert.match(sql, /verification_source = 'admin_snapshot'/);
    assert.match(sql, /snapshot_import_id = snapshot_state\.active_import_id/);
    assert.match(sql, /snapshot_import\.expires_at > CURRENT_TIMESTAMP/);
    assert.match(sql, /approved_claim\.status = 'approved'/);
    assert.match(sql, /youtube_membership_snapshot_members[\s\S]*status = 'active'/);
    assert.match(
      sql,
      /FROM videos[\s\S]*is_unlisted = TRUE OR member_only = TRUE/,
    );
    assert.doesNotMatch(sql, /FROM exclusive_videos/);
    assert.equal(stats.activeUserDefinition.primaryWindowDays, 30);
    assert.equal(stats.users.total, 120);
    assert.equal(stats.users.active30d, 88);
    assert.equal(stats.totalUsers, 120);
    assert.equal(stats.activeUsers, 88);
    assert.equal(stats.activeUsersToday, 10);
    assert.equal(stats.activeToday, 10);
    assert.equal(stats.linkedYouTubeChannels, 44);
    assert.equal(stats.activeMemberships, 31);
    assert.equal(stats.roles.members, 31);
    assert.equal(stats.engagement.predictions, 901);
    assert.equal(stats.content.exclusiveVideos, 8);
    assert.deepEqual(
      Object.keys(stats).filter((key) => [
        'totalUsers',
        'activeUsers',
        'activeToday',
        'fans',
        'members',
        'moderators',
        'admins',
        'superAdmins',
        'suspendedUsers',
        'linkedYouTubeChannels',
        'activeMemberships',
      ].includes(key)).sort(),
      [
        'activeMemberships',
        'activeToday',
        'activeUsers',
        'admins',
        'fans',
        'linkedYouTubeChannels',
        'members',
        'moderators',
        'superAdmins',
        'suspendedUsers',
        'totalUsers',
      ],
    );
  });

  it('returns safe zeroes for empty or malformed aggregate results', async () => {
    const stats = await getAdminDashboardStats(async () => ({
      rows: [{ total_users: '-1', members: 'not-a-number' }],
    }));
    assert.equal(stats.users.total, 0);
    assert.equal(stats.roles.members, 0);
    assert.equal(stats.users.active30d, 0);
  });
});
