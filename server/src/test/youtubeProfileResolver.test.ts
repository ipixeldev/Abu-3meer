import assert from 'node:assert/strict';
import test from 'node:test';
import { parseYouTubeProfileReference } from '../services/youtubeChannelId.js';
import {
  channelIdFromYouTubeProfileHtml,
  resolveYouTubeProfileChannelId,
  YouTubeProfileResolutionError,
} from '../services/youtubeProfileResolver.js';

const channelId = `UC${'a'.repeat(22)}`;
const html = `<html><head><meta property="og:url" content="https://www.youtube.com/channel/${channelId}"></head></html>`;

test('accepts handles, Unicode, channel and legacy profile links with share parameters', () => {
  for (const [link, kind] of [
    [`https://youtube.com/channel/${channelId}?si=share`, 'channel'],
    ['https://youtube.com/@aeyaall', 'handle'],
    ['https://m.youtube.com/@أبو_عمير/?si=share', 'handle'],
    ['https://www.youtube.com/c/CreatorName', 'custom'],
    ['https://www.youtube.com/user/CreatorName/', 'user'],
  ]) assert.equal(parseYouTubeProfileReference(link)?.kind, kind, link);
});

test('rejects impostors, credentials, ports, video links and encoded path/control characters', () => {
  for (const link of [
    'https://youtube.com.evil.test/@name', 'https://127.0.0.1/@name',
    'https://attacker@youtube.com/@name', 'https://youtube.com:443/@name',
    'https://youtube.com/@name/videos', 'https://youtu.be/name',
    'https://youtube.com/watch?v=name', 'https://youtube.com/@',
    'https://youtube.com/@name%2Fwatch', 'https://youtube.com/@name%0A',
    'https://youtube.com/@name%ZZ', 'http://youtube.com/@name',
  ]) assert.equal(parseYouTubeProfileReference(link), null, link);
});

test('stable IDs never make an outbound request', async () => {
  assert.equal(await resolveYouTubeProfileChannelId(`https://youtube.com/channel/${channelId}`, {
    fetchImpl: async () => { throw new Error('must not fetch'); },
  }), channelId);
});

test('public API uses forHandle, no OAuth and returns the stable ID', async () => {
  const id = await resolveYouTubeProfileChannelId('https://youtube.com/@aeyaall?si=share', {
    apiKey: 'public-test-key',
    fetchImpl: async (input, init) => {
      const url = new URL(String(input));
      assert.equal(url.origin + url.pathname, 'https://www.googleapis.com/youtube/v3/channels');
      assert.equal(url.searchParams.get('forHandle'), 'aeyaall');
      assert.equal(url.searchParams.get('part'), 'id');
      assert.equal(init?.redirect, 'error');
      assert.equal(init?.headers, undefined);
      assert.ok(init?.signal);
      return new Response(JSON.stringify({ items: [{ id: channelId }] }));
    },
  });
  assert.equal(id, channelId);
});

test('without a key fetches only rebuilt trusted public profile URL and drops share parameters', async () => {
  assert.equal(await resolveYouTubeProfileChannelId('https://m.youtube.com/@أبو_عمير?next=https://evil.test', {
    apiKey: '',
    fetchImpl: async (input, init) => {
      const url = new URL(String(input));
      assert.equal(url.origin, 'https://www.youtube.com');
      assert.equal(decodeURIComponent(url.pathname), '/@أبو_عمير');
      assert.equal(url.search, '');
      assert.equal(init?.redirect, 'manual');
      assert.equal(new Headers(init?.headers).get('cookie'), 'SOCS=CAE');
      return new Response(html);
    },
  }), channelId);
});

test('HTML extraction accepts own channel metadata but ignores recommended/video channel IDs', () => {
  assert.equal(channelIdFromYouTubeProfileHtml(html), channelId);
  assert.equal(channelIdFromYouTubeProfileHtml(`<head><link href="https://www.youtube.com/channel/${channelId}" rel="canonical"></head>`), channelId);
  assert.equal(channelIdFromYouTubeProfileHtml(`<script>var ytInitialData={"metadata":{"channelMetadataRenderer":{"title":"A \\\" } title","externalId":"${channelId}"}}}</script>`), channelId);
  assert.equal(channelIdFromYouTubeProfileHtml(`{"videoDetails":{"channelId":"${channelId}"}}`), null);
  assert.equal(channelIdFromYouTubeProfileHtml(`<link rel="canonical" href="https://evil.test/channel/${channelId}">`), null);
});

test('body markup and metatag strings inside channel descriptions cannot choose a channel', () => {
  const otherId = `UC${'b'.repeat(22)}`;
  const fakeTag = `<meta property='og:url' content='https://www.youtube.com/channel/${otherId}'>`;
  assert.equal(channelIdFromYouTubeProfileHtml(`<head></head><body>${fakeTag}</body>`), null);
  assert.equal(channelIdFromYouTubeProfileHtml(`<head><script>const description=${JSON.stringify(fakeTag)};</script></head>`), null);
  const data = { metadata: { channelMetadataRenderer: { description: fakeTag, externalId: channelId } } };
  assert.equal(channelIdFromYouTubeProfileHtml(`<head><script>var ytInitialData=${JSON.stringify(data)};</script></head>`), channelId);
  assert.equal(channelIdFromYouTubeProfileHtml(`<head></head><body>"channelMetadataRenderer":{"externalId":"${otherId}"}</body>`), null);
  assert.equal(channelIdFromYouTubeProfileHtml(`<head><script>var description="${fakeTag}";</script><link rel="canonical" href="https://www.youtube.com/channel/${channelId}"></head>`), channelId);
});

test('legacy profile redirects resolve only within allowlisted profile URLs', async () => {
  let requests = 0;
  assert.equal(await resolveYouTubeProfileChannelId('https://youtube.com/c/Creator', {
    apiKey: '',
    fetchImpl: async () => {
      requests++;
      return requests === 1
        ? new Response(null, { status: 302, headers: { location: '/@creator' } })
        : new Response(html);
    },
  }), channelId);
  assert.equal(requests, 2);
  requests = 0;
  await assert.rejects(() => resolveYouTubeProfileChannelId('https://youtube.com/@creator', {
    apiKey: '', fetchImpl: async () => {
      requests++;
      return new Response(null, { status: 302, headers: { location: 'https://127.0.0.1/private' } });
    },
  }), (error: unknown) => error instanceof YouTubeProfileResolutionError && error.httpStatus === 503);
  assert.equal(requests, 1);
  requests = 0;
  await assert.rejects(() => resolveYouTubeProfileChannelId('https://youtube.com/@creator', {
    apiKey: '', fetchImpl: async () => {
      requests++;
      return new Response(null, { status: 302, headers: { location: '/@creator' } });
    },
  }), (error: unknown) => error instanceof YouTubeProfileResolutionError && error.httpStatus === 503);
  assert.equal(requests, 3);
});

test('missing profiles, network failure, oversized bodies and missing metadata never mean non-member', async () => {
  for (const [fetchImpl, expected] of [
    [async () => new Response(null, { status: 404 }), 400],
    [async () => new Response('consent required'), 503],
    [async () => new Response('x'.repeat(2_000_001)), 503],
    [async () => { throw new Error('network URL could contain a secret'); }, 503],
  ] as const) {
    await assert.rejects(() => resolveYouTubeProfileChannelId('https://youtube.com/@creator', { apiKey: '', fetchImpl }),
      (error: unknown) => error instanceof YouTubeProfileResolutionError && error.httpStatus === expected && !error.message.includes('secret'));
  }
});

test('API missing profile is distinct from snapshot membership and quota falls back to public metadata', async () => {
  await assert.rejects(() => resolveYouTubeProfileChannelId('https://youtube.com/@creator', {
    apiKey: 'test', fetchImpl: async () => new Response('{"items":[]}'),
  }), (error: unknown) => error instanceof YouTubeProfileResolutionError && error.code === 'youtube_profile_not_found');
  let requests = 0;
  assert.equal(await resolveYouTubeProfileChannelId('https://youtube.com/@creator', {
    apiKey: 'test', fetchImpl: async () => {
      requests++;
      return requests === 1 ? new Response(null, { status: 403 }) : new Response(html);
    },
  }), channelId);
});
