import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fetchLatestCreatorVideo } from '../services/youtubeVideoSyncService.js';

const channelId = `UC${'a'.repeat(22)}`;

describe('YouTube latest-video synchronization', () => {
  it('reads the newest public upload from the configured channel feed', async () => {
    let requestedUrl = '';
    const video = await fetchLatestCreatorVideo(channelId, async (input, init) => {
      requestedUrl = input.toString();
      assert.equal((init?.headers as Record<string, string>).Accept.includes('xml'), true);
      return new Response(`<?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <yt:videoId>dQw4w9WgXcQ</yt:videoId>
            <title>Match &amp; analysis</title>
            <published>2026-09-01T08:30:00+00:00</published>
            <media:group>
              <media:description>Latest &amp; greatest</media:description>
              <media:thumbnail url="https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg" />
            </media:group>
          </entry>
        </feed>`, { status: 200, headers: { 'content-type': 'application/atom+xml' } });
    });

    assert.equal(
      requestedUrl,
      `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`,
    );
    assert.deepEqual(video, {
      youtubeId: 'dQw4w9WgXcQ',
      title: 'Match & analysis',
      description: 'Latest & greatest',
      thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      publishedAt: new Date('2026-09-01T08:30:00Z'),
    });
  });

  it('rejects oversized feeds and never accepts an arbitrary channel value', async () => {
    await assert.rejects(
      fetchLatestCreatorVideo('not-a-channel', async () => new Response('')),
      /youtube_channel_invalid/,
    );
    await assert.rejects(
      fetchLatestCreatorVideo(channelId, async () => new Response('<feed/>', {
        headers: { 'content-length': '2000001' },
      })),
      /youtube_feed_too_large/,
    );
  });

  it('runs every 12 hours across restarts and preserves manual video edits', async () => {
    const service = await readFile(
      path.resolve(process.cwd(), 'src/services/youtubeVideoSyncService.ts'),
      'utf8',
    );
    const index = await readFile(path.resolve(process.cwd(), 'src/index.ts'), 'utf8');
    assert.match(service, /const twelveHoursMs = 12 \* 60 \* 60 \* 1000/);
    assert.match(service, /last_succeeded_at/);
    assert.match(service, /ON CONFLICT \(youtube_id\) DO NOTHING/);
    assert.doesNotMatch(service, /refresh_token|Authorization: `Bearer/);
    assert.match(index, /startYouTubeVideoSynchronization/);
    assert.match(index, /stopYouTubeVideoSync\?\.\(\)/);
  });
});
