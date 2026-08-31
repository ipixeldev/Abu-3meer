# Abu 3meer App Store Compliance Notes

Updated: 31 August 2026

## Required URLs

- Marketing URL: https://ipixeldev.github.io/Abu-3meer/
- Privacy Policy URL: https://ipixeldev.github.io/Abu-3meer/privacy/
- Privacy Choices URL: https://ipixeldev.github.io/Abu-3meer/delete-account/
- Support URL: https://ipixeldev.github.io/Abu-3meer/support/
- XP & Leaderboard Rules URL: https://ipixeldev.github.io/Abu-3meer/competition-rules/
- Account Deletion URL: https://ipixeldev.github.io/Abu-3meer/delete-account/
- Age Suitability URL: https://ipixeldev.github.io/Abu-3meer/age-suitability/

## App Review Rules Implemented

- Sign in with Apple is available on iOS alongside Google and email sign-in.
- Account deletion is available in Settings.
- Privacy Policy, Terms of Use, XP & Leaderboard Rules, and Support are available in Settings and on the public website.
- The app is completely free and has no purchases, paid entry, betting, wagering, prizes, rewards, or leaderboard winners.
- XP is awarded only for correct football predictions and correct video-question or player-guess answers.
- Verified YouTube members receive 2× XP only for those eligible actions. Signup, daily login, and passive activity are not multiplied.
- XP has no monetary value, cannot be bought, transferred, or redeemed, and unlocks nothing.
- Current-month, previous-month, and season leaderboards provide recognition only. Monthly XP resets while the completed month remains visible, and completed seasons remain available as archived rankings.
- The public XP & Leaderboard Rules state that Apple does not sponsor, administer, or participate in XP scoring or rankings.
- The iOS target contains `Runner/PrivacyInfo.xcprivacy`; it declares no tracking and is packaged at the app-bundle root.

## App Privacy Declaration

App Store Connect's privacy declaration must cover both first-party collection and embedded SDKs. The conservative declaration for the current build is:

- Data collected: yes.
- Tracking: no.
- No third-party advertising or developer advertising/marketing use.
- Contact information, YouTube membership status, location used for country suggestion, selected media, gameplay/user/search content, user/device identifiers, product interaction, usage data, diagnostics, and other profile/security data are disclosed for app functionality and the applicable analytics or personalization purposes.

Do not publish a narrower declaration without re-auditing the app, server logs, Google Sign-In, and Firebase privacy manifests.

## Content Rights

The current app accesses third-party football data, club marks, YouTube content, and thumbnails. App Store Connect's Content Rights declaration must not be certified until the developer has written authorization for the submitted content or the build is changed to use owned/licensed assets and permitted factual data only. A football API subscription by itself is not evidence of club-logo, league-mark, or publication rights; retain the provider and rightsholder licenses with the release records.

## App Store Age Rating Guidance

Answer the questionnaire based on the product that is actually shipped. Apple defines contests broadly enough to include events where users compete for rankings or personal goals, even when nothing of value is awarded. For the XP-only product described above:

- Contests: Frequent, because predictions and video questions contribute to recurring public monthly and season rankings.
- Simulated Gambling: None.
- Gambling: No.
- Loot Boxes: No.

The absence of paid entry, staking, prizes, rewards, redemptions, and exchangeable currency is why the gambling, simulated-gambling, and loot-box answers remain negative; it does not make a recurring public ranking cease to be a contest for the age-rating questionnaire. Keep screenshots, App Store copy, review notes, website copy, and in-app legal text consistent with the shipped behavior.

If App Store Connect applies a Morocco restriction after this accurate questionnaire is saved, contact Apple Developer Support with the build number and the XP & Leaderboard Rules URL. Do not change an answer merely to bypass a territory restriction.
