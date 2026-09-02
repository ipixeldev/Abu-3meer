export const youtubeChannelIdPattern = /^UC[A-Za-z0-9_-]{22}$/;

export type YouTubeMembershipLookup = {
  isMember: boolean;
  channelId: string | null;
  membershipLevelId: string | null;
  memberSince: Date | null;
};

const allowedYouTubeHosts = new Set([
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
]);

/** Accept only a stable UC channel ID or an exact YouTube /channel/UC… URL. */
export function normalizeYouTubeChannelId(value: string): string | null {
  const candidate = value.trim();
  if (youtubeChannelIdPattern.test(candidate)) return candidate;

  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch (_) {
    return null;
  }
  if (
    parsed.protocol !== 'https:' ||
    !allowedYouTubeHosts.has(parsed.hostname.toLowerCase())
  ) {
    return null;
  }
  const segments = parsed.pathname.split('/').filter(Boolean);
  if (segments.length !== 2 || segments[0].toLowerCase() !== 'channel') {
    return null;
  }
  return youtubeChannelIdPattern.test(segments[1]) ? segments[1] : null;
}
