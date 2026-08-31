-- 027_manual_leaderboard_seasons.sql
-- Explicit, audited season windows configured from Admin Studio. Automatic
-- football-schedule discovery remains the fallback for untouched periods.

ALTER TABLE leaderboard_periods
    ADD COLUMN IF NOT EXISTS management_mode VARCHAR(16) NOT NULL DEFAULT 'automatic',
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES users(id) ON DELETE SET NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'leaderboard_periods_management_mode_check'
          AND conrelid = 'leaderboard_periods'::regclass
    ) THEN
        ALTER TABLE leaderboard_periods
            ADD CONSTRAINT leaderboard_periods_management_mode_check
            CHECK (management_mode IN ('automatic', 'manual'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'leaderboard_periods_valid_window_check'
          AND conrelid = 'leaderboard_periods'::regclass
    ) THEN
        ALTER TABLE leaderboard_periods
            ADD CONSTRAINT leaderboard_periods_valid_window_check
            CHECK (ends_at IS NULL OR starts_at < ends_at);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_leaderboard_periods_season_window
    ON leaderboard_periods (starts_at, ends_at)
    WHERE type = 'season';

CREATE INDEX IF NOT EXISTS idx_leaderboard_periods_manual_seasons
    ON leaderboard_periods (starts_at DESC)
    WHERE type = 'season' AND management_mode = 'manual';
