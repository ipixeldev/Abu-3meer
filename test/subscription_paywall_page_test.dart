import 'dart:async';

import 'package:abu_3meer/features/subscriptions/subscription_paywall_page.dart';
import 'package:abu_3meer/production/subscription_service.dart';
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
