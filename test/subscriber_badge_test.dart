import 'dart:ui' as ui;

import 'package:abu_3meer/core/widgets/subscriber_badge.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'badge asset has a transparent background and opaque white star',
    () async {
      final data = await rootBundle.load('assets/images/subscriber_badge.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(pixels.getUint8(3), 0);
      final center =
          ((frame.image.height ~/ 2) * frame.image.width +
              frame.image.width ~/ 2) *
          4;
      expect(pixels.getUint8(center + 3), greaterThanOrEqualTo(250));
      expect(pixels.getUint8(center), greaterThan(240));
      expect(pixels.getUint8(center + 1), greaterThan(240));
      expect(pixels.getUint8(center + 2), greaterThan(240));
      frame.image.dispose();
      codec.dispose();
    },
  );

  Widget preview({bool active = true, bool arabic = false, double scale = 1}) =>
      MaterialApp(
        locale: Locale(arabic ? 'ar' : 'en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: SizedBox(
                width: 110,
                child: SubscriberName(
                  arabic
                      ? 'أبو عمير مشجع كرة القدم'
                      : 'A very long subscriber name',
                  isSubscriber: active,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('badge follows current status, including expiration', (
    tester,
  ) async {
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(find.byType(SubscriberBadge), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(preview(active: false));
    expect(find.byType(SubscriberBadge), findsNothing);
  });

  for (final arabic in [false, true]) {
    testWidgets('long name keeps badge visible at large text, Arabic=$arabic', (
      tester,
    ) async {
      await tester.pumpWidget(preview(arabic: arabic, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final name = tester.getRect(find.byType(Text).first);
      final badge = tester.getRect(find.byType(SubscriberBadge));
      expect(
        arabic ? badge.right <= name.left : badge.left >= name.right,
        isTrue,
      );
      expect(badge.width, 16);
    });
  }

  test('leaderboard and admin preserve only explicit subscription flag', () {
    for (final value in [null, false, 'true', 1]) {
      final data = {
        'isYouTubeMember': true,
        'role': 'superAdmin',
        'isProSubscriber': value,
      };
      expect(parseApiLeaderboardEntry(data).isProSubscriber, isFalse);
      expect(parseAdminUserProfile(data).isProSubscriber, isFalse);
    }
    final data = {'isProSubscriber': true, 'isYouTubeMember': false};
    final entry = parseApiLeaderboardEntry(data);
    expect(entry.isProSubscriber, isTrue);
    expect(entry.isMember, isFalse);
    final profile = parseAdminUserProfile(data);
    expect(profile.isProSubscriber, isTrue);
    expect(profile.isYouTubeMember, isFalse);
    expect(profile.copyWith(displayName: 'renamed').isProSubscriber, isTrue);
  });
}
