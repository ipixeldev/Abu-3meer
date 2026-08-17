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
}
