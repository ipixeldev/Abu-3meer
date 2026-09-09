-- The latest complete administrator-imported snapshot is the only membership
-- authority. Revoke any legacy Members-API flag (or superseded snapshot flag)
-- so a pre-CSV row can never retain member access when no current snapshot
-- supports it.

-- Creator OAuth is disabled in the CSV-only architecture. Destroy any token
-- left by an earlier owner-connection attempt before this release.
DELETE FROM youtube_creator_credentials;

UPDATE youtube_account_links l
SET is_member = FALSE,
    membership_level_id = NULL,
    member_since = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE l.is_member = TRUE
  AND NOT COALESCE(
    l.verification_source = 'admin_snapshot'
    AND l.snapshot_import_id = (
      SELECT active_import_id
      FROM youtube_membership_snapshot_state
      WHERE singleton = TRUE
    ),
    FALSE
  );

UPDATE users u
SET is_youtube_member = FALSE,
    youtube_member_since = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE u.is_youtube_member = TRUE
  AND NOT EXISTS (
    SELECT 1
    FROM youtube_account_links l
    WHERE l.user_id = u.id
      AND l.is_member = TRUE
      AND l.verification_source = 'admin_snapshot'
      AND l.snapshot_import_id = (
        SELECT active_import_id
        FROM youtube_membership_snapshot_state
        WHERE singleton = TRUE
      )
  );

DELETE FROM user_roles r
WHERE r.role_id = 'member'
  AND NOT EXISTS (
    SELECT 1
    FROM youtube_account_links l
    WHERE l.user_id = r.user_id
      AND l.is_member = TRUE
      AND l.verification_source = 'admin_snapshot'
      AND l.snapshot_import_id = (
        SELECT active_import_id
        FROM youtube_membership_snapshot_state
        WHERE singleton = TRUE
      )
  );
