-- 006_gamification_rewards.sql
-- Streaks, Levels, Achievements, Loyalty, and Prizes

CREATE TABLE IF NOT EXISTS user_streaks (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    current_streak INTEGER DEFAULT 0 NOT NULL,
    longest_streak INTEGER DEFAULT 0 NOT NULL,
    last_checkin_date DATE NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS achievements (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT NOT NULL,
    icon_name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    target_count INTEGER DEFAULT 1 NOT NULL,
    reward_points INTEGER DEFAULT 0 NOT NULL,
    badge_tier VARCHAR(30) DEFAULT 'bronze' CHECK (badge_tier IN ('bronze', 'silver', 'gold', 'diamond')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS user_achievements (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    achievement_id VARCHAR(100) REFERENCES achievements(id) ON DELETE CASCADE,
    progress INTEGER DEFAULT 0 NOT NULL,
    unlocked BOOLEAN DEFAULT FALSE NOT NULL,
    unlocked_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, achievement_id)
);

CREATE TABLE IF NOT EXISTS prize_configurations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_type VARCHAR(20) NOT NULL CHECK (period_type IN ('monthly', 'season', 'special')),
    period_key VARCHAR(50) NOT NULL,
    rank_from INTEGER NOT NULL,
    rank_to INTEGER NOT NULL,
    title VARCHAR(150) NOT NULL,
    reward_description TEXT NOT NULL,
    badge_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS prize_winners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prize_id UUID REFERENCES prize_configurations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    final_rank INTEGER NOT NULL,
    points_total INTEGER NOT NULL,
    period_key VARCHAR(50) NOT NULL,
    awarded_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);
