-- Temporary quick-tunnel hostnames expire even though the uploaded media
-- remains on the persistent API volume. Repoint legacy self-hosted avatars to
-- the stable Cloudflare Tunnel hostname so existing profiles render again.
UPDATE users
SET avatar_url = regexp_replace(
      avatar_url,
      '^https?://[^/]+\.trycloudflare\.com(/uploads/.*)$',
      'https://api.abu3meer.com\1'
    ),
    updated_at = CURRENT_TIMESTAMP
WHERE avatar_url ~* '^https?://[^/]+\.trycloudflare\.com/uploads/';
