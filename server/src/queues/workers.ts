import { Queue, Worker } from 'bullmq';
import { redis } from '../redis/client.js';
import { settleMatchPredictions } from '../services/predictionService.js';
import { processNotificationCampaign } from '../services/notificationService.js';
import { notificationDelayMs } from '../services/notificationDomain.js';
import { query } from '../db/pool.js';

export const matchSettlementQueue = new Queue('match-settlement', { connection: redis });
export const notificationQueue = new Queue('notification-broadcast', { connection: redis });

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
     WHERE status IN ('pending', 'failed')
        OR (status = 'processing'
            AND processing_started_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes')
     ORDER BY scheduled_for
     LIMIT 5000`
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

export async function startWorkers() {
  const matchWorker = new Worker(
    'match-settlement',
    async (job) => {
      const { matchId } = job.data;
      console.log(`[Worker: Match Settlement] Processing matchId: ${matchId}`);
      const res = await settleMatchPredictions(matchId);
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
}
