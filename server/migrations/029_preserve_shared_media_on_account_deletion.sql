-- Account deletion removes private avatars while preserving shared media that
-- may still be referenced by announcements, posts, challenges, or Player Cards.
-- The creator relationship is anonymized when its account is deleted.

ALTER TABLE media_uploads
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE media_uploads
  DROP CONSTRAINT IF EXISTS media_uploads_user_id_fkey;

ALTER TABLE media_uploads
  ADD CONSTRAINT media_uploads_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
