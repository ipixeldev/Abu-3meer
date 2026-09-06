import { config } from '../config.js';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function sandboxPolicySql(userIdColumn: string): string {
  if (config.revenueCat.allowSandbox) return 'TRUE';
  // Config parsing already validates these values. Revalidate at the SQL
  // boundary as defense in depth because this function returns SQL text.
  const reviewerIds = config.revenueCat.sandboxAllowedUserIds
    .filter(value => uuid.test(value))
    .slice(0, 20);
  if (reviewerIds.length === 0) return 'FALSE';
  const literals = reviewerIds.map(value => `'${value.toLowerCase()}'::uuid`).join(', ');
  return `${userIdColumn} = ANY(ARRAY[${literals}])`;
}

/** SQL-only expression. The caller passes a hardcoded table alias/column. */
export function activeSubscriptionSql(userIdColumn: string): string {
  if (!/^[a-z_]+\.[a-z_]+$/.test(userIdColumn)) {
    throw new Error('Subscription SQL requires a trusted qualified column');
  }
  // NULL from an expired grant (or no override) falls through to store status.
  // An explicit inactive override remains FALSE even while billing continues.
  return `COALESCE((
    SELECT CASE
      WHEN access_override.mode = 'inactive' THEN FALSE
      WHEN access_override.mode = 'active' AND
        (access_override.expires_at IS NULL OR access_override.expires_at > clock_timestamp()) THEN TRUE
      ELSE NULL
    END
    FROM user_subscription_access_overrides access_override
    WHERE access_override.user_id = ${userIdColumn}
  ), EXISTS (
    SELECT 1 FROM user_subscription_entitlements subscription_access
    WHERE subscription_access.user_id = ${userIdColumn}
      AND subscription_access.entitlement_id = 'abu_3meer_pro'
      AND subscription_access.is_active = TRUE
      AND subscription_access.product_id IS NOT NULL
      AND subscription_access.expires_at > clock_timestamp()
      AND subscription_access.verified_at > clock_timestamp() - INTERVAL '24 hours'
      AND subscription_access.verified_at <= clock_timestamp() + INTERVAL '1 minute'
      AND (subscription_access.is_sandbox = FALSE OR ${sandboxPolicySql(userIdColumn)})
  ))`;
}
