-- 002_football_schema.sql
-- Football Competitions, Seasons, Teams, Matches, Results, and Live Timelines

CREATE TABLE IF NOT EXISTS seasons (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS competitions (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    code VARCHAR(50),
    emblem_url TEXT,
    country VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE NOT NULL
);

CREATE TABLE IF NOT EXISTS teams (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    normalized_name VARCHAR(150) NOT NULL,
    short_name VARCHAR(50),
    badge_url TEXT NOT NULL,
    league VARCHAR(100),
    is_popular BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_teams_normalized_name ON teams(normalized_name);

CREATE TABLE IF NOT EXISTS matches (
    id VARCHAR(100) PRIMARY KEY,
    season_id VARCHAR(50) REFERENCES seasons(id) ON DELETE SET NULL,
    competition_id VARCHAR(100) REFERENCES competitions(id) ON DELETE SET NULL,
    competition_name VARCHAR(150) NOT NULL,
    home_team_id VARCHAR(100) REFERENCES teams(id) ON DELETE SET NULL,
    away_team_id VARCHAR(100) REFERENCES teams(id) ON DELETE SET NULL,
    home_team VARCHAR(150) NOT NULL,
    away_team VARCHAR(150) NOT NULL,
    home_logo_url TEXT,
    away_logo_url TEXT,
    kickoff_at TIMESTAMPTZ NOT NULL,
    predictions_open_at TIMESTAMPTZ NOT NULL,
    predictions_close_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'open', 'closed', 'live', 'finished', 'cancelled', 'postponed')),
    home_score INTEGER,
    away_score INTEGER,
    first_scorer VARCHAR(150),
    first_scorer_options JSONB DEFAULT '[]'::jsonb,
    is_hot BOOLEAN DEFAULT FALSE NOT NULL,
    venue VARCHAR(150),
    reward_processed BOOLEAN DEFAULT FALSE NOT NULL,
    reward_processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_matches_kickoff ON matches(kickoff_at);
CREATE INDEX IF NOT EXISTS idx_matches_status ON matches(status);
CREATE INDEX IF NOT EXISTS idx_matches_teams ON matches(home_team, away_team);

CREATE TABLE IF NOT EXISTS match_timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id VARCHAR(100) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    minute INTEGER NOT NULL,
    extra_minute INTEGER,
    team VARCHAR(150) NOT NULL,
    player VARCHAR(150) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('goal', 'penalty_goal', 'own_goal', 'yellow_card', 'red_card', 'sub', 'var')),
    detail TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_timeline_match ON match_timeline_events(match_id, minute);
