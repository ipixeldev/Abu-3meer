/**
 * Request targets can contain names, email addresses, and search terms in the
 * query string. Operational logs only need the route path, so discard the
 * query and fragment before a request is serialized or written to an audit
 * record.
 */
export function redactRequestUrl(rawUrl: string): string {
  const path = rawUrl.split(/[?#]/, 1)[0] || '/';

  // OAuth polling identifiers are bearer-like correlators. Keep the route
  // template useful for metrics without retaining an individual flow UUID.
  const oauthTemplate = path
    .replace(
      /^\/api\/v1\/profile\/youtube\/connect\/[^/]+\/status$/i,
      '/api/v1/profile/youtube/connect/:flowId/status',
    )
    .replace(
      /^\/api\/v1\/admin\/youtube\/creator\/connect\/[^/]+\/status$/i,
      '/api/v1/admin/youtube/creator/connect/:flowId/status',
    );
  if (oauthTemplate !== path) return oauthTemplate;

  // Public profile lookup accepts a PostgreSQL UUID, Firebase UID, username,
  // or (for older clients) another account identifier in the path. Keep the
  // route shape useful for metrics while preventing that identifier from
  // entering ordinary request and audit logs. Static profile operations do
  // not contain user-provided identifiers and remain intact.
  return path.replace(
    /^(\/api\/v1\/profile\/)(?!me(?:\/|$)|point-history(?:\/|$)|team(?:\/|$))[^/]+/i,
    '$1:id',
  );
}

interface LogRequestLike {
  id?: string;
  method?: string;
  url?: string;
}

/**
 * Deliberately excludes the remote IP. IP-based throttling can still use the
 * live request value without retaining it in ordinary application logs.
 */
export function serializeRequestForLog(request: LogRequestLike) {
  return {
    id: request.id,
    method: request.method,
    url: redactRequestUrl(request.url ?? '/'),
  };
}
