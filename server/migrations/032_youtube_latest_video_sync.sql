CREATE TABLE IF NOT EXISTS youtube_video_sync_state (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton = TRUE),
    last_attempted_at TIMESTAMPTZ,
    last_succeeded_at TIMESTAMPTZ,
    last_video_id VARCHAR(50),
    last_error_code VARCHAR(100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO youtube_video_sync_state (singleton)
VALUES (TRUE)
ON CONFLICT (singleton) DO NOTHING;
