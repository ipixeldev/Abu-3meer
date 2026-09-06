# RC-23: confirmed findings and next owner action

Checked 6 September 2026 after the physical-device build 20 report.

## Confirmed

- The released app uses the real App Store public SDK key (`appl_`), not RevenueCat Test Store.
- RevenueCat returns the published `default` offering/paywall and the exact Apple product IDs `Ostoora3` and `Ostoora3_Pro_Max`.
- Apple lists both products as READY_TO_SUBMIT, with prices and availability in 175 territories. They are not approved for public sale yet. READY_TO_SUBMIT does not by itself explain a TestFlight product lookup failure.
- The device reports configuration error RC-23. Without its underlying native error or agreement status, the exact cause is not established.
- The existing `dev` customer in the same RevenueCat project currently has neither expected subscription nor `abu_3meer_pro`. This agrees with the server's `no_entitlement`; it is not a rejected active sandbox subscription.
- The server diagnostic's `runtimeSupportsAccessReasons: false` means the running container predates the newer diagnostic fields. Pulling Git alone does not update a running Docker image.

## Owner action needed now

1. Sign in to the **client's** App Store Connect account.
2. Open **Business**, then **Agreements**. Check **Paid Applications** is **Active**, not New/Pending/Action Needed.
3. Complete any required tax forms and banking setup through Apple's prompts. Only the account holder should accept agreements or provide financial details.
4. Send the agreement status and any warning text, hiding bank/tax details. Do not send private keys.
5. If all requirements already show active/complete, capture the failing phone's native RevenueCat/StoreKit configuration error around opening View plans. Do not recreate products, rotate keys, or enable test entitlements as a guess.

These prerequisites apply even before public release. See [RevenueCat's iOS setup requirements](https://www.revenuecat.com/docs/getting-started/entitlements/ios-products) and [empty-products troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings).

## Update the running backend after pulling the branch

From the existing server checkout, with the same `.env` preserved:

```bash
cd /opt/abu3meer/server
docker compose config -q
docker compose build api
docker compose up -d --no-deps --force-recreate api
curl -fsS https://api.abu3meer.com/ready
docker compose exec -T api node --input-type=module - --username dev < scripts/diagnose_subscriptions.mjs
```

Stop on any command failure. This updates the existing API image; it does not delete the database. It does **not** fix Apple's product lookup or manufacture a subscription. Leave `REVENUECAT_ALLOW_SANDBOX=false` for the current production-only policy. The account will remain inactive until a valid purchase is recognized and verified.

## Icon correction in build 21

The exact user-supplied JPG is rendered through a circular viewport. No generated/redrawn replacement is used. The old distorted PNG is removed from the bundled assets and remains recoverable in Git history.
