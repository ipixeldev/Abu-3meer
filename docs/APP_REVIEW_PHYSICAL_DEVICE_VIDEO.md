# App Review physical-device video

Record the corrected build **1.1.0 (34)** on a physical iPhone running the latest available iOS. Do not reuse an older recording because build 34 contains the current production RevenueCat and AdMob configuration, verified public-domain links, privacy-hardened ad identifiers, and the hardened account-deletion flow. Use one continuous recording when practical, starting from the iPhone Home Screen and showing the app being launched.

## Before recording

- Install build 34 from TestFlight after the matching server update has been deployed.
- Confirm notifications are allowed in iOS Settings.
- Prepare one disposable account for demonstrating account deletion.
- Keep the permanent App Review demo account available for the rest of the flow.
- Prepare a harmless test profile you own for demonstrating Report and Block. Do not report a real user.
- In Admin Studio, publish at least one open prediction, one playable challenge, and one members-only item. Confirm they remain available after closing and reopening the app.
- Sign into an Apple sandbox tester that can purchase or restore the subscriptions.
- Hide passwords, email notifications, phone numbers, and other personal information.
- Note the iPhone model, iOS version, build number, and storefront currency for the written reply.

## Record this exact flow

1. Start on the iPhone Home Screen and launch **ABU 3MEER**.
2. Briefly show the Home screen, then open sign-in and account registration.
3. Create the disposable account, verify its email if requested, and finish onboarding. Show that the profile photo can be skipped.
4. Open **Profile > Settings > Account > Delete account**. Show the warning that deleting the account does not cancel an Apple subscription, show the Manage Apple Subscription option, type DELETE, and finish deletion.
5. Sign in to the permanent App Review demo account. Use Password AutoFill or cover the password while recording.
6. Show the normal user flow: **Home**, **Predict**, **Challenges**, **Members**, and **Profile**. Open one representative prediction or challenge so Apple can see what a user actually does.
7. Open **Leaderboard**, select the harmless test profile, tap **Report profile**, choose a reason, and submit. Then tap **Block user** and show that the profile disappears. Open **Profile > Settings > Account > Blocked users** and demonstrate Unblock.
8. Open **Members > View plans**. Pause long enough to show both plans, including each title, duration, localized price, benefits, renewal wording, Restore Purchases, Terms of Use, and Privacy Policy. Open the Terms and Privacy links briefly.
9. Complete one sandbox purchase, or restore a prepared sandbox purchase. Show the member content becoming available and the member badge appearing. Open Subscription details and show Restore/Manage subscription.
10. On the Members screen, briefly show the separate **existing YouTube member** verification control. Show that iOS has no link or button to buy a YouTube membership; this control only checks a membership the user already obtained independently.
11. Open notification settings and show notifications enabled. Send one test notification and show it arriving on the locked device.
12. If the supplied reviewer account has a staff role, open **Admin Studio > User Reports**, show the report created in step 7, and record a harmless resolve or dismiss decision with an audit note.
13. Return to Home and end the recording.

## Upload and submit

- Upload the video as an unlisted or public link that does not require Apple to sign in or request access.
- Test the link in a private browser window.
- Capture the fresh App Store screenshots listed in `docs/APP_STORE_SCREENSHOT_PLAN.md` from this same build while its representative content is available.
- Put the same video URL and the complete seven numbered answers in both:
  - **App Store Connect > My Apps > ABU 3MEER - League > iOS 1.1.0 > App Review Information > Notes**
  - the reply in **Resolution Center**
- Replace every bracketed placeholder in ios/fastlane/review_notes.txt before pasting it. Never submit placeholder text.

## Evidence to attach

Attach proof that the developer is authorized to use the Abu 3meer channel/brand and any protected league, club, player, logo, image, video, or sports-data material shown by the app. A data-provider invoice or API subscription alone may not grant publication rights.
