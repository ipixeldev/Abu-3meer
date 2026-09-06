-- The product accepts self-declared stable YouTube profile links and checks
-- them against the creator's current complete CSV. Preserve the distinction
-- between a manual link and historically Google-proven channel ownership.
-- Existing links, CSV snapshots, and uniqueness constraints remain intact.

ALTER TABLE youtube_channel_claims
    DROP CONSTRAINT IF EXISTS youtube_channel_claims_ownership_verification_source_check;

ALTER TABLE youtube_channel_claims
    ADD CONSTRAINT youtube_channel_claims_ownership_verification_source_check
    CHECK (ownership_verification_source IN (
      'legacy_manual', 'google_oauth', 'manual_profile_link'
    ));

ALTER TABLE youtube_channel_claims
    DROP CONSTRAINT IF EXISTS youtube_channel_claims_approved_google_oauth_check;

ALTER TABLE youtube_channel_claims
    ADD CONSTRAINT youtube_channel_claims_approved_source_check
    CHECK (
      status <> 'approved'
      OR ownership_verification_source IN ('google_oauth', 'manual_profile_link')
    );
