# Diagnose subscription access without changing it

The store saying **Active** does not establish that a subscription is a paid production purchase. A TestFlight or Xcode receipt can be active but intentionally denied by the production server. Do not buy it again, change database membership flags, or enable sandbox access just to remove that message.

## Read the running server's decision

After this release is published to GitHub, run each block separately on Ubuntu. Stop if any command fails. No `.env` values or private keys need to be copied or shared.

```bash
cd /opt/abu3meer
```

```bash
git status --short
```

If tracked files are modified, stop before pulling. Preserve those changes.

```bash
git rev-parse --short HEAD
```

`17e5a4f` added subscription verification; `56e79db` added explicit access reasons. The checkout revision alone does not prove which image is currently running.

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

Replace `dev` only if the affected account has a different app username. This streams the diagnostic script into the **currently running API image**; it also works with the older `17e5a4f` image and requires no rebuild for the diagnostic itself. It performs a parameterized database `SELECT` in a read-only transaction. It does not contact RevenueCat, refresh receipts, write entitlements, or change settings.

The report omits private keys, tokens, email addresses and account IDs. It only contains the selected username, configuration booleans and a minimized subscription snapshot. Review it before sharing.

| Report field | Meaning |
| --- | --- |
| `runtimeSupportsAccessReasons: false` | The running API predates the new status diagnostics, even if the checkout has been updated. |
| `serverKeyConfigured: true` | A server-key-shaped value is configured; this does **not** prove it is valid or belongs to the correct RevenueCat project. |
| `sandboxAllowed: false` | The running server intentionally rejects sandbox access. |
| `sourceEntitlementActive: true` | The last verified upstream subscription was active. This alone does not grant production access. |
| `accessReason: sandbox_not_allowed` | A stored active test subscription is rejected by current production policy. |
| `accessReason: no_entitlement` | No recognized entitlement is stored for this account. This does not prove an account mismatch. |
| `accessReason: expired` | The stored entitlement has expired. |
| `accessReason: verification_required` | The verification lease needs a fresh server-to-server check. |
| `accessReason: inactive` | The stored source is inactive or incomplete. |
| `accessActive: true` | The running server's policy currently allows the stored entitlement. |

This is a report of the last saved verification, not a live RevenueCat lookup. **Refresh access** in the signed-in app is the separate action that requests a fresh verification. Never infer production billing from `isSandbox: false` when `snapshotPresent` is false.

## Production and Apple review are different

Apple uses a fixed **August 1, 2013** sandbox value for the app's `originalPurchaseDate`. That is app-purchase metadata, not the subscription's actual start or expiry date. It must not be used to grant membership. [Apple's originalPurchaseDate documentation](https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate)

TestFlight uses sandbox purchases even when signed into a real Apple account. Changing the public SDK key or rebuilding cannot turn those test transactions into paid production purchases. [RevenueCat's TestFlight documentation](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store)

**Remaining review blocker:** Apple also assesses in-app purchases in its sandbox. A production-only server that rejects every sandbox transaction cannot demonstrate the complete purchase-to-unlock flow to App Review. Keep production policy unchanged until a deliberate review-access design is approved; do not describe this as fully review-ready yet. [Apple App Review guidance](https://developer.apple.com/forums/thread/810791), [RevenueCat's review troubleshooting](https://www.revenuecat.com/docs/test-and-launch/app-store-rejections)

A possible next step is dedicated review accounts with an explicit server-side allowlist and RevenueCat's matching **Allowed App User IDs** setting. That is **not implemented** by this diagnostic script. Such access must still require a verified store receipt, be documented to App Review, and remain distinct from a public paid-production badge. [RevenueCat sandbox access controls](https://www.revenuecat.com/docs/projects/sandbox-access)
