-- 028_restore_signup_daily_xp.sql
-- Restore fixed activity XP while keeping it recognition-only. Signup and
-- daily login are never eligible for the YouTube membership multiplier.

UPDATE point_rules
SET base_points = CASE key
        WHEN 'signUpBonus' THEN 50
        WHEN 'dailyStreak' THEN 5
    END,
    member_multiplier = 1.00,
    description = CASE key
        WHEN 'signUpBonus' THEN 'Awarded once when an account is first created'
        WHEN 'dailyStreak' THEN 'Awarded once for the first app login each UTC day'
    END,
    updated_at = CURRENT_TIMESTAMP
WHERE key IN ('signUpBonus', 'dailyStreak');

-- Existing non-guest accounts created while signup XP was disabled receive
-- the same one-time immutable ledger entry as a newly provisioned account.
-- Using the account creation timestamp preserves the correct historical month
-- and season instead of moving old signup XP into the current period.
INSERT INTO point_transactions (
    user_id,
    source_type,
    source_id,
    base_points,
    multiplier,
    final_points,
    description,
    idempotency_key,
    created_at
)
SELECT users.id,
       'signup_bonus',
       'signup',
       rules.base_points,
       1.00,
       rules.base_points,
       'One-time signup XP',
       'signup_bonus_' || users.id::text,
       users.created_at
FROM users
JOIN user_profiles profile ON profile.user_id = users.id
JOIN point_rules rules ON rules.key = 'signUpBonus'
WHERE profile.is_guest = FALSE
  AND NOT EXISTS (
      SELECT 1
      FROM point_transactions existing
      WHERE existing.user_id = users.id
        AND existing.source_type = 'signup_bonus'
  )
ON CONFLICT (idempotency_key) DO NOTHING;

-- Migration 026 created the same named partial index with a narrower source
-- predicate. It must be replaced, not conditionally created, for the restored
-- sources to participate efficiently in month and season scans.
DROP INDEX IF EXISTS idx_point_transactions_xp_ranking_period;

CREATE INDEX idx_point_transactions_xp_ranking_period
    ON point_transactions (created_at, user_id)
    INCLUDE (final_points)
    WHERE source_type IN (
        'signup_bonus',
        'daily_streak',
        'prediction_exact',
        'prediction_scorer',
        'prediction_winner',
        'prediction_win',
        'video_phrase',
        'player_card'
    );

-- Rebuild cached profile counters from the immutable eligible-XP ledger. The
-- active season window is configuration-owned; no football date is hardcoded.
WITH active_season AS (
    SELECT starts_at, ends_at
    FROM leaderboard_periods
    WHERE type = 'season'
      AND is_current = TRUE
    ORDER BY starts_at DESC
    LIMIT 1
), eligible_xp AS (
    SELECT user_id, final_points, created_at
    FROM point_transactions
    WHERE source_type IN (
        'signup_bonus',
        'daily_streak',
        'prediction_exact',
        'prediction_scorer',
        'prediction_winner',
        'prediction_win',
        'video_phrase',
        'player_card'
    )
), rebuilt AS (
    SELECT profile.user_id,
           COALESCE(SUM(xp.final_points), 0)::integer AS total_points,
           COALESCE(
               SUM(xp.final_points) FILTER (
                   WHERE xp.created_at >= (
                       date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                       AT TIME ZONE 'UTC'
                   )
                     AND xp.created_at < (
                       (date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC')
                        + INTERVAL '1 month') AT TIME ZONE 'UTC'
                     )
               ),
               0
           )::integer AS monthly_points,
           COALESCE(
               SUM(xp.final_points) FILTER (
                   WHERE season.starts_at IS NOT NULL
                     AND xp.created_at >= season.starts_at
                     AND (season.ends_at IS NULL OR xp.created_at < season.ends_at)
               ),
               0
           )::integer AS season_points
    FROM user_profiles profile
    LEFT JOIN eligible_xp xp ON xp.user_id = profile.user_id
    LEFT JOIN active_season season ON TRUE
    GROUP BY profile.user_id
)
UPDATE user_profiles profile
SET total_points = rebuilt.total_points,
    monthly_points = rebuilt.monthly_points,
    season_points = rebuilt.season_points,
    loyalty_points = 0,
    updated_at = CURRENT_TIMESTAMP
FROM rebuilt
WHERE rebuilt.user_id = profile.user_id;
