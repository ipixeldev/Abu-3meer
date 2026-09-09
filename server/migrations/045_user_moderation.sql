-- User safety controls required by the public profile and leaderboard surfaces.
-- Blocks are a relationship state (one row per directed pair). Reports are a
-- durable moderation queue, with at most one open report per reporter/target
-- pair so client retries cannot create duplicate work for moderators.

CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    CONSTRAINT user_blocks_not_self CHECK (blocker_user_id <> blocked_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked_user
    ON user_blocks(blocked_user_id, blocker_user_id);

CREATE TABLE IF NOT EXISTS user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(50) NOT NULL,
    details TEXT,
    status VARCHAR(20) DEFAULT 'open' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resolved_at TIMESTAMPTZ,
    resolved_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    resolution_note TEXT,
    CONSTRAINT user_reports_not_self
        CHECK (reporter_user_id <> reported_user_id),
    CONSTRAINT user_reports_reason_valid
        CHECK (
            reason IN (
                'inappropriate_content',
                'harassment',
                'hate_speech',
                'impersonation',
                'spam',
                'other'
            )
        ),
    CONSTRAINT user_reports_details_length
        CHECK (details IS NULL OR char_length(details) <= 1000),
    CONSTRAINT user_reports_status_valid
        CHECK (status IN ('open', 'resolved', 'dismissed')),
    CONSTRAINT user_reports_resolution_note_length
        CHECK (resolution_note IS NULL OR char_length(resolution_note) <= 1000),
    CONSTRAINT user_reports_resolution_state_valid
        CHECK (
            (status = 'open' AND resolved_at IS NULL)
            OR (status IN ('resolved', 'dismissed') AND resolved_at IS NOT NULL)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_reports_open_pair
    ON user_reports(reporter_user_id, reported_user_id)
    WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_user_reports_moderation_queue
    ON user_reports(status, created_at DESC, id);

CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user
    ON user_reports(reported_user_id, created_at DESC);
