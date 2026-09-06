# Production release checklist

The application code is configured for the real Abu 3meer App Store app: the
iOS client uses its public RevenueCat `appl_` SDK key, the server keeps the
private `sk_` key, and the product identifiers are `Ostoora3` and
`Ostoora3_Pro_Max`. A release build cannot silently fall back to RevenueCat Test
Store or the repository's local StoreKit preview catalog.

This checklist separates code/deployment work from account-owner actions. A
successful build or healthy `/ready` response does not make an App Store
submission ready by itself.

## Implemented application behavior

- The navigation label is **Members** and uses the supplied green-star artwork.
- **View plans** opens a dedicated screen and presents RevenueCat's native
  `PaywallView` for the current offering. A store lookup failure stays on that
  screen with Retry, Close, a sanitized `RC-…` code, and a read-only product
  report.
- Access and subscriber badges use the authenticated server decision. An Apple
  or RevenueCat client alert alone never grants protected access.
- Subscription refresh bypasses stale client state. An administrator block is
  shown as an access decision and does not prompt the user to buy again.
- Admin Studio has a separate **Membership access** directory for admins and
  super admins. It can grant app access, block app access, or return a user to
  store-controlled status. Migration `042_admin_subscription_access.sql`
  records these overrides and their audit history. This never cancels, renews,
  refunds, or invents an App Store purchase, and it does not change YouTube CSV
  membership.
- A WhatsApp support action is available from the app's support and subscription
  failure surfaces. It opens only a server-validated `wa.me` number; when the
  server setting is blank, the app shows the existing support email instead of
  opening a placeholder chat.
- The signup country selector avoids the keyboard, Arabic fan-card metrics no
  longer overlap, and the YouTube check accepts resolvable channel/profile URLs
  (including `@handle` profiles) while returning a friendly not-member result
  when the channel is absent from the current CSV snapshot.

## Deploy the current server revision

The current revision contains server changes beyond migrations 040/041. The
earlier successful Docker recreation does **not** deploy the admin override,
review-account allowlist, or WhatsApp support changes. Pull the new revision,
back up PostgreSQL, update `.env`, rebuild the API image, and recreate the API.
Migration 042 runs automatically at API startup.

Keep these production values in `/opt/abu3meer/server/.env`:

```dotenv
REVENUECAT_SECRET_API_KEY=sk_...
REVENUECAT_ALLOW_SANDBOX=false
REVENUECAT_SANDBOX_ALLOWED_USER_IDS=<dedicated-review-app-account-postgresql-uuid>
SUPPORT_WHATSAPP_NUMBER=
```

`REVENUECAT_SANDBOX_ALLOWED_USER_IDS` is a comma-separated list of app-account
PostgreSQL UUIDs, not emails, Apple IDs, Firebase UIDs, or RevenueCat keys. Use
only dedicated TestFlight/App Review accounts. Leave
`SUPPORT_WHATSAPP_NUMBER` blank until the business number is known; blank safely
disables WhatsApp. When enabled, enter the international number with country
code using digits only, without `+`, spaces, `00`, or a local trunk prefix.

The detailed, non-destructive commands are in
[DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md](DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md). Do not
run `docker compose down -v`.

## Production-first TestFlight and App Review access

TestFlight and App Review purchases use Apple's sandbox even though the same
binary uses the production `appl_` key. Keep the global server switch
`REVENUECAT_ALLOW_SANDBOX=false`.

For the dedicated review account only:

1. Put its PostgreSQL user UUID in
   `REVENUECAT_SANDBOX_ALLOWED_USER_IDS` and redeploy the API.
2. In RevenueCat, open the project **Sandbox Testing Access** settings, choose
   **Allowed App User IDs only**, and add the same UUID. The app identifies the
   RevenueCat customer with this UUID.
3. Sign into that exact app account in TestFlight and use Restore/Refresh once
   if it already owns the test subscription.

The server always asks RevenueCat for production state first. Only if that exact
allowlisted account has no active production entitlement does it perform the
explicit sandbox lookup. An active production entitlement therefore cannot be
shadowed by test data, and sandbox access remains unavailable to every other
production user. Do not set the global sandbox switch to `true` for the public
deployment.

## Current store and release state

- Both subscriptions have prices, 175-territory availability, localizations,
  and review images in App Store Connect. Their current state is
  **Ready to Submit**.
- The RevenueCat `default` offering contains both products and the published
  paywall. The public SDK key, bundle identifier, product identifiers,
  entitlement, and the displayed Apple credential panels match.
- The earlier TestFlight phone returned zero StoreKit products in the Turkey
  storefront, which caused `RC-23`. After the agreement/catalog propagation,
  the full Runner app (with no local StoreKit catalog attached) loaded both
  products and RevenueCat's published paywall on 6 September 2026. Retest build
  24 on the physical TestFlight device before review, but no client
  configuration mismatch remains.
- Paid Applications, banking, and tax were activated on 6 September 2026. Apple
  catalog changes can take time to propagate. Wait up to 24 hours from that
  activation before treating the unchanged zero-product result as final, then
  retry on a current TestFlight build and copy the sanitized store report.
- Full production build **1.1.0 (24)** is processed, valid, attached to the App
  Store version, and available to internal TestFlight testers. It was not
  submitted to Beta App Review or App Review.
- Fresh 2064x2752 iPad screenshots from the current build are uploaded and
  complete for both English and Arabic. TestFlight app descriptions and build
  24 What to Test notes are also populated in both locales.

The supplied sample app succeeds locally because its Xcode Run scheme enables a
local `.storekit` catalog. That confirms its UI path, not TestFlight catalog
availability. See [SAMPLECAT_CONFIGURATION_CHECK.md](SAMPLECAT_CONFIGURATION_CHECK.md)
and [RC23_STORE_ACTIONS.md](RC23_STORE_ACTIONS.md).

## App Store Connect actions that still require the account owner

The review draft currently contains the subscription group and both
subscription versions. Build 24 is selected for the app version, but the app
version cannot join that draft until the owner completes these items without
inventing legal or contact information:

1. Answer and publish **App Privacy** for the current app.
2. Fill the App Review contact first name, last name, email, phone country code,
   and phone number. A review demo login is already stored; do not expose it in
   chat or source control.
3. Enter the exact copyright holder text.
4. Set the content-rights declaration accurately. Football logos and videos
   mean third-party content rights must not be guessed.
5. Wait for or resolve the **Digital Services Act** status currently shown as
   **In Review** if Apple requires completion for EU distribution.
6. Add the app version to the same review submission as the first subscription
   group/items after those owner fields are complete.

External TestFlight review separately needs the same four contact fields.
Internal TestFlight already has build 24 and does not require Beta App Review.

Apple currently refuses editing the draft version's **What's New** field in its
present state; this is not a reason to invent release notes through another
field. Optional promotional images are not release blockers.

The App Store Connect API cannot truthfully answer App Privacy, content-rights,
copyright, reviewer identity, or DSA legal questions for the owner. Those
require manual owner input; the build, screenshots, and non-legal localized
metadata are already filled through the API.

## Release authorization boundary

Uploading a build to App Store Connect/TestFlight and selecting it is distinct
from submitting Beta App Review, submitting public App Review, or releasing the
app. Do **not** submit any App Review or release action without the owner's
explicit authorization after the manual blockers above are cleared and the
purchase-to-access flow is verified.

No App Review submission is authorized by this checklist.

References: [RevenueCat sandbox access controls](https://www.revenuecat.com/docs/projects/sandbox-access),
[RevenueCat Apple sandbox/TestFlight behavior](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
[RevenueCat empty-offering troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings),
[Apple: submit an in-app purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase),
[Apple: submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).
