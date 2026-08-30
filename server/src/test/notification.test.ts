import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  isPermanentPushTokenError,
  isTransientPushError,
  isUnclassifiedPushTransportFailure,
  normalizePushData,
  notificationDelayMs,
  notificationPreferenceColumn,
  safePushFailureCode,
  summarizePushFailureCodes,
  summarizePushFailures,
} from '../services/notificationDomain.js';
import { exclusiveVideoNotificationCampaign } from '../services/exclusiveVideoNotification.js';
import {
  cancelNotificationCampaignBySource,
  createNotificationCampaign,
} from '../services/notificationService.js';
import {
  challengeNotificationCampaign,
  shouldScheduleChallengeNotification,
} from '../services/challengeNotification.js';

describe('push notification domain', () => {
  it('normalizes every FCM data value to a string and omits nulls', () => {
    assert.deepEqual(
      normalizePushData({ route: '/matches/1', matchId: 42, urgent: true, empty: null }),
      { route: '/matches/1', matchId: '42', urgent: 'true' }
    );
  });

  it('only deactivates permanently invalid provider tokens', () => {
    assert.equal(isPermanentPushTokenError('messaging/registration-token-not-registered'), true);
    assert.equal(isPermanentPushTokenError('messaging/invalid-registration-token'), true);
    assert.equal(isPermanentPushTokenError('messaging/mismatched-credential'), true);
    assert.equal(isPermanentPushTokenError('messaging/internal-error'), false);
  });

  it('retries transient provider failures without retrying permanent tokens or credentials', () => {
    assert.equal(isTransientPushError('messaging/internal-error'), true);
    assert.equal(isTransientPushError('messaging/server-unavailable'), true);
    assert.equal(isTransientPushError('messaging/quota-exceeded'), true);
    assert.equal(isTransientPushError('messaging/transport-error'), true);
    assert.equal(isTransientPushError('messaging/registration-token-not-registered'), false);
    assert.equal(isTransientPushError('messaging/third-party-auth-error'), false);
  });

  it('summarizes provider failures without including tokens or messages', () => {
    assert.deepEqual(
      summarizePushFailureCodes([
        'messaging/third-party-auth-error',
        'messaging/third-party-auth-error',
        undefined,
      ]),
      {
        failureCodes: ['messaging/third-party-auth-error'],
        requiresTokenRefresh: false,
        providerConfigurationError: true,
      }
    );
    assert.deepEqual(summarizePushFailureCodes(['messaging/mismatched-credential']), {
      failureCodes: ['messaging/mismatched-credential'],
      requiresTokenRefresh: true,
      providerConfigurationError: false,
    });
    assert.deepEqual(summarizePushFailureCodes(['messaging/unknown-error']), {
      failureCodes: ['messaging/unknown-error'],
      requiresTokenRefresh: true,
      providerConfigurationError: false,
    });
  });

  it('extracts Firebase errors from getters, JSON, errorInfo, and safe message hints', () => {
    const getterError = Object.create(null, {
      code: { get: () => 'messaging/third-party-auth-error' },
    });
    assert.equal(safePushFailureCode(getterError), 'messaging/third-party-auth-error');
    assert.equal(
      safePushFailureCode({ toJSON: () => ({ code: 'messaging/mismatched-credential' }) }),
      'messaging/mismatched-credential'
    );
    assert.equal(
      safePushFailureCode({ errorInfo: { code: 'messaging/internal-error' } }),
      'messaging/internal-error'
    );
    assert.equal(
      safePushFailureCode({ message: 'APNS_AUTH_ERROR from upstream provider' }),
      'messaging/third-party-auth-error'
    );
    assert.equal(
      safePushFailureCode({ message: 'Requested entity was not found.' }),
      'messaging/registration-token-not-registered'
    );
    assert.equal(
      safePushFailureCode({ code: 'APNS_AUTH_ERROR' }),
      'messaging/third-party-auth-error'
    );
    assert.equal(
      safePushFailureCode({ code: 'UNREGISTERED' }),
      'messaging/registration-token-not-registered'
    );
    assert.equal(safePushFailureCode({}), 'messaging/unknown-error');
    assert.equal(isUnclassifiedPushTransportFailure({}), true);
    assert.equal(isUnclassifiedPushTransportFailure({ code: 'ECONNRESET' }), true);
    assert.equal(isUnclassifiedPushTransportFailure({ code: 'ERR_HTTP2_STREAM_ERROR' }), true);
    assert.equal(
      isUnclassifiedPushTransportFailure({ code: 'messaging/ERR_HTTP2_SESSION_ERROR' }),
      true
    );
    assert.equal(
      safePushFailureCode({ code: 'messaging/ERR_HTTP2_SESSION_ERROR' }),
      'messaging/transport-error'
    );
    assert.equal(
      isUnclassifiedPushTransportFailure({ code: 'messaging/unknown-error' }),
      false
    );
    assert.equal(
      isUnclassifiedPushTransportFailure({ message: 'APNS_AUTH_ERROR from provider' }),
      false
    );
    assert.deepEqual(summarizePushFailures([{}, undefined]), {
      failureCodes: ['messaging/unknown-error'],
      requiresTokenRefresh: true,
      providerConfigurationError: false,
    });
  });

  it('maps campaign categories to user preference columns', () => {
    assert.equal(notificationPreferenceColumn('match'), 'match_enabled');
    assert.equal(notificationPreferenceColumn('challenge'), 'challenge_enabled');
    assert.equal(notificationPreferenceColumn('general'), null);
  });

  it('clamps notification schedule delays and rejects invalid dates safely', () => {
    const now = Date.parse('2026-08-30T12:00:00.000Z');
    assert.equal(
      notificationDelayMs(new Date('2026-08-30T12:15:00.000Z'), now),
      15 * 60 * 1000
    );
    assert.equal(
      notificationDelayMs(new Date('2026-08-30T11:00:00.000Z'), now),
      0
    );
    assert.equal(notificationDelayMs(new Date('invalid'), now), 0);
  });

  it('builds a preference-aware, deduplicated Exclusive video campaign', () => {
    const publishedAt = new Date('2026-09-01T18:00:00.000Z');
    const campaign = exclusiveVideoNotificationCampaign({
      videoId: 'vid_abc123',
      youtubeId: 'abc123',
      title: 'Members preview',
      thumbnailUrl: 'https://api.abu3meer.com/uploads/announcement/cover.jpg',
      publishedAt,
      memberOnly: true,
      createdBy: 'admin-id',
    });

    assert.equal(campaign.category, 'challenge');
    assert.equal(campaign.targetAudience, 'members_only');
    assert.equal(campaign.imageUrl, 'https://api.abu3meer.com/uploads/announcement/cover.jpg');
    assert.equal(campaign.scheduledFor, publishedAt);
    assert.equal(campaign.sourceType, 'exclusive_video');
    assert.equal(campaign.sourceId, 'vid_abc123');
    assert.deepEqual(campaign.data, {
      route: '/exclusive',
      videoId: 'vid_abc123',
      youtubeId: 'abc123',
    });
  });

  it('omits an unsafe non-HTTPS Exclusive video notification image', () => {
    const campaign = exclusiveVideoNotificationCampaign({
      videoId: 'vid_abc123',
      youtubeId: 'abc123',
      title: 'Public preview',
      thumbnailUrl: 'http://localhost/cover.jpg',
      publishedAt: new Date('2026-09-01T18:00:00.000Z'),
      memberOnly: false,
      createdBy: 'admin-id',
    });
    assert.equal(campaign.targetAudience, 'all');
    assert.equal(campaign.imageUrl, null);
  });

  it('schedules a new challenge notification for its future live time', () => {
    const now = new Date('2026-08-30T12:00:00.000Z');
    const startsAt = new Date('2026-08-30T14:00:00.000Z');
    const campaign = challengeNotificationCampaign({
      challengeId: 'challenge_123',
      title: 'Guess the player',
      imageUrl: 'https://api.abu3meer.com/uploads/challenge/card.jpg',
      startsAt,
      status: 'scheduled',
      memberOnly: true,
      createdBy: 'admin-id',
    }, now);

    assert.equal(campaign.category, 'challenge');
    assert.equal(campaign.targetAudience, 'members_only');
    assert.equal(campaign.scheduledFor, startsAt);
    assert.equal(campaign.sourceType, 'challenge');
    assert.equal(campaign.sourceId, 'challenge_123');
    assert.deepEqual(campaign.data, {
      route: '/challenges',
      challengeId: 'challenge_123',
    });
  });

  it('sends an already-live challenge immediately to its eligible audience', () => {
    const now = new Date('2026-08-30T12:00:00.000Z');
    const campaign = challengeNotificationCampaign({
      challengeId: 'challenge_456',
      title: 'Video phrase',
      imageUrl: '',
      startsAt: new Date('2026-08-30T11:00:00.000Z'),
      status: 'open',
      memberOnly: false,
      createdBy: 'admin-id',
    }, now);

    assert.equal(campaign.targetAudience, 'all');
    assert.equal(campaign.scheduledFor, now);
    assert.equal(campaign.imageUrl, null);
  });

  it('only schedules challenge notifications for open or scheduled content', () => {
    assert.equal(shouldScheduleChallengeNotification(true, 'scheduled'), true);
    assert.equal(shouldScheduleChallengeNotification(true, 'open'), true);
    assert.equal(shouldScheduleChallengeNotification(true, 'draft'), false);
    assert.equal(shouldScheduleChallengeNotification(true, 'disabled'), false);
    assert.equal(shouldScheduleChallengeNotification(true, 'archived'), false);
    assert.equal(shouldScheduleChallengeNotification(false, 'open'), false);
    assert.throws(
      () => challengeNotificationCampaign({
        challengeId: 'draft_1',
        title: 'Draft',
        imageUrl: '',
        startsAt: new Date('2026-08-31T12:00:00.000Z'),
        status: 'draft',
        memberOnly: false,
        createdBy: 'admin-id',
      }),
      /cannot create a notification campaign/,
    );
  });

  it('queues an explicitly open challenge immediately even if its start time is future', () => {
    const now = new Date('2026-08-30T12:00:00.000Z');
    const campaign = challengeNotificationCampaign({
      challengeId: 'challenge_open',
      title: 'Open now',
      imageUrl: '',
      startsAt: new Date('2026-08-31T12:00:00.000Z'),
      status: 'open',
      memberOnly: false,
      createdBy: 'admin-id',
    }, now);
    assert.equal(campaign.scheduledFor, now);
  });

  it('re-arms a cancelled source campaign instead of duplicating it', async () => {
    const statements: string[] = [];
    const scheduledFor = new Date('2026-08-31T12:00:00.000Z');
    const result = await createNotificationCampaign(
      {
        title: 'Abu 3meer',
        body: 'Challenge live',
        category: 'challenge',
        scheduledFor,
        sourceType: 'challenge',
        sourceId: 'challenge_1',
      },
      async (text) => {
        statements.push(text);
        if (statements.length === 1) return { rowCount: 0, rows: [] };
        return {
          rowCount: 1,
          rows: [{ id: 'campaign_1', scheduled_for: scheduledFor }],
        };
      },
    );
    assert.equal(result.campaignId, 'campaign_1');
    assert.equal(result.created, false);
    assert.match(statements[1], /status IN \('pending', 'failed', 'cancelled'\)/);
  });

  it('cancels only unsent source campaigns', async () => {
    let statement = '';
    const ids = await cancelNotificationCampaignBySource(
      'challenge',
      'challenge_1',
      async (text) => {
        statement = text;
        return { rowCount: 1, rows: [{ id: 'campaign_1' }] };
      },
    );
    assert.deepEqual(ids, ['campaign_1']);
    assert.match(statement, /status = 'cancelled'/);
    assert.match(statement, /status IN \('pending', 'failed', 'processing'\)/);
  });
});
