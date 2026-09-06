# Production release: what remains

The iOS app uses the public App Store `appl_` SDK key and the real products `Ostoora3` and `Ostoora3_Pro_Max`. The server's private `sk_` credential stays in its existing environment file. A release build cannot silently switch to RevenueCat Test Store.

## Subscription screens

- Members Zone uses a compact membership row, not a full-page subscription form.
- Manage/Details opens the detailed controls on demand.
- View plans opens RevenueCat's native paywall for the current offering. The existing `default` offering was verified to serve the published custom paywall, revision 98, on 6 September 2026. Do not recreate the products or enter replacement prices in app code.
- The paid badge is based on the server's verified profile, never just the store's "already subscribed" alert.

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

In the updated app open Members Zone → Details/Manage → Refresh access. The detailed result distinguishes production-only test rejection from missing entitlements, expiry, and temporary verification failures. Do not purchase again to try to fix an activation issue.

## TestFlight is not the public App Store

TestFlight always uses sandbox purchases. The same production-ready binary and `appl_` key use real payments once installed from the public App Store. With production-only server policy, a TestFlight test subscription intentionally gets no production access or badge.

The external TestFlight link is enabled and below its tester limit, but builds 17/18 had not passed Beta App Review at the time of the audit. Complete TestFlight → Test Information → Beta App Review Information (contact first/last name, email, phone, and a working dedicated review login). Do not paste the review password in chat. External testing then requires a Beta App Review submission and approval.

## Before public App Review

- Complete reviewer contact details and a working review login under App Review Information as well.
- Supply copyright holder text and an accurate third-party content-rights declaration. Football logos/videos mean "does not use third-party content" cannot be assumed.
- Add the required primary Arabic screenshots.
- Confirm and publish App Privacy answers, age rating, regional/trader and business agreement information in App Store Connect. Do not guess legal declarations.
- Attach both first subscriptions to the app-version review submission. Both products have complete required metadata but are not yet approved.
- Configure and verify RevenueCat webhooks so renewals, refunds, expirations and transfers reach the server.
- Verify a reviewer purchase can unlock the advertised features. Apple reviews in sandbox; a production-only server that rejects the review purchase will fail that flow. Use an intentional review/test environment or agree a tightly scoped reviewer-access policy before submission. Do not silently grant test users paid production badges.

No Beta App Review, public App Review or public release has been submitted by this update.

References: [RevenueCat: Apple App Store and TestFlight](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store), [Apple: invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).
