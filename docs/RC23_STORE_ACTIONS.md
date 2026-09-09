# RC-23: confirmed findings and next actions

> Historical incident record. RC-23 was resolved after the Apple agreement and
> catalog propagated. Do not use the old build-24 instructions for the current
> release; use `APP_REVIEW_PHYSICAL_DEVICE_VIDEO.md` and build 31 instead.

Updated 6 September 2026 after the physical-device report, the App Store
Connect/API audit, the RevenueCat credential screenshots, and inspection of the
supplied SampleCat ZIP.

## What is confirmed

- The iOS app uses the real public RevenueCat App Store SDK key (`appl_`) and
  passes the authenticated Abu 3meer PostgreSQL user UUID as the RevenueCat App
  User ID. The server separately uses the private REST API v1 `sk_` key.
- Bundle identifier `omar.abu3meer.app`, entitlement `abu_3meer_pro`, and product
  identifiers `Ostoora3` and `Ostoora3_Pro_Max` match between the app,
  RevenueCat, and App Store Connect.
- RevenueCat's `default` offering contains both products and the published
  native paywall.
- Both subscriptions have prices, 175-territory availability (including
  Turkey), localizations, and review images. Both are **Ready to Submit**.
- The phone's sanitized report completed both storefront and StoreKit lookups
  for `TUR`, but StoreKit returned neither requested product. RevenueCat
  therefore raised configuration error `RC-23`. This proves an empty product
  response; it does not prove the public SDK key is missing.
- Paid Applications, banking, and tax became Active on 6 September 2026. Store
  catalog changes can take time to propagate after an agreement is activated.
- RevenueCat shows **Valid credentials** for both the In-App Purchase key and
  the separate App Store Connect API key. There is no screenshot evidence that
  either `.p8` credential is invalid.
- The existing `dev` RevenueCat customer has an active sandbox subscription but
  no active production entitlement. Apple's **Active** test UI and Customer
  Center therefore do not establish a paid public-App-Store subscription.

## Why the sample app appeared to work

The supplied SampleCat Xcode Run scheme enables a local StoreKit configuration.
Its sample prices are fixture values, so it can render and purchase locally even
when Apple's TestFlight catalog returns zero products. The RevenueCat SDK flow
is otherwise the same normal native paywall flow used by Abu 3meer.

A local Xcode preview is useful for layout testing, but it is not evidence that
`Ostoora3` or `Ostoora3_Pro_Max` is available from Apple's sandbox storefront.
The release Runner scheme and exported release app do not enable the local
StoreKit catalog. See
[SAMPLECAT_CONFIGURATION_CHECK.md](SAMPLECAT_CONFIGURATION_CHECK.md).

## Apple credential roles

- The public `appl_` key identifies the RevenueCat app to the client SDK. It is
  expected in the iOS app and is not a secret.
- The `sk_` key authenticates the Abu 3meer server to RevenueCat. It must never
  be bundled into the app.
- RevenueCat's **In-app purchase key configuration** `.p8` lets RevenueCat
  validate/record modern Apple transactions. The displayed key ID and issuer
  show valid credentials.
- The separate **App Store Connect API** `.p8` supports product import, prices,
  and related App Store Connect operations. It is not the client SDK key.
- An app-specific shared secret is a legacy StoreKit 1 compatibility credential.
  It should be valid if legacy receipt validation is required, but it does not
  populate an empty StoreKit product response.
- Apple server-to-server notifications are recommended for timely renewal,
  refund, and expiration updates. A page saying no notifications have yet been
  received does not explain why StoreKit returned zero products before a
  purchase. Applying RevenueCat's notification URL is a separate recommended
  setup step.

Do not rotate another key, upload an arbitrary team key, recreate products, or
copy the sample's fixture prices in response to `RC-23`.

## Next product-lookup action

The full Runner app, without a local StoreKit catalog, loaded both App Store
products and RevenueCat's published paywall on 6 September after the agreement
change. The remaining check is to confirm the same result on the physical
TestFlight device:

1. Install/open TestFlight build 31, then use **Members → View plans →
   Check store connection → Copy report**. This is a read-only product lookup;
   it does not charge, restore, or grant access.
2. If both products are still absent after the 24-hour propagation window,
   retain the
   sanitized report with the app version/build, exact UTC time, storefront,
   bundle ID, and both product IDs. Escalate that evidence to Apple Developer
   Support and RevenueCat Support. Do not share API keys, `.p8` files, receipts,
   Apple IDs, or review passwords.

The app can show the native RevenueCat paywall only after Apple returns at least
one package's StoreKit product. A backend rebuild cannot manufacture that
product response.

References: [RevenueCat empty-offering troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings),
[RevenueCat Apple sandbox/TestFlight behavior](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
[RevenueCat in-app purchase key configuration](https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration).

## Server deployment required for access fixes

The earlier healthy Docker rebuild deployed migrations 040/041. The current
revision additionally contains:

- migration `042_admin_subscription_access.sql`;
- production-first, per-account sandbox access for TestFlight/App Review;
- admin grant/block/store-control actions; and
- the validated WhatsApp support endpoint.

Pull, back up, rebuild, and recreate the API using
[DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md](DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md). This is
required for those access/support features, but it is not presented as a repair
for Apple's `RC-23` product response.

Keep:

```dotenv
REVENUECAT_ALLOW_SANDBOX=false
REVENUECAT_SANDBOX_ALLOWED_USER_IDS=<dedicated-review-app-account-postgresql-uuid>
SUPPORT_WHATSAPP_NUMBER=
```

The server requests production state first. Only the exact allowlisted account,
and only when it lacks an active production entitlement, receives the explicit
sandbox fallback. RevenueCat must also be set manually to **Sandbox Testing
Access → Allowed App User IDs only** with the same UUID. Blank WhatsApp support
is disabled safely until the real international digits-only number is supplied.

## App Store Connect review blockers

The current review submission contains the rejected app-version item plus the
subscription group and both subscription versions. App Privacy is published;
the reviewer contact, private demo login, copyright, and third-party content
declaration are filled. Remaining owner actions are to provide the build-31
physical-device video and complete review response, identify the applicable
publication/brand/media rights, complete physical-device QA, and wait for or
resolve the Digital Services Act status shown as **In Review** if Apple requires
it for EU distribution.

Fresh build-31 iPhone and iPad screenshots are uploaded in both locales, and
build 31 is processed and selected. The dedicated review login is already
stored and must remain private. Resolve and resubmit the existing app-version
item with the same first-subscription items; do not create a separate review
submission that leaves those products behind.

Do not submit Beta App Review, public App Review, or release the app without
explicit owner authorization. No App Review submission is authorized by this
document.
