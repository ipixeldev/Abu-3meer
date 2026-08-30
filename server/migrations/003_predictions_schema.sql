-- 003_predictions_schema.sql
-- Match Predictions with strict server-side deadline validation and idempotency

CREATE TABLE IF NOT EXISTS predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    match_id VARCHAR(100) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    home_score INTEGER NOT NULL CHECK (home_score >= 0),
    away_score INTEGER NOT NULL CHECK (away_score >= 0),
    first_scorer VARCHAR(150) NOT NULL DEFAULT '',
    both_teams_score BOOLEAN DEFAULT FALSE,
    points_awarded INTEGER DEFAULT 0 NOT NULL,
    rewarded BOOLEAN DEFAULT FALSE NOT NULL,
    seen_result BOOLEAN DEFAULT FALSE NOT NULL,
    is_exact_match BOOLEAN DEFAULT FALSE,
    is_first_scorer_match BOOLEAN DEFAULT FALSE,
    is_winner_match BOOLEAN DEFAULT FALSE,
    submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_user_match_prediction UNIQUE (user_id, match_id)
);

CREATE INDEX IF NOT EXISTS idx_predictions_user ON predictions(user_id);
CREATE INDEX IF NOT EXISTS idx_predictions_match ON predictions(match_id);
CREATE INDEX IF NOT EXISTS idx_predictions_rewarded ON predictions(rewarded) WHERE NOT rewarded;
