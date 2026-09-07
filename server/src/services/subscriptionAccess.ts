import { config } from '../config.js';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function validateUserIdColumn(userIdColumn: string): void {
  if (!/^[a-z_]+\.[a-z_]+$/.test(userIdColumn)) {
    throw new Error('Membership SQL requires a trusted qualified column');
  }
}

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

function accessOverrideDecisionSql(userIdColumn: string): string {
  return `(SELECT CASE
      WHEN access_override.mode = 'inactive' THEN FALSE
      WHEN access_override.mode = 'active' AND
        (access_override.expires_at IS NULL OR access_override.expires_at > clock_timestamp()) THEN TRUE
      ELSE NULL
    END
    FROM user_subscription_access_overrides access_override
    WHERE access_override.user_id = ${userIdColumn})`;
}

function verifiedStoreSubscriptionSql(userIdColumn: string): string {
  return `EXISTS (
    SELECT 1 FROM user_subscription_entitlements subscription_access
    WHERE subscription_access.user_id = ${userIdColumn}
      AND subscription_access.entitlement_id = 'abu_3meer_pro'
      AND subscription_access.is_active = TRUE
      AND subscription_access.product_id IS NOT NULL
      AND subscription_access.expires_at > clock_timestamp()
      -- Verification age is not a lease: background settlement must honor the
      -- authenticated store snapshot through its paid/grace-period expiry.
      -- Webhooks and explicit syncs replace this row on refund or revocation.
      AND subscription_access.verified_at IS NOT NULL
      AND subscription_access.verified_at <= clock_timestamp() + INTERVAL '1 minute'
      AND (
        subscription_access.is_sandbox = FALSE
        OR subscription_access.store_name IN ('app_store', 'play_store')
        OR ${sandboxPolicySql(userIdColumn)}
      )
  )`;
}

/**
 * Current manual YouTube verification before an admin access decision.
 * A claim is valid only for the exact active, unexpired CSV snapshot checked
 * by the user. Uploading a replacement CSV never silently renews that check.
 */
export function currentYouTubeMembershipSql(userIdColumn: string): string {
  validateUserIdColumn(userIdColumn);
  return `EXISTS (
    SELECT 1
    FROM youtube_account_links member_link
    JOIN youtube_membership_snapshot_state snapshot_state
      ON snapshot_state.singleton = TRUE
     AND snapshot_state.active_import_id = member_link.snapshot_import_id
    JOIN youtube_membership_snapshot_imports snapshot_import
      ON snapshot_import.id = snapshot_state.active_import_id
     AND snapshot_import.expires_at > clock_timestamp()
    JOIN youtube_channel_claims approved_claim
      ON approved_claim.user_id = member_link.user_id
     AND approved_claim.youtube_channel_id = member_link.youtube_channel_id
     AND approved_claim.status = 'approved'
     AND approved_claim.approved_snapshot_import_id = snapshot_state.active_import_id
    WHERE member_link.user_id = ${userIdColumn}
      AND member_link.is_member = TRUE
      AND member_link.verification_source = 'admin_snapshot'
  )`;
}

/** Effective subscription/admin access without considering YouTube. */
export function activeSubscriptionSql(userIdColumn: string): string {
  validateUserIdColumn(userIdColumn);
  // NULL from an expired grant (or no override) falls through to store status.
  // An explicit inactive override remains FALSE even while billing continues.
  return `COALESCE(
    ${accessOverrideDecisionSql(userIdColumn)},
    ${verifiedStoreSubscriptionSql(userIdColumn)}
  )`;
}

/** Effective member access with one final admin override across every source. */
export function activeMemberAccessSql(userIdColumn: string): string {
  validateUserIdColumn(userIdColumn);
  return `COALESCE(
    ${accessOverrideDecisionSql(userIdColumn)},
    (${currentYouTubeMembershipSql(userIdColumn)}
      OR ${verifiedStoreSubscriptionSql(userIdColumn)})
  )`;
}

/** Effective YouTube badge state; a final admin block suppresses the badge. */
export function activeYouTubeMembershipSql(userIdColumn: string): string {
  validateUserIdColumn(userIdColumn);
  return `(${currentYouTubeMembershipSql(userIdColumn)}
    AND ${activeMemberAccessSql(userIdColumn)})`;
}
