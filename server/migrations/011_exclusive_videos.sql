-- 011_exclusive_videos.sql
-- Special Unlisted YouTube Videos for App Users

ALTER TABLE videos ADD COLUMN IF NOT EXISTS is_unlisted BOOLEAN DEFAULT TRUE NOT NULL;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS member_only BOOLEAN DEFAULT FALSE NOT NULL;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0 NOT NULL;

CREATE INDEX IF NOT EXISTS idx_videos_published ON videos(published_at DESC);
