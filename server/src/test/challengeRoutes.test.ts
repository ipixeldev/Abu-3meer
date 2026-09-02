import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeChallengeActivity } from '../routes/challengeRoutes.js';
import {
  resolveChallengeMembership,
} from '../services/challengeMembershipService.js';
import { memberMultiplierForSource } from '../services/pointsService.js';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

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

test('a stale active member is refreshed before receiving the 2x challenge award', async () => {
  let reads = 0;
  let refreshes = 0;
  const isMember = await resolveChallengeMembership('user-1', {
    queryMembership: async () => ({
      rows: [{ linked: true, current_member: ++reads > 1 }],
    }),
    refreshMembership: async () => {
      refreshes += 1;
      return {
        status: 'verified',
        isYouTubeMember: true,
        cached: false,
        verifiedAt: new Date().toISOString(),
      };
    },
  });

  assert.equal(refreshes, 1);
  assert.equal(isMember, true);
  assert.equal(memberMultiplierForSource('video_phrase', isMember), 2);
});

test('a missing or unreadable CSV falls back to x1 without blocking base XP', async () => {
  const isMember = await resolveChallengeMembership('user-1', {
    queryMembership: async () => ({
      rows: [{ linked: true, current_member: false }],
    }),
    refreshMembership: async () => {
      throw new Error('temporary snapshot read error');
    },
  });
  assert.equal(isMember, false);
  assert.equal(memberMultiplierForSource('video_phrase', isMember), 1);

  const source = await readFile(
    path.resolve(process.cwd(), 'src/routes/challengeRoutes.ts'),
    'utf8',
  );
  assert.ok(
    source.indexOf('resolveChallengeMembership(user.id)') <
      source.indexOf('// Check anti-brute force lock'),
  );
  assert.ok(
    source.indexOf('resolveChallengeMembership(user.id)') <
      source.indexOf('const result = await submitChallengeAnswer('),
  );
  assert.doesNotMatch(source, /YouTubeMembershipUnavailable/);
});
