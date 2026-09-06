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

Asset: `assets/images/subscriber_badge.png` (true PNG alpha).
Created with the built-in image editing tool using the user's supplied badge.
Prompt: Remove only the dark navy rectangular background, making the space
outside the green circle transparent. Preserve the green circle and rounded
white five-point star; center with minimal transparent padding. No text,
border, shadow, or drawn checkerboard.

`SubscriberName` reserves badge space when a long name is truncated, supports
RTL layout, and includes a localized accessibility label.

The separate `lib/main_paywall_preview.dart` entrypoint is debug-only and opens
the actual RevenueCat App Store offering for screenshots. It does not grant
membership or set mock prices. Normal app builds use `lib/main.dart`.

`ios/Abu3meerAppStorePreview.storekit` was synchronized by Xcode from Apple app
6808717649. Its US prices are $3.99/month and $39.99/year as of 2026-09-06.
Using it in a local preview scheme simulates StoreKit billing and is suitable
for viewing the UI, not proof that sandbox/production purchases are working.
