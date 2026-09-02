import 'dart:io';

import 'package:abu_3meer/production/youtube_membership_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channelId = 'UC1234567890123456789012';
  const verifiedAt = '2026-09-02T12:00:00.000Z';
  const expiresAt = '2026-09-09T12:00:00.000Z';

  test('parses active and inactive membership-check responses', () {
    final active = parseYouTubeMembershipCheckEnvelope({
      'membership': {
        'status': 'active',
        'isMember': true,
        'youtubeChannelId': channelId,
        'membershipLevelId': 'gold',
        'memberSince': '2026-01-02T12:00:00.000Z',
        'verifiedAt': verifiedAt,
        'snapshotExpiresAt': expiresAt,
      },
    });
    expect(active.status, YouTubeMembershipCheckStatus.active);
    expect(active.isYouTubeMember, isTrue);
    expect(active.youtubeChannelId, channelId);
    expect(active.membershipLevelId, 'gold');

    final notMember = parseYouTubeMembershipCheckEnvelope({
      'membership': {
        'status': 'not_in_snapshot',
        'isMember': false,
        'youtubeChannelId': channelId,
        'membershipLevelId': null,
        'memberSince': null,
        'verifiedAt': verifiedAt,
        'snapshotExpiresAt': expiresAt,
      },
    });
    expect(notMember.status, YouTubeMembershipCheckStatus.notInSnapshot);
    expect(notMember.isYouTubeMember, isFalse);
  });

  test('parses safe non-match outcomes without inventing a channel', () {
    for (final status in <String>[
      'snapshot_unavailable',
      'no_youtube_channel',
    ]) {
      final result = parseYouTubeMembershipCheckEnvelope({
        'membership': {
          'status': status,
          'isMember': false,
          'membershipLevelId': null,
          'memberSince': null,
          'verifiedAt': verifiedAt,
        },
      });
      expect(result.isYouTubeMember, isFalse);
      expect(result.youtubeChannelId, isNull);
    }
  });

  test('rejects contradictory or unsafe membership-check responses', () {
    expect(
      () => parseYouTubeMembershipCheckEnvelope({
        'membership': {
          'status': 'active',
          'isMember': false,
          'youtubeChannelId': channelId,
          'verifiedAt': verifiedAt,
          'snapshotExpiresAt': expiresAt,
        },
      }),
      throwsFormatException,
    );
    expect(
      () => parseYouTubeMembershipCheckEnvelope({
        'membership': {
          'status': 'active',
          'isMember': true,
          'youtubeChannelId': 'https://youtube.com/@unsafe',
          'verifiedAt': verifiedAt,
          'snapshotExpiresAt': expiresAt,
        },
      }),
      throwsFormatException,
    );
  });

  test(
    'mobile performs one-tap read-only verification with no manual input',
    () {
      final api = File('lib/production/api_production_repository.dart')
          .readAsStringSync();
      final repository = File('lib/production/production_repository.dart')
          .readAsStringSync();
      final ui = File('lib/demo/production_ui.dart').readAsStringSync();
      final admin = File('lib/demo/youtube_membership_snapshot_admin.dart')
          .readAsStringSync();

      expect(api, contains("'/profile/youtube/membership/check'"));
      expect(api, contains("'accessToken': accessToken"));
      expect(
        repository,
        contains('https://www.googleapis.com/auth/youtube.readonly'),
      );
      expect(repository, contains('.authorizationForScopes('));
      expect(repository, contains('.authorizeScopes('));
      expect(repository, contains('linkWithCredential('));
      expect(repository, contains('getIdToken(true)'));
      expect(ui, contains("Key('youtube-membership-check-dialog')"));
      expect(ui, contains('CHECK MEMBERSHIP'));

      final executableClient = '$api\n$repository\n$ui\n$admin';
      expect(executableClient, isNot(contains('youtube-channel-claim-input')));
      expect(executableClient, isNot(contains('SUBMIT CHANNEL CLAIM')));
      expect(executableClient, isNot(contains('SUBMIT FOR REVIEW')));
      expect(executableClient, isNot(contains("'/profile/youtube/claim'")));
      expect(
        executableClient,
        isNot(contains('profile-review-youtube-channel-claims')),
      );
    },
  );
}
