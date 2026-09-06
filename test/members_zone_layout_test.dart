import 'package:abu_3meer/features/videos/exclusive_videos_view.dart';
import 'package:abu_3meer/production/models.dart';
import 'package:abu_3meer/production/production_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _VideoRepository implements ProductionRepository {
  var refreshes = 0;

  @override
  Future<void> refreshExclusiveVideos({bool force = true}) async {
    refreshes++;
  }

  @override
  Stream<List<ExclusiveVideo>> watchExclusiveVideos() => Stream.value([
    for (final index in [1, 2])
      ExclusiveVideo(
        id: '$index',
        youtubeId: '',
        title: 'Member video $index',
        thumbnailUrl: '',
        videoUrl: '',
        publishedAt: DateTime(2026, 9, 6),
      ),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets(
      'Members Zone leads with video before compact subscription row ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _VideoRepository();
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: ExclusiveVideosView(
                repository: repository,
                profile: AbuUserProfile.guest(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final summary = find.byKey(const Key('subscription-summary'));
        expect(
          tester.getTopLeft(find.text('Member video 1')).dy,
          lessThan(tester.getTopLeft(summary).dy),
        );
        expect(
          tester.getTopLeft(summary).dy,
          lessThan(tester.getTopLeft(find.text('Member video 2')).dy),
        );
        expect(tester.getSize(summary).height, lessThan(170));
        expect(find.text('Restore purchases'), findsNothing);
        expect(repository.refreshes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
