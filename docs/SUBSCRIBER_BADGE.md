# Subscriber badge

The green-circle/white-star badge is shown beside active app subscribers' names
on profiles, monthly/season leaderboards, settings, and staff user/audit lists.
Both Ostoora3 billing plans use the same badge. CSV membership and staff roles
remain separate and do not imply an app subscription.

The server derives `isProSubscriber` from its verified `abu_3meer_pro`
entitlement. Public responses expose only the boolean, not billing details.
Expiration/removal takes effect when fresh server data is loaded. Deploy the
updated server code as well as the Flutter build for public-profile and
leaderboard badges; older servers safely render no subscriber badge.

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
