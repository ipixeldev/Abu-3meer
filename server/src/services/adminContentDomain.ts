export const adminChallengeStatuses = [
  'draft',
  'scheduled',
  'open',
  'disabled',
  'ended',
  'closed',
  'archived',
] as const;

export type AdminChallengeStatus = typeof adminChallengeStatuses[number];

export const redemptionStatuses = [
  'pending',
  'contacted',
  'fulfilled',
  'cancelled',
] as const;

export type AdminRedemptionStatus = typeof redemptionStatuses[number];

export function canTransitionRedemptionStatus(
  from: AdminRedemptionStatus,
  to: AdminRedemptionStatus,
): boolean {
  if (from === to) return true;
  if (from === 'pending') {
    return to === 'contacted' || to === 'fulfilled' || to === 'cancelled';
  }
  if (from === 'contacted') {
    return to === 'pending' || to === 'fulfilled' || to === 'cancelled';
  }
  return false;
}

export interface LoyaltyRefundState {
  balance: number;
  cost: number;
  stock: number | null;
  claimCount: number;
}

export interface LoyaltyRefundResult {
  balance: number;
  stock: number | null;
  claimCount: number;
}

export function calculateLoyaltyRefund(
  state: LoyaltyRefundState,
): LoyaltyRefundResult {
  const integers = [state.balance, state.cost, state.claimCount];
  if (
    !integers.every(Number.isSafeInteger) ||
    state.balance < 0 ||
    state.cost < 1 ||
    state.claimCount < 1 ||
    (state.stock !== null &&
      (!Number.isSafeInteger(state.stock) || state.stock < 0))
  ) {
    throw new Error('Invalid loyalty refund state.');
  }
  const balance = state.balance + state.cost;
  const stock = state.stock === null ? null : state.stock + 1;
  if (
    !Number.isSafeInteger(balance) ||
    (stock !== null && !Number.isSafeInteger(stock))
  ) {
    throw new Error('Loyalty refund exceeds the supported range.');
  }
  return { balance, stock, claimCount: state.claimCount - 1 };
}

export function finiteInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number {
  const number = typeof value === 'number' ? value : Number(value);
  if (
    !Number.isSafeInteger(number) ||
    number < minimum ||
    number > maximum
  ) {
    throw new Error(`${field} is invalid.`);
  }
  return number;
}

export function safeDocumentId(value: string, field = 'Document'): string {
  const id = value.trim();
  if (!id || id.length > 150 || id.includes('/')) {
    throw new Error(`${field} ID is invalid.`);
  }
  return id;
}

function legacyIdComponent(value: string): string {
  const encoded = encodeURIComponent(value);
  return `${encoded.length}-${encoded}`;
}

/** Matches the IDs created by the existing Firebase loyalty callable. */
export function loyaltyRewardClaimId(userId: string, rewardId: string): string {
  return `claim_${[userId, rewardId].map(legacyIdComponent).join('_')}`;
}

/** Matches the idempotent refund receipt used by the Firebase callable. */
export function loyaltyRefundTransactionId(redemptionId: string): string {
  return `refund_${legacyIdComponent(redemptionId)}`;
}
