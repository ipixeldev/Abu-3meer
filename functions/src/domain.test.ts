import assert from "node:assert/strict";
import test from "node:test";
import {
  LoyaltyRedemptionError,
  adminMembershipState,
  achievementClaimId,
  achievementProgressValue,
  calculateLoyaltyRefund,
  calculatePoints,
  calculateLoyaltyRedemption,
  canTransitionRedemptionStatus,
  challengeIsOpen,
  didBothTeamsScore,
  evaluateChallengeAnswers,
  footballSeasonId,
  isMemberMultiplierEligible,
  memberMultiplierForSource,
  normalizeChallengeAnswer,
  parseFootballSeasonId,
  playerCardOwnershipId,
  predictionIsOpen,
  redemptionLedgerId,
  redemptionRefundLedgerId,
  resolveLeaderboardSeasonId,
  rewardIsAvailableConfiguration,
  rewardClaimId,
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

test("member multiplier is limited to predictions and video questions", () => {
  for (const source of [
    "exactPrediction",
    "firstScorer",
    "winnerOutcome",
    "bothTeamsScore",
    "videoQuestion",
  ] as const) {
    assert.equal(isMemberMultiplierEligible(source), true);
    assert.equal(memberMultiplierForSource(source, 2), 2);
  }

  for (const source of [
    "playerCard",
    "dailyStreak",
    "signUpBonus",
    "achievement",
    "adminAdjustment",
  ] as const) {
    assert.equal(isMemberMultiplierEligible(source), false);
    assert.equal(memberMultiplierForSource(source, 2), 1);
    assert.equal(memberMultiplierForSource(source, 10), 1);
  }

  assert.equal(memberMultiplierForSource("videoQuestion", 2, false), 1);
  assert.equal(memberMultiplierForSource("exactPrediction", 2, false), 1);
});

test("trusted admin membership state has fixed grant and revoke multipliers", () => {
  assert.deepEqual(adminMembershipState(true), {
    isYouTubeMember: true,
    membershipMultiplier: 2,
  });
  assert.deepEqual(adminMembershipState(false), {
    isYouTubeMember: false,
    membershipMultiplier: 1,
  });
});

test("reward ids are deterministic for duplicate prevention", () => {
  const first = rewardLedgerId("exactPrediction", "match-1", "user-1");
  const second = rewardLedgerId("exactPrediction", "match-1", "user-1");
  assert.equal(first, second);
});

test("point ledger ids are path safe and collision resistant", () => {
  const first = rewardLedgerId("videoQuestion", "a_b", "c/user");
  const second = rewardLedgerId("videoQuestion", "a", "b_c/user");
  assert.notEqual(first, second);
  assert.equal(first.includes("/"), false);
  assert.equal(second.includes("/"), false);
});

test("football season IDs turn over deterministically on 1 July UTC", () => {
  assert.equal(footballSeasonId(new Date("2026-06-30T23:59:59.999Z")), "2025-2026");
  assert.equal(footballSeasonId(new Date("2026-07-01T00:00:00.000Z")), "2026-2027");
  assert.equal(footballSeasonId(new Date("2027-01-15T12:00:00.000Z")), "2026-2027");
  assert.throws(() => footballSeasonId(new Date("invalid")));
});

test("an active leaderboard season overrides the deterministic fallback", () => {
  const now = new Date("2026-08-20T12:00:00.000Z");
  assert.equal(resolveLeaderboardSeasonId(now, []), "2026-2027");
  assert.equal(resolveLeaderboardSeasonId(now, [
    {id: "campaign-a", startsAtMs: 100},
    {id: "campaign-b", startsAtMs: 200},
  ]), "campaign-b");
  assert.equal(resolveLeaderboardSeasonId(now, [
    {id: "campaign-b", startsAtMs: 200},
    {id: "campaign-a", startsAtMs: 200},
  ]), "campaign-a");
  assert.equal(resolveLeaderboardSeasonId(
    new Date("2027-07-01T00:00:00.000Z"),
    [{id: "2026-2027", startsAtMs: 100}],
  ), "2027-2028");
});

test("automatic season IDs produce selectable July-to-July archive metadata", () => {
  const season = parseFootballSeasonId("2026-2027");
  assert.equal(season?.displayName, "Season 2026/2027");
  assert.equal(season?.startsAt.toISOString(), "2026-07-01T00:00:00.000Z");
  assert.equal(season?.endsAt.toISOString(), "2027-07-01T00:00:00.000Z");
  assert.equal(parseFootballSeasonId("2026-2028"), null);
  assert.equal(parseFootballSeasonId("campaign-a"), null);
});

test("achievement progress uses only supported server-owned metrics", () => {
  const metrics = {
    totalPoints: 1_000,
    seasonPoints: 800,
    monthlyPoints: 200,
    streak: 7,
    playerCards: 4,
    predictions: 12,
  };
  assert.equal(achievementProgressValue("totalPoints", metrics), 1_000);
  assert.equal(achievementProgressValue("seasonPoints", metrics), 800);
  assert.equal(achievementProgressValue("monthlyPoints", metrics), 200);
  assert.equal(achievementProgressValue("streak", metrics), 7);
  assert.equal(achievementProgressValue("playerCards", metrics), 4);
  assert.equal(achievementProgressValue("predictions", metrics), 12);
  assert.throws(() => achievementProgressValue("clientValue", metrics));
  assert.throws(() => achievementProgressValue("streak", {...metrics, streak: -1}));
});

test("achievement claim and redemption refund IDs are deterministic and path safe", () => {
  const claim = achievementClaimId("user/a", "achievement/a");
  const refund = redemptionRefundLedgerId("redemption/a");
  assert.equal(claim.includes("/"), false);
  assert.equal(refund.includes("/"), false);
  assert.equal(claim, achievementClaimId("user/a", "achievement/a"));
  assert.equal(refund, redemptionRefundLedgerId("redemption/a"));
});

test("redemption fulfillment transitions keep terminal states immutable", () => {
  assert.equal(canTransitionRedemptionStatus("pending", "contacted"), true);
  assert.equal(canTransitionRedemptionStatus("pending", "fulfilled"), true);
  assert.equal(canTransitionRedemptionStatus("contacted", "pending"), true);
  assert.equal(canTransitionRedemptionStatus("contacted", "cancelled"), true);
  assert.equal(canTransitionRedemptionStatus("fulfilled", "cancelled"), false);
  assert.equal(canTransitionRedemptionStatus("cancelled", "pending"), false);
  assert.equal(canTransitionRedemptionStatus("cancelled", "cancelled"), true);
});

test("Player Card ownership prefers a stable linked catalogue ID", () => {
  assert.equal(playerCardOwnershipId("challenge", []), "challenge");
  assert.equal(
    playerCardOwnershipId("challenge", ["card-z", "card-a"]),
    "card-a",
  );
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

test("challenge answer normalization handles unicode, whitespace, and true/false aliases", () => {
  assert.equal(normalizeChallengeAnswer("  REAL   Madrid  "), "real madrid");
  assert.equal(normalizeChallengeAnswer("نعم", "trueFalse"), "true");
  assert.equal(normalizeChallengeAnswer(false, "trueFalse"), "false");
  assert.throws(() => normalizeChallengeAnswer("maybe", "trueFalse"));
});

test("legacy video phrase answers remain supported", () => {
  const result = evaluateChallengeAnswers(
    {main: "  Hala Madrid "},
    {normalizedAnswer: "hala madrid"},
  );
  assert.deepEqual(result, {
    correct: true,
    questionCount: 1,
    answeredCount: 1,
    normalizedAnswers: {main: "hala madrid"},
  });
});

test("mixed multi-question challenges require every private answer", () => {
  const secret = {
    schemaVersion: 2,
    questions: [
      {id: "club", type: "multipleChoice", acceptedAnswers: ["fcb"]},
      {id: "won", type: "trueFalse", acceptedAnswers: [true]},
      {id: "phrase", type: "text", acceptedAnswers: ["visca barca", "visca el barca"]},
    ],
  };
  const correct = evaluateChallengeAnswers(
    {club: "FCB", won: "yes", phrase: "Visca  Barça"},
    {
      ...secret,
      questions: [
        secret.questions[0],
        secret.questions[1],
        {id: "phrase", type: "text", acceptedAnswers: ["visca barça"]},
      ],
    },
  );
  assert.equal(correct.correct, true);
  assert.equal(correct.questionCount, 3);

  const incomplete = evaluateChallengeAnswers(
    {club: "FCB", won: false},
    secret,
  );
  assert.equal(incomplete.correct, false);
  assert.equal(incomplete.answeredCount, 2);
});

test("invalid challenge secret schemas and oversized answer payloads are rejected", () => {
  assert.throws(() => evaluateChallengeAnswers({main: "x"}, {questions: []}));
  assert.throws(() => evaluateChallengeAnswers({"bad/id": "x"}, {normalizedAnswer: "x"}));
  assert.throws(() => evaluateChallengeAnswers(
    Object.fromEntries(Array.from({length: 21}, (_, index) => [`q${index}`, "x"])),
    {normalizedAnswer: "x"},
  ));
});

test("challenge schedule accepts live aliases and uses an exclusive end", () => {
  assert.equal(challengeIsOpen("open", 1_500, 1_000, 2_000), true);
  assert.equal(challengeIsOpen("scheduled", 1_500, 1_000, 2_000), true);
  assert.equal(challengeIsOpen("live", 1_500, 1_000, 2_000), true);
  assert.equal(challengeIsOpen("draft", 1_500, 1_000, 2_000), false);
  assert.equal(challengeIsOpen("open", 2_000, 1_000, 2_000), false);
});

test("reward availability keeps app and server catalogue states aligned", () => {
  assert.equal(rewardIsAvailableConfiguration(true, "active"), true);
  assert.equal(rewardIsAvailableConfiguration(true, "live"), true);
  assert.equal(rewardIsAvailableConfiguration(true, undefined), true);
  assert.equal(rewardIsAvailableConfiguration(undefined, "active"), true);
  assert.equal(rewardIsAvailableConfiguration(false, "active"), false);
  assert.equal(rewardIsAvailableConfiguration(true, "disabled"), false);
  assert.equal(rewardIsAvailableConfiguration(undefined, undefined), false);
});

test("loyalty redemption and claim IDs are deterministic and path safe", () => {
  const redemptionId = redemptionLedgerId("user/1", "reward/1", "request-1");
  const claimId = rewardClaimId("user/1", "reward/1");
  assert.equal(redemptionId.includes("/"), false);
  assert.equal(claimId.includes("/"), false);
  assert.equal(
    redemptionLedgerId("user", "reward", "same"),
    redemptionLedgerId("user", "reward", "same"),
  );
  assert.notEqual(
    redemptionLedgerId("a_b", "c", "same"),
    redemptionLedgerId("a", "b_c", "same"),
  );
});

test("loyalty redemption atomically derives balance, stock, and claims", () => {
  assert.deepEqual(calculateLoyaltyRedemption({
    balance: 1_000,
    cost: 250,
    stock: 4,
    claimCount: 1,
    perUserLimit: 3,
  }), {
    remainingBalance: 750,
    stockRemaining: 3,
    claimCount: 2,
  });
  assert.deepEqual(calculateLoyaltyRedemption({
    balance: 1_000,
    cost: 250,
    stock: null,
    claimCount: 0,
    perUserLimit: 1,
  }).stockRemaining, null);
});

test("loyalty redemption rejects limits, stock, balance, and invalid state", () => {
  const reason = (callback: () => unknown): string | undefined => {
    try {
      callback();
      return undefined;
    } catch (error) {
      assert.ok(error instanceof LoyaltyRedemptionError);
      return error.reason;
    }
  };
  assert.equal(reason(() => calculateLoyaltyRedemption({
    balance: 100, cost: 1, stock: null, claimCount: 1, perUserLimit: 1,
  })), "claim-limit");
  assert.equal(reason(() => calculateLoyaltyRedemption({
    balance: 100, cost: 1, stock: 0, claimCount: 0, perUserLimit: 1,
  })), "out-of-stock");
  assert.equal(reason(() => calculateLoyaltyRedemption({
    balance: 5, cost: 10, stock: null, claimCount: 0, perUserLimit: 1,
  })), "insufficient-balance");
  assert.equal(reason(() => calculateLoyaltyRedemption({
    balance: -1, cost: 1, stock: null, claimCount: 0, perUserLimit: 1,
  })), "invalid-state");
});

test("loyalty refund atomically restores balance, finite stock, and claim count", () => {
  assert.deepEqual(calculateLoyaltyRefund({
    balance: 750,
    cost: 250,
    stock: 3,
    claimCount: 2,
  }), {
    remainingBalance: 1_000,
    stockRemaining: 4,
    claimCount: 1,
  });
  assert.deepEqual(calculateLoyaltyRefund({
    balance: 750,
    cost: 250,
    stock: null,
    claimCount: 1,
  }), {
    remainingBalance: 1_000,
    stockRemaining: null,
    claimCount: 0,
  });
  assert.throws(() => calculateLoyaltyRefund({
    balance: 750,
    cost: 250,
    stock: 3,
    claimCount: 0,
  }), LoyaltyRedemptionError);
  assert.throws(() => calculateLoyaltyRefund({
    balance: Number.MAX_SAFE_INTEGER,
    cost: 1,
    stock: null,
    claimCount: 1,
  }), LoyaltyRedemptionError);
});
