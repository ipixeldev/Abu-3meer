-- 012_profile_media_persistence.sql
-- Store full country names and track locally persisted media files.

ALTER TABLE users
  ALTER COLUMN country TYPE VARCHAR(100),
  ADD COLUMN IF NOT EXISTS country_code VARCHAR(2),
  ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS media_uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose VARCHAR(40) NOT NULL CHECK (
      purpose IN ('avatar', 'announcement', 'post', 'challenge', 'player_card')
    ),
    storage_path TEXT UNIQUE NOT NULL,
    public_url TEXT NOT NULL,
    content_type VARCHAR(50) NOT NULL,
    size_bytes INTEGER NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 8388608),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_media_uploads_user_created
  ON media_uploads(user_id, created_at DESC);
