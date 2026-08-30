import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CachedProviderSection,
  FootballProviderError,
  apiFootballWeekWindow,
  isEmptyProviderSection,
  normalizeApiFootballFixtures,
  normalizeApiFootballMatchDetailsPayload,
  normalizeApiFootballPlayerProfiles,
  normalizeApiFootballSquads,
  normalizeApiFootballTeams,
  normalizeExternalFootballEvents,
  normalizeExternalMatchDetailsPayload,
  normalizeFootballPlayers,
  normalizeFootballTeams,
  normalizeTimelineType,
  reserveSportsDbDailyRequest,
  resolveAvailableProviderSections,
  resolveSharedProviderSection,
  sportsDbCacheTtlForEndpoint,
  sportsDbDailyCounterKey,
  sportsDbNegativeCacheTtlForEndpoint,
} from '../services/footballDetailsService.js';

test('normalizes API-Football fixtures into the stable mobile match shape', () => {
  const matches = normalizeApiFootballFixtures([
    {
      fixture: {
        id: 1570360,
        date: '2026-08-30T15:00:00+00:00',
        status: { short: 'NS', long: 'Not Started' },
      },
      league: { id: 140, name: 'La Liga', season: 2026 },
      teams: {
        home: { id: 541, name: 'Real Madrid', logo: 'http://images.example/541.png' },
        away: { id: 529, name: 'Barcelona', logo: 'https://images.example/529.png' },
      },
      goals: { home: null, away: null },
    },
    {
      fixture: {
        id: 1570361,
        date: '2026-09-01T15:00:00+00:00',
        status: { short: '2H', long: 'Second Half' },
      },
      league: { name: 'La Liga' },
      teams: {
        home: { id: 529, name: 'Barcelona' },
        away: { id: 541, name: 'Real Madrid' },
      },
      goals: { home: 1, away: 1 },
    },
  ]);

  assert.equal(matches.length, 2);
  assert.equal(matches[0]?.id, 'external_1570360');
  assert.equal(matches[0]?.provider, 'API-Football');
  assert.equal(matches[0]?.home_team_id, '541');
  assert.equal(matches[0]?.home_logo_url, 'https://images.example/541.png');
  assert.equal(matches[0]?.status, 'upcoming');
  assert.equal(matches[1]?.status, 'live');
  assert.equal(matches[1]?.home_score, 1);
});

test('uses a date range that retains live fixtures in the weekly feed', () => {
  const window = apiFootballWeekWindow(
    new Date('2026-08-30T15:53:00Z'),
    7,
  );
  assert.equal(window.from, '2026-08-30');
  assert.equal(window.to, '2026-09-07');
  assert.equal(window.season, '2026');
  assert.ok(Date.parse('2026-08-30T15:00:00Z') >= window.earliest);
  assert.ok(Date.parse('2026-09-06T14:15:00Z') <= window.latest);

  assert.equal(
    apiFootballWeekWindow(new Date('2027-02-01T12:00:00Z'), 7).season,
    '2026',
  );
});

test('maps API-Football details, standings, teams and player catalogs', () => {
  const details = normalizeApiFootballMatchDetailsPayload({
    fixture: [
      {
        fixture: { venue: { name: 'Bernabéu' } },
        league: { id: 140, season: 2026 },
        teams: {
          home: { id: 541, name: 'Real Madrid' },
          away: { id: 548, name: 'Real Sociedad' },
        },
      },
    ],
    events: [
      {
        time: { elapsed: 45, extra: 2 },
        team: { id: 541, name: 'Real Madrid' },
        player: { name: 'K. Mbappé' },
        assist: { name: 'J. Bellingham' },
        type: 'Goal',
        detail: 'Normal Goal',
      },
    ],
    lineups: [
      {
        team: { id: 541, name: 'Real Madrid' },
        startXI: [{ player: { id: 1, name: 'Starter', number: 10, pos: 'F' } }],
        substitutes: [{ player: { id: 2, name: 'Sub', number: 20, pos: 'M' } }],
      },
    ],
    statistics: [
      {
        team: { id: 541 },
        statistics: [{ type: 'Shots on Goal', value: 11 }],
      },
      {
        team: { id: 548 },
        statistics: [{ type: 'Shots on Goal', value: 3 }],
      },
    ],
    standings: [
      {
        league: {
          standings: [[
            {
              rank: 1,
              team: { id: 541, name: 'Real Madrid', logo: 'https://images.example/541.png' },
              points: 9,
              goalsDiff: 7,
              form: 'WWW',
              all: { played: 3, win: 3, draw: 0, lose: 0, goals: { for: 9, against: 2 } },
            },
          ]],
        },
      },
    ],
  });

  assert.equal(details.provider, 'API-Football');
  assert.equal(details.isProviderLimited, false);
  assert.equal(details.venue, 'Bernabéu');
  assert.equal(details.season, '2026');
  assert.equal(details.timeline[0]?.minute, '45+2');
  assert.equal(details.timeline[0]?.type, 'goal');
  assert.equal(details.timeline[0]?.isHome, true);
  assert.equal(details.lineup[0]?.position, 'Forward');
  assert.equal(details.lineup[1]?.isSubstitute, true);
  assert.equal(details.statistics[0]?.homeValue, '11');
  assert.equal(details.statistics[0]?.awayValue, '3');
  assert.equal(details.standings[0]?.goalsFor, 9);
  assert.equal(details.standings[0]?.goalsAgainst, 2);

  const teams = normalizeApiFootballTeams([
    { team: { id: 541, name: 'Real Madrid', country: 'Spain', logo: 'https://images.example/541.png' } },
  ], 'real madrid');
  assert.equal(teams[0]?.teamId, '541');
  assert.equal(teams[0]?.country, 'Spain');

  const squad = normalizeApiFootballSquads([
    {
      team: { id: 541, name: 'Real Madrid' },
      players: [{ id: 278, name: 'Kylian Mbappé', number: 10, position: 'Attacker', photo: 'https://images.example/278.png' }],
    },
  ]);
  assert.equal(squad[0]?.team, 'Real Madrid');
  assert.equal(squad[0]?.squadNumber, '10');

  const profiles = normalizeApiFootballPlayerProfiles([
    { player: { id: 278, name: 'Kylian Mbappé', position: 'Attacker', nationality: 'France' } },
  ]);
  assert.equal(profiles[0]?.nationality, 'France');
});

test('normalizes provider cards, goals, assists and substitutions', () => {
  assert.equal(normalizeTimelineType('Card', 'Yellow Card'), 'yellow_card');
  assert.equal(normalizeTimelineType('Card', 'Red Card'), 'red_card');
  assert.equal(normalizeTimelineType('Goal', 'Penalty'), 'penalty_goal');
  assert.equal(normalizeTimelineType('Substitution', ''), 'sub');

  const details = normalizeExternalMatchDetailsPayload(
    {
      event: {
        events: [
          {
            strHomeTeam: 'Real Madrid',
            strVenue: 'Santiago Bernabéu',
            strSeason: '2026-2027',
          },
        ],
      },
      timeline: [
        {
          intTime: '12',
          strTimeline: 'Card',
          strTimelineDetail: 'Yellow Card',
          strPlayer: 'Player One',
          strTeam: 'Real Madrid',
          strHome: 'Yes',
          strComment: 'Tripping',
        },
        {
          intTime: '24',
          strTimeline: 'Goal',
          strPlayer: 'Player Two',
          strAssist: 'Player Three',
          strTeam: 'Real Madrid',
          strHome: 'Yes',
        },
      ],
      lineup: [
        {
          strPlayer: 'Goalkeeper',
          strTeam: 'Real Madrid',
          strHome: 'Yes',
          strPosition: 'Goalkeeper',
          strSubstitute: 'No',
          intSquadNumber: '1',
        },
        {
          strPlayer: 'Bench Player',
          strTeam: 'Away FC',
          strHome: 'No',
          strPosition: 'Forward',
          strSubstitute: 'Yes',
          intSquadNumber: '20',
        },
      ],
      statistics: [{ strStat: 'Shots on Goal', intHome: '8', intAway: '3' }],
      standings: [
        {
          intRank: '1',
          strTeam: 'Real Madrid',
          intPlayed: '3',
          intWin: '3',
          intDraw: '0',
          intLoss: '0',
          intGoalDifference: '7',
          intGoalsFor: '9',
          intGoalsAgainst: '2',
          intPoints: '9',
        },
      ],
    },
    true,
  );

  assert.equal(details.timeline[0]?.type, 'yellow_card');
  assert.equal(details.standings[0]?.goalsFor, 9);
  assert.equal(details.standings[0]?.goalsAgainst, 2);
  assert.equal(details.timeline[0]?.detail, 'Yellow Card · Tripping');
  assert.equal(details.timeline[1]?.assist, 'Player Three');
  assert.equal(details.lineup[0]?.isHome, true);
  assert.equal(details.lineup[0]?.isSubstitute, false);
  assert.equal(details.lineup[1]?.isSubstitute, true);
  assert.equal(details.statistics[0]?.homeValue, '8');
  assert.equal(details.standings[0]?.points, 9);
  assert.equal(details.venue, 'Santiago Bernabéu');
  assert.equal(details.season, '2026-2027');
  assert.equal(details.isProviderLimited, true);
});

test('uses short live-data TTLs and longer stable-section TTLs', () => {
  const liveTtl = sportsDbCacheTtlForEndpoint('lookuptimeline.php');
  assert.ok(liveTtl > 0);
  assert.ok(sportsDbCacheTtlForEndpoint('lookupevent.php') > liveTtl);
  assert.ok(sportsDbCacheTtlForEndpoint('lookuplineup.php') > liveTtl);
  assert.ok(sportsDbCacheTtlForEndpoint('lookuptable.php') > liveTtl);
  assert.ok(sportsDbCacheTtlForEndpoint('eventsnext.php') >= liveTtl);
  assert.ok(
    sportsDbCacheTtlForEndpoint('searchteams.php') >
      sportsDbCacheTtlForEndpoint('eventsnext.php'),
  );
  assert.ok(
    sportsDbNegativeCacheTtlForEndpoint('searchteams.php') >
      sportsDbNegativeCacheTtlForEndpoint('lookuptimeline.php'),
  );
});

test('caches valid empty provider envelopes with the short negative TTL', async () => {
  assert.equal(isEmptyProviderSection({ response: [] }), true);
  assert.equal(isEmptyProviderSection({ lineup: null }), true);
  assert.equal(isEmptyProviderSection({ table: [] }), true);
  assert.equal(
    isEmptyProviderSection({ response: [{ fixture: { id: 1 } }] }),
    false,
  );

  const cache = new Map<string, CachedProviderSection>();
  let receivedTtl = 0;
  await resolveSharedProviderSection('test:negative-envelope', 1800, 20, {
    read: async key => cache.get(key) ?? null,
    write: async (key, entry, ttlSeconds) => {
      cache.set(key, entry);
      receivedTtl = ttlSeconds;
    },
    load: async () => ({ response: [] }),
    isNegativeValue: isEmptyProviderSection,
  });
  assert.equal(receivedTtl, 20);
});

test('preserves available detail sections when one upstream section fails', async () => {
  const expected = { response: [{ id: 1 }] };
  const sections = await resolveAvailableProviderSections([
    Promise.resolve(expected),
    Promise.reject(new Error('standings unavailable')),
  ]);
  assert.deepEqual(sections, [expected, null]);

  await assert.rejects(
    resolveAvailableProviderSections([
      Promise.reject(new Error('events unavailable')),
      Promise.reject(new Error('lineups unavailable')),
    ]),
    /events unavailable/,
  );
});

test('normalizes external fixtures into the match shape consumed by mobile clients', () => {
  const matches = normalizeExternalFootballEvents([
    {
      idEvent: '12345',
      idHomeTeam: '133738',
      idAwayTeam: '133739',
      strHomeTeam: 'Real Madrid',
      strAwayTeam: 'Barcelona',
      strLeague: 'Spanish La Liga',
      strTimestamp: '2026-08-30T17:00:00Z',
      intHomeScore: '2',
      intAwayScore: '1',
      strHomeTeamBadge: 'http://images.example/home.png',
      strAwayTeamBadge: '//images.example/away.png',
    },
    { idEvent: 'missing-teams', strTimestamp: '2026-08-30T17:00:00Z' },
  ]);

  assert.equal(matches.length, 1);
  assert.equal(matches[0]?.id, 'external_12345');
  assert.equal(matches[0]?.status, 'completed');
  assert.equal(matches[0]?.home_score, 2);
  assert.equal(matches[0]?.away_score, 1);
  assert.equal(matches[0]?.home_logo_url, 'https://images.example/home.png');
  assert.equal(matches[0]?.away_logo_url, 'https://images.example/away.png');
  assert.equal(matches[0]?.predictions_close_at, matches[0]?.kickoff_at);
  assert.equal(
    Date.parse(matches[0]!.kickoff_at) - Date.parse(matches[0]!.predictions_open_at),
    24 * 60 * 60 * 1000,
  );
});

test('filters non-football teams and returns useful cached player fields', () => {
  const teams = normalizeFootballTeams(
    [
      {
        idTeam: '2',
        strTeam: 'Real Madrid Basketball',
        strSport: 'Basketball',
      },
      {
        idTeam: '1',
        strTeam: 'Real Madrid',
        strSport: 'Soccer',
        strBadge: 'http://images.example/real.png',
        strLeague: 'Spanish La Liga',
        strCountry: 'Spain',
      },
    ],
    'Real Madrid',
  );
  assert.deepEqual(teams, [
    {
      teamId: '1',
      name: 'Real Madrid',
      badgeUrl: 'https://images.example/real.png',
      league: 'Spanish La Liga',
      country: 'Spain',
    },
  ]);

  const players = normalizeFootballPlayers([
    {
      idPlayer: '7',
      idTeam: '1',
      strTeam: 'Real Madrid',
      strPlayer: 'Player One',
      strPosition: 'Forward',
      strNumber: '9',
      strCutout: 'http://images.example/player.png',
      strNationality: 'Spain',
    },
  ]);
  assert.equal(players[0]?.name, 'Player One');
  assert.equal(players[0]?.imageUrl, 'https://images.example/player.png');
});

test('coalesces simultaneous cache misses into one upstream request', async () => {
  const cache = new Map<string, { value: Record<string, unknown> | null }>();
  let loads = 0;
  let writes = 0;
  const key = `test:coalesce:${Date.now()}:${Math.random()}`;
  const dependencies = {
    read: async (cacheKey: string) => cache.get(cacheKey) ?? null,
    write: async (
      cacheKey: string,
      entry: { value: Record<string, unknown> | null },
      _ttlSeconds: number,
    ) => {
      writes += 1;
      cache.set(cacheKey, entry);
    },
    load: async () => {
      loads += 1;
      await new Promise(resolve => setTimeout(resolve, 5));
      return { events: [{ idEvent: 'one' }] };
    },
  };

  const results = await Promise.all(
    Array.from({ length: 12 }, () =>
      resolveSharedProviderSection(key, 300, 20, dependencies),
    ),
  );
  assert.equal(loads, 1);
  assert.equal(writes, 1);
  assert.equal(results.every(result => result?.events != null), true);

  await resolveSharedProviderSection(key, 300, 20, dependencies);
  assert.equal(loads, 1);
});

test('coalesces and briefly caches sanitized provider failures instead of returning empty data', async () => {
  const cache = new Map<string, CachedProviderSection>();
  let loads = 0;
  let writes = 0;
  const key = `test:provider-error:${Date.now()}:${Math.random()}`;
  const dependencies = {
    read: async (cacheKey: string) => cache.get(cacheKey) ?? null,
    write: async (
      cacheKey: string,
      entry: CachedProviderSection,
      _ttlSeconds: number,
    ) => {
      writes += 1;
      cache.set(cacheKey, entry);
    },
    load: async () => {
      loads += 1;
      throw new FootballProviderError(
        'configuration',
        'API-Football',
        'fixtures',
        401,
      );
    },
  };

  const first = await Promise.allSettled(
    Array.from({ length: 8 }, () =>
      resolveSharedProviderSection(key, 300, 20, dependencies),
    ),
  );
  assert.equal(loads, 1);
  assert.equal(writes, 1);
  assert.equal(first.every(result => result.status === 'rejected'), true);
  assert.equal(cache.get(key)?.error?.code, 'configuration');
  assert.equal(cache.get(key)?.error?.provider, 'API-Football');

  await assert.rejects(
    resolveSharedProviderSection(key, 300, 20, dependencies),
    (error: unknown) => {
      assert.ok(error instanceof FootballProviderError);
      assert.equal(error.message, 'Football data provider is not configured correctly.');
      assert.equal(error.message.includes('key'), false);
      return true;
    },
  );
  assert.equal(loads, 1);
});

test('uses a UTC daily shared quota key and honors a denied reservation', async () => {
  const now = new Date('2026-08-29T23:58:00Z');
  assert.match(
    sportsDbDailyCounterKey(now),
    /^quota:football:v2:.*:2026-08-29$/,
  );
  let receivedKey = '';
  let receivedLimit = 0;
  const reservation = await reserveSportsDbDailyRequest(
    now,
    async (key, limit) => {
      receivedKey = key;
      receivedLimit = limit;
      return { allowed: false, count: limit, limit };
    },
  );
  assert.equal(receivedKey, sportsDbDailyCounterKey(now));
  assert.ok(receivedLimit > 0 && receivedLimit < 150_000);
  assert.equal(reservation.allowed, false);
  assert.equal(reservation.count, reservation.limit);

  const redisFallback = await reserveSportsDbDailyRequest(
    now,
    async () => {
      throw new Error('Redis unavailable');
    },
  );
  assert.equal(redisFallback.allowed, true);
  assert.ok(redisFallback.limit <= 1_000);
});
