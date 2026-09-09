# ABU 3MEER Android RevenueCat and Play production guide

The Android package stays `com.abu3meer.app`. iOS remains `omar.abu3meer.app`. This is correct: Apple and Google package IDs do not need to match. The app label is `ABU 3MEER`.

## RevenueCat

RevenueCat dashboard: Apps → + New app → Play Store. Enter package name `com.abu3meer.app`. Copy the Android public SDK key (starts with `goog_`) into the release build:

```sh
flutter build appbundle --release \
  --dart-define=REVENUECAT_ANDROID_API_KEY=goog_your_public_key
```

Never put the RevenueCat `sk_` secret in Flutter, Gradle, GitHub, or an APK/AAB. Keep it only on the server. Configure the Play Store app with a Google Cloud service-account JSON and verify the entitlement `abu_3meer_pro`, Android products `ostoora3:monthly` and `ostoora3_pro_max:yearly`, and the current offering. Apple keeps its separate existing product IDs.

Keep the server's synthetic Test Store switch off. Genuine Google Play test-track purchases are still accepted and visibly marked as sandbox; they do not need the server escape-hatch allowlist.

## Play Console setup

1. Play Console → select **ABU 3MEER - League** → Monetize with Play → Products → Subscriptions → Create subscription.
2. Create subscription product ID `ostoora3`; add and activate base-plan ID `monthly`; set its monthly price.
3. Create subscription product ID `ostoora3_pro_max`; add and activate base-plan ID `yearly`; set its yearly price. Google product/base-plan IDs must be lowercase. In RevenueCat these plans appear as `ostoora3:monthly` and `ostoora3_pro_max:yearly`.
4. Google Cloud Console → select or create a project → APIs & Services → Library → enable **Google Play Android Developer API** and **Google Play Developer Reporting API**.
5. Google Cloud Console → IAM & Admin → Service Accounts → create `revenuecat-play` → Keys → Add key → Create new key → JSON. Download the JSON once and store it privately. It is not created in RevenueCat and must never be committed or copied to this app's server.
6. Play Console (developer-account level, not inside only the app) → **Users and permissions** → Invite new users. Enter the JSON's `client_email`, add **ABU 3MEER**, and grant these four permissions: **View app information and download bulk reports (read-only)**, **View financial data, orders, and cancellation survey responses**, **Manage orders and subscriptions**, and **Manage store presence**. Save and confirm the service account is Active.
7. RevenueCat → ABU 3MEER → Apps & providers → the Play Store app → upload that exact JSON under **Service Account Credentials JSON** → Save changes → Check again. Google permission propagation can take up to 36 hours.
8. RevenueCat → Product catalog → Products → Import products → select the Play Store app → import `ostoora3:monthly` and `ostoora3_pro_max:yearly`. Attach both to entitlement `abu_3meer_pro`; attach monthly to the `$rc_monthly` package and yearly to `$rc_annual` in the current/default offering; publish the paywall.
9. Configure Google real-time developer notifications from the same RevenueCat Play app settings, following its generated Pub/Sub instructions. In Google Cloud, grant that service account **Pub/Sub Editor** (use Pub/Sub Admin only if Editor is rejected) and **Monitoring Viewer**, and enable the Pub/Sub API.
10. Play Console → Test and release → Internal testing → create release → upload signed `.aab` → add testers → copy opt-in link.
11. Complete Play Console Dashboard tasks: app details, store listing, Data safety, content rating, privacy policy, payments profile, and closed-test requirement.

If RevenueCat still says it cannot validate the JSON, open **View details** first. Verify its Project ID and Client Email match the service account, all four Play permissions are enabled, both Play APIs are enabled in that JSON's Google Cloud project, and the account is Active. Re-upload a newly generated JSON key after any key/service-account replacement; permission changes alone do not normally require a new JSON key.

## Which RevenueCat keys go where

- RevenueCat → Project settings → API keys → **ABU 3MEER (Play Store)** public key beginning `goog_`: pass it only to Flutter as `REVENUECAT_ANDROID_API_KEY` at build time.
- RevenueCat → Project settings → API keys → secret REST API v1 key beginning `sk_`: put it only in `/opt/abu3meer/server/.env` as `REVENUECAT_SECRET_API_KEY=sk_...`, then recreate the API container.
- Google service-account JSON: upload it only to the RevenueCat Play app settings. The Abu 3meer server does not need this JSON.

## Firebase follow-up

Do not create or rename the Firebase Android app. Keep the existing app/package `com.abu3meer.app`. After Play App Signing is enabled, open Play Console → Test and release → Setup → App integrity, copy both the **App signing key certificate** SHA-1 and SHA-256, then add them to this existing Android app in Firebase Console → Project settings → Your apps. Download the refreshed `google-services.json` and replace `android/app/google-services.json`. This fingerprint step is required for Google sign-in in Play-installed builds and does not require rebuilding the Firebase project.

## Build troubleshooting

Use the repository's Gradle wrapper and run `flutter clean && flutter pub get` before rebuilding. The project uses AGP 8.12.1, Gradle 8.14, and Kotlin 2.4.10. Flutter 3.47 may temporarily add `android.builtInKotlin=false` and the deprecated `android.newDsl=false` compatibility flags while building older Flutter plugins. Those warnings do not cause the device to remain on “Installing”; remove the generated lines before committing, and update Flutter/plugins when Flutter no longer needs the compatibility bridge.

Create the private upload key once (choose and safely record the passwords):

```sh
keytool -genkeypair -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
nano android/key.properties
```

The two generated files are ignored by Git. Back them up securely; losing the upload key requires a Play Console upload-key reset. Then build the signed bundle with the Android public SDK key:

```sh
flutter clean
flutter pub get
flutter build appbundle --release --dart-define=REVENUECAT_ANDROID_API_KEY=goog_your_public_key
```

Confirm the build says it used the release signing configuration before uploading `build/app/outputs/bundle/release/app-release.aab` to Play Console.

References: [RevenueCat Play service credentials](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials), [Google Play Developer API setup](https://developers.google.com/android-publisher/getting_started).
