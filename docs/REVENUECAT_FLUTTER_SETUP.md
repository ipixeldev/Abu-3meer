# ABU 3MEER: subscriptions and membership setup

Project: `proja7bd8e75` · iOS bundle: `omar.abu3meer.app` · entitlement: `abu_3meer_pro`.

The user has created the Apple products and RevenueCat App Store app. The Flutter app now includes that app's public iOS SDK key. Live purchase/restore testing is still required; a simulator paywall screenshot alone does not verify billing or server activation.

## 1. Use the right keys

| Credential | Where it belongs |
| --- | --- |
| RevenueCat public `appl_…` SDK key | Flutter iOS build configuration |
| RevenueCat public `goog_…` SDK key | Flutter Android build configuration, after Play setup |
| RevenueCat secret `sk_…` REST API key | Server `.env` only; never Flutter, Git, or chat |
| Apple In-App Purchase `.p8`, Key ID, Issuer ID | RevenueCat's App Store app configuration |

Revoke the secret key pasted into chat and generate a replacement. Do not reuse an exposed key. Public SDK keys can be shared; secret keys cannot. [RevenueCat API keys](https://www.revenuecat.com/docs/projects/authentication).

## 2. Create the Apple subscriptions

In the **client's** App Store Connect account, open **Apps → Abu 3meer** and confirm bundle `omar.abu3meer.app`.

1. Ensure the Account Holder has completed the Paid Apps agreement and required banking/tax information.
2. Open **Monetization → Subscriptions** (or Subscriptions in the sidebar).
3. Create one subscription group, **Ostoora3 Membership**. If equivalent products already exist, reuse them instead of creating duplicates.
4. Reuse these existing auto-renewable subscriptions; do not create duplicates or change their product identifiers.

| Display name | Product ID | Duration | US price |
| --- | --- | --- | --- |
| Ostoora3 | `Ostoora3` | 1 month | USD 3.99 (currently configured in Apple) |
| Ostoora3 Pro Max | `Ostoora3_Pro_Max` | 1 year | USD 39.99 (currently configured in Apple) |

These current US prices were read from Apple's synchronized StoreKit configuration
on 2026-09-06; the originally requested amounts were $4 and $40. The screenshot
preview uses Apple's current values, not invented prices or a change to the store.

Both products currently provide the **same member benefits**, with different billing periods. Put both at the same service level in the same group. Do not create two groups, which could let a customer subscribe to both independently. [Apple subscription groups and levels](https://developer.apple.com/app-store/subscriptions/).

5. Add English/Arabic localizations, duration, availability, description, and App Review screenshot for each product. Example description: “Members Zone access and member bonuses.”
6. Under Subscription Prices, select the US price. Use **See Additional Prices** if necessary to find exactly $4.00 and $40.00; do not silently substitute $3.99/$39.99. Review the other storefront prices before saving. The app displays the store's localized price, not a hardcoded dollar amount. [Apple pricing steps](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions).
7. Complete the subscription group localization and resolve missing-metadata warnings. Before the first public release, attach the first subscriptions to the app version's review submission. Creating products alone does not submit or release them.

## 3. Connect Apple's store to RevenueCat

1. Open RevenueCat project `proja7bd8e75` → **Apps & providers** → select the **App Store** app. Its bundle ID must be `omar.abu3meer.app`.
2. In App Store Connect, open **Users and Access → Integrations → In-App Purchase**. Generate/download an In-App Purchase key using the client's account.
3. In RevenueCat's App Store app → **In-app purchase key configuration**, upload that `.p8` and enter its matching Key ID and Issuer ID. This is required by the StoreKit 2 SDK used here; an APNs key or Sign in with Apple key is not a substitute. [RevenueCat IAP key setup](https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration).
4. Configure RevenueCat's separate App Store Connect API integration if you want automatic product import. Use the required App Store Connect API credentials in that section, not an APNs key.
5. Open **Product catalog → Products → Import Products**, select the App Store app, and import both products. If importing manually, enter each exact Apple product ID and choose the correct store. [Product configuration](https://www.revenuecat.com/docs/offerings/products-overview).
6. The App Store app's public `appl_` SDK key is now configured in `SubscriptionService`. `REVENUECAT_IOS_API_KEY` can override it when intentionally targeting a different RevenueCat app. Never use a secret `sk_` key in Flutter.

## 4. Entitlement, offering, paywall, Customer Center

1. In **Product catalog → Entitlements**, create or select identifier **`abu_3meer_pro`**. Attach both Apple products. The identifier is case-sensitive; do not replace it with the display name.
2. In **Offerings**, create/select `default` and make it the project's default offering.
3. Add a **Monthly** package (`$rc_monthly`) and attach the monthly Apple product. Add an **Annual** package (`$rc_annual`) and attach the yearly Apple product.
4. Both products must be attached to **the entitlement and the offering packages**; these are separate settings. The implementation reads `getOfferings().current`, so you can update the default offering remotely. [RevenueCat offerings](https://www.revenuecat.com/docs/offerings/overview).
5. In **Paywalls**, create a two-plan paywall for this offering. Use store price/duration variables, add English/Arabic content, close/restore controls, privacy URL `https://ipixeldev.github.io/Abu-3meer/privacy/`, and terms URL `https://ipixeldev.github.io/Abu-3meer/terms/`. Preview, save, and publish the paywall configuration. This is not App Store submission. [RevenueCat Paywalls](https://www.revenuecat.com/docs/tools/paywalls).
6. Configure **Customer Center** in RevenueCat, including support contact `support@abu3meer.com`. The app's Manage subscription/Customer Center action presents the native screen, then refreshes customer info and server access. [Customer Center](https://www.revenuecat.com/docs/tools/customer-center).
7. Review RevenueCat's restore/transfer behavior deliberately. For this account-bound app, start with keeping purchases on the original app account; people should sign back into that account to restore. Do not use a legacy sharing setting that gives unrelated app accounts the same subscription. If you choose transfer behavior, test both affected app accounts—the webhook refreshes both.

## 5. Flutter implementation (already added)

Dependencies in `pubspec.yaml`:

```yaml
purchases_flutter: ^10.11.0
purchases_ui_flutter: ^10.11.0
```

For a fresh checkout, run `flutter pub get`. To add the same versions to another Flutter project:

```sh
flutter pub add 'purchases_flutter:^10.11.0' 'purchases_ui_flutter:^10.11.0'
```

Complete production implementations:

- `lib/production/subscription_service.dart`: one-time configuration, explicit account identification, customer-info listener, purchases, restore, paywall, Customer Center, cancellation/pending/network errors, serialized identity transitions, and sign-out cleanup.
- `lib/features/subscriptions/subscription_panel.dart`: mobile layout, EN/AR copy, subscription controls in Profile, Settings, and Members Zone; handles store success followed by a server outage without asking the customer to buy twice.
- `lib/production/production_repository.dart`: authenticated server synchronization after purchases/restores and on login/foreground.
- `lib/production/models.dart`: `isProSubscriber` and `hasMemberAccess`, separate from `isYouTubeMember`.

This app identifies RevenueCat customers with the server database UUID from `/profile/me → user.id`, **not** an email, channel link, Firebase UID, or anonymous guest ID. Account switches cannot reuse an in-flight purchase's access state.

Example using the implemented service (call from a signed-in screen; do not duplicate these calls when using `SubscriptionPanel`):

```dart
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:abu_3meer/production/subscription_service.dart';

Future<void> openPlans(
  AbuUserProfile profile,
  ProductionRepository repository,
) async {
  final subscriptions = SubscriptionService.instance;
  try {
    final info = await subscriptions.refresh(profile.backendUserId);
    final active = info.entitlements.active['abu_3meer_pro'];
    if (active != null) {
      await subscriptions.showCustomerCenter(profile.backendUserId);
    } else {
      final result = await subscriptions.showPaywall(profile.backendUserId);
      if (result == PaywallResult.cancelled ||
          result == PaywallResult.notPresented) return;
      if (result == PaywallResult.error) {
        throw const SubscriptionException('The store request failed.');
      }
    }
    await repository.syncSubscription(profile);
  } catch (error) {
    if (SubscriptionService.isCancellation(error)) return;
    // Display a retryable message. A completed store charge must not be
    // repeated just because backend synchronization is unavailable.
    rethrow;
  }
}

Future<void> restoreMembership(
  AbuUserProfile profile,
  ProductionRepository repository,
) async {
  // Invoke only from an explicit Restore button, never automatically.
  await SubscriptionService.instance.restore(profile.backendUserId);
  await repository.syncSubscription(profile);
}
```

For a custom paywall, fetch `SubscriptionService.instance.offering(userId)`, display each package's `storeProduct.priceString`, and call `purchase(userId, package)` once. This wraps modern `Purchases.purchase(PurchaseParams.package(package))`. The existing RevenueCat paywall owns its own purchase flow—do not call purchase again from its completion callback.

## 6. Build configuration

The real public iOS and Android SDK keys are committed as platform-specific
defaults. They are public client identifiers, not RevenueCat secret REST keys.
Build normally:

```sh
flutter build ipa --release --target lib/main.dart --export-options-plist=ios/ExportOptions.plist
flutter build appbundle --release
```

The client contains no RevenueCat Test Store key or switch. TestFlight uses the
real `appl_` key with Apple's sandbox; Play Internal Testing uses the real
`goog_` key with Google Play's licensed test purchase flow.

Android has `FlutterFragmentActivity`, the Billing permission, and its real
RevenueCat Play key. iOS In-App Purchase capability is enabled. [Flutter installation requirements](https://www.revenuecat.com/docs/getting-started/installation/flutter#installation).

The Xcode PhaseScriptExecution failure came from running **Release on a simulator**. Run now uses Debug; Archive stays Release. Open `ios/Runner.xcworkspace`. For Archive select a physical device or **Any iOS Device (arm64)**, not an iPhone simulator. Firebase, Google URL scheme, signing team, and export settings have been updated for the new bundle/team.

## 7. Server deployment and verification

Follow `docs/REVENUECAT_SERVER.md` for the server-only secret, webhook, sandbox switch, and migration `041`. Migration `040` changes membership checking to a manual profile-link/CSV match. Deploy the backend **before** testing these new app endpoints. No Cloudflare route change is needed when the existing API hostname already reaches this server.

Run server commands one at a time, after pulling the reviewed release into the existing `/opt/abu3meer` checkout. Stop if any command reports an error; preserve local production changes. Back up the database before deployment.

```sh
cd /opt/abu3meer/server
```

```sh
nano .env
```

Set the fresh server secret and webhook authorization described in the server guide. Then:

```sh
docker compose build api
```

```sh
docker compose up -d --no-deps --force-recreate api
```

```sh
docker compose logs --tail=100 api
```

The API startup applies pending migrations before serving requests. Confirm `040_manual_profile_membership.sql` and `041_revenuecat_subscriptions.sql` succeed and the API reports ready. Merely restarting an existing container does not apply new image code or changed Compose environment variables.

Before release test: a successful purchase, cancellation, restore, expiration/refund, account switch, pending payment, network outage after purchase, a CSV-only member, and a non-member. Confirm RevenueCat's customer UUID matches the API account and server `isProSubscriber` agrees with the purchase. Also publish/review the updated public privacy/terms pages and App Store privacy disclosures for RevenueCat before review. Unit tests and an unsigned build cannot prove a real store transaction works.

Manual link matching does not prove channel ownership. The server prevents linking one channel to multiple app accounts, but the first claimant could still submit another member's public link. Membership freshness also depends on staff uploading complete current exports.
