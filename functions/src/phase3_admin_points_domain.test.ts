import assert from "node:assert/strict";
import test from "node:test";
import {
  AdminPointAdjustmentPolicyError,
  adminPointAdjustmentFingerprint,
  adminPointAdjustmentId,
  applyAdminPointAdjustment,
} from "./phase3_admin_points_domain.js";

test("admin point additions update every active XP balance", () => {
  const result = applyAdminPointAdjustment({
    totalPoints: 1_000,
    monthlyPoints: 200,
    seasonPoints: 800,
  }, 150);
  assert.deepEqual(result.after, {
    totalPoints: 1_150,
    monthlyPoints: 350,
    seasonPoints: 950,
  });
  assert.equal(result.appliedMonthlyDelta, 150);
  assert.equal(result.appliedSeasonDelta, 150);
  assert.equal(result.periodFloorApplied, false);
});

test("admin point deductions clamp period counters but preserve total policy", () => {
  const result = applyAdminPointAdjustment({
    totalPoints: 500,
    monthlyPoints: 25,
    seasonPoints: 75,
  }, -100);
  assert.deepEqual(result.after, {
    totalPoints: 400,
    monthlyPoints: 0,
    seasonPoints: 0,
  });
  assert.equal(result.appliedMonthlyDelta, -25);
  assert.equal(result.appliedSeasonDelta, -75);
  assert.equal(result.periodFloorApplied, true);
});

test("admin point deductions cannot make all-time points negative", () => {
  assert.throws(
    () => applyAdminPointAdjustment({
      totalPoints: 99,
      monthlyPoints: 99,
      seasonPoints: 99,
    }, -100),
    (error) => error instanceof AdminPointAdjustmentPolicyError &&
      error.code === "total-floor",
  );
});

test("admin adjustment receipts are deterministic and payload-bound", () => {
  const first = adminPointAdjustmentId("admin/a", "retry-key");
  assert.equal(first, adminPointAdjustmentId("admin/a", "retry-key"));
  assert.notEqual(first, adminPointAdjustmentId("admin/b", "retry-key"));
  assert.equal(first.includes("/"), false);

  const fingerprint = adminPointAdjustmentFingerprint({
    targetUserId: "user-a",
    delta: 50,
    reason: "Manual event correction",
  });
  assert.equal(fingerprint, adminPointAdjustmentFingerprint({
    targetUserId: "user-a",
    delta: 50,
    reason: "Manual event correction",
  }));
  assert.notEqual(fingerprint, adminPointAdjustmentFingerprint({
    targetUserId: "user-a",
    delta: -50,
    reason: "Manual event correction",
  }));
});
