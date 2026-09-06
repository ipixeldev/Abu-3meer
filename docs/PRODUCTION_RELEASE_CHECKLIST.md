# Production release: what remains

The iOS app uses the public App Store `appl_` SDK key and the real products `Ostoora3` and `Ostoora3_Pro_Max`. The server's private `sk_` credential stays in its existing environment file. A release build cannot silently switch to RevenueCat Test Store.

## Subscription screens

- Members only uses a compact membership row and the green-star icon, not a full-page subscription form.
- Manage/Details opens the detailed controls on demand.
- View plans opens a dedicated full-screen route immediately, then loads the current offering into RevenueCat's native `PaywallView`. Store failures stay on that screen with Retry/Close and a safe `RC-…` code; they do not bounce back into a second View plans dialog. The existing `default` offering was verified to serve the published custom paywall, revision 98, on 6 September 2026. Do not recreate the products or enter replacement prices in app code.
- The paid badge is based on the server's verified profile, never just the store's "already subscribed" alert.
- Build 20 also fixes the signup country keyboard overlap, RTL fan-card edit/XP overlap, and stale-language subscription messages. The SDK receives the app's selected language; RevenueCat dashboard content still needs its own matching localization.

## Physical-device paywall failure: what to check

Apple currently lists both subscriptions as Ready to Submit with current prices in 175 territories, including Sweden, USA and Saudi Arabia. RevenueCat returns both product IDs and the published paywall. These checks do not prove Apple can return StoreKit products on the affected phone.

1. On the client's App Store Connect account, open **Business → Agreements**. **Paid Applications must be Active**, with any required banking/tax setup complete. This cannot be inspected through the public App Store Connect API. The browser session was signed out during our audit; no agreement was accepted on your behalf.
2. Install build 20, open **Members only → View plans** (or **Details → View plans** if the account already has a store subscription). If it fails, send the `RC-…` code from the screen. Do not send keys, receipts or passwords.
3. `RC-23` means a store/RevenueCat configuration error, `RC-5` means a product is unavailable, `RC-11` means credentials, and `RC-17` means the Apple subscription key. These are categories, not proof of one specific missing setting. Connection errors have separate messages.
4. For missing server access/badges, run the read-only report in [SUBSCRIPTION_PRODUCTION_DIAGNOSTICS.md](SUBSCRIPTION_PRODUCTION_DIAGNOSTICS.md). It determines the running server's actual denial reason; a healthy `/ready` and unauthenticated `401` cannot do that.

The simulator rendered the published paywall without a new purchase. A successful physical-device purchase/activation has **not** been verified by this update.

## Update the existing server

Your previous deployment already applied migrations 040/041 and created a database backup. This follow-up adds clearer status reasons and a timestamp guard; no new migration is required. Run each block on the Ubuntu server separately and stop on an error.

```bash
cd /opt/abu3meer
```

```bash
git status --short
```

Stop if tracked files have edits. Keep the existing environment files and backups private; do not add them to Git.

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
nano .env
```

Keep your new RevenueCat secret unchanged. For your requested production-only policy, set `REVENUECAT_ALLOW_SANDBOX=false`. Save with Ctrl+O, Enter, Ctrl+X.

```bash
docker compose config -q
```

```bash
docker compose build api
```

```bash
docker compose up -d --no-deps --force-recreate api
```

```bash
curl -sS https://api.abu3meer.com/ready
```

No users, points, CSV uploads, or subscriptions are deleted. Do not run `docker compose down -v`.

In the updated app open Members only → Details/Manage → Refresh access. The detailed result distinguishes production-only test rejection from missing entitlements, expiry, and temporary verification failures. Do not purchase again to try to fix an activation issue.

## TestFlight is not the public App Store

TestFlight always uses sandbox purchases. The same production-ready binary and `appl_` key use real payments once installed from the public App Store. With production-only server policy, a TestFlight test subscription intentionally gets no production access or badge.

The **1 August 2013** original-download date in Customer Center is Apple's documented sandbox `AppTransaction.originalPurchaseDate` placeholder. It is not the app release date, the user's birthday, or a subscription start date. See [Apple's date documentation](https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate).

The external TestFlight link is enabled and below its tester limit, but builds 17/18 had not passed Beta App Review at the time of the audit. Complete TestFlight → Test Information → Beta App Review Information (contact first/last name, email, phone, and a working dedicated review login). Do not paste the review password in chat. External testing then requires a Beta App Review submission and approval.

## Before public App Review

- Complete reviewer contact details and a working review login under App Review Information as well.
- Supply copyright holder text and an accurate third-party content-rights declaration. Football logos/videos mean "does not use third-party content" cannot be assumed.
- Current primary Arabic screenshots were uploaded on 6 September 2026 from full build 20 at native 1320×2868 resolution (Predictions and Leaderboard); both completed processing. Refresh them if those screens change.
- Confirm and publish App Privacy answers, age rating, regional/trader and business agreement information in App Store Connect. Do not guess legal declarations.
- Attach both first subscriptions to the app-version review submission. Both products have complete required metadata but are not yet approved.
- Configure and verify RevenueCat webhooks so renewals, refunds, expirations and transfers reach the server.
- Verify a reviewer purchase can unlock the advertised features. Apple reviews in sandbox; a production-only server that rejects the review purchase will fail that flow. Use an intentional review/test environment or agree a tightly scoped reviewer-access policy before submission. Do not silently grant test users paid production badges.

No Beta App Review, public App Review or public release has been submitted by this update.

References: [RevenueCat: Apple App Store and TestFlight](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store), [Apple: invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).
