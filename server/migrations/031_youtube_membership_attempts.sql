-- Verification attempts and successful membership observations have different
-- trust semantics. A temporary Google/configuration failure must not replace a
-- previously successful membership result or make that failure look fresh.

ALTER TABLE youtube_account_links
    ADD COLUMN IF NOT EXISTS last_attempted_at TIMESTAMPTZ;

UPDATE youtube_account_links
SET last_attempted_at = last_verified_at
WHERE last_attempted_at IS NULL;

ALTER TABLE youtube_account_links
    ALTER COLUMN last_attempted_at SET NOT NULL;

-- Remove legacy manual membership authority and make the denormalized user
-- fields mirror the OAuth-bound link. Runtime authorization always applies the
-- freshness window to youtube_account_links rather than trusting these fields.
UPDATE users AS u
SET is_youtube_member = l.is_member,
    youtube_channel_id = l.youtube_channel_id,
    youtube_member_since = l.member_since,
    youtube_membership_verified_at = l.last_verified_at
FROM youtube_account_links AS l
WHERE l.user_id = u.id;

UPDATE users AS u
SET is_youtube_member = FALSE,
    youtube_channel_id = NULL,
    youtube_member_since = NULL,
    youtube_membership_verified_at = NULL
WHERE NOT EXISTS (
    SELECT 1 FROM youtube_account_links AS l WHERE l.user_id = u.id
);

DELETE FROM user_roles AS ur
WHERE ur.role_id = 'member'
  AND NOT EXISTS (
      SELECT 1 FROM youtube_account_links AS l
      WHERE l.user_id = ur.user_id AND l.is_member = TRUE
  );
