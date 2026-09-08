import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import Fastify from 'fastify';
import {
  isPermanentPushTokenError,
  isProviderConfigurationPushError,
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
  claimNotificationDeliveryDevices,
  createNotificationCampaign,
  getNotificationCampaignStatus,
  lockNotificationCampaignForDispatch,
  recordNotificationDeliveryOutcome,
  revokeDeviceInstallation,
} from '../services/notificationService.js';
import {
  challengeNotificationCampaign,
  shouldScheduleChallengeNotification,
} from '../services/challengeNotification.js';
import { predictionResultNotificationCampaign } from '../services/predictionResultNotification.js';
import { adminRoutes } from '../routes/adminRoutes.js';

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

  it('recognizes project-level APNs credential failures without blaming device tokens', () => {
    assert.equal(isProviderConfigurationPushError('messaging/third-party-auth-error'), true);
    assert.equal(isProviderConfigurationPushError('messaging/invalid-apns-credentials'), true);
    assert.equal(isProviderConfigurationPushError('messaging/mismatched-credential'), false);
    assert.equal(isPermanentPushTokenError('messaging/third-party-auth-error'), false);
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

  it('does not announce an explicitly open challenge before its future start time', () => {
    const now = new Date('2026-08-30T12:00:00.000Z');
    const startsAt = new Date('2026-08-31T12:00:00.000Z');
    const campaign = challengeNotificationCampaign({
      challengeId: 'challenge_open',
      title: 'Open now',
      imageUrl: '',
      startsAt,
      status: 'open',
      memberOnly: false,
      createdBy: 'admin-id',
    }, now);
    assert.equal(campaign.scheduledFor, startsAt);
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
    assert.match(statements[1], /status = 'cancelled'/);
  });

  it('never re-arms a cancelled manual broadcast during idempotent replay', async () => {
    const statements: string[] = [];
    const scheduledFor = new Date('2026-08-31T12:00:00.000Z');
    const result = await createNotificationCampaign(
      {
        title: 'Manual announcement',
        body: 'One logical send',
        category: 'general',
        scheduledFor,
        sourceType: 'admin_broadcast',
        sourceId: 'admin_1:attempt_1',
      },
      async (text) => {
        statements.push(text);
        if (statements.length === 1) return { rowCount: 0, rows: [] };
        return { rowCount: 0, rows: [] };
      },
      { rearmCancelled: false },
    );

    assert.equal(result.campaignId, null);
    assert.equal(result.scheduledFor, scheduledFor);
    assert.equal(statements.length, 2);
    assert.equal(statements.some(statement => /status = 'cancelled'/.test(statement)), false);
  });

  it('reuses a failed source only while its persisted retry budget remains', async () => {
    const statements: string[] = [];
    const scheduledFor = new Date('2026-08-31T12:00:00.000Z');
    const result = await createNotificationCampaign(
      {
        title: 'Prediction result',
        body: 'Result ready',
        category: 'match',
        sourceType: 'prediction_result',
        sourceId: 'prediction_1',
      },
      async (text) => {
        statements.push(text);
        if (statements.length < 3) return { rowCount: 0, rows: [] };
        return {
          rowCount: 1,
          rows: [{ id: 'campaign_1', scheduled_for: scheduledFor }],
        };
      },
    );
    assert.equal(result.campaignId, 'campaign_1');
    assert.equal(statements.length, 3);
    assert.match(statements[2], /attempt_count < \$3/);
  });

  it('does not re-arm an exhausted failed source campaign', async () => {
    let statements = 0;
    const result = await createNotificationCampaign(
      {
        title: 'Prediction result',
        body: 'Result ready',
        category: 'match',
        sourceType: 'prediction_result',
        sourceId: 'prediction_1',
      },
      async () => {
        statements += 1;
        return { rowCount: 0, rows: [] };
      },
    );
    assert.equal(statements, 3);
    assert.equal(result.campaignId, null);
  });

  it('targets one prediction owner with a source-deduplicated result alert', () => {
    const campaign = predictionResultNotificationCampaign({
      predictionId: 'prediction_1',
      userId: 'user_1',
      matchId: 'external_123',
      homeTeam: 'Real Madrid',
      awayTeam: 'Malaga',
      homeScore: 2,
      awayScore: 1,
      pointsAwarded: 60,
    });
    assert.equal(campaign.targetAudience, 'user_specific');
    assert.equal(campaign.targetUserId, 'user_1');
    assert.equal(campaign.sourceType, 'prediction_result');
    assert.equal(campaign.sourceId, 'prediction_1');
    assert.deepEqual(campaign.data, {
      route: '/predict',
      matchId: 'external_123',
      predictionId: 'prediction_1',
    });
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

  it('reserves deliveries before FCM and never reclaims sent or processing rows', async () => {
    let statement = '';
    let parameters: any[] = [];
    const devices = [
      { id: '00000000-0000-0000-0000-000000000001', fcm_token: 'token-1' },
      { id: '00000000-0000-0000-0000-000000000002', fcm_token: 'token-2' },
    ];
    const claimed = await claimNotificationDeliveryDevices(
      '00000000-0000-0000-0000-000000000010',
      devices,
      async (text, params) => {
        statement = text;
        parameters = params ?? [];
        return {
          rowCount: 1,
          rows: [{ device_id: devices[1].id }],
        };
      },
    );

    assert.deepEqual(claimed, [devices[1]]);
    assert.deepEqual(parameters[1], devices.map(device => device.id));
    assert.match(statement, /'processing'/);
    assert.match(statement, /campaign\.status = 'processing'/);
    assert.match(statement, /notification_deliveries\.status = 'failed'/);
    assert.match(statement, /RETURNING device_id/);
  });

  it('leases the campaign row before dispatch so cancellation cannot commit mid-send', async () => {
    let statement = '';
    const allowed = await lockNotificationCampaignForDispatch(
      '00000000-0000-0000-0000-000000000010',
      async (text) => {
        statement = text;
        return { rowCount: 1, rows: [{ status: 'processing' }] };
      },
    );
    assert.equal(allowed, true);
    assert.match(statement, /FOR UPDATE/);
    assert.match(statement, /WHERE id = \$1/);
  });

  it('uses one explicit PostgreSQL type for the reused delivery status parameter', async () => {
    let statement = '';
    let parameters: any[] = [];
    await recordNotificationDeliveryOutcome(
      {
        campaignId: '00000000-0000-0000-0000-000000000010',
        deviceId: '00000000-0000-0000-0000-000000000001',
        status: 'sent',
        providerMessageId: 'provider-message-1',
        errorCode: null,
        errorMessage: null,
      },
      async (text, params) => {
        statement = text;
        parameters = params ?? [];
        return { rowCount: 1, rows: [] };
      },
    );

    assert.match(statement, /status = \$3::varchar\(20\)/);
    assert.match(statement, /WHEN \$3::varchar\(20\) = 'sent'/);
    assert.deepEqual(parameters, [
      '00000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-000000000001',
      'sent',
      'provider-message-1',
      null,
      null,
    ]);
  });

  it('durable sign-out revocation requires both opaque installation secrets', async () => {
    let statement = '';
    let parameters: any[] = [];
    await revokeDeviceInstallation(
      'fcm-token-value',
      '0123456789abcdef0123456789abcdef',
      async (text, params) => {
        statement = text;
        parameters = params ?? [];
        return { rowCount: 1, rows: [] };
      },
    );
    assert.match(statement, /fcm_token = \$1/);
    assert.match(statement, /installation_id = \$2/);
    assert.deepEqual(parameters, [
      'fcm-token-value',
      '0123456789abcdef0123456789abcdef',
    ]);
  });

  it('returns a token-free campaign status with sanitized iOS provider diagnostics', async () => {
    const statements: Array<{ text: string; params?: any[] }> = [];
    const campaignId = '00000000-0000-4000-8000-000000000010';
    const status = await getNotificationCampaignStatus(
      campaignId,
      async (text, params) => {
        statements.push({ text, params });
        if (statements.length === 1) {
          return {
            rowCount: 1,
            rows: [{
              id: campaignId,
              status: 'failed',
              scheduled_for: '2026-09-08T10:00:00.000Z',
              sent_at: null,
              last_attempt_at: '2026-09-08T10:00:10.000Z',
              attempt_count: '2',
              sent_count: '2',
              failed_count: '4',
            }],
          };
        }
        return {
          rowCount: 4,
          rows: [
            { platform: 'android', status: 'sent', error_code: null, delivery_count: '2' },
            {
              platform: 'ios',
              status: 'failed',
              error_code: 'messaging/third-party-auth-error',
              delivery_count: '3',
            },
            {
              platform: 'ios',
              status: 'failed',
              // A legacy/raw provider value is never reflected to Admin Studio.
              error_code: 'SECRET_PROVIDER_DETAIL',
              delivery_count: '1',
            },
            { platform: 'ios', status: 'processing', error_code: null, delivery_count: '1' },
          ],
        };
      },
    );

    assert.ok(status);
    assert.equal(status.status, 'failed');
    assert.equal(status.sentCount, 2);
    assert.equal(status.failedCount, 4);
    assert.equal(status.processingCount, 1);
    assert.equal(status.attemptCount, 2);
    assert.equal(status.maxAttempts, 3);
    assert.equal(status.canRetry, true);
    assert.equal(status.terminal, false);
    assert.equal(status.providerConfigurationError, true);
    assert.deepEqual(status.failureCodes, [
      'messaging/third-party-auth-error',
      'messaging/unknown-error',
    ]);
    assert.deepEqual(status.platforms, [
      {
        platform: 'android',
        sentCount: 2,
        failedCount: 0,
        processingCount: 0,
        failureCodes: [],
      },
      {
        platform: 'ios',
        sentCount: 0,
        failedCount: 4,
        processingCount: 1,
        failureCodes: [
          'messaging/third-party-auth-error',
          'messaging/unknown-error',
        ],
      },
    ]);
    assert.equal(statements.length, 2);
    assert.deepEqual(statements.map(statement => statement.params), [
      [campaignId],
      [campaignId],
    ]);
    assert.equal(
      statements.some(statement => /fcm_token|error_message/i.test(statement.text)),
      false,
    );
  });

  it('returns null for an unknown notification campaign without querying deliveries', async () => {
    let calls = 0;
    const status = await getNotificationCampaignStatus(
      '00000000-0000-4000-8000-000000000099',
      async () => {
        calls += 1;
        return { rowCount: 0, rows: [] };
      },
    );
    assert.equal(status, null);
    assert.equal(calls, 1);
  });

  it('registers the campaign status endpoint behind notification-sender RBAC', async () => {
    const app = Fastify({ logger: false });
    await app.register(adminRoutes, { prefix: '/api/v1' });
    await app.ready();
    try {
      const response = await app.inject({
        method: 'GET',
        url: '/api/v1/admin/notifications/00000000-0000-4000-8000-000000000010/status',
      });
      // 401 proves the route exists and reaches its permission pre-handler;
      // an unregistered or misspelled endpoint would return 404.
      assert.equal(response.statusCode, 401);
      assert.equal(response.json().error, 'Unauthorized');

      const inventedPath = await app.inject({
        method: 'GET',
        url: '/api/v1/admin/notification-status/00000000-0000-4000-8000-000000000010',
      });
      assert.equal(inventedPath.statusCode, 404);
    } finally {
      await app.close();
    }
  });
});
