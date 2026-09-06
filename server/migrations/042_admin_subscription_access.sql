-- Local app-access overrides are not store purchases and must never rewrite
-- RevenueCat receipts, billing state, YouTube membership, or account roles.
CREATE TABLE IF NOT EXISTS user_subscription_access_overrides (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  mode VARCHAR(10) NOT NULL CHECK (mode IN ('active', 'inactive')),
  expires_at TIMESTAMPTZ,
  reason VARCHAR(500) NOT NULL CHECK (char_length(reason) BETWEEN 3 AND 500),
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (mode = 'active' OR expires_at IS NULL)
);

INSERT INTO permissions (id, name, category, description) VALUES
('subscriptions.manage', 'Manage Subscription Access', 'membership',
 'Grant, block, or restore store-controlled app access without changing store billing')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name,
 category = EXCLUDED.category, description = EXCLUDED.description;

INSERT INTO role_permissions (role_id, permission_id) VALUES
('admin', 'subscriptions.manage'), ('super_admin', 'subscriptions.manage')
ON CONFLICT DO NOTHING;

DELETE FROM role_permissions WHERE permission_id = 'subscriptions.manage'
 AND role_id NOT IN ('admin', 'super_admin');
