import {createHash} from "node:crypto";

export const MAX_ADMIN_POINT_ADJUSTMENT = 100_000;
export const MAX_STORED_POINT_BALANCE = 1_000_000_000;

export type AdminPointBalances = {
  totalPoints: number;
  monthlyPoints: number;
  seasonPoints: number;
};

export type AppliedAdminPointAdjustment = {
  before: AdminPointBalances;
  after: AdminPointBalances;
  appliedMonthlyDelta: number;
  appliedSeasonDelta: number;
  periodFloorApplied: boolean;
};

export class AdminPointAdjustmentPolicyError extends Error {
  constructor(readonly code: "invalid-state" | "total-floor" | "overflow") {
    super(code);
  }
}

/**
 * Applies an XP correction using the product's explicit floor policy.
 *
 * The all-time balance is authoritative and a deduction that would make it
 * negative is rejected. Month and season counters represent bounded periods,
 * so deductions clamp those counters at zero. Loyalty is intentionally not
 * part of this helper: manual XP corrections never mint or remove spendable
 * loyalty currency.
 */
export function applyAdminPointAdjustment(
  balances: AdminPointBalances,
  delta: number,
): AppliedAdminPointAdjustment {
  const values = [
    balances.totalPoints,
    balances.monthlyPoints,
    balances.seasonPoints,
    delta,
  ];
  if (!values.every(Number.isSafeInteger) ||
      balances.totalPoints < 0 || balances.monthlyPoints < 0 ||
      balances.seasonPoints < 0 || delta === 0 ||
      Math.abs(delta) > MAX_ADMIN_POINT_ADJUSTMENT) {
    throw new AdminPointAdjustmentPolicyError("invalid-state");
  }

  const totalPoints = balances.totalPoints + delta;
  if (totalPoints < 0) {
    throw new AdminPointAdjustmentPolicyError("total-floor");
  }
  const monthlyPoints = Math.max(0, balances.monthlyPoints + delta);
  const seasonPoints = Math.max(0, balances.seasonPoints + delta);
  if ([totalPoints, monthlyPoints, seasonPoints].some((value) =>
    !Number.isSafeInteger(value) || value > MAX_STORED_POINT_BALANCE)) {
    throw new AdminPointAdjustmentPolicyError("overflow");
  }

  return {
    before: {...balances},
    after: {totalPoints, monthlyPoints, seasonPoints},
    appliedMonthlyDelta: monthlyPoints - balances.monthlyPoints,
    appliedSeasonDelta: seasonPoints - balances.seasonPoints,
    periodFloorApplied:
      monthlyPoints - balances.monthlyPoints !== delta ||
      seasonPoints - balances.seasonPoints !== delta,
  };
}

export function adminPointAdjustmentId(
  adminId: string,
  idempotencyKey: string,
): string {
  return `point_adjustment_${createHash("sha256")
    .update(`${adminId}\u001f${idempotencyKey}`)
    .digest("hex")}`;
}

export function adminPointAdjustmentFingerprint(params: {
  targetUserId: string;
  delta: number;
  reason: string;
}): string {
  return createHash("sha256")
    .update(`${params.targetUserId}\u001f${params.delta}\u001f${params.reason}`)
    .digest("hex");
}
