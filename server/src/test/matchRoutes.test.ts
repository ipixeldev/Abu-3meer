import assert from 'node:assert/strict';
import test from 'node:test';

import {
  matchDetailsCacheTtlSeconds,
  retainPublishedMatchDetails,
  serializeMatchDetailPublication,
} from '../routes/matchRoutes.js';
import { ExternalMatchDetails } from '../services/footballDetailsService.js';

test('external and live match details refresh on the live-data cadence', () => {
  assert.equal(matchDetailsCacheTtlSeconds('external_1570360'), 20);
  assert.equal(matchDetailsCacheTtlSeconds('managed-one', 'live'), 20);
  assert.equal(matchDetailsCacheTtlSeconds('managed-one', 'completed'), 120);
});

test('empty refresh retains previously published match sections and score', () => {
  const base: ExternalMatchDetails = {
    timeline: [{ minute: '90', type: 'goal', player: 'Player', assist: '', detail: '', team: 'Home', isHome: true }],
    lineup: [{ player: 'Player', team: 'Home', position: 'Forward', isHome: true, isSubstitute: false, squadNumber: '9', playerImageUrl: '' }],
    statistics: [{ label: 'Shots', homeValue: '10', awayValue: '4' }],
    standings: [{ rank: 1, team: 'Home', played: 3, won: 3, drawn: 0, lost: 0, goalDifference: 5, goalsFor: 7, goalsAgainst: 2, points: 9, teamId: '1', badgeUrl: '', form: 'WWW' }],
    venue: 'Ground', season: '2026', provider: 'API-Football',
    isProviderLimited: false, status: 'completed', homeScore: 2, awayScore: 1,
  };
  const empty: ExternalMatchDetails = {
    timeline: [], lineup: [], statistics: [], standings: [], venue: '',
    season: '', provider: 'API-Football', isProviderLimited: false,
    status: '', homeScore: null, awayScore: null,
  };

  assert.deepEqual(retainPublishedMatchDetails(base, empty), base);
});

test('shorter nonempty provider snapshots cannot retract published detail rows', () => {
  const base: ExternalMatchDetails = {
    timeline: [
      { minute: '12', type: 'goal', player: 'First', assist: '', detail: '', team: 'Home', isHome: true },
      { minute: '70', type: 'goal', player: 'Second', assist: '', detail: '', team: 'Away', isHome: false },
    ],
    lineup: [
      { player: 'Home Starter', team: 'Home', position: 'Forward', isHome: true, isSubstitute: false, squadNumber: '9', playerImageUrl: '' },
      { player: 'Away Starter', team: 'Away', position: 'Keeper', isHome: false, isSubstitute: false, squadNumber: '1', playerImageUrl: '' },
    ],
    statistics: [
      { label: 'Shots', homeValue: '10', awayValue: '4' },
      { label: 'Possession', homeValue: '60%', awayValue: '40%' },
    ],
    standings: [
      { rank: 1, team: 'Home', played: 3, won: 3, drawn: 0, lost: 0, goalDifference: 5, goalsFor: 7, goalsAgainst: 2, points: 9, teamId: '1', badgeUrl: '', form: 'WWW' },
      { rank: 2, team: 'Away', played: 3, won: 2, drawn: 0, lost: 1, goalDifference: 2, goalsFor: 5, goalsAgainst: 3, points: 6, teamId: '2', badgeUrl: '', form: 'WWL' },
    ],
    venue: 'Ground', season: '2026', provider: 'API-Football',
    isProviderLimited: false, status: 'completed', homeScore: 2, awayScore: 1,
  };
  const delayed: ExternalMatchDetails = {
    ...base,
    timeline: [{ ...base.timeline[0]!, assist: 'Provider correction' }],
    lineup: [{ ...base.lineup[0]!, playerImageUrl: 'https://images.example/home.png' }],
    statistics: [{ label: 'Shots', homeValue: '10', awayValue: '4' }],
    standings: [{ ...base.standings[0]!, form: 'WWW' }],
  };

  const retained = retainPublishedMatchDetails(base, delayed);
  assert.equal(retained.timeline.length, 2);
  assert.equal(retained.timeline[0]?.assist, 'Provider correction');
  assert.equal(retained.lineup.length, 2);
  assert.equal(retained.lineup[0]?.playerImageUrl, 'https://images.example/home.png');
  assert.equal(retained.statistics.length, 2);
  assert.equal(retained.standings.length, 2);
});

test('same-match publication turns cannot race a shorter snapshot over a complete one', async () => {
  const calls: string[] = [];
  let releaseFirst!: () => void;
  const firstGate = new Promise<void>(resolve => { releaseFirst = resolve; });

  const first = serializeMatchDetailPublication('external_1', async () => {
    calls.push('first:start');
    await firstGate;
    calls.push('first:end');
    return 'complete';
  });
  const second = serializeMatchDetailPublication('external_1', async () => {
    calls.push('second');
    return 'short';
  });

  await new Promise<void>(resolve => setImmediate(resolve));
  assert.deepEqual(calls, ['first:start']);
  releaseFirst();
  assert.deepEqual(await Promise.all([first, second]), ['complete', 'short']);
  assert.deepEqual(calls, ['first:start', 'first:end', 'second']);
});
