-- 026_xp_only_rankings.sql
-- Rankings are XP-only: paid entry, prizes, signup, attendance, achievements,
-- redemptions and manual adjustments never contribute to a leaderboard.

ALTER TABLE user_profiles
    ALTER COLUMN total_points SET DEFAULT 0,
    ALTER COLUMN monthly_points SET DEFAULT 0,
    ALTER COLUMN season_points SET DEFAULT 0,
    ALTER COLUMN loyalty_points SET DEFAULT 0;

UPDATE point_rules
SET base_points = 0,
    member_multiplier = 1.00,
    updated_at = CURRENT_TIMESTAMP
WHERE key IN ('signUpBonus', 'dailyStreak');

-- Older or partially provisioned installations may not have these optional
-- gamification/notification tables. Dynamic statements keep this migration
-- safe on both a complete production schema and those installations.
DO $$
BEGIN
    IF to_regclass('public.achievements') IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'achievements'
             AND column_name = 'reward_points'
       ) THEN
        EXECUTE 'ALTER TABLE public.achievements ALTER COLUMN reward_points SET DEFAULT 0';
        EXECUTE 'UPDATE public.achievements SET reward_points = 0 WHERE reward_points <> 0';
    END IF;
END $$;

DO $$
BEGIN
    IF to_regclass('public.notification_campaigns') IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'notification_campaigns'
             AND column_name = 'category'
       )
       AND EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'notification_campaigns'
             AND column_name = 'status'
       ) THEN
        EXECUTE 'ALTER TABLE public.notification_campaigns DROP CONSTRAINT IF EXISTS notification_campaigns_status_check';
        EXECUTE $constraint$
            ALTER TABLE public.notification_campaigns
            ADD CONSTRAINT notification_campaigns_status_check
            CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled'))
        $constraint$;
        EXECUTE $cancel$
            UPDATE public.notification_campaigns
            SET status = 'cancelled'
            WHERE category = 'reward'
              AND status IN ('pending', 'failed', 'processing')
        $cancel$;
    END IF;
END $$;

-- An active season has an open-ended window until the next season is
-- deliberately configured. Historical seasons keep an explicit end date.
ALTER TABLE leaderboard_periods
    ALTER COLUMN ends_at DROP NOT NULL;

UPDATE leaderboard_periods
SET is_current = FALSE
WHERE type = 'season'
  AND id <> '2026-2027';

INSERT INTO leaderboard_periods (
    id,
    type,
    name,
    starts_at,
    ends_at,
    is_current
) VALUES (
    '2026-2027',
    'season',
    '2026/27 Season',
    TIMESTAMPTZ '2026-08-30 15:00:00+00',
    NULL,
    TRUE
)
ON CONFLICT (id) DO UPDATE SET
    type = EXCLUDED.type,
    name = EXCLUDED.name,
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    is_current = EXCLUDED.is_current;

CREATE UNIQUE INDEX IF NOT EXISTS idx_leaderboard_periods_one_current_season
    ON leaderboard_periods (is_current)
    WHERE type = 'season' AND is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_leaderboard_periods_season_start
    ON leaderboard_periods (starts_at DESC)
    WHERE type = 'season';

-- This partial covering index serves current-month, previous-month and season
-- ledger scans while making the excluded XP sources impossible to enter the
-- index used by rankings.
CREATE INDEX IF NOT EXISTS idx_point_transactions_xp_ranking_period
    ON point_transactions (created_at, user_id)
    INCLUDE (final_points)
    WHERE source_type IN (
        'prediction_exact',
        'prediction_scorer',
        'prediction_winner',
        'prediction_win',
        'video_phrase',
        'player_card'
    );

-- Rebuild legacy counters from the immutable ledger so existing signup,
-- streak, achievement, redemption and admin points disappear immediately.
WITH eligible_xp AS (
    SELECT user_id, final_points, created_at
    FROM point_transactions
    WHERE source_type IN (
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
               ),
               0
           )::integer AS monthly_points,
           COALESCE(
               SUM(xp.final_points) FILTER (
                   WHERE xp.created_at >= TIMESTAMPTZ '2026-08-30 15:00:00+00'
               ),
               0
           )::integer AS season_points
    FROM user_profiles profile
    LEFT JOIN eligible_xp xp ON xp.user_id = profile.user_id
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
