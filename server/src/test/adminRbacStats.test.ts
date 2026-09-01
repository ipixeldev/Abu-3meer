import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { getAdminDashboardStats } from '../services/adminStatsService.js';

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

    const membershipRoutes = await readFile(
      path.resolve(process.cwd(), 'src/routes/youtubeMembershipRoutes.ts'),
      'utf8',
    );
    const permissionUses = membershipRoutes.match(
      /requirePermission\('membership_snapshots\.manage'\)/g,
    );
    assert.equal(permissionUses?.length, 2);
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
    assert.match(
      routes,
      /\/admin\/dashboard\/stats'[\s\S]{0,120}admin_dashboard\.view/,
    );
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
    assert.match(sql, /youtube_membership_snapshot_members[\s\S]*status = 'active'/);
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
