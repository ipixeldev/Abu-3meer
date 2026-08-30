-- 005_points_ledger.sql
-- Immutable Point Transactions Ledger, Point Rules, and Multipliers

CREATE TABLE IF NOT EXISTS point_rules (
    key VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    base_points INTEGER NOT NULL,
    member_multiplier NUMERIC(3, 2) DEFAULT 2.00 NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

INSERT INTO point_rules (key, name, base_points, member_multiplier, description) VALUES
('signUpBonus', 'Sign-up Bonus', 50, 1.00, 'Awarded once upon completing onboarding'),
('exactPrediction', 'Exact-score Prediction', 30, 2.00, 'Predicting the exact match final score'),
('firstScorer', 'First Scorer Prediction', 20, 2.00, 'Predicting who scores the first goal'),
('winnerOutcome', 'Winner Outcome Prediction', 10, 2.00, 'Predicting the winning team or draw'),
('videoQuestion', 'Secret Video Phrase', 10, 2.00, 'Solving the hidden video phrase'),
('playerCard', 'Player Card Discovery', 10, 2.00, 'Finding and claiming the hidden player card'),
('dailyStreak', 'Daily Streak Check-in', 5, 2.00, 'Daily attendance check-in reward')
ON CONFLICT (key) DO UPDATE SET
base_points = EXCLUDED.base_points,
member_multiplier = EXCLUDED.member_multiplier;

CREATE TABLE IF NOT EXISTS point_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_type VARCHAR(50) NOT NULL CHECK (source_type IN ('signup_bonus', 'prediction_exact', 'prediction_scorer', 'prediction_winner', 'prediction_win', 'video_phrase', 'player_card', 'daily_streak', 'admin_adjustment', 'loyalty_redemption', 'achievement_bonus')),
    source_id VARCHAR(100) NOT NULL,
    base_points INTEGER NOT NULL,
    multiplier NUMERIC(3, 2) DEFAULT 1.00 NOT NULL,
    final_points INTEGER NOT NULL,
    description TEXT NOT NULL,
    idempotency_key VARCHAR(150) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_point_transactions_user ON point_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_point_transactions_source ON point_transactions(source_type, source_id);
CREATE INDEX IF NOT EXISTS idx_point_transactions_idempotency ON point_transactions(idempotency_key);
