import {
  parseYouTubeProfileReference,
  youtubeChannelIdPattern,
  type YouTubeProfileReference,
} from './youtubeChannelId.js';

export class YouTubeProfileResolutionError extends Error {
  constructor(public readonly code: string, public readonly httpStatus: number, message: string) {
    super(message);
    this.name = 'YouTubeProfileResolutionError';
  }
}

const unavailable = () => new YouTubeProfileResolutionError(
  'youtube_profile_lookup_unavailable', 503,
  'YouTube could not resolve this profile right now. Please try again later, or use its /channel/UC… link. Your membership has not been changed.',
);
const notFound = () => new YouTubeProfileResolutionError(
  'youtube_profile_not_found', 400,
  'This YouTube profile could not be found. Check the channel profile link and try again.',
);

async function readBounded(response: Response, maximum: number): Promise<string> {
  if (Number(response.headers.get('content-length')) > maximum) {
    await response.body?.cancel();
    throw unavailable();
  }
  if (!response.body) throw unavailable();
  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      bytes += part.value.length;
      if (bytes > maximum) { await reader.cancel(); throw unavailable(); }
      parts.push(part.value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(parts).toString('utf8');
}

/** Only the page's channel metadata is trusted, never arbitrary video/recommendation IDs. */
export function channelIdFromYouTubeProfileHtml(html: string): string | null {
  // Meta/link text inside descriptions, scripts or body content is not a head
  // tag. Remove inert blocks before isolating the document's actual head.
  const markup = html
    .replace(/<(script|style|template)\b[^>]*>[\s\S]*?(?:<\/\1\s*>|$)/gi, '')
    .replace(/<!--[\s\S]*?(?:-->|$)/g, '');
  const head = markup.match(/<head\b[^>]*>([\s\S]*?)<\/head\s*>/i)?.[1] ?? '';
  for (const tag of head.matchAll(/<(?:link|meta)\b[^>]*>/gi)) {
    const attributes = new Map<string, string>();
    for (const attribute of tag[0].matchAll(/([\w:-]+)\s*=\s*(["'])(.*?)\2/gs)) {
      attributes.set(attribute[1].toLowerCase(), attribute[3]);
    }
    const channelId = attributes.get('content') ?? '';
    if (attributes.get('itemprop') === 'channelId' && youtubeChannelIdPattern.test(channelId)) {
      return channelId;
    }
    const canonical = attributes.get('rel') === 'canonical' ? attributes.get('href') :
      attributes.get('property') === 'og:url' ? attributes.get('content') : undefined;
    if (canonical) {
      const parsed = parseYouTubeProfileReference(canonical);
      if (parsed?.kind === 'channel') return parsed.value;
    }
  }
  for (const script of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)) {
    const contents = script[1];
    const marker = /(?:\b(?:var\s+)?ytInitialData|window\s*\[\s*["']ytInitialData["']\s*\])\s*=\s*\{/.exec(contents);
    if (!marker) continue;
    const start = marker.index + marker[0].length - 1;
    const data = initialDataObject(contents, start) as {
      metadata?: { channelMetadataRenderer?: { externalId?: unknown } };
    } | null;
    const channelId = data?.metadata?.channelMetadataRenderer?.externalId;
    if (typeof channelId === 'string' && youtubeChannelIdPattern.test(channelId)) return channelId;
  }
  return null;
}

function initialDataObject(contents: string, start: number): unknown {
  let depth = 0;
  let quoted = false;
  let escaped = false;
  for (let index = start; index < contents.length; index++) {
    const char = contents[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') quoted = false;
      continue;
    }
    if (char === '"') quoted = true;
    else if (char === '{') depth++;
    else if (char === '}' && --depth === 0) {
      try {
        return JSON.parse(contents.slice(start, index + 1));
      } catch { return null; }
    }
  }
  return null;
}

export async function resolveYouTubeProfileChannelId(value: string, options: {
  apiKey?: string;
  fetchImpl?: typeof fetch;
} = {}): Promise<string> {
  const profile = parseYouTubeProfileReference(value);
  if (!profile) throw new YouTubeProfileResolutionError(
    'youtube_profile_link_invalid', 400,
    'Paste a full YouTube channel profile link, such as https://youtube.com/@yourhandle or https://youtube.com/channel/UC…. Video links are not supported.',
  );
  if (profile.kind === 'channel') return profile.value;
  const request = options.fetchImpl ?? fetch;
  const apiKey = (options.apiKey ?? process.env.YOUTUBE_API_KEY ?? '').trim();
  const signal = AbortSignal.timeout(8000);
  try {
    if (apiKey && (profile.kind === 'handle' || profile.kind === 'user')) {
      const url = new URL('https://www.googleapis.com/youtube/v3/channels');
      url.searchParams.set('part', 'id');
      url.searchParams.set(profile.kind === 'handle' ? 'forHandle' : 'forUsername', profile.value);
      url.searchParams.set('key', apiKey);
      const response = await request(url, { signal, redirect: 'error' });
      if (response.ok) {
        const result = JSON.parse(await readBounded(response, 128_000)) as { items?: Array<{ id?: string }> };
        if (Array.isArray(result.items) && result.items.length === 0) throw notFound();
        if (result.items?.length === 1 && typeof result.items[0]?.id === 'string' &&
            youtubeChannelIdPattern.test(result.items[0].id)) return result.items[0].id;
        throw unavailable();
      }
      await response.body?.cancel();
      // Quota/key availability must not prevent the public-page fallback.
    }
    let current: YouTubeProfileReference = profile;
    for (let redirects = 0; redirects <= 2; redirects++) {
      const url = new URL(current.path, 'https://www.youtube.com');
      const response = await request(url, {
        signal, redirect: 'manual', headers: {
          Accept: 'text/html',
          'Accept-Language': 'en',
          // Anonymous, reject-optional-cookies preference. This is not an
          // account/auth cookie and avoids the regional consent interstitial.
          Cookie: 'SOCS=CAE',
        },
      });
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('location');
        await response.body?.cancel();
        if (!location) throw unavailable();
        const next = parseYouTubeProfileReference(new URL(location, url).href);
        if (!next) throw unavailable();
        if (next.kind === 'channel') return next.value;
        current = next;
        continue;
      }
      if (response.status === 404) { await response.body?.cancel(); throw notFound(); }
      if (!response.ok) { await response.body?.cancel(); throw unavailable(); }
      const channelId = channelIdFromYouTubeProfileHtml(await readBounded(response, 2_000_000));
      if (channelId) return channelId;
      throw unavailable();
    }
    throw unavailable();
  } catch (error) {
    if (error instanceof YouTubeProfileResolutionError) throw error;
    // Never return membership=false or expose request URLs/API keys on resolution failure.
    throw unavailable();
  }
}
