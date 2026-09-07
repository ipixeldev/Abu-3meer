import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(process.cwd(), '.env') });

const configuredSportsDbApiKey = (process.env.SPORTSDB_API_KEY || '123').trim();
const legacyApiFootballKey = /^[a-f0-9]{32}$/i.test(configuredSportsDbApiKey)
  ? configuredSportsDbApiKey
  : '';
const configuredApiFootballKey = (
  process.env.API_FOOTBALL_API_KEY || legacyApiFootballKey
).trim();
const sportsDbApiKey = legacyApiFootballKey ? '123' : configuredSportsDbApiKey;

function numericIdList(value: string, maximum = 8): string[] {
  return value
    .split(',')
    .map(item => item.trim())
    .filter(item => /^\d{1,20}$/.test(item))
    .filter((item, index, items) => items.indexOf(item) === index)
    .slice(0, maximum);
}

function uuidList(value: string, maximum = 20): string[] {
  return value
    .split(',')
    .map(item => item.trim().toLowerCase())
    .filter(item => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(item))
    .filter((item, index, items) => items.indexOf(item) === index)
    .slice(0, maximum);
}

function dailyFootballRequestBudget(value: string): number {
  // The Mega plan permits 150,000 requests/day. Preserve headroom for manual
  // diagnostics and a second deployment during a rolling release.
  return Math.min(149_000, Math.max(1, parseInt(value, 10)));
}

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',

  support: {
    // Public business contact, not a secret. Blank disables WhatsApp support.
    whatsappNumber: (process.env.SUPPORT_WHATSAPP_NUMBER || '').trim(),
  },

  database: {
    url: process.env.DATABASE_URL || 'postgres://abu3meer_admin:change_me_in_production@127.0.0.1:6432/abu3meer_prod',
    directUrl: process.env.DIRECT_DATABASE_URL || 'postgres://abu3meer_admin:change_me_in_production@127.0.0.1:5432/abu3meer_prod',
    maxConnections: parseInt(process.env.DB_MAX_CONNECTIONS || '20', 10),
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  },

  redis: {
    host: process.env.REDIS_HOST || '127.0.0.1',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD || undefined,
  },

  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID || 'abu-3meer-9fd70',
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL || '',
    privateKey: (process.env.FIREBASE_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
  },

  revenueCat: {
    // A RevenueCat secret REST API v1 key. Never use the SDK's public key here.
    secretApiKey: (process.env.REVENUECAT_SECRET_API_KEY || '').trim(),
    entitlementId: 'abu_3meer_pro',
    webhookAuthorization: (process.env.REVENUECAT_WEBHOOK_AUTHORIZATION || '').trim(),
    // Escape hatch for RevenueCat Test Store/legacy unknown sandbox rows.
    // Normal App Store/Play test-track receipts do not need this switch.
    allowSandbox: process.env.REVENUECAT_ALLOW_SANDBOX === 'true',
    // Genuine Apple/Google sandbox receipts are accepted based on their
    // persisted store provenance. This opt-in is only for RevenueCat Test
    // Store or legacy sandbox rows whose provider cannot be verified.
    sandboxAllowedUserIds: uuidList(
      process.env.REVENUECAT_SANDBOX_ALLOWED_USER_IDS || '',
    ),
  },

  // No implicit production administrator. The first configured address is the
  // protected bootstrap Super Administrator, so it must be explicit in .env.
  adminEmails: (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map(e => e.trim().toLowerCase())
    .filter(Boolean),

  // Native iOS/Android requests do not carry a browser Origin header. These
  // values are only used to allow the hosted/PWA frontends to call the API.
  corsOrigins: (process.env.CORS_ORIGINS || [
    'https://abu3meer.com',
    'https://www.abu3meer.com',
    'https://abu-3meer-9fd70.web.app',
    'https://abu-3meer-9fd70.firebaseapp.com',
  ].join(','))
    .split(',')
    .map(origin => origin.trim().replace(/\/$/, ''))
    .filter(Boolean),

  r2: {
    accountId: process.env.R2_ACCOUNT_ID || '',
    accessKeyId: process.env.R2_ACCESS_KEY_ID || '',
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || '',
    bucketName: process.env.R2_BUCKET_NAME || 'abu3meer-assets',
    publicUrl: process.env.R2_PUBLIC_URL || 'https://assets.abu3meer.com',
  },

  uploads: {
    directory: path.resolve(
      process.env.UPLOAD_DIRECTORY || path.join(process.cwd(), 'uploads'),
    ),
    publicBaseUrl: (process.env.UPLOAD_PUBLIC_BASE_URL || '').replace(/\/$/, ''),
    maxImageBytes: parseInt(
      process.env.UPLOAD_MAX_IMAGE_BYTES || `${8 * 1024 * 1024}`,
      10,
    ),
  },

  sportsDb: {
    // The public TheSportsDB key remains a development fallback. Existing
    // installations that placed a 32-character API-Football key in the legacy
    // variable are detected above and safely routed to API-Football instead.
    apiKey: sportsDbApiKey,
    eventCacheTtlSeconds: parseInt(process.env.SPORTSDB_EVENT_CACHE_TTL_SECONDS || '300', 10),
    liveDataCacheTtlSeconds: parseInt(process.env.SPORTSDB_LIVE_CACHE_TTL_SECONDS || '45', 10),
    lineupCacheTtlSeconds: parseInt(process.env.SPORTSDB_LINEUP_CACHE_TTL_SECONDS || '1800', 10),
    standingsCacheTtlSeconds: parseInt(process.env.SPORTSDB_STANDINGS_CACHE_TTL_SECONDS || '900', 10),
    fixtureCacheTtlSeconds: parseInt(process.env.SPORTSDB_FIXTURE_CACHE_TTL_SECONDS || '300', 10),
    catalogCacheTtlSeconds: parseInt(process.env.SPORTSDB_CATALOG_CACHE_TTL_SECONDS || '21600', 10),
    catalogNegativeCacheTtlSeconds: parseInt(
      process.env.SPORTSDB_CATALOG_NEGATIVE_CACHE_TTL_SECONDS || '300',
      10,
    ),
    negativeCacheTtlSeconds: parseInt(process.env.SPORTSDB_NEGATIVE_CACHE_TTL_SECONDS || '20', 10),
    dailyRequestBudget: dailyFootballRequestBudget(
      process.env.SPORTSDB_DAILY_REQUEST_BUDGET || '140000',
    ),
    featuredTeamIds: numericIdList(
      process.env.SPORTSDB_FEATURED_TEAM_IDS || '133738,133739',
    ),
  },

  apiFootball: {
    apiKey: configuredApiFootballKey,
    baseUrl: 'https://v3.football.api-sports.io',
    dailyRequestBudget: dailyFootballRequestBudget(
      process.env.API_FOOTBALL_DAILY_REQUEST_BUDGET ||
        process.env.SPORTSDB_DAILY_REQUEST_BUDGET ||
        '140000',
    ),
    // API-Football IDs: Real Madrid and Barcelona. These are deliberately
    // separate from TheSportsDB's 133738/133739 identifiers.
    featuredTeamIds: numericIdList(
      process.env.API_FOOTBALL_FEATURED_TEAM_IDS || '541,529',
    ),
  },

  pointDefaults: {
    // Signup and daily attendance are fixed activity awards. They deliberately
    // remain outside the YouTube membership multiplier.
    signUpBonus: parseInt(process.env.SIGNUP_BONUS_POINTS || '50', 10),
    exactScore: parseInt(process.env.EXACT_SCORE_POINTS || '50', 10),
    firstScorer: parseInt(process.env.FIRST_SCORER_POINTS || '20', 10),
    winnerOutcome: parseInt(process.env.WINNER_OUTCOME_POINTS || '10', 10),
    videoPhrase: parseInt(process.env.VIDEO_PHRASE_POINTS || '15', 10),
    playerCard: parseInt(process.env.PLAYER_CARD_POINTS || '15', 10),
    dailyStreak: parseInt(process.env.DAILY_STREAK_POINTS || '5', 10),
    firstMembershipActivation: parseInt(
      process.env.FIRST_MEMBERSHIP_ACTIVATION_POINTS || '150',
      10,
    ),
    membershipRenewal: parseInt(
      process.env.MEMBERSHIP_RENEWAL_POINTS || '50',
      10,
    ),
    memberMultiplier: parseFloat(process.env.MEMBER_MULTIPLIER || '2.0'),
  },
};
