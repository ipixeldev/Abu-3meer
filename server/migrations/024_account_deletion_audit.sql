-- 024_account_deletion_audit.sql
-- Preserve proof that an account-deletion request completed without retaining
-- a user identifier, email address, Firebase UID, or other deleted profile data.

CREATE TABLE IF NOT EXISTS account_deletion_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id VARCHAR(100),
    deleted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_audit_deleted_at
    ON account_deletion_audit(deleted_at DESC);
