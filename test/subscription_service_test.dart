import 'dart:async';

import 'package:abu_3meer/production/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  const uiChannel = MethodChannel('purchases_ui_flutter');
  late SubscriptionService service;
  late List<MethodCall> calls;
  late String nativeId;
  late Map<String, dynamic> offerings;
  late String paywallResult;
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
    offerings = {'all': {}, 'current': null};
    paywallResult = 'CANCELLED';
    service = SubscriptionService.forTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiChannel, (call) async {
          calls.add(call);
          return paywallResult;
        });
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
              return offerings;
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(uiChannel, null);
  });

  Map<String, dynamic> currentOffering() => {
    'identifier': 'default',
    'serverDescription': 'Published membership paywall',
    'metadata': <String, Object>{},
    'availablePackages': [
      {
        'identifier': r'$rc_monthly',
        'packageType': 'MONTHLY',
        'product': {
          'identifier': 'Ostoora3',
          'description': 'Monthly membership',
          'title': 'Ostoora3',
          'price': 3.99,
          'priceString': r'$3.99',
          'currencyCode': 'USD',
        },
        'presentedOfferingContext': {'offeringIdentifier': 'default'},
      },
    ],
  };

  test('iOS uses its real app key without a Test Store fallback', () {
    expect(service.apiKey, startsWith('appl_'));
    expect(service.usesTestStore, false);
    expect(service.available, true);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // No Android store configuration has been supplied for this project yet.
    expect(service.apiKey, isEmpty);
    expect(service.available, false);
  });

  test('server policy reason is separate from a subscription grant', () {
    final result = SubscriptionAccessResult.fromEnvelope({
      'data': {
        'entitlementId': 'abu_3meer_pro',
        'isActive': false,
        'accessReason': 'sandbox_not_allowed',
        'environment': 'sandbox',
      },
    });
    expect(result.isActive, false);
    expect(result.reason, 'sandbox_not_allowed');
    expect(result.environment, 'sandbox');
    final invalid = SubscriptionAccessResult.fromEnvelope({
      'data': {
        'entitlementId': 'another_entitlement',
        'isActive': true,
        'accessReason': 'active',
      },
    });
    expect(invalid.isActive, false);
    expect(invalid.reason, 'unknown');
    for (final reason in ['sandbox_not_allowed', 'expired', 'no_entitlement']) {
      final contradictory = SubscriptionAccessResult.fromEnvelope({
        'data': {
          'entitlementId': 'abu_3meer_pro',
          'isActive': true,
          'accessReason': reason,
        },
      });
      expect(contradictory.isActive, false);
    }
  });

  for (final result in {
    'CANCELLED': PaywallResult.cancelled,
    'PURCHASED': PaywallResult.purchased,
    'RESTORED': PaywallResult.restored,
  }.entries) {
    test(
      'native published offering is passed through for ${result.key}',
      () async {
        offerings = {
          'all': {'default': currentOffering()},
          'current': currentOffering(),
        };
        paywallResult = result.key;
        expect(await service.showPaywall('account-1'), result.value);
        final presentation = calls.singleWhere(
          (c) => c.method == 'presentPaywall',
        );
        expect(presentation.arguments['offeringIdentifier'], 'default');
        expect(presentation.arguments['displayCloseButton'], true);
        expect(calls.where((c) => c.method.startsWith('purchase')), isEmpty);
        expect(service.customerInfo?.originalAppUserId, 'account-1');
        expect(service.busy, false);
      },
    );
  }

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
