# Phase 3 security rollout

The Phase 3 security foundation lives in `functions/src/phase3_security.ts`.
It is deliberately separate from the business callables so it can be rolled
out gradually instead of accidentally blocking every installed client at once.

## What is implemented

- Three App Check modes: `off`, `monitor`, and `enforce`. Firebase emulators
  always resolve to `off`, even if a developer has production environment
  variables on their machine.
- Reusable callable options for App Check enforcement. App Check token
  consumption is only enabled for explicitly marked, low-volume critical
  mutations.
- A handler-level security gate that checks authentication, profile presence,
  suspended accounts, missing/replayed App Check tokens, and fixed-window
  request limits.
- Atomic per-user, per-installation, and per-IP rate counters. IP addresses and
  installation tokens are stored only as SHA-256 hashes with a secret pepper.
- Aggregated `suspiciousEvents` records for rate-limit breaches, suspended-user
  attempts, missing App Check attestations during monitoring, consumed-token
  replay, and idempotency-key conflicts.
- Generic request idempotency reservations that distinguish a safe duplicate
  from a key reused with a different payload. Reservations and rate counters
  include `expireAt` fields for Firestore TTL cleanup.
- Firestore rules that block suspended accounts from profile/community/duel
  mutations, keep security counters private, and provide admins with a live,
  triageable suspicious-events stream.

## Callable integration pattern

Each callable needs both trigger-level App Check options and the handler-level
gate. Keep business-ledger idempotency as the final authority; the security
reservation is an additional replay/conflict signal.

```ts
export const submitPrediction = onCall(
  phase3CallableOptions(region),
  async (request) => {
    const security = await enforceCallableSecurity(request, {
      action: "submitPrediction",
      perUserLimit: 12,
      perDeviceLimit: 18,
      perIpLimit: 80,
    });
    // Existing transaction follows.
  },
);
```

For a low-volume critical operation such as a loyalty redemption:

```ts
phase3CallableOptions(region, {replayProtected: true})
```

and set `rejectConsumedAppCheckToken: true` in its handler security policy.
Do not enable token consumption on high-frequency game taps or ordinary reads;
it adds latency and consumes attestation-provider quota.

## Required Firebase Console and release actions

No production setting has been changed and nothing has been deployed.

1. Register every Firebase app with App Check:
   - Web/PWA: reCAPTCHA v3, matching the current
     `ReCaptchaV3Provider` client configuration. If the project chooses
     reCAPTCHA Enterprise, switch the Flutter provider at the same time.
   - iOS: App Attest with DeviceCheck fallback.
   - Android: Play Integrity.
2. Add and initialize `firebase_app_check` in Flutter before any callable or
   Firestore request. Configure debug providers only in debug builds and add
   local debug tokens in the Firebase Console.
3. Create the Secret Manager secret `SECURITY_HASH_PEPPER` with a random value
   of at least 32 characters. Grant the Functions runtime access when Firebase
   prompts during deployment.
4. Start with `ABU3MEER_APP_CHECK_MODE=monitor`, deploy the integrated
   callables, and watch App Check metrics plus `suspiciousEvents`. The mode is
   read while functions are deployed, so changing it requires a redeploy.
5. Once supported-client coverage is acceptable, change the mode to `enforce`
   and redeploy. Keep older required app versions in mind before enforcement.
6. Enable Firestore TTL policies on `expireAt` for `securityRateLimits` and
   `securityIdempotency`.
7. Deploy the updated Firestore rules and indexes. Admin clients can stream
   open signals with `status == "open"`, ordered by `lastSeen desc`.
8. Add alerting for high/critical suspicious events (Cloud Monitoring, email,
   or an admin notification workflow). Do not automatically suspend users from
   one IP-only signal; shared networks and carrier NAT create false positives.

## Suggested initial limits

The helper defaults to 20 requests/user/minute, 30/installation/minute, and
100/IP/minute. Override these per callable. Prediction and challenge submissions
should be tighter; ordinary content operations can be looser. Duel taps need a
purpose-built higher-frequency policy rather than the defaults.

Recommended first-pass policies:

| Callable | User/min | Device/min | IP/min | Consume token |
| --- | ---: | ---: | ---: | --- |
| `completeOnboarding` | 5 | 8 | 30 | No |
| `submitPrediction` | 12 | 18 | 80 | No |
| `submitChallenge` and legacy challenge aliases | 20 | 25 | 100 | No |
| `claimAchievement` | 10 | 15 | 60 | No |
| `redeemLoyaltyReward` | 5 | 8 | 30 | Yes |
| Admin content mutations | 10 | 15 | 40 | Yes for result/point/reward mutations |

`completeOnboarding` must set `requireActiveProfile: false` because the profile
does not exist yet. Every exported legacy challenge alias needs its own guard;
protecting only `submitChallenge` does not protect separately exported handlers.

## Privacy and operational notes

- `Firebase-Instance-ID-Token` is an unverified rate-limit hint, never an
  authorization credential.
- A Cloud Functions IP is useful for throttling but is not a durable identity.
- Suspicious signals are aggregated into hourly fingerprints to avoid turning
  an attack into unbounded event writes.
- Rotate the hash pepper only with a planned migration; rotation intentionally
  changes all future IP/device hashes.
