# RecipeRift RevenueCat comparison

Read-only reference audit, 6 September 2026. The requested local Documents folder was not identified. The exact named GitHub repository `ipixeldev/RecipeRift` is accessible and was inspected through targeted GitHub API reads without cloning or modifying it. Reference snapshot: `278a8c00ea89742cb82362e003a188bde6bce0fe` (29 May 2026). The user's current local working copy could differ.

No `AGENTS.md`, tracked StoreKit configuration, or shared `.xcscheme` appears in that repository tree. RevenueCat troubleshooting instructions and both native iOS/Flutter references were read for this comparison.

## Concrete comparison

| Item | RecipeRift reference | Abu3meer release21 |
| --- | --- | --- |
| Framework | SwiftUI native | Flutter, native RevenueCat SDK/UI under the plugin |
| iOS RevenueCat SDK | 5.75.0 in Package.resolved | 5.87.1 in Package.resolved |
| Initialization | AppDelegate startup: configure with a public `appl_` key | Configure once with public `appl_` key and stable signed-in app user ID |
| Customer identity | No explicit appUserID or Purchases.logIn call found | Identified account, account-switch guards, backend verification |
| Paywall | `RevenueCatUI.PaywallView(displayCloseButton: true)`; SDK resolves current offering internally | Fetch current offering, validate packages, pass offering to SDK PaywallView inside a retained page |
| Entitlement handling | Active `RecipeRift Pro` purchase/restore callback saves local proPlan=lifetime | `abu_3meer_pro` customer info plus authoritative server verification; test receipts not production access |
| Bundle | `com.aftermath9.RecipeRift` | `omar.abu3meer.app` |
| Signing team | **P9X53J2SQX** | **A4V5S8R8F8** |

## What this establishes

- RecipeRift uses the normal RevenueCat SDK/UI route, not a different purchase service or a method that bypasses Apple's product lookup.
- Its simpler UI does not explicitly prefetch offerings. Abu's explicit fetch exposes an Apple/RevenueCat configuration failure before rendering the native paywall. Removing this check would not manufacture StoreKit products.
- No product-ID filter, custom offering identifier, explicit product fetch, or alternate fallback offering appears in RecipeRift's initialization/paywall code. Its paywall uses the SDK's implicit current offering. Abu also chooses `.current`, with only a null/empty-packages guard, not a monthly/yearly ID filter.
- RecipeRift initializes Firebase first, then sets RevenueCat debug logging and configures RevenueCat synchronously in AppDelegate (`RecipeRiftApp.swift:21–24`). Abu initializes Firebase in the app bootstrap and awaits RevenueCat configuration/customer info inside its serialized signed-in subscription workflow before fetching offerings (`subscription_service.dart:181–262`). This is an initialization-timing/identity difference, not evidence of a failed or skipped configure call in Abu.
- Most importantly, RecipeRift uses a **different Apple developer team**. Working purchases there do not establish that the client's Abu3meer Paid Applications Agreement/tax/banking setup is active.
- Different SDK versions are a comparison fact, not evidence that the newer SDK is faulty. No downgrade is justified by this reference alone.
- The reference's local lifetime flag should not be copied into Abu's production access model: it does not provide Abu's server-verified subscription lifecycle and test/production separation.

## Evidence locations

- [RecipeRift initialization, lines16–26](https://github.com/ipixeldev/RecipeRift/blob/278a8c00ea89742cb82362e003a188bde6bce0fe/RecipeRift/RecipeRiftApp.swift#L16-L26).
- [RecipeRift SDK paywall and callback, lines8–23](https://github.com/ipixeldev/RecipeRift/blob/278a8c00ea89742cb82362e003a188bde6bce0fe/RecipeRift/Views/PaywallView.swift#L8-L23).
- [RecipeRift build settings](https://github.com/ipixeldev/RecipeRift/blob/278a8c00ea89742cb82362e003a188bde6bce0fe/RecipeRift.xcodeproj/project.pbxproj#L274-L325).
- [RecipeRift dependency lockfile](https://github.com/ipixeldev/RecipeRift/blob/278a8c00ea89742cb82362e003a188bde6bce0fe/RecipeRift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).
- Abu local `lib/production/subscription_service.dart` configures identity and fetches offerings; `lib/features/subscriptions/subscription_paywall_page.dart` embeds the SDK PaywallView.

## Scope and credential hygiene

No RecipeRift app, account, settings, entitlement, or key was changed. Keys in viewed source were redacted before output and were not copied into Abu. The repository root lists a tracked `AuthKey_*.p8` filename; its contents were not fetched or used. No other private project was downloaded or inspected.

The precise physical-device RC-23 root cause is still not proven by this comparison. The client account's Business agreement status and the failing phone's underlying native StoreKit error remain the useful next checks.

