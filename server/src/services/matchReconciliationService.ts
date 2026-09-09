import { query } from '../db/pool.js';
import {
  fetchExternalMatchDetails,
  fetchExternalRecentMatches,
  type ExternalFootballMatch,
  type MatchTimelineDetail,
} from './footballDetailsService.js';
import { redis } from '../redis/client.js';

interface PendingMatchRow {
  id: string;
  home_team: string;
  away_team: string;
  kickoff_at: Date;
}

interface FinishedMatchRow {
  id: string;
  reward_processed: boolean;
  has_unrewarded: boolean;
}

export interface FinishedMatchSettlementRecoveryResult {
  found: number;
  enqueued: number;
  failed: number;
}

export function settlementRecoveryRequired(candidate: {
  rewardProcessed: boolean;
  hasUnrewarded: boolean;
}): boolean {
  // A crash can happen after the last prediction row is marked rewarded but
  // before denormalized counters, campaigns, and the match completion marker
  // are committed. The false match marker is therefore durable work too.
  return !candidate.rewardProcessed || candidate.hasUnrewarded;
}

export const FIRST_SCORER_RECONCILIATION_GRACE_MS = 4 * 60 * 60 * 1000;
export const PROVIDER_MATCH_KICKOFF_TOLERANCE_MS = 5 * 60 * 1000;

function normalizedTeam(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

function minuteValue(value: string): number {
  const [minute, extra] = value.split('+').map(part => Number.parseInt(part, 10));
  return (Number.isFinite(minute) ? minute : Number.MAX_SAFE_INTEGER) * 1000 +
    (Number.isFinite(extra) ? extra : 0);
}

export function firstScorerFromTimeline(
  timeline: MatchTimelineDetail[],
): string {
  const firstGoal = [...timeline]
    .filter(event => ['goal', 'penalty_goal', 'own_goal'].includes(event.type))
    .filter(event => event.player.trim().length > 0)
    .sort((left, right) => minuteValue(left.minute) - minuteValue(right.minute))[0];
  return firstGoal?.player.trim() ?? '';
}

export function officialFirstScorer(input: {
  homeScore: number;
  awayScore: number;
  provided?: string | null;
  timeline?: MatchTimelineDetail[];
}): string {
  const provided = input.provided?.trim() ?? '';
  if (provided) return provided;
  if (input.homeScore === 0 && input.awayScore === 0) return 'No scorer';
  return firstScorerFromTimeline(input.timeline ?? []);
}

/**
 * Some football providers publish the final score before their event feed.
 * Keep polling during a conservative post-kickoff grace window, then settle
 * score/winner rewards with an explicit unknown scorer instead of leaving
 * every prediction pending forever.
 */
export function firstScorerAfterProviderGrace(input: {
  kickoffAt: Date;
  homeScore: number;
  awayScore: number;
  now?: Date;
}): string {
  if (input.homeScore === 0 && input.awayScore === 0) return 'No scorer';
  const now = input.now ?? new Date();
  return now.getTime() - input.kickoffAt.getTime() >=
      FIRST_SCORER_RECONCILIATION_GRACE_MS
    ? 'Unknown'
    : '';
}

export function findCompletedProviderMatch(
  pending: PendingMatchRow,
  providerMatches: ExternalFootballMatch[],
): ExternalFootballMatch | undefined {
  const exact = providerMatches.find(match => match.id === pending.id);
  if (exact) return exact;
  const home = normalizedTeam(pending.home_team);
  const away = normalizedTeam(pending.away_team);
  return providerMatches.find(match => {
    const kickoffDifference = Math.abs(
      Date.parse(match.kickoff_at) - new Date(pending.kickoff_at).getTime(),
    );
    return normalizedTeam(match.home_team) === home &&
      normalizedTeam(match.away_team) === away &&
      kickoffDifference <= PROVIDER_MATCH_KICKOFF_TOLERANCE_MS;
  });
}

/**
 * The BullMQ job is an accelerator, not the durable source of truth. Finished
 * matches and unrewarded predictions live in PostgreSQL, so periodically
 * rebuilding jobs from this query recovers a Redis restart, a removed job, or
 * a job that exhausted its retry budget. Deliberately do not filter by match
 * ID prefix: manually managed matches need the same recovery guarantee as
 * provider-imported fixtures.
 */
export async function finishedMatchesAwaitingSettlement(): Promise<string[]> {
  const result = await query<FinishedMatchRow>(
    `SELECT m.id,
            m.reward_processed,
            EXISTS (
              SELECT 1
              FROM predictions pending
              WHERE pending.match_id = m.id
                AND pending.rewarded = false
            ) AS has_unrewarded
     FROM matches m
     WHERE m.status = 'finished'
       AND m.home_score IS NOT NULL
       AND m.away_score IS NOT NULL
       AND EXISTS (
         SELECT 1
         FROM predictions p
         WHERE p.match_id = m.id
       )
       AND (
         m.reward_processed = false
         OR EXISTS (
           SELECT 1
           FROM predictions pending
           WHERE pending.match_id = m.id
             AND pending.rewarded = false
         )
       )
     ORDER BY m.kickoff_at, m.id`,
  );
  return result.rows
    .filter(match => settlementRecoveryRequired({
      rewardProcessed: match.reward_processed,
      hasUnrewarded: match.has_unrewarded,
    }))
    .map(match => match.id);
}

/**
 * Enqueue every durable settlement candidate independently. A single Redis
 * failure must not prevent later matches from being recovered, and every
 * failure remains discoverable on the next periodic pass.
 */
export async function recoverFinishedMatchSettlements(
  enqueue: (matchId: string) => Promise<unknown>,
  loadMatchIds: () => Promise<string[]> = finishedMatchesAwaitingSettlement,
): Promise<FinishedMatchSettlementRecoveryResult> {
  const matchIds = await loadMatchIds();
  let enqueued = 0;
  let failed = 0;
  for (const matchId of matchIds) {
    try {
      await enqueue(matchId);
      enqueued += 1;
    } catch (error) {
      failed += 1;
      console.error(
        `[Worker: Match Settlement] Could not recover match ${matchId}:`,
        error instanceof Error ? error.message : 'unknown queue error',
      );
    }
  }
  return { found: matchIds.length, enqueued, failed };
}

/**
 * Imports official provider results only for matches that have unresolved
 * PostgreSQL predictions. It returns match IDs for the settlement worker,
 * keeping provider polling bounded regardless of total audience size.
 */
export async function reconcileCompletedExternalMatches(): Promise<string[]> {
  const pending = await query<PendingMatchRow>(
    `SELECT DISTINCT m.id, m.home_team, m.away_team, m.kickoff_at
     FROM matches m
     JOIN predictions p ON p.match_id = m.id
     WHERE p.rewarded = false
       AND m.kickoff_at <= CURRENT_TIMESTAMP
       AND m.status <> 'finished'
       AND m.status NOT IN ('cancelled', 'postponed')
     ORDER BY m.kickoff_at`,
  );
  if (pending.rowCount === 0) return [];

  const providerMatches = await fetchExternalRecentMatches();
  const ready: string[] = [];
  for (const match of pending.rows) {
    const providerMatch = findCompletedProviderMatch(match, providerMatches);
    if (
      !providerMatch ||
      providerMatch.status !== 'completed' ||
      providerMatch.home_score == null ||
      providerMatch.away_score == null
    ) {
      continue;
    }

    let firstScorer = officialFirstScorer({
      homeScore: providerMatch.home_score,
      awayScore: providerMatch.away_score,
      provided: providerMatch.first_scorer,
    });
    if (!firstScorer) {
      try {
        const details = await fetchExternalMatchDetails(providerMatch.id);
        firstScorer = officialFirstScorer({
          homeScore: providerMatch.home_score,
          awayScore: providerMatch.away_score,
          timeline: details.timeline,
        });
      } catch {
        // A provider section can be briefly unavailable just after full
        // time. Leave the prediction unresolved and retry on the next
        // bounded reconciliation pass instead of permanently losing the
        // first-scorer reward.
      }
    }
    if (!firstScorer) {
      firstScorer = firstScorerAfterProviderGrace({
        kickoffAt: new Date(match.kickoff_at),
        homeScore: providerMatch.home_score,
        awayScore: providerMatch.away_score,
      });
    }
    if (!firstScorer) continue;

    const updated = await query(
      `UPDATE matches
       SET home_score = $2,
           away_score = $3,
           first_scorer = $4,
           status = 'finished',
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1
         AND status <> 'finished'
         AND status NOT IN ('cancelled', 'postponed')
         AND reward_processed = false
       RETURNING id`,
      [
        match.id,
        providerMatch.home_score,
        providerMatch.away_score,
        firstScorer,
      ],
    );
    if (updated.rowCount === 1) {
      ready.push(match.id);
      await redis.del(
        'cache:matches:upcoming',
        `cache:matches:v3:${match.id}:details`,
      ).catch(() => undefined);
    }
  }
  return ready;
}
