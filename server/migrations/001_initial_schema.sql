-- 001_initial_schema.sql
-- Core Identity, Users, User Profiles, Roles, and Permissions

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid VARCHAR(128) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    username VARCHAR(50) UNIQUE NOT NULL,
    normalized_username VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    avatar_url TEXT,
    country VARCHAR(10),
    supported_team VARCHAR(100) DEFAULT 'General Fan',
    supported_team_logo TEXT,
    is_youtube_member BOOLEAN DEFAULT FALSE,
    youtube_member_since TIMESTAMPTZ,
    youtube_channel_id VARCHAR(128),
    account_status VARCHAR(20) DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'banned', 'pending_deletion')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_active_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_normalized_username ON users(normalized_username);
CREATE INDEX IF NOT EXISTS idx_users_supported_team ON users(supported_team);

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    total_points INTEGER DEFAULT 50 NOT NULL,
    monthly_points INTEGER DEFAULT 50 NOT NULL,
    season_points INTEGER DEFAULT 50 NOT NULL,
    loyalty_points INTEGER DEFAULT 50 NOT NULL,
    streak_count INTEGER DEFAULT 0 NOT NULL,
    streak_best INTEGER DEFAULT 0 NOT NULL,
    streak_last_checkin TIMESTAMPTZ,
    level INTEGER DEFAULT 1 NOT NULL,
    exact_predictions_count INTEGER DEFAULT 0 NOT NULL,
    challenges_completed_count INTEGER DEFAULT 0 NOT NULL,
    player_cards_collected_count INTEGER DEFAULT 0 NOT NULL,
    is_guest BOOLEAN DEFAULT FALSE NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_total_points ON user_profiles(total_points DESC);
CREATE INDEX IF NOT EXISTS idx_user_profiles_monthly_points ON user_profiles(monthly_points DESC);
CREATE INDEX IF NOT EXISTS idx_user_profiles_season_points ON user_profiles(season_points DESC);

CREATE TABLE IF NOT EXISTS roles (
    id VARCHAR(30) PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    description TEXT
);

INSERT INTO roles (id, name, description) VALUES
('fan', 'Fan', 'Standard application user'),
('member', 'YouTube Member', 'Verified YouTube channel member with 2x point multiplier'),
('moderator', 'Moderator', 'Can manage community and user reports'),
('admin', 'Administrator', 'Full access to Admin Studio, match settlement, and rules')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id VARCHAR(30) REFERENCES roles(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE IF NOT EXISTS membership_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(30) NOT NULL,
    google_account_email VARCHAR(255),
    verified_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at TIMESTAMPTZ,
    metadata JSONB
);

CREATE INDEX IF NOT EXISTS idx_membership_history_user ON membership_history(user_id);
