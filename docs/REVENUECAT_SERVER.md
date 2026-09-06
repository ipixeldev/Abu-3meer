# RevenueCat server setup

Project: `proja7bd8e75`. Both Ostoora3 monthly and Ostoora3 Pro Max yearly map to entitlement `abu_3meer_pro`. The current App Store US prices verified on 6 September 2026 are USD 3.99/month and USD 39.99/year. Configure store prices in App Store Connect/Google Play and import the matching product identifiers into RevenueCat; server access is based on the entitlement, not a price or client claim. Display localized prices returned by the store rather than hardcoding these amounts in the app.

The Flutter SDK uses the authenticated server account's UUID (`/profile/me` → `user.id`) as RevenueCat `appUserID`. Do not use a Firebase UID, email, channel URL, or anonymous ID for a signed-in purchase. Native customer info drives paywall display; the server independently checks RevenueCat before granting protected content or gameplay benefits.

## Credentials and deployment

1. In the RevenueCat project's API keys page, create a secret REST API v1 key. Put it only in `server/.env` as `REVENUECAT_SECRET_API_KEY=sk_...`. The public `test_...` SDK key is not this credential.
2. Generate a random webhook authorization value and set `REVENUECAT_WEBHOOK_AUTHORIZATION="Bearer <random value>"` in the same file. Do not commit this file or paste the secret into chat.
3. Set `REVENUECAT_ALLOW_SANDBOX=false` for live production. For an intentional TestFlight/Test Store test deployment, set it to `true` to allow test receipts to grant member benefits; return it to `false` before serving paid production customers. Test Store SDK keys cannot be used for App Store purchases.
4. Deploy the code using the existing repository release workflow. The API startup runs migration `041_revenuecat_subscriptions.sql`; Docker Compose now forwards all three environment variables. Recreating the API container is required after `.env` changes (a plain restart does not reload Compose environment).
5. In RevenueCat → Integrations → Webhooks, configure URL `https://api.abu3meer.com/api/v1/subscriptions/webhook`, the exact Authorization header from step 2, and the appropriate app/environments. Send all event types so renewals, refunds, expirations, and transfers refresh the backend. Use Send Test to verify a 200 response.

The API does not need the App Store `.p8` or public SDK key. RevenueCat holds the store credentials; the server uses only its secret REST API key.

## API contract

- `POST /api/v1/subscriptions/sync` — Firebase Bearer token, `{}` body. Called after purchase/restore, login, and app foreground. Client user IDs and entitlement fields are rejected.
- `GET /api/v1/subscriptions/status` — Firebase Bearer token. Reads verified state and rechecks expiry; does not contact RevenueCat.
- `POST /api/v1/subscriptions/webhook` — dedicated RevenueCat Authorization header. Retries are idempotent; transfer events refresh both old and new existing backend UUIDs. Event entitlement claims never directly grant access.

Successful sync/status responses:

```json
{
  "data": {
    "entitlementId": "abu_3meer_pro",
    "isActive": true,
    "productId": "your_store_product_identifier",
    "expiresAt": "2026-10-05T12:00:00.000Z",
    "willRenew": true,
    "isSandbox": false,
    "verifiedAt": "2026-09-05T12:00:00.000Z"
  }
}
```

Missing server credentials produce 503 with code `subscriptions_not_configured`. Verification failures leave the previous stored state unchanged, but access still expires at the paid/grace-period end and at most 24 hours after the last successful check. A cancellation keeps access through the paid term; a verified refund removes paid access.

`/auth/sync` and `/profile/me` return separate `isYouTubeMember`, `isProSubscriber`, and `hasMemberAccess` fields. Valid CSV membership OR an active server-verified subscription grants Members Zone videos, member-only challenges, member notification eligibility (subject to notification preferences), and the existing x2 eligible gameplay XP. Signup/daily attendance XP remains unmultiplied. CSV imports and subscription updates never overwrite one another, and paid subscriptions never grant staff roles.

## Verification before release

Make one sandbox purchase and one restore with the same backend UUID, check the RevenueCat customer page, and verify both SDK entitlement and `/subscriptions/sync` agree. Test cancellation/expiry/refund, account switching, an account without a purchase, and a CSV member without a subscription. These store tests require configured real products/credentials; unit tests cannot certify store payment processing.

Sources: [RevenueCat REST API](https://www.revenuecat.com/docs/api-v1/customers), [webhook setup and retry semantics](https://www.revenuecat.com/docs/integrations/webhooks).
