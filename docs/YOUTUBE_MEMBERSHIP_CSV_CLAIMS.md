# YouTube membership: profile link + current CSV

The latest complete YouTube Studio members export is the authority for YouTube
membership benefits. A signed-in user submits their YouTube channel profile
link; the server extracts its stable channel ID and compares it with that
export. This flow does not request Google sign-in or YouTube API access.

## User flow

1. A moderator, admin, or super admin uploads a complete current YouTube Studio
   members export as UTF-8 CSV or TSV.
2. A signed-in user taps **Check membership** and pastes their channel profile
   link, such as `https://www.youtube.com/channel/UC...`.
3. The app sends `POST /api/v1/profile/youtube/membership/check` with JSON
   `{"profileLink":"https://www.youtube.com/channel/UC..."}`, authenticated using
   the normal app session.
4. The server checks the exact stable ID against the active, unexpired CSV.
   A match activates the member role and eligible membership benefits in one
   transaction; a missing ID returns `not_in_snapshot`.
5. A channel already linked to another app account is rejected. New snapshots
   automatically refresh the status of saved links.

The server accepts HTTPS profile links on `youtube.com`, `www.youtube.com`,
or `m.youtube.com`, with an exact `/channel/UC...` path (and optional trailing
slash/share query). A bare stable UC channel ID is also accepted by the API.
It does not resolve `@handle`, `/c/`, or `/user/` links. For those, open YouTube
**Settings → Advanced settings**, copy **Channel ID**, and use the stable
`https://www.youtube.com/channel/CHANNEL_ID` URL. Display names are never matched.

## What a manual link proves

A public channel URL does not prove the app user owns that YouTube channel.
This product flow intentionally accepts self-declared links. It prevents a
channel being shared by multiple app accounts, but the first person to submit
someone else's unclaimed member link could receive those benefits. Support
must resolve ownership disputes before releasing an existing link.

Receipts therefore record `manual_profile_link` and
`ownershipVerified: false`; they never claim Google verified ownership.
Historically Google-verified links remain valid, and migration 040 does not
delete existing users, links, snapshots, or membership history.

## Snapshot freshness

If a channel disappears from the next full export, or the snapshot expires,
YouTube membership benefits stop. With the default 168-hour lifetime, upload a
new complete export at least weekly. Status is only as current as the latest
upload. A RevenueCat subscription, when present, is evaluated separately.

The server keeps channel IDs and minimized membership lifecycle data, not the
raw uploaded file or YouTube display names. Every upload must be a complete
current export, never a partial list.

## Server configuration

Only these YouTube values are stored in `server/.env`:

```dotenv
YOUTUBE_CREATOR_CHANNEL_ID=UCtetMtDxaZv1Fun1Ff85h4w
YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS=168
```

The creator channel ID is public and is used for latest-video discovery.
Membership checks need no Google OAuth client secret, YouTube API key, or
creator token. Google sign-in may still be used for normal app authentication;
do not delete its Firebase client configuration for this membership change.

Deploy the backend with migration
`040_manual_profile_membership.sql` before installing the matching mobile
build. Older clients submitting `accessToken` receive a validation error and
need the updated app.
