import assert from 'node:assert/strict';
import test from 'node:test';
import {
  LoyaltyRedemptionError,
  calculateLoyaltyRedemption,
  loyaltyRedemptionId,
  loyaltyRewardClaimId,
  postgresLoyaltyRedemptionLedgerId,
  postgresLoyaltyRefundLedgerId,
  rewardIsAvailableConfiguration,
} from '../services/rewardRedemptionService.js';

test('self-hosted redemption retains legacy path-safe idempotency IDs', () => {
  const first = loyaltyRedemptionId('user/1', 'reward/1', 'attempt-1');
  const replay = loyaltyRedemptionId('user/1', 'reward/1', 'attempt-1');
  const other = loyaltyRedemptionId('user/1', 'reward/1', 'attempt-2');
  const claim = loyaltyRewardClaimId('user/1', 'reward/1');

  assert.equal(first, replay);
  assert.notEqual(first, other);
  assert.equal(first.includes('/'), false);
  assert.equal(claim.includes('/'), false);
});

test('deduction and cancellation use distinct stable PostgreSQL ledger keys', () => {
  const redemptionId = loyaltyRedemptionId('user-1', 'reward-1', 'attempt-1');
  const deduction = postgresLoyaltyRedemptionLedgerId(redemptionId);
  const refund = postgresLoyaltyRefundLedgerId(redemptionId);

  assert.equal(deduction, postgresLoyaltyRedemptionLedgerId(redemptionId));
  assert.equal(refund, postgresLoyaltyRefundLedgerId(redemptionId));
  assert.notEqual(deduction, refund);
  assert.ok(deduction.length <= 150);
  assert.ok(refund.length <= 150);
});

test('redemption atomically derives wallet, finite stock, and claim count', () => {
  assert.deepEqual(
    calculateLoyaltyRedemption({
      balance: 1_000,
      cost: 250,
      stock: 4,
      claimCount: 1,
      perUserLimit: 3,
    }),
    {
      remainingBalance: 750,
      stockRemaining: 3,
      claimCount: 2,
    },
  );
  assert.deepEqual(
    calculateLoyaltyRedemption({
      balance: 1_000,
      cost: 250,
      stock: null,
      claimCount: 0,
      perUserLimit: 1,
    }),
    {
      remainingBalance: 750,
      stockRemaining: null,
      claimCount: 1,
    },
  );
});

test('redemption rejects limit, stock, balance, and malformed state', () => {
  const reason = (
    state: Parameters<typeof calculateLoyaltyRedemption>[0],
  ): string => {
    try {
      calculateLoyaltyRedemption(state);
      assert.fail('Expected redemption to fail.');
    } catch (error) {
      assert.ok(error instanceof LoyaltyRedemptionError);
      return error.reason;
    }
  };

  assert.equal(
    reason({
      balance: 100,
      cost: 1,
      stock: null,
      claimCount: 1,
      perUserLimit: 1,
    }),
    'claim-limit',
  );
  assert.equal(
    reason({
      balance: 100,
      cost: 1,
      stock: 0,
      claimCount: 0,
      perUserLimit: 1,
    }),
    'out-of-stock',
  );
  assert.equal(
    reason({
      balance: 5,
      cost: 10,
      stock: null,
      claimCount: 0,
      perUserLimit: 1,
    }),
    'insufficient-balance',
  );
  assert.equal(
    reason({
      balance: -1,
      cost: 1,
      stock: null,
      claimCount: 0,
      perUserLimit: 1,
    }),
    'invalid-configuration',
  );
});

test('catalogue availability matches current reward model semantics', () => {
  assert.equal(rewardIsAvailableConfiguration(true, 'active'), true);
  assert.equal(rewardIsAvailableConfiguration(true, 'live'), true);
  assert.equal(rewardIsAvailableConfiguration(undefined, 'active'), true);
  assert.equal(rewardIsAvailableConfiguration(true, undefined), true);
  assert.equal(rewardIsAvailableConfiguration(false, 'active'), false);
  assert.equal(rewardIsAvailableConfiguration(true, 'disabled'), false);
  assert.equal(rewardIsAvailableConfiguration(undefined, undefined), false);
});
