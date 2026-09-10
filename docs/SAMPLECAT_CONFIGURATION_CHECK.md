# RevenueCat SampleCat configuration check

Checked 6 September 2026 against the attached `2-sample_app.zip`, the current
Flutter source, the release Runner configuration, and the supplied RevenueCat
screenshots. The ZIP was inspected with targeted archive reads; it was not
installed or used to make a purchase. No `.p8`, receipt, password, or secret API
key was read.

## Main finding: the public SDK key is already in use

The App Store public key in the sample's `SampleCat/Constants.swift` matches the
value provided by the app's `SubscriptionService._iosKey`. Its identifying
fragment is `appl_iCzD…ihuOS`. This is a client identifier, not the private
RevenueCat server credential.

Current Abu 3meer source references (use symbols rather than old line numbers,
which changed as access handling was added):

- `lib/production/subscription_service.dart`:
  `SubscriptionService.entitlementId`, `_iosKey`, `apiKey`, `_connect`, and
  `_currentOffering` select the App Store key, configure Purchases with the
  authenticated PostgreSQL user UUID, and fetch the current offering.
- `lib/features/subscriptions/subscription_paywall_page.dart`:
  `PaywallView` renders the selected RevenueCat offering.
- `pubspec.yaml`: `purchases_flutter` and `purchases_ui_flutter` are both on the
  10.11 line; the iOS lock resolves RevenueCat Purchases 5.87.1.
- `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`: the release app
  does not enable a local StoreKit configuration.

The client rejects `sk_` and `test_` values and now contains only the real
platform-specific public SDK keys. The existing [build 23 payload audit](../artifacts/app-store/release-1.1.0-23.md)
also found the expected App Store key and no StoreKit configuration in that
exported IPA.

## Exact functional comparison

| Setting | Attached SampleCat | Abu 3meer release app |
| --- | --- | --- |
| RevenueCat client key | Same public `appl_` key | Same public `appl_` key |
| Bundle ID | `omar.abu3meer.app` | `omar.abu3meer.app` |
| Entitlement | `abu_3meer_pro` | `abu_3meer_pro` |
| Product IDs | `Ostoora3`, `Ostoora3_Pro_Max` | Same exact IDs |
| RevenueCat identity | Initially anonymous; optional demo login | Authenticated PostgreSQL app-account UUID |
| Offering/paywall | Fetches offerings and uses native RevenueCat paywall UI | Fetches current offering and uses Flutter RevenueCat `PaywallView` |
| Product source in supplied Xcode Run scheme | Local `SampleCatStoreKitConfiguration.storekit` | Apple's store services; no local catalog in release Runner |
| Prices in sample archive | Local fixture `9.99` monthly / `79.99` yearly | StoreKit prices from App Store Connect, never copied from the fixture |

Relevant sample archive symbols/files:

- `SampleCat/Constants.swift`: public key and entitlement.
- `SampleCat/UserViewModel.swift`: SDK configuration, offerings, products, and
  customer state.
- `SampleCat/Screens/Paywalls/PaywallsTabView.swift`: offering selection and
  native paywall presentation.
- `SampleCat.xcodeproj/xcshareddata/xcschemes/SampleCat.xcscheme`: attaches the
  local StoreKit configuration to the Xcode Run action.
- `SampleCatStoreKitConfiguration.storekit`: fixture product identifiers,
  periods, and prices.
- `SampleCat.xcodeproj/project.pbxproj`: bundle identifiers and RevenueCat SDK
  requirement.

The language/framework difference (SwiftUI versus Flutter) and the small native
SDK version difference do not establish the cause of an empty StoreKit product
response.

## What the screenshots establish

- The RevenueCat app is associated with bundle `omar.abu3meer.app`, and its SDK
  compatibility panel observed `purchases-flutter` 10.11.0.
- RevenueCat displays **Valid credentials** for the **In-app purchase key** and
  the separate **App Store Connect API** key.
- Those `.p8` keys, the app's public `appl_` key, and the backend's private `sk_`
  key have different roles. A valid team/account credential does not make the
  public SDK key unused.
- The public key is masked in the screenshot. The exact comparison comes from
  the supplied sample and app source, not from guessing the hidden dots.

The screenshots alone did not prove an end-to-end TestFlight product fetch. App
Store Connect separately confirms both products have prices and availability in
175 territories, including Turkey, and are **Ready to Submit**. After Paid
Applications, banking, and tax became Active on 6 September 2026, the full
Runner app (without the sample's local StoreKit catalog) loaded both products
and the published RevenueCat paywall. Build 24 still needs the same confirmation
on the physical TestFlight device before review.

## Consequence for RC-23

The supplied sample can work in Xcode because the Run scheme supplies local
products. On the affected TestFlight device, the sanitized Abu 3meer diagnostic
instead reported `Returned products: none` and both exact product IDs missing in
the Turkey storefront. RevenueCat cannot render a purchasable native paywall
when Apple supplies no StoreKit products for its packages.

Therefore:

1. Keep the existing public SDK key, entitlement, product identifiers, bundle
   identifier, and the two RevenueCat credential configurations.
2. Do not copy the sample's `9.99`/`79.99` fixture prices into App Store Connect.
3. Wait through the agreement propagation window, retest a current TestFlight
   build, and copy the sanitized store report.
4. If the products remain absent after 24 hours, send the report, UTC time,
   storefront, build, bundle ID, and product IDs to Apple Developer Support and
   RevenueCat Support. Never send a key, `.p8`, receipt, Apple ID, or password.

This sample comparison does not claim that another client-code change can
manufacture Apple's product response. See
[RC23_STORE_ACTIONS.md](RC23_STORE_ACTIONS.md).

## Separate production-access requirements

TestFlight and App Review still produce sandbox receipts after product lookup
works. The server checks production first and then accepts a genuine
`app_store`/`play_store` sandbox entitlement without enabling RevenueCat Test
Store. Keep `REVENUECAT_ALLOW_SANDBOX=false`. If RevenueCat's own sandbox access
is restricted, allow the tester's PostgreSQL UUID there. This does not change
the client key or the product lookup described above.

The current server revision must be rebuilt/recreated to deploy migrations
043/044, admin access controls, and the optional WhatsApp support endpoint.
See [DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md](DEPLOY_MEMBERSHIP_SUBSCRIPTIONS.md).

References: [RevenueCat configure the SDK](https://www.revenuecat.com/docs/getting-started/configuring-sdk),
[RevenueCat Apple sandbox/TestFlight behavior](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
[RevenueCat empty-offering troubleshooting](https://www.revenuecat.com/docs/offerings/troubleshooting-offerings).
