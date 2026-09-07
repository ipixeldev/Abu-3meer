-- Retain the verified RevenueCat store provider so genuine Apple/Google
-- sandbox purchases can grant test-track access without also trusting the
-- RevenueCat Test Store. Existing production rows remain valid; legacy
-- sandbox rows must be refreshed once to establish their store provenance.

ALTER TABLE user_subscription_entitlements
  ADD COLUMN IF NOT EXISTS store_name VARCHAR(32);

ALTER TABLE user_subscription_entitlements
  DROP CONSTRAINT IF EXISTS user_subscription_entitlements_store_name_valid;

ALTER TABLE user_subscription_entitlements
  ADD CONSTRAINT user_subscription_entitlements_store_name_valid
  CHECK (
    store_name IS NULL
    OR store_name IN ('app_store', 'play_store', 'test_store')
  );
