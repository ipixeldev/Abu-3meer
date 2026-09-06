# Deploy the membership, subscription-access, and support update

Run these commands on the Ubuntu production server, one block at a time. Stop
after an error. The procedure preserves users, points, subscription snapshots,
uploaded CSV files, and media.

This release adds backend behavior, including migration
`042_admin_subscription_access.sql`. An earlier rebuild that applied only
migrations 040/041 is not sufficient; the API image must be rebuilt and
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
git ls-files server/migrations/042_admin_subscription_access.sql server/src/routes/adminSubscriptionRoutes.ts server/src/routes/supportRoutes.ts
```

All three paths must appear. If one is missing, stop because the required
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

Keep public production accounts on production receipts while permitting only a
dedicated TestFlight/App Review account to prove Apple's sandbox purchase flow:

```dotenv
REVENUECAT_ALLOW_SANDBOX=false
REVENUECAT_SANDBOX_ALLOWED_USER_IDS=<dedicated-review-app-account-postgresql-uuid>
```

Use a comma-separated list only if there is more than one dedicated reviewer
account. Values must be PostgreSQL `users.id` UUIDs. Emails, usernames, Apple
IDs, Firebase UIDs, and RevenueCat keys are not accepted. The server queries
RevenueCat production first and uses the sandbox lookup only for an exact
allowlisted UUID with no active production entitlement. Do not set the global
switch to `true` on the public deployment.

To find a dedicated review account's UUID without exposing its login password,
replace `REVIEW_USERNAME` in this read-only command:

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT id, username FROM users WHERE normalized_username = lower(\$\$REVIEW_USERNAME\$\$);"'
```

Configure the same exact UUID manually in RevenueCat under **Sandbox Testing
Access → Allowed App User IDs only**. Both sides are required: the server
allowlist controls Abu 3meer's protected access, while RevenueCat's setting
controls which SDK App User IDs may receive sandbox entitlements.

Keep the existing webhook secret if it is configured:

```dotenv
REVENUECAT_WEBHOOK_AUTHORIZATION=<existing-random-authorization-value>
```

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
the log reports `042_admin_subscription_access.sql` as applied (or already
applied) and contains no startup error:

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
2. Sign into the exact dedicated review app account whose UUID is on both
   allowlists. Restore once if it already owns a sandbox subscription, then tap
   Refresh access. TestFlight and App Review purchases remain sandbox even with
   the production `appl_` key.
3. Sign into a normal, non-allowlisted account and confirm a sandbox receipt does
   not grant access.
4. In Admin Studio, an admin or super admin can open **Membership access** and
   choose **Activate access**, **Deactivate access**, or **Use store status**.
   A reason is required; an active grant may have a future expiry. Confirming
   this action changes only app access and the subscriber badge. It does not
   alter store billing or YouTube membership.
5. Tap WhatsApp support. With the number blank, confirm the app shows the support
   email. Once a real number is configured, confirm it opens that business chat.

## App Store boundary

The first subscriptions must be reviewed with an app version. The review draft
already contains the subscription group and both subscription versions. Build
1.1.0 (24) is valid, selected for the app version, and available to internal
TestFlight testers; current iPad screenshots are uploaded in English and Arabic.
The app version cannot be added to the review draft until the owner completes
App Privacy, reviewer contact details, copyright, and the content-rights
declaration. The current Digital Services Act status is also **In Review**.
These are App Store Connect owner/legal actions, not server deployment commands.

Do not submit Beta App Review, public App Review, or release the app without the
owner's explicit authorization after those items and the purchase-to-access
flow have been verified.
