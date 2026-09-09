import { Queue, Worker } from 'bullmq';
import { redis } from '../redis/client.js';
import { settleMatchPredictions } from '../services/predictionService.js';
import {
  MAX_NOTIFICATION_DELIVERY_ATTEMPTS,
  processNotificationCampaign,
} from '../services/notificationService.js';
import { notificationDelayMs } from '../services/notificationDomain.js';
import { query } from '../db/pool.js';
import {
  reconcileCompletedExternalMatches,
  recoverFinishedMatchSettlements,
} from '../services/matchReconciliationService.js';

export const matchSettlementQueue = new Queue('match-settlement', { connection: redis });
export const notificationQueue = new Queue('notification-broadcast', { connection: redis });

const matchSettlementJobOptions = {
  attempts: 5,
  backoff: { type: 'exponential' as const, delay: 5000 },
  removeOnComplete: 1000,
  removeOnFail: 1000,
};

const notificationJobOptions = {
  attempts: 3,
  backoff: { type: 'exponential' as const, delay: 5000 },
  removeOnComplete: 1000,
  removeOnFail: 1000,
};

export async function enqueueNotificationCampaign(
  campaignId: string,
  scheduledFor: Date
) {
  const jobId = `notification-${campaignId}`;
  const existing = await notificationQueue.getJob(jobId);
  if (existing) {
    const state = await existing.getState();
    if (state === 'delayed') {
      // Once BullMQ has begun its own retry sequence, its delayed timestamp is
      // the retry backoff rather than the campaign schedule. Never replace
      // that job: doing so resets attemptsMade and recreates an unbounded loop.
      if (existing.attemptsMade > 0) return existing;
      const existingRunAt = existing.timestamp + existing.delay;
      if (Math.abs(existingRunAt - scheduledFor.getTime()) <= 1000) {
        return existing;
      }
      await existing.remove();
    } else if (state === 'completed' || state === 'failed') {
      await existing.remove();
    } else {
      return existing;
    }
  }
  return await notificationQueue.add(
    'broadcast',
    { campaignId },
    {
      ...notificationJobOptions,
      jobId,
      delay: notificationDelayMs(scheduledFor),
    }
  );
}

export function matchSettlementJobId(matchId: string): string {
  return `match-settlement-${matchId.replace(/[^A-Za-z0-9_-]/g, '-')}`;
}

export async function enqueueMatchSettlement(matchId: string) {
  const jobId = matchSettlementJobId(matchId);
  const existing = await matchSettlementQueue.getJob(jobId);
  if (existing) {
    const state = await existing.getState();
    if (state === 'waiting' || state === 'active' || state === 'delayed') {
      return existing;
    }
    await existing.remove();
  }
  return await matchSettlementQueue.add(
    'settle',
    { matchId },
    { ...matchSettlementJobOptions, jobId },
  );
}

export async function cancelNotificationCampaignJob(campaignId: string) {
  const job = await notificationQueue.getJob(`notification-${campaignId}`);
  if (!job) return false;
  const state = await job.getState();
  if (state === 'active') return false;
  await job.remove();
  return true;
}

export async function recoverPendingNotificationCampaigns() {
  const pending = await query<{ id: string; scheduled_for: Date }>(
    `SELECT id, scheduled_for
     FROM notification_campaigns
     WHERE (status IN ('pending', 'failed')
            AND attempt_count < $1)
        OR (status = 'processing'
            AND processing_started_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes'
            AND attempt_count < $1)
     ORDER BY scheduled_for
     LIMIT 5000`,
    [MAX_NOTIFICATION_DELIVERY_ATTEMPTS],
  );
  let recovered = 0;
  for (const campaign of pending.rows) {
    try {
      await enqueueNotificationCampaign(
        campaign.id,
        new Date(campaign.scheduled_for)
      );
      recovered += 1;
    } catch (error) {
      console.error(
        `[Worker: Notifications] Could not enqueue durable campaign ${campaign.id}:`,
        error instanceof Error ? error.message : 'unknown queue error',
      );
    }
  }
  if (recovered > 0) {
    console.log(
      `[Worker: Notifications] Recovered ${recovered} pending campaign(s).`
    );
  }
  return { found: pending.rowCount ?? pending.rows.length, recovered };
}

async function processMatchSettlement(matchId: string) {
  const result = await settleMatchPredictions(matchId);
  for (const campaign of result.notificationCampaigns) {
    if (!campaign.campaignId) continue;
    try {
      await enqueueNotificationCampaign(
        campaign.campaignId,
        campaign.scheduledFor,
      );
    } catch (error) {
      // The campaign is already durable. The bounded outbox recovery loop
      // will enqueue it after a temporary Redis failure.
      console.error(
        `[Worker: Match Settlement] Could not enqueue result campaign ${campaign.campaignId}:`,
        error instanceof Error ? error.message : 'unknown queue error',
      );
    }
  }
  return result;
}

export async function startWorkers() {
  const matchWorker = new Worker(
    'match-settlement',
    async (job) => {
      const { matchId } = job.data;
      console.log(`[Worker: Match Settlement] Processing matchId: ${matchId}`);
      const res = await processMatchSettlement(matchId);
      console.log(`[Worker: Match Settlement] Succeeded: ${res.processedCount} predictions resolved, ${res.pointsDistributed} points awarded.`);
      return res;
    },
    { connection: redis, concurrency: 2 }
  );

  const notificationWorker = new Worker(
    'notification-broadcast',
    async (job) => {
      const { campaignId } = job.data;
      console.log(`[Worker: Notifications] Processing campaign: ${campaignId}`);
      const res = await processNotificationCampaign(campaignId);
      console.log(`[Worker: Notifications] Finished. Sent: ${res.sentCount}, Failed: ${res.failedCount}`);
      return res;
    },
    { connection: redis, concurrency: 1 }
  );

  matchWorker.on('failed', (job, err) => {
    console.error(`[Worker: Match Settlement] Job ${job?.id} failed:`, err);
  });

  notificationWorker.on('failed', (job, err) => {
    console.error(`[Worker: Notifications] Job ${job?.id} failed:`, err);
  });

  console.log('[BullMQ Workers] Background workers started.');
  await recoverPendingNotificationCampaigns();
  let recoveryRunning = false;
  const recoveryTimer = setInterval(async () => {
    if (recoveryRunning) return;
    recoveryRunning = true;
    try {
      await recoverPendingNotificationCampaigns();
    } catch (error) {
      console.error(
        '[Worker: Notifications] Periodic outbox recovery failed:',
        error instanceof Error ? error.message : 'unknown recovery error',
      );
    } finally {
      recoveryRunning = false;
    }
  }, 60_000);
  recoveryTimer.unref();

  let reconciliationRunning = false;
  const reconcile = async () => {
    if (reconciliationRunning) return;
    reconciliationRunning = true;
    try {
      // Recover PostgreSQL-backed work first. A slow or unavailable football
      // provider must never delay settlement of a manually managed result.
      const recovery = await recoverFinishedMatchSettlements(
        enqueueMatchSettlement,
      );
      if (recovery.enqueued > 0 || recovery.failed > 0) {
        console.log(
          `[Worker: Match Settlement] Recovery found ${recovery.found}; ` +
          `enqueued ${recovery.enqueued}; failed ${recovery.failed}.`,
        );
      }
    } catch (error) {
      console.error(
        '[Worker: Match Settlement] Periodic recovery failed:',
        error instanceof Error ? error.message : 'unknown reconciliation error',
      );
    }
    try {
      const reconciledMatchIds = await reconcileCompletedExternalMatches();
      // Newly imported final scores were not present in the recovery query at
      // the beginning of this pass, so enqueue them immediately. Any queue
      // failure remains recoverable from PostgreSQL on the next pass.
      const recovery = await recoverFinishedMatchSettlements(
        enqueueMatchSettlement,
        async () => reconciledMatchIds,
      );
      if (recovery.enqueued > 0 || recovery.failed > 0) {
        console.log(
          `[Worker: Match Reconciliation] Imported ${recovery.found}; ` +
          `enqueued ${recovery.enqueued}; failed ${recovery.failed}.`,
        );
      }
    } catch (error) {
      console.error(
        '[Worker: Match Reconciliation] Provider reconciliation failed:',
        error instanceof Error ? error.message : 'unknown reconciliation error',
      );
    } finally {
      reconciliationRunning = false;
    }
  };
  const initialReconciliation = setTimeout(() => void reconcile(), 5_000);
  initialReconciliation.unref();
  const reconciliationTimer = setInterval(() => void reconcile(), 60_000);
  reconciliationTimer.unref();

  return async () => {
    clearTimeout(initialReconciliation);
    clearInterval(reconciliationTimer);
    clearInterval(recoveryTimer);
    await Promise.all([
      matchWorker.close(),
      notificationWorker.close(),
    ]);
  };
}
