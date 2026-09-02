import 'dart:io';

import 'package:abu_3meer/production/youtube_channel_claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channelId = 'UC1234567890123456789012';

  test('parses safe channel claim envelopes and all effective states', () {
    for (final status in <String>[
      'pending',
      'active',
      'lapsed',
      'rejected',
      'revoked',
      'superseded',
    ]) {
      final claim = parseYouTubeChannelClaimEnvelope({
        'claim': {
          'id': 'claim-id',
          'userId': 'user-id',
          'youtubeChannelId': channelId,
          'status': status,
          'submittedAt': '2026-09-02T12:00:00.000Z',
        },
      });
      expect(claim, isNotNull);
      expect(claim!.youtubeChannelId, channelId);
    }
    expect(parseYouTubeChannelClaimEnvelope({'claim': null}), isNull);
    expect(
      () => parseYouTubeChannelClaimEnvelope({
        'claim': {
          'id': 'claim-id',
          'userId': 'user-id',
          'youtubeChannelId': 'https://youtube.com/@unsafe',
          'status': 'active',
          'submittedAt': '2026-09-02T12:00:00.000Z',
        },
      }),
      throwsFormatException,
    );
  });

  test('mobile uses staff-approved claims and has no YouTube OAuth UX', () {
    final api = File('lib/production/api_production_repository.dart')
        .readAsStringSync();
    final repository = File('lib/production/production_repository.dart')
        .readAsStringSync();
    final ui = File('lib/demo/production_ui.dart').readAsStringSync();
    final admin = File('lib/demo/production_features.dart').readAsStringSync();

    expect(api, contains("'/profile/youtube/claim'"));
    expect(api, contains("'/admin/youtube/membership/claims/"));
    expect(repository, contains('submitYouTubeChannelClaim'));
    expect(ui, contains("Key('youtube-channel-claim-dialog')"));
    expect(ui, contains('SUBMIT CHANNEL CLAIM'));
    expect(admin, contains("Key('review-youtube-channel-claims')"));
    expect(admin, contains('YouTubeChannelClaimDecision.approve'));
    expect(admin, contains('YouTubeChannelClaimDecision.revoke'));
    expect(admin, contains("value: 'approved'"));
    expect(admin, contains("'/channel/\${claim.youtubeChannelId}'"));

    final combined = '$api\n$repository\n$ui';
    expect(combined, isNot(contains('/youtube/connect/start')));
    expect(combined, isNot(contains('accounts.google.com')));
    expect(combined, isNot(contains('YouTubeOAuth')));
  });
}
