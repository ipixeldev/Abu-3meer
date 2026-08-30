import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  deriveMatchWindow,
  evaluatePrediction,
} from '../services/predictionService.js';
import { parsePredictionInputPayload } from '../services/predictionInput.js';

describe('prediction native-client compatibility', () => {
  it('normalizes legacy Android string, snake-case, and Unix timestamp values', () => {
    const result = parsePredictionInputPayload({
      match_id: 'external_123',
      home_score: '2',
      away_score: '0',
      first_scorer: null,
      home_team: 'Barcelona',
      away_team: 'Away FC',
      competition_name: 'La Liga',
      kickoff_at: 1788123600,
    });

    assert.equal(result.success, true);
    if (!result.success) return;
    assert.equal(result.data.homeScore, 2);
    assert.equal(result.data.awayScore, 0);
    assert.equal(result.data.firstScorer, 'No scorer');
    assert.match(result.data.kickoffAt || '', /Z$/);
  });

  it('ignores removed legacy both-teams-score input', () => {
    const result = parsePredictionInputPayload({
      matchId: 'external_123',
      homeScore: 1,
      awayScore: 1,
      bothTeamsScore: 'not-a-boolean',
    });
    assert.equal(result.success, true);
    if (!result.success) return;
    assert.equal('bothTeamsScore' in result.data, false);
  });
});

describe('prediction persistence match window', () => {
  it('creates every required scheduling value for an external fixture', () => {
    const now = new Date('2026-08-27T10:00:00.000Z');
    const result = deriveMatchWindow('2026-08-27T21:00:00.000Z', now);

    assert.equal(result.kickoffAt.toISOString(), '2026-08-27T21:00:00.000Z');
    assert.equal(
      result.predictionsCloseAt.toISOString(),
      '2026-08-27T20:55:00.000Z',
    );
    assert.equal(result.status, 'open');
    assert.ok(result.predictionsOpenAt < now);
  });

  it('rejects invalid and already-closed fixture times', () => {
    const now = new Date('2026-08-27T21:00:00.000Z');
    assert.throws(
      () => deriveMatchWindow('not-a-date', now),
      /kickoff time is invalid/,
    );
    assert.throws(
      () => deriveMatchWindow('2026-08-27T21:04:00.000Z', now),
      /window is closed/,
    );
  });
});

describe('prediction outcome evaluation', () => {
  it('evaluates exact score, winner, and scorer', () => {
    assert.deepEqual(
      evaluatePrediction({
        predictedHome: 2,
        predictedAway: 1,
        predictedFirstScorer: 'Lamine Yamal',
        actualHome: 2,
        actualAway: 1,
        actualFirstScorer: 'Lamine Yamal',
      }),
      {
        isExact: true,
        isFirstScorer: true,
        isWinner: true,
      },
    );
  });

  it('never treats a blank scorer as correct', () => {
    const result = evaluatePrediction({
      predictedHome: 2,
      predictedAway: 0,
      predictedFirstScorer: '',
      actualHome: 3,
      actualAway: 0,
      actualFirstScorer: 'Vinicius Junior',
    });

    assert.equal(result.isExact, false);
    assert.equal(result.isFirstScorer, false);
    assert.equal(result.isWinner, true);
  });

  it('requires the exact normalized scorer option instead of a substring', () => {
    const partial = evaluatePrediction({
      predictedHome: 1,
      predictedAway: 0,
      predictedFirstScorer: 'Junior',
      actualHome: 1,
      actualAway: 0,
      actualFirstScorer: 'Vinicius Junior',
    });
    const canonical = evaluatePrediction({
      predictedHome: 1,
      predictedAway: 0,
      predictedFirstScorer: '  VINICIUS   JUNIOR ',
      actualHome: 1,
      actualAway: 0,
      actualFirstScorer: 'Vinicius Junior',
    });

    assert.equal(partial.isFirstScorer, false);
    assert.equal(canonical.isFirstScorer, true);
  });

  it('settles a 0-0 No scorer prediction as exact, scorer, and draw', () => {
    assert.deepEqual(
      evaluatePrediction({
        predictedHome: 0,
        predictedAway: 0,
        predictedFirstScorer: 'No scorer',
        actualHome: 0,
        actualAway: 0,
        actualFirstScorer: 'No scorer',
      }),
      {
        isExact: true,
        isFirstScorer: true,
        isWinner: true,
      },
    );
  });
});
