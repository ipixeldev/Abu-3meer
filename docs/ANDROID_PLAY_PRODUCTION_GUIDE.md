# ABU 3MEER Android RevenueCat and Play production guide

The Android package stays `com.abu3meer.app`. iOS remains `omar.abu3meer.app`. This is correct: Apple and Google package IDs do not need to match. The app label is `ABU 3MEER`.

## RevenueCat

RevenueCat dashboard: Apps → + New app → Play Store. Enter package name `com.abu3meer.app`. Copy the Android public SDK key (starts with `goog_`) into the release build:

```sh
flutter build appbundle --release \
  --dart-define=REVENUECAT_ANDROID_API_KEY=goog_your_public_key
```

Never put the RevenueCat `sk_` secret in Flutter, Gradle, GitHub, or an APK/AAB. Keep it only on the server. Configure the Play Store app with the Google Play service-account JSON from Play Console and verify the entitlement `abu_3meer_pro`, products `Ostoora3` and `Ostoora3_Pro_Max`, and the current offering.

For production access, turn off RevenueCat sandbox access. For internal testing, allow only the exact test account IDs in RevenueCat and the server allowlist.

## Play Console setup

1. Play Console → select **ABU 3MEER - League** → Monetize with Play → Products → Subscriptions → Create subscription.
2. Create product ID `Ostoora3`; add a monthly base plan; set price; activate it.
3. Create product ID `Ostoora3_Pro_Max`; add a yearly base plan; set price; activate it.
4. Play Console → Settings → Developer account → API access → create/select a service account → grant View financial data and Manage orders permissions → download JSON.
5. RevenueCat → Apps → Play Store app → upload that JSON.
6. Play Console → Monetize with Play → Monetization setup → Real-time developer notifications; create Pub/Sub topic and connect it.
7. Play Console → Test and release → Internal testing → create release → upload signed `.aab` → add testers → copy opt-in link.
8. Complete Play Console Dashboard tasks: app details, store listing, Data safety, content rating, privacy policy, payments profile, and closed-test requirement.

## Firebase follow-up

Do not change Firebase. Android continues using the existing Firebase app/package `com.abu3meer.app`.

## Build troubleshooting

Use the repository's Gradle wrapper and run `flutter clean && flutter pub get` before rebuilding. The project uses AGP 8.12.1, Gradle 8.13, and Kotlin 2.2.20, which are compatible with the current Flutter toolchain. Do not re-enable `android.newDsl=false`; it is deprecated. The first Play build must use a real release keystore, not the debug fallback currently used for local development.
