import { query } from '../db/pool.js';
import { sendPushNotification } from '../firebase/admin.js';
import {
  isPermanentPushTokenError,
  isTransientPushError,
  normalizePushData,
  notificationPreferenceColumn,
  safePushFailureCode,
  summarizePushFailures,
  type NotificationCategory,
} from './notificationDomain.js';

export interface DeviceRegistration {
  fcmToken: string;
  platform: 'ios' | 'android' | 'web';
  appVersion?: string;
  deviceModel?: string;
  osVersion?: string;
  locale?: string;
}

export interface NotificationPreferences {
  enabled: boolean;
  matchEnabled: boolean;
  challengeEnabled: boolean;
  rewardEnabled: boolean;
  newsEnabled: boolean;
}

export type NotificationTargetAudience =
  | 'all'
  | 'members_only'
  | 'team_specific'
  | 'inactive_users';

export interface CreateNotificationCampaignInput {
  title: string;
  body: string;
  category: NotificationCategory;
  targetAudience?: NotificationTargetAudience;
  targetTeam?: string | null;
  data?: Record<string, unknown>;
  imageUrl?: string | null;
  scheduledFor?: Date;
  createdBy?: string | null;
  sourceType?: string | null;
  sourceId?: string | null;
}

export interface CreatedNotificationCampaign {
  created: boolean;
  campaignId: string | null;
  scheduledFor: Date;
}

export type NotificationCampaignQueryExecutor = (
  text: string,
  params?: any[]
) => Promise<{ rowCount: number | null; rows: Array<Record<string, unknown>> }>;

/**
 * Persists the campaign before it is queued, so delayed broadcasts survive
 * API restarts. Source-backed campaigns (for example an Exclusive video) are
 * inserted once and cannot notify the same publication twice.
 */
export async function createNotificationCampaign(
  input: CreateNotificationCampaignInput,
  execute: NotificationCampaignQueryExecutor = query
): Promise<CreatedNotificationCampaign> {
  const scheduledFor = input.scheduledFor ?? new Date();
  const result = await execute(
    `INSERT INTO notification_campaigns
       (title, body, target_audience, target_team, category, data_payload,
        image_url, scheduled_for, created_by, source_type, source_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
     ON CONFLICT (source_type, source_id)
       WHERE source_type IS NOT NULL AND source_id IS NOT NULL
       DO NOTHING
     RETURNING id, scheduled_for`,
    [
      input.title,
      input.body,
      input.targetAudience ?? 'all',
      input.targetTeam ?? null,
      input.category,
      JSON.stringify(input.data ?? {}),
      input.imageUrl?.trim() || null,
      scheduledFor,
      input.createdBy ?? null,
      input.sourceType ?? null,
      input.sourceId ?? null,
    ]
  );
  if (result.rowCount === 0) {
    if (input.sourceType && input.sourceId) {
      // A source may be scheduled, disabled, then enabled again. Re-arm a
      // pending/failed/cancelled outbox record instead of creating a second
      // campaign or leaving the source permanently muted by the unique key.
      const existing = await execute(
        `UPDATE notification_campaigns
         SET title = $3,
             body = $4,
             target_audience = $5,
             target_team = $6,
             category = $7,
             data_payload = $8,
             image_url = $9,
             scheduled_for = $10,
             created_by = COALESCE($11, created_by),
             status = 'pending',
             processing_started_at = NULL,
             sent_at = NULL,
             last_error = NULL,
             sent_count = 0,
             failed_count = 0
         WHERE source_type = $1
           AND source_id = $2
           AND status IN ('pending', 'failed', 'cancelled')
         RETURNING id, scheduled_for`,
        [
          input.sourceType,
          input.sourceId,
          input.title,
          input.body,
          input.targetAudience ?? 'all',
          input.targetTeam ?? null,
          input.category,
          JSON.stringify(input.data ?? {}),
          input.imageUrl?.trim() || null,
          scheduledFor,
          input.createdBy ?? null,
        ]
      );
      if ((existing.rowCount ?? 0) > 0) {
        return {
          created: false,
          campaignId: String(existing.rows[0].id),
          scheduledFor: new Date(existing.rows[0].scheduled_for as Date),
        };
      }
    }
    return { created: false, campaignId: null, scheduledFor };
  }
  return {
    created: true,
    campaignId: String(result.rows[0].id),
    scheduledFor: new Date(result.rows[0].scheduled_for as Date),
  };
}

export async function cancelNotificationCampaignBySource(
  sourceType: string,
  sourceId: string,
  execute: NotificationCampaignQueryExecutor = query,
): Promise<string[]> {
  const result = await execute(
    `UPDATE notification_campaigns
     SET status = 'cancelled', processing_started_at = NULL, last_error = NULL
     WHERE source_type = $1
       AND source_id = $2
       AND status IN ('pending', 'failed', 'processing')
     RETURNING id`,
    [sourceType, sourceId],
  );
  return result.rows.map((row) => String(row.id));
}

export async function registerDeviceToken(userId: string, input: DeviceRegistration) {
  const res = await query(
    `INSERT INTO devices
       (user_id, fcm_token, platform, app_version, device_model, os_version, locale, is_active, last_seen_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, true, CURRENT_TIMESTAMP)
     ON CONFLICT (fcm_token) DO UPDATE SET
       user_id = EXCLUDED.user_id,
       platform = EXCLUDED.platform,
       app_version = EXCLUDED.app_version,
       device_model = EXCLUDED.device_model,
       os_version = EXCLUDED.os_version,
       locale = EXCLUDED.locale,
       is_active = true,
       last_seen_at = CURRENT_TIMESTAMP
     RETURNING id`,
    [
      userId,
      input.fcmToken,
      input.platform,
      input.appVersion || null,
      input.deviceModel || null,
      input.osVersion || null,
      input.locale || null,
    ]
  );
  await query(
    `INSERT INTO notification_preferences (user_id)
     VALUES ($1)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId]
  );
  return res.rows[0];
}

export async function unregisterDeviceToken(userId: string, fcmToken: string) {
  await query(
    `UPDATE devices SET is_active = false
     WHERE user_id = $1 AND fcm_token = $2`,
    [userId, fcmToken]
  );
}

export async function getNotificationPreferences(userId: string): Promise<NotificationPreferences> {
  const res = await query(
    `INSERT INTO notification_preferences (user_id)
     VALUES ($1)
     ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
     RETURNING enabled, match_enabled, challenge_enabled, reward_enabled, news_enabled`,
    [userId]
  );
  const row = res.rows[0];
  return {
    enabled: row.enabled,
    matchEnabled: row.match_enabled,
    challengeEnabled: row.challenge_enabled,
    rewardEnabled: row.reward_enabled,
    newsEnabled: row.news_enabled,
  };
}

export async function updateNotificationPreferences(
  userId: string,
  preferences: NotificationPreferences
): Promise<NotificationPreferences> {
  await query(
    `INSERT INTO notification_preferences
       (user_id, enabled, match_enabled, challenge_enabled, reward_enabled, news_enabled, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
     ON CONFLICT (user_id) DO UPDATE SET
       enabled = EXCLUDED.enabled,
       match_enabled = EXCLUDED.match_enabled,
       challenge_enabled = EXCLUDED.challenge_enabled,
       reward_enabled = EXCLUDED.reward_enabled,
       news_enabled = EXCLUDED.news_enabled,
       updated_at = CURRENT_TIMESTAMP`,
    [
      userId,
      preferences.enabled,
      preferences.matchEnabled,
      preferences.challengeEnabled,
      preferences.rewardEnabled,
      preferences.newsEnabled,
    ]
  );
  return preferences;
}

interface CampaignRow {
  id: string;
  title: string;
  body: string;
  target_audience: string;
  target_team: string | null;
  category: NotificationCategory;
  data_payload: Record<string, unknown> | null;
  image_url: string | null;
  scheduled_for: Date;
}

interface TargetDeviceRow {
  id: string;
  fcm_token: string;
}

export async function processNotificationCampaign(campaignId: string) {
  const claimed = await query<CampaignRow>(
    `UPDATE notification_campaigns
     SET status = 'processing', processing_started_at = CURRENT_TIMESTAMP, last_error = NULL
     WHERE id = $1 AND (
       status IN ('pending', 'failed') OR
       (status = 'processing' AND processing_started_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes')
     )
     RETURNING *`,
    [campaignId]
  );
  if (claimed.rowCount === 0) {
    const existing = await query(
      'SELECT status, sent_count, failed_count FROM notification_campaigns WHERE id = $1',
      [campaignId]
    );
    if (existing.rowCount === 0) throw new Error(`Notification campaign ${campaignId} not found.`);
    return {
      alreadyProcessed: true,
      sentCount: existing.rows[0].sent_count,
      failedCount: existing.rows[0].failed_count,
    };
  }

  const campaign = claimed.rows[0];
  const preferenceColumn = notificationPreferenceColumn(campaign.category);
  const preferenceFilter = preferenceColumn ? `AND COALESCE(np.${preferenceColumn}, true) = true` : '';
  const audienceFilter = {
    all: '',
    members_only: 'AND u.is_youtube_member = true',
    team_specific: 'AND LOWER(u.supported_team) = LOWER($2)',
    inactive_users: "AND d.last_seen_at < CURRENT_TIMESTAMP - INTERVAL '14 days'",
  }[campaign.target_audience] ?? '';
  const targetParams = campaign.target_audience === 'team_specific' ? [campaign.target_team] : [];

  try {
    const targets = await query<TargetDeviceRow>(
      `SELECT d.id, d.fcm_token
       FROM devices d
       JOIN users u ON u.id = d.user_id
       LEFT JOIN notification_preferences np ON np.user_id = u.id
       WHERE d.is_active = true
         AND COALESCE(np.enabled, true) = true
         AND NOT EXISTS (
           SELECT 1 FROM notification_deliveries nd
           WHERE nd.campaign_id = $1 AND nd.device_id = d.id AND nd.status = 'sent'
         )
         ${preferenceFilter}
         ${audienceFilter}
       ORDER BY d.created_at`,
      [campaign.id, ...targetParams]
    );

    let sentCount = 0;
    let failedCount = 0;
    let transientFailureCount = 0;
    const data = normalizePushData({
      ...campaign.data_payload,
      campaignId: campaign.id,
      category: campaign.category,
      imageUrl: campaign.image_url,
    });

    for (let i = 0; i < targets.rows.length; i += 500) {
      // A scheduled source can be disabled after BullMQ has already claimed
      // the job. Re-check the durable lifecycle before every provider batch.
      const lifecycle = await query<{ status: string }>(
        'SELECT status FROM notification_campaigns WHERE id = $1',
        [campaign.id],
      );
      if (lifecycle.rows[0]?.status === 'cancelled') {
        return { alreadyProcessed: true, sentCount, failedCount };
      }
      const chunk = targets.rows.slice(i, i + 500);
      const response = await sendPushNotification(
        chunk.map(device => device.fcm_token),
        campaign.title,
        campaign.body,
        data,
        { imageUrl: campaign.image_url }
      );
      sentCount += response.successCount;
      failedCount += response.failureCount;

      for (let index = 0; index < chunk.length; index += 1) {
        const device = chunk[index];
        const result = response.responses[index];
        const errorCode = result?.success
          ? null
          : safePushFailureCode(result?.error);
        if (isTransientPushError(errorCode || undefined)) {
          transientFailureCount += 1;
        }
        await query(
          `INSERT INTO notification_deliveries
             (campaign_id, device_id, status, provider_message_id, error_code, error_message, delivered_at)
           VALUES ($1, $2, $3, $4, $5, $6, CASE WHEN $3 = 'sent' THEN CURRENT_TIMESTAMP ELSE NULL END)
           ON CONFLICT (campaign_id, device_id) DO UPDATE SET
             status = EXCLUDED.status,
             provider_message_id = EXCLUDED.provider_message_id,
             error_code = EXCLUDED.error_code,
             error_message = EXCLUDED.error_message,
             delivered_at = EXCLUDED.delivered_at`,
          [
            campaign.id,
            device.id,
            result?.success ? 'sent' : 'failed',
            result?.messageId || null,
            errorCode,
            result?.error?.message || null,
          ]
        );
        if (isPermanentPushTokenError(errorCode || undefined)) {
          await query('UPDATE devices SET is_active = false WHERE id = $1', [device.id]);
        }
      }
    }

    const totals = await query(
      `SELECT
         COUNT(*) FILTER (WHERE status = 'sent')::int AS sent_count,
         COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_count
       FROM notification_deliveries
       WHERE campaign_id = $1`,
      [campaign.id]
    );
    sentCount = totals.rows[0].sent_count;
    failedCount = totals.rows[0].failed_count;
    if (transientFailureCount > 0) {
      throw new Error(
        `${transientFailureCount} transient push delivery failure(s); retry scheduled.`,
      );
    }
    await query(
      `UPDATE notification_campaigns
       SET status = 'completed', sent_count = $2, failed_count = $3,
           sent_at = CURRENT_TIMESTAMP, processing_started_at = NULL
       WHERE id = $1`,
      [campaign.id, sentCount, failedCount]
    );
    return { alreadyProcessed: false, sentCount, failedCount };
  } catch (error) {
    await query(
      `UPDATE notification_campaigns
       SET status = 'failed',
           last_error = $2,
           processing_started_at = NULL,
           sent_count = (
             SELECT COUNT(*)::int FROM notification_deliveries
             WHERE campaign_id = $1 AND status = 'sent'
           ),
           failed_count = (
             SELECT COUNT(*)::int FROM notification_deliveries
             WHERE campaign_id = $1 AND status = 'failed'
           )
       WHERE id = $1`,
      [campaign.id, error instanceof Error ? error.message.slice(0, 1000) : 'Unknown push error']
    );
    throw error;
  }
}

export async function sendTestNotification(userId: string) {
  const devices = await query<TargetDeviceRow>(
    `SELECT id, fcm_token FROM devices
     WHERE user_id = $1 AND is_active = true
     ORDER BY last_seen_at DESC
     LIMIT 10`,
    [userId]
  );
  if (devices.rowCount === 0) {
    return { sentCount: 0, failedCount: 0, noRegisteredDevice: true };
  }
  const response = await sendPushNotification(
    devices.rows.map(device => device.fcm_token),
    'Abu 3meer ⚽',
    'Push notifications are connected to your device.',
    { category: 'general', route: '/settings', test: 'true' }
  );
  const diagnostics = summarizePushFailures(
    response.responses.filter(result => !result.success).map(result => result.error)
  );
  for (let index = 0; index < devices.rows.length; index += 1) {
    const result = response.responses[index];
    if (!result?.success && isPermanentPushTokenError(safePushFailureCode(result.error))) {
      await query('UPDATE devices SET is_active = false WHERE id = $1', [devices.rows[index].id]);
    }
  }
  if (response.failureCount > 0) {
    // Codes identify the corrective action without leaking FCM registration
    // tokens, APNs tokens, service-account values, or provider error bodies.
    console.error(
      `[FCM Test] ${response.failureCount}/${devices.rows.length} delivery attempt(s) failed; codes=${diagnostics.failureCodes.join(',') || 'unknown'}`
    );
  }
  return {
    sentCount: response.successCount,
    failedCount: response.failureCount,
    noRegisteredDevice: false,
    diagnosticVersion: 2,
    ...diagnostics,
  };
}
