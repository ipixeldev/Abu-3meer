-- Preserve the lifecycle derived from each full YouTube Studio members export.
-- The stable channel ID remains the only member identifier; display names and
-- uploaded CSV contents are deliberately not retained.

ALTER TABLE youtube_membership_snapshot_members
    ADD COLUMN IF NOT EXISTS status VARCHAR(12) NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP;

UPDATE youtube_membership_snapshot_members m
SET joined_at = CASE
        WHEN lower(regexp_replace(COALESCE(m.source_last_update, ''),
                                  '[[:space:]_-]+', '', 'g'))
             IN ('joined', 'rejoined')
          THEN m.source_last_update_at
        ELSE NULL
    END,
    last_seen_at = COALESCE(i.activated_at, m.created_at),
    updated_at = CURRENT_TIMESTAMP
FROM youtube_membership_snapshot_imports i
WHERE i.id = m.import_id
  AND m.last_seen_at IS NULL;

ALTER TABLE youtube_membership_snapshot_members
    ALTER COLUMN last_seen_at SET NOT NULL,
    ADD CONSTRAINT youtube_snapshot_member_status_valid
        CHECK (status IN ('active', 'lapsed')),
    ADD CONSTRAINT youtube_snapshot_member_lapsed_at_valid
        CHECK (
          (status = 'active' AND left_at IS NULL)
          OR (status = 'lapsed' AND left_at IS NOT NULL)
        );

CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_members_status
    ON youtube_membership_snapshot_members(status, youtube_channel_id);
CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_members_last_seen
    ON youtube_membership_snapshot_members(last_seen_at DESC);
