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
  static const _publicSportsDbApiKey = '123';

  final http.Client _client;
  Future<LatestVideo>? _latestVideoRequest;
  Future<List<MatchEvent>>? _weekMatchesRequest;
  final Map<String, Future<MatchDetails>> _matchDetailsRequests = {};

  Uri _sportsDbUri(String endpoint, Map<String, String> query) => Uri.https(
    'www.thesportsdb.com',
    '/api/v1/json/$_publicSportsDbApiKey/$endpoint',
    query,
  );

  Future<LatestVideo> latestVideo({bool refresh = false}) {
    if (refresh) _latestVideoRequest = null;
    return _latestVideoRequest ??= _fetchLatestVideo();
  }

  Future<List<MatchEvent>> weekMatches({bool refresh = false}) {
    if (refresh) _weekMatchesRequest = null;
    return _weekMatchesRequest ??= _fetchWeekMatches();
  }

  Future<MatchEvent?> nextMatch({bool refresh = false}) async {
    final matches = await weekMatches(refresh: refresh);
    return matches.isEmpty ? null : matches.first;
  }

  /// Finds the canonical team name, league and badge exposed by TheSportsDB.
  /// The JSON endpoint supports browser CORS; the badge widget separately uses
  /// an HTML image fallback because the image CDN does not always do so.
  Future<FootballTeamAsset?> lookupTeam(String query) async {
    final value = _cleanText(query);
    if (value.isEmpty) return null;
    final endpoint = _sportsDbUri('searchteams.php', {'t': value});
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

  /// Searches TheSportsDB for football teams matching the given query keyword.
  Future<List<FootballTeamAsset>> searchTeams(String query) async {
    final value = _cleanText(query);
    if (value.isEmpty) return const [];
    final endpoint = _sportsDbUri('searchteams.php', {'t': value});
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final rawTeams = decoded['teams'];
      if (rawTeams is! List<dynamic>) return const [];
      final teams = rawTeams
          .whereType<Map<String, dynamic>>()
          .where(_isFootballTeam)
          .map(
            (team) => FootballTeamAsset(
              name: _cleanText(team['strTeam']).isEmpty
                  ? value
                  : _cleanText(team['strTeam']),
              badgeUrl: normalizeExternalImageUrl(
                team['strBadge'] ?? team['strTeamBadge'],
              ),
              league: _firstText([team['strLeague'], team['strLeague2']]),
              teamId: _cleanText(team['idTeam']),
              country: _cleanText(team['strCountry']),
            ),
          )
          .toList();
      return teams;
    } catch (_) {
      return const [];
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

  Future<List<MatchEvent>> _fetchWeekMatches() async {
    final responses = await Future.wait([
      _fetchTeamMatches(_barcelonaTeamId),
      _fetchTeamMatches(_realMadridTeamId),
    ]);
    final seen = <String>{};
    final now = DateTime.now();
    final weekEnd = now.add(const Duration(days: 7, hours: 12));
    final matches = <MatchEvent>[];
    for (final list in responses) {
      for (final match in list) {
        if (seen.add(match.id) && _isBarcaOrRealMatch(match)) {
          if (match.kickoffAt.isAfter(now.subtract(const Duration(hours: 4))) &&
              match.kickoffAt.isBefore(weekEnd)) {
            matches.add(match);
          }
        }
      }
    }
    matches.sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
    return matches;
  }

  bool _isBarcaOrRealMatch(MatchEvent match) {
    final home = match.homeTeam.toLowerCase();
    final away = match.awayTeam.toLowerCase();
    return home.contains('barcelona') ||
        home.contains('barça') ||
        home.contains('barca') ||
        away.contains('barcelona') ||
        away.contains('barça') ||
        away.contains('barca') ||
        home.contains('real madrid') ||
        away.contains('real madrid');
  }

  Future<List<MatchEvent>> fetchRecentFinishedMatches() async {
    final responses = await Future.wait([
      _fetchTeamPastMatches(_barcelonaTeamId),
      _fetchTeamPastMatches(_realMadridTeamId),
    ]);
    final list = <MatchEvent>[];
    final seen = <String>{};
    for (final sub in responses) {
      for (final m in sub) {
        if (seen.add(m.id) && _isBarcaOrRealMatch(m)) {
          list.add(m);
        }
      }
    }
    return list;
  }

  Future<List<MatchEvent>> _fetchTeamPastMatches(String teamId) async {
    final endpoint = _sportsDbUri('eventslast.php', {'id': teamId});
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final events =
          payload['results'] as List<dynamic>? ??
          payload['events'] as List<dynamic>? ??
          const [];
      return _parseEventsList(events);
    } catch (_) {
      return const [];
    }
  }

  Future<List<MatchEvent>> _fetchTeamMatches(String teamId) async {
    final endpoint = _sportsDbUri('eventsnext.php', {'id': teamId});
    try {
      final response = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final events = payload['events'] as List<dynamic>? ?? const [];
      return _parseEventsList(events);
    } catch (_) {
      return const [];
    }
  }

  Future<List<MatchTimelineEvent>> fetchMatchTimeline(String eventId) async {
    final cleanId = eventId.replaceFirst('external_', '');
    final payload = await _fetchSportsDbJson('lookuptimeline.php', cleanId);
    return _parseTimeline(payload?['timeline']);
  }

  /// Loads every match-detail section TheSportsDB has published for an event.
  ///
  /// Requests are independent, so a missing lineup does not hide an available
  /// timeline or table. The public `123` key intentionally returns at most five
  /// rows per detail endpoint; callers surface that limitation instead of
  /// inventing the rest of a starting XI or match history.
  Future<MatchDetails> fetchMatchDetails(
    String eventId, {
    bool refresh = false,
  }) {
    final cleanId = eventId.replaceFirst('external_', '').trim();
    if (cleanId.isEmpty) return Future.value(const MatchDetails());
    if (refresh) _matchDetailsRequests.remove(cleanId);
    return _matchDetailsRequests.putIfAbsent(
      cleanId,
      () => _fetchMatchDetails(cleanId),
    );
  }

  Future<MatchDetails> _fetchMatchDetails(String eventId) async {
    final eventPayload = await _fetchSportsDbJson('lookupevent.php', eventId);
    final rawEvent = _firstMap(eventPayload?['events']);
    final leagueId = _providerText(rawEvent?['idLeague']);
    final season = _providerText(rawEvent?['strSeason']);
    final homeTeam = _providerText(rawEvent?['strHomeTeam']);

    final sectionPayloads = await Future.wait([
      _fetchSportsDbJson('lookuptimeline.php', eventId),
      _fetchSportsDbJson('lookuplineup.php', eventId),
      _fetchSportsDbJson('lookupeventstats.php', eventId),
      if (leagueId.isNotEmpty && season.isNotEmpty)
        _fetchSportsDbJson(
          'lookuptable.php',
          leagueId,
          idParameter: 'l',
          query: {'s': season},
        )
      else
        Future<Map<String, dynamic>?>.value(null),
    ]);

    return MatchDetails(
      timeline: _parseTimeline(sectionPayloads[0]?['timeline']),
      lineup: _parseLineup(sectionPayloads[1]?['lineup'], homeTeam: homeTeam),
      statistics: _parseStatistics(sectionPayloads[2]?['eventstats']),
      standings: _parseStandings(sectionPayloads[3]?['table']),
      venue: _providerText(rawEvent?['strVenue']),
      season: season,
      provider: 'TheSportsDB',
      isProviderLimited: true,
    );
  }

  Future<Map<String, dynamic>?> _fetchSportsDbJson(
    String endpoint,
    String id, {
    String idParameter = 'id',
    Map<String, String> query = const {},
  }) async {
    final url = _sportsDbUri(endpoint, {idParameter: id, ...query});
    try {
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    }
  }

  List<MatchTimelineEvent> _parseTimeline(Object? value) {
    final raw = value is List<dynamic> ? value : const <dynamic>[];
    final events = <MatchTimelineEvent>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final timeline = _providerText(item['strTimeline']);
      final timelineDetail = _providerText(item['strTimelineDetail']);
      final comment = _providerText(item['strComment']);
      final details = <String>{
        if (timelineDetail.isNotEmpty) timelineDetail,
        if (comment.isNotEmpty) comment,
      }.join(' · ');
      events.add(
        MatchTimelineEvent(
          minute: _providerText(item['intTime']),
          type: normalizeMatchTimelineType(timeline, timelineDetail),
          player: _providerText(item['strPlayer']),
          assist: _providerText(item['strAssist']),
          detail: details,
          team: _providerText(item['strTeam']),
          isHome: _providerText(item['strHome']).toLowerCase() == 'yes',
        ),
      );
    }
    events.sort((left, right) {
      final leftMinute = int.tryParse(left.minute.split('+').first) ?? 0;
      final rightMinute = int.tryParse(right.minute.split('+').first) ?? 0;
      return leftMinute.compareTo(rightMinute);
    });
    return events;
  }

  List<MatchLineupPlayer> _parseLineup(
    Object? value, {
    required String homeTeam,
  }) {
    final raw = value is List<dynamic> ? value : const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final team = _providerText(item['strTeam']);
          final homeFlag = _providerText(item['strHome']).toLowerCase();
          final substituteFlag = _providerText(
            item['strSubstitute'] ?? item['strSub'],
          ).toLowerCase();
          return MatchLineupPlayer(
            player: _providerText(item['strPlayer']),
            team: team,
            position: _providerText(item['strPosition']),
            isHome:
                homeFlag == 'yes' ||
                (homeFlag.isEmpty &&
                    team.toLowerCase() == homeTeam.toLowerCase()),
            isSubstitute:
                substituteFlag == 'yes' ||
                substituteFlag == 'true' ||
                substituteFlag == '1',
            squadNumber: _providerText(
              item['intSquadNumber'] ?? item['strNumber'],
            ),
            playerImageUrl: normalizeExternalImageUrl(
              item['strCutout'] ?? item['strThumb'],
            ),
          );
        })
        .where((item) => item.player.isNotEmpty)
        .toList(growable: false);
  }

  List<MatchStatistic> _parseStatistics(Object? value) {
    final raw = value is List<dynamic> ? value : const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) {
          return MatchStatistic(
            label: _providerText(item['strStat']),
            homeValue: _providerText(item['intHome']),
            awayValue: _providerText(item['intAway']),
          );
        })
        .where((item) => item.label.isNotEmpty)
        .toList(growable: false);
  }

  List<MatchStanding> _parseStandings(Object? value) {
    final raw = value is List<dynamic> ? value : const <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((item) {
          return MatchStanding(
            rank: int.tryParse(_providerText(item['intRank'])) ?? 0,
            team: _providerText(item['strTeam']),
            played: int.tryParse(_providerText(item['intPlayed'])) ?? 0,
            won: int.tryParse(_providerText(item['intWin'])) ?? 0,
            drawn: int.tryParse(_providerText(item['intDraw'])) ?? 0,
            lost: int.tryParse(_providerText(item['intLoss'])) ?? 0,
            goalDifference:
                int.tryParse(_providerText(item['intGoalDifference'])) ?? 0,
            points: int.tryParse(_providerText(item['intPoints'])) ?? 0,
            teamId: _providerText(item['idTeam']),
            badgeUrl: normalizeExternalImageUrl(item['strBadge']),
            form: _providerText(item['strForm']),
          );
        })
        .where((item) => item.team.isNotEmpty)
        .toList(growable: false);
  }

  final Map<String, List<String>> _teamPlayersCache = {};

  static const Map<String, List<String>> _knownStarPlayers = {
    'real madrid': [
      'Kylian Mbappé',
      'Vinícius Júnior',
      'Jude Bellingham',
      'Rodrygo',
      'Arda Güler',
      'Brahim Díaz',
      'Endrick',
      'Federico Valverde',
      'Eduardo Camavinga',
      'Luka Modrić',
    ],
    'barcelona': [
      'Lamine Yamal',
      'Robert Lewandowski',
      'Raphinha',
      'Dani Olmo',
      'Pedri',
      'Ferran Torres',
      'Gavi',
      'Frenkie de Jong',
      'Fermín López',
      'Pau Víctor',
    ],
    'atletico madrid': [
      'Antoine Griezmann',
      'Julián Álvarez',
      'Alexander Sørloth',
      'Ángel Correa',
      'Rodrigo De Paul',
      'Conor Gallagher',
      'Marcos Llorente',
    ],
    'real sociedad': [
      'Mikel Oyarzabal',
      'Takefusa Kubo',
      'Brais Méndez',
      'Orri Óskarsson',
      'Sheraldo Becker',
      'Ander Barrenetxea',
    ],
    'athletic club': [
      'Nico Williams',
      'Iñaki Williams',
      'Oihan Sancet',
      'Gorka Guruzeta',
      'Álex Berenguer',
    ],
    'villarreal': [
      'Ayoze Pérez',
      'Gerard Moreno',
      'Thierno Barry',
      'Nicolas Pépé',
      'Álex Baena',
    ],
    'girona': [
      'Abel Ruiz',
      'Viktor Tsygankov',
      'Bryan Gil',
      'Cristhian Stuani',
      'Yáser Asprilla',
    ],
    'sevilla': [
      'Isaac Romero',
      'Dodi Lukebakio',
      'Kelechi Iheanacho',
      'Saúl Ñíguez',
      'Chidera Ejuke',
    ],
    'real betis': [
      'Vitor Roque',
      'Giovani Lo Celso',
      'Chimy Ávila',
      'Pablo Fornals',
      'Isco',
    ],
    'elche': [
      'Mourad El Ghezouani',
      'Nicolás Fernández',
      'Agustín Álvarez',
      'Yago Santiago',
      'Nico Castro',
      'Óscar Plano',
    ],
    'manchester city': [
      'Erling Haaland',
      'Kevin De Bruyne',
      'Phil Foden',
      'Bernardo Silva',
      'Jack Grealish',
      'Jérémy Doku',
      'Savinho',
    ],
    'arsenal': [
      'Bukayo Saka',
      'Kai Havertz',
      'Martin Ødegaard',
      'Gabriel Martinelli',
      'Gabriel Jesus',
      'Leandro Trossard',
      'Raheem Sterling',
    ],
    'liverpool': [
      'Mohamed Salah',
      'Luis Díaz',
      'Diogo Jota',
      'Darwin Núñez',
      'Cody Gakpo',
      'Dominik Szoboszlai',
      'Federico Chiesa',
    ],
    'bayern': [
      'Harry Kane',
      'Jamal Musiala',
      'Michael Olise',
      'Serge Gnabry',
      'Leroy Sané',
      'Thomas Müller',
      'Kingsley Coman',
    ],
    'paris saint-germain': [
      'Bradley Barcola',
      'Ousmane Dembélé',
      'Randal Kolo Muani',
      'Gonçalo Ramos',
      'Marco Asensio',
      'Kang-in Lee',
      'Vitinha',
    ],
    'chelsea': [
      'Cole Palmer',
      'Nicolas Jackson',
      'Christopher Nkunku',
      'Noni Madueke',
      'Pedro Neto',
      'João Félix',
      'Enzo Fernández',
      'Moisés Caicedo',
    ],
    'juventus': [
      'Dušan Vlahović',
      'Kenan Yıldız',
      'Teun Koopmeiners',
      'Francisco Conceição',
      'Nicolò González',
      'Timothy Weah',
      'Weston McKennie',
    ],
    'inter': [
      'Lautaro Martínez',
      'Marcus Thuram',
      'Hakan Çalhanoğlu',
      'Nicolò Barella',
      'Federico Dimarco',
      'Mehdi Taremi',
      'Davide Frattesi',
    ],
    'milan': [
      'Rafael Leão',
      'Álvaro Morata',
      'Christian Pulisic',
      'Tammy Abraham',
      'Samuel Chukwueze',
      'Tijjani Reijnders',
      'Theo Hernández',
    ],
    'al hilal': [
      'Aleksandar Mitrović',
      'Neymar Jr',
      'Malcom',
      'Sergej Milinković-Savić',
      'Rúben Neves',
      'Salem Al-Dawsari',
      'Marcos Leonardo',
    ],
    'al nassr': [
      'Cristiano Ronaldo',
      'Sadio Mané',
      'Anderson Talisca',
      'Otávio',
      'Marcelo Brozović',
      'Ayman Yahya',
      'Angelo Gabriel',
    ],
    'al ittihad': [
      'Karim Benzema',
      'Moussa Diaby',
      'Houssem Aouar',
      'Steven Bergwijn',
      'N\'Golo Kanté',
      'Fabinho',
      'Saleh Al-Shehri',
    ],
    'al ahli': [
      'Ivan Toney',
      'Riyad Mahrez',
      'Roberto Firmino',
      'Gabri Veiga',
      'Franck Kessié',
      'Firas Al-Buraikan',
    ],
  };

  List<String> _getKnownPlayersForTeam(String teamName) {
    final key = teamName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .trim();
    for (final entry in _knownStarPlayers.entries) {
      final target = entry.key.toLowerCase();
      if (key.contains(target) || target.contains(key)) {
        return entry.value;
      }
      final words = target.split(' ').where((w) => w.length > 3);
      for (final w in words) {
        if (key.contains(w)) {
          return entry.value;
        }
      }
    }
    return const [];
  }

  Future<List<String>> lookupPlayersForTeam(
    String teamName, {
    String? teamId,
  }) async {
    final cacheKey = (teamId?.isNotEmpty == true ? teamId! : teamName)
        .toLowerCase()
        .trim();
    if (_teamPlayersCache.containsKey(cacheKey)) {
      return _teamPlayersCache[cacheKey]!;
    }
    final results = <String>[..._getKnownPlayersForTeam(teamName)];
    if (teamId != null && teamId.isNotEmpty) {
      final endpoint = _sportsDbUri('lookup_all_players.php', {'id': teamId});
      try {
        final response = await _client
            .get(endpoint)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final payload = jsonDecode(response.body) as Map<String, dynamic>;
          final players = payload['player'] as List<dynamic>? ?? const [];
          for (final raw in players) {
            if (raw is! Map<String, dynamic>) continue;
            final name = _cleanText(raw['strPlayer']);
            final position = _cleanText(raw['strPosition']).toLowerCase();
            if (name.isNotEmpty &&
                !position.contains('goalkeeper') &&
                !results.contains(name)) {
              results.add(name);
            }
          }
        }
      } catch (_) {}
    }
    _teamPlayersCache[cacheKey] = results;
    return results;
  }

  Future<List<String>> lookupPlayersForTeams(
    String homeTeam,
    String awayTeam, {
    String? homeTeamId,
    String? awayTeamId,
  }) async {
    final futures = await Future.wait([
      lookupPlayersForTeam(homeTeam, teamId: homeTeamId),
      lookupPlayersForTeam(awayTeam, teamId: awayTeamId),
    ]);
    final combined = <String>{};
    for (final list in futures) {
      combined.addAll(list);
    }
    return combined.toList();
  }

  List<MatchEvent> _parseEventsList(List<dynamic> events) {
    final results = <MatchEvent>[];
    for (final raw in events) {
      if (raw is! Map<String, dynamic>) continue;
      final timestamp = _cleanText(raw['strTimestamp']);
      final kickoff = _parseExternalTimestamp(timestamp)?.toLocal();
      if (kickoff == null) continue;
      final eventId = _cleanText(raw['idEvent']);
      if (eventId.isEmpty) continue;
      final homeTeam = _firstText([raw['strHomeTeam'], 'Home']);
      final awayTeam = _firstText([raw['strAwayTeam'], 'Away']);
      final opens = kickoff.subtract(const Duration(hours: 24));
      final defaultPlayers = <String>{
        ..._getKnownPlayersForTeam(homeTeam),
        ..._getKnownPlayersForTeam(awayTeam),
      }.toList();
      final rawHomeScore = _cleanText(raw['intHomeScore']);
      final rawAwayScore = _cleanText(raw['intAwayScore']);
      final homeScore = rawHomeScore.isNotEmpty
          ? int.tryParse(rawHomeScore)
          : null;
      final awayScore = rawAwayScore.isNotEmpty
          ? int.tryParse(rawAwayScore)
          : null;
      final status = (homeScore != null && awayScore != null)
          ? 'completed'
          : 'upcoming';

      results.add(
        MatchEvent(
          id: 'external_$eventId',
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          competition: _firstText([raw['strLeague'], 'Football']),
          kickoffAt: kickoff,
          predictionOpensAt: opens,
          predictionClosesAt: kickoff,
          status: status,
          homeTeamId: _cleanText(raw['idHomeTeam']),
          awayTeamId: _cleanText(raw['idAwayTeam']),
          homeScore: homeScore,
          awayScore: awayScore,
          firstScorerOptions: defaultPlayers,
          homeLogoUrl: normalizeExternalImageUrl(raw['strHomeTeamBadge']),
          awayLogoUrl: normalizeExternalImageUrl(raw['strAwayTeamBadge']),
        ),
      );
    }
    return results;
  }
}

String _cleanText(Object? value) =>
    value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

/// TheSportsDB uses the literal string `NULL` for some empty fields.
String _providerText(Object? value) {
  final text = _cleanText(value);
  return text.toLowerCase() == 'null' ? '' : text;
}

Map<String, dynamic>? _firstMap(Object? value) {
  if (value is! List<dynamic>) return null;
  for (final item in value) {
    if (item is Map<String, dynamic>) return item;
  }
  return null;
}

/// Converts provider-specific timeline labels into the stable types consumed
/// by the app and self-hosted backend.
String normalizeMatchTimelineType(Object? type, [Object? detail]) {
  final combined = '${_providerText(type)} ${_providerText(detail)}'
      .toLowerCase();
  if (combined.contains('yellow')) return 'yellow_card';
  if (combined.contains('red')) return 'red_card';
  if (combined.contains('substitut') || combined.contains('player change')) {
    return 'sub';
  }
  if (combined.contains('own goal')) return 'own_goal';
  if (combined.contains('penalty') && combined.contains('goal')) {
    return 'penalty_goal';
  }
  if (combined.contains('goal')) return 'goal';
  if (combined.contains('var')) return 'var';
  if (combined.contains('period') || combined.contains('half time')) {
    return 'period';
  }
  final normalized = _providerText(type)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return normalized.isEmpty ? 'event' : normalized;
}

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
