# Production release checklist

The application code is configured for the real Abu 3meer App Store app: the
iOS client uses its public RevenueCat `appl_` SDK key, Android release builds
receive the Play app's public `goog_` key, and the server keeps the private
`sk_` key. Apple product identifiers are `Ostoora3` and `Ostoora3_Pro_Max`;
Google Play uses `ostoora3:ostoora3` and
`ostoora3_pro_max:ostoora3-pro-max`. A release
build cannot silently fall back to RevenueCat Test
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
- A channel link that matches the current imported YouTube member list activates
  member access directly as **YouTube membership**, never as a store/test
  subscription. The lease does not claim auto-renewal; after its snapshot
  expires or is replaced, the user must run the membership check again.
- The manual channel-link flow proves that a public channel is in the imported
  member list, but it does not prove that the signed-in app user owns that
  channel. The first matching account is bound uniquely. For a stronger public
  launch guarantee, require Google/YouTube ownership authorization or an
  admin-issued one-time claim code; otherwise staff must resolve disputed links.
- Loyalty defaults are 50 signup, 5 daily login, 15 correct word, 15 correct
  player, 10 winner, 20 first goalscorer, and 50 exact score. The member
  multiplier applies only to the three prediction rewards. First verified
  activation awards 150 XP once; a newly proven paid/membership period awards
  50 XP. Admin Studio now saves these rules to PostgreSQL and scoring reads
  those saved values.
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
membership rewards, store provenance, or WhatsApp support changes. Pull the new revision,
back up PostgreSQL, update `.env`, rebuild the API image, and recreate the API.
Migrations 043 and 044 run automatically at API startup.

Keep these production values in `/opt/abu3meer/server/.env`:

```dotenv
REVENUECAT_SECRET_API_KEY=sk_...
REVENUECAT_ALLOW_SANDBOX=false
REVENUECAT_SANDBOX_ALLOWED_USER_IDS=
SUPPORT_WHATSAPP_NUMBER=
```

`REVENUECAT_SANDBOX_ALLOWED_USER_IDS` is a comma-separated list of app-account
PostgreSQL UUIDs, not emails, Apple IDs, Firebase UIDs, or RevenueCat keys. It
is only an escape hatch for RevenueCat Test Store or legacy sandbox rows whose
store provenance is unknown. Genuine App Store and Play Store test receipts do
not need this server allowlist. Leave
`SUPPORT_WHATSAPP_NUMBER` blank until the business number is known; blank safely
disables WhatsApp. When enabled, enter the international number with country
code using digits only, without `+`, spaces, `00`, or a local trunk prefix.

The detailed, non-destructive commands are in
[DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md](DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md). Do not
run `docker compose down -v`.

## TestFlight, Play test-track, and App Review access

TestFlight/App Review and Google Play test-track purchases are genuine
store-signed sandbox transactions. The server asks RevenueCat for production
state first, then checks sandbox when production has no active entitlement.
An active `app_store` or `play_store` sandbox entitlement grants member access
and the badge, while the UI continues to label it as a test purchase rather
than a live charge. RevenueCat Test Store and legacy sandbox rows with unknown
store provenance remain blocked while `REVENUECAT_ALLOW_SANDBOX=false`.

After migration 044, an existing tester must tap **Refresh access** once so the
server records `store_name`. If RevenueCat's own sandbox-access setting is
restricted, allow that tester's PostgreSQL app-user UUID there as well.

## Current store and release state

- The installed iOS and Android display name is exactly **ABU 3MEER**. Apple
  reports that the exact storefront name is already used by another account,
  so both App Store localizations use the available uppercase name
  **ABU 3MEER - League**.
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
  31 on the physical TestFlight device before review; no client configuration
  mismatch remains.
- Paid Applications, banking, and tax were activated on 6 September 2026. Apple
  catalog changes can take time to propagate. Wait up to 24 hours from that
  activation before treating the unchanged zero-product result as final, then
  retry on a current TestFlight build and copy the sanitized store report.
- Full production build **1.1.0 (31)** is uploaded to TestFlight and selected
  for App Store version 1.1.0. Do not submit it until the current server update
  is live, the physical-device flow is verified, and the App Review information
  is complete.
- Reviewed build-32 App Store screenshots are uploaded in English and Arabic
  for both the 6.7-inch iPhone and 13-inch iPad display classes. Follow
  `APP_STORE_SCREENSHOT_PLAN.md` for the uploaded set and any future richer
  replacement.

The supplied sample app succeeds locally because its Xcode Run scheme enables a
local `.storekit` catalog. That confirms its UI path, not TestFlight catalog
availability. See [SAMPLECAT_CONFIGURATION_CHECK.md](SAMPLECAT_CONFIGURATION_CHECK.md)
and [RC23_STORE_ACTIONS.md](RC23_STORE_ACTIONS.md).

## App Store Connect actions that still require the account owner

The review draft currently contains the subscription group and both
subscription versions. Build 34 is processed and selected for the app version.
App Privacy
must be republished with the current first-party, RevenueCat, Firebase, and
AdMob data disclosures; the review contact and private demo login are filled,
copyright is `2026 Omar Jabur`, and the app declares that it uses third-party content.
Do not resubmit until the remaining owner/reviewer items are complete:

1. Upload or link the build-34 physical-device recording, fill the remaining
   review-note placeholders, and reply to the existing Guideline 2.1 message.
2. Attach or identify the applicable publication/brand/media rights. Football
   logos, videos, and data rights must not be guessed.
3. Wait for or resolve the **Digital Services Act** status currently shown as
   **In Review** if Apple requires completion for EU distribution.
4. Retest the full build-34 account-deletion, purchase/restore, notification,
   report/block, and member-access flow on the physical review device.
5. Resolve the existing review item and keep the app version in the same review
   submission as the first subscription group/items when resubmitting.

External TestFlight review separately needs the same four contact fields.
Internal TestFlight receives build 34 automatically and does not require Beta App Review.

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
