import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home reads the dedicated public-video endpoint, never Exclusive data',
    () {
      final api = File('lib/production/api_production_repository.dart')
          .readAsStringSync();
      final repository = File('lib/production/production_repository.dart')
          .readAsStringSync();
      final start = repository.indexOf('Future<LatestVideo> latestVideo');
      final end = repository.indexOf(
        'Future<FootballTeamAsset?> lookupTeam',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final latestVideo = repository.substring(start, end);

      expect(api, contains("'/videos/latest'"));
      expect(latestVideo, contains('fetchLatestPublicVideo'));
      expect(latestVideo, contains('externalContent.latestVideo'));
      expect(latestVideo, isNot(contains("doc('latestVideo')")));
      expect(latestVideo, isNot(contains('fetchExclusiveVideos')));
    },
  );
}
