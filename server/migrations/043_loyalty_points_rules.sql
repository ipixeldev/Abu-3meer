-- 043_loyalty_points_rules.sql
-- Make the published loyalty table authoritative, add durable membership
-- activation/renewal awards, and preserve independently floored period edits.

INSERT INTO point_rules (
    key,
    name,
    base_points,
    member_multiplier,
    description
) VALUES
    ('signUpBonus', 'Sign-up Bonus', 50, 1.00,
     'Awarded once when an account is first created'),
    ('dailyStreak', 'Daily Login', 5, 1.00,
     'Awarded once per UTC calendar day'),
    ('videoQuestion', 'Correct Word', 15, 1.00,
     'Correctly answering a word challenge'),
    ('playerCard', 'Correct Player', 15, 1.00,
     'Correctly identifying a player'),
    ('winnerOutcome', 'Correct Match Winner Prediction', 10, 2.00,
     'Correctly predicting the winning team or draw'),
    ('firstScorer', 'Correct First Goalscorer Prediction', 20, 2.00,
     'Correctly predicting the first goalscorer'),
    ('exactPrediction', 'Correct Exact Score Prediction', 50, 2.00,
     'Correctly predicting the exact match score'),
    ('firstMembershipActivation', 'First Membership Activation', 150, 1.00,
     'Awarded once when membership is activated for the first time'),
    ('membershipRenewal', 'Membership Renewal', 50, 1.00,
     'Awarded once for each newly verified membership cycle')
ON CONFLICT (key) DO UPDATE SET
    name = EXCLUDED.name,
    base_points = EXCLUDED.base_points,
    member_multiplier = EXCLUDED.member_multiplier,
    description = EXCLUDED.description,
    updated_at = CURRENT_TIMESTAMP;

-- Correct-word and correct-player challenges are fixed base awards. Member
-- doubling belongs only to the three prediction reward categories.
UPDATE challenges
SET reward_points = 15,
    member_points = 15
WHERE kind IN ('videoPhrase', 'playerCard')
  AND (reward_points <> 15 OR member_points <> 15);

ALTER TABLE point_transactions
    DROP CONSTRAINT IF EXISTS point_transactions_source_type_check;

ALTER TABLE point_transactions
    ADD CONSTRAINT point_transactions_source_type_check CHECK (
        source_type IN (
            'signup_bonus',
            'prediction_exact',
            'prediction_scorer',
            'prediction_winner',
            'prediction_btts',
            'prediction_win',
            'video_phrase',
            'player_card',
            'daily_streak',
            'membership_activation',
            'membership_renewal',
            'admin_adjustment',
            'loyalty_redemption',
            'achievement_bonus'
        )
    );

-- Most awards contribute the same amount to lifetime, monthly, and season XP.
-- Admin deductions may hit a period floor before the lifetime balance, so the
-- immutable ledger stores those two effective deltas separately.
ALTER TABLE point_transactions
    ADD COLUMN IF NOT EXISTS monthly_points_delta INTEGER,
    ADD COLUMN IF NOT EXISTS season_points_delta INTEGER;

UPDATE point_transactions
SET monthly_points_delta = final_points
WHERE monthly_points_delta IS NULL;

UPDATE point_transactions
SET season_points_delta = final_points
WHERE season_points_delta IS NULL;

CREATE TABLE IF NOT EXISTS membership_reward_cycles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(20) NOT NULL CHECK (provider IN ('revenuecat', 'youtube')),
    cycle_key VARCHAR(180) NOT NULL,
    cycle_sequence NUMERIC NOT NULL,
    first_observed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_observed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, provider)
);

DROP INDEX IF EXISTS idx_point_transactions_xp_ranking_period;

CREATE INDEX idx_point_transactions_xp_ranking_period
    ON point_transactions (created_at, user_id)
    INCLUDE (final_points, monthly_points_delta, season_points_delta)
    WHERE source_type IN (
        'signup_bonus',
        'daily_streak',
        'prediction_exact',
        'prediction_scorer',
        'prediction_winner',
        'prediction_win',
        'video_phrase',
        'player_card',
        'membership_activation',
        'membership_renewal',
        'admin_adjustment'
    );

UPDATE roles
SET description = 'Verified member with the configured multiplier on winner, first-goalscorer, and exact-score prediction rewards'
WHERE id = 'member';
