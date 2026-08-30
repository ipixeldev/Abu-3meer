import { createHash } from 'node:crypto';
import { config } from '../config.js';
import { getCachedJson, redis, setCachedJson } from '../redis/client.js';

type JsonRecord = Record<string, unknown>;
type FootballProviderName = 'TheSportsDB' | 'API-Football';

export interface MatchTimelineDetail {
  minute: string;
  type: string;
  player: string;
  assist: string;
  detail: string;
  team: string;
  isHome: boolean;
}

export interface MatchLineupDetail {
  player: string;
  team: string;
  position: string;
  isHome: boolean;
  isSubstitute: boolean;
  squadNumber: string;
  playerImageUrl: string;
}

export interface MatchStatisticDetail {
  label: string;
  homeValue: string;
  awayValue: string;
}

export interface MatchStandingDetail {
  rank: number;
  team: string;
  played: number;
  won: number;
  drawn: number;
  lost: number;
  goalDifference: number;
  goalsFor: number;
  goalsAgainst: number;
  points: number;
  teamId: string;
  badgeUrl: string;
  form: string;
}

export interface ExternalMatchDetails {
  timeline: MatchTimelineDetail[];
  lineup: MatchLineupDetail[];
  statistics: MatchStatisticDetail[];
  standings: MatchStandingDetail[];
  venue: string;
  season: string;
  provider: string;
  isProviderLimited: boolean;
}

export interface ExternalFootballMatch {
  id: string;
  competition_name: string;
  home_team_id: string;
  away_team_id: string;
  home_team: string;
  away_team: string;
  home_logo_url: string;
  away_logo_url: string;
  kickoff_at: string;
  predictions_open_at: string;
  predictions_close_at: string;
  status: 'upcoming' | 'live' | 'completed' | 'postponed' | 'cancelled';
  home_score: number | null;
  away_score: number | null;
  first_scorer: string;
  first_scorer_options: string[];
  provider: FootballProviderName;
}

export interface FootballTeamSummary {
  teamId: string;
  name: string;
  badgeUrl: string;
  league: string;
  country: string;
}

export interface FootballPlayerSummary {
  playerId: string;
  teamId: string;
  team: string;
  name: string;
  position: string;
  squadNumber: string;
  imageUrl: string;
  nationality: string;
}

function text(value: unknown): string {
  const result = value == null ? '' : String(value).replace(/\s+/g, ' ').trim();
  return result.toLowerCase() === 'null' ? '' : result;
}

function numberValue(value: unknown): number {
  return Number.parseInt(text(value), 10) || 0;
}

function optionalNumberValue(value: unknown): number | null {
  const raw = text(value);
  if (!raw) return null;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function rows(value: unknown): JsonRecord[] {
  if (!Array.isArray(value)) return [];
  return value.filter(
    (entry): entry is JsonRecord =>
      typeof entry === 'object' && entry !== null && !Array.isArray(entry),
  );
}

function record(value: unknown): JsonRecord | undefined {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as JsonRecord
    : undefined;
}

function nestedRecord(value: unknown, key: string): JsonRecord | undefined {
  return record(record(value)?.[key]);
}

function firstRow(value: unknown): JsonRecord | undefined {
  return rows(value)[0];
}

function secureImageUrl(value: unknown): string {
  const raw = text(value);
  if (!raw) return '';
  try {
    const candidate = raw.startsWith('//') ? `https:${raw}` : raw;
    const parsed = new URL(candidate);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return '';
    parsed.protocol = 'https:';
    return parsed.toString();
  } catch {
    return '';
  }
}

function searchKey(value: unknown): string {
  return text(value)
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function isFootballTeam(item: JsonRecord): boolean {
  const sport = text(item.strSport).toLowerCase();
  return sport === '' || sport === 'soccer' || sport === 'football';
}

function providerTimestamp(item: JsonRecord): Date | null {
  const timestamp = text(item.strTimestamp);
  if (timestamp) {
    const normalized = /(?:z|[+-]\d\d:?\d\d)$/i.test(timestamp)
      ? timestamp
      : `${timestamp}Z`;
    const parsed = new Date(normalized);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }

  const date = text(item.dateEvent);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const time = text(item.strTime).replace(/[^0-9:]/g, '') || '00:00:00';
  const parsed = new Date(`${date}T${time}Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function providerEventStatus(
  item: JsonRecord,
  homeScore: number | null,
  awayScore: number | null,
): ExternalFootballMatch['status'] {
  const status = `${text(item.strStatus)} ${text(item.strPostponed)}`.toLowerCase();
  if (status.includes('cancel')) return 'cancelled';
  if (status.includes('postpon')) return 'postponed';
  if (
    status.includes('live') ||
    status.includes('progress') ||
    status.includes('half time')
  ) return 'live';
  return homeScore !== null && awayScore !== null ? 'completed' : 'upcoming';
}

export function normalizeExternalFootballEvents(value: unknown): ExternalFootballMatch[] {
  const events = rows(value);
  const results: ExternalFootballMatch[] = [];
  for (const item of events) {
    const providerId = text(item.idEvent);
    const homeTeam = text(item.strHomeTeam);
    const awayTeam = text(item.strAwayTeam);
    const kickoff = providerTimestamp(item);
    if (!providerId || !homeTeam || !awayTeam || !kickoff) continue;
    const homeScore = optionalNumberValue(item.intHomeScore);
    const awayScore = optionalNumberValue(item.intAwayScore);
    results.push({
      id: `external_${providerId}`,
      competition_name: text(item.strLeague) || 'Football',
      home_team_id: text(item.idHomeTeam),
      away_team_id: text(item.idAwayTeam),
      home_team: homeTeam,
      away_team: awayTeam,
      home_logo_url: secureImageUrl(item.strHomeTeamBadge),
      away_logo_url: secureImageUrl(item.strAwayTeamBadge),
      kickoff_at: kickoff.toISOString(),
      predictions_open_at: new Date(kickoff.getTime() - 24 * 60 * 60 * 1000).toISOString(),
      predictions_close_at: kickoff.toISOString(),
      status: providerEventStatus(item, homeScore, awayScore),
      home_score: homeScore,
      away_score: awayScore,
      first_scorer: '',
      first_scorer_options: [],
      provider: 'TheSportsDB',
    });
  }
  return results;
}

function apiFootballTimestamp(item: JsonRecord): Date | null {
  const fixture = record(item.fixture);
  const dateValue = text(fixture?.date);
  if (dateValue) {
    const parsed = new Date(dateValue);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  const timestamp = Number(fixture?.timestamp);
  if (Number.isFinite(timestamp) && timestamp > 0) {
    return new Date(timestamp * 1000);
  }
  return null;
}

function apiFootballFixtureStatus(
  item: JsonRecord,
  homeScore: number | null,
  awayScore: number | null,
): ExternalFootballMatch['status'] {
  const status = nestedRecord(item.fixture, 'status');
  const short = text(status?.short).toUpperCase();
  const long = text(status?.long).toLowerCase();
  if (['CANC', 'ABD'].includes(short) || long.includes('cancel') || long.includes('abandon')) {
    return 'cancelled';
  }
  if (
    ['PST', 'SUSP', 'INT'].includes(short) ||
    long.includes('postpon') ||
    long.includes('suspend') ||
    long.includes('interrupt')
  ) {
    return 'postponed';
  }
  if (['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(short)) return 'live';
  if (['FT', 'AET', 'PEN', 'AWD', 'WO'].includes(short)) return 'completed';
  return homeScore !== null && awayScore !== null ? 'completed' : 'upcoming';
}

export function normalizeApiFootballFixtures(value: unknown): ExternalFootballMatch[] {
  const results: ExternalFootballMatch[] = [];
  for (const item of rows(value)) {
    const fixture = record(item.fixture);
    const league = record(item.league);
    const teams = record(item.teams);
    const home = record(teams?.home);
    const away = record(teams?.away);
    const goals = record(item.goals);
    const providerId = text(fixture?.id);
    const homeTeam = text(home?.name);
    const awayTeam = text(away?.name);
    const kickoff = apiFootballTimestamp(item);
    if (!providerId || !homeTeam || !awayTeam || !kickoff) continue;
    const homeScore = optionalNumberValue(goals?.home);
    const awayScore = optionalNumberValue(goals?.away);
    results.push({
      id: `external_${providerId}`,
      competition_name: text(league?.name) || 'Football',
      home_team_id: text(home?.id),
      away_team_id: text(away?.id),
      home_team: homeTeam,
      away_team: awayTeam,
      home_logo_url: secureImageUrl(home?.logo),
      away_logo_url: secureImageUrl(away?.logo),
      kickoff_at: kickoff.toISOString(),
      predictions_open_at: new Date(kickoff.getTime() - 24 * 60 * 60 * 1000).toISOString(),
      predictions_close_at: kickoff.toISOString(),
      status: apiFootballFixtureStatus(item, homeScore, awayScore),
      home_score: homeScore,
      away_score: awayScore,
      first_scorer: '',
      first_scorer_options: [],
      provider: 'API-Football',
    });
  }
  return results;
}

function teamMatchScore(item: JsonRecord, wantedQuery: string): number {
  const wanted = searchKey(wantedQuery);
  const name = searchKey(item.strTeam);
  const aliases = text(item.strTeamAlternate)
    .split(/[,;/|]/)
    .map(searchKey)
    .filter(Boolean);
  let score = 0;
  if (name && name === wanted) score += 100;
  if (aliases.includes(wanted)) score += 80;
  if (name && (name.startsWith(wanted) || wanted.startsWith(name))) score += 30;
  if (name && (name.includes(wanted) || wanted.includes(name))) score += 15;
  if (secureImageUrl(item.strBadge) || secureImageUrl(item.strTeamBadge)) score += 2;
  return score;
}

export function normalizeFootballTeams(value: unknown, query = ''): FootballTeamSummary[] {
  return rows(value)
    .filter(isFootballTeam)
    .sort((left, right) => teamMatchScore(right, query) - teamMatchScore(left, query))
    .map(item => ({
      teamId: text(item.idTeam),
      name: text(item.strTeam),
      badgeUrl: secureImageUrl(item.strBadge) || secureImageUrl(item.strTeamBadge),
      league: text(item.strLeague) || text(item.strLeague2),
      country: text(item.strCountry),
    }))
    .filter(item => item.teamId.length > 0 && item.name.length > 0);
}

export function normalizeFootballPlayers(value: unknown): FootballPlayerSummary[] {
  return rows(value)
    .map(item => ({
      playerId: text(item.idPlayer),
      teamId: text(item.idTeam),
      team: text(item.strTeam),
      name: text(item.strPlayer),
      position: text(item.strPosition),
      squadNumber: text(item.strNumber) || text(item.intSquadNumber),
      imageUrl: secureImageUrl(item.strCutout) || secureImageUrl(item.strThumb),
      nationality: text(item.strNationality),
    }))
    .filter(item => item.name.length > 0);
}

function apiFootballTeamMatchScore(item: JsonRecord, wantedQuery: string): number {
  const wanted = searchKey(wantedQuery);
  const team = record(item.team);
  const name = searchKey(team?.name);
  let score = 0;
  if (name && name === wanted) score += 100;
  if (name && (name.startsWith(wanted) || wanted.startsWith(name))) score += 30;
  if (name && (name.includes(wanted) || wanted.includes(name))) score += 15;
  if (secureImageUrl(team?.logo)) score += 2;
  return score;
}

export function normalizeApiFootballTeams(
  value: unknown,
  query = '',
): FootballTeamSummary[] {
  return rows(value)
    .sort(
      (left, right) =>
        apiFootballTeamMatchScore(right, query) -
        apiFootballTeamMatchScore(left, query),
    )
    .map((item) => {
      const team = record(item.team);
      return {
        teamId: text(team?.id),
        name: text(team?.name),
        badgeUrl: secureImageUrl(team?.logo),
        league: '',
        country: text(team?.country),
      };
    })
    .filter(item => item.teamId.length > 0 && item.name.length > 0);
}

export function normalizeApiFootballSquads(value: unknown): FootballPlayerSummary[] {
  const results: FootballPlayerSummary[] = [];
  for (const item of rows(value)) {
    const team = record(item.team);
    for (const playerItem of rows(item.players)) {
      results.push({
        playerId: text(playerItem.id),
        teamId: text(team?.id),
        team: text(team?.name),
        name: text(playerItem.name),
        position: text(playerItem.position),
        squadNumber: text(playerItem.number),
        imageUrl: secureImageUrl(playerItem.photo),
        nationality: '',
      });
    }
  }
  return results.filter(item => item.playerId.length > 0 && item.name.length > 0);
}

export function normalizeApiFootballPlayerProfiles(value: unknown): FootballPlayerSummary[] {
  return rows(value)
    .map((item) => {
      const player = record(item.player);
      return {
        playerId: text(player?.id),
        teamId: '',
        team: '',
        name: text(player?.name),
        position: text(player?.position),
        squadNumber: text(player?.number),
        imageUrl: secureImageUrl(player?.photo),
        nationality: text(player?.nationality),
      };
    })
    .filter(item => item.playerId.length > 0 && item.name.length > 0);
}

export function normalizeTimelineType(type: unknown, detail?: unknown): string {
  const combined = `${text(type)} ${text(detail)}`.toLowerCase();
  if (combined.includes('yellow')) return 'yellow_card';
  if (combined.includes('red')) return 'red_card';
  if (combined.includes('substitut') || combined.includes('player change')) return 'sub';
  if (combined.includes('own goal')) return 'own_goal';
  if (combined.includes('penalty') && combined.includes('goal')) return 'penalty_goal';
  if (combined.includes('goal')) return 'goal';
  if (combined.includes('var')) return 'var';
  if (combined.includes('period') || combined.includes('half time')) return 'period';
  return text(type).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'event';
}

export function normalizeExternalMatchDetailsPayload(
  payload: {
    event?: JsonRecord | null;
    timeline?: unknown;
    lineup?: unknown;
    statistics?: unknown;
    standings?: unknown;
  },
  providerLimited = config.sportsDb.apiKey === '123',
): ExternalMatchDetails {
  const event = firstRow(payload.event?.events);
  const homeTeam = text(event?.strHomeTeam).toLowerCase();

  const timeline = rows(payload.timeline).map((item) => {
    const timelineDetail = text(item.strTimelineDetail);
    const comment = text(item.strComment);
    return {
      minute: text(item.intTime),
      type: normalizeTimelineType(item.strTimeline, timelineDetail),
      player: text(item.strPlayer),
      assist: text(item.strAssist),
      detail: [...new Set([timelineDetail, comment].filter(Boolean))].join(' · '),
      team: text(item.strTeam),
      isHome: text(item.strHome).toLowerCase() === 'yes',
    };
  }).sort((left, right) => numberValue(left.minute.split('+')[0]) - numberValue(right.minute.split('+')[0]));

  const lineup = rows(payload.lineup).map((item) => {
    const team = text(item.strTeam);
    const homeFlag = text(item.strHome).toLowerCase();
    const substituteFlag = text(item.strSubstitute ?? item.strSub).toLowerCase();
    return {
      player: text(item.strPlayer),
      team,
      position: text(item.strPosition),
      isHome: homeFlag === 'yes' || (!homeFlag && team.toLowerCase() === homeTeam),
      isSubstitute: substituteFlag === 'yes' || substituteFlag === 'true' || substituteFlag === '1',
      squadNumber: text(item.intSquadNumber) || text(item.strNumber),
      playerImageUrl: secureImageUrl(item.strCutout) || secureImageUrl(item.strThumb),
    };
  }).filter((item) => item.player.length > 0);

  const statistics = rows(payload.statistics).map((item) => ({
    label: text(item.strStat),
    homeValue: text(item.intHome),
    awayValue: text(item.intAway),
  })).filter((item) => item.label.length > 0);

  const standings = rows(payload.standings).map((item) => ({
    rank: numberValue(item.intRank),
    team: text(item.strTeam),
    played: numberValue(item.intPlayed),
    won: numberValue(item.intWin),
    drawn: numberValue(item.intDraw),
    lost: numberValue(item.intLoss),
    goalDifference: numberValue(item.intGoalDifference),
    goalsFor: numberValue(item.intGoalsFor),
    goalsAgainst: numberValue(item.intGoalsAgainst),
    points: numberValue(item.intPoints),
    teamId: text(item.idTeam),
    badgeUrl: secureImageUrl(item.strBadge),
    form: text(item.strForm),
  })).filter((item) => item.team.length > 0);

  return {
    timeline,
    lineup,
    statistics,
    standings,
    venue: text(event?.strVenue),
    season: text(event?.strSeason),
    provider: 'TheSportsDB',
    isProviderLimited: providerLimited,
  };
}

function apiFootballPosition(value: unknown): string {
  switch (text(value).toUpperCase()) {
    case 'G':
      return 'Goalkeeper';
    case 'D':
      return 'Defender';
    case 'M':
      return 'Midfielder';
    case 'F':
    case 'A':
      return 'Forward';
    default:
      return text(value);
  }
}

function apiFootballMinute(value: unknown): string {
  const time = record(value);
  const elapsed = text(time?.elapsed);
  const extra = numberValue(time?.extra);
  return extra > 0 ? `${elapsed}+${extra}` : elapsed;
}

function apiFootballStandings(value: unknown): MatchStandingDetail[] {
  const result: MatchStandingDetail[] = [];
  for (const item of rows(value)) {
    const league = record(item.league);
    const groups = Array.isArray(league?.standings) ? league.standings : [];
    for (const group of groups) {
      for (const standing of rows(group)) {
        const team = record(standing.team);
        const all = record(standing.all);
        const goals = record(all?.goals);
        result.push({
          rank: numberValue(standing.rank),
          team: text(team?.name),
          played: numberValue(all?.played),
          won: numberValue(all?.win),
          drawn: numberValue(all?.draw),
          lost: numberValue(all?.lose),
          goalDifference: numberValue(standing.goalsDiff),
          goalsFor: numberValue(goals?.for),
          goalsAgainst: numberValue(goals?.against),
          points: numberValue(standing.points),
          teamId: text(team?.id),
          badgeUrl: secureImageUrl(team?.logo),
          form: text(standing.form),
        });
      }
    }
  }
  return result.filter(item => item.team.length > 0);
}

export function normalizeApiFootballMatchDetailsPayload(payload: {
  fixture?: unknown;
  events?: unknown;
  lineups?: unknown;
  statistics?: unknown;
  standings?: unknown;
}): ExternalMatchDetails {
  const fixtureItem = firstRow(payload.fixture);
  const fixture = record(fixtureItem?.fixture);
  const league = record(fixtureItem?.league);
  const teams = record(fixtureItem?.teams);
  const homeTeam = record(teams?.home);
  const homeTeamId = text(homeTeam?.id);

  const timeline = rows(payload.events)
    .map((item) => {
      const team = record(item.team);
      const player = record(item.player);
      const assist = record(item.assist);
      const detail = text(item.detail);
      const comment = text(item.comments);
      return {
        minute: apiFootballMinute(item.time),
        type: normalizeTimelineType(item.type, item.detail),
        player: text(player?.name),
        assist: text(assist?.name),
        detail: [...new Set([detail, comment].filter(Boolean))].join(' · '),
        team: text(team?.name),
        isHome: text(team?.id) === homeTeamId,
      };
    })
    .sort(
      (left, right) =>
        numberValue(left.minute.split('+')[0]) -
        numberValue(right.minute.split('+')[0]),
    );

  const lineup: MatchLineupDetail[] = [];
  for (const teamLineup of rows(payload.lineups)) {
    const team = record(teamLineup.team);
    const isHome = text(team?.id) === homeTeamId;
    const appendPlayers = (value: unknown, isSubstitute: boolean) => {
      for (const entry of rows(value)) {
        const player = record(entry.player);
        const playerName = text(player?.name);
        if (!playerName) continue;
        lineup.push({
          player: playerName,
          team: text(team?.name),
          position: apiFootballPosition(player?.pos),
          isHome,
          isSubstitute,
          squadNumber: text(player?.number),
          playerImageUrl: '',
        });
      }
    };
    appendPlayers(teamLineup.startXI, false);
    appendPlayers(teamLineup.substitutes, true);
  }

  const statisticsByLabel = new Map<string, MatchStatisticDetail>();
  for (const [teamIndex, teamStatistics] of rows(payload.statistics).entries()) {
    const team = record(teamStatistics.team);
    const isHome = homeTeamId
      ? text(team?.id) === homeTeamId
      : teamIndex === 0;
    for (const statistic of rows(teamStatistics.statistics)) {
      const label = text(statistic.type);
      if (!label) continue;
      const current = statisticsByLabel.get(label) ?? {
        label,
        homeValue: '',
        awayValue: '',
      };
      if (isHome) current.homeValue = text(statistic.value);
      else current.awayValue = text(statistic.value);
      statisticsByLabel.set(label, current);
    }
  }

  return {
    timeline,
    lineup,
    statistics: [...statisticsByLabel.values()],
    standings: apiFootballStandings(payload.standings),
    venue: text(nestedRecord(fixture, 'venue')?.name),
    season: text(league?.season),
    provider: 'API-Football',
    isProviderLimited: false,
  };
}

type FootballProviderErrorCode =
  | 'configuration'
  | 'daily_budget_exhausted'
  | 'upstream_rate_limited'
  | 'upstream_unavailable'
  | 'invalid_response';

interface CachedFootballProviderError {
  code: FootballProviderErrorCode;
  provider: FootballProviderName;
  endpoint: string;
  upstreamStatus?: number;
}

export interface CachedProviderSection {
  value: JsonRecord | null;
  error?: CachedFootballProviderError;
}

const providerErrorMessages: Record<FootballProviderErrorCode, string> = {
  configuration: 'Football data provider is not configured correctly.',
  daily_budget_exhausted: 'Football data is temporarily unavailable.',
  upstream_rate_limited: 'Football data is temporarily unavailable.',
  upstream_unavailable: 'Football data provider is temporarily unavailable.',
  invalid_response: 'Football data provider returned an invalid response.',
};

export class FootballProviderError extends Error {
  readonly statusCode = 503;

  constructor(
    readonly code: FootballProviderErrorCode,
    readonly provider: FootballProviderName,
    readonly endpoint: string,
    readonly upstreamStatus?: number,
  ) {
    super(providerErrorMessages[code]);
    this.name = 'FootballProviderError';
  }

  toCached(): CachedFootballProviderError {
    return {
      code: this.code,
      provider: this.provider,
      endpoint: this.endpoint,
      ...(this.upstreamStatus === undefined
        ? {}
        : { upstreamStatus: this.upstreamStatus }),
    };
  }

  static fromCached(error: CachedFootballProviderError): FootballProviderError {
    return new FootballProviderError(
      error.code,
      error.provider,
      error.endpoint,
      error.upstreamStatus,
    );
  }
}

interface ActiveFootballProvider {
  name: FootballProviderName;
  apiKey: string;
  baseUrl: string;
  dailyRequestBudget: number;
  featuredTeamIds: string[];
  cacheFingerprint: string;
}

function activeFootballProvider(): ActiveFootballProvider {
  const isApiFootball = config.apiFootball.apiKey.length > 0;
  const apiKey = isApiFootball
    ? config.apiFootball.apiKey
    : config.sportsDb.apiKey;
  const name: FootballProviderName = isApiFootball
    ? 'API-Football'
    : 'TheSportsDB';
  return {
    name,
    apiKey,
    baseUrl: isApiFootball
      ? config.apiFootball.baseUrl
      : 'https://www.thesportsdb.com/api/v1/json',
    dailyRequestBudget: isApiFootball
      ? config.apiFootball.dailyRequestBudget
      : config.sportsDb.dailyRequestBudget,
    featuredTeamIds: isApiFootball
      ? config.apiFootball.featuredTeamIds
      : config.sportsDb.featuredTeamIds,
    // The raw credential never appears in a cache key or a log. Including a
    // short one-way fingerprint prevents a rotated key from inheriting cached
    // errors or data from the previous account.
    cacheFingerprint: createHash('sha256').update(apiKey).digest('hex').slice(0, 12),
  };
}

export function activeFootballProviderName(): FootballProviderName {
  return activeFootballProvider().name;
}

const inFlightSections = new Map<string, Promise<JsonRecord | null>>();
const localProviderSections = new Map<
  string,
  { entry: CachedProviderSection; expiresAt: number }
>();
const maxLocalProviderSections = 512;
let localBudgetDay = '';
let localBudgetCount = 0;

export interface ProviderSectionResolverDependencies {
  read(key: string): Promise<CachedProviderSection | null>;
  write(key: string, entry: CachedProviderSection, ttlSeconds: number): Promise<void>;
  load(): Promise<JsonRecord | null>;
  isNegativeValue?(value: JsonRecord): boolean;
}

export interface SportsDbBudgetReservation {
  allowed: boolean;
  count: number;
  limit: number;
}

export function sportsDbCacheTtlForEndpoint(endpoint: string): number {
  switch (endpoint) {
    case 'eventsnext.php':
    case 'eventslast.php':
    case 'fixtures':
      return config.sportsDb.fixtureCacheTtlSeconds;
    case 'searchteams.php':
    case 'searchplayers.php':
    case 'lookup_all_players.php':
    case 'teams':
    case 'players/profiles':
    case 'players/squads':
      return config.sportsDb.catalogCacheTtlSeconds;
    case 'lookupevent.php':
      return config.sportsDb.eventCacheTtlSeconds;
    case 'lookuplineup.php':
    case 'fixtures/lineups':
      return config.sportsDb.lineupCacheTtlSeconds;
    case 'lookuptable.php':
    case 'standings':
      return config.sportsDb.standingsCacheTtlSeconds;
    case 'lookuptimeline.php':
    case 'lookupeventstats.php':
    case 'fixtures/events':
    case 'fixtures/statistics':
    default:
      return config.sportsDb.liveDataCacheTtlSeconds;
  }
}

export function sportsDbNegativeCacheTtlForEndpoint(endpoint: string): number {
  switch (endpoint) {
    case 'searchteams.php':
    case 'searchplayers.php':
    case 'lookup_all_players.php':
    case 'teams':
    case 'players/profiles':
    case 'players/squads':
      return config.sportsDb.catalogNegativeCacheTtlSeconds;
    default:
      return config.sportsDb.negativeCacheTtlSeconds;
  }
}

function providerCacheKey(endpoint: string, parameters: Record<string, string>): string {
  const normalizedParameters = Object.entries(parameters)
    .sort(([left], [right]) => left.localeCompare(right));
  const provider = activeFootballProvider();
  const digest = createHash('sha256')
    .update(JSON.stringify([
      provider.name,
      provider.cacheFingerprint,
      endpoint,
      normalizedParameters,
    ]))
    .digest('hex');
  // v3 invalidates pre-fix empty lineup envelopes that may still carry the
  // old 30-minute positive TTL after deployment.
  return `cache:football:v3:${digest}`;
}

function setLocalProviderSection(
  key: string,
  entry: CachedProviderSection,
  ttlSeconds: number,
): void {
  if (localProviderSections.size >= maxLocalProviderSections && !localProviderSections.has(key)) {
    const oldestKey = localProviderSections.keys().next().value as string | undefined;
    if (oldestKey) localProviderSections.delete(oldestKey);
  }
  localProviderSections.delete(key);
  localProviderSections.set(key, {
    entry,
    expiresAt: Date.now() + Math.max(1, ttlSeconds) * 1000,
  });
}

async function cachedProviderSection(key: string): Promise<CachedProviderSection | null> {
  const local = localProviderSections.get(key);
  if (local) {
    if (local.expiresAt > Date.now()) return local.entry;
    localProviderSections.delete(key);
  }
  try {
    const cached = await getCachedJson<CachedProviderSection>(key);
    if (cached && Object.prototype.hasOwnProperty.call(cached, 'value')) {
      // Redis remains the durable shared cache. A short L1 copy both reduces
      // Redis traffic and keeps the service stable during a brief reconnect.
      setLocalProviderSection(key, cached, 30);
      return cached;
    }
  } catch {
    // Provider details should remain available if Redis is briefly restarting.
  }
  return null;
}

async function storeProviderSection(
  key: string,
  entry: CachedProviderSection,
  ttlSeconds: number,
): Promise<void> {
  setLocalProviderSection(key, entry, ttlSeconds);
  try {
    await setCachedJson(key, entry, ttlSeconds);
  } catch {
    // The bounded process-local cache remains active while Redis reconnects.
  }
}

function utcBudgetWindow(now: Date): { day: string; expiresAtEpochSeconds: number } {
  const day = now.toISOString().slice(0, 10);
  const expiresAt = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate() + 1,
    1,
  );
  return { day, expiresAtEpochSeconds: Math.floor(expiresAt / 1000) };
}

export function sportsDbDailyCounterKey(now = new Date()): string {
  const { day } = utcBudgetWindow(now);
  const provider = activeFootballProvider();
  const providerName = provider.name === 'API-Football'
    ? 'api-football'
    : 'sportsdb';
  // Keep the quota guard outside the unversioned Redis namespace. Older
  // installations restored their transient quota counter together with the
  // durable Redis archive during a server migration. A stale/corrupt counter
  // could then deny provider requests even though API-Football still reported
  // almost the full daily allowance.
  return `quota:football:v2:${providerName}:${provider.cacheFingerprint}:${day}`;
}

async function reserveRedisSportsDbRequest(
  key: string,
  limit: number,
  expiresAtEpochSeconds: number,
): Promise<SportsDbBudgetReservation> {
  const script = `
    local current = tonumber(redis.call('GET', KEYS[1]) or '0')
    local requestLimit = tonumber(ARGV[1])
    if current >= requestLimit then
      return {0, current}
    end
    local nextValue = redis.call('INCR', KEYS[1])
    if nextValue == 1 then
      redis.call('EXPIREAT', KEYS[1], ARGV[2])
    end
    return {1, nextValue}
  `;
  const result = await redis.eval(
    script,
    1,
    key,
    String(limit),
    String(expiresAtEpochSeconds),
  ) as [number, number];
  return {
    allowed: Number(result[0]) === 1,
    count: Number(result[1]),
    limit,
  };
}

export async function reserveSportsDbDailyRequest(
  now = new Date(),
  reserve = reserveRedisSportsDbRequest,
): Promise<SportsDbBudgetReservation> {
  const provider = activeFootballProvider();
  const limit = provider.dailyRequestBudget;
  const window = utcBudgetWindow(now);
  const key = sportsDbDailyCounterKey(now);
  try {
    return await reserve(key, limit, window.expiresAtEpochSeconds);
  } catch {
    // A Redis restart must not cause a provider stampede. Fall back to a
    // conservative process-local allowance until the shared guard is
    // reachable. Even if Redis fails near the 140k guard, this caps emergency
    // overrun at 1,000 requests per API replica instead of another full day.
    const localLimit = Math.min(limit, 1_000);
    const localBudgetScope = `${provider.name}:${provider.cacheFingerprint}:${window.day}`;
    if (localBudgetDay !== localBudgetScope) {
      localBudgetDay = localBudgetScope;
      localBudgetCount = 0;
    }
    if (localBudgetCount >= localLimit) {
      return { allowed: false, count: localBudgetCount, limit: localLimit };
    }
    localBudgetCount += 1;
    return { allowed: true, count: localBudgetCount, limit: localLimit };
  }
}

async function fetchProviderSection(
  endpoint: string,
  parameters: Record<string, string>,
): Promise<JsonRecord | null> {
  const provider = activeFootballProvider();
  const reservation = await reserveSportsDbDailyRequest();
  if (!reservation.allowed) {
    const error = new FootballProviderError(
      'daily_budget_exhausted',
      provider.name,
      endpoint,
    );
    logFootballProviderError(error);
    throw error;
  }
  const isApiFootball = provider.name === 'API-Football';
  const url = isApiFootball
    ? new URL(endpoint.replace(/^\/+/, ''), `${provider.baseUrl}/`)
    : new URL(
      `${encodeURIComponent(provider.apiKey)}/${endpoint}`,
      `${provider.baseUrl}/`,
    );
  for (const [key, value] of Object.entries(parameters)) {
    url.searchParams.set(key, value);
  }
  try {
    const response = await fetch(url, {
      headers: {
        accept: 'application/json',
        'user-agent': 'Abu3meer/1.1',
        ...(isApiFootball ? { 'x-apisports-key': provider.apiKey } : {}),
      },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) {
      const code: FootballProviderErrorCode =
        response.status === 400 || response.status === 401 || response.status === 403
          ? 'configuration'
          : response.status === 429
            ? 'upstream_rate_limited'
            : 'upstream_unavailable';
      const error = new FootballProviderError(
        code,
        provider.name,
        endpoint,
        response.status,
      );
      logFootballProviderError(error);
      throw error;
    }
    const result: unknown = await response.json();
    const resultRecord = record(result);
    if (!resultRecord) {
      const error = new FootballProviderError(
        'invalid_response',
        provider.name,
        endpoint,
        response.status,
      );
      logFootballProviderError(error);
      throw error;
    }
    if (isApiFootball && apiFootballEnvelopeHasErrors(resultRecord)) {
      const errorKeys = apiFootballEnvelopeErrorKeys(resultRecord);
      const configurationError = errorKeys.some(key =>
        /token|key|access|account|subscription/i.test(key),
      );
      const rateLimitError = errorKeys.some(key => /rate|limit|request/i.test(key));
      const error = new FootballProviderError(
        configurationError
          ? 'configuration'
          : rateLimitError
            ? 'upstream_rate_limited'
            : 'invalid_response',
        provider.name,
        endpoint,
        response.status,
      );
      logFootballProviderError(error);
      throw error;
    }
    return resultRecord;
  } catch (error) {
    if (error instanceof FootballProviderError) throw error;
    const providerError = new FootballProviderError(
      'upstream_unavailable',
      provider.name,
      endpoint,
    );
    logFootballProviderError(providerError);
    throw providerError;
  }
}

function apiFootballEnvelopeErrorKeys(value: JsonRecord): string[] {
  const errors = value.errors;
  if (Array.isArray(errors)) return errors.map(text).filter(Boolean);
  const errorsRecord = record(errors);
  if (errorsRecord) return Object.keys(errorsRecord);
  return text(errors) ? ['unknown'] : [];
}

function apiFootballEnvelopeHasErrors(value: JsonRecord): boolean {
  return apiFootballEnvelopeErrorKeys(value).length > 0;
}

function logFootballProviderError(error: FootballProviderError): void {
  // Deliberately omit URLs, query values, response bodies, and credentials.
  console.error(JSON.stringify({
    event: 'football_provider_request_failed',
    provider: error.provider,
    endpoint: error.endpoint,
    category: error.code,
    ...(error.upstreamStatus === undefined
      ? {}
      : { upstreamStatus: error.upstreamStatus }),
  }));
}

function valueFromCachedProviderSection(
  cached: CachedProviderSection,
): JsonRecord | null {
  if (cached.error) throw FootballProviderError.fromCached(cached.error);
  return cached.value;
}

export async function resolveSharedProviderSection(
  cacheKey: string,
  positiveTtlSeconds: number,
  negativeTtlSeconds: number,
  dependencies: ProviderSectionResolverDependencies,
): Promise<JsonRecord | null> {
  const cached = await dependencies.read(cacheKey);
  if (cached) return valueFromCachedProviderSection(cached);
  const existing = inFlightSections.get(cacheKey);
  if (existing) return existing;
  const request = (async () => {
    const rechecked = await dependencies.read(cacheKey);
    if (rechecked) return valueFromCachedProviderSection(rechecked);
    try {
      const value = await dependencies.load();
      const isNegativeValue = value === null || (
        value !== null && dependencies.isNegativeValue?.(value) === true
      );
      await dependencies.write(
        cacheKey,
        { value },
        isNegativeValue ? negativeTtlSeconds : positiveTtlSeconds,
      );
      return value;
    } catch (error) {
      if (error instanceof FootballProviderError) {
        await dependencies.write(
          cacheKey,
          { value: null, error: error.toCached() },
          Math.min(60, Math.max(1, negativeTtlSeconds)),
        );
      }
      throw error;
    }
  })();
  inFlightSections.set(cacheKey, request);
  try {
    return await request;
  } finally {
    if (inFlightSections.get(cacheKey) === request) {
      inFlightSections.delete(cacheKey);
    }
  }
}

/**
 * Provider envelopes are valid JSON even when a section has not been
 * published yet. Treat those empty arrays/nulls as negative cache hits;
 * otherwise an early lineup request can hide a newly published lineup for the
 * full 30-minute positive TTL.
 */
export function isEmptyProviderSection(value: JsonRecord): boolean {
  const sectionKeys = [
    'response',
    'events',
    'results',
    'timeline',
    'lineup',
    'eventstats',
    'table',
    'teams',
    'player',
    'players',
  ];
  let foundSection = false;
  for (const key of sectionKeys) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
    foundSection = true;
    const section = value[key];
    if (Array.isArray(section) && section.length > 0) return false;
    if (section != null && !Array.isArray(section)) return false;
  }
  return foundSection;
}

async function fetchSection(
  endpoint: string,
  parameters: Record<string, string>,
): Promise<JsonRecord | null> {
  const cacheKey = providerCacheKey(endpoint, parameters);
  return resolveSharedProviderSection(
    cacheKey,
    sportsDbCacheTtlForEndpoint(endpoint),
    sportsDbNegativeCacheTtlForEndpoint(endpoint),
    {
      read: cachedProviderSection,
      write: storeProviderSection,
      load: () => fetchProviderSection(endpoint, parameters),
      isNegativeValue: isEmptyProviderSection,
    },
  );
}

export async function resolveAvailableProviderSections(
  requests: Promise<JsonRecord | null>[],
): Promise<(JsonRecord | null)[]> {
  const settled = await Promise.allSettled(requests);
  const fulfilled = settled.filter(
    (result): result is PromiseFulfilledResult<JsonRecord | null> =>
      result.status === 'fulfilled',
  );
  if (fulfilled.length === 0) {
    const firstFailure = settled.find(
      (result): result is PromiseRejectedResult => result.status === 'rejected',
    );
    throw firstFailure?.reason ?? new Error(
      'Football detail sections are unavailable.',
    );
  }
  return settled.map(
    result => result.status === 'fulfilled' ? result.value : null,
  );
}

export async function fetchExternalMatchDetails(eventId: string): Promise<ExternalMatchDetails> {
  const id = eventId.replace(/^external_/, '').trim();
  if (!id) {
    return activeFootballProviderName() === 'API-Football'
      ? normalizeApiFootballMatchDetailsPayload({})
      : normalizeExternalMatchDetailsPayload({}, config.sportsDb.apiKey === '123');
  }

  if (activeFootballProviderName() === 'API-Football') {
    const fixture = await fetchSection('fixtures', { id, timezone: 'UTC' });
    const fixtureItem = firstRow(fixture?.response);
    const league = record(fixtureItem?.league);
    const leagueId = text(league?.id);
    const season = text(league?.season);
    // Detail sections are independent upstream resources. A temporary failure
    // in statistics or standings must not erase an available live timeline or
    // official lineup. If every section fails, preserve the provider error so
    // callers can retry rather than caching a completely empty result.
    const [events, lineups, statistics, standings] =
      await resolveAvailableProviderSections([
        fetchSection('fixtures/events', { fixture: id }),
        fetchSection('fixtures/lineups', { fixture: id }),
        fetchSection('fixtures/statistics', { fixture: id }),
        leagueId && season
          ? fetchSection('standings', { league: leagueId, season })
          : Promise.resolve(null),
      ]);
    return normalizeApiFootballMatchDetailsPayload({
      fixture: fixture?.response,
      events: events?.response,
      lineups: lineups?.response,
      statistics: statistics?.response,
      standings: standings?.response,
    });
  }

  const event = await fetchSection('lookupevent.php', { id });
  const eventData = firstRow(event?.events);
  const leagueId = text(eventData?.idLeague);
  const season = text(eventData?.strSeason);
  const [timeline, lineup, statistics, standings] =
    await resolveAvailableProviderSections([
      fetchSection('lookuptimeline.php', { id }),
      fetchSection('lookuplineup.php', { id }),
      fetchSection('lookupeventstats.php', { id }),
      leagueId && season
        ? fetchSection('lookuptable.php', { l: leagueId, s: season })
        : Promise.resolve(null),
    ]);

  return normalizeExternalMatchDetailsPayload(
    {
      event,
      timeline: timeline?.timeline,
      lineup: lineup?.lineup,
      statistics: statistics?.eventstats,
      standings: standings?.table,
    },
    config.sportsDb.apiKey === '123',
  );
}

function uniqueMatches(matches: ExternalFootballMatch[]): ExternalFootballMatch[] {
  const byId = new Map<string, ExternalFootballMatch>();
  for (const match of matches) byId.set(match.id, match);
  return [...byId.values()];
}

async function fetchFeaturedTeamEventPayloads(endpoint: 'eventsnext.php' | 'eventslast.php') {
  const teamIds = activeFootballProvider().featuredTeamIds;
  return Promise.all(teamIds.map(id => fetchSection(endpoint, { id })));
}

async function fetchApiFootballFeaturedTeamFixtures(direction: 'next' | 'last') {
  const provider = activeFootballProvider();
  return Promise.all(
    provider.featuredTeamIds.map(team =>
      fetchSection('fixtures', {
        team,
        [direction]: '20',
        timezone: 'UTC',
      }),
    ),
  );
}

export function apiFootballWeekWindow(now: Date, days: number): {
  earliest: number;
  latest: number;
  from: string;
  to: string;
  season: string;
} {
  const boundedDays = Math.max(1, Math.min(days, 14));
  const earliest = now.getTime() - 4 * 60 * 60 * 1000;
  const latest = now.getTime() + (boundedDays * 24 + 12) * 60 * 60 * 1000;
  return {
    earliest,
    latest,
    from: new Date(earliest).toISOString().slice(0, 10),
    to: new Date(latest).toISOString().slice(0, 10),
    // API-Football requires the season alongside team + date-range filters.
    // European competitions use the starting year as their season ID.
    season: String(
      now.getUTCMonth() >= 6 ? now.getUTCFullYear() : now.getUTCFullYear() - 1,
    ),
  };
}

async function fetchApiFootballFeaturedTeamFixtureRange(
  from: string,
  to: string,
  season: string,
) {
  const provider = activeFootballProvider();
  return Promise.all(
    provider.featuredTeamIds.map(team =>
      fetchSection('fixtures', {
        team,
        from,
        to,
        season,
        timezone: 'UTC',
      }),
    ),
  );
}

export async function fetchExternalWeekMatches(days = 7): Promise<ExternalFootballMatch[]> {
  const isApiFootball = activeFootballProviderName() === 'API-Football';
  const window = apiFootballWeekWindow(new Date(), days);
  const payloads = isApiFootball
    // `next` drops a fixture the moment it kicks off. A bounded date range
    // keeps today's live/recent fixture beside upcoming matches, which is the
    // behavior expected by the shared Predict screen.
    ? await fetchApiFootballFeaturedTeamFixtureRange(
        window.from,
        window.to,
        window.season,
      )
    : await fetchFeaturedTeamEventPayloads('eventsnext.php');
  return uniqueMatches(
    payloads.flatMap(payload =>
      isApiFootball
        ? normalizeApiFootballFixtures(payload?.response)
        : normalizeExternalFootballEvents(payload?.events),
    ),
  )
    .filter(match => {
      const kickoff = Date.parse(match.kickoff_at);
      return Number.isFinite(kickoff) &&
        kickoff >= window.earliest &&
        kickoff <= window.latest;
    })
    .sort((left, right) => Date.parse(left.kickoff_at) - Date.parse(right.kickoff_at));
}

export async function fetchExternalRecentMatches(): Promise<ExternalFootballMatch[]> {
  const isApiFootball = activeFootballProviderName() === 'API-Football';
  const payloads = isApiFootball
    ? await fetchApiFootballFeaturedTeamFixtures('last')
    : await fetchFeaturedTeamEventPayloads('eventslast.php');
  return uniqueMatches(
    payloads.flatMap(payload =>
      isApiFootball
        ? normalizeApiFootballFixtures(payload?.response)
        : normalizeExternalFootballEvents(payload?.results ?? payload?.events),
    ),
  ).sort((left, right) => Date.parse(right.kickoff_at) - Date.parse(left.kickoff_at));
}

export async function searchFootballTeams(query: string): Promise<FootballTeamSummary[]> {
  const normalized = text(query).toLowerCase();
  if (normalized.length < 2) return [];
  if (activeFootballProviderName() === 'API-Football') {
    // API-Football requires at least three characters for catalog searches.
    if (normalized.length < 3) return [];
    const payload = await fetchSection('teams', { search: normalized });
    return normalizeApiFootballTeams(payload?.response, normalized);
  }
  const payload = await fetchSection('searchteams.php', { t: normalized });
  return normalizeFootballTeams(payload?.teams, normalized);
}

export async function fetchFootballTeamPlayers(
  teamId: string,
): Promise<FootballPlayerSummary[]> {
  if (!/^\d{3,20}$/.test(teamId)) return [];
  if (activeFootballProviderName() === 'API-Football') {
    const payload = await fetchSection('players/squads', { team: teamId });
    return normalizeApiFootballSquads(payload?.response);
  }
  const payload = await fetchSection('lookup_all_players.php', { id: teamId });
  return normalizeFootballPlayers(payload?.player);
}

export async function searchFootballPlayers(query: string): Promise<FootballPlayerSummary[]> {
  const normalized = text(query).toLowerCase();
  if (normalized.length < 3) return [];
  if (activeFootballProviderName() === 'API-Football') {
    // The profiles endpoint is the only API-Football player search that does
    // not require a league or team filter; it requires four characters.
    if (normalized.length < 4) return [];
    const payload = await fetchSection('players/profiles', { search: normalized });
    return normalizeApiFootballPlayerProfiles(payload?.response);
  }
  const payload = await fetchSection('searchplayers.php', { p: normalized });
  return normalizeFootballPlayers(payload?.player);
}
