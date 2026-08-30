-- Persist onboarding independently from profile placeholder values.
--
-- Existing accounts predate this flag and have already been allowed into the
-- application, so preserve that behaviour. Accounts provisioned after this
-- migration start incomplete until the profile completion request succeeds.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN;

UPDATE users
SET onboarding_completed = TRUE
WHERE onboarding_completed IS NULL;

ALTER TABLE users
    ALTER COLUMN onboarding_completed SET DEFAULT FALSE,
    ALTER COLUMN onboarding_completed SET NOT NULL;
