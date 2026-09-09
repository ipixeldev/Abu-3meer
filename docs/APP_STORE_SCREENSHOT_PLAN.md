# App Store screenshot replacement plan

The screenshots previously stored in `ios/fastlane/screenshots` came from an older build and showed the retired **Exclusive** tab, identifiable user profiles, and football imagery whose publication rights must be documented. Those files have been replaced; do not recover or reuse them for build 31.

On 9 September 2026, App Store Connect version 1.1.0 was updated with reviewed build-31 simulator captures. English and Arabic each contain three `APP_IPHONE_67` screenshots at **1320 x 2868** and three `APP_IPAD_PRO_3GEN_129` screenshots at **2064 x 2752**. The legacy Arabic `APP_IPHONE_65` set contains the same three reviewed screens at **1242 x 2688** so Apple does not retain an empty blocking set. The uploaded order is Challenges, Members, Subscription details. All 15 assets reached `COMPLETE`; the prior assets were backed up under `artifacts/app-store/backup-before-build31/` before replacement.

Capture fresh screenshots from the same corrected build used for the review video. Use only accounts and media owned by Abu 3meer or covered by written publication permission. Keep passwords, email addresses, notification previews, and other personal data out of every image.

## Required sizes

- iPhone: use one accepted 6.9-inch portrait size, such as **1290 × 2796**, **1320 × 2868**, or **1260 × 2736** pixels.
- iPad (the app currently supports iPad): use **2064 × 2752** or **2048 × 2732** pixels in portrait.
- Provide 1–10 screenshots per device family. Use the same current images for English and Arabic only if the visible language actually matches that localization.

## Future richer replacement set

Capture at least these five screens in English and Arabic:

1. Home with current app navigation and owned/licensed content.
2. Predict with a representative open match prediction.
3. Challenges with a representative video question or player guess.
4. Members with member content visible, without showing a sandbox/test warning.
5. Leaderboard using synthetic or consented test names and neutral avatars.

An optional sixth screenshot may show the subscription plan selector, but only when both product titles, durations, and localized prices are loaded from the App Store.

## Upload rule

Back up the current App Store Connect assets before replacing them. `ios/fastlane/screenshots` now mirrors the reviewed build-31 captures, and the Fastlane lane overwrites the existing sets. Run it only after visually reviewing every local file and setting its explicit confirmation variable.
