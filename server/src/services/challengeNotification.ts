import type { CreateNotificationCampaignInput } from './notificationService.js';

export interface ChallengeNotificationInput {
  challengeId: string;
  title: string;
  imageUrl: string;
  startsAt: Date;
  status: string;
  memberOnly: boolean;
  createdBy: string;
}

export function shouldScheduleChallengeNotification(
  notifyOnLive: boolean,
  status: string,
): boolean {
  return notifyOnLive && (status === 'open' || status === 'scheduled');
}

/**
 * Builds the one-time campaign created together with a challenge. Passing
 * `now` makes the max(now, startsAt) rule deterministic in tests.
 */
export function challengeNotificationCampaign(
  input: ChallengeNotificationInput,
  now: Date = new Date()
): CreateNotificationCampaignInput {
  if (!shouldScheduleChallengeNotification(true, input.status)) {
    throw new Error(`Challenge status ${input.status} cannot create a notification campaign.`);
  }
  const scheduledFor = input.status === 'scheduled' && input.startsAt.getTime() > now.getTime()
    ? input.startsAt
    : now;
  return {
    title: 'Abu 3meer',
    body: input.title,
    category: 'challenge',
    targetAudience: input.memberOnly ? 'members_only' : 'all',
    imageUrl: input.imageUrl.startsWith('https://') ? input.imageUrl : null,
    scheduledFor,
    createdBy: input.createdBy,
    sourceType: 'challenge',
    sourceId: input.challengeId,
    data: {
      route: '/challenges',
      challengeId: input.challengeId,
    },
  };
}
