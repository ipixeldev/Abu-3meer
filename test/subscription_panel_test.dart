import 'dart:async';

import 'package:abu_3meer/features/subscriptions/subscription_feedback.dart';
import 'package:abu_3meer/features/subscriptions/subscription_panel.dart';
import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:abu_3meer/production/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _profile = AbuUserProfile(
  uid: 'firebase-user',
  backendUserId: 'backend-user',
  email: '',
  username: 'fan',
  displayName: 'Fan',
  country: '',
  supportedTeam: '',
  avatarUrl: '',
  role: 'fan',
  membershipMultiplier: 1,
  totalPoints: 10,
  monthlyPoints: 5,
  seasonPoints: 10,
  suspended: false,
);

class _Store extends SubscriptionService {
  _Store({this.active = true, this.identity = 'backend-user'})
    : super.forTesting();
  final bool active;
  final String identity;
  var refreshes = 0;
  @override
  bool get available => true;
  @override
  bool get usesTestStore => false;
  @override
  String get userId => identity;
  @override
  CustomerInfo get customerInfo {
    const entitlement = EntitlementInfo(
      'abu_3meer_pro',
      true,
      true,
      '2026-09-06T00:00:00Z',
      '2026-09-06T00:00:00Z',
      'Ostoora3_Pro_Max',
      true,
    );
    final entries = active
        ? {'abu_3meer_pro': entitlement}
        : <String, EntitlementInfo>{};
    return CustomerInfo(
      EntitlementInfos(entries, entries),
      {},
      [],
      [],
      [],
      '2026-09-06T00:00:00Z',
      identity,
      {},
      '2026-09-06T00:00:00Z',
    );
  }

  @override
  Future<CustomerInfo> refresh(String userId) async {
    refreshes++;
    return customerInfo;
  }
}

class _Repository implements ProductionRepository {
  final result = Completer<bool>();
  var syncs = 0;
  @override
  Future<bool> syncSubscription(AbuUserProfile profile) {
    syncs++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'missing route has actionable feedback, never asks for another purchase',
    () {
      final feedback = SubscriptionFeedback.serverFailure(
        AbuApiException(statusCode: 404, message: 'Route not found'),
      );
      expect(feedback.english, contains('server update'));
      expect(feedback.english, contains('Do not purchase again'));
      expect(feedback.english, isNot(contains('tap Refresh access')));
      expect(feedback.arabic, contains('تحديث الخادم'));
    },
  );

  test(
    'server configuration, sign-in, networking, and throttling stay distinct',
    () {
      for (final value in <(int, Object?, String)>[
        (503, '{"code":"subscriptions_not_configured"}', 'not configured'),
        (503, {'code': 'subscriptions_not_configured'}, 'not configured'),
        (401, null, 'Sign in again'),
        (0, null, 'Check your connection'),
        (429, null, 'Wait a minute'),
        (503, 'not-json', 'could not confirm access'),
      ]) {
        final feedback = SubscriptionFeedback.serverFailure(
          AbuApiException(
            statusCode: value.$1,
            message: 'private diagnostic',
            details: value.$2,
          ),
        );
        expect(feedback.english, contains(value.$3));
        expect(feedback.english, isNot(contains('private diagnostic')));
      }
    },
  );

  test('store-only sandbox access is pending, not an active server grant', () {
    final feedback = SubscriptionFeedback.checked(
      serverActive: false,
      storeActive: true,
      isSandbox: true,
    );
    expect(feedback.english, contains('test subscription'));
    expect(feedback.english, contains('server access is not active'));
    expect(
      SubscriptionFeedback.checked(
        serverActive: false,
        storeActive: false,
        isSandbox: false,
      ).english,
      contains('Restore purchases'),
    );
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      'refresh reports missing backend and protects existing buyer ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _Store();
        addTearDown(store.dispose);
        final repository = _Repository();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SubscriptionPanel(
                  repository: repository,
                  profile: _profile,
                  subscriptionService: store,
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(
            language == 'en' ? 'Manage subscription' : 'إدارة الاشتراك',
          ),
          findsOneWidget,
        );
        expect(find.text('Subscription active'), findsNothing);
        expect(find.text('View plans'), findsNothing);
        expect(_profile.isProSubscriber, false);
        final button = find.text(
          language == 'en' ? 'Refresh access' : 'تحديث الصلاحيات',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(store.refreshes, 1);
        expect(repository.syncs, 1);
        expect(
          find.text(language == 'en' ? 'Refreshing…' : 'جارٍ التحديث…'),
          findsOneWidget,
        );
        repository.result.completeError(
          AbuApiException(statusCode: 404, message: 'Route missing'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            language == 'en' ? 'server update' : 'تحديث الخادم',
          ),
          findsOneWidget,
        );
        expect(find.text('Subscription active'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an inactive store account is offered plans without an active badge claim',
    (tester) async {
      final store = _Store(active: false);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SubscriptionPanel(
                repository: _Repository(),
                profile: _profile,
                subscriptionService: store,
              ),
            ),
          ),
        ),
      );
      expect(find.text('View plans'), findsOneWidget);
      expect(find.textContaining('activation pending'), findsNothing);
      expect(find.text('Subscription active'), findsNothing);
    },
  );

  testWidgets('another app account cannot show a stale store subscription', (
    tester,
  ) async {
    final store = _Store(identity: 'another-account');
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SubscriptionPanel(
              repository: _Repository(),
              profile: _profile,
              subscriptionService: store,
            ),
          ),
        ),
      ),
    );
    expect(find.text('View plans'), findsOneWidget);
    expect(find.textContaining('activation pending'), findsNothing);
    expect(find.text('Subscription active'), findsNothing);
  });
}
