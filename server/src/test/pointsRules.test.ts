import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import type { PoolClient } from 'pg';
import {
  adjustUserPoints,
  recordMembershipRewardCycleInTransaction,
  updatePointRuleSettings,
} from '../services/pointsService.js';
import {
  adminPointAdjustmentBodySchema,
  adminPointRuleBodySchema,
} from '../routes/adminRoutes.js';
import { syncSubscriptionStatus } from '../services/subscriptionService.js';

function membershipLedgerClient(hasMemberAccess = true) {
  let cycle: { key: string; sequence: number } | null = null;
  let totalPoints = 0;
  const ledger = new Map<string, {
    user_id: string;
    final_points: number;
    source_type: string;
  }>();
  const client = {
    query: async (text: string, values: unknown[] = []) => {
      const sql = text.replace(/\s+/g, ' ').trim();
      if (sql.startsWith('SELECT id FROM users')) {
        return { rowCount: 1, rows: [{ id: values[0] }] };
      }
      if (sql.includes('AS has_member_access')) {
        return { rowCount: 1, rows: [{ has_member_access: hasMemberAccess }] };
      }
      if (sql.startsWith('INSERT INTO membership_reward_cycles')) {
        if (cycle) return { rowCount: 0, rows: [] };
        cycle = { key: String(values[2]), sequence: Number(values[3]) };
        return { rowCount: 1, rows: [{ cycle_key: cycle.key }] };
      }
      if (sql.startsWith('SELECT base_points FROM point_rules')) {
        const points = values[0] === 'firstMembershipActivation' ? 150 : 50;
        return { rowCount: 1, rows: [{ base_points: points }] };
      }
      if (sql.startsWith('INSERT INTO point_transactions')) {
        const key = String(values[7]);
        if (ledger.has(key)) return { rowCount: 0, rows: [] };
        ledger.set(key, {
          user_id: String(values[0]),
          source_type: String(values[1]),
          final_points: Number(values[5]),
        });
        return { rowCount: 1, rows: [{ final_points: Number(values[5]) }] };
      }
      if (sql.startsWith('SELECT user_id, final_points')) {
        const row = ledger.get(String(values[0]));
        return { rowCount: row ? 1 : 0, rows: row ? [row] : [] };
      }
      if (sql.startsWith('UPDATE user_profiles')) {
        totalPoints += Number(values[0]);
        return { rowCount: 1, rows: [] };
      }
      if (sql.startsWith('SELECT cycle_key, cycle_sequence')) {
        return cycle
          ? { rowCount: 1, rows: [{ cycle_key: cycle.key, cycle_sequence: cycle.sequence }] }
          : { rowCount: 0, rows: [] };
      }
      if (sql.startsWith('UPDATE membership_reward_cycles')) {
        cycle = { key: String(values[2]), sequence: Number(values[3]) };
        return { rowCount: 1, rows: [] };
      }
      throw new Error(`Unexpected membership ledger query: ${sql}`);
    },
  } as unknown as PoolClient;
  return { client, ledger, getTotal: () => totalPoints, getCycle: () => cycle };
}

describe('published loyalty rules', () => {
  it('awards a store activation once and renews only for a newer receipt period', async () => {
    const fake = membershipLedgerClient();
    const first = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-09-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-09-01T00:00:00.000Z'),
    });
    const retry = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-09-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-09-01T00:00:00.000Z'),
    });
    const renewed = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-10-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-10-01T00:00:00.000Z'),
    });
    const renewedRetry = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-10-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-10-01T00:00:00.000Z'),
    });

    assert.deepEqual(first, {
      activationPoints: 150,
      renewalPoints: 0,
      cycleChanged: false,
    });
    assert.deepEqual(retry, {
      activationPoints: 0,
      renewalPoints: 0,
      cycleChanged: false,
    });
    assert.deepEqual(renewed, {
      activationPoints: 0,
      renewalPoints: 50,
      cycleChanged: true,
    });
    assert.deepEqual(renewedRetry, {
      activationPoints: 0,
      renewalPoints: 0,
      cycleChanged: false,
    });
    assert.equal(fake.getTotal(), 200);
    assert.deepEqual(
      [...fake.ledger.values()].map(row => row.source_type).sort(),
      ['membership_activation', 'membership_renewal'],
    );
  });

  it('renews YouTube points only when cumulative member months strictly increase', async () => {
    const fake = membershipLedgerClient();
    const first = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'youtube',
      cycleKey: 'tenure:months:8',
      cycleSequence: 8,
    });
    const replacementSnapshot = await recordMembershipRewardCycleInTransaction(
      fake.client,
      {
        userId: 'user-1',
        provider: 'youtube',
        cycleKey: 'tenure:months:8',
        cycleSequence: 8,
      },
    );
    const increasedTenure = await recordMembershipRewardCycleInTransaction(
      fake.client,
      {
        userId: 'user-1',
        provider: 'youtube',
        cycleKey: 'tenure:months:9',
        cycleSequence: 9,
      },
    );
    assert.equal(first.activationPoints, 150);
    assert.equal(replacementSnapshot.renewalPoints, 0);
    assert.equal(increasedTenure.renewalPoints, 50);
    assert.equal(fake.getTotal(), 200);
  });

  it('awards only first activation when YouTube cumulative tenure is unavailable', async () => {
    const fake = membershipLedgerClient();
    const first = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'youtube',
      cycleKey: 'tenure:unknown',
      cycleSequence: 0,
    });
    const laterSnapshot = await recordMembershipRewardCycleInTransaction(
      fake.client,
      {
        userId: 'user-1',
        provider: 'youtube',
        cycleKey: 'tenure:unknown',
        cycleSequence: 0,
      },
    );
    assert.equal(first.activationPoints, 150);
    assert.equal(first.renewalPoints, 0);
    assert.equal(laterSnapshot.activationPoints, 0);
    assert.equal(laterSnapshot.renewalPoints, 0);
    assert.equal(fake.getTotal(), 150);
  });

  it('adopts the new evidence family without manufacturing a renewal', async () => {
    const fake = membershipLedgerClient();
    await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'app_store:Ostoora3:2099-10-01T00:00:00.000Z',
      cycleSequence: Date.parse('2099-10-01T00:00:00.000Z'),
    });
    const adopted = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-09-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-09-01T00:00:00.000Z'),
    });
    const realRenewal = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'revenuecat',
      cycleKey: 'purchase:app_store:Ostoora3:2026-10-01T00:00:00.000Z',
      cycleSequence: Date.parse('2026-10-01T00:00:00.000Z'),
    });
    assert.equal(adopted.renewalPoints, 0);
    assert.equal(realRenewal.renewalPoints, 50);
    assert.equal(fake.getTotal(), 200);
  });

  it('never consumes reward state for sandbox or Test Store access', async () => {
    const expiresAt = '2099-09-14T00:00:00.000Z';
    const cycles: Array<Record<string, unknown>> = [];
    for (const store of ['app_store', 'test_store'] as const) {
      let saved: Record<string, unknown> = {};
      const status = await syncSubscriptionStatus(
        '00000000-0000-4000-8000-000000000001',
        {
          fetchCustomer: async () => ({ subscriber: {
            entitlements: {
              abu_3meer_pro: {
                product_identifier: 'Ostoora3',
                expires_date: expiresAt,
              },
            },
            subscriptions: {
              Ostoora3: {
                is_sandbox: true,
                store,
                purchase_date: '2026-09-01T00:00:00.000Z',
              },
            },
          } }),
          execute: async (text, values = []) => {
            if (text.trimStart().startsWith('INSERT INTO user_subscription_entitlements')) {
              saved = {
                is_active: values[1],
                product_id: values[2],
                store_name: values[3],
                expires_at: values[4],
                will_renew: values[5],
                is_sandbox: values[6],
                verified_at: values[7],
              };
              return { rows: [] };
            }
            return { rows: [saved] };
          },
          recordMembershipCycle: async params => {
            cycles.push(params);
            return { activationPoints: 150, renewalPoints: 0, cycleChanged: false };
          },
        },
      );
      assert.equal(status.environment, 'sandbox');
    }
    assert.equal(cycles.length, 0);
  });

  it('uses production purchase_date, never expiry or grace extension, as the store cycle', async () => {
    const purchaseAt = '2026-09-01T00:00:00.000Z';
    const expiresAt = '2099-10-01T00:00:00.000Z';
    let saved: Record<string, unknown> = {};
    const cycles: Array<Record<string, unknown>> = [];
    const status = await syncSubscriptionStatus(
      '00000000-0000-4000-8000-000000000001',
      {
        fetchCustomer: async () => ({ subscriber: {
          entitlements: {
            abu_3meer_pro: {
              product_identifier: 'Ostoora3',
              expires_date: expiresAt,
              grace_period_expires_date: '2099-10-05T00:00:00.000Z',
            },
          },
          subscriptions: {
            Ostoora3: {
              is_sandbox: false,
              store: 'app_store',
              purchase_date: purchaseAt,
            },
          },
        } }),
        execute: async (text, values = []) => {
          if (text.trimStart().startsWith('INSERT INTO user_subscription_entitlements')) {
            saved = {
              is_active: values[1],
              product_id: values[2],
              store_name: values[3],
              expires_at: values[4],
              will_renew: values[5],
              is_sandbox: values[6],
              verified_at: values[7],
            };
            return { rows: [] };
          }
          return { rows: [saved] };
        },
        recordMembershipCycle: async params => {
          cycles.push(params);
          return { activationPoints: 150, renewalPoints: 0, cycleChanged: false };
        },
      },
    );

    assert.equal(status.environment, 'production');
    assert.equal(cycles.length, 1);
    assert.equal(
      cycles[0].cycleKey,
      `purchase:app_store:Ostoora3:${purchaseAt}`,
    );
    assert.equal(cycles[0].cycleSequence, Date.parse(purchaseAt));
  });

  it('an inactive admin override suppresses and does not consume membership rewards', async () => {
    const fake = membershipLedgerClient(false);
    const result = await recordMembershipRewardCycleInTransaction(fake.client, {
      userId: 'user-1',
      provider: 'youtube',
      cycleKey: 'tenure:months:12',
      cycleSequence: 12,
    });
    assert.deepEqual(result, {
      activationPoints: 0,
      renewalPoints: 0,
      cycleChanged: false,
    });
    assert.equal(fake.getCycle(), null);
    assert.equal(fake.ledger.size, 0);
  });

  it('a store sync does not dispatch XP while the effective access override is inactive', async () => {
    let saved: Record<string, unknown> = {};
    const cycles: Array<Record<string, unknown>> = [];
    const status = await syncSubscriptionStatus(
      '00000000-0000-4000-8000-000000000001',
      {
        fetchCustomer: async () => ({ subscriber: {
          entitlements: { abu_3meer_pro: {
            product_identifier: 'Ostoora3',
            expires_date: '2099-10-01T00:00:00.000Z',
          } },
          subscriptions: { Ostoora3: {
            is_sandbox: false,
            store: 'app_store',
            purchase_date: '2026-09-01T00:00:00.000Z',
          } },
        } }),
        execute: async (text, values = []) => {
          if (text.trimStart().startsWith('INSERT INTO user_subscription_entitlements')) {
            saved = {
              is_active: values[1],
              product_id: values[2],
              store_name: values[3],
              expires_at: values[4],
              will_renew: values[5],
              is_sandbox: values[6],
              verified_at: values[7],
              access_override_mode: 'inactive',
            };
            return { rows: [] };
          }
          return { rows: [saved] };
        },
        recordMembershipCycle: async params => {
          cycles.push(params);
          return { activationPoints: 150, renewalPoints: 0, cycleChanged: false };
        },
      },
    );
    assert.equal(status.hasMemberAccess, false);
    assert.equal(status.accessReason, 'admin_revoked');
    assert.equal(cycles.length, 0);
  });

  it('persists real admin corrections and independent period-floor deltas', async () => {
    const statements: Array<{ sql: string; values: unknown[] }> = [];
    let balance = { total: 100, monthly: 10, season: 0 };
    let adjustmentLedger: Record<string, unknown> | null = null;
    let released = false;
    const client = {
      query: async (text: string, values: unknown[] = []) => {
        const sql = text.replace(/\s+/g, ' ').trim();
        statements.push({ sql, values });
        if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
          return { rowCount: null, rows: [] };
        }
        if (sql.startsWith('SELECT 1 FROM user_profiles')) {
          return { rowCount: 1, rows: [{ '?column?': 1 }] };
        }
        if (sql.startsWith('SELECT firebase_uid, display_name, username')) {
          return { rowCount: 1, rows: [{
            firebase_uid: 'admin-firebase-1',
            display_name: 'Admin One',
            username: 'admin',
          }] };
        }
        if (sql.includes('FROM point_transactions pt')) {
          return { rowCount: 1, rows: [{
            total_points: balance.total,
            monthly_points: balance.monthly,
            season_points: balance.season,
            season_id: '2026-2027',
          }] };
        }
        if (sql.startsWith('SELECT id, user_id, final_points')) {
          return adjustmentLedger
            ? { rowCount: 1, rows: [adjustmentLedger] }
            : { rowCount: 0, rows: [] };
        }
        if (sql.startsWith('INSERT INTO point_transactions')) {
          adjustmentLedger = {
            id: 'adjustment-1',
            user_id: 'user-1',
            final_points: values[2],
            monthly_points_delta: values[3],
            season_points_delta: values[4],
          };
          return { rowCount: 1, rows: [{ id: 'adjustment-1' }] };
        }
        if (sql.startsWith('UPDATE user_profiles')) {
          balance = {
            total: Number(values[1]),
            monthly: Number(values[2]),
            season: Number(values[3]),
          };
          return { rowCount: 1, rows: [] };
        }
        if (sql.startsWith('INSERT INTO admin_audit_logs')) {
          return { rowCount: 1, rows: [] };
        }
        throw new Error(`Unexpected adjustment query: ${sql}`);
      },
      release: () => { released = true; },
    } as unknown as PoolClient;

    const result = await adjustUserPoints({
      actorId: 'admin-1',
      targetUserId: 'user-1',
      amount: -20,
      reason: 'Correct an incorrectly awarded answer.',
      idempotencyKey: 'adjustment_123',
      observedAt: new Date('2026-09-07T12:00:00.000Z'),
    }, async () => client, async () => undefined);

    assert.deepEqual(result, {
      adjustmentId: 'adjustment-1',
      targetUserId: 'user-1',
      delta: -20,
      totalPoints: 80,
      monthlyPoints: 0,
      seasonPoints: 0,
      duplicate: false,
      periodFloorApplied: true,
    });
    const ledgerWrite = statements.find(statement =>
      statement.sql.startsWith('INSERT INTO point_transactions'));
    assert.deepEqual(ledgerWrite?.values.slice(2, 5), [-20, -10, 0]);
    const auditWrite = statements.find(statement =>
      statement.sql.startsWith('INSERT INTO admin_audit_logs'));
    const auditAfter = JSON.parse(String(auditWrite?.values[3]));
    assert.equal(auditAfter.adminId, 'admin-firebase-1');
    assert.equal(auditAfter.adminDisplayName, 'Admin One');
    const replay = await adjustUserPoints({
      actorId: 'admin-1',
      targetUserId: 'user-1',
      amount: -20,
      reason: 'Correct an incorrectly awarded answer.',
      idempotencyKey: 'adjustment_123',
      observedAt: new Date('2026-09-07T12:00:00.000Z'),
    }, async () => client, async () => undefined);
    assert.equal(replay.duplicate, true);
    assert.equal(replay.adjustmentId, 'adjustment-1');
    assert.equal(replay.periodFloorApplied, true);
    assert.equal(
      statements.filter(statement =>
        statement.sql.startsWith('INSERT INTO point_transactions')).length,
      1,
    );
    assert.equal(released, true);
  });

  it('updates point values and the prediction-only multiplier transactionally', async () => {
    const state: Record<string, { points: number; multiplier: number }> = {
      signUpBonus: { points: 50, multiplier: 1 },
      dailyStreak: { points: 5, multiplier: 1 },
      videoQuestion: { points: 10, multiplier: 1 },
      playerCard: { points: 10, multiplier: 1 },
      winnerOutcome: { points: 10, multiplier: 2 },
      firstScorer: { points: 20, multiplier: 2 },
      exactPrediction: { points: 30, multiplier: 2 },
      firstMembershipActivation: { points: 150, multiplier: 1 },
      membershipRenewal: { points: 50, multiplier: 1 },
    };
    const client = {
      query: async (text: string, values: unknown[] = []) => {
        const sql = text.replace(/\s+/g, ' ').trim();
        if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
          return { rowCount: null, rows: [] };
        }
        if (sql.startsWith('SELECT key, base_points, member_multiplier')) {
          return { rows: Object.entries(state).map(([key, value]) => ({
            key,
            base_points: value.points,
            member_multiplier: value.multiplier,
          })) };
        }
        if (sql.startsWith('SELECT key FROM point_rules')) {
          return { rowCount: Object.keys(state).length, rows: [] };
        }
        if (sql.startsWith('UPDATE point_rules SET base_points')) {
          state[String(values[1])].points = Number(values[0]);
          return { rowCount: 1, rows: [{ key: values[1] }] };
        }
        if (sql.startsWith('UPDATE point_rules SET member_multiplier')) {
          const eligible = new Set(values[0] as string[]);
          for (const [key, value] of Object.entries(state)) {
            value.multiplier = eligible.has(key) ? Number(values[1]) : 1;
          }
          return { rowCount: Object.keys(state).length, rows: [] };
        }
        if (sql.startsWith('INSERT INTO admin_audit_logs')) {
          return { rowCount: 1, rows: [] };
        }
        throw new Error(`Unexpected rule query: ${sql}`);
      },
      release: () => undefined,
    } as unknown as PoolClient;

    const result = await updatePointRuleSettings('admin-1', {
      videoQuestion: 15,
      playerCard: 15,
      exactPrediction: 50,
      memberMultiplier: 2.5,
    }, async () => client);

    assert.equal(result.videoQuestion, 15);
    assert.equal(result.playerCard, 15);
    assert.equal(result.exactPrediction, 50);
    assert.equal(result.memberMultiplier, 2.5);
    assert.equal(state.winnerOutcome.multiplier, 2.5);
    assert.equal(state.firstScorer.multiplier, 2.5);
    assert.equal(state.videoQuestion.multiplier, 1);
  });

  it('strictly validates administrator point mutations', () => {
    assert.equal(adminPointAdjustmentBodySchema.safeParse({
      amount: 50,
      reason: 'Manual correction.',
      idempotencyKey: 'adjust_123',
    }).success, true);
    assert.equal(adminPointAdjustmentBodySchema.safeParse({
      amount: 0,
      reason: 'Manual correction.',
      idempotencyKey: 'adjust_123',
    }).success, false);
    assert.equal(adminPointRuleBodySchema.safeParse({
      exactPrediction: 50,
      memberMultiplier: 2,
    }).success, true);
    assert.equal(adminPointRuleBodySchema.safeParse({ unexpected: 999 }).success, false);
  });

  it('installs the published table and durable membership/admin ledger columns', async () => {
    const migration = await readFile(
      path.resolve(process.cwd(), 'migrations/043_loyalty_points_rules.sql'),
      'utf8',
    );
    for (const [key, points] of [
      ['signUpBonus', 50],
      ['dailyStreak', 5],
      ['videoQuestion', 15],
      ['playerCard', 15],
      ['winnerOutcome', 10],
      ['firstScorer', 20],
      ['exactPrediction', 50],
      ['firstMembershipActivation', 150],
      ['membershipRenewal', 50],
    ] as const) {
      assert.match(migration, new RegExp(`\\('${key}',[^\\n]+, ${points},`));
    }
    assert.match(migration, /CREATE TABLE IF NOT EXISTS membership_reward_cycles/);
    assert.match(migration, /monthly_points_delta INTEGER/);
    assert.match(migration, /season_points_delta INTEGER/);
    const snapshotImportService = await readFile(
      path.resolve(
        process.cwd(),
        'src/services/youtubeMembershipSnapshotService.ts',
      ),
      'utf8',
    );
    assert.doesNotMatch(
      snapshotImportService,
      /recordMembershipRewardCycle(?:InTransaction)?/,
    );
  });
});
