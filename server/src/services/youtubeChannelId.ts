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

export type YouTubeProfileReference =
  | { kind: 'channel'; value: string; path: string }
  | { kind: 'handle' | 'user' | 'custom'; value: string; path: string };

/** Validate first; outbound requests are rebuilt on www.youtube.com, never this URL. */
export function parseYouTubeProfileReference(value: string): YouTubeProfileReference | null {
  const candidate = value.trim();
  if (youtubeChannelIdPattern.test(candidate)) {
    return { kind: 'channel', value: candidate, path: `/channel/${candidate}` };
  }
  if (candidate.length > 2048 || candidate.includes('\\')) return null;
  let parsed: URL;
  try { parsed = new URL(candidate); } catch { return null; }
  if (parsed.protocol !== 'https:' ||
      !allowedYouTubeHosts.has(parsed.hostname.toLowerCase()) ||
      parsed.username || parsed.password || parsed.port ||
      !/^https:\/\/(?:www\.|m\.)?youtube\.com\//i.test(candidate)) return null;
  let profilePath: string;
  try { profilePath = decodeURIComponent(parsed.pathname); } catch { return null; }
  const stable = profilePath.match(/^\/channel\/(UC[A-Za-z0-9_-]{22})\/?$/);
  if (stable) return { kind: 'channel', value: stable[1], path: `/channel/${stable[1]}` };
  const named = profilePath.match(/^\/(?:@([^/]+)|(user|c)\/([^/]+))\/?$/u);
  const name = named?.[1] ?? named?.[3];
  // Permit Unicode handles, but not path delimiters, escapes or invisible whitespace.
  if (!name || name.length > 100 || /[\s\u0000-\u001f\u007f/@?#%\\]/u.test(name) ||
      name === '.' || name === '..') return null;
  const kind = named?.[1] ? 'handle' : named?.[2] === 'user' ? 'user' : 'custom';
  const prefix = kind === 'handle' ? '/@' : kind === 'user' ? '/user/' : '/c/';
  return { kind, value: name, path: `${prefix}${encodeURIComponent(name)}` };
}

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
    !allowedYouTubeHosts.has(parsed.hostname.toLowerCase()) ||
    parsed.username !== '' ||
    parsed.password !== '' ||
    parsed.port !== ''
  ) {
    return null;
  }
  const channelPath = /^\/channel\/(UC[A-Za-z0-9_-]{22})\/?$/;
  return parsed.pathname.match(channelPath)?.[1] ?? null;
}
