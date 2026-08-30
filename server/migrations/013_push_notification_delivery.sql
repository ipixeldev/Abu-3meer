-- 013_push_notification_delivery.sql
-- Durable notification preferences, campaign targeting, and provider delivery audit.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS locale VARCHAR(20);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT TRUE NOT NULL,
    match_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    challenge_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    reward_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    news_enabled BOOLEAN DEFAULT FALSE NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

ALTER TABLE notification_campaigns
    ADD COLUMN IF NOT EXISTS category VARCHAR(30) DEFAULT 'general' NOT NULL,
    ADD COLUMN IF NOT EXISTS last_error TEXT,
    ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'notification_campaigns_category_check'
    ) THEN
        ALTER TABLE notification_campaigns
            ADD CONSTRAINT notification_campaigns_category_check
            CHECK (category IN ('match', 'challenge', 'reward', 'news', 'general'));
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS notification_deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL REFERENCES notification_campaigns(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL CHECK (status IN ('sent', 'failed')),
    provider_message_id TEXT,
    error_code VARCHAR(150),
    error_message TEXT,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    UNIQUE (campaign_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_campaign
    ON notification_deliveries(campaign_id, status);
