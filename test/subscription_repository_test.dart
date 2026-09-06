import 'dart:async';

import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _Auth extends Fake implements FirebaseAuth {
  User? user = _User('fan-a');
  @override
  User? get currentUser => user;
}

class _Firestore extends Fake implements FirebaseFirestore {}

class _Functions extends Fake implements FirebaseFunctions {}

class _Storage extends Fake implements FirebaseStorage {}

class _Client extends AbuApiClient {
  Future<dynamic> Function()? onSync;
  int syncCalls = 0;

  @override
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    expect(path, '/subscriptions/sync');
    expect(body, isEmpty);
    expect(requireAuth, isTrue);
    syncCalls++;
    return await onSync!();
  }
}

AbuUserProfile _profile({String uid = 'fan-a', bool active = false}) =>
    AbuUserProfile(
      uid: uid,
      email: '',
      username: uid,
      displayName: uid,
      country: '',
      supportedTeam: '',
      avatarUrl: '',
      role: 'user',
      membershipMultiplier: 1,
      totalPoints: 10,
      monthlyPoints: 10,
      seasonPoints: 10,
      suspended: false,
      isProSubscriber: active,
    );

class _Api extends ApiProductionRepository {
  _Api(_Client client, _Auth auth) : super(apiClient: client, auth: auth);

  bool active = false;
  int profileCalls = 0;
  int topCalls = 0;
  int snapshotCalls = 0;
  int usersCalls = 0;
  int videoCalls = 0;
  bool failVideos = false;
  bool failTop = false;
  Future<AbuUserProfile?> Function()? profileLoader;

  @override
  Future<AbuUserProfile?> fetchProfile() async {
    profileCalls++;
    return profileLoader == null
        ? _profile(active: active)
        : await profileLoader!();
  }

  LeaderboardEntry get entry => LeaderboardEntry(
    uid: 'fan-a',
    username: 'fan-a',
    avatarUrl: '',
    supportedTeam: '',
    monthlyPoints: 10,
    seasonPoints: 10,
    isMember: false,
    isProSubscriber: active,
  );

  @override
  Future<List<LeaderboardEntry>> fetchTopLeaderboard({
    String period = 'monthly',
  }) async {
    topCalls++;
    if (failTop) throw StateError('Leaderboards temporarily unavailable');
    return [entry];
  }

  @override
  Future<LeaderboardSnapshot> fetchLeaderboardSnapshot({
    String period = 'monthly',
    String? seasonId,
  }) async {
    snapshotCalls++;
    final ranked = RankedLeaderboardEntry(entry: entry, rank: 1, points: 10);
    return LeaderboardSnapshot(
      entries: [ranked],
      currentUser: ranked,
      totalPlayers: 1,
      seasons: const [],
      activeSeasonId: null,
    );
  }

  @override
  Future<List<AbuUserProfile>> fetchAdminUsers({
    String search = '',
    String? role,
    String? status,
    int limit = 200,
  }) async {
    usersCalls++;
    return [_profile(active: active)];
  }

  @override
  Future<List<ExclusiveVideo>> fetchExclusiveVideos({
    bool managed = false,
    bool forceRefresh = false,
  }) async {
    videoCalls++;
    if (failVideos) throw StateError('Videos temporarily unavailable');
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late _Client client;
  late _Api api;
  late ProductionRepository repository;
  final subscriptions = <StreamSubscription<dynamic>>[];

  Future<void> observe<T>(Stream<T> stream, List<T> values) async {
    subscriptions.add(stream.listen(values.add));
    await stream.first;
  }

  Map<String, dynamic> verdict(bool active) => {
    'data': {'entitlementId': 'abu_3meer_pro', 'isActive': active},
  };

  setUp(() {
    auth = _Auth();
    client = _Client();
    api = _Api(client, auth);
    client.onSync = () async {
      api.active = true;
      return verdict(true);
    };
    repository = ProductionRepository(
      auth: auth,
      firestore: _Firestore(),
      functions: _Functions(),
      storage: _Storage(),
      apiRepo: api,
    );
  });

  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
  });

  test(
    'detailed sync preserves production denial without granting a badge',
    () async {
      client.onSync = () async => {
        'data': {
          'entitlementId': 'abu_3meer_pro',
          'isActive': false,
          'accessReason': 'sandbox_not_allowed',
          'environment': 'sandbox',
        },
      };
      final profiles = <AbuUserProfile?>[];
      await observe(repository.watchProfile('fan-a'), profiles);
      final result = await repository.syncSubscriptionAccess(_profile());
      expect(result.isActive, false);
      expect(result.reason, 'sandbox_not_allowed');
      expect(result.environment, 'sandbox');
      expect(profiles.last!.isProSubscriber, false);
    },
  );

  test(
    'verified sync updates profile and every opened identity feed',
    () async {
      final profiles = <AbuUserProfile?>[];
      final top = <List<LeaderboardEntry>>[];
      final month = <LeaderboardSnapshot>[];
      final season = <LeaderboardSnapshot>[];
      final users = <List<AbuUserProfile>>[];
      await observe(repository.watchProfile('fan-a'), profiles);
      await observe(repository.watchLeaderboard(monthly: true), top);
      await observe(
        repository.watchLeaderboardView(period: LeaderboardPeriod.currentMonth),
        month,
      );
      await observe(
        repository.watchLeaderboardView(period: LeaderboardPeriod.season),
        season,
      );
      await observe(repository.watchUsers(search: 'fan'), users);
      await repository.watchExclusiveVideos().first;
      expect(profiles.last!.isProSubscriber, isFalse);

      expect(await repository.syncSubscription(_profile()), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(profiles.last!.isProSubscriber, isTrue);
      expect(top.last.single.isProSubscriber, isTrue);
      expect(month.last.currentUser!.entry.isProSubscriber, isTrue);
      expect(season.last.currentUser!.entry.isProSubscriber, isTrue);
      expect(users.last.single.isProSubscriber, isTrue);
      expect(api.profileCalls, 2);
      expect(api.topCalls, 2);
      expect(api.snapshotCalls, 4);
      expect(api.usersCalls, 2);
      expect(api.videoCalls, 2);
    },
  );

  test('sync does not open unused content or staff resources', () async {
    expect(await repository.syncSubscription(_profile()), isTrue);
    expect(api.profileCalls, 1);
    expect(api.topCalls, 0);
    expect(api.snapshotCalls, 0);
    expect(api.usersCalls, 0);
    expect(api.videoCalls, 0);
  });

  test('optional feed errors do not undo confirmed activation', () async {
    final top = <List<LeaderboardEntry>>[];
    final users = <List<AbuUserProfile>>[];
    await observe(repository.watchLeaderboard(monthly: true), top);
    await observe(repository.watchUsers(), users);
    await repository.watchExclusiveVideos().first;
    api.failTop = true;
    api.failVideos = true;

    expect(await repository.syncSubscription(_profile()), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(users.last.single.isProSubscriber, isTrue);
    expect(top.last.single.isProSubscriber, isFalse); // last good snapshot
    expect(api.topCalls, 2);
    expect(api.videoCalls, 2);
  });

  test(
    '404 from subscription server remains an error, without any grant',
    () async {
      final failure = AbuApiException(
        statusCode: 404,
        message: 'Route not found',
      );
      client.onSync = () async => throw failure;
      await expectLater(
        repository.syncSubscription(_profile()),
        throwsA(same(failure)),
      );
      expect(api.profileCalls, 0);
      expect(api.active, isFalse);
    },
  );

  test('authoritative profile refresh failure is not swallowed', () async {
    final failure = StateError('Profile unavailable');
    api.profileLoader = () async => throw failure;
    await expectLater(
      repository.syncSubscription(_profile()),
      throwsA(same(failure)),
    );
  });

  test(
    'inactive verdict removes badges instead of using old client state',
    () async {
      api.active = true;
      final profiles = <AbuUserProfile?>[];
      final top = <List<LeaderboardEntry>>[];
      await observe(repository.watchProfile('fan-a'), profiles);
      await observe(repository.watchLeaderboard(monthly: true), top);
      client.onSync = () async {
        api.active = false;
        return verdict(false);
      };

      expect(
        await repository.syncSubscription(_profile(active: true)),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);
      expect(profiles.last!.isProSubscriber, isFalse);
      expect(top.last.single.isProSubscriber, isFalse);
    },
  );

  test('account switch while POST is pending rejects the old result', () async {
    final pending = Completer<dynamic>();
    client.onSync = () => pending.future;
    final sync = repository.syncSubscription(_profile());
    auth.user = _User('fan-b');
    pending.complete(verdict(true));

    expect(await sync, isFalse);
    expect(api.profileCalls, 0);
  });

  test(
    'account switch during profile refresh cannot cache another user',
    () async {
      final profiles = <AbuUserProfile?>[];
      await observe(repository.watchProfile('fan-a'), profiles);
      final pending = Completer<AbuUserProfile?>();
      final started = Completer<void>();
      api.profileLoader = () {
        started.complete();
        return pending.future;
      };
      final sync = repository.syncSubscription(_profile());
      await started.future;
      auth.user = _User('fan-b');
      pending.complete(_profile(uid: 'fan-b', active: true));

      expect(await sync, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        profiles.whereType<AbuUserProfile>().every((p) => p.uid == 'fan-a'),
        isTrue,
      );
      expect(profiles.last, isNull);
      expect(api.videoCalls, 0);
    },
  );

  test(
    'guest or mismatched profile never starts a subscription request',
    () async {
      expect(
        await repository.syncSubscription(AbuUserProfile.guest()),
        isFalse,
      );
      expect(
        await repository.syncSubscription(_profile(uid: 'fan-b')),
        isFalse,
      );
      expect(client.syncCalls, 0);
    },
  );
}
