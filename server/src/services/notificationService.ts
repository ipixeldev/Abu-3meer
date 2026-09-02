import { getClient, query } from '../db/pool.js';
import {
  firebaseMessagingIsConfigured,
  sendPushNotification,
} from '../firebase/admin.js';
import {
  isPermanentPushTokenError,
  isTransientPushError,
  normalizePushData,
  notificationPreferenceColumn,
  safePushFailureCode,
  type NotificationCategory,
} from './notificationDomain.js';

export interface DeviceRegistration {
  fcmToken: string;
  installationId?: string;
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
  | 'inactive_users'
  | 'user_specific';

// BullMQ already performs three exponential retries. Persist the same ceiling
// in PostgreSQL so the periodic outbox recovery loop cannot reset a failed job
// and send the same campaign forever.
export const MAX_NOTIFICATION_DELIVERY_ATTEMPTS = 3;

export interface CreateNotificationCampaignInput {
  title: string;
  body: string;
  category: NotificationCategory;
  targetAudience?: NotificationTargetAudience;
  targetTeam?: string | null;
  targetUserId?: string | null;
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

export interface CreateNotificationCampaignOptions {
  rearmCancelled?: boolean;
}

/**
 * Persists the campaign before it is queued, so delayed broadcasts survive
 * API restarts. Source-backed campaigns (for example an Exclusive video) are
 * inserted once and cannot notify the same publication twice.
 */
export async function createNotificationCampaign(
  input: CreateNotificationCampaignInput,
  execute: NotificationCampaignQueryExecutor = query,
  options: CreateNotificationCampaignOptions = {},
): Promise<CreatedNotificationCampaign> {
  const scheduledFor = input.scheduledFor ?? new Date();
  const result = await execute(
    `INSERT INTO notification_campaigns
       (title, body, target_audience, target_team, target_user_id, category,
        data_payload, image_url, scheduled_for, created_by, source_type, source_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
     ON CONFLICT (source_type, source_id)
       WHERE source_type IS NOT NULL AND source_id IS NOT NULL
       DO NOTHING
     RETURNING id, scheduled_for`,
    [
      input.title,
      input.body,
      input.targetAudience ?? 'all',
      input.targetTeam ?? null,
      input.targetUserId ?? null,
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
      // A source may be scheduled, disabled, then enabled again. Only an
      // explicit cancellation is re-armed. Resetting a failed source here
      // would defeat the retry ceiling every time an admin screen resubmits
      // the same content.
      const rearmed = options.rearmCancelled === false
        ? { rowCount: 0, rows: [] }
        : await execute(
          `UPDATE notification_campaigns
         SET title = $3,
             body = $4,
             target_audience = $5,
             target_team = $6,
             target_user_id = $7,
             category = $8,
             data_payload = $9,
             image_url = $10,
             scheduled_for = $11,
             created_by = COALESCE($12, created_by),
             status = 'pending',
             processing_started_at = NULL,
             sent_at = NULL,
             last_error = NULL,
             sent_count = 0,
             failed_count = 0,
             attempt_count = 0,
             last_attempt_at = NULL
         WHERE source_type = $1
           AND source_id = $2
           AND status = 'cancelled'
         RETURNING id, scheduled_for`,
          [
            input.sourceType,
            input.sourceId,
            input.title,
            input.body,
            input.targetAudience ?? 'all',
            input.targetTeam ?? null,
            input.targetUserId ?? null,
            input.category,
            JSON.stringify(input.data ?? {}),
            input.imageUrl?.trim() || null,
            scheduledFor,
            input.createdBy ?? null,
          ],
        );
      if ((rearmed.rowCount ?? 0) > 0) {
        return {
          created: false,
          campaignId: String(rearmed.rows[0].id),
          scheduledFor: new Date(rearmed.rows[0].scheduled_for as Date),
        };
      }

      // Concurrent creates share one durable pending campaign. Failed rows
      // remain eligible only while their persisted attempt budget remains.
      const existing = await execute(
        `SELECT id, scheduled_for
         FROM notification_campaigns
         WHERE source_type = $1
           AND source_id = $2
           AND status IN ('pending', 'failed')
           AND attempt_count < $3`,
        [input.sourceType, input.sourceId, MAX_NOTIFICATION_DELIVERY_ATTEMPTS],
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
  const installationId = input.installationId?.trim() || null;
  const client = await getClient();
  try {
    await client.query('BEGIN');
    let stableDeviceId: string | null = null;
    if (installationId) {
      // Token refreshes can race. Serialize one physical installation and
      // retire its prior token before activating the replacement.
      await client.query(
        `SELECT pg_advisory_xact_lock(hashtext('device-installation:' || $1))`,
        [installationId],
      );
      await client.query(
        `UPDATE devices
         SET is_active = false
         WHERE installation_id = $1
           AND fcm_token <> $2
           AND is_active = true`,
        [installationId, input.fcmToken],
      );
      const stableDevice = await client.query(
        `SELECT id
         FROM devices
         WHERE installation_id = $1
         ORDER BY is_active DESC, last_seen_at DESC, created_at DESC
         LIMIT 1
         FOR UPDATE`,
        [installationId],
      );
      stableDeviceId = stableDevice.rows[0]?.id ?? null;
    }
    let res;
    if (stableDeviceId) {
      const duplicateToken = await client.query(
        `SELECT id FROM devices WHERE fcm_token = $1 AND id <> $2 FOR UPDATE`,
        [input.fcmToken, stableDeviceId],
      );
      const duplicateId = duplicateToken.rows[0]?.id;
      if (duplicateId) {
        // Keep the installation's original device UUID so campaign-delivery
        // uniqueness survives FCM token rotation. Merge any history attached
        // to a previously seen replacement token before removing that row.
        await client.query(
          `INSERT INTO notification_deliveries
             (campaign_id, device_id, status, provider_message_id,
              error_code, error_message, delivered_at, created_at)
           SELECT campaign_id, $1, status, provider_message_id,
                  error_code, error_message, delivered_at, created_at
           FROM notification_deliveries
           WHERE device_id = $2
           ON CONFLICT (campaign_id, device_id) DO UPDATE SET
             status = CASE
               WHEN notification_deliveries.status = 'sent'
                 OR EXCLUDED.status = 'sent' THEN 'sent'
               WHEN notification_deliveries.status = 'processing'
                 OR EXCLUDED.status = 'processing' THEN 'processing'
               ELSE 'failed'
             END,
             provider_message_id = COALESCE(
               notification_deliveries.provider_message_id,
               EXCLUDED.provider_message_id
             ),
             error_code = COALESCE(
               notification_deliveries.error_code,
               EXCLUDED.error_code
             ),
             error_message = COALESCE(
               notification_deliveries.error_message,
               EXCLUDED.error_message
             ),
             delivered_at = COALESCE(
               notification_deliveries.delivered_at,
               EXCLUDED.delivered_at
             )`,
          [stableDeviceId, duplicateId],
        );
        await client.query('DELETE FROM devices WHERE id = $1', [duplicateId]);
      }
      res = await client.query(
        `UPDATE devices
         SET user_id = $2,
             fcm_token = $3,
             installation_id = $4,
             platform = $5,
             app_version = $6,
             device_model = $7,
             os_version = $8,
             locale = $9,
             is_active = true,
             last_seen_at = CURRENT_TIMESTAMP
         WHERE id = $1
         RETURNING id`,
        [
          stableDeviceId,
          userId,
          input.fcmToken,
          installationId,
          input.platform,
          input.appVersion || null,
          input.deviceModel || null,
          input.osVersion || null,
          input.locale || null,
        ],
      );
    } else {
      res = await client.query(
        `INSERT INTO devices
           (user_id, fcm_token, installation_id, platform, app_version,
            device_model, os_version, locale, is_active, last_seen_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, CURRENT_TIMESTAMP)
         ON CONFLICT (fcm_token) DO UPDATE SET
           user_id = EXCLUDED.user_id,
           installation_id = EXCLUDED.installation_id,
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
          installationId,
          input.platform,
          input.appVersion || null,
          input.deviceModel || null,
          input.osVersion || null,
          input.locale || null,
        ],
      );
    }
    await client.query(
      `INSERT INTO notification_preferences (user_id)
       VALUES ($1)
       ON CONFLICT (user_id) DO NOTHING`,
      [userId],
    );
    await client.query('COMMIT');
    return res.rows[0];
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function unregisterDeviceToken(userId: string, fcmToken: string) {
  await query(
    `UPDATE devices SET is_active = false
     WHERE user_id = $1 AND fcm_token = $2`,
    [userId, fcmToken]
  );
}

export async function revokeDeviceInstallation(
  fcmToken: string,
  installationId: string,
  execute: NotificationCampaignQueryExecutor = query,
) {
  // This endpoint remains safe without an auth session because both values
  // are high-entropy installation secrets and the only permitted mutation is
  // deactivation. It lets a durable sign-out intent finish after Firebase Auth
  // has already ended or connectivity returns.
  await execute(
    `UPDATE devices
     SET is_active = false
     WHERE fcm_token = $1
       AND installation_id = $2
       AND is_active = true`,
    [fcmToken, installationId],
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
  target_user_id: string | null;
  category: NotificationCategory;
  data_payload: Record<string, unknown> | null;
  image_url: string | null;
  scheduled_for: Date;
}

interface TargetDeviceRow {
  id: string;
  fcm_token: string;
}

/**
 * Atomically reserves candidate devices before the provider call. Existing
 * sent/processing rows are never reclaimed; only an explicit provider failure
 * can move back to processing for a bounded retry.
 */
export async function claimNotificationDeliveryDevices(
  campaignId: string,
  devices: TargetDeviceRow[],
  execute: NotificationCampaignQueryExecutor = query,
): Promise<TargetDeviceRow[]> {
  if (devices.length === 0) return [];
  const claimed = await execute(
    `INSERT INTO notification_deliveries
       (campaign_id, device_id, status, provider_message_id,
        error_code, error_message, delivered_at)
     SELECT $1, candidate.device_id, 'processing', NULL, NULL, NULL, NULL
     FROM UNNEST($2::uuid[]) AS candidate(device_id)
     WHERE EXISTS (
       SELECT 1
       FROM notification_campaigns campaign
       WHERE campaign.id = $1
         AND campaign.status = 'processing'
     )
     ON CONFLICT (campaign_id, device_id) DO UPDATE SET
       status = 'processing',
       provider_message_id = NULL,
       error_code = NULL,
       error_message = NULL,
       delivered_at = NULL
     WHERE notification_deliveries.status = 'failed'
     RETURNING device_id`,
    [campaignId, devices.map(device => device.id)],
  );
  const claimedIds = new Set(
    claimed.rows.map(row => String(row.device_id)),
  );
  return devices.filter(device => claimedIds.has(device.id));
}

export async function lockNotificationCampaignForDispatch(
  campaignId: string,
  execute: NotificationCampaignQueryExecutor,
): Promise<boolean> {
  const lifecycle = await execute(
    `SELECT status
     FROM notification_campaigns
     WHERE id = $1
     FOR UPDATE`,
    [campaignId],
  );
  return lifecycle.rows[0]?.status === 'processing';
}

export async function processNotificationCampaign(campaignId: string) {
  const claimed = await query<CampaignRow>(
    `UPDATE notification_campaigns
     SET status = 'processing',
         processing_started_at = CURRENT_TIMESTAMP,
         last_error = NULL,
         attempt_count = attempt_count + 1,
         last_attempt_at = CURRENT_TIMESTAMP
     WHERE id = $1 AND (
       (status IN ('pending', 'failed') AND attempt_count < $2) OR
       (status = 'processing' AND processing_started_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes')
     )
     AND attempt_count < $2
     RETURNING *`,
    [campaignId, MAX_NOTIFICATION_DELIVERY_ATTEMPTS]
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

  try {
    if (!firebaseMessagingIsConfigured()) {
      throw new Error(
        'FCM is not configured on this server. Notification delivery is unavailable.',
      );
    }
    const preferenceColumn = notificationPreferenceColumn(campaign.category);
    const preferenceFilter = preferenceColumn
      ? `AND COALESCE(np.${preferenceColumn}, true) = true`
      : '';
    const audienceFilters: Record<string, string> = {
      all: '',
      members_only: `AND EXISTS (
        SELECT 1
        FROM youtube_account_links member_link
        WHERE member_link.user_id = u.id
          AND member_link.is_member = TRUE
          AND member_link.verification_source = 'admin_snapshot'
          AND EXISTS (
            SELECT 1
            FROM youtube_membership_snapshot_state snapshot_state
            JOIN youtube_membership_snapshot_imports snapshot_import
              ON snapshot_import.id = snapshot_state.active_import_id
             AND snapshot_import.expires_at > CURRENT_TIMESTAMP
            WHERE snapshot_state.singleton = TRUE
              AND snapshot_state.active_import_id = member_link.snapshot_import_id
          )
          AND EXISTS (
            SELECT 1 FROM youtube_channel_claims claim
            WHERE claim.user_id = u.id
              AND claim.youtube_channel_id = member_link.youtube_channel_id
              AND claim.status = 'approved'
          )
      )`,
      team_specific: 'AND LOWER(u.supported_team) = LOWER($2)',
      inactive_users: "AND d.last_seen_at < CURRENT_TIMESTAMP - INTERVAL '14 days'",
      user_specific: 'AND u.id = $2',
    };
    const audienceFilter = audienceFilters[campaign.target_audience];
    if (audienceFilter === undefined) {
      throw new Error(`Unsupported notification audience: ${campaign.target_audience}`);
    }
    const targetParams = campaign.target_audience === 'team_specific'
      ? [campaign.target_team]
      : campaign.target_audience === 'user_specific'
        ? [campaign.target_user_id]
        : [];
    const targets = await query<TargetDeviceRow>(
      `SELECT d.id, d.fcm_token
       FROM devices d
       JOIN users u ON u.id = d.user_id
       LEFT JOIN notification_preferences np ON np.user_id = u.id
       WHERE d.is_active = true
         AND COALESCE(np.enabled, true) = true
         AND NOT EXISTS (
           SELECT 1 FROM notification_deliveries nd
           WHERE nd.campaign_id = $1
             AND nd.device_id = d.id
             AND nd.status IN ('processing', 'sent')
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
      const chunk = await claimNotificationDeliveryDevices(
        campaign.id,
        targets.rows.slice(i, i + 500),
      );
      if (chunk.length === 0) continue;
      const dispatchClient = await getClient();
      try {
        await dispatchClient.query('BEGIN');
        // Hold the campaign row through the provider dispatch. Cancellation
        // uses UPDATE on this same row, so either cancellation commits first
        // and this batch is skipped, or this leased batch finishes first and
        // cancellation takes effect before any following batch.
        const dispatchAllowed = await lockNotificationCampaignForDispatch(
          campaign.id,
          (text, params) => dispatchClient.query(text, params),
        );
        if (!dispatchAllowed) {
          await dispatchClient.query('ROLLBACK');
          return { alreadyProcessed: true, sentCount, failedCount };
        }
        const response = await sendPushNotification(
          chunk.map(device => device.fcm_token),
          campaign.title,
          campaign.body,
          data,
          { imageUrl: campaign.image_url },
        );
        sentCount += response.successCount;
        failedCount += response.failureCount;

        for (let index = 0; index < chunk.length; index += 1) {
          const device = chunk[index];
          const result = response.responses[index];
          // A missing per-device result is an unknown provider outcome. Keep
          // the committed pre-send reservation so no retry duplicates it.
          if (!result) continue;
          const errorCode = result.success
            ? null
            : safePushFailureCode(result.error);
          if (isTransientPushError(errorCode || undefined)) {
            transientFailureCount += 1;
          }
          await dispatchClient.query(
            `UPDATE notification_deliveries
             SET status = $3,
                 provider_message_id = $4,
                 error_code = $5,
                 error_message = $6,
                 delivered_at = CASE
                   WHEN $3 = 'sent' THEN CURRENT_TIMESTAMP
                   ELSE NULL
                 END
             WHERE campaign_id = $1
               AND device_id = $2
               AND status = 'processing'`,
            [
              campaign.id,
              device.id,
              result.success ? 'sent' : 'failed',
              result.messageId || null,
              errorCode,
              result.error?.message || null,
            ],
          );
          if (isPermanentPushTokenError(errorCode || undefined)) {
            await dispatchClient.query(
              'UPDATE devices SET is_active = false WHERE id = $1',
              [device.id],
            );
          }
        }
        await dispatchClient.query('COMMIT');
      } catch (error) {
        await dispatchClient.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        dispatchClient.release();
      }
    }

    const totals = await query(
      `SELECT
         COUNT(*) FILTER (WHERE status = 'sent')::int AS sent_count,
         COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_count,
         COUNT(*) FILTER (WHERE status = 'processing')::int AS processing_count
       FROM notification_deliveries
       WHERE campaign_id = $1`,
      [campaign.id]
    );
    sentCount = totals.rows[0].sent_count;
    failedCount = totals.rows[0].failed_count;
    const processingCount = totals.rows[0].processing_count;
    if (processingCount > 0) {
      // An exception or missing per-token provider response after reservation
      // has an unknown outcome. Never mark that campaign 0/0 complete and
      // never reclaim those devices for an unsafe duplicate send.
      throw new Error(
        `${processingCount} push delivery outcome(s) remain unconfirmed.`,
      );
    }
    if (transientFailureCount > 0) {
      throw new Error(
        `${transientFailureCount} transient push delivery failure(s); retry scheduled.`,
      );
    }
    await query(
      `UPDATE notification_campaigns
       SET status = 'completed', sent_count = $2, failed_count = $3,
           sent_at = CURRENT_TIMESTAMP, processing_started_at = NULL
       WHERE id = $1 AND status = 'processing'`,
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
       WHERE id = $1 AND status <> 'cancelled'`,
      [campaign.id, error instanceof Error ? error.message.slice(0, 1000) : 'Unknown push error']
    );
    throw error;
  }
}
