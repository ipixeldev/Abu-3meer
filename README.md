# The Fan League — Flutter Client Demo

A responsive, frontend-only football fan engagement prototype for client presentations. The project uses simulated local state and intentionally has no backend, external authentication, football API, YouTube API, or payment integration.

## Run on web

Flutter is installed at `/Users/ipixeldev/flutter/bin/flutter` on this machine.

```bash
cd "/Users/ipixeldev/Desktop/Abu3meer Demo"
CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  /Users/ipixeldev/flutter/bin/flutter run -d chrome
```

Do not open `web/index.html` directly. Flutter Web must be served over HTTP.

## Presentation areas

- Login, account creation, profile setup, and team selection
- Fan Hub, Match Center, predictions, and completed match rewards
- Season leaderboard, public fan profiles, and Barcelona vs Real Madrid Fan War
- Challenge hub and playable secret-phrase/knowledge challenge states
- Streaks, achievements, levels, loyalty rewards, notifications, and activity
- Profile, YouTube membership simulation, editing, and settings
- Demo scenario controls
- Twelve-section admin console with local creation dialogs
- Navigation-free OBS/browser-source overlay with simulated ranking movement

## Quality checks

```bash
/Users/ipixeldev/flutter/bin/flutter analyze
/Users/ipixeldev/flutter/bin/flutter test
/Users/ipixeldev/flutter/bin/flutter build web
```

The active presentation implementation is in `lib/demo`. Earlier generated prototype source is retained under `lib/core` and `lib/features` as migration reference and is excluded from analysis because it was incomplete and internally inconsistent.
