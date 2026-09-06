import 'dart:async';

import 'package:abu_3meer/features/membership/manual_membership_dialog.dart';
import 'package:abu_3meer/production/api_client.dart';
import 'package:abu_3meer/production/youtube_membership_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'UC1234567890123456789012';
  const link = 'https://www.youtube.com/channel/$id';

  test('profile link parser accepts stable channel URLs and rejects impostor/video/handle URLs', () {
    expect(channelIdFromProfileLink(link), id);
    expect(
      channelIdFromProfileLink('https://m.youtube.com/channel/$id/?si=share'),
      id,
    );
    for (final invalid in [
      id,
      'https://youtube.com/@name',
      'http://youtube.com/channel/$id',
      'https://youtube.com.evil.test/channel/$id',
      'https://someone@youtube.com/channel/$id',
      'https://youtube.com:123/channel/$id',
      '$link/videos',
      'https://youtu.be/$id',
    ]) {
      expect(channelIdFromProfileLink(invalid), isNull, reason: invalid);
    }
  });

  test('profile validator accepts shared handles and legacy profile URLs', () {
    for (final profileLink in [
      link,
      'https://youtube.com/@aeyaall',
      'https://m.youtube.com/@aeyaalli7979?si=shared#channel',
      'https://youtube.com/@أبو_عمير',
      'https://youtube.com/@%D8%A3%D8%A8%D9%88_%D8%B9%D9%85%D9%8A%D8%B1/',
      'https://www.youtube.com/c/CreatorName',
      'https://www.youtube.com/user/CreatorName/',
    ]) {
      expect(isYouTubeProfileLink(profileLink), isTrue, reason: profileLink);
    }
    for (final invalid in [
      id,
      '@name',
      'https://youtube.com/@',
      'https://youtube.com/@name/videos',
      'https://youtube.com/@name%2Fwatch',
      'https://youtube.com/@name%0A',
      'https://youtube.com/@name%ZZ',
      'https://youtube.com.evil.test/@name',
      'https://attacker@youtube.com/@name',
      'https://youtube.com:443/@name',
      'https://youtube.com/watch?v=video',
      'https://youtu.be/video',
    ]) {
      expect(isYouTubeProfileLink(invalid), isFalse, reason: invalid);
    }
  });

  for (final language in ['en', 'ar']) {
    testWidgets(
      'manual check is usable at 320px in $language and cannot double-submit',
      (tester) async {
        tester.view.physicalSize = const Size(320, 750);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<YouTubeMembershipCheckResult>();
        var checks = 0;
        YouTubeMembershipCheckResult? received;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    received = await showDialog<YouTubeMembershipCheckResult>(
                      context: context,
                      builder: (_) => ManualMembershipDialog(
                        onCheck: (value) {
                          expect(
                            value,
                            'https://youtube.com/@aeyaall?si=share',
                          );
                          checks++;
                          return pending.future;
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = find.byKey(const Key('youtube-profile-link-input'));
        await tester.enterText(field, 'https://youtube.com/@aeyaall?si=share');
        final button = find.byType(FilledButton);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(checks, 1);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        pending.complete(
          parseYouTubeMembershipCheckEnvelope({
            'membership': {
              'status': 'not_in_snapshot',
              'isMember': false,
              'youtubeChannelId': id,
              'verifiedAt': '2026-09-05T12:00:00Z',
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(received?.status, YouTubeMembershipCheckStatus.notInSnapshot);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['en', 'ar']) {
    final updateMessage = language == 'ar'
        ? 'التحقق من العضوية يحتاج إلى تحديث الخادم. تواصل مع الدعم.'
        : 'Membership checking needs a server update. Contact support.';
    for (final error in [
      AbuApiException(
        statusCode: 404,
        message: 'Route POST:/profile/youtube/membership/check not found',
      ),
      AbuApiException(
        statusCode: 400,
        message: 'A valid short-lived Google access token is required.',
      ),
      AbuApiException(
        statusCode: 400,
        message: 'ValidationError',
        details: {
          'fieldErrors': {
            'accessToken': ['Required'],
          },
        },
      ),
      AbuApiException(
        statusCode: 400,
        message: 'This YouTube profile could not be found.',
      ),
      AbuApiException(
        statusCode: 503,
        message: 'YouTube could not resolve this profile right now.',
      ),
    ]) {
      testWidgets(
        'membership $language handles ${error.statusCode} ${error.message}',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: ManualMembershipDialog(onCheck: (_) async => throw error),
              ),
            ),
          );
          await tester.enterText(
            find.byType(TextFormField),
            'https://youtube.com/@aeyaall',
          );
          await tester.ensureVisible(find.byType(FilledButton));
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          final needsUpdate =
              error.statusCode == 404 ||
              error.message.contains('Google access token') ||
              error.details != null;
          expect(
            find.text(needsUpdate ? updateMessage : error.message),
            findsOneWidget,
          );
          if (needsUpdate) {
            expect(find.textContaining('access token'), findsNothing);
          }
          expect(
            tester
                .widget<TextFormField>(find.byType(TextFormField))
                .controller!
                .text,
            'https://youtube.com/@aeyaall',
          );
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNotNull,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('server failure keeps the link and enables retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualMembershipDialog(
            onCheck: (_) async => throw AbuApiException(
              statusCode: 409,
              message: 'This channel is already linked.',
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), link);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('already linked'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      link,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
