export const notificationCategories = ['match', 'challenge', 'reward', 'news', 'general'] as const;
export type NotificationCategory = (typeof notificationCategories)[number];

const permanentTokenErrorCodes = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

export function isPermanentPushTokenError(code?: string): boolean {
  return code != null && permanentTokenErrorCodes.has(code);
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
