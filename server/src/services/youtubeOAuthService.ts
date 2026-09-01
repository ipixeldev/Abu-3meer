import crypto from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';

export const youtubeReadonlyScope =
  'https://www.googleapis.com/auth/youtube.readonly';
export const youtubeCreatorMembershipScope =
  'https://www.googleapis.com/auth/youtube.channel-memberships.creator';
export const googleOpenIdScope = 'openid';

const googleAuthorizationEndpoint =
  'https://accounts.google.com/o/oauth2/v2/auth';
const googleTokenEndpoint = 'https://oauth2.googleapis.com/token';
const youtubeChannelsEndpoint =
  'https://www.googleapis.com/youtube/v3/channels';
const tokenEnvelopeAad = 'abu3meer:youtube:creator-refresh-token';

export type YouTubeOAuthPurpose = 'member_link' | 'creator_connect';
export type FetchLike = (
  input: string | URL,
  init?: RequestInit,
) => Promise<Response>;

export type YouTubeRuntimeConfig = {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  creatorChannelId: string;
  tokenEncryptionKey: Buffer;
  membershipRefreshIntervalSeconds: number;
};

export class YouTubeIntegrationError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus = 400,
    message = 'YouTube connection could not be completed.',
  ) {
    super(message);
    this.name = 'YouTubeIntegrationError';
  }
}

function requiredEnvironmentValue(
  environment: NodeJS.ProcessEnv,
  name: string,
): string {
  const value = environment[name]?.trim() ?? '';
  if (!value) {
    throw new YouTubeIntegrationError(
      'youtube_not_configured',
      503,
      'YouTube membership verification is not configured.',
    );
  }
  return value;
}

function encryptionKey(value: string): Buffer {
  let decoded = Buffer.alloc(0);
  if (/^[A-Za-z0-9+/]+={0,2}$/.test(value) && value.length % 4 === 0) {
    try {
      decoded = Buffer.from(value, 'base64');
    } catch {
      decoded = Buffer.alloc(0);
    }
  }
  if (decoded.length !== 32) {
    throw new YouTubeIntegrationError(
      'youtube_invalid_encryption_key',
      503,
      'YouTube membership verification is not configured.',
    );
  }
  return decoded;
}

// YouTube channel IDs use the UC prefix followed by exactly 22 URL-safe
// characters. A broader pattern would allow arbitrary client identifiers into
// membership lookups and the unique account-link table.
export const youtubeChannelIdPattern = /^UC[A-Za-z0-9_-]{22}$/;

export function googleProviderSubjectFromFirebaseIdentities(
  identities: unknown,
): string | null {
  if (!identities || typeof identities !== 'object') return null;
  const googleIdentities = (identities as Record<string, unknown>)['google.com'];
  if (!Array.isArray(googleIdentities) || googleIdentities.length !== 1) {
    return null;
  }
  const subject = googleIdentities[0];
  return typeof subject === 'string' && /^[A-Za-z0-9_-]{1,255}$/.test(subject)
    ? subject
    : null;
}

export function youtubeMembershipRefreshIntervalSeconds(
  environment: NodeJS.ProcessEnv = process.env,
): number {
  const configured = Number.parseInt(
    environment.YOUTUBE_MEMBERSHIP_REFRESH_INTERVAL_SECONDS ?? '21600',
    10,
  );
  if (!Number.isFinite(configured)) return 21600;
  return Math.min(86400, Math.max(900, configured));
}

export function loadYouTubeRuntimeConfig(
  environment: NodeJS.ProcessEnv = process.env,
): YouTubeRuntimeConfig {
  const redirectUri = requiredEnvironmentValue(
    environment,
    'YOUTUBE_OAUTH_REDIRECT_URI',
  );
  let parsedRedirect: URL;
  try {
    parsedRedirect = new URL(redirectUri);
  } catch {
    throw new YouTubeIntegrationError(
      'youtube_invalid_redirect_uri',
      503,
      'YouTube membership verification is not configured.',
    );
  }
  const localDevelopmentRedirect =
    ['development', 'test'].includes(environment.NODE_ENV ?? '') &&
    ['localhost', '127.0.0.1'].includes(parsedRedirect.hostname);
  if (parsedRedirect.protocol !== 'https:' && !localDevelopmentRedirect) {
    throw new YouTubeIntegrationError(
      'youtube_invalid_redirect_uri',
      503,
      'YouTube membership verification is not configured.',
    );
  }
  if (
    parsedRedirect.username ||
    parsedRedirect.password ||
    parsedRedirect.search ||
    parsedRedirect.hash ||
    parsedRedirect.pathname !== '/api/v1/youtube/oauth/callback'
  ) {
    throw new YouTubeIntegrationError(
      'youtube_invalid_redirect_uri',
      503,
      'YouTube membership verification is not configured.',
    );
  }

  const clientId = requiredEnvironmentValue(
    environment,
    'YOUTUBE_OAUTH_CLIENT_ID',
  );
  if (!/^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$/.test(clientId)) {
    throw new YouTubeIntegrationError(
      'youtube_invalid_client_id',
      503,
      'YouTube membership verification is not configured.',
    );
  }

  const creatorChannelId = requiredEnvironmentValue(
    environment,
    'YOUTUBE_CREATOR_CHANNEL_ID',
  );
  if (!youtubeChannelIdPattern.test(creatorChannelId)) {
    throw new YouTubeIntegrationError(
      'youtube_invalid_creator_channel',
      503,
      'YouTube membership verification is not configured.',
    );
  }

  return {
    clientId,
    clientSecret: requiredEnvironmentValue(
      environment,
      'YOUTUBE_OAUTH_CLIENT_SECRET',
    ),
    redirectUri: parsedRedirect.toString(),
    creatorChannelId,
    tokenEncryptionKey: encryptionKey(
      requiredEnvironmentValue(environment, 'YOUTUBE_TOKEN_ENCRYPTION_KEY'),
    ),
    membershipRefreshIntervalSeconds:
      youtubeMembershipRefreshIntervalSeconds(environment),
  };
}

export function sha256Hex(value: string): string {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function constantTimeHexEqual(left: string, right: string): boolean {
  if (!/^[a-f0-9]{64}$/i.test(left) || !/^[a-f0-9]{64}$/i.test(right)) {
    return false;
  }
  return crypto.timingSafeEqual(Buffer.from(left, 'hex'), Buffer.from(right, 'hex'));
}

export function encryptYouTubeSecret(
  plaintext: string,
  key: Buffer,
  additionalAuthenticatedData: string,
): string {
  if (!plaintext || key.length !== 32) {
    throw new YouTubeIntegrationError('youtube_secret_encryption_failed', 500);
  }
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(additionalAuthenticatedData, 'utf8'));
  const encrypted = Buffer.concat([
    cipher.update(plaintext, 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    'v1',
    nonce.toString('base64url'),
    tag.toString('base64url'),
    encrypted.toString('base64url'),
  ].join('.');
}

export function decryptYouTubeSecret(
  envelope: string,
  key: Buffer,
  additionalAuthenticatedData: string,
): string {
  const [version, nonceValue, tagValue, ciphertextValue, ...extra] =
    envelope.split('.');
  if (
    version !== 'v1' ||
    !nonceValue ||
    !tagValue ||
    !ciphertextValue ||
    extra.length > 0 ||
    key.length !== 32
  ) {
    throw new YouTubeIntegrationError('youtube_secret_decryption_failed', 500);
  }
  try {
    const nonce = Buffer.from(nonceValue, 'base64url');
    const tag = Buffer.from(tagValue, 'base64url');
    const ciphertext = Buffer.from(ciphertextValue, 'base64url');
    if (nonce.length !== 12 || tag.length !== 16 || ciphertext.length === 0) {
      throw new Error('Invalid encrypted token envelope.');
    }
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAAD(Buffer.from(additionalAuthenticatedData, 'utf8'));
    decipher.setAuthTag(tag);
    return Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]).toString('utf8');
  } catch {
    throw new YouTubeIntegrationError('youtube_secret_decryption_failed', 500);
  }
}

export function encryptCreatorRefreshToken(
  refreshToken: string,
  config: YouTubeRuntimeConfig,
): string {
  return encryptYouTubeSecret(
    refreshToken,
    config.tokenEncryptionKey,
    tokenEnvelopeAad,
  );
}

export function decryptCreatorRefreshToken(
  ciphertext: string,
  config: YouTubeRuntimeConfig,
): string {
  return decryptYouTubeSecret(
    ciphertext,
    config.tokenEncryptionKey,
    tokenEnvelopeAad,
  );
}

export type GeneratedOAuthFlow = {
  flowId: string;
  state: string;
  stateHash: string;
  authorizationUrl: string;
  pkceVerifierCiphertext: string;
  oidcNonceHash: string;
};

export function generateYouTubeOAuthFlow(
  purpose: YouTubeOAuthPurpose,
  config: YouTubeRuntimeConfig,
): GeneratedOAuthFlow {
  const flowId = crypto.randomUUID();
  const state = crypto.randomBytes(32).toString('base64url');
  const codeVerifier = crypto.randomBytes(48).toString('base64url');
  const codeChallenge = crypto
    .createHash('sha256')
    .update(codeVerifier, 'ascii')
    .digest('base64url');
  const oidcNonce = crypto.randomBytes(32).toString('base64url');
  // Private creator-membership access is intentionally unsupported. OAuth is
  // only used to prove which public YouTube channel the app user owns.
  const scopes = [googleOpenIdScope, youtubeReadonlyScope];
  const url = new URL(googleAuthorizationEndpoint);
  url.searchParams.set('client_id', config.clientId);
  url.searchParams.set('redirect_uri', config.redirectUri);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', scopes.join(' '));
  url.searchParams.set('state', state);
  url.searchParams.set('nonce', oidcNonce);
  url.searchParams.set('code_challenge', codeChallenge);
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('include_granted_scopes', 'true');
  url.searchParams.set('prompt', 'select_account');

  return {
    flowId,
    state,
    stateHash: sha256Hex(state),
    authorizationUrl: url.toString(),
    pkceVerifierCiphertext: encryptYouTubeSecret(
      codeVerifier,
      config.tokenEncryptionKey,
      `abu3meer:youtube:oauth-flow:${flowId}`,
    ),
    oidcNonceHash: sha256Hex(oidcNonce),
  };
}

export function decryptOAuthCodeVerifier(
  flowId: string,
  ciphertext: string,
  config: YouTubeRuntimeConfig,
): string {
  return decryptYouTubeSecret(
    ciphertext,
    config.tokenEncryptionKey,
    `abu3meer:youtube:oauth-flow:${flowId}`,
  );
}

type GoogleTokenResponse = {
  accessToken: string;
  refreshToken: string | null;
  idToken: string;
  grantedScopes: Set<string>;
};

function objectValue(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object'
    ? value as Record<string, unknown>
    : {};
}

async function responseJson(response: Response): Promise<Record<string, unknown>> {
  try {
    return objectValue(await response.json());
  } catch {
    return {};
  }
}

function safeGoogleErrorCode(body: Record<string, unknown>): string {
  const direct = typeof body.error === 'string' ? body.error : '';
  const errorObject = objectValue(body.error);
  const nestedErrors = Array.isArray(errorObject.errors)
    ? errorObject.errors.map(objectValue)
    : [];
  const reason = nestedErrors.find((entry) =>
    typeof entry.reason === 'string',
  )?.reason;
  const candidate = direct || (typeof reason === 'string' ? reason : '');
  return /^[A-Za-z0-9_-]{1,80}$/.test(candidate)
    ? candidate
    : 'google_api_error';
}

function requestTimeout(): AbortSignal | undefined {
  return typeof AbortSignal.timeout === 'function'
    ? AbortSignal.timeout(10000)
    : undefined;
}

export async function exchangeGoogleAuthorizationCode(
  code: string,
  codeVerifier: string,
  config: YouTubeRuntimeConfig,
  fetchImpl: FetchLike = fetch,
): Promise<GoogleTokenResponse> {
  if (!code || code.length > 4096 || !codeVerifier) {
    throw new YouTubeIntegrationError('invalid_oauth_callback', 400);
  }
  const form = new URLSearchParams({
    code,
    client_id: config.clientId,
    client_secret: config.clientSecret,
    redirect_uri: config.redirectUri,
    grant_type: 'authorization_code',
    code_verifier: codeVerifier,
  });
  let response: Response;
  try {
    response = await fetchImpl(googleTokenEndpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form.toString(),
      signal: requestTimeout(),
    });
  } catch {
    throw new YouTubeIntegrationError('google_token_unavailable', 503);
  }
  const body = await responseJson(response);
  if (!response.ok) {
    const googleCode = safeGoogleErrorCode(body);
    throw new YouTubeIntegrationError(
      googleCode === 'invalid_grant'
        ? 'oauth_code_rejected'
        : 'google_token_rejected',
      400,
    );
  }
  const accessToken = typeof body.access_token === 'string'
    ? body.access_token
    : '';
  const idToken = typeof body.id_token === 'string' ? body.id_token : '';
  if (!accessToken || !idToken) {
    throw new YouTubeIntegrationError('google_token_incomplete', 502);
  }
  return {
    accessToken,
    refreshToken: typeof body.refresh_token === 'string'
      ? body.refresh_token
      : null,
    idToken,
    grantedScopes: new Set(
      typeof body.scope === 'string' ? body.scope.split(/\s+/).filter(Boolean) : [],
    ),
  };
}

export async function refreshGoogleAccessToken(
  refreshToken: string,
  config: YouTubeRuntimeConfig,
  fetchImpl: FetchLike = fetch,
): Promise<string> {
  const form = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    refresh_token: refreshToken,
    grant_type: 'refresh_token',
  });
  let response: Response;
  try {
    response = await fetchImpl(googleTokenEndpoint, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form.toString(),
      signal: requestTimeout(),
    });
  } catch {
    throw new YouTubeIntegrationError('creator_token_unavailable', 503);
  }
  const body = await responseJson(response);
  if (!response.ok) {
    throw new YouTubeIntegrationError(
      safeGoogleErrorCode(body) === 'invalid_grant'
        ? 'creator_reauthorization_required'
        : 'creator_token_rejected',
      503,
    );
  }
  const accessToken = typeof body.access_token === 'string'
    ? body.access_token
    : '';
  if (!accessToken) {
    throw new YouTubeIntegrationError('creator_token_incomplete', 502);
  }
  return accessToken;
}

type IdTokenVerifier = Pick<OAuth2Client, 'verifyIdToken'>;

export async function verifyGoogleAccountBinding(
  idToken: string,
  expectedGoogleSubject: string,
  expectedNonceHash: string,
  config: YouTubeRuntimeConfig,
  verifier: IdTokenVerifier = new OAuth2Client(config.clientId),
  nowEpochSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  let payload;
  try {
    const ticket = await verifier.verifyIdToken({
      idToken,
      audience: config.clientId,
    });
    payload = ticket.getPayload();
  } catch {
    throw new YouTubeIntegrationError('google_identity_invalid', 403);
  }
  const issuer = payload?.iss;
  const subject = payload?.sub ?? '';
  const nonce = payload?.nonce ?? '';
  const expiresAt = Number(payload?.exp ?? 0);
  if (
    !['https://accounts.google.com', 'accounts.google.com'].includes(issuer ?? '') ||
    !subject ||
    subject !== expectedGoogleSubject ||
    expiresAt <= nowEpochSeconds ||
    !constantTimeHexEqual(sha256Hex(nonce), expectedNonceHash)
  ) {
    throw new YouTubeIntegrationError('google_account_mismatch', 403);
  }
  return subject;
}

async function authorizedGoogleJson(
  url: URL,
  accessToken: string,
  fetchImpl: FetchLike,
): Promise<Record<string, unknown>> {
  let response: Response;
  try {
    response = await fetchImpl(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      signal: requestTimeout(),
    });
  } catch {
    throw new YouTubeIntegrationError('youtube_api_unavailable', 503);
  }
  const body = await responseJson(response);
  if (!response.ok) {
    const googleCode = safeGoogleErrorCode(body);
    const code = googleCode === 'channelMembershipsNotEnabled'
      ? 'creator_memberships_disabled'
      : response.status === 401
        ? 'creator_reauthorization_required'
        : response.status === 403
          ? 'creator_members_api_unavailable'
          : 'youtube_api_rejected';
    throw new YouTubeIntegrationError(code, response.status >= 500 ? 503 : 409);
  }
  return body;
}

export async function fetchOwnedYouTubeChannelIds(
  accessToken: string,
  fetchImpl: FetchLike = fetch,
): Promise<string[]> {
  const url = new URL(youtubeChannelsEndpoint);
  url.searchParams.set('part', 'id');
  url.searchParams.set('mine', 'true');
  url.searchParams.set('maxResults', '50');
  const body = await authorizedGoogleJson(url, accessToken, fetchImpl);
  const channels = Array.isArray(body.items) ? body.items.map(objectValue) : [];
  return [...new Set(channels
    .map((channel) => typeof channel.id === 'string' ? channel.id : '')
    .filter((channelId) => youtubeChannelIdPattern.test(channelId))
  )];
}

export type YouTubeMembershipLookup = {
  isMember: boolean;
  channelId: string | null;
  membershipLevelId: string | null;
  memberSince: Date | null;
};
