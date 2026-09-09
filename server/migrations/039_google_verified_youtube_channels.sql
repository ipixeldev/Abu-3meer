-- Replace the temporary typed-channel/staff-review trust boundary with
-- ownership proven directly by a short-lived Google OAuth credential.
--
-- Every pre-039 pending or approved claim could have originated from a typed
-- UC ID. Revoke that trust once, fail all membership bonuses closed, and make
-- users run the new automatic check. The CSV remains the sole authority for
-- whether a Google-proven channel currently receives member benefits.

ALTER TABLE youtube_channel_claims
    ADD COLUMN IF NOT EXISTS ownership_verification_source VARCHAR(30)
        NOT NULL DEFAULT 'legacy_manual'
        CHECK (ownership_verification_source IN (
          'legacy_manual', 'google_oauth'
        ));

INSERT INTO membership_history
    (user_id, status, verified_at, expires_at, metadata)
SELECT link.user_id, 'inactive', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
       jsonb_build_object(
         'source', 'google_oauth_trust_cutover',
         'youtubeChannelId', link.youtube_channel_id
       )
FROM youtube_account_links link
WHERE link.is_member = TRUE;

UPDATE youtube_channel_claims
SET status = 'revoked',
    reviewed_at = CURRENT_TIMESTAMP,
    reviewed_by_user_id = NULL,
    review_reason = 'Reverification required after Google OAuth trust cutover.',
    approved_snapshot_import_id = NULL,
    ownership_verification_source = 'legacy_manual',
    updated_at = CURRENT_TIMESTAMP
WHERE status IN ('pending', 'approved');

DELETE FROM youtube_account_links;

UPDATE users
SET is_youtube_member = FALSE,
    youtube_channel_id = NULL,
    youtube_member_since = NULL,
    youtube_membership_verified_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE is_youtube_member = TRUE
   OR youtube_channel_id IS NOT NULL
   OR youtube_membership_verified_at IS NOT NULL;

DELETE FROM user_roles WHERE role_id = 'member';

UPDATE youtube_membership_snapshot_imports
SET matched_user_count = 0
WHERE matched_user_count <> 0;

ALTER TABLE youtube_channel_claims
    DROP CONSTRAINT IF EXISTS youtube_channel_claims_approved_google_oauth_check;
ALTER TABLE youtube_channel_claims
    ADD CONSTRAINT youtube_channel_claims_approved_google_oauth_check
    CHECK (
      status <> 'approved'
      OR ownership_verification_source = 'google_oauth'
    );
