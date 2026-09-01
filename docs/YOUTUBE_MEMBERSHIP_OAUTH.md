# YouTube membership OAuth deployment

This integration verifies a user's active Abu 3meer channel membership by
YouTube channel ID. Both the channel owner's refresh token and all Google OAuth
credentials remain on the backend; none belong in Flutter, an APK, or an IPA.

Access to YouTube's channel-membership endpoints is separately controlled by
Google/YouTube. A valid OAuth client does not by itself guarantee that
`members.list` is enabled for the creator channel.

## 1. Google Cloud configuration

Use the Google Cloud project where **YouTube Data API v3** is enabled. The OAuth
client type must be **Web application**.

- Authorized JavaScript origins: leave empty.
- Authorized redirect URI (exact, with no trailing slash):
  `https://api.abu3meer.com/api/v1/youtube/oauth/callback`
- Creator scope:
  `https://www.googleapis.com/auth/youtube.channel-memberships.creator`
- User-link scope: the minimum read-only YouTube scope requested by the backend.

The shared callback distinguishes creator and user authorization with
server-generated, short-lived OAuth state. Never add a second callback path or
put a Firebase token, Google code, OAuth state, or refresh token in a log.

## 2. Server-only environment

Set these in `/opt/abu3meer/server/.env`, which must remain mode `600` and
ignored by Git:

```dotenv
YOUTUBE_OAUTH_CLIENT_ID=replace_with_google_web_oauth_client_id
YOUTUBE_OAUTH_CLIENT_SECRET=replace_with_google_web_oauth_client_secret
YOUTUBE_OAUTH_REDIRECT_URI=https://api.abu3meer.com/api/v1/youtube/oauth/callback
YOUTUBE_CREATOR_CHANNEL_ID=replace_with_24_character_youtube_channel_id
YOUTUBE_TOKEN_ENCRYPTION_KEY=replace_with_32_byte_base64_key
YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS=21600
```

Generate the encryption key once and save it in the server's secret manager or
password manager as well as `.env`:

```bash
umask 077
openssl rand -base64 32
```

Do not rotate this key casually: stored creator tokens must be re-encrypted as
part of a planned rotation. The refresh interval accepts 900 through 86400
seconds; six hours is the default.

## 3. Validate and deploy without printing secrets

`config --quiet` validates interpolation without rendering secret values:

```bash
cd /opt/abu3meer/server
chmod 600 .env
docker compose --profile production config --quiet
docker compose build api
docker compose --profile production up -d api cloudflared
docker compose --profile production ps
curl --fail --show-error https://api.abu3meer.com/ready
```

Inspect only the safe configuration status (variable names and reasons, never
values):

```bash
docker compose exec -T api node --input-type=module -e \
  "const {config}=await import('./dist/config.js'); console.log(JSON.stringify(config.youtubeOAuth.status)); process.exit(config.youtubeOAuth.configured?0:1)"
```

Expected after configuration:

```json
{"state":"configured","issues":[]}
```

Confirm the public callback exists without initiating OAuth. A `400` response
for missing state/code is expected; `404` is not:

```bash
curl --silent --output /dev/null --write-out '%{http_code}\n' \
  https://api.abu3meer.com/api/v1/youtube/oauth/callback
```

## 4. Authorize the Abu 3meer creator account

Every start/status endpoint requires a current Firebase bearer token with the
required admin role. Keep the token in a temporary shell variable and unset it
when finished; never paste it into chat or a committed script.

```bash
read -r -s -p 'Temporary admin Firebase ID token: ' ADMIN_ID_TOKEN
echo
CREATOR_START="$(curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $ADMIN_ID_TOKEN" \
  https://api.abu3meer.com/api/v1/admin/youtube/creator/connect/start)"
CREATOR_FLOW_ID="$(printf '%s' "$CREATOR_START" | jq -r '.flowId')"
printf '%s' "$CREATOR_START" | jq -r '.authorizationUrl'
```

Open the printed URL only in the trusted browser where the Abu 3meer channel
owner is signed in. Approve the requested membership scope, then poll the
one-time flow status without replaying the callback:

```bash
curl --fail --silent --show-error \
  --header "Authorization: Bearer $ADMIN_ID_TOKEN" \
  "https://api.abu3meer.com/api/v1/admin/youtube/creator/connect/$CREATOR_FLOW_ID/status" \
  | jq .

curl --fail --silent --show-error \
  --header "Authorization: Bearer $ADMIN_ID_TOKEN" \
  https://api.abu3meer.com/api/v1/admin/youtube/creator/status \
  | jq .

unset CREATOR_START CREATOR_FLOW_ID ADMIN_ID_TOKEN
```

The status response may report connection state, channel identity, and refresh
time. It must never return Google access tokens, refresh tokens, the client
secret, or the local encryption key.

## 5. Smoke-test one user's channel link

Use a short-lived Firebase ID token for a dedicated test account. Authorize the
Google account that owns that user's intended YouTube channel (including the
correct Brand Account identity, if applicable):

```bash
read -r -s -p 'Temporary test-user Firebase ID token: ' USER_ID_TOKEN
echo
USER_START="$(curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $USER_ID_TOKEN" \
  https://api.abu3meer.com/api/v1/profile/youtube/connect/start)"
USER_FLOW_ID="$(printf '%s' "$USER_START" | jq -r '.flowId')"
printf '%s' "$USER_START" | jq -r '.authorizationUrl'
```

Complete Google authorization in a trusted browser, then poll:

```bash
curl --fail --silent --show-error \
  --header "Authorization: Bearer $USER_ID_TOKEN" \
  "https://api.abu3meer.com/api/v1/profile/youtube/connect/$USER_FLOW_ID/status" \
  | jq .

unset USER_START USER_FLOW_ID USER_ID_TOKEN
```

Test both an active channel member and a non-member. Verify the backend stores
only the linked YouTube channel identity and derived membership state for the
app user. Membership refresh failures must preserve the last verified state
only according to the backend's expiry policy; they must never grant membership
merely because Google is temporarily unavailable.
