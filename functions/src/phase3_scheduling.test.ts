import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {
  automaticMatchResultHash,
  matchResultRetryDelayMs,
  parseOfficialMatchResult,
  resultJobCanBeClaimed,
  scheduledTargetStatus,
  storedMatchHasProcessedResult,
} from "./phase3_scheduling.js";

test("official result jobs normalize scorer text and reject unsafe payloads", () => {
  assert.deepEqual(parseOfficialMatchResult({
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "  Lamine   Yamal  ",
  }), {
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "Lamine Yamal",
  });
  assert.throws(() => parseOfficialMatchResult({
    matchId: "bad/path",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "Player",
  }));
  assert.throws(() => parseOfficialMatchResult({
    matchId: "match_1",
    homeScore: 21,
    awayScore: 1,
    firstScorer: "Player",
  }));
  assert.throws(() => parseOfficialMatchResult({
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "",
  }));
});

test("automatic result hashes are stable across harmless scorer formatting", () => {
  const first = automaticMatchResultHash({
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "Lamine  Yamal",
  });
  const replay = automaticMatchResultHash({
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: " lamine yamal ",
  });
  const changed = automaticMatchResultHash({
    matchId: "match_1",
    homeScore: 1,
    awayScore: 2,
    firstScorer: "Lamine Yamal",
  });
  assert.equal(first, replay);
  assert.notEqual(first, changed);
});

test("ambiguous result retries confirm only the identical processed result", () => {
  const result = {
    matchId: "match_1",
    homeScore: 2,
    awayScore: 1,
    firstScorer: "Lamine Yamal",
  };
  assert.equal(storedMatchHasProcessedResult({
    resultProcessed: true,
    resultHash: automaticMatchResultHash(result),
  }, result), true);
  assert.equal(storedMatchHasProcessedResult({
    resultProcessed: true,
    homeScore: 2,
    awayScore: 1,
    firstScorer: " lamine  yamal ",
  }, result), true);
  assert.equal(storedMatchHasProcessedResult({
    resultProcessed: true,
    homeScore: 1,
    awayScore: 2,
    firstScorer: "Lamine Yamal",
  }, result), false);
  assert.equal(storedMatchHasProcessedResult({
    resultProcessed: false,
    resultHash: automaticMatchResultHash(result),
  }, result), false);
});

test("result job leases are claimable only when due or expired", () => {
  const now = 2_000;
  assert.equal(resultJobCanBeClaimed({
    status: "pending",
    nextAttemptAt: Timestamp.fromMillis(now),
  }, now), true);
  assert.equal(resultJobCanBeClaimed({
    status: "retry",
    nextAttemptAt: Timestamp.fromMillis(now + 1),
  }, now), false);
  assert.equal(resultJobCanBeClaimed({
    status: "processing",
    leaseExpiresAt: Timestamp.fromMillis(now),
  }, now), true);
  assert.equal(resultJobCanBeClaimed({
    status: "processing",
    leaseExpiresAt: Timestamp.fromMillis(now + 1),
  }, now), false);
  assert.equal(resultJobCanBeClaimed({
    status: "completed",
    nextAttemptAt: Timestamp.fromMillis(0),
  }, now), false);
  assert.equal(resultJobCanBeClaimed({status: "pending"}, now), false);
});

test("result retry backoff is deterministic and capped at one hour", () => {
  assert.equal(matchResultRetryDelayMs(1), 30_000);
  assert.equal(matchResultRetryDelayMs(2), 60_000);
  assert.equal(matchResultRetryDelayMs(7), 1_920_000);
  assert.equal(matchResultRetryDelayMs(8), 3_600_000);
  assert.equal(matchResultRetryDelayMs(50), 3_600_000);
  assert.throws(() => matchResultRetryDelayMs(0));
});

test("match prediction windows activate and lock at exact UTC boundaries", () => {
  assert.equal(scheduledTargetStatus({
    family: "match",
    currentStatus: "scheduled",
    nowMs: 999,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), null);
  assert.equal(scheduledTargetStatus({
    family: "match",
    currentStatus: "scheduled",
    nowMs: 1_000,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), "open");
  assert.equal(scheduledTargetStatus({
    family: "match",
    currentStatus: "open",
    nowMs: 2_000,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), "locked");
});

test("challenge windows promote scheduled/open aliases and expire exclusively", () => {
  assert.equal(scheduledTargetStatus({
    family: "challenge",
    currentStatus: "open",
    nowMs: 500,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), "scheduled");
  assert.equal(scheduledTargetStatus({
    family: "challenge",
    currentStatus: "scheduled",
    nowMs: 1_000,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), "live");
  assert.equal(scheduledTargetStatus({
    family: "challenge",
    currentStatus: "live",
    nowMs: 2_000,
    startsAtMs: 1_000,
    endsAtMs: 2_000,
  }), "ended");
});

test("reward windows support open-ended bounds without overriding disabled rewards", () => {
  assert.equal(scheduledTargetStatus({
    family: "reward",
    currentStatus: "scheduled",
    nowMs: 1_000,
    startsAtMs: null,
    endsAtMs: null,
    enabled: true,
  }), "active");
  assert.equal(scheduledTargetStatus({
    family: "reward",
    currentStatus: "active",
    nowMs: 1_000,
    startsAtMs: null,
    endsAtMs: 1_000,
    enabled: true,
  }), "expired");
  assert.equal(scheduledTargetStatus({
    family: "reward",
    currentStatus: "live",
    nowMs: 1_000,
    startsAtMs: 500,
    endsAtMs: 2_000,
    enabled: true,
  }), null);
  assert.equal(scheduledTargetStatus({
    family: "reward",
    currentStatus: "scheduled",
    nowMs: 1_000,
    startsAtMs: 500,
    endsAtMs: 2_000,
    enabled: false,
  }), null);
});

test("invalid or incomplete required schedules never transition", () => {
  assert.equal(scheduledTargetStatus({
    family: "challenge",
    currentStatus: "scheduled",
    nowMs: 1_500,
    startsAtMs: null,
    endsAtMs: 2_000,
  }), null);
  assert.equal(scheduledTargetStatus({
    family: "match",
    currentStatus: "open",
    nowMs: 1_500,
    startsAtMs: 2_000,
    endsAtMs: 1_000,
  }), null);
});
