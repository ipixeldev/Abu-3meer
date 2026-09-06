import { config } from '../config.js';

/** SQL-only expression. The caller passes a hardcoded table alias/column. */
export function activeSubscriptionSql(userIdColumn: string): string {
  if (!/^[a-z_]+\.[a-z_]+$/.test(userIdColumn)) {
    throw new Error('Subscription SQL requires a trusted qualified column');
  }
  return `EXISTS (
    SELECT 1 FROM user_subscription_entitlements subscription_access
    WHERE subscription_access.user_id = ${userIdColumn}
      AND subscription_access.entitlement_id = 'abu_3meer_pro'
      AND subscription_access.is_active = TRUE
      AND subscription_access.expires_at > clock_timestamp()
      AND subscription_access.verified_at > clock_timestamp() - INTERVAL '24 hours'
      AND subscription_access.verified_at <= clock_timestamp() + INTERVAL '1 minute'
      AND (subscription_access.is_sandbox = FALSE OR ${config.revenueCat.allowSandbox ? 'TRUE' : 'FALSE'})
  )`;
}
