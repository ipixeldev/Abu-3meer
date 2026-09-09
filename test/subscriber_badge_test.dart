import 'dart:ui' as ui;

import 'package:abu_3meer/core/widgets/subscriber_badge.dart';
import 'package:abu_3meer/production/api_production_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'badge source retains the original JPG dimensions and white star',
    () async {
      final data = await rootBundle.load(
        'assets/images/subscriber_badge_source.jpg',
      );
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(frame.image.width, 626);
      expect(frame.image.height, 548);
      // The original black rectangle is preserved in the source file. Only
      // the widget viewport removes it from the displayed badge.
      expect(pixels.getUint8(3), 255);
      expect(pixels.getUint8(0), lessThan(10));
      expect(pixels.getUint8(1), lessThan(10));
      expect(pixels.getUint8(2), lessThan(10));
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

  for (final language in ['en', 'ar']) {
    for (final size in [18.0, 28.0, 64.0]) {
      testWidgets(
        'original badge has a clean circular viewport at $size ($language)',
        (tester) async {
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SubscriberBadge(size: size),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/images/subscriber_badge_source.jpg'),
              tester.element(find.byType(SubscriberBadge)),
            ),
          );
          await tester.pumpAndSettle();
          final semantics = tester.ensureSemantics();
          try {
            await tester.pump();
            expect(
              find.bySemanticsLabel(language == 'ar' ? 'مشترك' : 'Subscriber'),
              findsOneWidget,
            );
          } finally {
            semantics.dispose();
          }
          expect(
            tester.getSize(find.byType(SubscriberBadge)),
            Size.square(size),
          );
          expect(find.byType(ClipOval), findsOneWidget);
          final image = tester.widget<Image>(find.byType(Image));
          expect(
            (image.image as AssetImage).assetName,
            'assets/images/subscriber_badge_source.jpg',
          );
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final raster = await boundary.toImage(pixelRatio: 3);
            final pixels = (await raster.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final width = raster.width;
            final height = raster.height;
            int channel(int x, int y, int component) =>
                pixels.getUint8((y * width + x) * 4 + component);
            // Transparent corners prove the source's black rectangle is not
            // painted; the star and inner green disk remain original pixels.
            for (final point in [
              (0, 0),
              (width - 1, 0),
              (0, height - 1),
              (width - 1, height - 1),
            ]) {
              expect(channel(point.$1, point.$2, 3), 0);
            }
            final centerX = width ~/ 2;
            final centerY = height ~/ 2;
            for (final component in [0, 1, 2, 3]) {
              expect(channel(centerX, centerY, component), greaterThan(240));
            }
            final greenY = (height * .08).round();
            expect(channel(centerX, greenY, 1), greaterThan(150));
            expect(channel(centerX, greenY, 0), lessThan(80));
            // No dark halo or generated noise inside the circular crop.
            final innerRadius = width / 2 - 2;
            for (var y = 0; y < height; y++) {
              for (var x = 0; x < width; x++) {
                final dx = x + .5 - width / 2;
                final dy = y + .5 - height / 2;
                if (dx * dx + dy * dy < innerRadius * innerRadius) {
                  expect(channel(x, y, 1), greaterThan(120));
                }
              }
            }
            raster.dispose();
          });
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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

  test('leaderboard and admin expose effective member access for badges', () {
    for (final value in [null, false, 'true', 1]) {
      final data = {
        'isYouTubeMember': true,
        'role': 'superAdmin',
        'isProSubscriber': value,
      };
      expect(parseApiLeaderboardEntry(data).isProSubscriber, isFalse);
      expect(parseApiLeaderboardEntry(data).hasMemberAccess, isTrue);
      expect(parseAdminUserProfile(data).isProSubscriber, isFalse);
      expect(parseAdminUserProfile(data).hasMemberAccess, isTrue);
    }
    final data = {'isProSubscriber': true, 'isYouTubeMember': false};
    final entry = parseApiLeaderboardEntry(data);
    expect(entry.isProSubscriber, isTrue);
    expect(entry.isMember, isFalse);
    expect(entry.hasMemberAccess, isTrue);
    final profile = parseAdminUserProfile(data);
    expect(profile.isProSubscriber, isTrue);
    expect(profile.isYouTubeMember, isFalse);
    expect(profile.hasMemberAccess, isTrue);
    expect(profile.copyWith(displayName: 'renamed').isProSubscriber, isTrue);
    expect(profile.copyWith(displayName: 'renamed').hasMemberAccess, isTrue);

    final blocked = parseAdminUserProfile({
      'isYouTubeMember': true,
      'youtubeMembershipActive': true,
      'hasMemberAccess': false,
      'subscriptionAccessReason': 'admin_revoked',
    });
    expect(blocked.isYouTubeMember, isFalse);
    expect(blocked.hasMemberAccess, isFalse);
    expect(blocked.copyWith(displayName: 'blocked').hasMemberAccess, isFalse);
  });
}
