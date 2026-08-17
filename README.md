# Abu 3meer

Abu 3meer is a production Flutter fan platform for web, iOS, and Android. The active application uses Firebase Authentication, Cloud Firestore, callable Cloud Functions, and a server-owned points ledger. Its existing premium dark/lime interface is preserved while the former demo flows are replaced by live data.

## Current production flows

- Email registration, email verification, sign-in, password reset, and Google sign-in
- Profile onboarding with a unique username, country, and supported club
- Admin-created match events with server-enforced prediction windows
- Exact-score predictions worth 100 points, or 200 for verified members
- Server-owned point transactions and season/monthly leaderboards
- Admin result publishing and editable launch point rules
- Strict Firestore and Storage security rules

## Run locally

Flutter is installed at `/Users/ipixeldev/flutter/bin/flutter` on this machine.

```bash
cd "/Users/ipixeldev/Desktop/Abu3meer Demo"
/Users/ipixeldev/flutter/bin/flutter pub get
/Users/ipixeldev/flutter/bin/flutter run -d chrome
```

To use Brave, Flutter still targets the `chrome` web device while the executable is overridden:

```bash
CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  /Users/ipixeldev/flutter/bin/flutter run -d chrome
```

Do not open `web/index.html` directly. Flutter Web must be served over HTTP.

## Verification

```bash
/Users/ipixeldev/flutter/bin/flutter analyze
/Users/ipixeldev/flutter/bin/flutter test
npm test --prefix functions
/Users/ipixeldev/flutter/bin/flutter build web --release --no-wasm-dry-run
```

## Firebase

The repository is linked to Firebase project `abu-3meer`. Production Android and iOS use bundle/package ID `com.abu3meer.app`; the web app keeps the existing Firebase Hosting identity.

Backend source lives in `functions/src`, database access rules in `firestore.rules`, indexes in `firestore.indexes.json`, and upload rules in `storage.rules`.

Before public launch, enable Email/Password and Google providers in Firebase Authentication, add Android signing fingerprints, select the Apple signing team in Xcode, and replace the placeholder support/social URLs in `lib/production/brand.dart`.
