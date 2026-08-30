import { query } from '../db/pool.js';
import { sendPushNotification } from '../firebase/admin.js';
import {
  isPermanentPushTokenError,
  normalizePushData,
  notificationPreferenceColumn,
  summarizePushFailureCodes,
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
    const data = normalizePushData({
      ...campaign.data_payload,
      campaignId: campaign.id,
      category: campaign.category,
    });

    for (let i = 0; i < targets.rows.length; i += 500) {
      const chunk = targets.rows.slice(i, i + 500);
      const response = await sendPushNotification(
        chunk.map(device => device.fcm_token),
        campaign.title,
        campaign.body,
        data
      );
      sentCount += response.successCount;
      failedCount += response.failureCount;

      for (let index = 0; index < chunk.length; index += 1) {
        const device = chunk[index];
        const result = response.responses[index];
        const errorCode = result?.error?.code || null;
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
       SET status = 'failed', last_error = $2, processing_started_at = NULL
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
  const diagnostics = summarizePushFailureCodes(
    response.responses.map(result => result.error?.code)
  );
  for (let index = 0; index < devices.rows.length; index += 1) {
    if (isPermanentPushTokenError(response.responses[index]?.error?.code)) {
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
    ...diagnostics,
  };
}
