# YouTube membership: CSV + staff-approved channel claims

ABU 3MEER does not use Google/YouTube OAuth for membership verification. The
only authority for current paid membership is the latest complete YouTube
Studio members export uploaded as UTF-8 CSV or TSV.

## User flow

1. A signed-in user submits either a stable `UC…` channel ID or the exact
   `https://www.youtube.com/channel/UC…` URL.
2. This creates an **untrusted pending claim**. It grants no role, multiplier,
   or member-only access.
3. A moderator, administrator, or super administrator independently verifies
   that the app user controls that channel and records an approval reason.
4. The server approves only when the exact channel ID is active in the latest
   unexpired complete CSV snapshot and is not approved for another user.
5. Approval, the unique account link, member role, and audit record commit in
   one database transaction.

If the channel disappears from the next full export, or the snapshot expires,
membership benefits fail closed to x1. A later current full export containing
the already-approved channel can make it active again.

## Server configuration

Only these YouTube values are used:

```dotenv
YOUTUBE_CREATOR_CHANNEL_ID=UCtetMtDxaZv1Fun1Ff85h4w
YOUTUBE_MEMBERSHIP_SNAPSHOT_MAX_AGE_HOURS=168
```

The channel ID is public and is used for latest-video discovery. There is no
OAuth client ID, client secret, redirect URI, creator refresh token, or token
encryption key.

## Operational rule

Every upload must be a complete current export, never a partial list. The
server stores minimized channel/lifecycle fields, not the raw uploaded file or
member display names. Upload a new full export at least weekly when the default
168-hour lifetime is used.
