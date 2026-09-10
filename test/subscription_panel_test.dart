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
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

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
  _Store({
    this.active = true,
    this.identity = 'backend-user',
    this.paywallResult = PaywallResult.cancelled,
  }) : super.forTesting();
  final bool active;
  final String identity;
  final PaywallResult paywallResult;
  var refreshes = 0;
  var paywalls = 0;
  @override
  Future<PaywallResult> showPaywall(
    String userId, {
    Future<PaywallResult> Function(Offering)? presenter,
    String? locale,
  }) async {
    paywalls++;
    return paywallResult;
  }

  @override
  bool get available => true;
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
  final result = Completer<SubscriptionAccessResult>();
  var syncs = 0;
  @override
  Future<SubscriptionAccessResult> syncSubscriptionAccess(
    AbuUserProfile profile,
  ) {
    syncs++;
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final initialLanguage in ['en', 'ar']) {
    for (final serverFailure in [false, true]) {
      testWidgets(
        'open feedback follows locale after ${serverFailure ? 'failure' : 'check'} from $initialLanguage',
        (tester) async {
          tester.view.physicalSize = const Size(320, 750);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final locale = ValueNotifier(Locale(initialLanguage));
          addTearDown(locale.dispose);
          final store = _Store();
          addTearDown(store.dispose);
          final repository = _Repository();
          final failure = AbuApiException(
            statusCode: 404,
            message: 'Route missing',
          );
          final feedback = serverFailure
              ? SubscriptionFeedback.serverFailure(failure)
              : SubscriptionFeedback.checked(
                  serverActive: false,
                  storeActive: true,
                  isSandbox: true,
                  accessReason: 'sandbox_not_allowed',
                );
          final panel = SubscriptionPanel(
            repository: repository,
            profile: _profile,
            subscriptionService: store,
          );
          await tester.pumpWidget(
            ValueListenableBuilder<Locale>(
              valueListenable: locale,
              builder: (_, currentLocale, _) => MaterialApp(
                locale: currentLocale,
                supportedLocales: const [Locale('en'), Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: panel,
                  ),
                ),
              ),
            ),
          );
          final summary = find.byKey(const Key('subscription-summary'));
          await tester.tap(find.byKey(const Key('subscription-open-details')));
          await tester.pumpAndSettle();
          final refresh = find.text(
            initialLanguage == 'en' ? 'Refresh access' : 'تحديث الصلاحيات',
          );
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await tester.pump();
          expect(
            find.descendant(
              of: summary,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(summary).height, lessThan(170));
          expect(tester.takeException(), isNull);
          if (serverFailure) {
            repository.result.completeError(failure);
          } else {
            repository.result.complete(
              const SubscriptionAccessResult(
                isActive: false,
                reason: 'sandbox_not_allowed',
                environment: 'sandbox',
              ),
            );
          }
          await tester.pumpAndSettle();
          final oldMessage = initialLanguage == 'en'
              ? feedback.english
              : feedback.arabic;
          final nextMessage = initialLanguage == 'en'
              ? feedback.arabic
              : feedback.english;
          expect(find.text(oldMessage), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          locale.value = Locale(initialLanguage == 'en' ? 'ar' : 'en');
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('subscription-details-sheet')),
            findsOneWidget,
          );
          expect(find.text(nextMessage), findsOneWidget);
          expect(find.text(oldMessage), findsNothing);
          expect(tester.getSize(summary).height, lessThan(170));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('close-subscription-details')));
          await tester.pumpAndSettle();
          expect(
            find.text(
              initialLanguage == 'en' ? 'اشتراك تجريبي' : 'Test subscription',
            ),
            findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(_profile.isProSubscriber, isFalse);
        },
      );
    }
  }

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
    for (final reason in ['sandbox_not_allowed', 'no_entitlement']) {
      testWidgets(
        'known $reason is not endless activation pending ($language)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 750);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = _Store();
          addTearDown(store.dispose);
          final repository = _Repository();
          repository.result.complete(
            SubscriptionAccessResult(
              isActive: false,
              reason: reason,
              environment: 'sandbox',
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SubscriptionPanel(
                    repository: repository,
                    profile: _profile,
                    subscriptionService: store,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('subscription-open-details')));
          await tester.pumpAndSettle();
          final refresh = find.text(
            language == 'en' ? 'Refresh access' : 'تحديث الصلاحيات',
          );
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              language == 'en' ? 'Do not purchase again' : 'لا تشترِ مرة أخرى',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('close-subscription-details')));
          await tester.pumpAndSettle();
          expect(
            find.text(
              reason == 'sandbox_not_allowed'
                  ? (language == 'en' ? 'Test subscription' : 'اشتراك تجريبي')
                  : (language == 'en'
                        ? 'Access not active'
                        : 'الصلاحيات غير مفعّلة'),
            ),
            findsOneWidget,
          );
          expect(find.text('Activation pending'), findsNothing);
          expect(find.text('Subscription active'), findsNothing);
          expect(find.text('View plans'), findsNothing);
          expect(
            tester
                .getSize(find.byKey(const Key('subscription-summary')))
                .height,
            lessThan(170),
          );
          expect(_profile.isProSubscriber, false);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final result in [PaywallResult.purchased]) {
    testWidgets(
      'plans $result opens explicit diagnostic details, not another purchase',
      (tester) async {
        final store = _Store(active: false, paywallResult: result);
        addTearDown(store.dispose);
        final repository = _Repository();
        repository.result.complete(
          const SubscriptionAccessResult(
            isActive: false,
            reason: 'sandbox_not_allowed',
            environment: 'sandbox',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SubscriptionPanel(
                repository: repository,
                profile: _profile,
                subscriptionService: store,
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('subscription-view-plans')));
        await tester.pumpAndSettle();
        expect(store.paywalls, 1);
        expect(
          find.byKey(const Key('subscription-details-sheet')),
          findsOneWidget,
        );
        expect(_profile.isProSubscriber, false);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
          find.text(language == 'en' ? 'Test subscription' : 'اشتراك تجريبي'),
          findsOneWidget,
        );
        expect(find.text('Subscription active'), findsNothing);
        expect(find.text('View plans'), findsNothing);
        expect(_profile.isProSubscriber, false);
        expect(find.text('Restore purchases'), findsNothing);
        expect(find.text('Privacy'), findsNothing);
        expect(
          tester.getSize(find.byKey(const Key('subscription-summary'))).height,
          lessThan(170),
        );
        await tester.tap(find.byKey(const Key('subscription-open-details')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('subscription-details-sheet')),
          findsOneWidget,
        );
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
      await tester.tap(find.byKey(const Key('subscription-view-plans')));
      await tester.pumpAndSettle();
      expect(store.paywalls, 1);
      expect(find.byKey(const Key('subscription-details-sheet')), findsNothing);
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

  testWidgets(
    'verified YouTube membership takes priority over a stale sandbox receipt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      addTearDown(store.dispose);
      final expiresAt = DateTime(2026, 9, 10);
      final profile = _profile.copyWith(
        membershipMultiplier: 2,
        hasMemberAccess: true,
        memberAccessSource: 'youtube',
        memberAccessReason: 'youtube_verified',
        memberAccessExpiresAt: expiresAt,
        youtubeMembershipExpiresAt: expiresAt,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubscriptionPanel(
              repository: _Repository(),
              profile: profile,
              subscriptionService: store,
            ),
          ),
        ),
      );

      expect(find.text('YouTube membership active'), findsOneWidget);
      expect(find.text('Test subscription'), findsNothing);
      expect(profile.hasMemberAccess, isTrue);
      await tester.tap(find.byKey(const Key('subscription-open-details')));
      await tester.pumpAndSettle();
      expect(find.text('YOUTUBE MEMBERSHIP'), findsOneWidget);
      expect(
        find.textContaining('does not auto-renew through this app'),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('youtube-membership-recheck')),
        findsOneWidget,
      );
      expect(find.textContaining('Test subscription'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired YouTube verification asks for recheck instead of calling it test',
    (tester) async {
      final store = _Store();
      addTearDown(store.dispose);
      final profile = _profile.copyWith(
        hasMemberAccess: false,
        youtubeMembershipRecheckRequired: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubscriptionPanel(
              repository: _Repository(),
              profile: profile,
              subscriptionService: store,
            ),
          ),
        ),
      );

      expect(find.text('YouTube membership needs recheck'), findsOneWidget);
      expect(find.text('Test subscription'), findsNothing);
      await tester.tap(find.byKey(const Key('subscription-open-details')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('previous YouTube membership check has expired'),
        findsOneWidget,
      );
      expect(find.textContaining('Test subscription'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh access response replaces a stale profile reason until profile rebuild',
    (tester) async {
      final store = _Store();
      addTearDown(store.dispose);
      final repository = _Repository();
      repository.result.complete(
        const SubscriptionAccessResult(
          isActive: true,
          reason: 'admin_granted',
          source: 'admin',
          overrideMode: 'active',
        ),
      );
      final staleProfile = _profile.copyWith(
        subscriptionAccessReason: 'no_entitlement',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubscriptionPanel(
              repository: repository,
              profile: staleProfile,
              subscriptionService: store,
            ),
          ),
        ),
      );

      expect(find.text('Access not active'), findsOneWidget);
      await tester.tap(find.byKey(const Key('subscription-open-details')));
      await tester.pumpAndSettle();
      final refresh = find.text('Refresh access');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('close-subscription-details')));
      await tester.pumpAndSettle();

      expect(find.text('Admin-granted access'), findsOneWidget);
      expect(find.text('Access not active'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin block never asks an unsubscribed user to purchase again', (
    tester,
  ) async {
    final store = _Store(active: false);
    addTearDown(store.dispose);
    final blockedProfile = _profile.copyWith(
      membershipMultiplier: 2,
      hasMemberAccess: false,
      subscriptionAccessMode: SubscriptionAccessMode.inactive,
      subscriptionAccessReason: 'admin_revoked',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubscriptionPanel(
            repository: _Repository(),
            profile: blockedProfile,
            subscriptionService: store,
          ),
        ),
      ),
    );

    expect(find.text('Subscription access blocked'), findsOneWidget);
    expect(find.text('View plans'), findsNothing);
    await tester.tap(find.byKey(const Key('subscription-open-details')));
    await tester.pumpAndSettle();
    expect(find.text('View plans'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
    expect(find.text('Customer Center'), findsNothing);
    expect(find.text('Refresh access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      'active subscription stays compact and management is explicit ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const activeProfile = AbuUserProfile(
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
          isProSubscriber: true,
        );
        final store = _Store();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SubscriptionPanel(
                  repository: _Repository(),
                  profile: activeProfile,
                  subscriptionService: store,
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(
            language == 'en' ? 'Sandbox active' : 'اشتراك تجريبي مفعّل',
          ),
          findsOneWidget,
        );
        expect(find.text('View plans'), findsNothing);
        expect(find.text('Restore purchases'), findsNothing);
        expect(
          find.text('Ostoora3 · Monthly\nOstoora3 Pro Max · Yearly'),
          findsNothing,
        );
        expect(
          tester.getSize(find.byKey(const Key('subscription-summary'))).height,
          lessThan(170),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('subscription-open-details')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('subscription-details-sheet')),
          findsOneWidget,
        );
        final plans = find.byKey(const Key('subscription-details-view-plans'));
        await tester.ensureVisible(plans);
        await tester.tap(plans);
        await tester.pumpAndSettle();
        expect(store.paywalls, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('close-subscription-details')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('subscription-details-sheet')),
          findsNothing,
        );
        expect(
          find.text(
            language == 'en' ? 'Sandbox active' : 'اشتراك تجريبي مفعّل',
          ),
          findsOneWidget,
        );
      },
    );
  }
}
