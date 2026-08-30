-- 007_leaderboards.sql
-- Leaderboard Periods, Precomputed Aggregate Rankings, and Fan War Stats

CREATE TABLE IF NOT EXISTS leaderboard_periods (
    id VARCHAR(50) PRIMARY KEY,
    type VARCHAR(20) NOT NULL CHECK (type IN ('monthly', 'season', 'all_time')),
    name VARCHAR(100) NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    is_current BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS leaderboard_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id VARCHAR(50) NOT NULL REFERENCES leaderboard_periods(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rank INTEGER NOT NULL,
    points INTEGER NOT NULL,
    username VARCHAR(50) NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    supported_team VARCHAR(100),
    is_youtube_member BOOLEAN DEFAULT FALSE,
    snapshot_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_period_user_snapshot UNIQUE (period_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_snapshots_period_rank ON leaderboard_snapshots(period_id, rank);

CREATE TABLE IF NOT EXISTS team_leaderboards (
    team_name VARCHAR(100) PRIMARY KEY,
    total_fans INTEGER DEFAULT 0 NOT NULL,
    total_points BIGINT DEFAULT 0 NOT NULL,
    average_points NUMERIC(10, 2) DEFAULT 0.00 NOT NULL,
    logo_url TEXT,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);
