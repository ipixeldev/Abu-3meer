-- 014_btts_prediction_points.sql
-- Persist and award the Both Teams To Score prediction independently.

ALTER TABLE predictions
    ADD COLUMN IF NOT EXISTS is_both_teams_score_match BOOLEAN DEFAULT FALSE;

UPDATE predictions
SET is_both_teams_score_match = FALSE
WHERE is_both_teams_score_match IS NULL;

ALTER TABLE predictions
    ALTER COLUMN is_both_teams_score_match SET DEFAULT FALSE,
    ALTER COLUMN is_both_teams_score_match SET NOT NULL;

INSERT INTO point_rules (
    key,
    name,
    base_points,
    member_multiplier,
    description
) VALUES (
    'bothTeamsScore',
    'Both Teams To Score',
    15,
    2.00,
    'Correctly predicting whether both teams score'
)
ON CONFLICT (key) DO NOTHING;

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
            'admin_adjustment',
            'loyalty_redemption',
            'achievement_bonus'
        )
    );
