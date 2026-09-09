# Deploy the membership, subscription-access, and support update

Run these commands on the Ubuntu production server, one block at a time. Stop
after an error. The procedure preserves users, points, subscription snapshots,
uploaded CSV files, and media.

This release adds backend behavior through migrations
`042_admin_subscription_access.sql`, `043_loyalty_points_rules.sql`,
`044_revenuecat_store_provenance.sql`, and
`045_user_moderation.sql`. Migration 045 adds user reports, blocking, and the
staff moderation queue required by build 31. An earlier rebuild that stopped
before any of these is not sufficient; the API image must be rebuilt and
recreated after the new revision is pulled.

## 1. Pull the published revision

```bash
cd /opt/abu3meer
```

```bash
git status --short
```

Stop if tracked files have edits. Preserve `.env` and the existing backup files;
do not use `git reset --hard` or overwrite them.

```bash
git fetch origin agent/production-backend
```

```bash
git merge --ff-only origin/agent/production-backend
```

```bash
git ls-files server/migrations/042_admin_subscription_access.sql server/migrations/043_loyalty_points_rules.sql server/migrations/044_revenuecat_store_provenance.sql server/migrations/045_user_moderation.sql server/src/routes/adminSubscriptionRoutes.ts server/src/routes/userModerationRoutes.ts server/src/routes/supportRoutes.ts
```

All seven paths must appear. If one is missing, stop because the required
revision was not pulled.

## 2. Back up PostgreSQL

```bash
cd /opt/abu3meer/server
```

```bash
sudo install -d -m 700 -o abu3meer -g abu3meer /opt/abu3meer-backups
```

```bash
backup_file="/opt/abu3meer-backups/pre-subscription-access-$(date -u +%Y%m%dT%H%M%SZ).dump"
```

```bash
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$backup_file"
```

Continue only when the dump succeeds and is nonempty:

```bash
test -s "$backup_file"
```

```bash
ls -lh "$backup_file"
```

## 3. Update the private environment file

```bash
nano .env
```

Keep the existing RevenueCat REST API v1 server credential:

```dotenv
REVENUECAT_SECRET_API_KEY=sk_...
```

The public `appl_` key belongs in the iOS client and must not replace this
server key. Never paste either key into logs, chat, or source control.

Keep synthetic RevenueCat Test Store access disabled while accepting genuine
Apple/Google store-signed test transactions:

```dotenv
REVENUECAT_ALLOW_SANDBOX=false
REVENUECAT_SANDBOX_ALLOWED_USER_IDS=
```

The server queries RevenueCat production first and checks sandbox only when no
active production entitlement exists. Sandbox rows whose persisted provider is
`app_store` or `play_store` grant test-track access and a badge automatically.
They remain visibly marked as test purchases. `test_store` and legacy rows with
no verified provider still require the global switch or an account UUID in the
optional allowlist; do not enable either on the public deployment unless that
synthetic access is intentional.

To find a dedicated review account's UUID without exposing its login password,
replace `REVIEW_USERNAME` in this read-only command:

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, username FROM users WHERE normalized_username = lower(\$\$REVIEW_USERNAME\$\$);"'
```

Only use that UUID command when intentionally allowing RevenueCat Test Store or
a legacy unknown-provider row. If RevenueCat's own sandbox-access setting is
restricted, its allowlist still controls which SDK App User IDs can receive a
sandbox entitlement.

The server compares the complete Authorization header exactly. Keep the
`Bearer ` prefix inside the environment value and use the identical complete
value in RevenueCat:

```dotenv
REVENUECAT_WEBHOOK_AUTHORIZATION="Bearer <random-authorization-value>"
```

If the previous value was copied into chat, a ticket, or a screenshot, rotate
it before release. Generate a replacement with `openssl rand -hex 32`, then
put `Bearer ` followed by that output in both the server value above and the
RevenueCat webhook's Authorization header value.

RevenueCat's webhook URL is
`https://api.abu3meer.com/api/v1/subscriptions/webhook`; its Authorization value
must match this separate secret.

WhatsApp support is optional and has safe blank-disable behavior:

```dotenv
SUPPORT_WHATSAPP_NUMBER=
```

Leave it blank until the business number is ready. To enable it, enter an
international number with country code using digits only, for example
`31612345678`; omit `+`, spaces, leading `00`, and a local trunk prefix. An
invalid or blank value produces no public WhatsApp URL, and the app directs the
user to the existing support email.

Save in nano with **Ctrl+O**, **Enter**, then **Ctrl+X**.

## 4. Validate, rebuild, and recreate the API

```bash
docker compose config -q
```

```bash
docker compose build api
```

```bash
docker compose up -d --no-deps --force-recreate --wait api
```

The API migration runner applies pending migrations at startup. Confirm that
the log reports migrations 042, 043, and 044 as applied (or already applied)
and contains no startup error:

```bash
docker compose logs --tail=120 api
```

Do not run `docker compose down -v`; it can remove persistent database data.

## 5. Read-only deployment checks

```bash
curl -fsS https://api.abu3meer.com/ready
```

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://api.abu3meer.com/api/v1/subscriptions/status
```

The first response should be healthy. The second should print `401`, not `404`:
curl is unauthenticated, so `401` confirms that the protected route exists but
does not prove that a subscription is active.

The support endpoint is public and never returns the raw environment value:

```bash
curl -fsS https://api.abu3meer.com/api/v1/support/contact
```

With a blank number, expect `{"data":{"whatsappUrl":null}}`. With a valid
number, expect an HTTPS `wa.me` URL.

Run the read-only per-account report when subscription access needs diagnosis:

```bash
docker compose exec -T api node --input-type=module - --username REVIEW_USERNAME < scripts/diagnose_subscriptions.mjs
```

This report does not fetch RevenueCat, make a purchase, change access, or print
keys. See [SUBSCRIPTION_PRODUCTION_DIAGNOSTICS.md](SUBSCRIPTION_PRODUCTION_DIAGNOSTICS.md).

## 6. Verify the application flows

1. Open **Members → View plans** on the current TestFlight build. A zero-product
   `RC-23` report is an Apple/RevenueCat catalog problem; rebuilding this backend
   alone cannot populate StoreKit products.
2. Sign into the TestFlight/Play test-track account. Restore once if it already
   owns a sandbox subscription, then tap **Refresh access**. Confirm the screen
   labels it as sandbox/test while member access and the badge are active.
3. If RevenueCat's sandbox-access setting is restricted, confirm the tester's
   PostgreSQL app-user UUID is allowed there. The server-side escape-hatch
   allowlist may remain blank for genuine App Store/Play Store receipts.
4. In Admin Studio, an admin or super admin can open **Membership access** and
   choose **Activate access**, **Deactivate access**, or **Use store status**.
   A reason is required; an active grant may have a future expiry. Confirming
   this action changes effective app access and the subscriber badge. It does
   not alter store billing or erase the underlying YouTube verification; an
   explicit inactive override nevertheless blocks member access until an admin
   chooses **Use store status** again.
5. Tap WhatsApp support. With the number blank, confirm the app shows the support
   email. Once a real number is configured, confirm it opens that business chat.

## App Store boundary

The first subscriptions must be reviewed with an app version. The review draft
already contains the subscription group and both subscription versions. The
current source and App Review candidate are 1.1.0 (31). Deploy the current
server revision, install build 31 from TestFlight, and complete the
physical-device checklist before submitting that build for review. The reviewed
build-31 English and Arabic iPhone/iPad screenshots are already uploaded; check
them against `APP_STORE_SCREENSHOT_PLAN.md` before submission.
App Privacy, reviewer contact details, the private demo login, copyright, and
the third-party content declaration are filled. The existing review submission
still has one rejected app-version item while the subscription items remain
ready. Add the build-31 video/review response, identify the applicable content
rights, complete physical-device QA, and resolve that existing item before
resubmitting. The current Digital Services Act status is also **In Review**.
These are App Store Connect owner/legal actions, not server deployment commands.

Do not submit Beta App Review, public App Review, or release the app without the
owner's explicit authorization after those items and the purchase-to-access
flow have been verified.
