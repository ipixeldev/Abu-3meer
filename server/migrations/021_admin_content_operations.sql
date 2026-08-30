-- 021_admin_content_operations.sql
-- Makes Admin Studio content use the self-hosted PostgreSQL/RBAC backend.

-- Admin Studio exposes these lifecycle values. Keep one vocabulary across the
-- database, API and Flutter client instead of silently mapping values.
ALTER TABLE challenges DROP CONSTRAINT IF EXISTS challenges_status_check;
ALTER TABLE challenges
  ADD CONSTRAINT challenges_status_check
  CHECK (status IN (
    'draft', 'scheduled', 'open', 'disabled', 'ended', 'closed', 'archived'
  ));

ALTER TABLE challenges
  ADD COLUMN IF NOT EXISTS notify_on_live BOOLEAN DEFAULT FALSE NOT NULL;

-- Public prompts/options and private accepted answers live in separate
-- columns. Public challenge queries never select normalized_accepted_answers.
CREATE TABLE IF NOT EXISTS challenge_questions (
  id VARCHAR(100) NOT NULL,
  challenge_id VARCHAR(100) NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  prompt TEXT NOT NULL,
  answer_type VARCHAR(30) DEFAULT 'text' NOT NULL
    CHECK (answer_type IN ('text', 'multipleChoice', 'trueFalse')),
  options JSONB DEFAULT '[]'::jsonb NOT NULL,
  normalized_accepted_answers JSONB DEFAULT '[]'::jsonb NOT NULL,
  position INTEGER DEFAULT 0 NOT NULL,
  PRIMARY KEY (challenge_id, id)
);

CREATE INDEX IF NOT EXISTS idx_challenge_questions_order
  ON challenge_questions(challenge_id, position);

-- The original constraint made every submission unique, so maximumAttempts
-- could never be greater than one. Preserve all failed attempts while allowing
-- only one successful claim per user/challenge.
ALTER TABLE challenge_submissions
  DROP CONSTRAINT IF EXISTS uq_user_correct_challenge;
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_correct_challenge
  ON challenge_submissions(user_id, challenge_id)
  WHERE is_correct = TRUE;

-- Expand the original football-card table to the catalogue model used by the
-- app. Existing installations keep their data and receive safe defaults.
ALTER TABLE player_cards
  ADD COLUMN IF NOT EXISTS player_name_ar VARCHAR(150) DEFAULT '' NOT NULL,
  ADD COLUMN IF NOT EXISTS team_logo_url TEXT DEFAULT '' NOT NULL,
  ADD COLUMN IF NOT EXISTS rating INTEGER DEFAULT 1 NOT NULL,
  ADD COLUMN IF NOT EXISTS rarity VARCHAR(30) DEFAULT 'common' NOT NULL,
  ADD COLUMN IF NOT EXISTS stats JSONB DEFAULT '{}'::jsonb NOT NULL,
  ADD COLUMN IF NOT EXISTS description TEXT DEFAULT '' NOT NULL,
  ADD COLUMN IF NOT EXISTS description_ar TEXT DEFAULT '' NOT NULL,
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN DEFAULT TRUE NOT NULL,
  ADD COLUMN IF NOT EXISTS source_challenge_id VARCHAR(100) DEFAULT '' NOT NULL,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL;

-- Preserve catalogue meaning for installations created by migration 004.
-- The application now reads rarity/source_challenge_id, while the original
-- schema stored those values as card_tier/challenge_id.
UPDATE player_cards
SET rarity = card_tier
WHERE rarity = 'common'
  AND card_tier IS NOT NULL
  AND card_tier <> 'common';

UPDATE player_cards
SET source_challenge_id = challenge_id
WHERE source_challenge_id = ''
  AND challenge_id IS NOT NULL;

UPDATE player_cards
SET updated_at = created_at
WHERE created_at IS NOT NULL;

ALTER TABLE player_cards DROP CONSTRAINT IF EXISTS player_cards_card_tier_check;
ALTER TABLE player_cards
  ADD CONSTRAINT player_cards_card_tier_check
  CHECK (card_tier IN (
    'common', 'rare', 'epic', 'legendary', 'silver', 'gold'
  ));

ALTER TABLE player_cards DROP CONSTRAINT IF EXISTS player_cards_rating_check;
ALTER TABLE player_cards
  ADD CONSTRAINT player_cards_rating_check CHECK (rating BETWEEN 1 AND 99);

INSERT INTO permissions (id, name, category, description) VALUES
('redemptions.manage', 'Manage Redemptions', 'rewards',
 'Review and fulfill loyalty reward redemption requests')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
VALUES
  ('super_admin', 'redemptions.manage'),
  ('admin', 'redemptions.manage')
ON CONFLICT DO NOTHING;
