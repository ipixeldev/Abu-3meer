-- The channel's normal public upload belongs on Home, never in the Exclusive
-- catalogue. Keep one replaceable public-video record while preserving the
-- existing durable 12-hour synchronization state.
CREATE TABLE IF NOT EXISTS youtube_latest_public_video (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    youtube_id VARCHAR(11) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    thumbnail_url VARCHAR(500) NOT NULL,
    video_url VARCHAR(500) NOT NULL,
    published_at TIMESTAMPTZ NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Preserve the last discovered upload when upgrading a server that previously
-- inserted that upload into `videos`.
INSERT INTO youtube_latest_public_video (
    singleton,
    youtube_id,
    title,
    description,
    thumbnail_url,
    video_url,
    published_at,
    fetched_at
)
SELECT
    TRUE,
    video.youtube_id,
    video.title,
    video.description,
    video.thumbnail_url,
    video.video_url,
    video.published_at,
    CURRENT_TIMESTAMP
FROM videos video
JOIN youtube_video_sync_state state
  ON state.last_video_id = video.youtube_id
WHERE video.is_unlisted = FALSE
  AND video.member_only = FALSE
ORDER BY video.published_at DESC
LIMIT 1
ON CONFLICT (singleton) DO NOTHING;

-- Remove only the public row previously created by automatic synchronization.
-- Manually managed unlisted/member-only Exclusive videos are untouched.
DELETE FROM videos video
USING youtube_video_sync_state state
WHERE state.last_video_id = video.youtube_id
  AND video.is_unlisted = FALSE
  AND video.member_only = FALSE;
