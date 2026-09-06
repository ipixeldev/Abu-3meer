-- Keep paid subscriptions independent from imported YouTube membership. A
-- CSV replacement must never revoke a paid subscription, and a subscription
-- expiry must never clear a valid CSV membership or staff role.
CREATE TABLE IF NOT EXISTS user_subscription_entitlements (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entitlement_id VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT FALSE,
  product_id VARCHAR(255),
  expires_at TIMESTAMPTZ,
  will_renew BOOLEAN NOT NULL DEFAULT FALSE,
  is_sandbox BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at TIMESTAMPTZ NOT NULL,
  source_requested_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, entitlement_id)
);

CREATE INDEX IF NOT EXISTS user_subscription_active_expiry_idx
  ON user_subscription_entitlements(expires_at) WHERE is_active = TRUE;

CREATE TABLE IF NOT EXISTS revenuecat_webhook_receipts (
  event_id VARCHAR(255) PRIMARY KEY,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
