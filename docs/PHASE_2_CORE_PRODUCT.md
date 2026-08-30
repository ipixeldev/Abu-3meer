# Phase 2 core product

Phase 2 turns the engagement screens into live, configurable product surfaces while keeping temporary mock content isolated behind the existing Settings toggle.

## User experiences

- Predictions remember the current user's saved picks, allow updates while the prediction window is open, and expose a filterable history with the final result, pick-by-pick correctness, and awarded points.
- Leaderboards support monthly, season, and all-time scopes. Season documents provide the selector, and the current user's exact rank is returned even when it falls outside the visible top list.
- Challenges support video phrases, Player Cards, multiple choice, true/false, and multi-question quizzes. Attempt limits, member-only eligibility, reward points, and availability windows are visible before submission.
- Achievements and levels are read from configurable Firestore definitions rather than hard-coded production lists.
- Eligible achievements are claimed through a server-owned, idempotent award flow, so the configured reward cannot be granted twice.
- The loyalty store exposes active rewards, stock and member restrictions, the user's spendable loyalty balance, and redemption history.
- The Player Card collection distinguishes locked and collected cards and provides full player, rarity, position, team, description, and stat details.

## Admin experiences

Content managers can configure and preview:

- Challenge type, questions, choices, accepted answers, attempts, points, schedule, status, notification flag, and member-only access.
- Achievement definitions and their requirement thresholds.
- Level thresholds, visual identity, and perks.
- Loyalty rewards, costs, stock, per-user limits, availability, fulfillment type, and member-only access.
- Redemption requests, contact/fulfilled states, and cancellation notes with atomic point, stock, and claim-limit refunds.
- Player Card identity, art, rating, rarity, position, stats, description, and availability.

Answer keys are written only to each challenge's private subcollection. Public challenge documents contain prompts and options but never correct answers.

New Player Card challenge links are stored in the private `playerCardChallengeLinks` collection. Before a public launch, any legacy catalogue rows that still contain a public `sourceChallengeId` must be resaved or migrated. Fully confidential locked-card metadata and secret-achievement definitions require a later server-redacted projection; the current signed-in catalogue masks them in the UI but does not claim database-level secrecy for those descriptive fields.

## Firestore collections

| Collection | Purpose |
| --- | --- |
| `predictions` | One saved prediction per user and match, including result-award metadata after processing. |
| `leaderboardEntries` | Current monthly, season, and all-time totals. |
| `leaderboardSeasons` | Season metadata; archived ranking rows can live in `leaderboardSeasons/{seasonId}/entries`. |
| `videoQuestions` | Video phrase, multiple-choice, true/false, and multi-question challenges. |
| `playerCards` | Player Card catalogue entries and Player Card challenges, separated by `documentType`. |
| `playerCardChallengeLinks` | Admin/server-only mapping from a hidden Player Card challenge to its catalogue reward. |
| `achievementDefinitions` | Admin-configurable achievement definitions. |
| `achievementClaims` | Deterministic server receipts for achievement point awards. |
| `levelDefinitions` | Admin-configurable level thresholds and perks. |
| `loyaltyRewards` | Active and scheduled reward catalogue. |
| `loyaltyRedemptions` | Server-created redemption history. |

Per-user challenge attempts stay under the challenge document. Collected cards and achievement progress stay under the user document. Loyalty and point transactions are server-owned ledgers.

## Callable functions

- `submitChallenge` evaluates all Phase 2 challenge types against private answer data, enforces scheduling, membership, and attempt limits, and awards points idempotently.
- `redeemLoyaltyReward` performs an idempotent transaction across user balance, stock, claim limits, redemption history, and the loyalty ledger.
- `claimAchievement` verifies progress from server-owned user metrics and grants the configured reward once.
- `updateRedemptionStatus` lets an authorized content manager contact or fulfill a request, or cancel it with an atomic loyalty/stock refund.
- Existing prediction result processing now records aggregate and per-category points on each saved prediction so history can show the exact award.

Leaderboard season rollover also preserves each user's previous-season row under the archived season before resetting the live season total. Player Card challenge-to-catalogue links are kept in an admin/server-only collection so the answer cannot be inferred from the public catalogue.

The legacy `submitVideoAnswer` and `claimPlayerCard` callables remain compatible and delegate to the same challenge engine.

## Required before live verification

The source, rules, indexes, tests, and UI are included in the repository, but callable-backed submissions and redemptions require the Cloud Functions deployment that was intentionally deferred. After Firebase billing is enabled, deploy Functions and Firestore configuration, then run the complete prediction and challenge journeys against the production project.
