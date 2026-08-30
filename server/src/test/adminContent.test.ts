import assert from 'node:assert/strict';
import test from 'node:test';
import {
  calculateLoyaltyRefund,
  canTransitionRedemptionStatus,
  deletePlayerCardDefinition,
  finiteInteger,
  loyaltyRefundTransactionId,
  loyaltyRewardClaimId,
  resetLaunchAnnouncementSetting,
  retireChallengeDefinition,
  safeDocumentId,
  setPlayerCardEnabledState,
  upsertPlayerCardDefinition,
} from '../services/adminContentDomain.js';
import {
  isValidYoutubeVideoId,
  listExclusiveVideos,
  redactExclusiveVideoForViewer,
} from '../services/videoDomain.js';
import { listPlayerCardsForUser } from '../services/playerCardService.js';
import { challengeCreateSchema } from '../routes/adminContentRoutes.js';

test('video challenges accept an omitted Player Card ID', () => {
  const parsed = challengeCreateSchema.safeParse({
    kind: 'videoPhrase',
    title: 'Watch and answer',
    rewardPoints: 10,
    availableFrom: '2026-08-30T18:00:00.000Z',
    availableUntil: '2026-08-31T18:00:00.000Z',
    questions: [{
      id: 'main',
      prompt: 'What happened?',
      type: 'text',
      options: [],
      correctAnswer: 'goal',
      acceptedAnswers: [],
    }],
  });

  assert.equal(parsed.success, true);
  if (parsed.success) assert.equal(parsed.data.playerCardId, '');
});

test('Player Card challenges still require a valid linked card ID', () => {
  const parsed = challengeCreateSchema.safeParse({
    kind: 'playerCard',
    title: 'Guess the player',
    rewardPoints: 10,
    availableFrom: '2026-08-30T18:00:00.000Z',
    availableUntil: '2026-08-31T18:00:00.000Z',
    questions: [{
      id: 'main',
      prompt: 'Who is it?',
      type: 'text',
      options: [],
      correctAnswer: 'player',
      acceptedAnswers: [],
    }],
  });

  assert.equal(parsed.success, false);
});

test('redemption transitions keep fulfilled and cancelled requests terminal', () => {
  assert.equal(canTransitionRedemptionStatus('pending', 'contacted'), true);
  assert.equal(canTransitionRedemptionStatus('pending', 'fulfilled'), true);
  assert.equal(canTransitionRedemptionStatus('contacted', 'pending'), true);
  assert.equal(canTransitionRedemptionStatus('contacted', 'cancelled'), true);
  assert.equal(canTransitionRedemptionStatus('fulfilled', 'cancelled'), false);
  assert.equal(canTransitionRedemptionStatus('cancelled', 'pending'), false);
});

test('cancellation refunds points, stock, and the per-user claim exactly once', () => {
  assert.deepEqual(
    calculateLoyaltyRefund({
      balance: 250,
      cost: 100,
      stock: 4,
      claimCount: 2,
    }),
    { balance: 350, stock: 5, claimCount: 1 },
  );
  assert.deepEqual(
    calculateLoyaltyRefund({
      balance: 0,
      cost: 25,
      stock: null,
      claimCount: 1,
    }),
    { balance: 25, stock: null, claimCount: 0 },
  );
  assert.throws(
    () => calculateLoyaltyRefund({ balance: 0, cost: 25, stock: 0, claimCount: 0 }),
    /Invalid loyalty refund state/,
  );
});

test('server bridge uses the same deterministic Firestore IDs as the legacy callable', () => {
  assert.equal(
    loyaltyRewardClaimId('user-1', 'reward/x'),
    'claim_6-user-1_10-reward%2Fx',
  );
  assert.equal(
    loyaltyRefundTransactionId('redemption/1'),
    'refund_14-redemption%2F1',
  );
});

test('document IDs and stored integers reject unsafe admin input', () => {
  assert.equal(safeDocumentId(' valid-id '), 'valid-id');
  assert.throws(() => safeDocumentId('bad/id'), /ID is invalid/);
  assert.equal(finiteInteger('12', 'Points', 0, 20), 12);
  assert.throws(() => finiteInteger(21, 'Points', 0, 20), /Points is invalid/);
});

test('Player Card deletion returns the deleted row and targets one ID', async () => {
  let sql = '';
  let params: unknown[] | undefined;
  const deleted = await deletePlayerCardDefinition(async (text, values) => {
    sql = text;
    params = values;
    return {
      rowCount: 1,
      rows: [{ id: 'card_1', player_name: 'Test Player', enabled: true }],
    };
  }, 'card_1');

  assert.match(sql, /DELETE FROM player_cards/);
  assert.doesNotMatch(sql, /challenge\.status IN/);
  assert.match(sql, /RETURNING id, player_name/);
  assert.deepEqual(params, ['card_1']);
  assert.equal(deleted.status, 'deleted');
  if (deleted.status === 'deleted') {
    assert.equal(deleted.card.id, 'card_1');
  }
});

test('Player Card deletion reports a missing card without inventing success', async () => {
  const deleted = await deletePlayerCardDefinition(
    async () => ({ rowCount: 0, rows: [] }),
    'missing',
  );
  assert.equal(deleted.status, 'missing');
});

test('claimed Player Cards are retained so collection counters stay correct', async () => {
  let calls = 0;
  const deleted = await deletePlayerCardDefinition(async () => {
    calls += 1;
    return calls === 1
      ? { rowCount: 0, rows: [] }
      : { rowCount: 1, rows: [{ id: 'card_claimed', claim_count: 3 }] };
  }, 'card_claimed');

  assert.equal(deleted.status, 'claimed');
  if (deleted.status === 'claimed') assert.equal(deleted.claimCount, 3);
});

test('Player Cards linked to any challenge state cannot be deleted', async () => {
  let calls = 0;
  const deleted = await deletePlayerCardDefinition(async () => {
    calls += 1;
    return calls === 1
      ? { rowCount: 0, rows: [] }
      : {
          rowCount: 1,
          rows: [{
            id: 'card_live',
            claim_count: 0,
            active_challenge_id: 'challenge_live',
            active_challenge_status: 'open',
          }],
        };
  }, 'card_live');

  assert.deepEqual(deleted, {
    status: 'linked',
    challengeId: 'challenge_live',
    challengeStatus: 'open',
  });
});

test('disabling a Player Card is blocked for every linked challenge state', async () => {
  const statements: string[] = [];
  let calls = 0;
  const update = await setPlayerCardEnabledState(async (text, params) => {
    statements.push(text);
    calls += 1;
    assert.deepEqual(params, calls === 1 ? [false, 'card_scheduled'] : ['card_scheduled']);
    return calls === 1
      ? { rowCount: 0, rows: [] }
      : {
          rowCount: 1,
          rows: [{
            id: 'card_scheduled',
            active_challenge_id: 'challenge_scheduled',
            active_challenge_status: 'scheduled',
          }],
        };
  }, 'card_scheduled', false);

  assert.match(statements[0], /NOT EXISTS/);
  assert.doesNotMatch(statements[0], /challenge\.status IN/);
  assert.deepEqual(update, {
    status: 'linked',
    challengeId: 'challenge_scheduled',
    challengeStatus: 'scheduled',
  });
});

test('Player Card edits preserve server-owned linkage and enabled state', async () => {
  let sql = '';
  let params: unknown[] | undefined;
  const saved = await upsertPlayerCardDefinition(async (text, values) => {
    sql = text;
    params = values;
    return {
      rowCount: 1,
      rows: [{
        id: 'card_linked',
        enabled: true,
        source_challenge_id: 'challenge_existing',
      }],
    };
  }, {
    id: 'card_linked',
    playerName: 'Edited Player',
    normalizedPlayerName: 'edited player',
    playerNameAr: '',
    imageUrl: '',
    teamName: 'RMA',
    teamLogoUrl: '',
    position: 'CM',
    rating: 88,
    rarity: 'rare',
    stats: { passing: 90 },
    description: '',
    descriptionAr: '',
    enabled: false,
  });

  assert.match(sql, /source_challenge_id, updated_at/);
  assert.match(sql, /\$14, '', CURRENT_TIMESTAMP/);
  assert.doesNotMatch(sql, /source_challenge_id = EXCLUDED/);
  assert.doesNotMatch(sql, /enabled = EXCLUDED/);
  assert.equal(params?.length, 14);
  assert.equal(params?.includes('challenge_existing'), false);
  assert.equal(saved.source_challenge_id, 'challenge_existing');
  assert.equal(saved.enabled, true);
});

test('fan Player Card feed exposes only claimed cards or cards in a live challenge', async () => {
  let sql = '';
  let params: unknown[] | undefined;
  const rows = await listPlayerCardsForUser(async (text, values) => {
    sql = text;
    params = values;
    return {
      rowCount: 1,
      rows: [{ id: 'card_owned', enabled: false, unlocked: true }],
    };
  }, 'user_1');

  assert.match(sql, /WHERE claim\.id IS NOT NULL/);
  assert.match(sql, /EXISTS \(/);
  assert.match(sql, /challenge\.status IN \('open', 'scheduled'\)/);
  assert.match(sql, /challenge\.starts_at <= CURRENT_TIMESTAMP/);
  assert.deepEqual(params, ['user_1']);
  assert.deepEqual(rows, [{ id: 'card_owned', enabled: false, unlocked: true }]);
});

test('unused challenge retirement unlinks its Player Card before deletion', async () => {
  const statements: string[] = [];
  const result = await retireChallengeDefinition(async (text, params) => {
    statements.push(text);
    assert.deepEqual(params, ['challenge_test']);
    if (statements.length === 1) {
      return {
        rowCount: 1,
        rows: [{
          id: 'challenge_test',
          title: 'Test',
          kind: 'playerCard',
          status: 'draft',
        }],
      };
    }
    if (statements.length === 2) {
      return { rowCount: 1, rows: [{ id: 'card_test' }] };
    }
    if (statements.length === 3) {
      return {
        rowCount: 1,
        rows: [{ submission_count: 0, claim_count: 0 }],
      };
    }
    return { rowCount: 1, rows: [] };
  }, 'challenge_test');

  assert.equal(result.status, 'retired');
  if (result.status === 'retired') {
    assert.deepEqual(result.playerCardIds, ['card_test']);
  }
  assert.match(statements[0], /FROM challenges/);
  assert.match(statements[0], /FOR UPDATE/);
  assert.match(statements[3], /SET source_challenge_id = ''/);
  assert.match(statements[3], /challenge_id = NULL/);
  assert.match(statements[4], /DELETE FROM challenges/);
});

test('challenge retirement preserves content that already has fan activity', async () => {
  let calls = 0;
  const result = await retireChallengeDefinition(async () => {
    calls += 1;
    if (calls === 1) {
      return {
        rowCount: 1,
        rows: [{ id: 'challenge_used', title: 'Used', kind: 'videoPhrase' }],
      };
    }
    if (calls === 2) return { rowCount: 0, rows: [] };
    return {
      rowCount: 1,
      rows: [{ submission_count: 2, claim_count: 0 }],
    };
  }, 'challenge_used');

  assert.deepEqual(result, {
    status: 'in_use',
    submissionCount: 2,
    claimCount: 0,
  });
  assert.equal(calls, 3);
});

test('launch-popup reset deletes the canonical platform setting', async () => {
  let sql = '';
  const deleted = await resetLaunchAnnouncementSetting(async (text) => {
    sql = text;
    return {
      rowCount: 1,
      rows: [{ key: 'launchAnnouncement', value: { enabled: false } }],
    };
  });

  assert.match(sql, /DELETE FROM platform_settings/);
  assert.match(sql, /key = 'launchAnnouncement'/);
  assert.equal(deleted?.key, 'launchAnnouncement');
});

test('exclusive videos accept only real YouTube ID-shaped values', () => {
  assert.equal(isValidYoutubeVideoId('dQw4w9WgXcQ'), true);
  assert.equal(isValidYoutubeVideoId('u_pHQ5jAoWk'), true);
  assert.equal(isValidYoutubeVideoId('iamr.dev'), false);
  assert.equal(isValidYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ'), false);
});

test('fan video feed excludes scheduled rows while Admin Studio includes them', async () => {
  const statements: string[] = [];
  const execute = async (text: string) => {
    statements.push(text);
    return { rowCount: 0, rows: [] };
  };

  await listExclusiveVideos(execute, { includeScheduled: false });
  await listExclusiveVideos(execute, { includeScheduled: true });

  assert.match(statements[0], /published_at <= CURRENT_TIMESTAMP/);
  assert.match(statements[0], /youtube_id ~/);
  assert.doesNotMatch(statements[1], /published_at <= CURRENT_TIMESTAMP/);
  assert.doesNotMatch(statements[1], /youtube_id ~/);
});

test('Gold-only video links are server-redacted for non-members', () => {
  const memberOnlyVideo = {
    id: 'vid_dQw4w9WgXcQ',
    youtube_id: 'dQw4w9WgXcQ',
    title: 'Members preview',
    description: 'Visible metadata',
    thumbnail_url: 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    video_url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    member_only: true,
  };

  const redacted = redactExclusiveVideoForViewer(memberOnlyVideo, false);
  assert.equal(redacted.id, '');
  assert.equal(redacted.youtube_id, '');
  assert.equal(redacted.thumbnail_url, '');
  assert.equal(redacted.video_url, '');
  assert.equal(redacted.title, 'Members preview');
  assert.equal(redacted.description, 'Visible metadata');

  assert.deepEqual(
    redactExclusiveVideoForViewer(memberOnlyVideo, true),
    memberOnlyVideo,
  );
  assert.equal(
    redactExclusiveVideoForViewer(
      { ...memberOnlyVideo, member_only: false },
      false,
    ).youtube_id,
    'dQw4w9WgXcQ',
  );
});

test('fan list applies Gold redaction while Admin Studio preserves links', async () => {
  const row = {
    id: 'vid_dQw4w9WgXcQ',
    youtube_id: 'dQw4w9WgXcQ',
    thumbnail_url: 'https://example.com/thumb.jpg',
    video_url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    member_only: true,
  };
  const execute = async () => ({ rowCount: 1, rows: [row] });

  const fan = await listExclusiveVideos(execute, {
    includeScheduled: false,
    canAccessMemberOnly: false,
  });
  const admin = await listExclusiveVideos(execute, {
    includeScheduled: true,
    canAccessMemberOnly: true,
  });

  assert.equal(fan[0].youtube_id, '');
  assert.equal(fan[0].video_url, '');
  assert.equal(admin[0].youtube_id, 'dQw4w9WgXcQ');
  assert.equal(admin[0].video_url, row.video_url);
});
