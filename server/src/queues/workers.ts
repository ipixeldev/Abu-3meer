import { Queue, Worker } from 'bullmq';
import { redis } from '../redis/client.js';
import { settleMatchPredictions } from '../services/predictionService.js';
import { processNotificationCampaign } from '../services/notificationService.js';

export const matchSettlementQueue = new Queue('match-settlement', { connection: redis });
export const notificationQueue = new Queue('notification-broadcast', { connection: redis });

export function startWorkers() {
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
}
