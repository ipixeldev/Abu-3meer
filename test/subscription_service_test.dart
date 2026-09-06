import 'dart:async';

import 'package:abu_3meer/production/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  late SubscriptionService service;
  late List<MethodCall> calls;
  late String nativeId;
  Completer<Map<String, dynamic>>? pendingRestore;
  Map<String, dynamic> info() => {
    'entitlements': {'all': {}, 'active': {}},
    'allPurchaseDates': {},
    'activeSubscriptions': [],
    'allPurchasedProductIdentifiers': [],
    'nonSubscriptionTransactions': [],
    'firstSeen': '2026-09-05T00:00:00Z',
    'originalAppUserId': nativeId,
    'allExpirationDates': {},
    'requestDate': '2026-09-05T12:00:00Z',
  };
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    nativeId = '';
    pendingRestore = null;
    service = SubscriptionService.forTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'setupPurchases':
              nativeId = call.arguments['appUserId'] as String;
              return null;
            case 'getCustomerInfo':
              return info();
            case 'logIn':
              nativeId = call.arguments['appUserID'] as String;
              return {'customerInfo': info(), 'created': false};
            case 'logOut':
              nativeId = r'$RCAnonymousID:test';
              return info();
            case 'isAnonymous':
              return nativeId.startsWith(r'$RCAnonymousID:');
            case 'getAppUserID':
              return nativeId;
            case 'restorePurchases':
              return pendingRestore?.future ?? Future.value(info());
            case 'getOfferings':
              return {'all': {}, 'current': null};
            default:
              return null;
          }
        });
  });
  tearDown(() {
    service.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('production rejects test/secret/wrong-platform keys', () {
    for (final key in ['', 'sk_never_embed', 'test_testing', 'goog_android']) {
      expect(
        SubscriptionService.validPublicKey(
          key,
          isIOS: true,
          allowTestStore: false,
        ),
        false,
      );
    }
    expect(
      SubscriptionService.validPublicKey(
        'appl_public',
        isIOS: true,
        allowTestStore: false,
      ),
      true,
    );
    expect(
      SubscriptionService.validPublicKey(
        'test_testing',
        isIOS: true,
        allowTestStore: true,
      ),
      true,
    );
  });
  test(
    'server access reads the real API envelope and only this entitlement',
    () {
      expect(
        SubscriptionService.serverConfirmedAccess({
          'data': {'entitlementId': 'abu_3meer_pro', 'isActive': true},
        }),
        true,
      );
      for (final value in [
        null,
        {'isActive': true},
        {
          'data': {'isActive': true},
        },
        {
          'data': {'entitlementId': 'another_entitlement', 'isActive': true},
        },
        {
          'data': {'entitlementId': 'abu_3meer_pro', 'isActive': 'true'},
        },
        {
          'data': {'entitlementId': 'abu_3meer_pro', 'isActive': false},
        },
      ]) {
        expect(SubscriptionService.serverConfirmedAccess(value), false);
      }
    },
  );
  test(
    'configure only once and explicitly identify an account switch',
    () async {
      await service.refresh('account-1');
      await service.refresh('account-1');
      await service.refresh('account-2');
      expect(calls.where((c) => c.method == 'setupPurchases').length, 1);
      expect(calls.where((c) => c.method == 'logIn').length, 1);
      expect(service.userId, 'account-2');
      expect(service.customerInfo?.originalAppUserId, 'account-2');
      expect(service.hasStoreEntitlement, false);
      expect(service.busy, false);
    },
  );
  test(
    'sign-out invalidates an in-flight restore and queued account actions',
    () async {
      await service.refresh('account-1');
      pendingRestore = Completer<Map<String, dynamic>>();
      final restore = service.restore('account-1');
      final restoreExpectation = expectLater(
        restore,
        throwsA(isA<SubscriptionException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final queued = service.refresh('account-1');
      final queuedExpectation = expectLater(
        queued,
        throwsA(isA<SubscriptionException>()),
      );
      final logout = service.clearIdentity();
      expect(service.customerInfo, isNull);
      expect(service.userId, isNull);
      pendingRestore!.complete(info());
      await restoreExpectation;
      await queuedExpectation;
      await logout;
      expect(service.customerInfo, isNull);
      expect(service.userId, isNull);
      expect(service.busy, false);
    },
  );
  test('empty offerings produce a useful configuration error', () async {
    await expectLater(
      service.offering('account-1'),
      throwsA(isA<SubscriptionException>()),
    );
    expect(service.busy, false);
  });
}
