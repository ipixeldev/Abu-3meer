import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  isPermanentPushTokenError,
  isUnclassifiedPushTransportFailure,
  normalizePushData,
  notificationPreferenceColumn,
  safePushFailureCode,
  summarizePushFailureCodes,
  summarizePushFailures,
} from '../services/notificationDomain.js';

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
});
