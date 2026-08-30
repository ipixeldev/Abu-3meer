-- Bound provider retries so a permanently failing campaign cannot be
-- re-created by periodic outbox recovery forever. Also allow durable,
-- preference-aware notifications for one prediction owner.

ALTER TABLE notification_campaigns
  ADD COLUMN IF NOT EXISTS target_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS attempt_count INTEGER DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS installation_id VARCHAR(128);

ALTER TABLE devices
  DROP CONSTRAINT IF EXISTS devices_installation_id_check;

ALTER TABLE devices
  ADD CONSTRAINT devices_installation_id_check
  CHECK (
    installation_id IS NULL
    OR installation_id ~ '^[A-Za-z0-9_-]{16,128}$'
  );

CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_one_active_installation
  ON devices(installation_id)
  WHERE installation_id IS NOT NULL AND is_active = true;

-- Reserve a device delivery before handing it to FCM. A worker crash after
-- provider acceptance therefore leaves a durable `processing` tombstone and
-- cannot resend the same campaign to the same device on recovery.
ALTER TABLE notification_deliveries
  DROP CONSTRAINT IF EXISTS notification_deliveries_status_check;

ALTER TABLE notification_deliveries
  ADD CONSTRAINT notification_deliveries_status_check
  CHECK (status IN ('processing', 'sent', 'failed'));

ALTER TABLE notification_campaigns
  DROP CONSTRAINT IF EXISTS notification_campaigns_target_audience_check;

-- A nullable CHECK allowed legacy NULL audiences to behave like `all` in the
-- worker. Quarantine every unsent malformed campaign before normalizing its
-- shape so a deployment can never broaden an unknown audience to all users.
UPDATE notification_campaigns
SET status = 'failed',
    attempt_count = 3,
    processing_started_at = NULL,
    last_attempt_at = COALESCE(last_attempt_at, CURRENT_TIMESTAMP),
    last_error = COALESCE(
      NULLIF(last_error, ''),
      'Quarantined because the notification audience was invalid'
    )
WHERE status IN ('pending', 'failed', 'processing')
  AND (
    target_audience IS NULL
    OR target_audience NOT IN (
      'all', 'members_only', 'team_specific', 'inactive_users', 'user_specific'
    )
    OR (target_audience = 'user_specific' AND target_user_id IS NULL)
    OR (target_audience <> 'user_specific' AND target_user_id IS NOT NULL)
  );

UPDATE notification_campaigns
SET target_audience = 'all', target_user_id = NULL
WHERE target_audience IS NULL
   OR target_audience NOT IN (
     'all', 'members_only', 'team_specific', 'inactive_users', 'user_specific'
   )
   OR (target_audience = 'user_specific' AND target_user_id IS NULL)
   OR (target_audience <> 'user_specific' AND target_user_id IS NOT NULL);

ALTER TABLE notification_campaigns
  ALTER COLUMN target_audience SET DEFAULT 'all',
  ALTER COLUMN target_audience SET NOT NULL,
  ADD CONSTRAINT notification_campaigns_target_audience_check
  CHECK (target_audience IN (
    'all', 'members_only', 'team_specific', 'inactive_users', 'user_specific'
  ));

ALTER TABLE notification_campaigns
  DROP CONSTRAINT IF EXISTS notification_campaigns_user_target_check;

ALTER TABLE notification_campaigns
  ADD CONSTRAINT notification_campaigns_user_target_check
  CHECK (
    (target_audience = 'user_specific' AND target_user_id IS NOT NULL)
    OR
    (target_audience <> 'user_specific' AND target_user_id IS NULL)
  );

ALTER TABLE notification_campaigns
  DROP CONSTRAINT IF EXISTS notification_campaigns_attempt_count_check;

ALTER TABLE notification_campaigns
  ADD CONSTRAINT notification_campaigns_attempt_count_check
  CHECK (attempt_count >= 0);

-- Rows left behind by the pre-budget worker may already have been re-enqueued
-- an unknown number of times. Quarantine failed/stuck work and overdue pending
-- broadcasts during this migration so deploying the fix cannot replay an old
-- campaign even once. Future scheduled campaigns are deliberately preserved.
UPDATE notification_campaigns
SET status = 'failed',
    attempt_count = 3,
    processing_started_at = NULL,
    last_attempt_at = COALESCE(last_attempt_at, CURRENT_TIMESTAMP),
    last_error = COALESCE(
      NULLIF(last_error, ''),
      'Quarantined during bounded notification retry migration'
    )
WHERE status IN ('failed', 'processing')
   OR (
     status = 'pending'
     AND scheduled_for <= CURRENT_TIMESTAMP
   );

CREATE INDEX IF NOT EXISTS idx_notification_campaigns_target_user
  ON notification_campaigns(target_user_id, status)
  WHERE target_user_id IS NOT NULL;

DROP INDEX IF EXISTS idx_notification_campaigns_pending_schedule;
CREATE INDEX idx_notification_campaigns_pending_schedule
  ON notification_campaigns(status, scheduled_for)
  WHERE status IN ('pending', 'failed') AND attempt_count < 3;
