export const youtubeVideoIdPattern = /^[A-Za-z0-9_-]{11}$/;

export function isValidYoutubeVideoId(value: string): boolean {
  return youtubeVideoIdPattern.test(value.trim());
}

export type VideoQueryExecutor = (
  text: string,
  params?: unknown[],
) => Promise<{
  rowCount: number | null;
  rows: Array<Record<string, unknown>>;
}>;

export interface ExclusiveVideoListOptions {
  includeScheduled: boolean;
  canAccessMemberOnly?: boolean;
}

/**
 * Gold-only links must be protected by the server, not only by a disabled
 * button in the app. The legacy video ID is derived from the YouTube ID, so it
 * is redacted as well; otherwise a non-member could reconstruct the URL from
 * `vid_<youtube-id>` even when the explicit URL fields were blank.
 */
export function redactExclusiveVideoForViewer(
  row: Record<string, unknown>,
  canAccessMemberOnly: boolean,
): Record<string, unknown> {
  if (row.member_only !== true || canAccessMemberOnly) return row;
  return {
    ...row,
    id: '',
    youtube_id: '',
    thumbnail_url: '',
    video_url: '',
  };
}

/**
 * Admins need scheduled entries as well as live entries. Fans must only ever
 * receive videos whose publication time has arrived.
 */
export async function listExclusiveVideos(
  execute: VideoQueryExecutor,
  options: ExclusiveVideoListOptions,
): Promise<Array<Record<string, unknown>>> {
  const publicationFilter = options.includeScheduled
    ? ''
    : `AND published_at <= CURRENT_TIMESTAMP
         AND youtube_id ~ '^[A-Za-z0-9_-]{11}$'`;
  const result = await execute(
    `SELECT id, youtube_id, title, description, thumbnail_url, video_url,
            published_at, is_unlisted, member_only, view_count
     FROM videos
     WHERE (is_unlisted = TRUE OR member_only = TRUE)
     ${publicationFilter}
     ORDER BY published_at DESC
     LIMIT 200`,
  );
  return result.rows.map((row) =>
    redactExclusiveVideoForViewer(
      row,
      options.includeScheduled || options.canAccessMemberOnly === true,
    ),
  );
}
