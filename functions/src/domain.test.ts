import assert from "node:assert/strict";
import test from "node:test";
import {
  calculatePoints,
  didBothTeamsScore,
  predictionIsOpen,
  rewardLedgerId,
} from "./domain.js";

test("launch point rules apply normal and member multipliers", () => {
  assert.equal(calculatePoints(100, 1), 100);
  assert.equal(calculatePoints(100, 2), 200);
  assert.equal(calculatePoints(250, 1), 250);
  assert.equal(calculatePoints(250, 2), 500);
  assert.equal(calculatePoints(150, 1), 150);
  assert.equal(calculatePoints(150, 2), 300);
  assert.equal(calculatePoints(40, 1), 40);
  assert.equal(calculatePoints(40, 2), 80);
  assert.equal(calculatePoints(20, 1), 20);
  assert.equal(calculatePoints(20, 2), 40);
});

test("reward ids are deterministic for duplicate prevention", () => {
  const first = rewardLedgerId("exactPrediction", "match-1", "user-1");
  const second = rewardLedgerId("exactPrediction", "match-1", "user-1");
  assert.equal(first, second);
});

test("prediction deadline uses server interval semantics", () => {
  assert.equal(predictionIsOpen(1_500, 1_000, 2_000), true);
  assert.equal(predictionIsOpen(2_000, 1_000, 2_000), false);
  assert.equal(predictionIsOpen(999, 1_000, 2_000), false);
});

test("both-teams-score result is derived from the official score", () => {
  assert.equal(didBothTeamsScore(2, 1), true);
  assert.equal(didBothTeamsScore(0, 1), false);
  assert.equal(didBothTeamsScore(0, 0), false);
  assert.throws(() => didBothTeamsScore(-1, 1));
});
