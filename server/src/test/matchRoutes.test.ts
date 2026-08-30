import assert from 'node:assert/strict';
import test from 'node:test';

import { matchDetailsCacheTtlSeconds } from '../routes/matchRoutes.js';

test('external and live match details refresh on the live-data cadence', () => {
  assert.equal(matchDetailsCacheTtlSeconds('external_1570360'), 20);
  assert.equal(matchDetailsCacheTtlSeconds('managed-one', 'live'), 20);
  assert.equal(matchDetailsCacheTtlSeconds('managed-one', 'completed'), 120);
});
