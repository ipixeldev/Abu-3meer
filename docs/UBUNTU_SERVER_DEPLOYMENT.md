# Abu 3meer Ubuntu production deployment

This runbook moves the self-hosted Abu 3meer API from Docker Desktop to a
dedicated Ubuntu Server while preserving PostgreSQL data, Redis/BullMQ state,
uploaded images, Firebase authentication/push delivery, API-Football caching,
and the existing `api.abu3meer.com` Cloudflare Tunnel hostname.

The active Firebase project is `abu-3meer-9fd70`. The native application ID is
`com.abu3meer.app` on Android and iOS.

## 1. What is stored where

| Data | Current storage | Migration/backup requirement |
| --- | --- | --- |
| Users, roles, predictions, points, FCM tokens | PostgreSQL `pgdata` volume | Logical PostgreSQL dump and restore |
| BullMQ jobs, API-Football cache/quota state | Redis `redisdata` volume | Copy for an exact cutover; it can be omitted only when all queues are empty |
| Avatars and admin-uploaded images | `mediauploads` volume | Copy and back up separately |
| Application code | Git repository | Clone the exact deployed commit, including submodules |
| API/Firebase/Cloudflare credentials | `server/.env` | Transfer separately over SSH; never commit it |
| Cloudflare routing | Cloudflare account | Reuse the existing tunnel and token; do not recreate DNS |
| Android/iOS Firebase client config | Tracked platform config files | These identify the app but are not Firebase Admin credentials |

The API runs migrations automatically before it starts listening. PostgreSQL,
Redis, and uploads are persistent Docker volumes. Nothing under `build/`,
`node_modules/`, or a local Flutter SDK needs to be copied to Ubuntu.

## 2. Server sizing and network

Start with at least 2 vCPU, 4 GB RAM, and 40 GB of SSD storage. The checked-in
defaults use 512 MB for PostgreSQL shared buffers and 512 MB for Redis. Increase
them only after measuring memory pressure. For an 8-16 GB host, tune the
`POSTGRES_*` and `REDIS_MAXMEMORY` values in `.env`; do not restore the former
hard-coded 4 GB PostgreSQL buffer on a small server.

Only SSH needs an inbound firewall rule. The API binds to `127.0.0.1:3001`, and
PostgreSQL/Redis are not published to the host. Cloudflare Tunnel makes outbound
connections on UDP/TCP 7844 with TCP 443 fallback. Do not open ports 3001, 5432,
6379, or 6432 publicly.

## 3. Prepare Git and the Ubuntu host

The Flutter app has a path dependency at `packages/liquid_glass_widgets`. It is
declared as a Git submodule, so clone recursively. The deployment branch for
this release is `agent/production-backend`:

```bash
sudo mkdir -p /opt/abu3meer
sudo chown "$USER:$USER" /opt/abu3meer
git clone --recurse-submodules --branch agent/production-backend git@github.com:ipixeldev/Abu-3meer.git /opt/abu3meer
cd /opt/abu3meer
git submodule update --init --recursive
```

For a private repository, add a read-only GitHub deploy key to the Ubuntu
account before cloning. Do not put a personal access token in a clone URL or
shell history.

Provision Ubuntu from the repository. This installs Docker from Docker's apt
repository, enables UFW/fail2ban/security updates, and creates the
`abu3meer-backend.service` systemd unit:

```bash
cd /opt/abu3meer/server
sudo bash scripts/setup_ubuntu_server.sh
```

Log out and back in once so Docker group membership applies, then verify:

```bash
docker version
docker compose version
sudo ufw status verbose
```

## 4. Transfer production secrets safely

The easiest and least error-prone migration is to copy the already-working
`server/.env` through SSH, then lock down its permissions. From the Mac:

```bash
SOURCE_CHECKOUT="/path/to/Abu3meer Demo"
scp "$SOURCE_CHECKOUT/server/.env" SERVER_USER@SERVER_IP:/tmp/abu3meer.env
```

On Ubuntu:

```bash
sudo install -o "$USER" -g "$USER" -m 600 /tmp/abu3meer.env /opt/abu3meer/server/.env
rm -f /tmp/abu3meer.env
cd /opt/abu3meer/server
```

Open `.env` locally on the server and verify these names without printing their
values into logs or chat:

```text
POSTGRES_PASSWORD
REDIS_PASSWORD
FIREBASE_PROJECT_ID=abu-3meer-9fd70
FIREBASE_CLIENT_EMAIL
FIREBASE_PRIVATE_KEY
ADMIN_EMAILS
CLOUDFLARE_TUNNEL_TOKEN
API_FOOTBALL_API_KEY
API_FOOTBALL_DAILY_REQUEST_BUDGET=140000
YOUTUBE_CREATOR_CHANNEL_ID
YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS=168
BACKUP_ENCRYPTION_KEY
```

Move the 32-character API-Football key to `API_FOOTBALL_API_KEY` and leave
`SPORTSDB_API_KEY=123` for the public fallback. `FIREBASE_PRIVATE_KEY` must be
one quoted line containing literal `\n` separators, exactly as in the service
account JSON. Do not copy the `*.json` Admin key into the Git checkout.

Generate new database/cache/encryption secrets when starting fresh:

```bash
openssl rand -hex 32
openssl rand -hex 32
openssl rand -base64 48
```

Store the backup encryption key in a password manager as well as `.env`; an R2
backup cannot be decrypted without it. Before starting containers, reject
placeholders and validate Compose without rendering secrets:

```bash
if grep -Eq 'change_me|paste_|generate_.*_here|replace_with_' .env; then
  echo 'Replace every placeholder in server/.env before production.'
  exit 1
fi
test "$(stat -c %a .env)" = 600
docker compose --profile production config --quiet
```

YouTube membership does not use Google OAuth credentials. Configure only the
public creator channel ID for latest-video discovery and the CSV snapshot age.
Follow [YOUTUBE_MEMBERSHIP_CSV_CLAIMS.md](YOUTUBE_MEMBERSHIP_CSV_CLAIMS.md) for
the staff-approved claim and complete-export workflow.

## 5. Make the existing tunnel Linux-compatible

This stack uses a remotely managed, token-based Cloudflare Tunnel. In
Cloudflare Zero Trust, open **Networks > Tunnels > abu3meer-home > Routes /
Published application**, edit `api.abu3meer.com`, and set its service URL to:

```text
http://api:3000
```

Do this while the Mac stack is still running and confirm the public health
check remains `200`. Both the Mac and Ubuntu Compose stacks put `cloudflared`
and the service named `api` on the same `internal-net`, so this origin works on
both. `host.docker.internal:3001` is Docker Desktop-specific and must not remain
in the production route.

Do not delete or replace the existing proxied Tunnel DNS record and do not
rotate the token during migration. Multiple replicas may connect with the same
tunnel token; Cloudflare gives each process its own connector ID.

## 6. Prepare the destination without public traffic

Start only the private services on Ubuntu. Do not start `cloudflared` yet:

```bash
cd /opt/abu3meer/server
docker compose up -d postgres redis uploads-init pgbouncer
docker compose up -d --build api
docker compose ps
curl --fail --show-error http://127.0.0.1:3001/ready
```

The initial empty API boot applies all SQL migrations. Stop it before restoring
the production snapshot:

```bash
docker compose stop api redis
```

## 7. Create the final snapshot on the Mac

This architecture uses a local PostgreSQL instance, so a fully consistent
cutover requires a short maintenance window. Stop the old public connector and
API before the final dump. Do not run both independent databases behind the
same hostname while users can write.

On the Mac:

```bash
SOURCE_CHECKOUT="/path/to/Abu3meer Demo"
cd "$SOURCE_CHECKOUT/server"
mkdir -p transfer
chmod 700 transfer
docker compose --profile production stop cloudflared api
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists' | gzip -9 > transfer/abu3meer-db.sql.gz
docker compose stop redis
docker compose run --rm --no-deps -T api sh -c 'tar -C /app/uploads -czf - .' > transfer/abu3meer-uploads.tar.gz
docker compose run --rm --no-deps -T redis sh -c 'tar -C /data -czf - .' > transfer/abu3meer-redis.tar.gz
shasum -a 256 transfer/*
```

Copy the three archives to Ubuntu:

```bash
scp transfer/abu3meer-db.sql.gz transfer/abu3meer-uploads.tar.gz transfer/abu3meer-redis.tar.gz SERVER_USER@SERVER_IP:/tmp/
```

## 8. Restore on Ubuntu

Verify the checksums against the Mac, then restore while the API and Redis are
stopped:

```bash
cd /opt/abu3meer/server
sha256sum /tmp/abu3meer-*.gz
gunzip -c /tmp/abu3meer-db.sql.gz | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose run --rm --no-deps -T api sh -c 'tar -xzf - -C /app/uploads' < /tmp/abu3meer-uploads.tar.gz
docker compose run --rm --no-deps -T redis sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf {} +; tar -xzf - -C /data' < /tmp/abu3meer-redis.tar.gz
docker compose run --rm --no-deps uploads-init
rm -f /tmp/abu3meer-db.sql.gz /tmp/abu3meer-uploads.tar.gz /tmp/abu3meer-redis.tar.gz
```

Start Redis and the API, then verify the private origin before exposing it:

```bash
docker compose up -d redis pgbouncer
docker compose up -d --build api
docker compose ps
docker compose logs --tail=100 api
curl --fail --show-error http://127.0.0.1:3001/ready
curl --fail --show-error http://127.0.0.1:3001/api/v1/football/matches/week?days=7
```

The health response must say database and Redis are connected and push
notifications are configured.

## 9. Cut Cloudflare over

Start the existing tunnel on Ubuntu:

```bash
docker compose --profile production up -d cloudflared
docker compose --profile production ps
docker compose logs --tail=100 cloudflared
docker run --rm --network server_internal-net curlimages/curl:8.12.1 --fail --show-error http://api:3000/ready
curl --fail --show-error https://api.abu3meer.com/ready
curl --fail --show-error 'https://api.abu3meer.com/api/v1/football/matches/week?days=7'
```

The public response should contain `server: cloudflare`, return `200`, and show
real fixtures. The Cloudflare dashboard should show an Ubuntu connector for
`abu3meer-home`. Once verified, leave the old Mac API/tunnel stopped.

Enable the checked-in boot service:

```bash
sudo systemctl enable --now abu3meer-backend
sudo systemctl status abu3meer-backend --no-pager
```

Rollback before accepting new writes is simple: stop the Ubuntu `cloudflared`
and API, then start the Mac API and tunnel again. If Ubuntu has already accepted
user writes, take a new Ubuntu database/uploads snapshot before any rollback;
blindly restarting the old database would lose those writes.

## 10. Automated encrypted backups

The `backup` service is deliberately behind the `backup` Compose profile. It
will refuse to run unless the R2 account, R2 key pair, bucket, and encryption
passphrase are configured. It creates encrypted PostgreSQL and media archives;
Redis is intentionally excluded from scheduled backups because caches can be
rebuilt and durable campaign status is in PostgreSQL.

Create an R2 bucket such as `abu3meer-backups` and an R2 API token scoped only
to Object Read/Write for that bucket. Set these in `.env`:

```text
R2_ACCOUNT_ID
R2_ACCESS_KEY_ID
R2_SECRET_ACCESS_KEY
R2_BACKUP_BUCKET=abu3meer-backups
BACKUP_ENCRYPTION_KEY
```

Start it and force one test backup:

```bash
docker compose --profile backup up -d backup
docker compose --profile backup exec backup /run_backup.sh
docker compose logs --tail=100 backup
```

The job runs daily at 03:00 server time and uploads to `db_backups/` and
`media_backups/`. Configure an R2 lifecycle policy (for example, retain daily
objects for 30-90 days), enable R2 audit visibility, and perform a restore drill
at least monthly. To recreate the optional backup container after a reboot,
either run the profile command above or add `--profile backup` to the systemd
unit's `ExecStart` after the R2 variables have been configured.

Example encrypted database restore:

```bash
gpg --batch --decrypt abu3meer_db_TIMESTAMP.sql.gz.enc | gunzip | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

Example encrypted media restore:

```bash
gpg --batch --decrypt abu3meer_uploads_TIMESTAMP.tar.gz.enc | docker compose run --rm --no-deps -T api sh -c 'tar -xzf - -C /app/uploads'
docker compose run --rm --no-deps uploads-init
```

## 11. Firebase Cloud Messaging setup

### Server credential

In Firebase Console for `abu-3meer-9fd70`, open **Project settings > Service
accounts > Firebase Admin SDK > Generate new private key**. The server uses the
JSON `project_id`, `client_email`, and `private_key` fields through the three
`FIREBASE_*` environment variables. Treat this key as a root-level server
credential: keep it out of Git, device builds, screenshots, and chat. If it is
ever exposed, disable/delete that service-account key in Google Cloud IAM and
generate a replacement.

Also verify **Project settings > Cloud Messaging > Firebase Cloud Messaging API
(HTTP v1)** is enabled. Official references:

- <https://firebase.google.com/docs/admin/setup>
- <https://firebase.google.com/docs/cloud-messaging/send/admin-sdk>

### Android

1. Keep the Firebase Android app package as `com.abu3meer.app`.
2. Keep the current new-project `android/app/google-services.json` in the app.
3. Install on a physical device or emulator with Google Play services.
4. Android 13+ users must allow the notification permission when prompted.

SHA fingerprints are needed for Google Sign-In, not for delivery of ordinary
FCM notifications. They should nevertheless remain configured for the debug
and release signing keys used by this app.

### iOS

1. In Apple Developer, enable Push Notifications for the App ID
   `com.abu3meer.app`.
2. Under **Certificates, Identifiers & Profiles > Keys**, create an APNs key,
   enable Apple Push Notifications service, and download the `.p8` file. Apple
   permits downloading it only once.
3. In Firebase Console, open **Project settings > Cloud Messaging**, select the
   iOS app, and upload the APNs authentication key with its Key ID and Apple
   Team ID (`P9X53J2SQX` for the current Xcode project).
4. In Xcode, keep **Push Notifications** and **Background Modes > Remote
   notifications** enabled. The repository already declares both capabilities.
5. A development-signed build receives the APNs sandbox entitlement; a
   TestFlight/App Store build must be signed with a distribution profile and
   receive the production entitlement. The APNs token key uploaded to Firebase
   can serve both environments.

Firebase's Flutter setup reference is:
<https://firebase.google.com/docs/cloud-messaging/flutter/get-started>.

Never copy the APNs `.p8` file onto the Ubuntu application server. Firebase
stores and uses that key; the Ubuntu server talks to FCM with the Firebase Admin
service account.

### Register and test a real device

The app registers an FCM token only after the user signs in and grants
notification permission. On each Android/iPhone:

1. Install the freshly built app and sign in.
2. Open the avatar menu, then **Settings > Notification preferences**.
3. Enable a notification category and accept the OS prompt.
4. Press **SEND TEST NOTIFICATION**.

The test calls the authenticated backend endpoint, which sends a real FCM/APNs
message back to the registered device. Verify without printing token values:

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT platform, count(*) AS active_devices FROM devices WHERE is_active GROUP BY platform ORDER BY platform"'
docker compose logs --since=10m api | grep -E 'FCM|Notifications|notification'
```

Admin Studio broadcasts are inserted into `notification_campaigns`, queued in
BullMQ, split into batches of at most 500 recipients, and recorded in
`notification_deliveries`. Permanent invalid-token responses deactivate the
device row. A server showing `pushNotifications: configured` proves the Admin
credential is loaded; it does not prove APNs is uploaded or that a user has
allowed/registered a device, so always complete the real-device test.

### Current push feature boundary

The transport is implemented for device registration, preferences, a remote
test, and manual Admin Studio broadcasts. Automatic producers are not yet
implemented: nothing currently creates a campaign 15 minutes before kickoff or
automatically when a challenge, reward, or news post is published. Notification
tap payloads are exposed by `NotificationService.notificationTaps`, but that
stream is not yet connected to the app navigator, so tapping a message opens
the app without guaranteed deep-link routing. Add and test those two behaviors
before advertising automatic reminders or notification deep links.

## 12. Web Firebase configuration warning

Android and iOS point to `abu-3meer-9fd70`, but the web entry in
`lib/firebase_options.dart` still identifies the former `abu-3meer` project.
This does not affect the native apps or Ubuntu API. Before publishing the PWA,
register a Web app in the new Firebase project and regenerate all selected
platforms:

```bash
flutterfire configure --project=abu-3meer-9fd70 --platforms=web,android,ios
```

Review the resulting diff before committing so the working Android/iOS app IDs
remain unchanged.

## 13. Routine updates and rollback

Always back up before a deployment because startup may apply a new SQL
migration:

```bash
cd /opt/abu3meer
PREVIOUS_COMMIT=$(git rev-parse HEAD)
git fetch origin
git checkout agent/production-backend
git pull --ff-only
git submodule update --init --recursive
cd server
docker compose build api
docker compose --profile production up -d api cloudflared
curl --fail --show-error http://127.0.0.1:3001/ready
curl --fail --show-error https://api.abu3meer.com/ready
```

For a code rollback, check out `PREVIOUS_COMMIT`, update submodules, rebuild,
and recreate the API. Do not automatically roll the database schema backward;
SQL migrations must be designed to remain compatible with the previous app or
restored from a verified pre-deploy backup during a maintenance window.

Useful operational commands:

```bash
docker compose --profile production ps
docker compose logs --tail=200 api
docker compose logs --tail=200 cloudflared
docker stats --no-stream
docker system df
sudo journalctl -u abu3meer-backend -n 200 --no-pager
```

Set external uptime checks on `https://api.abu3meer.com/ready` and alert on any
non-200 response, zero healthy tunnel replicas, low disk space, failed backup
logs, PostgreSQL restart loops, or Redis `OOM` errors.

## 14. Secret-release checklist

Before pushing or deploying:

```bash
git check-ignore -v server/.env
git status --short
git diff --cached --name-only
find . -path './.git' -prune -o \( -name '*.p8' -o -name '*.p12' -o -name '*.mobileprovision' \) -print
```

Expected: `server/.env` is ignored, no tracked file contains a private key or
real tunnel token, and no APNs/signing file is in the checkout. Firebase client
files (`google-services.json`, `GoogleService-Info.plist`, and
`firebase_options.dart`) contain public client identifiers and are expected in
the app repository; they are not substitutes for the private Admin credential.
