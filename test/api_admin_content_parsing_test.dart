import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'admin challenge parser includes public questions without answer keys',
    () {
      final challenge = parseApiChallenge({
        'id': 'challenge_1',
        'kind': 'videoPhrase',
        'title': 'Video question',
        'description': 'Watch first',
        'status': 'scheduled',
        'reward_points': 250,
        'video_url': 'https://youtu.be/test',
        'image_url': 'https://api.abu3meer.com/media/challenge/test.jpg',
        'maximum_attempts': 3,
        'member_only': false,
        'notify_on_live': true,
        'starts_at': '2026-08-30T12:00:00.000Z',
        'ends_at': '2026-09-06T12:00:00.000Z',
        'questions': [
          {
            'id': 'q1',
            'prompt': 'What did he say?',
            'type': 'text',
            'options': <String>[],
          },
        ],
      });

      expect(challenge.id, 'challenge_1');
      expect(challenge.rewardPoints, 250);
      expect(challenge.maximumAttempts, 3);
      expect(challenge.notifyOnLive, isTrue);
      expect(challenge.questions.single.prompt, 'What did he say?');
      expect(challenge.questions.single.correctAnswer, isEmpty);
    },
  );

  test('Player Card parser accepts PostgreSQL snake-case fields', () {
    final card = parseApiPlayerCard({
      'id': 'card_1',
      'player_name': 'Vinicius Jr',
      'player_name_ar': 'فينيسيوس',
      'card_image_url': 'https://api.abu3meer.com/media/card.jpg',
      'team': 'Real Madrid',
      'team_logo_url': 'https://api.abu3meer.com/media/team.png',
      'position': 'LW',
      'rating': 93,
      'rarity': 'legendary',
      'stats': {'pace': 98, 'shooting': '88'},
      'description': 'Fast winger',
      'description_ar': 'جناح سريع',
      'enabled': true,
      'source_challenge_id': 'challenge_1',
      'unlocked': true,
      'unlocked_at': '2026-08-30T13:00:00.000Z',
    });

    expect(card.playerName, 'Vinicius Jr');
    expect(card.unlocked, isTrue);
    expect(card.unlockedAt, isNotNull);
    expect(card.rating, 93);
    expect(card.stats, {'pace': 98, 'shooting': 88});
    expect(card.sourceChallengeId, 'challenge_1');
  });

  test('locked Player Card response keeps only safe catalogue fields', () {
    final card = parseApiPlayerCard({
      'id': 'card_locked',
      'player_name': '',
      'player_name_ar': '',
      'card_image_url': '',
      'team': '',
      'team_logo_url': '',
      'position': '',
      'rating': 0,
      'rarity': 'epic',
      'stats': <String, int>{},
      'description': '',
      'description_ar': '',
      'enabled': true,
      'source_challenge_id': 'challenge_hidden',
      'unlocked': false,
      'unlocked_at': null,
    });

    expect(card.unlocked, isFalse);
    expect(card.playerName, isEmpty);
    expect(card.imageUrl, isEmpty);
    expect(card.teamName, isEmpty);
    expect(card.stats, isEmpty);
    expect(card.rarity, 'epic');
    expect(card.sourceChallengeId, 'challenge_hidden');
  });

  test('a claimed Player Card stays representable after admins disable it', () {
    final card = parseApiPlayerCard({
      'id': 'card_collected',
      'player_name': 'Collected Player',
      'player_name_ar': '',
      'card_image_url': 'https://api.abu3meer.com/media/card.jpg',
      'team': 'RMA',
      'team_logo_url': '',
      'position': 'CM',
      'rating': 88,
      'rarity': 'rare',
      'stats': {'passing': 90},
      'description': '',
      'description_ar': '',
      'enabled': false,
      'source_challenge_id': 'challenge_closed',
      'unlocked': true,
      'unlocked_at': '2026-08-30T13:00:00.000Z',
    });

    expect(card.enabled, isFalse);
    expect(card.unlocked, isTrue);
    expect(card.playerName, 'Collected Player');
  });

  test('launch popup and redemption parse API timestamps', () {
    final popup = parseApiLaunchAnnouncement({
      'enabled': true,
      'title': 'Welcome',
      'body': 'New video',
      'imageUrl': '',
      'linkUrl': 'https://youtube.com',
      'buttonLabel': 'WATCH',
      'revision': 12,
      'frequency': 'daily',
      'startsAt': '2026-08-30T12:00:00.000Z',
      'endsAt': '2026-09-01T12:00:00.000Z',
    });
    final redemption = parseApiRedemption({
      'id': 'redemption_1',
      'rewardId': 'reward_1',
      'rewardTitle': 'Signed shirt',
      'cost': 500,
      'status': 'pending',
      'userId': 'user_1',
      'userDisplayName': 'Omar',
      'note': '',
      'createdAt': '2026-08-30T13:00:00.000Z',
    });

    expect(popup, isNotNull);
    expect(popup!.frequency, 'daily');
    expect(popup.startsAt.isUtc, isFalse);
    expect(redemption.rewardTitle, 'Signed shirt');
    expect(redemption.userDisplayName, 'Omar');
    expect(redemption.createdAt.year, 2026);
  });

  test('self-hosted reward redemption receipt keeps retry metadata', () {
    final receipt = parseRewardRedemptionReceipt({
      'ok': true,
      'duplicate': true,
      'redemptionId': 'redemption_user_reward_attempt',
      'remainingBalance': 350,
      'stockRemaining': 4,
      'claimCount': 2,
    });

    expect(receipt.redemptionId, 'redemption_user_reward_attempt');
    expect(receipt.remainingBalance, 350);
    expect(receipt.stockRemaining, 4);
    expect(receipt.claimCount, 2);
    expect(receipt.duplicate, isTrue);
  });

  test('malformed self-hosted reward redemption receipt is rejected', () {
    expect(
      () => parseRewardRedemptionReceipt({
        'ok': true,
        'redemptionId': '',
        'remainingBalance': '350',
      }),
      throwsFormatException,
    );
  });
}
