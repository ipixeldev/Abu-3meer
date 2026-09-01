# YouTube membership CSV deployment

Abu 3meer does not call YouTube's restricted `members.list` endpoint and does
not store a channel-owner OAuth credential. A complete current-members export
from YouTube Studio is the only membership authority.

The stable YouTube channel ID from the export's `Link to profile` column is the
matching key. Display names are not retained or trusted because creators can
change them.

## 1. Google Cloud configuration

Use a **Web application** OAuth client in the Google Cloud project where the
YouTube Data API v3 is enabled.

- Authorized JavaScript origins: leave empty.
- Authorized redirect URI (exact, with no trailing slash):
  `https://api.abu3meer.com/api/v1/youtube/oauth/callback`
- User scopes requested by the backend:
  - `openid`
  - `https://www.googleapis.com/auth/youtube.readonly`
- Do not request
  `https://www.googleapis.com/auth/youtube.channel-memberships.creator`.

The read-only user authorization is used once to call
`channels.list(part=id&mine=true)`. This proves which channel ID is
owned by the Google identity already linked to the app account. The short-lived
Google access token is not stored.

## 2. Server-only environment

Keep these values in `/opt/abu3meer/server/.env`, mode `600`, and out of Git:

```dotenv
YOUTUBE_OAUTH_CLIENT_ID=replace_with_google_web_oauth_client_id
YOUTUBE_OAUTH_CLIENT_SECRET=replace_with_google_web_oauth_client_secret
YOUTUBE_OAUTH_REDIRECT_URI=https://api.abu3meer.com/api/v1/youtube/oauth/callback
YOUTUBE_CREATOR_CHANNEL_ID=replace_with_24_character_youtube_channel_id
YOUTUBE_TOKEN_ENCRYPTION_KEY=replace_with_32_byte_base64_key
YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS=21600
```

`YOUTUBE_TOKEN_ENCRYPTION_KEY` protects short-lived OAuth flow state/PKCE data;
it is not a creator-membership token. Generate it once with
`openssl rand -base64 32` and keep a recoverable secret backup.

## 3. Import a complete membership export

YouTube Studio exports these expected columns:

```text
Member
Link to profile
Current level
Total time on level (months)
Total time as member (months)
Last update
Last update timestamp
```

Export as UTF-8 CSV or TSV. Excel files are intentionally rejected. In the
app, a moderator, admin, or super admin can choose **Profile → Membership CSV**
and import the file. The app sends it as an authenticated multipart HTTPS
request to the API. The server parses it transactionally into PostgreSQL and
does not retain the raw file or YouTube display names.

Each import is a complete replacement:

- IDs present in the file are active and have their level, cumulative months,
  event timestamp, and last-seen time updated.
- New IDs become active.
- A previously lapsed ID that reappears becomes active again.
- Active IDs absent from the new file become lapsed. `left_at` is the import
  time because YouTube does not provide the exact cancellation time.

Never upload a partial list. A partial file would correctly be interpreted as
every omitted member having lapsed.

If a replacement contains no members or is more than 20% smaller than the
current snapshot, the server rejects the first attempt. The app then shows a
second destructive-change warning and requires staff to explicitly confirm
that the file is the complete current export.

## 4. User verification

The app user links Google, completes the read-only YouTube authorization, and
the backend resolves the owned channel ID. The backend then matches that ID to
the current CSV-derived member table. Active matches receive the configured 2×
XP multiplier; lapsed or absent IDs receive normal 1× XP.

Membership is only as current as the latest manual export. Upload a complete
fresh export at least weekly and show the last import time in the staff UI.

## 5. Deploy and validate

```bash
cd /opt/abu3meer/server
chmod 600 .env
docker compose --profile production config --quiet
docker compose build api
docker compose --profile production up -d api cloudflared
docker compose --profile production ps
curl --fail --show-error https://api.abu3meer.com/ready
```

The OAuth callback should return HTTP 400 when opened without a state/code;
that confirms the route exists without starting an OAuth flow:

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  https://api.abu3meer.com/api/v1/youtube/oauth/callback
```
