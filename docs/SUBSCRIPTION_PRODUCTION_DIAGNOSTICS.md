# Diagnose subscription access without changing it

Apple showing **Active** does not prove that the server sees a production
entitlement for the same Abu 3meer account. TestFlight, Xcode, and App Review
transactions are sandbox purchases. Do not buy again, edit entitlement rows, or
enable sandbox globally to hide an account/configuration problem.

## Read the running API's saved store decision

Run these blocks separately on Ubuntu. Stop after an error. No `.env` value,
receipt, key, email, password, or database user ID is printed by the report.

```bash
cd /opt/abu3meer
```

```bash
git status --short
```

Stop before pulling if tracked files are modified.

```bash
git fetch origin agent/production-backend
```

```bash
git merge --ff-only origin/agent/production-backend
```

```bash
cd /opt/abu3meer/server
```

```bash
docker compose exec -T api node --input-type=module - --username dev < scripts/diagnose_subscriptions.mjs
```

Replace `dev` only with the affected app username. The script is streamed from
the checked-out source into the **currently running** API container and runs a
parameterized `SELECT` inside a read-only transaction. It does not contact
RevenueCat, restore a purchase, refresh a receipt, or change any access state.

A Git commit hash or successful `/ready` response alone does not prove that the
new image is running. After deploying the current server revision, the startup
log must show migrations 042, 043, and 044 as applied or already applied.

## Report fields

| Field | Meaning |
| --- | --- |
| `runtimeSupportsAccessReasons` | Whether the running API exposes the modern access-reason contract. `false` means its image predates that contract. |
| `serverKeyConfigured` | A server-key-shaped `sk_` value exists. It does not prove the credential is valid or belongs to this RevenueCat project. |
| `sandboxAllowed` near the top | Whether the escape hatch for RevenueCat Test Store/unknown-provider sandbox rows is enabled. It should remain `false` in production. |
| `sandboxAllowed` in an account result | Whether this account has that escape hatch. Genuine `app_store`/`play_store` sandbox receipts do not require it. |
| `snapshotPresent` | The database has a saved RevenueCat verification row for this account. |
| `sourceEntitlementActive` | RevenueCat's last saved upstream entitlement was active before local access policy was applied. |
| `isSandbox` | The saved receipt came from sandbox. This remains truthful even when a verified Apple/Google test receipt grants member access. |
| `verificationTimestampValid` | The saved authenticated verification timestamp exists and is not unreasonably in the future. |
| `verificationAgeSeconds` | Informational age of the saved verification. Age alone does not revoke an otherwise active entitlement before its store expiry. |
| `accessReason: active` | The saved store entitlement currently passes active-state, expiry, verification-timestamp, and environment policy. |
| `accessReason: sandbox_not_allowed` | The row is RevenueCat Test Store or has unknown provider provenance and no explicit escape hatch. |
| `accessReason: no_entitlement` | No recognized `abu_3meer_pro` product is saved for this app account. This alone does not prove an account mismatch. |
| `accessReason: expired` | The saved entitlement expiry is in the past. |
| `accessReason: verification_required` | The saved verification timestamp is missing, malformed, or unreasonably in the future; an authenticated server-to-RevenueCat sync is needed. |
| `accessReason: inactive` | The saved source is refunded, malformed, or otherwise not active. |
| `accessActive` | The store snapshot passes the policy represented by this diagnostic report. |

An authenticated active store snapshot remains effective through its saved
paid/grace-period expiry even when `verificationAgeSeconds` exceeds 24 hours.
This keeps background prediction settlement consistent for users who do not
reopen the app daily. RevenueCat webhooks and explicit **Refresh access** syncs
must remain configured so refunds, transfers, and other upstream revocations
replace the cached row promptly.

The diagnostic intentionally reports the saved **store** snapshot. Migration
042 adds a separate admin access override; Admin Studio can grant or block app
access without rewriting the store row. Therefore an authenticated profile may
show `admin_granted` or `admin_revoked` even when this store-only report shows a
different underlying result. Use **Use store status** in Admin Studio to remove
that override; never edit either table directly.

## Refresh versus this read-only report

**Refresh access** in the signed-in app performs the live server-to-RevenueCat
sync. The server first requests the production customer. When it has no active
production entitlement, it performs the explicit sandbox request. A returned
active sandbox entitlement grants access when its persisted provider is
`app_store` or `play_store`. RevenueCat Test Store and legacy unknown-provider
rows additionally require either the global `REVENUECAT_ALLOW_SANDBOX` switch
or the app user's PostgreSQL UUID in `REVENUECAT_SANDBOX_ALLOWED_USER_IDS`.

This production-first order prevents a test purchase from shadowing a real paid
subscription. Keep `REVENUECAT_ALLOW_SANDBOX=false`. After migration 044, tap
**Refresh access** once for an existing TestFlight/Play tester so `store_name`
is populated. RevenueCat's own sandbox restriction, if enabled, is independent.

The `dev` evidence already showed the distinction: the production lookup had no
entitlement while the explicit sandbox lookup contained the active test
purchase. That is not a production subscription and must not be relabeled as
one.

## RC-23 is a different layer

`RC-23` with `Returned products: none` occurs before a new purchase can start:
StoreKit returned none of the requested products. The server access report
cannot repair or diagnose Apple's product catalog. Use the app's **Check store
connection → Copy report** after the Paid Applications change has had up to 24
hours to propagate, then follow [RC23_STORE_ACTIONS.md](RC23_STORE_ACTIONS.md).

The August 1, 2013 original-download date shown in sandbox Customer Center is
Apple sandbox metadata, not the app's release date or the subscription start.
It is not used for access.

References: [RevenueCat Apple sandbox/TestFlight behavior](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
[RevenueCat sandbox access controls](https://www.revenuecat.com/docs/projects/sandbox-access),
[Apple AppTransaction original purchase date](https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate).
