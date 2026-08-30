import assert from 'node:assert/strict';
import test from 'node:test';
import {
  calculateLoyaltyRefund,
  canTransitionRedemptionStatus,
  finiteInteger,
  loyaltyRefundTransactionId,
  loyaltyRewardClaimId,
  safeDocumentId,
} from '../services/adminContentDomain.js';

test('redemption transitions keep fulfilled and cancelled requests terminal', () => {
  assert.equal(canTransitionRedemptionStatus('pending', 'contacted'), true);
  assert.equal(canTransitionRedemptionStatus('pending', 'fulfilled'), true);
  assert.equal(canTransitionRedemptionStatus('contacted', 'pending'), true);
  assert.equal(canTransitionRedemptionStatus('contacted', 'cancelled'), true);
  assert.equal(canTransitionRedemptionStatus('fulfilled', 'cancelled'), false);
  assert.equal(canTransitionRedemptionStatus('cancelled', 'pending'), false);
});

test('cancellation refunds points, stock, and the per-user claim exactly once', () => {
  assert.deepEqual(
    calculateLoyaltyRefund({
      balance: 250,
      cost: 100,
      stock: 4,
      claimCount: 2,
    }),
    { balance: 350, stock: 5, claimCount: 1 },
  );
  assert.deepEqual(
    calculateLoyaltyRefund({
      balance: 0,
      cost: 25,
      stock: null,
      claimCount: 1,
    }),
    { balance: 25, stock: null, claimCount: 0 },
  );
  assert.throws(
    () => calculateLoyaltyRefund({ balance: 0, cost: 25, stock: 0, claimCount: 0 }),
    /Invalid loyalty refund state/,
  );
});

test('server bridge uses the same deterministic Firestore IDs as the legacy callable', () => {
  assert.equal(
    loyaltyRewardClaimId('user-1', 'reward/x'),
    'claim_6-user-1_10-reward%2Fx',
  );
  assert.equal(
    loyaltyRefundTransactionId('redemption/1'),
    'refund_14-redemption%2F1',
  );
});

test('document IDs and stored integers reject unsafe admin input', () => {
  assert.equal(safeDocumentId(' valid-id '), 'valid-id');
  assert.throws(() => safeDocumentId('bad/id'), /ID is invalid/);
  assert.equal(finiteInteger('12', 'Points', 0, 20), 12);
  assert.throws(() => finiteInteger(21, 'Points', 0, 20), /Points is invalid/);
});
