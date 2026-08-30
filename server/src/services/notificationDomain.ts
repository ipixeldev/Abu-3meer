export const notificationCategories = ['match', 'challenge', 'reward', 'news', 'general'] as const;
export type NotificationCategory = (typeof notificationCategories)[number];

const permanentTokenErrorCodes = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
  // This token was minted by a different Firebase project/sender. It can
  // never succeed with the currently configured Firebase Admin credential.
  'messaging/mismatched-credential',
]);

const providerCredentialErrorCodes = new Set([
  'messaging/third-party-auth-error',
  'messaging/invalid-apns-credentials',
]);

export function isPermanentPushTokenError(code?: string): boolean {
  return code != null && permanentTokenErrorCodes.has(code);
}

export interface PushFailureSummary {
  failureCodes: string[];
  requiresTokenRefresh: boolean;
  providerConfigurationError: boolean;
}

function errorString(error: unknown, key: 'code' | 'message'): string | undefined {
  if (typeof error !== 'object' || error === null) return undefined;
  try {
    const value = (error as Record<string, unknown>)[key];
    return typeof value === 'string' && value.trim() ? value.trim() : undefined;
  } catch {
    return undefined;
  }
}

function canonicalPushFailureCode(code: string): string {
  const trimmed = code.trim();
  if (/^messaging\/[a-z0-9-]+$/i.test(trimmed)) return trimmed.toLowerCase();
  const providerCode = trimmed.toUpperCase().replaceAll('-', '_');
  if (
    providerCode.includes('HTTP2') ||
    providerCode.includes('ECONNRESET') ||
    providerCode.includes('ETIMEDOUT') ||
    providerCode.includes('SOCKET')
  ) {
    return 'messaging/transport-error';
  }
  if (
    providerCode === 'APNS_AUTH_ERROR' ||
    providerCode === 'INVALID_APNS_CREDENTIAL' ||
    providerCode === 'THIRD_PARTY_AUTH_ERROR' ||
    providerCode === 'UNAUTHENTICATED'
  ) {
    return 'messaging/third-party-auth-error';
  }
  if (
    providerCode === 'SENDER_ID_MISMATCH' ||
    providerCode === 'MISMATCHED_CREDENTIAL' ||
    providerCode === 'PERMISSION_DENIED'
  ) {
    return 'messaging/mismatched-credential';
  }
  if (providerCode === 'UNREGISTERED' || providerCode === 'NOT_FOUND') {
    return 'messaging/registration-token-not-registered';
  }
  if (providerCode === 'INVALID_ARGUMENT') return 'messaging/invalid-argument';
  if (providerCode === 'INTERNAL') return 'messaging/internal-error';
  if (providerCode === 'UNAVAILABLE') return 'messaging/server-unavailable';
  return 'messaging/unknown-error';
}

function rawPushFailureCode(error: unknown): string | undefined {
  const directCode = errorString(error, 'code');
  if (directCode) return directCode;

  if (typeof error !== 'object' || error === null) return undefined;
  const record = error as Record<string, unknown>;
  const errorInfoCode = errorString(record.errorInfo, 'code');
  if (errorInfoCode) return errorInfoCode;

  if (typeof record.toJSON === 'function') {
    try {
      const json = (record.toJSON as () => unknown)();
      return errorString(json, 'code');
    } catch {
      return undefined;
    }
  }
  return undefined;
}

function pushFailureCodeFromMessage(error: unknown): string | undefined {
  const message = errorString(error, 'message')?.toLowerCase() || '';
  if (
    message.includes('apns_auth_error') ||
    message.includes('invalidapnscredential') ||
    message.includes('third-party auth') ||
    message.includes('apple push notification service')
  ) {
    return 'messaging/third-party-auth-error';
  }
  if (
    message.includes('sender_id_mismatch') ||
    message.includes('mismatched credential') ||
    message.includes('different firebase project')
  ) {
    return 'messaging/mismatched-credential';
  }
  if (
    message.includes('unregistered') ||
    message.includes('registration token is not registered') ||
    message.includes('requested entity was not found')
  ) {
    return 'messaging/registration-token-not-registered';
  }
  if (
    message.includes('invalid registration token') ||
    message.includes('not a valid fcm registration token')
  ) {
    return 'messaging/invalid-registration-token';
  }
  return undefined;
}

/**
 * FirebaseError exposes `code` through a getter, while some transports expose
 * the same value only through `toJSON()` or the internal `errorInfo` object.
 * Read all supported shapes and fall back to a conservative message
 * classification. The provider message itself is never returned or logged.
 */
export function safePushFailureCode(error: unknown): string {
  const rawCode = rawPushFailureCode(error);
  if (rawCode) return canonicalPushFailureCode(rawCode);
  return pushFailureCodeFromMessage(error) || 'messaging/unknown-error';
}

/** True only for a plain transport rejection, not a coded FCM/APNs error. */
export function isUnclassifiedPushTransportFailure(error: unknown): boolean {
  const rawCode = rawPushFailureCode(error);
  if (rawCode != null) {
    const canonicalCode = canonicalPushFailureCode(rawCode);
    return (
      canonicalCode === 'messaging/transport-error' ||
      (canonicalCode === 'messaging/unknown-error' &&
        !rawCode.toLowerCase().startsWith('messaging/'))
    );
  }
  return pushFailureCodeFromMessage(error) == null;
}

/**
 * Produces a token-free diagnostic that is safe to log and return to the
 * authenticated device-test endpoint. FCM registration tokens and provider
 * error messages are deliberately excluded.
 */
export function summarizePushFailureCodes(
  codes: Array<string | null | undefined>
): PushFailureSummary {
  const failureCodes = [...new Set(codes.filter((code): code is string => Boolean(code)))];
  return {
    failureCodes,
    // One token rotation is a safe recovery attempt when an older Admin SDK
    // response has no inspectable code. The client retries at most once.
    requiresTokenRefresh: failureCodes.some(
      code => isPermanentPushTokenError(code) || code === 'messaging/unknown-error'
    ),
    providerConfigurationError: failureCodes.some(code =>
      providerCredentialErrorCodes.has(code)
    ),
  };
}

export function summarizePushFailures(errors: unknown[]): PushFailureSummary {
  return summarizePushFailureCodes(errors.map(safePushFailureCode));
}

export function normalizePushData(
  data: Record<string, unknown> | null | undefined
): Record<string, string> {
  if (!data) return {};
  return Object.fromEntries(
    Object.entries(data)
      .filter(([, value]) => value != null)
      .map(([key, value]) => [key, String(value)])
  );
}

export function notificationPreferenceColumn(category: NotificationCategory): string | null {
  return {
    match: 'match_enabled',
    challenge: 'challenge_enabled',
    reward: 'reward_enabled',
    news: 'news_enabled',
    general: null,
  }[category];
}
