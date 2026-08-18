# Abu 3meer V1.1 popup

## English

- Title: `V1.1 — THE MATCH JUST GOT BIGGER`
- Message: `A sharper Abu 3meer experience is here. Predict the exact score, choose the first scorer, call whether both teams will score, protect your streak, and follow every point from your activity history. We also upgraded desktop layouts, Arabic support, team badges, admin previews, and PWA installation.`
- Button: `EXPLORE V1.1`
- Suggested destination: the Home screen or Predictions screen.

## Arabic

- Title: `V1.1 — المباراة أصبحت أكبر`
- Message: `تجربة أبو 3مير الجديدة وصلت. توقّع النتيجة الدقيقة، اختر أول مسجّل، وتوقّع ما إذا كان الفريقان سيسجلان، وحافظ على سلسلتك، وتابع كل نقطة في سجل النشاط. كما حسّنا تصميم سطح المكتب، ودعم العربية، وشعارات الفرق، ومعاينات الإدارة، وتثبيت التطبيق كتطبيق ويب.`
- Button: `اكتشف V1.1`
- Suggested destination: Home or Predictions.

Artwork: `assets/images/v1_1_update_popup.png`

Recommended campaign settings:

- Frequency: once per campaign
- Start: immediately after the V1.1 deployment
- End: 14 days after deployment
- Image fit: cover, with the right side kept visible

# Production roadmap — easiest first

## Phase 1 — product polish and validation

- Complete a manual English/Arabic copy review on phone, tablet, and desktop.
- Add widget tests for prediction controls, popup validation, settings persistence, and all empty/error states.
- Add admin draft/edit/delete flows and clearer unsaved-change warnings.
- Add pagination and filters to activity, leaderboard, community, and admin tables.
- Add account-wide popup delivery receipts instead of device-only local receipts.

## Phase 2 — engagement and operations

- Persist real streak check-ins and milestone awards on the server.
- Complete achievements, levels, loyalty catalogue, redemption history, and prize fulfillment.
- Add notification preference enforcement, push-token registration, and admin campaigns.
- Add admin user search, suspension, manual point adjustments with reasons, audit-log views, and suspicious-activity tools.
- Expand match and challenge analytics, prediction history, saved-pick editing, and user rank outside the top 100.

## Phase 3 — content and data integrations

- Replace direct third-party football calls with a licensed, server-cached team/match provider.
- Replace the public YouTube RSS bridge with a first-party scheduled sync and resilient cache.
- Add reusable event types, multi-question quizzes, richer Player Cards, prizes, and media management.
- Add real push notifications for match openings, challenge launches, results, rewards, and posts.

## Phase 4 — deferred infrastructure and external verification

- Deploy Cloud Functions and prove the complete prediction → result → points → leaderboard journey.
- Enable Firebase Storage and switch popup/post/challenge/avatar media from preview-only/fallback behavior to real uploads.
- Verify Google sign-in on real iOS and Android devices after the OAuth configuration fix.
- Implement trusted YouTube channel-membership verification and loyalty-point syncing.

These four items intentionally remain last for now because they require billing, platform-console configuration, external credentials, and/or real-device verification.
