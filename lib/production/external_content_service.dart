import 'dart:async';
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
    this.teamId = '',
    this.country = '',
  });

  final String name;
  final String badgeUrl;
  final String league;
  final String teamId;
  final String country;

  bool get hasBadge => badgeUrl.isNotEmpty;
}

/// Returns a browser-safe HTTP(S) image URL or an empty string.
///
/// TheSportsDB sometimes returns whitespace, protocol-relative URLs, or an
/// `http` badge even though the app is hosted over HTTPS. Normalizing at the
/// service boundary prevents mixed-content failures and gives badge widgets a
/// reliable signal for when to render their local initials fallback.
String normalizeExternalImageUrl(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  final candidate = raw.startsWith('//') ? 'https:$raw' : raw;
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return '';
  if (uri.scheme != 'http' && uri.scheme != 'https') return '';
  return uri.replace(scheme: 'https').toString();
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
    final value = _cleanText(query);
    if (value.isEmpty) return null;
    final endpoint = Uri.https(
      'www.thesportsdb.com',
      '/api/v1/json/123/searchteams.php',
      {'t': value},
    );
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      final rawTeams = decoded['teams'];
      if (rawTeams is! List<dynamic>) return null;
      final teams = rawTeams
          .whereType<Map<String, dynamic>>()
          .where(_isFootballTeam)
          .toList();
      if (teams.isEmpty) return null;
      teams.sort(
        (left, right) => _teamMatchScore(
          right,
          value,
        ).compareTo(_teamMatchScore(left, value)),
      );
      final team = teams.first;
      return FootballTeamAsset(
        name: _cleanText(team['strTeam']).isEmpty
            ? value
            : _cleanText(team['strTeam']),
        badgeUrl: normalizeExternalImageUrl(
          team['strBadge'] ?? team['strTeamBadge'],
        ),
        league: _firstText([team['strLeague'], team['strLeague2']]),
        teamId: _cleanText(team['idTeam']),
        country: _cleanText(team['strCountry']),
      );
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    }
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
    final timestamp = _cleanText(event['strTimestamp']);
    final kickoff = _parseExternalTimestamp(timestamp)?.toLocal();
    if (kickoff == null) return null;
    final eventId = _cleanText(event['idEvent']);
    if (eventId.isEmpty) return null;
    return MatchEvent(
      id: 'external_$eventId',
      homeTeam: _firstText([event['strHomeTeam'], 'Home']),
      awayTeam: _firstText([event['strAwayTeam'], 'Away']),
      competition: _firstText([event['strLeague'], 'Football']),
      kickoffAt: kickoff,
      predictionOpensAt: kickoff,
      predictionClosesAt: kickoff,
      status: 'upcoming',
      homeLogoUrl: normalizeExternalImageUrl(event['strHomeTeamBadge']),
      awayLogoUrl: normalizeExternalImageUrl(event['strAwayTeamBadge']),
    );
  }
}

String _cleanText(Object? value) =>
    value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _cleanText(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _isFootballTeam(Map<String, dynamic> team) {
  final sport = _cleanText(team['strSport']).toLowerCase();
  return sport.isEmpty || sport == 'soccer' || sport == 'football';
}

int _teamMatchScore(Map<String, dynamic> team, String query) {
  final wanted = _searchKey(query);
  final name = _searchKey(team['strTeam']);
  final aliases = _cleanText(team['strTeamAlternate'])
      .split(RegExp(r'[,;/|]'))
      .map(_searchKey)
      .where((alias) => alias.isNotEmpty);
  var score = 0;
  if (name.isNotEmpty && name == wanted) score += 100;
  if (aliases.contains(wanted)) score += 80;
  if (name.isNotEmpty && (name.startsWith(wanted) || wanted.startsWith(name))) {
    score += 30;
  }
  if (name.isNotEmpty && (name.contains(wanted) || wanted.contains(name))) {
    score += 15;
  }
  if (normalizeExternalImageUrl(team['strBadge']).isNotEmpty) score += 2;
  return score;
}

String _searchKey(Object? value) =>
    _cleanText(value)
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

DateTime? _parseExternalTimestamp(String value) {
  if (value.isEmpty) return null;
  final includesZone =
      value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(includesZone ? value : '${value}Z');
}
