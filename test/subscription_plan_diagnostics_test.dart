import 'dart:async';

import 'package:abu_3meer/production/subscription_plan_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ids = ['Ostoora3', 'Ostoora3_Pro_Max'];
  final checkedAt = DateTime.parse('2026-09-06T15:12:34+02:00');

  SubscriptionPlanDiagnosticsRunner runner({
    Future<bool> Function()? isConfigured,
    SubscriptionProductLookup? products,
    SubscriptionStorefrontLookup? storefront,
    Duration timeout = const Duration(seconds: 15),
  }) => SubscriptionPlanDiagnosticsRunner(
    isConfigured: isConfigured ?? () async => true,
    getProducts: products ?? (_) async => ids,
    getStorefrontCountry: storefront ?? () async => 'SWE',
    timeout: timeout,
    now: () => checkedAt,
    productIds: ids,
  );

  test(
    'both known plans return a safe UTC report without granting access',
    () async {
      final report = await runner(
        products: (requested) async {
          expect(requested, ids);
          expect(() => requested.add('another'), throwsUnsupportedError);
          return ids.reversed.toList();
        },
      ).check(originalSupportCode: 'RC-23');

      expect(report.category, 'products_available');
      expect(
        report.categoryKind,
        SubscriptionPlanDiagnosticCategory.productsAvailable,
      );
      expect(report.requestedProductIds, ids);
      expect(report.returnedProductIds, ids);
      expect(report.missingProductIds, isEmpty);
      expect(report.storefrontCountryCode, 'SWE');
      expect(report.checkedAtUtc.isUtc, isTrue);
      expect(report.checkedAtUtc.toIso8601String(), '2026-09-06T13:12:34.000Z');
      expect(report.originalSupportCode, 'RC-23');
      expect(report.setupErrorCode, isNull);
      expect(report.productLookupErrorCode, isNull);
      expect(report.storefrontErrorCode, isNull);
      expect(report.supportText, contains('RC-23 (configurationError)'));
      expect(
        report.supportText,
        contains('does not confirm payment, entitlement or release readiness'),
      );
      expect(report.toString(), report.supportText);
      expect(() => report.returnedProductIds.clear(), throwsUnsupportedError);
      expect(
        () => report.missingProductIds.add('another'),
        throwsUnsupportedError,
      );
    },
  );

  test('empty store response identifies both missing products', () async {
    final report = await runner(products: (_) async => []).check();
    expect(report.category, 'products_missing');
    expect(report.returnedProductIds, isEmpty);
    expect(report.missingProductIds, ids);
    expect(report.originalSupportCode, isNull);
    expect(report.supportText, contains('Original error: not_provided'));
    expect(report.productLookupErrorCode, isNull);
  });

  test('Android uses Play subscription IDs and accepts RevenueCat base-plan identifiers', () async {
    const playIds = ['ostoora3', 'ostoora3_pro_max'];
    final report = await SubscriptionPlanDiagnosticsRunner(
      productIds: playIds,
      returnedProductAliases:
          SubscriptionPlanDiagnosticsRunner.googleReturnedProductAliases,
      isConfigured: () async => true,
      getProducts: (requested) async {
        expect(requested, playIds);
        return ['ostoora3:monthly', 'ostoora3_pro_max:yearly'];
      },
      getStorefrontCountry: () async => 'TUR',
      now: () => checkedAt,
    ).check();

    expect(report.category, 'products_available');
    expect(report.requestedProductIds, playIds);
    expect(report.returnedProductIds, playIds);
    expect(report.missingProductIds, isEmpty);
  });

  test('partial response identifies the exact missing known plan', () async {
    final report = await runner(products: (_) async => ['Ostoora3_Pro_Max'])
        .check(originalSupportCode: 'RC-PLANS');
    expect(report.category, 'products_missing');
    expect(report.returnedProductIds, ['Ostoora3_Pro_Max']);
    expect(report.missingProductIds, ['Ostoora3']);
    expect(report.originalSupportCode, 'RC-PLANS');
  });

  test(
    'case variants and duplicate unknown product IDs are never reported',
    () async {
      final report = await runner(
        products: (_) async => [
          'Ostoora3',
          'Ostoora3',
          'ostoora3_pro_max',
          'sk_do_not_report',
          'customer-private-id',
          'receipt-private-data',
        ],
      ).check();
      expect(report.returnedProductIds, ['Ostoora3']);
      expect(report.category, 'products_missing');
      for (final privateValue in [
        'ostoora3_pro_max',
        'sk_do_not_report',
        'customer-private-id',
        'receipt-private-data',
      ]) {
        expect(report.supportText, isNot(contains(privateValue)));
      }
    },
  );

  test(
    'store failure preserves only whitelisted RC code and safe enum name',
    () async {
      final report = await runner(
        products: (_) async => throw PlatformException(
          code: '10',
          message: 'private-token-message',
          details: {
            'receipt': 'private-receipt',
            'customer': 'private-customer',
          },
          stacktrace: 'private-stacktrace',
        ),
      ).check(originalSupportCode: '23');
      expect(report.category, 'store_request_failed');
      expect(report.productLookupErrorCode, 'RC-10');
      expect(report.originalSupportCode, 'RC-23');
      expect(report.supportText, contains('RC-10 (networkError)'));
      expect(report.supportText, isNot(contains('private-')));
      expect(report.storefrontCountryCode, 'SWE');
    },
  );

  test(
    'storefront failure does not misclassify successful product lookup',
    () async {
      final report = await runner(
        storefront: () async =>
            throw PlatformException(code: '35', message: 'secret'),
      ).check();
      expect(report.category, 'products_available');
      expect(report.storefrontCountryCode, isNull);
      expect(report.storefrontErrorCode, 'RC-35');
      expect(report.productLookupErrorCode, isNull);
      expect(report.supportText, isNot(contains('secret')));
    },
  );

  test(
    'missing storefront is safe and does not imply a product failure',
    () async {
      final report = await runner(storefront: () async => null).check();
      expect(report.category, 'products_available');
      expect(report.storefrontCountryCode, isNull);
      expect(report.storefrontErrorCode, isNull);
      expect(report.supportText, contains('Storefront country: unavailable'));
    },
  );

  test('both read callbacks start without waiting for one another', () async {
    final products = Completer<List<String>>();
    final storefront = Completer<String?>();
    var startedProducts = false;
    var startedStorefront = false;
    final pending = runner(
      products: (_) {
        startedProducts = true;
        return products.future;
      },
      storefront: () {
        startedStorefront = true;
        return storefront.future;
      },
    ).check();
    await Future<void>.delayed(Duration.zero);
    expect(startedProducts, isTrue);
    expect(startedStorefront, isTrue);
    storefront.complete('USA');
    products.complete(ids);
    expect((await pending).storefrontCountryCode, 'USA');
  });

  test('both reads time out and late native errors remain handled', () async {
    final products = Completer<List<String>>();
    final storefront = Completer<String?>();
    final report = await runner(
      products: (_) => products.future,
      storefront: () => storefront.future,
      timeout: const Duration(milliseconds: 5),
    ).check();
    expect(report.category, 'store_request_failed');
    expect(report.productLookupErrorCode, 'timeout');
    expect(report.storefrontErrorCode, 'timeout');
    products.completeError(StateError('private-late-error'));
    storefront.completeError(StateError('private-late-error'));
    await Future<void>.delayed(Duration.zero);
  });

  test('a storefront timeout still reports available plans', () async {
    final report = await runner(
      storefront: () => Completer<String?>().future,
      timeout: const Duration(milliseconds: 5),
    ).check();
    expect(report.category, 'products_available');
    expect(report.storefrontErrorCode, 'timeout');
    expect(report.productLookupErrorCode, isNull);
  });

  test('synchronous callback exceptions are also contained', () async {
    final report = await runner(
      products: (_) => throw StateError('private-product-state'),
      storefront: () => throw ArgumentError('private-storefront-state'),
    ).check();
    expect(report.category, 'store_request_failed');
    expect(report.productLookupErrorCode, 'unknown_error');
    expect(report.storefrontErrorCode, 'unknown_error');
    expect(report.supportText, isNot(contains('private-')));
  });

  test(
    'raw private inputs and malformed codes are never copied to any report',
    () async {
      for (final privateValue in [
        'sk_private_secret',
        'appl_private_key',
        'test_private_key',
        'JWT.a-private-token.signature',
        'person@example.com',
        '49ec7b89-9ade-43e3-bbd9-19c0ecb31ccf',
        '-----BEGIN PRIVATE KEY-----',
        'RC-23\nprivate-receipt',
        '-1',
        '999999',
        '23.0',
        ' 23 ',
        '23e0',
      ]) {
        final report = await runner(
          products: (_) async => throw PlatformException(
            code: privateValue,
            message: privateValue,
            details: privateValue,
          ),
          storefront: () async => privateValue,
        ).check(originalSupportCode: privateValue);
        expect(report.originalSupportCode, 'unknown_error');
        expect(report.productLookupErrorCode, 'unknown_error');
        expect(report.storefrontCountryCode, isNull);
        expect(report.supportText, isNot(contains(privateValue)));
      }
    },
  );

  test(
    'known SDK enum names are converted to stable numeric support codes',
    () async {
      final report = await runner(
        products: (_) async =>
            throw PlatformException(code: 'productRequestTimeout'),
      ).check(originalSupportCode: 'configurationError');
      expect(report.productLookupErrorCode, 'RC-32');
      expect(report.originalSupportCode, 'RC-23');
      expect(report.supportText, contains('RC-32 (productRequestTimeout)'));
    },
  );

  test('only bounded alphabetic storefront codes are exposed', () async {
    for (final (input, expected) in [
      ('swe', 'SWE'),
      ('us', 'US'),
      ('S', null),
      ('SWEDEN', null),
      (' SWE ', null),
      ('SE\n', null),
      ('S3E', null),
      ('åäö', null),
    ]) {
      expect(
        (await runner(
          storefront: () async => input,
        ).check()).storefrontCountryCode,
        expected,
      );
    }
  });

  test('nonpositive timeouts are rejected immediately', () {
    expect(() => runner(timeout: Duration.zero), throwsArgumentError);
    expect(
      () => runner(timeout: const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });

  test(
    'default adapter checks setup before the two read-only SDK methods',
    () async {
      const channel = MethodChannel('purchases_flutter');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'isConfigured':
            return true;
          case 'getProductInfo':
            expect(call.arguments, {
              'productIdentifiers': ids,
              'type': 'subscription',
            });
            return [
              for (final id in ids)
                {
                  'identifier': id,
                  'description': 'private description',
                  'title': 'private title',
                  'price': 123.45,
                  'priceString': 'private price',
                  'currencyCode': 'USD',
                },
            ];
          case 'getStorefront':
            return {'countryCode': 'SWE', 'privateCustomer': 'not-for-report'};
          default:
            fail('Diagnostic called an unexpected SDK method: ${call.method}');
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final report = await SubscriptionPlanDiagnosticsRunner(productIds: ids)
          .check();
      expect(report.category, 'products_available');
      expect(calls.map((call) => call.method), [
        'isConfigured',
        'getProductInfo',
        'getStorefront',
      ]);
      expect(report.supportText, isNot(contains('private')));
      expect(report.supportText, isNot(contains('123.45')));
      expect(report.supportText, isNot(contains('not-for-report')));
    },
  );

  test(
    'unconfigured SDK never starts native product or storefront lookup',
    () async {
      var lookupCalls = 0;
      final report = await runner(
        isConfigured: () async => false,
        products: (_) async {
          lookupCalls++;
          return ids;
        },
        storefront: () async {
          lookupCalls++;
          return 'SWE';
        },
      ).check(originalSupportCode: 'RC-23');
      expect(report.category, 'store_request_failed');
      expect(report.setupErrorCode, 'sdk_not_configured');
      expect(report.productLookupErrorCode, 'not_started');
      expect(report.storefrontErrorCode, 'not_started');
      expect(report.returnedProductIds, isEmpty);
      expect(report.originalSupportCode, 'RC-23');
      expect(lookupCalls, 0);
      expect(report.supportText, contains('SDK setup: sdk_not_configured'));
    },
  );

  test('setup errors are sanitized and prevent both native lookups', () async {
    for (final error in [
      PlatformException(
        code: '23',
        message: 'private-message',
        details: 'private-key',
      ),
      PlatformException(code: 'private-token', message: 'private-message'),
      StateError('private-state'),
    ]) {
      var lookupCalls = 0;
      final report = await runner(
        isConfigured: () => throw error,
        products: (_) async {
          lookupCalls++;
          return ids;
        },
        storefront: () async {
          lookupCalls++;
          return 'SWE';
        },
      ).check();
      expect(report.category, 'store_request_failed');
      expect(
        report.setupErrorCode,
        error is PlatformException && error.code == '23'
            ? 'RC-23'
            : 'unknown_error',
      );
      expect(report.productLookupErrorCode, 'not_started');
      expect(report.storefrontErrorCode, 'not_started');
      expect(lookupCalls, 0);
      expect(report.supportText, isNot(contains('private-')));
    }
  });

  test(
    'setup timeout prevents lookups even if setup eventually succeeds',
    () async {
      final setup = Completer<bool>();
      var lookupCalls = 0;
      final report = await runner(
        isConfigured: () => setup.future,
        products: (_) async {
          lookupCalls++;
          return ids;
        },
        storefront: () async {
          lookupCalls++;
          return 'SWE';
        },
        timeout: const Duration(milliseconds: 5),
      ).check();
      expect(report.category, 'store_request_failed');
      expect(report.setupErrorCode, 'timeout');
      expect(report.productLookupErrorCode, 'not_started');
      expect(report.storefrontErrorCode, 'not_started');
      setup.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(lookupCalls, 0);
    },
  );

  test('slow setup and store reads share one overall deadline', () async {
    final elapsed = Stopwatch()..start();
    final report = await runner(
      isConfigured: () async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return true;
      },
      products: (_) => Completer<List<String>>().future,
      storefront: () => Completer<String?>().future,
      timeout: const Duration(milliseconds: 200),
    ).check();
    expect(report.setupErrorCode, isNull);
    expect(report.productLookupErrorCode, 'timeout');
    expect(report.storefrontErrorCode, 'timeout');
    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 300)));
  });

  test(
    'default SDK adapter does not invoke native lookups while unconfigured',
    () async {
      const channel = MethodChannel('purchases_flutter');
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return false;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final report = await SubscriptionPlanDiagnosticsRunner().check();
      expect(report.setupErrorCode, 'sdk_not_configured');
      expect(calls, ['isConfigured']);
    },
  );
}
