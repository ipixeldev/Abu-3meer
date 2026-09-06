import 'package:abu_3meer/features/admin/admin_subscription_dialog.dart';
import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:abu_3meer/production/subscription_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _backendUserId = '01234567-89ab-4def-8123-456789abcdef';

AbuUserProfile _profile({
  String role = 'fan',
  String uid = 'firebase-user',
  String backendUserId = _backendUserId,
  String username = 'fan',
  SubscriptionAccessMode mode = SubscriptionAccessMode.store,
  DateTime? expiresAt,
}) => AbuUserProfile(
  uid: uid,
  backendUserId: backendUserId,
  email: 'fan@example.com',
  username: username,
  displayName: username,
  country: '',
  supportedTeam: '',
  avatarUrl: '',
  role: role,
  membershipMultiplier: 1,
  totalPoints: 0,
  monthlyPoints: 0,
  seasonPoints: 0,
  suspended: false,
  subscriptionAccessMode: mode,
  subscriptionAccessExpiresAt: expiresAt,
);

class _Auth extends Fake implements FirebaseAuth {}

class _PutClient extends AbuApiClient {
  String? path;
  dynamic body;
  bool? requireAuth;
  int calls = 0;
  dynamic response = <String, dynamic>{
    'data': <String, dynamic>{
      'entitlementId': SubscriptionService.entitlementId,
      'isActive': true,
      'accessReason': 'admin_granted',
      'accessSource': 'admin',
      'subscriptionAccessMode': 'active',
      'subscriptionAccessExpiresAt': '2026-10-06T00:00:00.000Z',
    },
  };

  @override
  Future<dynamic> put(
    String path, {
    dynamic body,
    bool requireAuth = true,
  }) async {
    calls++;
    this.path = path;
    this.body = body;
    this.requireAuth = requireAuth;
    return response;
  }
}

class _DirectoryClient extends AbuApiClient {
  Map<String, String>? query;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    bool requireAuth = false,
    bool bypassCache = false,
  }) async {
    expect(path, '/admin/users');
    expect(requireAuth, isTrue);
    query = queryParams;
    return <String, dynamic>{
      'users': [
        <String, dynamic>{
          'id': _backendUserId,
          'firebaseUid': 'firebase-user',
          'username': 'fan',
        },
      ],
      'total': 201,
      'limit': 200,
      'offset': 200,
      'hasMore': false,
    };
  }
}

class _RepositoryFake extends Fake implements ProductionRepository {}

Widget _editor({
  required AbuUserProfile user,
  required AdminAccessSave onSave,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: AdminSubscriptionAccessEditor(user: user, onSave: onSave),
  ),
);

Widget _directory({required AdminUserPageLoader loader}) => MaterialApp(
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: AdminSubscriptionDialog(
      repository: _RepositoryFake(),
      currentProfile: _profile(role: 'admin'),
      loadUsersPage: loader,
    ),
  ),
);

void main() {
  test(
    'admin directory parser accepts canonical subscription access fields',
    () {
      final profile = parseAdminUserProfile(<String, dynamic>{
        'id': _backendUserId,
        'firebaseUid': 'firebase-user',
        'role': 'super_admin',
        'subscriptionAccessMode': 'inactive',
        'subscriptionAccessExpiresAt': '2026-10-06T00:00:00.000Z',
        'subscriptionAccessReason': 'admin_revoked',
        'subscriptionAccessSource': 'admin',
      });

      expect(profile.backendUserId, _backendUserId);
      expect(profile.role, 'superAdmin');
      expect(profile.canManageSubscriptions, isTrue);
      expect(profile.subscriptionAccessMode, SubscriptionAccessMode.inactive);
      expect(
        profile.subscriptionAccessExpiresAt?.toUtc(),
        DateTime.utc(2026, 10, 6),
      );
      expect(profile.subscriptionAccessReason, 'admin_revoked');
      expect(profile.subscriptionAccessSource, 'admin');
    },
  );

  test(
    'profile copyWith can update, preserve, and explicitly clear grant expiry',
    () {
      final originalExpiry = DateTime.utc(2026, 10, 6);
      final replacement = DateTime.utc(2026, 11, 6);
      final profile = _profile(
        mode: SubscriptionAccessMode.active,
        expiresAt: originalExpiry,
      );

      expect(
        profile.copyWith(displayName: 'Renamed').subscriptionAccessExpiresAt,
        originalExpiry,
      );
      expect(
        profile
            .copyWith(subscriptionAccessExpiresAt: replacement)
            .subscriptionAccessExpiresAt,
        replacement,
      );
      expect(
        profile
            .copyWith(clearSubscriptionAccessExpiresAt: true)
            .subscriptionAccessExpiresAt,
        isNull,
      );
    },
  );

  test('only app admins can open subscription access controls', () {
    expect(_profile(role: 'admin').canManageSubscriptions, isTrue);
    expect(_profile(role: 'superAdmin').canManageSubscriptions, isTrue);
    expect(_profile(role: 'moderator').canManageSubscriptions, isFalse);
    expect(_profile(role: 'fan').canManageSubscriptions, isFalse);
  });

  test('admin access request sends the audited server contract', () async {
    final client = _PutClient();
    final repository = ApiProductionRepository(
      apiClient: client,
      auth: _Auth(),
    );
    final expiry = DateTime.utc(2026, 10, 6, 12, 30);

    final result = await repository.setAdminSubscriptionAccess(
      userId: _backendUserId,
      mode: SubscriptionAccessMode.active,
      reason: '  Customer care grant  ',
      expiresAt: expiry,
    );

    expect(client.path, '/admin/users/$_backendUserId/subscription-access');
    expect(client.requireAuth, isTrue);
    expect(client.body, <String, dynamic>{
      'mode': 'active',
      'reason': 'Customer care grant',
      'expiresAt': expiry.toIso8601String(),
    });
    expect(result.isActive, isTrue);
    expect(result.reason, 'admin_granted');
    expect(result.source, 'admin');
    expect(result.overrideMode, 'active');
    expect(result.overrideExpiresAt?.toUtc(), DateTime.utc(2026, 10, 6));
  });

  test(
    'admin directory page sends offset and preserves server hasMore',
    () async {
      final client = _DirectoryClient();
      final repository = ApiProductionRepository(
        apiClient: client,
        auth: _Auth(),
      );

      final page = await repository.fetchAdminUserPage(
        search: ' fan ',
        limit: 200,
        offset: 200,
      );

      expect(client.query, <String, String>{
        'q': 'fan',
        'limit': '200',
        'offset': '200',
      });
      expect(page.users.single.username, 'fan');
      expect(page.total, 201);
      expect(page.offset, 200);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'admin access request rejects malformed targets and unsafe expiry',
    () async {
      final client = _PutClient();
      final repository = ApiProductionRepository(
        apiClient: client,
        auth: _Auth(),
      );

      await expectLater(
        repository.setAdminSubscriptionAccess(
          userId: 'firebase-user',
          mode: SubscriptionAccessMode.active,
          reason: 'valid reason',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.setAdminSubscriptionAccess(
          userId: _backendUserId,
          mode: SubscriptionAccessMode.inactive,
          reason: 'valid reason',
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
        throwsArgumentError,
      );
      expect(client.calls, 0);
    },
  );

  test(
    'admin access reason rejects Unicode control and format characters',
    () async {
      final client = _PutClient();
      final repository = ApiProductionRepository(
        apiClient: client,
        auth: _Auth(),
      );

      expect(isValidAdminSubscriptionReason('دعم العميل'), isTrue);
      for (final reason in [
        'hidden\u200Bformat',
        'override\u202Etext',
        'line\u0085break',
      ]) {
        expect(isValidAdminSubscriptionReason(reason), isFalse);
        await expectLater(
          repository.setAdminSubscriptionAccess(
            userId: _backendUserId,
            mode: SubscriptionAccessMode.active,
            reason: reason,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('control or formatting'),
            ),
          ),
        );
      }
      expect(client.calls, 0);
    },
  );

  testWidgets('admin directory loads the next page and resets on search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <({String search, int limit, int offset})>[];

    await tester.pumpWidget(
      _directory(
        loader: ({required search, required limit, required offset}) async {
          requests.add((search: search, limit: limit, offset: offset));
          if (search == 'needle') {
            return AdminUserPage(
              users: [
                _profile(
                  uid: 'search-user',
                  backendUserId: '31234567-89ab-4def-8123-456789abcdef',
                  username: 'needle',
                ),
              ],
              total: 1,
              limit: limit,
              offset: offset,
              hasMore: false,
            );
          }
          final isSecondPage = offset > 0;
          return AdminUserPage(
            users: [
              _profile(
                uid: isSecondPage ? 'second-user' : 'first-user',
                backendUserId: isSecondPage
                    ? '21234567-89ab-4def-8123-456789abcdef'
                    : _backendUserId,
                username: isSecondPage ? 'second' : 'first',
              ),
            ],
            total: 201,
            limit: limit,
            offset: offset,
            hasMore: !isSecondPage,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requests.single, (search: '', limit: 200, offset: 0));
    expect(find.text('@first'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('admin-access-load-more')));
    await tester.tap(find.byKey(const Key('admin-access-load-more')));
    await tester.pumpAndSettle();

    expect(requests[1], (search: '', limit: 200, offset: 1));
    await tester.enterText(
      find.byKey(const Key('admin-access-search')),
      'needle',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(requests.last, (search: 'needle', limit: 200, offset: 0));
    expect(find.text('@needle'), findsOneWidget);
    expect(find.text('@first'), findsNothing);
    expect(find.text('@second'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor preserves an existing grant end date by default', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final expiry = DateTime.now().toUtc().add(const Duration(days: 13));
    DateTime? savedExpiry;
    await tester.pumpWidget(
      _editor(
        user: _profile(mode: SubscriptionAccessMode.active, expiresAt: expiry),
        onSave: ({required mode, required reason, expiresAt}) async {
          savedExpiry = expiresAt;
          return const SubscriptionAccessResult(
            isActive: true,
            reason: 'admin_granted',
          );
        },
      ),
    );

    expect(find.textContaining('Keep current end date'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('admin-access-reason')),
      'Continue support grant',
    );
    await tester.tap(find.byKey(const Key('admin-access-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-access-confirm')));
    await tester.pumpAndSettle();

    expect(savedExpiry, expiry);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor localizes validation and never saves a short reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await tester.pumpWidget(
      _editor(
        locale: const Locale('ar'),
        user: _profile(),
        onSave: ({required mode, required reason, expiresAt}) async {
          saves++;
          return const SubscriptionAccessResult(isActive: false);
        },
      ),
    );

    await tester.enterText(find.byKey(const Key('admin-access-reason')), 'x');
    await tester.tap(find.byKey(const Key('admin-access-review')));
    await tester.pump();

    expect(find.textContaining('3 أحرف'), findsOneWidget);
    expect(find.byKey(const Key('admin-access-confirm')), findsNothing);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor explains hidden Unicode formatting characters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await tester.pumpWidget(
      _editor(
        user: _profile(),
        onSave: ({required mode, required reason, expiresAt}) async {
          saves++;
          return const SubscriptionAccessResult(isActive: false);
        },
      ),
    );

    await tester.enterText(
      find.byKey(const Key('admin-access-reason')),
      'valid\u200Blooking',
    );
    await tester.tap(find.byKey(const Key('admin-access-review')));
    await tester.pump();

    expect(find.textContaining('hidden control'), findsOneWidget);
    expect(find.byKey(const Key('admin-access-confirm')), findsNothing);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
}
