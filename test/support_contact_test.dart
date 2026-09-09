import 'dart:async';

import 'package:abu_3meer/features/support/whatsapp_support_button.dart';
import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/support_contact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('only a canonical HTTPS WhatsApp phone link is accepted', () {
    expect(
      SupportContactService.validatedWhatsAppUri('https://wa.me/46701234567')
          ?.host,
      'wa.me',
    );
    for (final input in [
      null,
      123,
      'https://evil.example/46701234567',
      'https://wa.me.evil.example/46701234567',
      'http://wa.me/46701234567',
      'https://user@wa.me/46701234567',
      'https://wa.me:443/46701234567',
      'https://wa.me/46701234567?text=private',
      'https://wa.me/46701234567#fragment',
      'https://wa.me/+46701234567',
      'https://wa.me/0046701234567',
    ]) {
      expect(SupportContactService.validatedWhatsAppUri(input), isNull);
    }
  });

  test(
    'contact request is public and fetches the current server number every tap',
    () async {
      var requests = 0;
      final launched = <Uri>[];
      final service = SupportContactService(
        api: AbuApiClient(
          httpClient: MockClient((request) async {
            requests++;
            expect(request.method, 'GET');
            expect(request.url.path, '/api/v1/support/contact');
            expect(request.headers.containsKey('Authorization'), isFalse);
            expect(request.body, isEmpty);
            return http.Response(
              '{"data":{"whatsappUrl":"https://wa.me/46701234567"}}',
              200,
            );
          }),
        ),
        launch: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      expect(await service.openWhatsApp(), SupportContactResult.opened);
      expect(await service.openWhatsApp(), SupportContactResult.opened);
      expect(requests, 2);
      expect(launched, hasLength(2));
      expect(launched.first.query, isEmpty);
    },
  );

  test(
    'unset, malformed and unavailable contacts never launch an external URL',
    () async {
      for (final example in [
        (
          '{"data":{"whatsappUrl":null}}',
          200,
          SupportContactResult.notConfigured,
        ),
        (
          '{"data":{"whatsappUrl":"https://evil.example"}}',
          200,
          SupportContactResult.unavailable,
        ),
        ('{}', 200, SupportContactResult.unavailable),
        ('{}', 503, SupportContactResult.unavailable),
      ]) {
        var launchCalls = 0;
        final service = SupportContactService(
          api: AbuApiClient(
            httpClient: MockClient(
              (_) async => http.Response(example.$1, example.$2),
            ),
          ),
          launch: (_) async {
            launchCalls++;
            return true;
          },
        );
        expect(await service.openWhatsApp(), example.$3);
        expect(launchCalls, 0);
      }
    },
  );

  test(
    'failed external launch is caught without exposing exception details',
    () async {
      final service = SupportContactService(
        api: AbuApiClient(
          httpClient: MockClient(
            (_) async => http.Response(
              '{"data":{"whatsappUrl":"https://wa.me/46701234567"}}',
              200,
            ),
          ),
        ),
        launch: (_) async => throw StateError('private platform detail'),
      );
      expect(await service.openWhatsApp(), SupportContactResult.launchFailed);
    },
  );

  for (final language in ['en', 'ar']) {
    testWidgets('support shows a helpful unset-number message ($language)', (
      tester,
    ) async {
      var requests = 0;
      final service = SupportContactService(
        api: AbuApiClient(
          httpClient: MockClient((_) async {
            requests++;
            return http.Response('{"data":{"whatsappUrl":null}}', 200);
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: WhatsAppSupportButton(service: service)),
        ),
      );
      expect(requests, 0);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.textContaining('support@abu3meer.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'busy contact button prevents repeated taps and tolerates disposal',
    (tester) async {
      final pending = Completer<http.Response>();
      var requests = 0;
      var launchCalls = 0;
      final service = SupportContactService(
        api: AbuApiClient(
          httpClient: MockClient((_) {
            requests++;
            return pending.future;
          }),
        ),
        launch: (_) async {
          launchCalls++;
          return true;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WhatsAppSupportButton(service: service)),
        ),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(
        http.Response(
          '{"data":{"whatsappUrl":"https://wa.me/46701234567"}}',
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(launchCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
