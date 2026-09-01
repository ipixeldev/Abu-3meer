-- Admin-imported YouTube membership snapshots provide a bounded fallback when
-- Google has not allowlisted the creator Members API or that API is
-- temporarily unavailable. Uploaded files and member display names are never
-- retained. Immutable import metadata plus the current minimized channel list
-- provide auditability without accumulating historical member PII.

CREATE TABLE IF NOT EXISTS youtube_membership_snapshot_imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    imported_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    source_filename VARCHAR(180) NOT NULL,
    source_format VARCHAR(10) NOT NULL
        CHECK (source_format IN ('csv', 'tsv')),
    source_sha256 CHAR(64) NOT NULL
        CHECK (source_sha256 ~ '^[a-f0-9]{64}$'),
    member_count INTEGER NOT NULL CHECK (member_count >= 0),
    matched_user_count INTEGER NOT NULL DEFAULT 0
        CHECK (matched_user_count >= 0),
    activated_at TIMESTAMPTZ NOT NULL,
    superseded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_imports_activated
    ON youtube_membership_snapshot_imports(activated_at DESC);
CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_imports_hash
    ON youtube_membership_snapshot_imports(source_sha256);

CREATE TABLE IF NOT EXISTS youtube_membership_snapshot_state (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    active_import_id UUID NOT NULL
        REFERENCES youtube_membership_snapshot_imports(id) ON DELETE RESTRICT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS youtube_membership_snapshot_members (
    youtube_channel_id VARCHAR(24) PRIMARY KEY
        CHECK (youtube_channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
    import_id UUID NOT NULL
        REFERENCES youtube_membership_snapshot_imports(id) ON DELETE CASCADE,
    membership_level VARCHAR(200),
    total_time_on_level_months NUMERIC(10, 2)
        CHECK (total_time_on_level_months IS NULL
               OR total_time_on_level_months >= 0),
    total_time_as_member_months NUMERIC(10, 2)
        CHECK (total_time_as_member_months IS NULL
               OR total_time_as_member_months >= 0),
    source_last_update VARCHAR(500),
    source_last_update_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_members_import
    ON youtube_membership_snapshot_members(import_id);

ALTER TABLE youtube_account_links
    ADD COLUMN IF NOT EXISTS verification_source VARCHAR(30)
        NOT NULL DEFAULT 'youtube_api'
        CHECK (verification_source IN ('youtube_api', 'admin_snapshot')),
    ADD COLUMN IF NOT EXISTS snapshot_import_id UUID
        REFERENCES youtube_membership_snapshot_imports(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_youtube_account_links_snapshot
    ON youtube_account_links(snapshot_import_id)
    WHERE snapshot_import_id IS NOT NULL;
