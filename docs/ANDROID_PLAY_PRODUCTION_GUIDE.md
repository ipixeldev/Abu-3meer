# ABU 3MEER Android RevenueCat and Play production guide

The Android package is now `omar.abu3meer.app`, matching iOS. The app label is `ABU 3MEER`.

## RevenueCat

Create/select the Android Play Store app in the existing RevenueCat project with package name `omar.abu3meer.app`. Copy its public SDK key (it must begin with `goog_`) into the release build:

```sh
flutter build appbundle --release \
  --dart-define=REVENUECAT_ANDROID_API_KEY=goog_your_public_key
```

Never put the RevenueCat `sk_` secret in Flutter, Gradle, GitHub, or an APK/AAB. Keep it only on the server. Configure the Play Store app with the Google Play service-account JSON from Play Console and verify the entitlement `abu_3meer_pro`, products `Ostoora3` and `Ostoora3_Pro_Max`, and the current offering.

For production access, turn off RevenueCat sandbox access. For internal testing, allow only the exact test account IDs in RevenueCat and the server allowlist.

## Play Console setup

1. Create the app with package name `omar.abu3meer.app` (package names cannot be changed after creation).
2. Add the two auto-renewing products with IDs `Ostoora3` and `Ostoora3_Pro_Max`, matching the RevenueCat catalog.
3. Create a Google Cloud service account, grant it Play Console access including financial/order permissions, and upload its JSON to RevenueCat's Play Store app configuration.
4. Configure Real-time Developer Notifications through a Cloud Pub/Sub topic and connect it in Play Console.
5. Add testers to an internal testing track, upload the signed AAB, and install from the Play opt-in link. Products are not returned to sideloaded APKs that are not associated with Play.
6. Complete Play App Content, Data safety, content rating, target API, store listing, privacy policy, and payments profile before production rollout.

## Firebase follow-up

Because the package changed from `com.abu3meer.app`, add a new Android app with package `omar.abu3meer.app` in Firebase, register the release and debug SHA-1/SHA-256 fingerprints, download the new `google-services.json`, and replace `android/app/google-services.json`. The checked-in file currently has the package name aligned for compilation, but Firebase OAuth/sign-in will not be production-correct until the new Firebase app credentials are downloaded.

## Build troubleshooting

Use the repository's Gradle wrapper and run `flutter clean && flutter pub get` before rebuilding. The project uses AGP 8.12.1, Gradle 8.13, and Kotlin 2.2.20, which are compatible with the current Flutter toolchain. Do not re-enable `android.newDsl=false`; it is deprecated. The first Play build must use a real release keystore, not the debug fallback currently used for local development.
