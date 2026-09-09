import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import {
  blockUser,
  isSelfModerationTarget,
  listBlockedUsers,
  listUserReports,
  mutualBlockVisibilitySql,
  reportUser,
  resolveUserReport,
  unblockUser,
} from '../services/userModerationService.js';
import {
  userReportBodySchema,
  userReportReasons,
} from '../routes/userModerationRoutes.js';

const viewer = {
  id: '11111111-1111-4111-8111-111111111111',
  firebaseUid: 'firebase-viewer',
  username: 'Viewer_Name',
};
const targetId = '22222222-2222-4222-8222-222222222222';
const now = new Date('2026-09-09T10:00:00.000Z');

describe('user report and block validation', () => {
  it('normalizes a bounded reason code and rejects unknown fields or prose', () => {
    const valid = userReportBodySchema.parse({
      reason: ' Harassment ',
      details: 'Repeated unwanted contact.',
    });
    assert.deepEqual(valid, {
      reason: 'harassment',
      details: 'Repeated unwanted contact.',
    });
    assert.equal(
      userReportBodySchema.safeParse({ reason: 'not okay!' }).success,
      false,
    );
    assert.deepEqual([...userReportReasons], [
      'inappropriate_content',
      'harassment',
      'hate_speech',
      'impersonation',
      'spam',
      'other',
    ]);
    for (const legacyOrInvented of [
      'sexual_content',
      'violence',
      'inappropriate_profile',
    ]) {
      assert.equal(
        userReportBodySchema.safeParse({ reason: legacyOrInvented }).success,
        false,
      );
    }
    assert.equal(
      userReportBodySchema.safeParse({ reason: 'spam', admin: true }).success,
      false,
    );
    assert.equal(
      userReportBodySchema.safeParse({
        reason: 'spam',
        details: 'x'.repeat(1001),
      }).success,
      false,
    );
  });

  it('recognizes every supported identifier for the authenticated account', () => {
    assert.equal(isSelfModerationTarget(viewer.id, viewer), true);
    assert.equal(isSelfModerationTarget(viewer.firebaseUid, viewer), true);
    assert.equal(isSelfModerationTarget('viewer_name', viewer), true);
    assert.equal(isSelfModerationTarget('another_fan', viewer), false);
  });

  it('builds a mutual relationship predicate without interpolating user input', () => {
    const sql = mutualBlockVisibilitySql('u.id', '$4');
    assert.match(sql, /blocker_user_id = \$4::uuid/);
    assert.match(sql, /blocked_user_id = u\.id/);
    assert.match(sql, /blocker_user_id = u\.id/);
    assert.match(sql, /blocked_user_id = \$4::uuid/);
  });
});

describe('user moderation persistence', () => {
  it('upserts one open report per pair and returns no internal target ID', async () => {
    let sql = '';
    let params: any[] | undefined;
    const report = await reportUser(
      viewer.id,
      'reported_fan',
      { reason: 'harassment', details: '  details  ' },
      async (statement, values) => {
        sql = statement;
        params = values;
        return { rows: [{
          id: '33333333-3333-4333-8333-333333333333',
          username: 'reported_fan',
          display_name: 'Reported Fan',
          avatar_url: 'https://uploads.example/reported-photo.png',
          reason: 'harassment',
          details: 'details',
          status: 'open',
          created_at: now,
          updated_at: now,
        }] };
      },
    );

    assert.match(
      sql,
      /ON CONFLICT \(reporter_user_id, reported_user_id\)[\s\S]*WHERE status = 'open'/,
    );
    assert.match(sql, /updated_at = CURRENT_TIMESTAMP/);
    assert.deepEqual(params, [viewer.id, 'reported_fan', 'harassment', 'details']);
    assert.equal(report.target.publicId, 'reported_fan');
    assert.equal(report.target.avatarUrl, null);
    assert.equal('id' in report.target, false);
  });

  it('makes block and unblock retries converge on one relationship state', async () => {
    let blockSql = '';
    const blocked = await blockUser(viewer.id, 'target', async statement => {
      blockSql = statement;
      return { rows: [{
        username: 'target',
        display_name: 'Target',
        avatar_url: null,
        blocked_at: now,
      }] };
    });
    assert.match(blockSql, /ON CONFLICT \(blocker_user_id, blocked_user_id\)/);
    assert.equal(blocked.blockedAt, now.toISOString());

    const first = await unblockUser(viewer.id, 'target', async statement => {
      assert.match(statement, /EXISTS \(SELECT 1 FROM removed\) AS removed/);
      return { rows: [{
        username: 'target',
        display_name: 'Target',
        avatar_url: null,
        removed: true,
      }] };
    });
    const retry = await unblockUser(viewer.id, 'target', async () => ({
      rows: [{
        username: 'target',
        display_name: 'Target',
        avatar_url: null,
        removed: false,
      }],
    }));
    assert.equal(first.removed, true);
    assert.equal(retry.removed, false);
  });

  it('lists only public fields for blocked accounts', async () => {
    const blocked = await listBlockedUsers(viewer.id, async () => ({ rows: [{
      username: 'blocked_fan',
      display_name: 'Blocked Fan',
      avatar_url: 'https://example.com/avatar.png',
      blocked_at: now,
      firebase_uid: 'must-not-leak',
      email: 'private@example.com',
    }] }));
    assert.deepEqual(blocked, [{
      publicId: 'blocked_fan',
      username: 'blocked_fan',
      displayName: 'Blocked Fan',
      avatarUrl: null,
      blockedAt: now.toISOString(),
    }]);
  });
});

describe('staff report moderation', () => {
  const reportRow = {
    id: '33333333-3333-4333-8333-333333333333',
    reason: 'spam',
    details: null,
    status: 'resolved',
    created_at: now,
    updated_at: now,
    resolved_at: now,
    resolution_note: 'Reviewed.',
    reporter_user_id: viewer.id,
    reported_user_id: targetId,
    reporter_username: 'reporter',
    reporter_display_name: 'Reporter',
    reporter_avatar_url: 'https://uploads.example/reporter-photo.png',
    reported_username: 'reported',
    reported_display_name: 'Reported',
    reported_avatar_url: 'https://uploads.example/reported-photo.png',
    resolver_username: 'moderator',
    resolver_display_name: 'Moderator',
    resolver_avatar_url: 'https://uploads.example/moderator-photo.png',
  };

  it('returns a paginated staff queue', async () => {
    const result = await listUserReports(
      { status: 'resolved', limit: 20, offset: 0 },
      async (sql, params) => {
        assert.match(sql, /WITH filtered_reports AS MATERIALIZED/);
        assert.match(sql, /SELECT COUNT\(\*\) AS total_count/);
        assert.match(sql, /LEFT JOIN report_page ON TRUE/);
        assert.deepEqual(params, ['resolved', 20, 0]);
        return { rows: [{ ...reportRow, total_count: '1' }] };
      },
    );
    assert.equal(result.total, 1);
    assert.equal(result.reports[0].target.publicId, 'reported');
    assert.equal(result.reports[0].reporter.publicId, 'reporter');
    assert.equal(result.reports[0].reportedUserId, targetId);
    assert.equal(
      result.reports[0].target.avatarUrl,
      'https://uploads.example/reported-photo.png',
    );
  });

  it('keeps the accurate total when an offset page is empty', async () => {
    const result = await listUserReports(
      { status: 'open', limit: 20, offset: 40 },
      async () => ({ rows: [{ id: null, total_count: '3' }] }),
    );
    assert.deepEqual(result.reports, []);
    assert.equal(result.total, 3);
    assert.equal(result.hasMore, false);
  });

  it('resolves and audit-logs a report in the same SQL statement', async () => {
    const result = await resolveUserReport(
      viewer.id,
      reportRow.id,
      { status: 'resolved', resolutionNote: ' Reviewed. ' },
      async (sql, params) => {
        assert.match(sql, /WITH previous AS MATERIALIZED/);
        assert.match(sql, /INSERT INTO admin_audit_logs/);
        assert.match(sql, /'user_report\.resolve'/);
        assert.deepEqual(params, [
          reportRow.id,
          'resolved',
          'Reviewed.',
          viewer.id,
        ]);
        return { rows: [reportRow] };
      },
    );
    assert.equal(result.status, 'resolved');
    assert.equal(result.resolvedBy?.publicId, 'moderator');
  });

  it('wires authenticated routes, staff permissions, schema, and visibility', async () => {
    const [migration, index, routes, admin, profile, leaderboard] =
      await Promise.all([
        readFile(path.resolve(process.cwd(), 'migrations/045_user_moderation.sql'), 'utf8'),
        readFile(path.resolve(process.cwd(), 'src/index.ts'), 'utf8'),
        readFile(path.resolve(process.cwd(), 'src/routes/userModerationRoutes.ts'), 'utf8'),
        readFile(path.resolve(process.cwd(), 'src/routes/adminRoutes.ts'), 'utf8'),
        readFile(path.resolve(process.cwd(), 'src/routes/profileRoutes.ts'), 'utf8'),
        readFile(path.resolve(process.cwd(), 'src/services/leaderboardService.ts'), 'utf8'),
      ]);
    assert.match(migration, /CONSTRAINT user_blocks_not_self/);
    assert.match(migration, /CREATE UNIQUE INDEX[\s\S]*WHERE status = 'open'/);
    for (const reason of userReportReasons) {
      assert.match(migration, new RegExp(`'${reason}'`));
    }
    assert.match(index, /v1\.register\(userModerationRoutes\)/);
    assert.match(routes, /\/users\/:userId\/report/);
    assert.match(routes, /\/users\/:userId\/block/);
    assert.match(routes, /\/users\/blocked/);
    assert.match(routes, /preHandler: \[authenticateUser\]/);
    assert.match(routes, /max: 10,[\s\S]*timeWindow: '1 hour'/);
    assert.match(admin, /\/admin\/reports'[\s\S]{0,100}users\.view/);
    assert.match(admin, /Cache-Control', 'private, no-store'/);
    assert.match(admin, /\/admin\/reports\/:reportId\/resolve'[\s\S]{0,120}users\.suspend/);
    assert.match(profile, /mutualBlockVisibilitySql\('u\.id', '\$3'\)/);
    assert.match(leaderboard, /mutualBlockVisibilitySql\('u\.id', '\$4'\)/);
  });
});
