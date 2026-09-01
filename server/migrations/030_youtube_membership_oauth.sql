-- Secure YouTube OAuth and channel-membership verification.
-- User access/refresh tokens are never persisted. Only the creator refresh
-- token is retained, encrypted by the application before it reaches Postgres.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS youtube_membership_verified_at TIMESTAMPTZ;

-- Existing trusted flags receive one bounded grace window after deployment.
-- Runtime authorization treats this timestamp as stale after the configured
-- refresh interval, so a cancelled membership cannot grant 2x XP forever.
UPDATE users
SET youtube_membership_verified_at = CURRENT_TIMESTAMP
WHERE is_youtube_member = TRUE
  AND youtube_membership_verified_at IS NULL;

CREATE TABLE IF NOT EXISTS youtube_oauth_flows (
    id UUID PRIMARY KEY,
    state_hash CHAR(64) UNIQUE NOT NULL
        CHECK (state_hash ~ '^[a-f0-9]{64}$'),
    purpose VARCHAR(30) NOT NULL
        CHECK (purpose IN ('member_link', 'creator_connect')),
    requested_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expected_google_subject VARCHAR(255),
    pkce_verifier_ciphertext TEXT NOT NULL,
    oidc_nonce_hash CHAR(64) NOT NULL
        CHECK (oidc_nonce_hash ~ '^[a-f0-9]{64}$'),
    status VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'verified', 'not_member', 'connected', 'error')),
    error_code VARCHAR(80),
    youtube_channel_id VARCHAR(128),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (
      purpose = 'creator_connect'
      OR expected_google_subject IS NOT NULL
      OR status <> 'pending'
    )
);

CREATE INDEX IF NOT EXISTS idx_youtube_oauth_flows_owner
    ON youtube_oauth_flows(requested_by_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_youtube_oauth_flows_expiry
    ON youtube_oauth_flows(expires_at);

CREATE TABLE IF NOT EXISTS youtube_creator_credentials (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    creator_channel_id VARCHAR(128) UNIQUE NOT NULL,
    refresh_token_ciphertext TEXT NOT NULL,
    authorized_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    authorized_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS youtube_account_links (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    youtube_channel_id VARCHAR(128) UNIQUE NOT NULL,
    is_member BOOLEAN NOT NULL DEFAULT FALSE,
    membership_level_id VARCHAR(128),
    member_since TIMESTAMPTZ,
    last_verified_at TIMESTAMPTZ NOT NULL,
    last_attempted_at TIMESTAMPTZ NOT NULL,
    last_error_code VARCHAR(80),
    linked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_youtube_account_links_refresh
    ON youtube_account_links(last_verified_at);
