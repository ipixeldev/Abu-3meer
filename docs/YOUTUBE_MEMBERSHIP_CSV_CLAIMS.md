# YouTube membership: verified channel + current CSV

The latest complete YouTube Studio members export is the only authority for
current paid membership. Google authorization is used only when a signed-in
user taps **Check membership**, so the server can securely discover which
YouTube channel that user controls. Users never type or submit channel IDs.

## User flow

1. Staff uploads a complete current YouTube Studio members export as UTF-8 CSV
   or TSV.
2. A signed-in user taps **Check membership** and chooses the Google account
   that owns their YouTube channel.
3. The mobile app requests only
   `https://www.googleapis.com/auth/youtube.readonly` and sends the resulting
   short-lived access token to the authenticated Abu 3meer API request.
4. The server validates that the Google token belongs to the Google identity
   linked to the same Abu 3meer account, calls `channels.list(mine=true)`, and
   compares the returned stable `UC...` channel ID with the latest unexpired
   CSV snapshot.
5. A unique match activates the member role and eligible 2x XP multiplier in
   one transaction. No manual channel entry or staff approval is involved.

The Google access token is used only for that check and is never stored. The
server stores the verified channel ID and minimized membership lifecycle data,
not the raw uploaded file or YouTube display names.

If the channel disappears from the next full export, or the snapshot expires,
membership benefits fail closed to x1. The user can check again after staff
uploads a newer complete export.

## Google configuration

The iOS app uses its existing public Google Sign-In OAuth client. On that
client's Google Cloud project:

1. Enable **YouTube Data API v3**.
2. Add the `youtube.readonly` scope to Google Auth Platform > Data Access.
3. While the consent app is in Testing, add every TestFlight tester's Google
   account under Audience > Test users.
4. Complete Google's OAuth app verification before making this available to
   users who are not test users.

This is the normal read-only YouTube Data API. It does not use the private
creator-members list scope, the YouTube Partner API, a web redirect URI, a
server OAuth client secret, a creator refresh token, or a token-encryption key.

## Server configuration

Only these YouTube values are stored in `server/.env`:

```dotenv
YOUTUBE_CREATOR_CHANNEL_ID=UCtetMtDxaZv1Fun1Ff85h4w
YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS=168
```

The creator channel ID is public and is used for latest-video discovery.

## Operational rule

Every upload must be a complete current export, never a partial list. Upload a
new full export at least weekly when the default 168-hour lifetime is used.
