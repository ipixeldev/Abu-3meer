import 'dart:io';

import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTube OAuth response parsing', () {
    test('accepts a Google HTTPS authorization URL and opaque flow ID', () {
      final result = parseYouTubeOAuthStart({
        'flowId': 'flow_12345678',
        'authorizationUrl': 'https://accounts.google.com/o/oauth2/v2/auth?client_id=public-id&state=opaque',
        // A compromised/incorrect response must not become part of the typed
        // mobile result even if extra secret-shaped fields are present.
        'creatorRefreshToken': 'must-never-reach-the-app',
      });

      expect(result.flowId, 'flow_12345678');
      expect(result.authorizationUrl.host, 'accounts.google.com');
      expect(result.toString(), isNot(contains('must-never-reach-the-app')));
    });

    test('rejects insecure or non-Google authorization destinations', () {
      for (final url in <String>[
        'http://accounts.google.com/o/oauth2/v2/auth',
        'https://evil.example/oauth',
        'javascript:alert(1)',
      ]) {
        expect(
          () => parseYouTubeOAuthStart({
            'flowId': 'flow_12345678',
            'authorizationUrl': url,
          }),
          throwsFormatException,
        );
      }
    });

    test('normalizes fan and creator terminal states', () {
      final verified = parseYouTubeOAuthStatus({
        'status': 'verified',
        'isYouTubeMember': true,
        'channelTitle': 'Fan Channel',
      });
      final notMember = parseYouTubeOAuthStatus({'status': 'not_member'});
      final connected = parseYouTubeOAuthStatus({'connected': true});

      expect(verified.state, YouTubeOAuthFlowState.verified);
      expect(verified.isYouTubeMember, isTrue);
      expect(verified.isTerminal, isTrue);
      expect(notMember.state, YouTubeOAuthFlowState.notMember);
      expect(connected.state, YouTubeOAuthFlowState.connected);
      expect(connected.isSuccessful, isTrue);
    });

    test('maps safe OAuth error codes without retaining raw diagnostics', () {
      const expected = <String, YouTubeOAuthErrorCode>{
        'creator_members_api_unavailable':
            YouTubeOAuthErrorCode.creatorMembersApiUnavailable,
        'creator_memberships_disabled':
            YouTubeOAuthErrorCode.creatorMembershipsDisabled,
        'creator_channel_mismatch':
            YouTubeOAuthErrorCode.creatorChannelMismatch,
        'google_account_mismatch': YouTubeOAuthErrorCode.googleAccountMismatch,
        'youtube_channel_already_linked':
            YouTubeOAuthErrorCode.youtubeChannelAlreadyLinked,
        'oauth_authorization_denied': YouTubeOAuthErrorCode.authorizationDenied,
      };

      for (final entry in expected.entries) {
        final result = parseYouTubeOAuthStatus({
          'status': 'error',
          'errorCode': entry.key,
          'message': 'provider diagnostic must never reach UI',
        });
        expect(result.errorCode, entry.value, reason: entry.key);
      }

      final unknown = parseYouTubeOAuthStatus({
        'status': 'error',
        'errorCode': 'access_token=secret-provider-value',
        'message': 'refresh_token=another-secret-provider-value',
      });

      expect(unknown.errorCode, YouTubeOAuthErrorCode.unknown);
      expect(unknown.toString(), isNot(contains('secret-provider-value')));
      expect(
        unknown.toString(),
        isNot(contains('another-secret-provider-value')),
      );
    });
  });

  test('mobile contract uses only authenticated backend OAuth endpoints', () {
    final api = File('lib/production/api_production_repository.dart')
        .readAsStringSync();
    final repository = File('lib/production/production_repository.dart')
        .readAsStringSync();
    final ui = File('lib/demo/production_ui.dart').readAsStringSync();
    final adminUi = File('lib/demo/production_features.dart')
        .readAsStringSync();
    final combined = '$api\n$repository\n$ui\n$adminUi';

    expect(api, contains("'/profile/youtube/connect/start'"));
    expect(api, contains("'/profile/youtube/connect/\$safeFlowId/status'"));
    expect(api, contains("'/admin/youtube/creator/status'"));
    expect(api, contains("'/admin/youtube/creator/connect/start'"));
    expect(
      api,
      contains("'/admin/youtube/creator/connect/\$safeFlowId/status'"),
    );
    expect(ui, contains('LaunchMode.externalApplication'));
    expect(ui, contains('CHECK STATUS'));
    expect(ui, contains('Google sign-in alone does not prove membership'));
    expect(ui, contains('creatorMembersApiUnavailable'));
    expect(ui, contains('creatorMembershipsDisabled'));
    expect(ui, contains('creatorChannelMismatch'));
    expect(ui, contains('googleAccountMismatch'));
    expect(ui, contains('youtubeChannelAlreadyLinked'));
    expect(ui, contains('authorizationDenied'));
    expect(ui, isNot(contains('current.message')));
    expect(repository, contains('await user.getIdToken(true)'));
    expect(
      adminUi,
      contains('User membership below is read-only and comes from secure'),
    );
    expect(adminUi, contains('youtubeMembershipVerifiedAt'));
    expect(adminUi, contains('youtubeMemberSince'));
    expect(combined, isNot(contains('setAdminYouTubeMembership')));
    expect(
      api,
      isNot(
        contains("'/admin/users/\${Uri.encodeComponent(userId)}/membership'"),
      ),
    );
    expect(adminUi, isNot(contains("'GRANT GOLD'")));

    expect(combined, isNot(contains('/youtube/v3/members')));
    expect(combined, isNot(contains('youtube.channel-memberships.creator')));
    expect(combined, isNot(contains('creatorAccessToken')));
    expect(combined, isNot(contains('creatorRefreshToken')));
  });
}
