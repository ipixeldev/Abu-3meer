-- 020_notification_campaign_scheduling.sql
-- Durable delayed broadcasts, optional rich-media URLs, and source-level
-- deduplication for automatically generated campaigns.

ALTER TABLE notification_campaigns
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS source_type VARCHAR(50),
    ADD COLUMN IF NOT EXISTS source_id VARCHAR(255);

UPDATE notification_campaigns
SET scheduled_for = COALESCE(sent_at, created_at, CURRENT_TIMESTAMP)
WHERE scheduled_for IS NULL;

ALTER TABLE notification_campaigns
    ALTER COLUMN scheduled_for SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN scheduled_for SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notification_campaigns_pending_schedule
    ON notification_campaigns(status, scheduled_for)
    WHERE status = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_campaigns_source
    ON notification_campaigns(source_type, source_id)
    WHERE source_type IS NOT NULL AND source_id IS NOT NULL;
