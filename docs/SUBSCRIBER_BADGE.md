# Subscriber badge

The green-circle/white-star badge is shown beside active members' names
on profiles, monthly/season leaderboards, settings, and staff user/audit lists.
Both Ostoora3 billing plans, a current verified YouTube membership, and an
explicit administrator access grant use the same badge. Staff roles alone do
not imply membership.

The server derives `hasMemberAccess` from its effective, override-aware access
decision. Public responses expose only the badge/access boolean, not billing
details. Expiration, a YouTube recheck requirement, or an admin block takes
effect when fresh server data is loaded. Genuine App Store and Google Play
sandbox purchases receive the badge for testing; synthetic RevenueCat Test
Store receipts remain subject to the explicit server policy. Deploy the server
and Flutter build together so every public profile and leaderboard agrees.

Asset: `assets/images/subscriber_badge_source.jpg` (626 × 548).
This is an unchanged binary copy of the user's replacement JPG. `SubscriberBadge`
uses a centered circular viewport inside the original green circle, so the
surrounding black rectangle is not displayed. No generated artwork, pixel edits,
redrawn star, or vector substitute is used. The viewport diameter is 342 source
pixels, just inside the circle's antialiased JPEG edge; Flutter scales the source
and clips it at render time. The old generated PNG is no longer displayed.

`SubscriberName` reserves badge space when a long name is truncated, supports
RTL layout, and includes a localized accessibility label.

The separate `lib/main_paywall_preview.dart` entrypoint is debug-only and opens
the actual RevenueCat App Store offering for screenshots. It does not grant
membership or set mock prices. Normal app builds use `lib/main.dart`.

`ios/Abu3meerAppStorePreview.storekit` was synchronized by Xcode from Apple app
6808717649. Its US prices are $3.99/month and $39.99/year as of 2026-09-06.
Using it in a local preview scheme simulates StoreKit billing and is suitable
for viewing the UI, not proof that sandbox/production purchases are working.
