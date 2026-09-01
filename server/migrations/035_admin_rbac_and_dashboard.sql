-- 035_admin_rbac_and_dashboard.sql
-- Keep staff capabilities explicit:
--   * super_admin: every permission, including role administration
--   * admin: every permission except role administration
--   * moderator: user moderation/audit plus membership snapshot imports only

INSERT INTO permissions (id, name, category, description) VALUES
('membership_snapshots.manage', 'Manage Membership Snapshots',
 'membership', 'View status and replace the active YouTube membership CSV/TSV snapshot'),
('admin_dashboard.view', 'View Admin Dashboard Statistics',
 'analytics', 'View aggregate account, role, content, and engagement statistics')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description;

-- A moderator must not be able to create or change events/content. Retain the
-- existing user moderation and audit capabilities, and grant the one new
-- operational capability explicitly requested for the role.
DELETE FROM role_permissions
WHERE role_id = 'moderator'
  AND permission_id NOT IN (
    'users.view',
    'users.suspend',
    'audit.view',
    'membership_snapshots.manage'
  );

INSERT INTO role_permissions (role_id, permission_id) VALUES
('moderator', 'users.view'),
('moderator', 'users.suspend'),
('moderator', 'audit.view'),
('moderator', 'membership_snapshots.manage')
ON CONFLICT DO NOTHING;

-- Admin receives every current capability except changing staff roles.
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'admin', id
FROM permissions
WHERE id <> 'roles.manage'
ON CONFLICT DO NOTHING;

DELETE FROM role_permissions
WHERE role_id = 'admin'
  AND permission_id = 'roles.manage';

-- This mirrors the middleware's super-admin override in the database so role
-- inspection and future permission checks remain consistent.
INSERT INTO role_permissions (role_id, permission_id)
SELECT 'super_admin', id
FROM permissions
ON CONFLICT DO NOTHING;
