# Abu 3meer App Store Compliance Notes

Updated: 31 August 2026

## Required URLs

- Marketing URL: https://ipixeldev.github.io/Abu-3meer/
- Privacy Policy URL: https://ipixeldev.github.io/Abu-3meer/privacy/
- Privacy Choices URL: https://ipixeldev.github.io/Abu-3meer/delete-account/
- Support URL: https://ipixeldev.github.io/Abu-3meer/support/
- Competition Rules URL: https://ipixeldev.github.io/Abu-3meer/competition-rules/
- Account Deletion URL: https://ipixeldev.github.io/Abu-3meer/delete-account/
- Age Suitability URL: https://ipixeldev.github.io/Abu-3meer/age-suitability/

## App Review Rules Implemented

- Sign in with Apple is available on iOS alongside Google and email sign-in.
- Account deletion is available in Settings.
- Privacy Policy, Terms of Use, Competition Rules, and Support are available in Settings and on the public website.
- Official competition rules state that Apple is not a sponsor or involved in competitions.
- YouTube members receive 2x points only for predictions and video challenges, including player guesses. Signup and daily streak points are not multiplied.
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

Answer the questionnaire based on the product that is actually shipped.

- Contests: Frequent if real prize leaderboards or recurring competition rewards are available in the submitted app.
- Simulated Gambling: None.
- Gambling: No.
- Loot Boxes: No.

Do not mark contests as None while real prize leaderboards are offered. Apple states that age rating answers must accurately represent the app. If Morocco must remain available and Apple blocks the app solely because Frequent Contests is selected, the compliant options are:

1. Remove competitive rankings and prize contests from the submitted app so that `Contests: None` accurately describes the shipped product. Personal predictions, questions, streaks, and non-redeemable personal XP may remain.
2. Make contests genuinely occasional and choose `Infrequent` only if that accurately describes the product, then verify whether Apple still applies the restriction.
3. Ask Apple in writing whether a server-enforced, contest-free Moroccan experience permits the same app record to remain available there, and how the global questionnaire should be answered.
4. Obtain Moroccan legal advice and any required authorization, then provide that documentation to App Review and Apple Developer Support.

Excluding Moroccan users only from physical prizes is an important legal safeguard, but it does not necessarily clear Apple's automatic restriction because Apple defines contests broadly enough to include rankings and personal goals. There is no documented developer override for the warning, and raising the age rating does not remove it.

Ordinary leaderboards are described as recognition and in-app progression, not an automatic promise of a real-world prize. Any future real-prize promotion requires a separate Promotion Notice. Paid YouTube-member multipliers must be excluded from prize scoring unless the notice provides an equal free scoring opportunity.
