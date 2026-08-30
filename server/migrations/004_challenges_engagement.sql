-- 004_challenges_engagement.sql
-- Videos, Playable Challenges (Secret Phrases & Player Cards), Submissions, and Claims

CREATE TABLE IF NOT EXISTS videos (
    id VARCHAR(100) PRIMARY KEY,
    youtube_id VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    thumbnail_url TEXT NOT NULL,
    video_url TEXT NOT NULL,
    published_at TIMESTAMPTZ NOT NULL,
    has_challenge BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS challenges (
    id VARCHAR(100) PRIMARY KEY,
    video_id VARCHAR(100) REFERENCES videos(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    kind VARCHAR(50) NOT NULL CHECK (kind IN ('videoPhrase', 'playerCard', 'matchQuiz', 'secretWord')),
    status VARCHAR(30) DEFAULT 'open' CHECK (status IN ('draft', 'scheduled', 'open', 'closed', 'archived')),
    reward_points INTEGER DEFAULT 10 NOT NULL,
    member_points INTEGER DEFAULT 20 NOT NULL,
    correct_answer VARCHAR(255) NOT NULL,
    normalized_correct_answer VARCHAR(255) NOT NULL,
    video_url TEXT,
    image_url TEXT,
    maximum_attempts INTEGER DEFAULT 3 NOT NULL,
    member_only BOOLEAN DEFAULT FALSE NOT NULL,
    starts_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_challenges_status ON challenges(status);
CREATE INDEX IF NOT EXISTS idx_challenges_dates ON challenges(starts_at, ends_at);

CREATE TABLE IF NOT EXISTS challenge_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id VARCHAR(100) NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    raw_answer TEXT NOT NULL,
    normalized_answer TEXT NOT NULL,
    is_correct BOOLEAN NOT NULL,
    attempt_number INTEGER DEFAULT 1 NOT NULL,
    points_awarded INTEGER DEFAULT 0 NOT NULL,
    submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_user_correct_challenge UNIQUE (user_id, challenge_id)
);

CREATE INDEX IF NOT EXISTS idx_challenge_submissions_user ON challenge_submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_challenge_submissions_challenge ON challenge_submissions(challenge_id);

CREATE TABLE IF NOT EXISTS player_cards (
    id VARCHAR(100) PRIMARY KEY,
    challenge_id VARCHAR(100) REFERENCES challenges(id) ON DELETE CASCADE,
    player_name VARCHAR(150) NOT NULL,
    normalized_player_name VARCHAR(150) NOT NULL,
    team VARCHAR(150) NOT NULL,
    position VARCHAR(50),
    card_tier VARCHAR(30) DEFAULT 'silver' CHECK (card_tier IN ('silver', 'gold', 'legendary')),
    card_image_url TEXT NOT NULL,
    verification_code VARCHAR(100),
    secret_hint TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS player_card_claims (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_card_id VARCHAR(100) NOT NULL REFERENCES player_cards(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    points_awarded INTEGER DEFAULT 10 NOT NULL,
    claimed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_user_player_card_claim UNIQUE (user_id, player_card_id)
);

CREATE INDEX IF NOT EXISTS idx_card_claims_user ON player_card_claims(user_id);
