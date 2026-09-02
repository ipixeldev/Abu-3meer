-- OAuth-free YouTube membership claims.
--
-- A user-supplied channel URL is only a claim; it never proves ownership and
-- never grants membership by itself. Authorized staff must approve the claim
-- while that exact channel is present in the current, unexpired full export.

ALTER TABLE youtube_membership_snapshot_imports
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

UPDATE youtube_membership_snapshot_imports
SET expires_at = activated_at + INTERVAL '7 days'
WHERE expires_at IS NULL;

ALTER TABLE youtube_membership_snapshot_imports
    ALTER COLUMN expires_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_youtube_snapshot_imports_expiry
    ON youtube_membership_snapshot_imports(expires_at DESC);

CREATE TABLE IF NOT EXISTS youtube_channel_claims (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    youtube_channel_id VARCHAR(24) NOT NULL
        CHECK (youtube_channel_id ~ '^UC[A-Za-z0-9_-]{22}$'),
    status VARCHAR(16) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
          'pending', 'approved', 'rejected', 'revoked', 'superseded'
        )),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMPTZ,
    reviewed_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    review_reason VARCHAR(500),
    approved_snapshot_import_id UUID
        REFERENCES youtube_membership_snapshot_imports(id) ON DELETE RESTRICT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
      (status = 'pending'
       AND reviewed_at IS NULL
       AND reviewed_by_user_id IS NULL
       AND review_reason IS NULL
       AND approved_snapshot_import_id IS NULL)
      OR
      (status <> 'pending'
       AND reviewed_at IS NOT NULL
       AND review_reason IS NOT NULL)
    ),
    CHECK (
      status <> 'approved' OR approved_snapshot_import_id IS NOT NULL
    )
);

CREATE INDEX IF NOT EXISTS idx_youtube_channel_claims_queue
    ON youtube_channel_claims(status, submitted_at ASC);
CREATE INDEX IF NOT EXISTS idx_youtube_channel_claims_user
    ON youtube_channel_claims(user_id, submitted_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_youtube_channel_claim_pending_user
    ON youtube_channel_claims(user_id)
    WHERE status = 'pending';
CREATE UNIQUE INDEX IF NOT EXISTS uq_youtube_channel_claim_approved_user
    ON youtube_channel_claims(user_id)
    WHERE status = 'approved';
CREATE UNIQUE INDEX IF NOT EXISTS uq_youtube_channel_claim_approved_channel
    ON youtube_channel_claims(youtube_channel_id)
    WHERE status = 'approved';

-- Preserve old channel suggestions for staff review, but revoke all legacy
-- OAuth-created trust. No account remains a member until a staff decision is
-- recorded through the new claim workflow.
INSERT INTO youtube_channel_claims (user_id, youtube_channel_id)
SELECT user_id, youtube_channel_id
FROM youtube_account_links
WHERE youtube_channel_id ~ '^UC[A-Za-z0-9_-]{22}$'
ON CONFLICT DO NOTHING;

DELETE FROM youtube_account_links;

-- Links are deliberately cleared above, so no import can keep reporting a
-- legacy OAuth match after the trust model changes.
UPDATE youtube_membership_snapshot_imports
SET matched_user_count = 0
WHERE matched_user_count <> 0;

UPDATE users
SET is_youtube_member = FALSE,
    youtube_channel_id = NULL,
    youtube_member_since = NULL,
    youtube_membership_verified_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE is_youtube_member = TRUE OR youtube_channel_id IS NOT NULL;

DELETE FROM user_roles WHERE role_id = 'member';

ALTER TABLE youtube_account_links
    ALTER COLUMN verification_source SET DEFAULT 'admin_snapshot';
ALTER TABLE youtube_account_links
    DROP CONSTRAINT IF EXISTS youtube_account_links_verification_source_check;
ALTER TABLE youtube_account_links
    ADD CONSTRAINT youtube_account_links_verification_source_check
    CHECK (verification_source = 'admin_snapshot');

-- Audit receipts must survive deletion of the staff account that performed
-- the action. Attribution is also copied into each claim receipt's JSON.
ALTER TABLE admin_audit_logs
    ALTER COLUMN admin_user_id DROP NOT NULL;
ALTER TABLE admin_audit_logs
    DROP CONSTRAINT IF EXISTS admin_audit_logs_admin_user_id_fkey;
ALTER TABLE admin_audit_logs
    ADD CONSTRAINT admin_audit_logs_admin_user_id_fkey
    FOREIGN KEY (admin_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Creator/member OAuth is no longer part of production. Destroy reusable
-- credentials and incomplete flows, while retaining the empty legacy schemas
-- for one release so a rollback does not fail against missing tables.
DELETE FROM youtube_creator_credentials;
DELETE FROM youtube_oauth_flows;
