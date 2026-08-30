import 'dart:io';

import 'package:abu_3meer/production/production_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('exclusive video input', () {
    const videoId = 'dQw4w9WgXcQ';

    test('extracts canonical IDs from supported YouTube links', () {
      expect(extractYoutubeVideoId(videoId), videoId);
      expect(extractYoutubeVideoId('https://youtu.be/$videoId?t=10'), videoId);
      expect(
        extractYoutubeVideoId('https://www.youtube.com/watch?v=$videoId'),
        videoId,
      );
      expect(
        extractYoutubeVideoId('https://youtube.com/shorts/$videoId'),
        videoId,
      );
      expect(
        extractYoutubeVideoId(
          'https://www.youtube-nocookie.com/embed/$videoId',
        ),
        videoId,
      );
    });

    test('rejects arbitrary hosts and malformed IDs', () {
      expect(extractYoutubeVideoId('iamr.dev'), isNull);
      expect(
        extractYoutubeVideoId('https://example.com/watch?v=$videoId'),
        isNull,
      );
      expect(extractYoutubeVideoId('too-short'), isNull);
    });
  });

  test('blank challenge prompt intentionally falls back to its title', () {
    expect(
      effectiveChallengePrompt(title: 'Name this player', prompt: '  '),
      'Name this player',
    );
    expect(
      effectiveChallengePrompt(
        title: 'Name this player',
        prompt: 'Which player is shown?',
      ),
      'Which player is shown?',
    );
  });

  test(
    'a successful content mutation force-refreshes every live feed',
    () async {
      final calls = <String>[];

      await runMutationAndForceRefresh(
        mutation: () async => calls.add('mutate'),
        refreshers: [
          () async => calls.add('public'),
          () async => calls.add('admin'),
        ],
      );

      expect(calls.first, 'mutate');
      expect(calls.skip(1), containsAll(<String>['public', 'admin']));
    },
  );

  test(
    'a rejected mutation cannot publish a misleading refreshed state',
    () async {
      var refreshCount = 0;

      await expectLater(
        runMutationAndForceRefresh(
          mutation: () async => throw StateError('rejected'),
          refreshers: [() async => refreshCount += 1],
        ),
        throwsStateError,
      );

      expect(refreshCount, 0);
    },
  );

  test('Challenges exposes Player Guess without a collectible-card shelf', () {
    final source = File('lib/demo/production_features.dart').readAsStringSync();
    final challengesStart = source.indexOf('class _ProductionChallenges');
    final challengeGridStart = source.indexOf('class _ProductionChallengeGrid');
    final challenges = source.substring(challengesStart, challengeGridStart);

    expect(challenges, isNot(contains('_ProductionPlayerCardCollection')));
    expect(source, contains("'Guess the player'"));
    expect(source, contains("'Private player name'"));
    expect(source, contains('repository.resetAnnouncement'));
  });

  test('claimed disabled Player Cards are not filtered out by the client', () {
    final source = File('lib/demo/production_features.dart').readAsStringSync();
    final collectionStart = source.indexOf(
      'class _ProductionPlayerCardCollection',
    );
    final tileStart = source.indexOf(
      'class _PlayerCollectionCard',
      collectionStart,
    );
    final collection = source.substring(collectionStart, tileStart);

    expect(collection, isNot(contains('.where((card) => card.enabled)')));
    expect(collection, contains('final cards = snapshot.data'));
  });

  test('Player Guess creation has no catalogue-card dependency', () {
    final source = File('lib/demo/production_features.dart').readAsStringSync();
    final createStart = source.indexOf('Future<void> createChallenge(');
    final createEnd = source.indexOf(
      'Future<void> editAnnouncement',
      createStart,
    );
    final creator = source.substring(createStart, createEnd);

    expect(creator, contains("var kind = initialKind == 'playerCard'"));
    expect(creator, contains("'Private player name'"));
    expect(creator, contains('acceptedAnswers'));
    expect(creator, isNot(contains('availablePlayerCards')));
    expect(creator, isNot(contains('Card unlocked by this challenge')));
    expect(creator, isNot(contains('playerCardId:')));
  });

  test('selecting mounted content tabs still performs a forced refresh', () {
    final source = File('lib/demo/production_ui.dart').readAsStringSync();

    expect(source, contains('refreshChallenges(force: true)'));
    expect(
      source,
      contains('refreshPlayerCards(widget.profile.uid, force: true)'),
    );
    expect(source, contains('refreshExclusiveVideos(force: true)'));
  });

  test('launch-popup editor remains compatible with AlertDialog intrinsics', () {
    final source = File('lib/demo/production_features.dart').readAsStringSync();
    final editorStart = source.indexOf(
      'Future<void> editAnnouncement(BuildContext context)',
    );
    final editorEnd = source.indexOf(
      'Future<void> manageAchievements',
      editorStart,
    );
    final editor = source.substring(editorStart, editorEnd);

    // AlertDialog uses IntrinsicWidth. A LayoutBuilder anywhere in this
    // subtree throws during layout on Android and leaves only the dim barrier.
    expect(editor, isNot(contains('LayoutBuilder(')));
    expect(editor, contains('MediaQuery.sizeOf(context).width'));
  });

  test(
    'exclusive-video play does not depend on Android package visibility',
    () {
      final source = File('lib/features/videos/exclusive_videos_view.dart')
          .readAsStringSync();

      expect(source, isNot(contains('canLaunchUrl(')));
      expect(source, contains('LaunchMode.externalApplication'));
      expect(source, contains('LaunchMode.platformDefault'));
      expect(source, contains('formatCompactDate'));
    },
  );
}
