# ABU 3MEER AdMob release guide

ABU 3MEER uses **Google AdMob**, not website AdSense. The code supports one
non-disruptive banner in the Home feed on Android and iOS. It does not show ads
on sign-in, account deletion, predictions, challenges, Members, purchase,
restore, or subscription-management screens. Active members do not see the
banner.

The SDK requests only non-personalized ads with restricted data processing,
teen treatment, and a maximum `PG` ad-content rating. Google UMP is queried on
every launch before any ad request, and Settings shows **Ad privacy choices**
whenever UMP requires that entry point for the user's region.

## Release configuration now

- Debug Android and iOS builds use Google's official sample app/banner IDs.
- Debug builds ignore production banner defines so they cannot accidentally
  request live ads.
- Android and iOS release builds contain their matching production App ID and
  Home banner ID. These AdMob identifiers are public application identifiers.
- Optional build overrides remain available for a deliberately separate
  release environment; malformed or Google sample production values fail
  closed.
- Never upload a release that uses a Google sample banner ID.
- No interstitial, rewarded, app-open, or purchase-adjacent ads are included.

## 1. Create both AdMob apps

Open <https://admob.google.com> and sign in.

1. Go to **Apps → Add app**.
2. Add Android. Keep package ID `com.abu3meer.app`.
3. Add iOS separately. Keep bundle ID `omar.abu3meer.app`.
4. If a store listing is not public yet, choose **No / Unpublished**, then link
   the real store entry after it becomes searchable.
5. Copy each platform's **App ID**. App IDs contain `~`.

## 2. Create one banner per platform

For each AdMob app:

1. Open **Ad units → Add ad unit → Banner**.
2. Name it `Home feed banner`.
3. Use Google-optimized refresh.
4. Copy the **Ad unit ID**. Ad unit IDs contain `/`, not `~`.

You will have four values:

```text
Android App ID:       ca-app-pub-...~...
Android Banner ID:    ca-app-pub-.../...
iOS App ID:           ca-app-pub-...~...
iOS Banner ID:        ca-app-pub-.../...
```

Do not submit the first AdMob-integrated binary until its platform has both a
real App ID and a real banner ID. The safe sample IDs are for local QA only.

## 3. Build the configured release

The production identifiers are committed in the platform-specific locations:

- Android App ID: `android/app/build.gradle.kts`
- iOS App ID: `ios/Flutter/Release.xcconfig`
- Android and iOS banner IDs: `lib/production/ad_service.dart`

Build normally:

```sh
flutter build appbundle --release
flutter build ipa --release
```

`ADMOB_ANDROID_APP_ID`, `ADMOB_ANDROID_BANNER_ID`, `ADMOB_IOS_BANNER_ID`, and
the ignored `ios/Flutter/AdMob.local.xcconfig` remain optional overrides. Do
not use them unless intentionally building for a different AdMob application.

## 4. Configure consent messages

In AdMob open **Privacy & messaging**:

1. Create and publish the European regulations message for both apps.
2. Enable consent choices and a privacy-options entry point.
3. Create the applicable US states message.
4. Keep both AdMob apps selected when publishing the messages.
5. Do not enable an IDFA/ATT message for this implementation. It deliberately
   requests non-personalized ads and does not ask for cross-app tracking.

UMP supplies the regional form. Do not create a second homemade GDPR popup.

Abu 3meer is presented as a 13+ app and currently has no verified age-band
field. Every ad request therefore receives Google's teen treatment as a
conservative default. Before enabling live ads, make sure the Play target
audience and App Store age information match that 13+ policy. If the product
later serves different treatment to adults and minors, add a neutral age-band
gate and pass the correct under-age signal to UMP; do not infer age from a
profile or silently claim that every user is an adult.

## 5. Update store declarations before the first AdMob release

### Google Play

Go to **Play Console → ABU 3MEER → Policy and programs → App content → Ads →
Manage**. Select **Yes, my app contains ads** and save. Google states this is
required for apps that include an ad SDK and banner ads. Do this before
uploading the first binary containing this integration, even if live serving is
temporarily disabled while AdMob reviews the app.

Also open **Policy and programs → App content → Advertising ID** and answer
**Yes** because the Google Mobile Ads SDK declares Android's Advertising ID
permission. Select the applicable purposes **Advertising or marketing**,
**Analytics**, and **Fraud prevention, security and compliance**. Google Play
can block an Android 13+ release when this declaration does not match the
merged manifest.

Then go to **Policy and programs → App content → Data safety → Manage**. Review
the entire form. At minimum, account for Google Mobile Ads processing:

- Approximate location (IP-derived)
- Device or other identifiers
- App interactions / product interaction
- Diagnostics / performance information
- Purposes: Advertising or marketing, Analytics, and Fraud prevention/security
  where the form offers them
- Mark the applicable Google Mobile Ads categories as both **collected** and
  **shared**; Google's disclosure guide says the SDK performs both
- Data is encrypted in transit
- The app provides an in-app account-deletion path

Do not mark data as optional merely because the banner may fail to fill. The
exact collected/shared answers must include every other SDK and the app's own
server behaviour, not AdMob alone.

### App Store Connect

Open **App Store Connect → My Apps → ABU 3MEER → App Privacy → Edit**. The local
`ios/fastlane/app_privacy.json` records the intended additional disclosures:

- Coarse location
- Device ID
- Product interaction
- Advertising data
- Crash data
- Performance data
- Other diagnostic data
- Add **Third-Party Advertising** and **Analytics** purposes as recorded

This implementation does not request App Tracking Transparency permission and
does not request personalized ads. Do not answer that the app tracks users
unless the final AdMob/privacy configuration actually links app data with
third-party data for targeted advertising or measurement. Recheck this if
personalized ads, mediation, or another ad network is enabled later.

The App Store privacy answers require an Apple web session and Google Play Data
Safety/Ads declarations are not supported by the configured publishing CLI, so
these answers must be reviewed and saved in their store web consoles.

## 6. Finish AdMob ownership and testing

1. Add the developer website to both store listings.
2. Copy AdMob's exact `app-ads.txt` line.
3. Publish it at the website root as `/app-ads.txt`.
4. In AdMob, verify app ownership and link each app to its store entry.
5. Use only Google sample ads or registered test devices during QA.
6. Confirm a visible **Test Ad** label before tapping any ad during testing.

The current Google Play developer website is
`https://ipixeldev.github.io/Abu-3meer`. AdMob uses only that URL's hostname,
so it will look for `https://ipixeldev.github.io/app-ads.txt`, not inside the
`/Abu-3meer/` project path. Either publish the file from the root GitHub Pages
site, or change both store listings to a domain you control (for example the
Abu 3meer website) and serve `/app-ads.txt` at that domain's root.

Official references:

- <https://developers.google.com/admob/flutter/quick-start>
- <https://developers.google.com/admob/flutter/privacy>
- <https://developers.google.com/admob/flutter/test-ads>
- <https://developers.google.com/admob/ios/privacy/data-disclosure>
- <https://support.google.com/googleplay/android-developer/answer/9859455>
- <https://support.google.com/googleplay/android-developer/answer/6048248>
- <https://support.google.com/admob/answer/9363762>
