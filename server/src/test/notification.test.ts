import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  isPermanentPushTokenError,
  normalizePushData,
  notificationPreferenceColumn,
  summarizePushFailureCodes,
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
  });

  it('maps campaign categories to user preference columns', () => {
    assert.equal(notificationPreferenceColumn('match'), 'match_enabled');
    assert.equal(notificationPreferenceColumn('challenge'), 'challenge_enabled');
    assert.equal(notificationPreferenceColumn('general'), null);
  });
});
