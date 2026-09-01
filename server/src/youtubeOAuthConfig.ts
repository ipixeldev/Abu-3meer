const requiredYouTubeOAuthVariables = [
  'YOUTUBE_OAUTH_CLIENT_ID',
  'YOUTUBE_OAUTH_CLIENT_SECRET',
  'YOUTUBE_OAUTH_REDIRECT_URI',
  'YOUTUBE_CREATOR_CHANNEL_ID',
  'YOUTUBE_TOKEN_ENCRYPTION_KEY',
] as const;

export type YouTubeOAuthVariable =
  | (typeof requiredYouTubeOAuthVariables)[number]
  | 'YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS';

export interface YouTubeOAuthConfigurationIssue {
  variable: YouTubeOAuthVariable;
  reason: 'missing' | 'invalid';
}

function clean(value: string | undefined): string {
  return (value || '').trim();
}

function isGoogleWebClientId(value: string): boolean {
  return /^[a-z0-9._-]+\.apps\.googleusercontent\.com$/i.test(value);
}

function isProductionRedirectUri(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:'
      && Boolean(url.hostname)
      && !url.username
      && !url.password
      && !url.search
      && !url.hash
      && url.pathname === '/api/v1/youtube/oauth/callback';
  } catch {
    return false;
  }
}

function isYouTubeChannelId(value: string): boolean {
  return /^UC[A-Za-z0-9_-]{22}$/.test(value);
}

function isBase64Aes256Key(value: string): boolean {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4 !== 0) {
    return false;
  }
  try {
    return Buffer.from(value, 'base64').length === 32;
  } catch {
    return false;
  }
}

export function loadYouTubeOAuthConfig(
  environment: NodeJS.ProcessEnv = process.env,
) {
  const clientId = clean(environment.YOUTUBE_OAUTH_CLIENT_ID);
  const clientSecret = clean(environment.YOUTUBE_OAUTH_CLIENT_SECRET);
  const redirectUri = clean(environment.YOUTUBE_OAUTH_REDIRECT_URI);
  const creatorChannelId = clean(environment.YOUTUBE_CREATOR_CHANNEL_ID);
  const tokenEncryptionKey = clean(environment.YOUTUBE_TOKEN_ENCRYPTION_KEY);
  const refreshIntervalRaw = clean(
    environment.YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS,
  ) || '21600';
  const parsedRefreshInterval = Number(refreshIntervalRaw);
  const refreshIntervalIsValid = Number.isInteger(parsedRefreshInterval)
    && parsedRefreshInterval >= 900
    && parsedRefreshInterval <= 86400;

  const values: Record<(typeof requiredYouTubeOAuthVariables)[number], string> = {
    YOUTUBE_OAUTH_CLIENT_ID: clientId,
    YOUTUBE_OAUTH_CLIENT_SECRET: clientSecret,
    YOUTUBE_OAUTH_REDIRECT_URI: redirectUri,
    YOUTUBE_CREATOR_CHANNEL_ID: creatorChannelId,
    YOUTUBE_TOKEN_ENCRYPTION_KEY: tokenEncryptionKey,
  };
  const issues: YouTubeOAuthConfigurationIssue[] = [];

  for (const variable of requiredYouTubeOAuthVariables) {
    if (!values[variable]) issues.push({ variable, reason: 'missing' });
  }
  if (clientId && !isGoogleWebClientId(clientId)) {
    issues.push({ variable: 'YOUTUBE_OAUTH_CLIENT_ID', reason: 'invalid' });
  }
  if (redirectUri && !isProductionRedirectUri(redirectUri)) {
    issues.push({ variable: 'YOUTUBE_OAUTH_REDIRECT_URI', reason: 'invalid' });
  }
  if (creatorChannelId && !isYouTubeChannelId(creatorChannelId)) {
    issues.push({ variable: 'YOUTUBE_CREATOR_CHANNEL_ID', reason: 'invalid' });
  }
  if (tokenEncryptionKey && !isBase64Aes256Key(tokenEncryptionKey)) {
    issues.push({ variable: 'YOUTUBE_TOKEN_ENCRYPTION_KEY', reason: 'invalid' });
  }
  if (!refreshIntervalIsValid) {
    issues.push({
      variable: 'YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS',
      reason: 'invalid',
    });
  }

  const configured = issues.length === 0;
  return {
    configured,
    clientId,
    clientSecret,
    redirectUri,
    creatorChannelId,
    tokenEncryptionKey,
    membershipRefreshIntervalSeconds: refreshIntervalIsValid
      ? parsedRefreshInterval
      : 21600,
    // This is the only safe portion of this object to expose through health
    // or diagnostics. It contains variable names, never credential values.
    status: {
      state: configured ? 'configured' as const : 'credentials_required' as const,
      issues,
    },
  };
}
