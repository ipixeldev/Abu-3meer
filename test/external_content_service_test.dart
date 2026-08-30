import 'package:abu_3meer/production/external_content_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads the newest Abu 3meer upload from the channel feed', () async {
    final service = AbuExternalContentService(
      client: MockClient(
        (_) async => http.Response(
          '''{"status":"ok","items":[{"title":"Newest upload","link":"https://www.youtube.com/watch?v=video123","thumbnail":"https://img.test/video.jpg","pubDate":"2026-08-16 20:00:00"}]}''',
          200,
        ),
      ),
    );

    final video = await service.latestVideo();

    expect(video.id, 'video123');
    expect(video.title, 'Newest upload');
    expect(video.url, contains('video123'));
  });

  test('chooses the earliest next match across both supported teams', () async {
    final barcelonaKickoff = DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    final realMadridKickoff = DateTime.now()
        .add(const Duration(days: 3))
        .toUtc()
        .toIso8601String();
    final service = AbuExternalContentService(
      client: MockClient((request) async {
        final realMadrid = request.url.queryParameters['id'] == '133738';
        return http.Response(
          '''{"events":[{"idEvent":"${realMadrid ? 'rm1' : 'fcb1'}","strHomeTeam":"${realMadrid ? 'Espanyol' : 'Barcelona'}","strAwayTeam":"${realMadrid ? 'Real Madrid' : 'Al Ahly'}","strLeague":"Friendly","strTimestamp":"${realMadrid ? realMadridKickoff : barcelonaKickoff}","strHomeTeamBadge":"","strAwayTeamBadge":""}]}''',
          200,
        );
      }),
    );

    final match = await service.nextMatch();

    expect(match, isNotNull);
    expect(match!.id, 'external_fcb1');
    expect(match.homeTeam, 'Barcelona');
    expect(match.awayTeam, 'Al Ahly');
  });

  test('normalizes and selects the closest football team result', () async {
    final service = AbuExternalContentService(
      client: MockClient(
        (_) async => http.Response(
          '''{"teams":[{"idTeam":"other","strTeam":"Real Madrid Women","strSport":"Soccer","strBadge":"http://img.test/women.png"},{"idTeam":"133738","strTeam":"Real Madrid","strTeamAlternate":"Real Madrid CF, Los Blancos","strSport":"Soccer","strLeague":"La Liga","strCountry":"Spain","strBadge":"//img.test/real.png"},{"idTeam":"wrong-sport","strTeam":"Real Madrid","strSport":"Basketball","strBadge":"https://img.test/basketball.png"}]}''',
          200,
        ),
      ),
    );

    final team = await service.lookupTeam('  Real   Madrid  ');

    expect(team, isNotNull);
    expect(team!.teamId, '133738');
    expect(team.name, 'Real Madrid');
    expect(team.league, 'La Liga');
    expect(team.country, 'Spain');
    expect(team.badgeUrl, 'https://img.test/real.png');
    expect(team.hasBadge, isTrue);
  });

  test('rejects unsafe team badge URLs and malformed team responses', () async {
    var malformed = false;
    final service = AbuExternalContentService(
      client: MockClient((_) async {
        if (malformed) return http.Response('{broken', 200);
        return http.Response(
          '''{"teams":[{"strTeam":"Safe FC","strSport":"Soccer","strBadge":"data:image/png;base64,unsafe"}]}''',
          200,
        );
      }),
    );

    final team = await service.lookupTeam('Safe FC');
    expect(team, isNotNull);
    expect(team!.badgeUrl, isEmpty);
    expect(team.hasBadge, isFalse);

    malformed = true;
    expect(await service.lookupTeam('Malformed FC'), isNull);
  });

  test('normalizes external image URLs for secure web rendering', () {
    expect(
      normalizeExternalImageUrl(' http://img.test/team badge.png '),
      'https://img.test/team%20badge.png',
    );
    expect(
      normalizeExternalImageUrl('//cdn.test/team.png'),
      'https://cdn.test/team.png',
    );
    expect(normalizeExternalImageUrl('javascript:alert(1)'), isEmpty);
    expect(normalizeExternalImageUrl('not a url'), isEmpty);
  });

  test('normalizes the provider timeline labels used for cards and goals', () {
    expect(normalizeMatchTimelineType('Card', 'Yellow Card'), 'yellow_card');
    expect(normalizeMatchTimelineType('Card', 'Red Card'), 'red_card');
    expect(normalizeMatchTimelineType('Goal', 'Penalty'), 'penalty_goal');
    expect(normalizeMatchTimelineType('Substitution'), 'sub');
  });

  test(
    'loads real match timeline, lineup, statistics and table sections',
    () async {
      final requestedPaths = <String>[];
      final service = AbuExternalContentService(
        client: MockClient((request) async {
          requestedPaths.add(request.url.path);
          return switch (request.url.pathSegments.last) {
            'lookupevent.php' => http.Response(
              '''{"events":[{"idLeague":"4335","strSeason":"2026-2027","strHomeTeam":"Real Madrid","strVenue":"Santiago Bernabéu"}]}''',
              200,
            ),
            'lookuptimeline.php' => http.Response(
              '''{"timeline":[{"intTime":"11","strTimeline":"Card","strTimelineDetail":"Yellow Card","strPlayer":"Álvaro Carreras","strTeam":"Real Madrid","strHome":"Yes","strComment":"Tripping"},{"intTime":"26","strTimeline":"Goal","strPlayer":"Kylian Mbappé","strAssist":"Federico Valverde","strTeam":"Real Madrid","strHome":"Yes"}]}''',
              200,
            ),
            'lookuplineup.php' => http.Response(
              '''{"lineup":[{"strPlayer":"Thibaut Courtois","strTeam":"Real Madrid","strHome":"Yes","strPosition":"Goalkeeper","strSubstitute":"No","intSquadNumber":"1"},{"strPlayer":"Away Substitute","strTeam":"Real Sociedad","strHome":"No","strPosition":"Forward","strSubstitute":"Yes","intSquadNumber":"20"}]}''',
              200,
            ),
            'lookupeventstats.php' => http.Response(
              '''{"eventstats":[{"strStat":"Shots on Goal","intHome":"8","intAway":"3"}]}''',
              200,
            ),
            'lookuptable.php' => http.Response(
              '''{"table":[{"intRank":"1","strTeam":"Real Madrid","intPlayed":"3","intWin":"3","intDraw":"0","intLoss":"0","intGoalDifference":"7","intPoints":"9"}]}''',
              200,
            ),
            _ => http.Response('{}', 404),
          };
        }),
      );

      final details = await service.fetchMatchDetails('external_2506175');

      expect(details.timeline, hasLength(2));
      expect(details.timeline.first.type, 'yellow_card');
      expect(details.timeline.first.detail, 'Yellow Card · Tripping');
      expect(details.timeline.last.assist, 'Federico Valverde');
      expect(details.lineup, hasLength(2));
      expect(details.lineup.first.isSubstitute, isFalse);
      expect(details.lineup.last.isSubstitute, isTrue);
      expect(details.statistics.single.label, 'Shots on Goal');
      expect(details.standings.single.points, 9);
      expect(details.venue, 'Santiago Bernabéu');
      expect(details.season, '2026-2027');
      expect(details.isProviderLimited, isTrue);
      expect(requestedPaths, contains(contains('lookuptable.php')));
    },
  );

  test(
    'keeps available match sections when another provider section fails',
    () async {
      final service = AbuExternalContentService(
        client: MockClient((request) async {
          return switch (request.url.pathSegments.last) {
            'lookupevent.php' => http.Response(
              '''{"events":[{"idLeague":"4335","strSeason":"2026-2027","strHomeTeam":"Barcelona"}]}''',
              200,
            ),
            'lookuptimeline.php' => http.Response(
              '''{"timeline":[{"intTime":"5","strTimeline":"Goal","strPlayer":"Scorer","strHome":"Yes"}]}''',
              200,
            ),
            'lookuplineup.php' => http.Response('service unavailable', 503),
            _ => http.Response('{}', 200),
          };
        }),
      );

      final details = await service.fetchMatchDetails('event-one');

      expect(details.timeline.single.player, 'Scorer');
      expect(details.lineup, isEmpty);
    },
  );
}
