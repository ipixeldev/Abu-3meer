import 'dart:async';

import 'package:abu_3meer/features/subscriptions/subscription_paywall_page.dart';
import 'package:abu_3meer/production/subscription_service.dart';
import 'package:abu_3meer/production/subscription_plan_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class _LoadingStore extends SubscriptionService {
  _LoadingStore() : super.forTesting();
  int loads = 0;
  Completer<PaywallResult> next = Completer<PaywallResult>();
  @override
  Future<PaywallResult> showPaywall(
    String userId, {
    Future<PaywallResult> Function(Offering)? presenter,
    String? locale,
  }) {
    loads++;
    return next.future;
  }
}

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets(
      'store report is explicit, read-only and safe to copy ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _LoadingStore();
        addTearDown(store.dispose);
        var productReads = 0;
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = call.arguments['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: SubscriptionPaywallPage(
              service: store,
              userId: 'private-account',
              diagnostics: SubscriptionPlanDiagnosticsRunner(
                getProducts: (ids) async {
                  productReads++;
                  expect(ids, ['Ostoora3', 'Ostoora3_Pro_Max']);
                  return [];
                },
                getStorefrontCountry: () async => 'SWE',
              ),
            ),
          ),
        );
        await tester.pump();
        store.next.completeError(
          PlatformException(code: '23', message: 'private receipt secret'),
        );
        await tester.pumpAndSettle();
        expect(productReads, 0);
        await tester.ensureVisible(
          find.byKey(const Key('check-subscription-store')),
        );
        await tester.tap(find.byKey(const Key('check-subscription-store')));
        await tester.pumpAndSettle();
        expect(productReads, 1);
        final text = tester
            .widget<SelectableText>(
              find.byKey(const Key('subscription-store-report')),
            )
            .data!;
        expect(text, contains('products_missing'));
        expect(text, contains('RC-23'));
        expect(text, contains('SWE'));
        expect(text, isNot(contains('private')));
        await tester.ensureVisible(
          find.byKey(const Key('copy-subscription-store-report')),
        );
        await tester.tap(
          find.byKey(const Key('copy-subscription-store-report')),
        );
        await tester.pumpAndSettle();
        expect(copied, text);
        expect(store.loads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('closing while a store check runs ignores its late result', (
    tester,
  ) async {
    final store = _LoadingStore();
    final products = Completer<List<String>>();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SubscriptionPaywallPage(
                    service: store,
                    userId: 'account-1',
                    diagnostics: SubscriptionPlanDiagnosticsRunner(
                      getProducts: (_) => products.future,
                      getStorefrontCountry: () async => null,
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    store.next.completeError(PlatformException(code: '23'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-subscription-store')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('close-subscription-paywall')));
    await tester.pumpAndSettle();
    products.complete(['Ostoora3', 'Ostoora3_Pro_Max']);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byKey(const Key('subscription-store-report')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      'one tap opens visible loading, retained error and retry ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _LoadingStore();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => SubscriptionPaywallPage.open(
                    context,
                    service: store,
                    userId: 'account-1',
                  ),
                  child: const Text('Open plans'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open plans'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const Key('subscription-paywall-page')),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'en'
                ? 'Loading subscription plans…'
                : 'جارٍ تحميل خطط الاشتراك…',
          ),
          findsOneWidget,
        );
        store.next.completeError(
          PlatformException(
            code: '23',
            message: 'private receipt / user identity',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('RC-23'), findsOneWidget);
        expect(find.textContaining('private receipt'), findsNothing);
        expect(
          find.text(language == 'en' ? 'Plans unavailable' : 'الخطط غير متاحة'),
          findsOneWidget,
        );
        store.next = Completer<PaywallResult>();
        await tester.tap(
          find.text(language == 'en' ? 'Try again' : 'حاول مجدداً'),
        );
        await tester.pump();
        expect(store.loads, 2);
        await tester.tap(find.byKey(const Key('close-subscription-paywall')));
        await tester.pumpAndSettle();
        expect(find.text('Open plans'), findsOneWidget);
        store.next.complete(PaywallResult.cancelled);
        await tester.pumpAndSettle();
        expect(find.text('Open plans'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
