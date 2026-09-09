import 'package:abu_3meer/core/widgets/subscriber_badge.dart';
import 'package:abu_3meer/demo/fan_league_app.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localizedApp(String language, Widget child) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData(fontFamily: language == 'ar' ? 'Cairo' : 'Inter'),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Inter', 'Cairo']) {
      final loader = FontLoader(font)
        ..addFont(rootBundle.load('assets/fonts/$font-Variable.ttf'));
      await loader.load();
    }
  });
  for (final language in ['en', 'ar']) {
    testWidgets(
      'country results stay tappable above the keyboard ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        String? selected;
        await tester.pumpWidget(
          _localizedApp(
            language,
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showProductionCountryPickerForTesting(
                    context,
                  );
                },
                child: const Text('Open countries'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open countries'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('country-search-input'));
        await tester.enterText(field, language == 'en' ? 'Germany' : 'ألمانيا');
        await tester.pumpAndSettle();
        final result = find.byKey(const ValueKey('country-DE'));
        expect(result, findsOneWidget);
        final list = tester.getRect(
          find.byKey(const Key('country-search-results')),
        );
        expect(list.height, greaterThan(56));
        expect(tester.getRect(result).bottom, lessThanOrEqualTo(640 - 300));
        expect(
          tester.getRect(result).top,
          greaterThan(tester.getRect(field).bottom),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(selected, 'DE');
      },
    );

    testWidgets('fan card edit stays opposite XP in $language', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edits = 0;
      await tester.pumpWidget(
        _localizedApp(
          language,
          productionFanCardForTesting(
            profile: AbuUserProfile.guest(),
            onEdit: () => edits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final xp = tester.getRect(find.byKey(const Key('fan-card-xp-heading')));
      final edit = tester.getRect(
        find.byKey(const Key('fan-card-edit-button')),
      );
      expect(edit.overlaps(xp), isFalse);
      if (language == 'ar') {
        expect(edit.right, lessThan(xp.left));
      } else {
        expect(edit.left, greaterThan(xp.right));
      }
      await tester.tap(find.byKey(const Key('fan-card-edit-button')));
      expect(edits, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'members navigation uses its badge and localized title ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _localizedApp(
            language,
            Align(
              alignment: Alignment.bottomCenter,
              child: Builder(builder: productionRootNavigationForTesting),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text(language == 'en' ? 'Members' : 'الأعضاء');
        expect(title, findsOneWidget);
        expect(find.byType(SubscriberBadge), findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(title);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason:
              'Navigation label size ${paragraph.size}, intrinsic ${paragraph.getMaxIntrinsicWidth(double.infinity)}, style ${paragraph.text.style}',
        );
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
