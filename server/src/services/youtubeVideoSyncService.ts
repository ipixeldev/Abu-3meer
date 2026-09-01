import { config } from '../config.js';
import { getDirectClient } from '../db/pool.js';
import { FetchLike } from './youtubeOAuthService.js';

const twelveHoursMs = 12 * 60 * 60 * 1000;
const schedulerTickMs = 60 * 60 * 1000;

export interface SyncedYouTubeVideo {
  youtubeId: string;
  title: string;
  description: string | null;
  thumbnailUrl: string;
  publishedAt: Date;
}

function configuredCreatorChannelId(): string | null {
  const channelId = config.youtubeOAuth.creatorChannelId;
  return /^UC[A-Za-z0-9_-]{22}$/.test(channelId) ? channelId : null;
}

function decodeXmlText(value: string): string {
  return value
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}

export async function fetchLatestCreatorVideo(
  creatorChannelId: string,
  fetchImpl: FetchLike = fetch,
): Promise<SyncedYouTubeVideo | null> {
  if (!/^UC[A-Za-z0-9_-]{22}$/.test(creatorChannelId)) {
    throw new Error('youtube_channel_invalid');
  }
  const url = new URL('https://www.youtube.com/feeds/videos.xml');
  url.searchParams.set('channel_id', creatorChannelId);
  const response = await fetchImpl(url, {
    headers: { Accept: 'application/atom+xml, application/xml;q=0.9' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`youtube_feed_${response.status}`);
  const length = Number(response.headers.get('content-length') ?? 0);
  if (length > 2_000_000) throw new Error('youtube_feed_too_large');
  const xml = await response.text();
  if (xml.length > 2_000_000) throw new Error('youtube_feed_too_large');
  const entry = xml.match(/<entry\b[\s\S]*?<\/entry>/i)?.[0];
  if (!entry) return null;
  const youtubeId = entry.match(/<yt:videoId>([A-Za-z0-9_-]{11})<\/yt:videoId>/i)?.[1];
  const titleText = entry.match(/<title>([\s\S]*?)<\/title>/i)?.[1];
  const publishedText = entry.match(/<published>([^<]+)<\/published>/i)?.[1];
  if (!youtubeId || !titleText || !publishedText) throw new Error('youtube_feed_invalid');
  const publishedAt = new Date(publishedText);
  if (Number.isNaN(publishedAt.getTime())) throw new Error('youtube_feed_invalid');
  const thumbnail = entry.match(/<media:thumbnail\b[^>]*\burl="(https:\/\/[^"<]+)"/i)?.[1];
  const descriptionText = entry.match(/<media:description>([\s\S]*?)<\/media:description>/i)?.[1];
  return {
    youtubeId,
    title: decodeXmlText(titleText).trim().slice(0, 255),
    description: descriptionText
      ? decodeXmlText(descriptionText).trim().slice(0, 10_000)
      : null,
    thumbnailUrl: thumbnail
      ? decodeXmlText(thumbnail)
      : `https://img.youtube.com/vi/${youtubeId}/hqdefault.jpg`,
    publishedAt,
  };
}

export async function synchronizeLatestYouTubeVideo(
  now = new Date(),
  fetchImpl: FetchLike = fetch,
): Promise<'synced' | 'not_due' | 'not_configured'> {
  const creatorChannelId = configuredCreatorChannelId();
  if (!creatorChannelId) return 'not_configured';
  const client = await getDirectClient();
  let locked = false;
  try {
    const lock = await client.query(
      `SELECT pg_try_advisory_lock(hashtextextended('youtube-latest-video-sync', 0)) AS acquired`,
    );
    locked = lock.rows[0]?.acquired === true;
    if (!locked) return 'not_due';
    const state = await client.query(
      `SELECT last_succeeded_at FROM youtube_video_sync_state WHERE singleton = TRUE`,
    );
    const lastSuccess = state.rows[0]?.last_succeeded_at
      ? new Date(state.rows[0].last_succeeded_at)
      : null;
    if (lastSuccess && now.getTime() - lastSuccess.getTime() < twelveHoursMs) {
      return 'not_due';
    }
    await client.query(
      `UPDATE youtube_video_sync_state SET last_attempted_at = $1, updated_at = $1 WHERE singleton = TRUE`,
      [now],
    );
    const video = await fetchLatestCreatorVideo(
      creatorChannelId,
      fetchImpl,
    );
    if (video) {
      // Never overwrite Admin Studio edits: automatic discovery only fills a
      // missing public row; admins retain full manual scheduling/control.
      await client.query(
        `INSERT INTO videos
           (id, youtube_id, title, description, thumbnail_url, video_url,
            published_at, is_unlisted, member_only)
         VALUES ($1, $2, $3, $4, $5, $6, $7, FALSE, FALSE)
         ON CONFLICT (youtube_id) DO NOTHING`,
        [
          `vid_${video.youtubeId}`,
          video.youtubeId,
          video.title,
          video.description,
          video.thumbnailUrl,
          `https://www.youtube.com/watch?v=${video.youtubeId}`,
          video.publishedAt,
        ],
      );
    }
    await client.query(
      `UPDATE youtube_video_sync_state
       SET last_succeeded_at = $1, last_video_id = $2,
           last_error_code = NULL, updated_at = $1
       WHERE singleton = TRUE`,
      [now, video?.youtubeId ?? null],
    );
    return 'synced';
  } catch (error) {
    const code = error instanceof Error ? error.message.slice(0, 100) : 'sync_failed';
    await client.query(
      `UPDATE youtube_video_sync_state
       SET last_error_code = $1, updated_at = CURRENT_TIMESTAMP
       WHERE singleton = TRUE`,
      [code],
    ).catch(() => undefined);
    throw error;
  } finally {
    if (locked) {
      await client.query(
        `SELECT pg_advisory_unlock(hashtextextended('youtube-latest-video-sync', 0))`,
      ).catch(() => undefined);
    }
    client.release();
  }
}

export function startYouTubeVideoSynchronization(
  log: { info: (data: unknown, message: string) => void; error: (data: unknown, message: string) => void },
): () => void {
  const run = () => void synchronizeLatestYouTubeVideo()
    .then((status) => log.info({ status }, 'YouTube latest-video synchronization checked'))
    .catch((error) => log.error({ err: error }, 'YouTube latest-video synchronization failed'));
  run();
  const timer = setInterval(run, schedulerTickMs);
  timer.unref();
  return () => clearInterval(timer);
}
