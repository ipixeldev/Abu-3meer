# RC-23: confirmed findings and next owner action

Updated 6 September 2026 after the physical-device RC-23 report and successful backend rebuild.

## Confirmed

- The released app uses the real App Store public SDK key (`appl_`), not RevenueCat Test Store.
- RevenueCat returns the published `default` offering/paywall and the exact Apple product IDs `Ostoora3` and `Ostoora3_Pro_Max`.
- Apple lists both products as READY_TO_SUBMIT, with prices and availability in 175 territories. They are not approved for public sale yet. READY_TO_SUBMIT does not by itself explain a TestFlight product lookup failure.
- The device reports configuration error RC-23. Without its underlying native error or agreement status, the exact cause is not established.
- The existing `dev` customer's **production** RevenueCat response has neither expected subscription nor `abu_3meer_pro`. This agrees with the server's `no_entitlement`.
- Follow-up native-SDK header inspection found that RevenueCat sends `X-Is-Sandbox`. Querying the same existing customer with that header `true` returns `Ostoora3_Pro_Max` and `abu_3meer_pro`, with `is_sandbox: true`; setting it `false` returns no subscription. Thus a test subscription DOES exist, but no production subscription is recognized. The earlier header-less check was not an inventory of both environments. Do not turn the test record into a production grant.
- The earlier `runtimeSupportsAccessReasons: false` diagnostic was collected before the backend rebuild. The user has since successfully built the API image and force-recreated it with `--wait`; Docker reports **Healthy** and `/ready` succeeds. Repeating that deployment is not the next RC-23 fix.
- The client's **Paid Applications agreement status remains unverified**. No evidence currently establishes that it is inactive.

## RecipeRift comparison

The [read-only RecipeRift comparison](RECIPERIFT_SUBSCRIPTIONS_COMPARISON.md) found the same normal RevenueCat native SDK/paywall flow, with SwiftUI instead of Flutter and a **different Apple developer team**. There is no alternative billing workaround to copy. Working purchases in RecipeRift do not verify the client's Abu3meer agreement status or identify the exact RC-23 cause.

## Owner action needed now

1. Sign in to the **client's** App Store Connect account.
2. Open **Business → Agreements** and check the **Paid Applications** status. Report whether it is **Active** or shows an action-needed status; its current state has not been confirmed.
3. If Apple requests agreement, tax, or banking actions, have the account holder complete them through Apple's prompts. Do not assume anything needs changing if it already shows complete.
4. Send the agreement status and any warning text, hiding bank/tax details. Do not send private keys.
5. In build 23 or later, open **Members → View plans**. If Plans unavailable appears, tap **Check store connection**, wait up to 15 seconds, then **Copy report** and send that text. It first checks SDK initialization, then checks the two real product IDs without buying, restoring, changing accounts, or granting access. The report excludes account IDs, keys, receipts, and raw native messages. SDK product reads may use cached data; this is not proof of a fresh Apple request or production approval. Build 22 is superseded by the guarded diagnostic in 23; do not use 22.
6. If both products load but the paywall still fails after Retry, or the account requirements are all complete, capture the failing phone's native RevenueCat/StoreKit error around opening View plans. Do not recreate products, rotate keys, or enable test entitlements as a guess.

These prerequisites apply even before public release. See [RevenueCat's iOS setup requirements](https://www.revenuecat.com/docs/getting-started/entitlements/ios-products) and [empty-products troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings).

## Backend update is complete

The successful Docker build, forced recreation with `--wait`, **Healthy** status, and `/ready` response confirm backend readiness. **No additional Docker command is required for the reported RC-23 issue.** These checks do not prove that Apple's product lookup works or that a production subscription exists.

Leave `REVENUECAT_ALLOW_SANDBOX=false` for the current production-only policy. A sandbox purchase must not be converted into production access; subscriber access still requires a recognized, verified production entitlement.

## Icon correction in build 21

The exact user-supplied JPG is rendered through a circular viewport. No generated/redrawn replacement is used. The old distorted PNG is removed from the bundled assets and remains recoverable in Git history.
