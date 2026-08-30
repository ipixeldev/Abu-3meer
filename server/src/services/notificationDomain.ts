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
    requiresTokenRefresh: failureCodes.some(isPermanentPushTokenError),
    providerConfigurationError: failureCodes.some(code =>
      providerCredentialErrorCodes.has(code)
    ),
  };
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
