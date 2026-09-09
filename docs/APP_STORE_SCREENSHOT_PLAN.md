# App Store screenshot replacement plan

The screenshots currently stored in ios/fastlane/screenshots are from an older build. They show the retired **Exclusive** tab, identifiable user profiles, and football imagery whose publication rights must be documented. Do not reuse or upload them for build 30.

Capture fresh screenshots from the same corrected build used for the review video. Use only accounts and media owned by Abu 3meer or covered by written publication permission. Keep passwords, email addresses, notification previews, and other personal data out of every image.

## Required sizes

- iPhone: use one accepted 6.9-inch portrait size, such as **1290 × 2796**, **1320 × 2868**, or **1260 × 2736** pixels.
- iPad (the app currently supports iPad): use **2064 × 2752** or **2048 × 2732** pixels in portrait.
- Provide 1–10 screenshots per device family. Use the same current images for English and Arabic only if the visible language actually matches that localization.

## Recommended set

Capture at least these five screens in English and Arabic:

1. Home with current app navigation and owned/licensed content.
2. Predict with a representative open match prediction.
3. Challenges with a representative video question or player guess.
4. Members with member content visible, without showing a sandbox/test warning.
5. Leaderboard using synthetic or consented test names and neutral avatars.

An optional sixth screenshot may show the subscription plan selector, but only when both product titles, durations, and localized prices are loaded from the App Store.

## Upload rule

Delete the old screenshot sets in App Store Connect before uploading the replacements. The current Fastlane screenshot lane is intentionally not safe for replacement because overwrite_screenshots is false. Do not run it until the replacement files have been reviewed and the lane has been changed to overwrite the old set.
