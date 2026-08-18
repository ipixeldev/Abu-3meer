import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class LatestVideo {
  const LatestVideo({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbnailUrl,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String url;
  final String thumbnailUrl;
  final DateTime publishedAt;
}

class FootballTeamAsset {
  const FootballTeamAsset({
    required this.name,
    required this.badgeUrl,
    required this.league,
  });

  final String name;
  final String badgeUrl;
  final String league;
}

class AbuExternalContentService {
  AbuExternalContentService({http.Client? client})
    : _client = client ?? http.Client();

  static const youtubeChannelId = 'UCtetMtDxaZv1Fun1Ff85h4w';
  static const _youtubeFeed =
      'https://www.youtube.com/feeds/videos.xml?channel_id=$youtubeChannelId';
  static const _realMadridTeamId = '133738';
  static const _barcelonaTeamId = '133739';

  final http.Client _client;
  Future<LatestVideo>? _latestVideoRequest;
  Future<MatchEvent?>? _nextMatchRequest;

  Future<LatestVideo> latestVideo({bool refresh = false}) {
    if (refresh) _latestVideoRequest = null;
    return _latestVideoRequest ??= _fetchLatestVideo();
  }

  Future<MatchEvent?> nextMatch({bool refresh = false}) {
    if (refresh) _nextMatchRequest = null;
    return _nextMatchRequest ??= _fetchNextMatch();
  }

  /// Finds the canonical team name, league and badge exposed by TheSportsDB.
  /// The JSON endpoint supports browser CORS; the badge widget separately uses
  /// an HTML image fallback because the image CDN does not always do so.
  Future<FootballTeamAsset?> lookupTeam(String query) async {
    final value = query.trim();
    if (value.isEmpty) return null;
    final endpoint = Uri.https(
      'www.thesportsdb.com',
      '/api/v1/json/123/searchteams.php',
      {'t': value},
    );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final teams = payload['teams'] as List<dynamic>? ?? const [];
    if (teams.isEmpty) return null;
    final footballTeams = teams
        .whereType<Map<String, dynamic>>()
        .where(
          (team) => team['strSport'] == null || team['strSport'] == 'Soccer',
        )
        .toList();
    final team = footballTeams.isEmpty
        ? teams.first as Map<String, dynamic>
        : footballTeams.first;
    return FootballTeamAsset(
      name: team['strTeam'] as String? ?? value,
      badgeUrl: team['strBadge'] as String? ?? '',
      league: team['strLeague'] as String? ?? '',
    );
  }

  Future<LatestVideo> _fetchLatestVideo() async {
    final endpoint = Uri.https('api.rss2json.com', '/v1/api.json', {
      'rss_url': _youtubeFeed,
    });
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('YouTube feed returned ${response.statusCode}.');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = payload['items'] as List<dynamic>? ?? const [];
    if (payload['status'] != 'ok' || items.isEmpty) {
      throw StateError('The latest YouTube video is unavailable.');
    }
    final item = items.first as Map<String, dynamic>;
    final url = item['link'] as String? ?? '';
    final id = Uri.tryParse(url)?.queryParameters['v'] ?? '';
    if (id.isEmpty) throw StateError('YouTube returned an invalid video.');
    return LatestVideo(
      id: id,
      title: item['title'] as String? ?? 'Latest Abu 3meer video',
      url: url,
      thumbnailUrl:
          item['thumbnail'] as String? ??
          'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      publishedAt:
          DateTime.tryParse('${item['pubDate'] ?? ''}Z')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<MatchEvent?> _fetchNextMatch() async {
    final responses = await Future.wait([
      _fetchTeamMatch(_barcelonaTeamId),
      _fetchTeamMatch(_realMadridTeamId),
    ]);
    final matches = responses.whereType<MatchEvent>().toList()
      ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    return matches.isEmpty ? null : matches.first;
  }

  Future<MatchEvent?> _fetchTeamMatch(String teamId) async {
    final endpoint = Uri.parse(
      'https://www.thesportsdb.com/api/v1/json/123/eventsnext.php?id=$teamId',
    );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final events = payload['events'] as List<dynamic>? ?? const [];
    if (events.isEmpty) return null;
    final event = events.first as Map<String, dynamic>;
    final timestamp = event['strTimestamp'] as String? ?? '';
    final kickoff = DateTime.tryParse('${timestamp}Z')?.toLocal();
    if (kickoff == null) return null;
    return MatchEvent(
      id: 'external_${event['idEvent']}',
      homeTeam: event['strHomeTeam'] as String? ?? 'Home',
      awayTeam: event['strAwayTeam'] as String? ?? 'Away',
      competition: event['strLeague'] as String? ?? 'Football',
      kickoffAt: kickoff,
      predictionOpensAt: kickoff,
      predictionClosesAt: kickoff,
      status: 'upcoming',
      homeLogoUrl: event['strHomeTeamBadge'] as String? ?? '',
      awayLogoUrl: event['strAwayTeamBadge'] as String? ?? '',
    );
  }
}
