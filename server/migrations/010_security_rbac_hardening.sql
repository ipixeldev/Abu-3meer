-- 010_security_rbac_hardening.sql
-- Granular RBAC Permissions, Super Admin Role, and Anti-Abuse Tables

INSERT INTO roles (id, name, description) VALUES
('super_admin', 'Super Administrator', 'Full platform access including role management and system security')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS permissions (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL,
    description TEXT
);

INSERT INTO permissions (id, name, category, description) VALUES
('matches.manage', 'Manage Matches', 'football', 'Create, edit, cancel and settle match results'),
('predictions.manage', 'Manage Predictions', 'football', 'View, audit, and force-settle match predictions'),
('challenges.manage', 'Manage Challenges', 'engagement', 'Create, update, schedule, and archive challenges'),
('player_cards.manage', 'Manage Player Cards', 'engagement', 'Create and manage player card drops'),
('points.adjust', 'Adjust Points', 'points', 'Manually grant or deduct points with mandatory audit logging'),
('users.view', 'View Users', 'users', 'View detailed user profiles and moderation notes'),
('users.suspend', 'Suspend Users', 'users', 'Temporarily suspend user accounts'),
('users.ban', 'Ban Users', 'users', 'Permanently ban malicious or abusive accounts'),
('leaderboards.manage', 'Manage Leaderboards', 'competition', 'Recalculate or freeze leaderboard periods'),
('prizes.manage', 'Manage Prizes', 'rewards', 'Configure rewards and assign prize winners'),
('notifications.send', 'Broadcast Notifications', 'communication', 'Send push notification campaigns via FCM'),
('roles.manage', 'Manage Admin Roles', 'security', 'Grant or revoke administrative and moderator roles'),
('settings.manage', 'Manage Platform Settings', 'system', 'Modify point rules, feature flags, and platform configs'),
('audit.view', 'View Audit Logs', 'security', 'View security events and admin activity logs')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id VARCHAR(30) REFERENCES roles(id) ON DELETE CASCADE,
    permission_id VARCHAR(50) REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Seed role_permissions
-- Super Admin gets all permissions
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'super_admin', id FROM permissions
ON CONFLICT DO NOTHING;

-- Admin gets all except roles.manage and system-critical settings
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'admin', id FROM permissions
WHERE id NOT IN ('roles.manage')
ON CONFLICT DO NOTHING;

-- Moderator gets user moderation and challenge management
INSERT INTO role_permissions (role_id, permission_id)
VALUES
('moderator', 'users.view'),
('moderator', 'users.suspend'),
('moderator', 'challenges.manage'),
('moderator', 'audit.view')
ON CONFLICT DO NOTHING;

-- Anti-Brute Force Attempt Tracker for Challenges and Player Cards
CREATE TABLE IF NOT EXISTS challenge_attempt_locks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    challenge_id VARCHAR(100) NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    failed_attempts INTEGER DEFAULT 0 NOT NULL,
    locked_until TIMESTAMPTZ,
    last_attempt_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uq_user_challenge_lock UNIQUE (user_id, challenge_id)
);

CREATE INDEX IF NOT EXISTS idx_attempt_locks_user ON challenge_attempt_locks(user_id, challenge_id);
