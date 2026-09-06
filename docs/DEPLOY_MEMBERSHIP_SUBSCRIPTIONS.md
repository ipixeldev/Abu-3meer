# Deploy the membership and subscription fixes

Run these commands **on the Ubuntu server**, one block at a time. Do not continue after an error. These steps preserve the database and uploaded CSV files; they do not delete users or reset points.

The old API returns `404` for `/api/v1/subscriptions/status`. Updating a RevenueCat key or restarting that old container cannot add the missing routes. Pull the published code and rebuild the API image.

## 1. Pull the code

```bash
cd /opt/abu3meer
```

```bash
git status --short
```

If tracked files have changes, stop and resolve them first. Do not use `git reset --hard` or overwrite the server's `.env`.

```bash
git fetch origin agent/production-backend
```

```bash
git merge --ff-only origin/agent/production-backend
```

```bash
git ls-files server/src/routes/subscriptionRoutes.ts server/migrations/041_revenuecat_subscriptions.sql server/src/services/youtubeProfileResolver.ts
```

All three paths must appear. If any is missing, stop: the required code has not been pulled.

## 2. Back up the current database

```bash
cd /opt/abu3meer/server
```

```bash
sudo install -d -m 700 -o abu3meer -g abu3meer /opt/abu3meer-backups
```

```bash
backup_file="/opt/abu3meer-backups/pre-membership-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

```bash
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup_file"
```

Continue only if the dump command succeeds. Confirm the file is nonempty:

```bash
test -s "$backup_file"
```

```bash
ls -lh "$backup_file"
```

## 3. Check the existing environment file privately

```bash
nano .env
```

Keep the new `REVENUECAT_SECRET_API_KEY=sk_…` already entered. It must be a RevenueCat REST API v1 server key, not a public `appl_` SDK key. Do not paste it into chat or GitHub.

For this intentional pre-release simulator/TestFlight test deployment, add or change:

```dotenv
REVENUECAT_ALLOW_SANDBOX=true
```

This explicitly permits server-verified test subscriptions to grant test access and badges. Leave it `false` on a paid production deployment unless you intentionally support sandbox access there. It does not grant subscriptions by itself: RevenueCat must confirm the `abu_3meer_pro` entitlement for the signed-in app account.

Keep `REVENUECAT_WEBHOOK_AUTHORIZATION` if already configured. RevenueCat's webhook URL is `https://api.abu3meer.com/api/v1/subscriptions/webhook`; its Authorization value must match that separate secret.

No Google OAuth client ID/secret is required for manual YouTube membership checking. The new server resolves a public `@handle` profile link and compares its stable channel ID with the uploaded CSV. `YOUTUBE_API_KEY` is optional for public channel resolution; without it, the resolver uses bounded public YouTube page metadata. If YouTube is unavailable or blocks the lookup, the app reports a temporary lookup problem instead of pretending the user is not a member.

Save in nano with **Ctrl+O**, **Enter**, then **Ctrl+X**.

## 4. Rebuild and recreate only the API

```bash
docker compose config -q
```

```bash
docker compose build api
```

```bash
docker compose up -d --no-deps --force-recreate api
```

The API runs its pending migrations on startup, including the manual membership and RevenueCat tables. Do not run `docker compose down -v`; that would remove persistent data.

```bash
docker compose logs --tail=80 api
```

Review locally for startup or migration errors. Do not share unredacted logs if they contain credentials or account information.

## 5. Verify the route and then the app

```bash
curl -sS https://api.abu3meer.com/ready
```

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://api.abu3meer.com/api/v1/subscriptions/status
```

Expect readiness to be healthy and the second command to print **401**, not **404**. A 401 is correct here because curl has no user sign-in; it proves the new authenticated route exists. This alone does not prove a subscription is active.

In the updated app, sign into the account used for the purchase and tap **Refresh access**. If Apple says you are subscribed but RevenueCat has no subscription for this app account, use **Restore purchases** once; do not buy it again. An Xcode `[Environment: Xcode]` alert is a local test-store result, not proof that the live backend has verified this user.

A successful authenticated sync must return `data.isActive: true`, and the refreshed profile must return `user.isProSubscriber: true`. The green badge then appears in the profile and refreshed leaderboards. If verification still fails, check that RevenueCat uses the app's PostgreSQL user ID, the product grants `abu_3meer_pro`, and test access is permitted. Do not manually change database membership flags to hide a verification failure.
