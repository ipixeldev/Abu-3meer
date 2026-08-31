# Abu 3meer

Abu 3meer is a production Flutter fan platform for web, iOS, and Android. The active application uses Firebase Authentication, Cloud Firestore, callable Cloud Functions, and a server-owned points ledger. Its existing premium dark/lime interface is preserved while the former demo flows are replaced by live data.

## Implemented production flows

- Email registration, email verification, sign-in, password reset, and Google sign-in
- Profile onboarding with a unique username, country, and supported club
- Admin-created match events with server-enforced prediction windows
- Saved exact-score and first-scorer predictions with history and result breakdowns
- Server-owned XP transactions and current-month, previous-month, and season leaderboards
- Video questions and player guesses with schedules, attempt limits, member access, and private answer keys
- Admin result publishing and editable launch point rules
- Strict Firestore and Storage security rules

The app is completely free. XP is granted once at signup (50 XP), for the first login each UTC day (5 XP), and for correct football predictions and correct video-question or player-guess answers. Verified YouTube members receive 2× XP only on eligible prediction and video-answer actions; signup and daily-login XP are never doubled. XP has no monetary value, cannot be bought, transferred, or redeemed, and unlocks nothing. Leaderboards are for recognition only and have no winners, prizes, or rewards.

The Phase 2 schema and feature contract are documented in
[`docs/PHASE_2_CORE_PRODUCT.md`](docs/PHASE_2_CORE_PRODUCT.md).
Ubuntu production migration, backups, Cloudflare Tunnel cutover, and Firebase
push setup are documented in
[`docs/UBUNTU_SERVER_DEPLOYMENT.md`](docs/UBUNTU_SERVER_DEPLOYMENT.md).

## Run locally

Install Flutter and make sure `flutter` is available on your `PATH`, then run
these commands from the repository root:

```bash
flutter pub get
flutter run -d chrome
```

To use Brave, Flutter still targets the `chrome` web device while the executable is overridden:

```bash
CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  flutter run -d chrome
```

Do not open `web/index.html` directly. Flutter Web must be served over HTTP.

## Verification

```bash
flutter analyze
flutter test
npm test --prefix functions
flutter build web --release --no-wasm-dry-run
```

## Firebase

The repository is linked to Firebase project `abu-3meer-9fd70`. Production Android and iOS use bundle/package ID `com.abu3meer.app`.

Backend source lives in `functions/src`, database access rules in `firestore.rules`, indexes in `firestore.indexes.json`, and upload rules in `storage.rules`.

The native production app uses the self-hosted PostgreSQL API in `server/` for
profiles, predictions, points, admin operations, football data, uploads, and
push campaigns. The remaining Firebase Functions sources are legacy/optional
web infrastructure and are not a substitute for deploying that API.

Before public launch, enable Email/Password and Google providers in Firebase Authentication, add Android signing fingerprints, select the Apple signing team in Xcode, and replace the placeholder support/social URLs in `lib/production/brand.dart`.

The project-specific Android debug keystore is intentionally ignored. A fresh
clone can build with Gradle's per-user debug key; add that key's SHA-1/SHA-256
fingerprints to Firebase before testing Google Sign-In. Production releases
must use a separate Play signing key supplied outside Git.
