import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeChallengeActivity } from '../routes/challengeRoutes.js';

test('active challenge cache is decorated with only the current user activity', () => {
  const cached = [
    { id: 'guess_1', title: 'Guess one' },
    { id: 'guess_2', title: 'Guess two' },
  ];
  const merged = mergeChallengeActivity(cached, [
    { challenge_id: 'guess_1', attempts_used: 2, solved: true },
  ]);

  assert.deepEqual(merged, [
    { id: 'guess_1', title: 'Guess one', attempts_used: 2, solved: true },
    { id: 'guess_2', title: 'Guess two', attempts_used: 0, solved: false },
  ]);
  assert.equal('attempts_used' in cached[0], false);
});
