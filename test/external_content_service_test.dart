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
    final service = AbuExternalContentService(
      client: MockClient((request) async {
        final realMadrid = request.url.queryParameters['id'] == '133738';
        return http.Response(
          '''{"events":[{"idEvent":"${realMadrid ? 'rm1' : 'fcb1'}","strHomeTeam":"${realMadrid ? 'Espanyol' : 'Barcelona'}","strAwayTeam":"${realMadrid ? 'Real Madrid' : 'Al Ahly'}","strLeague":"Friendly","strTimestamp":"${realMadrid ? '2026-08-22T19:00:00' : '2026-08-19T18:00:00'}","strHomeTeamBadge":"","strAwayTeamBadge":""}]}''',
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
}
