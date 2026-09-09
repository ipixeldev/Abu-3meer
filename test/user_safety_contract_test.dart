import 'dart:io';

import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends Fake implements FirebaseAuth {}

class _SafetyClient extends AbuApiClient {
  String? method;
  String? path;
  dynamic body;
  bool? requireAuth;
  bool? bypassCache;
  dynamic getResponse = const <String, dynamic>{'data': <dynamic>[]};

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    bool requireAuth = false,
    bool bypassCache = false,
  }) async {
    method = 'GET';
    this.path = path;
    this.requireAuth = requireAuth;
    this.bypassCache = bypassCache;
    return getResponse;
  }

  @override
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    method = 'POST';
    this.path = path;
    this.body = body;
    this.requireAuth = requireAuth;
    return const <String, dynamic>{'ok': true};
  }

  @override
  Future<dynamic> delete(String path, {bool requireAuth = true}) async {
    method = 'DELETE';
    this.path = path;
    this.requireAuth = requireAuth;
    return const <String, dynamic>{'ok': true};
  }
}

LeaderboardEntry _entry(String uid) => LeaderboardEntry(
  uid: uid,
  username: uid,
  displayName: uid,
  avatarUrl: '',
  supportedTeam: '',
  monthlyPoints: 10,
  seasonPoints: 10,
  totalPoints: 10,
  isMember: false,
);

void main() {
  group('user safety API', () {
    late _SafetyClient client;
    late ApiProductionRepository repository;

    setUp(() {
      client = _SafetyClient();
      repository = ApiProductionRepository(apiClient: client, auth: _Auth());
    });

    test('submits a canonical report with optional details', () async {
      await repository.reportUser(
        userId: ' fan/name ',
        reason: ' harassment ',
        details: ' repeated insults ',
      );

      expect(client.method, 'POST');
      expect(client.path, '/users/fan%2Fname/report');
      expect(client.requireAuth, isTrue);
      expect(client.body, <String, dynamic>{
        'reason': 'harassment',
        'details': 'repeated insults',
      });
    });

    test('block and unblock use authenticated encoded routes', () async {
      await repository.blockUser('fan/name');
      expect(client.method, 'POST');
      expect(client.path, '/users/fan%2Fname/block');
      expect(client.requireAuth, isTrue);
      expect(client.body, isNull);

      await repository.unblockUser('fan/name');
      expect(client.method, 'DELETE');
      expect(client.path, '/users/fan%2Fname/block');
      expect(client.requireAuth, isTrue);
    });

    test('parses the blocked-users data envelope', () async {
      client.getResponse = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'publicId': 'public-fan',
            'username': 'fan_7',
            'displayName': 'Fan Seven',
            'avatarUrl': 'https://example.com/avatar.png',
            'blockedAt': '2026-09-09T08:30:00.000Z',
          },
        ],
      };

      final users = await repository.fetchBlockedUsers();

      expect(client.path, '/users/blocked');
      expect(client.requireAuth, isTrue);
      expect(client.bypassCache, isTrue);
      expect(users.single.publicId, 'public-fan');
      expect(users.single.displayName, 'Fan Seven');
      expect(users.single.avatarUrl, isEmpty);
      expect(users.single.blockedAt?.toUtc(), DateTime.utc(2026, 9, 9, 8, 30));
    });

    test('public identity parsers never expose uploaded avatar URLs', () async {
      final leaderboard = parseApiLeaderboardEntry(<String, dynamic>{
        'publicId': 'public-fan',
        'username': 'fan_7',
        'displayName': 'Fan Seven',
        'avatarUrl': 'https://uploads.example/public-photo.png',
      });
      expect(leaderboard.avatarUrl, isEmpty);

      client.getResponse = <String, dynamic>{
        'publicId': 'public-fan',
        'username': 'fan_7',
        'displayName': 'Fan Seven',
        'avatarUrl': 'https://uploads.example/public-photo.png',
      };
      final profile = await repository.fetchPublicProfile('public-fan');
      expect(profile, isNotNull);
      expect(profile!.avatarUrl, isEmpty);
      expect(client.path, '/profile/public-fan');
      expect(client.requireAuth, isTrue);
      expect(client.bypassCache, isTrue);
    });

    test('rejects unsafe report codes before sending', () async {
      await expectLater(
        repository.reportUser(userId: 'fan', reason: 'free form reason'),
        throwsArgumentError,
      );
      expect(client.method, isNull);
    });
  });

  test(
    'blocked identities are immediately removed from cached leaderboards',
    () {
      final visible = _entry('visible-user');
      final blocked = _entry('Blocked-User');
      final rankedVisible = RankedLeaderboardEntry(
        entry: visible,
        rank: 1,
        points: 10,
      );
      final rankedBlocked = RankedLeaderboardEntry(
        entry: blocked,
        rank: 2,
        points: 10,
      );
      final snapshot = LeaderboardSnapshot(
        entries: <RankedLeaderboardEntry>[rankedVisible, rankedBlocked],
        currentUser: rankedVisible,
        totalPlayers: 2,
        seasons: const <LeaderboardSeason>[],
        activeSeasonId: null,
      );

      expect(
        excludeBlockedLeaderboardEntries(
          <LeaderboardEntry>[visible, blocked],
          const <String>[' blocked-user '],
        ).map((entry) => entry.uid),
        <String>['visible-user'],
      );
      expect(
        excludeBlockedLeaderboardSnapshot(snapshot, const <String>[
          'blocked-user',
        ]).entries.map((entry) => entry.entry.uid),
        <String>['visible-user'],
      );
    },
  );

  test(
    'review-safety controls are visible and onboarding photo is optional',
    () {
      final source = File('lib/demo/production_ui.dart').readAsStringSync();
      final onboardingStart = source.indexOf(
        'class _ProductionOnboardingState',
      );
      final onboardingEnd = source.indexOf(
        'class _ClubSelectionCard',
        onboardingStart,
      );
      final onboarding = source.substring(onboardingStart, onboardingEnd);

      expect(onboarding, contains("'Add a profile photo (optional)'"));
      expect(onboarding, isNot(contains('avatarUrl.trim().isEmpty)')));
      expect(source, contains("'REPORT PROFILE'"));
      expect(source, contains("'BLOCK USER'"));
      expect(source, contains("'Blocked users'"));
      expect(source, contains("'UNBLOCK'"));
      expect(source, contains('defaultTargetPlatform != TargetPlatform.iOS'));
      expect(
        source,
        contains(
          'Deleting this account does not cancel an Apple App Store subscription.',
        ),
      );
      expect(source, contains("'MANAGE APPLE SUBSCRIPTION'"));
    },
  );

  test('public profile visibility never falls back to Firestore', () {
    final source = File('lib/production/production_repository.dart')
        .readAsStringSync();
    final methodStart = source.indexOf(
      'Future<AbuUserProfile?> fetchProfileByUid(String uid)',
    );
    final methodEnd = source.indexOf(
      'Future<UserLeaderboardRanks> fetchUserRanks',
      methodStart,
    );
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final method = source.substring(methodStart, methodEnd);
    expect(method, contains('apiRepo.fetchPublicProfile(uid)'));
    expect(method, isNot(contains("firestore.collection('users')")));
  });
}
