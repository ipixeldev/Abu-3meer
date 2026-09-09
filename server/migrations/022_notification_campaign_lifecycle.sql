-- Durable cancellation and retry lifecycle for notification outbox records.

ALTER TABLE notification_campaigns
  DROP CONSTRAINT IF EXISTS notification_campaigns_status_check;

ALTER TABLE notification_campaigns
  ADD CONSTRAINT notification_campaigns_status_check
  CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled'));

DROP INDEX IF EXISTS idx_notification_campaigns_pending_schedule;
CREATE INDEX idx_notification_campaigns_pending_schedule
  ON notification_campaigns(status, scheduled_for)
  WHERE status IN ('pending', 'failed');
