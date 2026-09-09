# ABU 3MEER Android RevenueCat and Play production guide

The Android package stays `com.abu3meer.app`. iOS remains `omar.abu3meer.app`. This is correct: Apple and Google package IDs do not need to match. The app label is `ABU 3MEER`.

## Verified store identifiers and remaining RevenueCat work

The Google products and base plans already created are:

| Plan | Play subscription product ID | Play base-plan ID | RevenueCat product identifier |
| --- | --- | --- | --- |
| Monthly | `ostoora3` | `ostoora3` | `ostoora3:ostoora3` |
| Yearly | `ostoora3_pro_max` | `ostoora3-pro-max` | `ostoora3_pro_max:ostoora3-pro-max` |

The live RevenueCat configuration has been checked. Both Android rows are **Published**, and the action is **Detach**. That confirms both products are attached to entitlement `abu_3meer_pro`; do not import or attach them again. The current/default Offering is also correct:

1. Package `$rc_monthly` contains the iOS monthly product and `ostoora3:ostoora3`.
2. Package `$rc_annual` contains the iOS yearly product and `ostoora3_pro_max:ostoora3-pro-max`.
3. The offering is marked **Current**.
4. Paywall **Abu 3meer - fan league** is published.

Do not change those mappings. Two dashboard jobs remain:

1. RevenueCat → **Integrations → Webhooks** → open the Abu 3meer webhook. Select **Both Production and Sandbox**, enable transfer/lifecycle events, save, then use **Send test** and require HTTP 200. This is needed to exercise the full internal-test lifecycle before launch.
2. RevenueCat → **Apps & providers → ABU 3MEER (Play Store)** → **Google developer notifications**. Finish the Pub/Sub setup and connect the topic. Then add the same topic in Play Console → **Monetize with Play → Monetization setup → Real-time developer notifications** and send Google's test notification.

The RevenueCat Android public SDK key is not installed automatically by importing products or uploading the Google JSON. It must be supplied when the Android app is built. Keep the server's synthetic Test Store switch off: genuine Play test-track purchases are store-signed sandbox purchases and are accepted while remaining visibly labelled as sandbox.

## The four credentials and exactly where each goes

| Credential | Get it from | Put it here | Never put it here |
| --- | --- | --- | --- |
| RevenueCat Android public SDK key, `goog_...` | RevenueCat → Project settings → API keys → **Public SDK keys** → Play app | Flutter release build as `--dart-define=REVENUECAT_ANDROID_API_KEY=goog_...` | Server `.env` as the REST secret |
| RevenueCat secret REST API v1 key, `sk_...` | RevenueCat → Project settings → API keys → secret key | `/opt/abu3meer/server/.env` as `REVENUECAT_SECRET_API_KEY=sk_...`; then recreate the API container | Flutter, Gradle, AAB/APK, Git, screenshots, or chat |
| RevenueCat webhook Authorization header | Generate a long random value yourself; RevenueCat does not provide it | Put the exact full value, for example `Bearer <random>`, in both the RevenueCat webhook **Authorization header value** and server `.env` as `REVENUECAT_WEBHOOK_AUTHORIZATION="Bearer <random>"` | Flutter, Git, screenshots, or chat |
| Google service-account JSON | Google Cloud Console → IAM & Admin → Service Accounts → Keys → Add key → JSON | Upload to the RevenueCat Play app. It can also authenticate `gpc` locally after the service account has the Play permissions below. | Flutter, the Abu 3meer server, Git, screenshots, or chat |

The previously pasted webhook token must be considered exposed. Rotate it in the server `.env` and RevenueCat webhook together, recreate the API container, and use RevenueCat **Send test** to confirm HTTP 200. A manual `curl` must send the real exact header value; `YOUR_RANDOM_SECRET` or `<NEW_RANDOM_SECRET>` is only a placeholder and correctly returns 401.

The Android upload keystore and `android/key.properties` are a fifth, separate category: signing credentials. They are not RevenueCat keys and they are not the Google service-account JSON.

## Play service-account permissions

Keep both **Google Play Android Developer API** and **Google Play Developer Reporting API** enabled in the JSON service account's Google Cloud project because RevenueCat's official credential setup requires both. For `gpc` alone, the Reporting API is used for Android Vitals, `gpc apps get`, and a completely clean `gpc doctor`; it is not needed for bundle upload, tracks, subscriptions, or listings.

In Play Console → **Users and permissions**, invite the service account's `client_email` and add **ABU 3MEER** under App permissions. Then keep RevenueCat's four required Account permissions:

- **View app information and download bulk reports (read-only)**
- **View financial data, orders, and cancellation survey responses**
- **Manage orders and subscriptions**
- **Manage store presence**

RevenueCat requires those four account-level permissions; they cannot all be narrowed to a single app. For `gpc` to upload to internal testing, grant **Release apps to testing tracks** for only **ABU 3MEER**. Add **Manage testing tracks and edit tester lists** only if the CLI will manage tester groups. Do not grant **Release to production, exclude devices, and use Play App Signing** until a production release is explicitly intended.

The same JSON already used by RevenueCat can work with `gpc` after adding the app-scoped testing permission. A separate `playconsole-cli` service account is safer because it separates billing validation from release access, but it is not technically required. Google Cloud IAM roles such as Owner or Editor are not required for Android Publisher calls; the Play Console app permissions control them.

RevenueCat real-time developer notifications are separate from `gpc`: enable Pub/Sub API, grant the RevenueCat service account **Pub/Sub Editor** and **Monitoring Viewer**, and grant `google-play-developer-notifications@system.gserviceaccount.com` **Pub/Sub Publisher** on the topic if Google's test notification cannot publish. Play permission changes may take time to propagate; RevenueCat advises allowing up to 36 hours.

## Safe `playconsole-cli` setup

[`playconsole-cli`](https://github.com/AndroidPoet/playconsole-cli) is an unofficial third-party tool, not a Google product. It is currently a pre-1.0 project, so pin and re-audit updates before using them for releases. Version `0.5.15` (commit `8082c06866074216491db37dd041508be9b4b0d2`) is installed and was audited on this Mac. It supports AAB/track releases, Play listings and Play images, and read/create operations for subscriptions and base plans. It cannot attach RevenueCat entitlements, and its subscription commands do not replace the Play Console steps for updating prices or activating base plans.

If it is missing on another Mac, install it using the project's Homebrew tap, then confirm the version:

```sh
brew tap AndroidPoet/tap
brew install playconsole-cli
gpc version
```

This Mac is already configured with a private service-account profile for `com.abu3meer.app`; `gpc doctor` passes all six checks. The commands below are only for another Mac or a replacement credential. After the JSON is downloaded privately, copy it outside the repository and create an auth profile:

```sh
install -d -m 700 ~/.config/gpc
install -m 600 /ABSOLUTE/PATH/service-account.json ~/.config/gpc/abu3meer-play.json

gpc auth login \
  --name abu3meer \
  --credentials ~/.config/gpc/abu3meer-play.json \
  --default-package com.abu3meer.app
gpc auth switch --name abu3meer
```

Do not send the JSON through chat. Once it exists locally at the path above, these are safe read-only checks:

```sh
gpc auth current
gpc tracks list --package com.abu3meer.app --output table
gpc bundles list --package com.abu3meer.app --output table

gpc subscriptions get \
  --package com.abu3meer.app \
  --product-id ostoora3 \
  --pretty
gpc subscriptions base-plans list \
  --package com.abu3meer.app \
  --product-id ostoora3 \
  --output table

gpc subscriptions get \
  --package com.abu3meer.app \
  --product-id ostoora3_pro_max \
  --pretty
gpc subscriptions base-plans list \
  --package com.abu3meer.app \
  --product-id ostoora3_pro_max \
  --output table
```

`gpc doctor` also probes the optional Reporting API. A Reporting API failure does not prove that bundle publishing is broken; the focused track, bundle, and subscription commands above are the useful permission checks.

## Current Android release readiness

The source currently has package `com.abu3meer.app`, app name `ABU 3MEER`, and version `1.1.0+31`. Google Play's internal track currently contains version code 24. The saved `android/app/release/app-release.aab` is that stale build from 7 September 2026; do not upload it again.

The likely original upload keystore is present privately at `/Users/ipixeldev/Documents/Abu3meer.jks`, but `android/key.properties` and its alias/password values are not available. Do **not** generate a new keystore for this existing Play app unless Google has approved an upload-key reset. After the owner supplies the existing alias, store password, and key password, point an ignored `android/key.properties` at that file. In Play Console → **Setup → App integrity**, compare the **Upload key certificate** SHA-1 with the restored keystore. The version-24 bundle's signer SHA-1 is `3F:B8:AE:08:B6:BB:66:98:D3:41:FC:3D:F6:28:7E:3C:85:80:F7:40`; Play Console remains the authority.

Before building, use `gpc tracks list` and ensure the next source version code is greater than every version code already in Play. Version 31 is currently valid because the highest uploaded release is 24. Then build with the Android public SDK key:

```sh
flutter clean
flutter pub get
flutter build appbundle --release \
  --dart-define=REVENUECAT_ANDROID_API_KEY=goog_your_public_key

jarsigner -verify -verbose -certs \
  build/app/outputs/bundle/release/app-release.aab
keytool -printcert -jarfile \
  build/app/outputs/bundle/release/app-release.aab
```

Preview the internal upload first:

```sh
gpc bundles upload \
  --package com.abu3meer.app \
  --file build/app/outputs/bundle/release/app-release.aab \
  --track internal \
  --release-notes "Account deletion, subscriptions, and reliability fixes." \
  --release-notes-lang en-US \
  --dry-run
```

Important: this tool's `--dry-run` checks and previews the local request; it does not contact Google or prove that the credentials have permission. After the AAB, version code, certificate, release notes, and internal track have been reviewed, remove `--dry-run` to perform the upload:

```sh
gpc bundles upload \
  --package com.abu3meer.app \
  --file build/app/outputs/bundle/release/app-release.aab \
  --track internal \
  --release-notes "Account deletion, subscriptions, and reliability fixes." \
  --release-notes-lang en-US

gpc bundles wait \
  --package com.abu3meer.app \
  --version-code NEW_VERSION_CODE \
  --timeout 15m
gpc testing internal list \
  --package com.abu3meer.app \
  --output table
```

`gpc bundles upload --track internal` defaults to `--commit=true`, so the non-dry-run command immediately commits the internal-track edit. It is not merely an upload to a local draft. Manage individual tester emails and copy the opt-in link in Play Console until the CLI tester-group behaviour is separately verified.

Google's Publishing API works only after the app already exists and at least one APK/AAB has been uploaded through Play Console. It also cannot accept legal agreements or complete all policy declarations. If Google rejects the first API upload for that reason, upload the first artifact once in Play Console, finish the requested declarations there, and then use the CLI for later internal builds.

## Store listing screenshots

`gpc images` manages Google Play images only. It supports `phoneScreenshots`, `sevenInchScreenshots`, and `tenInchScreenshots`. Apple iPhone/iPad screenshots must be uploaded with App Store Connect or Fastlane; this Play CLI cannot upload them.

For Google Play, first inspect the remote set and prepare this local structure:

```text
play-listing-images/
  en-US/
    phoneScreenshots/
      01.png
    sevenInchScreenshots/
      01.png
    tenInchScreenshots/
      01.png
```

Then preview before syncing:

```sh
gpc images list \
  --package com.abu3meer.app \
  --locale en-US \
  --type phoneScreenshots \
  --output table
gpc images sync \
  --package com.abu3meer.app \
  --dir play-listing-images \
  --dry-run
```

`images sync` replaces the remote image set for each locale/type present in the directory. Keep a backup and remove `--dry-run` only after visually checking every local image.

## Remaining manual Play Console work

Play Console still must be used for payments-profile/banking approval, legal agreements, app access, Data safety, content rating, ads declaration, target audience, privacy policy, store-listing review, tester membership/opt-in link, and any required closed test or production-access application. Those tasks are not safely replaceable by this CLI.

## Firebase follow-up

Do not create or rename the Firebase Android app. Keep the existing app/package `com.abu3meer.app`. After Play App Signing is enabled, open Play Console → Test and release → Setup → App integrity, copy both the **App signing key certificate** SHA-1 and SHA-256, then add them to this existing Android app in Firebase Console → Project settings → Your apps. Download the refreshed `google-services.json` and replace `android/app/google-services.json`. This fingerprint step is required for Google sign-in in Play-installed builds and does not require rebuilding the Firebase project.

## Build troubleshooting

Use the repository's Gradle wrapper and run `flutter clean && flutter pub get` before rebuilding. The project uses AGP 8.12.1, Gradle 8.14, and Kotlin 2.4.10. Flutter 3.47 may temporarily add `android.builtInKotlin=false` and the deprecated `android.newDsl=false` compatibility flags while building older Flutter plugins. Those warnings do not cause the device to remain on “Installing”; remove the generated lines before committing, and update Flutter/plugins when Flutter no longer needs the compatibility bridge.

Release builds intentionally fail when `android/key.properties` is missing, rather than silently using a debug key. Restore the existing private upload key; do not work around that check. If the original key is genuinely lost, request an upload-key reset in Play Console and wait for Google to approve it before creating and using a replacement.

References: [playconsole-cli repository](https://github.com/AndroidPoet/playconsole-cli), [playconsole-cli command reference](https://github.com/AndroidPoet/playconsole-cli/blob/master/docs/commands.md), [audited v0.5.15 release](https://github.com/AndroidPoet/playconsole-cli/releases/tag/v0.5.15), [Google Play Developer API setup](https://developers.google.com/android-publisher/getting_started), [Google Publishing API edit limitations](https://developers.google.com/android-publisher/edits), [Play Console permission definitions](https://support.google.com/googleplay/android-developer/answer/9844686), [RevenueCat Play service credentials](https://www.revenuecat.com/docs/service-credentials/creating-play-service-credentials), and [RevenueCat Google real-time developer notifications](https://www.revenuecat.com/docs/platform-resources/server-notifications/google-server-notifications).
