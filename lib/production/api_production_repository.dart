import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';
import 'external_content_service.dart';
import 'models.dart';

@visibleForTesting
int parseApiInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

@visibleForTesting
double parseApiDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

@visibleForTesting
MatchEvent parseApiMatchEvent(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid football-match response.');
  }
  final match = Map<String, dynamic>.from(value);
  final kickoff =
      DateTime.tryParse(
        (match['kickoff_at'] ?? match['kickoffAt'] ?? '').toString(),
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  int? optionalInt(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    return raw is num ? raw.toInt() : int.tryParse(raw.toString());
  }

  final id = (match['id'] ?? '').toString();
  final explicitProviderMatchId =
      (match['provider_match_id'] ?? match['providerMatchId'] ?? '')
          .toString()
          .trim();

  return MatchEvent(
    id: id,
    providerMatchId: explicitProviderMatchId.isNotEmpty
        ? explicitProviderMatchId
        : (id.startsWith('external_') ? id : ''),
    competition:
        (match['competition_name'] ?? match['competition'] ?? 'Football')
            .toString(),
    homeTeam: (match['home_team'] ?? match['homeTeam'] ?? '').toString(),
    awayTeam: (match['away_team'] ?? match['awayTeam'] ?? '').toString(),
    homeTeamId: (match['home_team_id'] ?? match['homeTeamId'] ?? '').toString(),
    awayTeamId: (match['away_team_id'] ?? match['awayTeamId'] ?? '').toString(),
    homeLogoUrl: (match['home_logo_url'] ?? match['homeLogoUrl'] ?? '')
        .toString(),
    awayLogoUrl: (match['away_logo_url'] ?? match['awayLogoUrl'] ?? '')
        .toString(),
    kickoffAt: kickoff.toLocal(),
    predictionOpensAt:
        DateTime.tryParse(
          (match['predictions_open_at'] ?? match['predictionOpensAt'] ?? '')
              .toString(),
        )?.toLocal() ??
        kickoff.subtract(const Duration(hours: 24)).toLocal(),
    predictionClosesAt:
        DateTime.tryParse(
          (match['predictions_close_at'] ?? match['predictionClosesAt'] ?? '')
              .toString(),
        )?.toLocal() ??
        kickoff.toLocal(),
    status: (match['status'] ?? 'upcoming').toString(),
    homeScore: optionalInt(match['home_score'] ?? match['homeScore']),
    awayScore: optionalInt(match['away_score'] ?? match['awayScore']),
    firstScorer: (match['first_scorer'] ?? match['firstScorer'] ?? '')
        .toString(),
    firstScorerOptions:
        (match['first_scorer_options'] ?? match['firstScorerOptions']) is List
        ? ((match['first_scorer_options'] ?? match['firstScorerOptions'])
                  as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[],
  );
}

@visibleForTesting
FootballTeamAsset parseApiFootballTeam(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid football-team response.');
  }
  final team = Map<String, dynamic>.from(value);
  return FootballTeamAsset(
    teamId: (team['teamId'] ?? team['team_id'] ?? '').toString(),
    name: (team['name'] ?? team['team'] ?? '').toString(),
    badgeUrl: (team['badgeUrl'] ?? team['badge_url'] ?? '').toString(),
    league: (team['league'] ?? '').toString(),
    country: (team['country'] ?? '').toString(),
  );
}

@visibleForTesting
AbuUserProfile parseAdminUserProfile(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid admin-user response.');
  }
  final user = Map<String, dynamic>.from(value);
  final rawRole = (user['role'] ?? 'fan').toString();
  final role = rawRole == 'super_admin' ? 'superAdmin' : rawRole;
  final accountStatus = (user['accountStatus'] ?? 'active').toString();
  return AbuUserProfile(
    // Mutating endpoints accept either the PostgreSQL ID or Firebase UID. Use
    // the Firebase UID when present so the same model also works in existing
    // client-side identity comparisons.
    uid: (user['firebaseUid'] ?? user['uid'] ?? user['id'] ?? '').toString(),
    email: (user['email'] ?? '').toString(),
    username: (user['username'] ?? '').toString(),
    displayName: (user['displayName'] ?? '').toString(),
    country: (user['country'] ?? '').toString(),
    countryCode: (user['countryCode'] ?? '').toString(),
    supportedTeam: (user['supportedTeam'] ?? '').toString(),
    supportedTeamLogo: (user['supportedTeamLogo'] ?? '').toString(),
    avatarUrl: (user['avatarUrl'] ?? '').toString(),
    role: role,
    membershipMultiplier: user['isYouTubeMember'] == true ? 2.0 : 1.0,
    totalPoints: parseApiInt(user['totalPoints']),
    monthlyPoints: parseApiInt(user['monthlyPoints']),
    seasonPoints: parseApiInt(user['seasonPoints']),
    loyaltyPoints: parseApiInt(user['loyaltyPoints']),
    suspended:
        user['suspended'] == true ||
        accountStatus == 'suspended' ||
        accountStatus == 'banned',
    level: parseApiInt(user['level'], 1),
    lastActivityAt: DateTime.tryParse((user['lastActiveAt'] ?? '').toString()),
    onboardingCompleted: user['onboardingCompleted'] as bool?,
  );
}

@visibleForTesting
AdminPointAdjustment parseAdminPointAdjustment(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid point-adjustment response.');
  }
  final item = Map<String, dynamic>.from(value);
  return AdminPointAdjustment(
    id: (item['id'] ?? '').toString(),
    adminId: (item['adminId'] ?? '').toString(),
    adminDisplayName: (item['adminDisplayName'] ?? '').toString(),
    targetUserId: (item['targetUserId'] ?? '').toString(),
    targetDisplayName: (item['targetDisplayName'] ?? '').toString(),
    targetUsername: (item['targetUsername'] ?? '').toString(),
    delta: parseApiInt(item['delta']),
    reason: (item['reason'] ?? '').toString(),
    totalBefore: parseApiInt(item['totalBefore']),
    totalAfter: parseApiInt(item['totalAfter']),
    monthlyBefore: parseApiInt(item['monthlyBefore']),
    monthlyAfter: parseApiInt(item['monthlyAfter']),
    seasonBefore: parseApiInt(item['seasonBefore']),
    seasonAfter: parseApiInt(item['seasonAfter']),
    periodFloorApplied: item['periodFloorApplied'] == true,
    monthlyRolledOver: item['monthlyRolledOver'] == true,
    seasonRolledOver: item['seasonRolledOver'] == true,
    monthlyPeriod: (item['monthlyPeriod'] ?? '').toString(),
    seasonId: (item['seasonId'] ?? '').toString(),
    createdAt:
        DateTime.tryParse((item['createdAt'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class ApiProductionRepository {
  ApiProductionRepository({AbuApiClient? apiClient, FirebaseAuth? auth})
    : api = apiClient ?? AbuApiClient(),
      auth = auth ?? FirebaseAuth.instance;

  final AbuApiClient api;
  final FirebaseAuth auth;

  Stream<User?> get authChanges => auth.userChanges();

  Future<AbuUserProfile?> fetchProfile() async {
    final user = auth.currentUser;
    if (user == null) return null;

    final res = await api.get('/profile/me', requireAuth: true);
    if (res is Map && res.containsKey('user') && res.containsKey('profile')) {
      final u = res['user'];
      final p = res['profile'];
      if (u is! Map || p is! Map) {
        throw AbuApiException(
          statusCode: 502,
          message: 'The profile response from the server is incomplete.',
          details: res,
        );
      }
      final roles = (u['roles'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toSet();
      final role = u['isSuperAdmin'] == true
          ? 'superAdmin'
          : u['isAdmin'] == true || roles.contains('admin')
          ? 'admin'
          : roles.contains('moderator')
          ? 'moderator'
          : u['isYouTubeMember'] == true
          ? 'member'
          : 'fan';
      final accountStatus = (u['accountStatus'] ?? u['account_status'] ?? '')
          .toString();
      final storedAvatarUrl = (u['avatarUrl'] ?? '').toString().trim();
      return AbuUserProfile(
        uid: u['firebaseUid'] ?? user.uid,
        email: u['email'] ?? user.email ?? '',
        displayName: u['displayName'] ?? user.displayName ?? '',
        username: u['username'] ?? '',
        country: u['country'] ?? '',
        countryCode: u['countryCode'] ?? '',
        supportedTeam: u['supportedTeam'] ?? 'General Fan',
        supportedTeamLogo: u['supportedTeamLogo'] ?? '',
        // PostgreSQL uploads take precedence, while Google-authenticated
        // accounts still retain their Firebase profile photo until the user
        // chooses a custom avatar.
        avatarUrl: storedAvatarUrl.isNotEmpty
            ? storedAvatarUrl
            : (user.photoURL ?? '').trim(),
        role: role,
        membershipMultiplier: (u['isYouTubeMember'] == true) ? 2.0 : 1.0,
        totalPoints: (p['total_points'] ?? 50).toInt(),
        monthlyPoints: (p['monthly_points'] ?? 50).toInt(),
        seasonPoints: (p['season_points'] ?? 50).toInt(),
        loyaltyPoints: (p['loyalty_points'] ?? 50).toInt(),
        currentStreak: (p['streak_count'] ?? 0).toInt(),
        longestStreak: (p['streak_best'] ?? 0).toInt(),
        level: (p['level'] ?? 1).toInt(),
        exactPredictions: (p['exact_predictions_count'] ?? 0).toInt(),
        challengesCompleted: (p['challenges_completed_count'] ?? 0).toInt(),
        playerCardsCollected: (p['player_cards_collected_count'] ?? 0).toInt(),
        lastCheckInDate: p['streak_last_checkin'] != null
            ? p['streak_last_checkin'].toString().split('T').first
            : '',
        suspended: accountStatus == 'suspended' || accountStatus == 'banned',
        onboardingCompleted: u['onboardingCompleted'] as bool?,
      );
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not return your profile.',
      details: res,
    );
  }

  Future<List<MatchEvent>> fetchUpcomingMatches() async {
    final res = await api.get('/matches/upcoming');
    if (res is List) {
      return res.map(parseApiMatchEvent).toList(growable: false);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid upcoming-match list.',
      details: res,
    );
  }

  /// Shared provider-backed match cards. The server coalesces provider calls
  /// and stores the result in Redis, so every device reads the same snapshot.
  Future<List<MatchEvent>> fetchFootballWeekMatches({int days = 7}) async {
    final response = await api.get(
      '/football/matches/week',
      queryParams: {'days': days.clamp(1, 14).toString()},
    );
    if (response is! List) {
      throw const FormatException('Invalid weekly football response.');
    }
    return response.map(parseApiMatchEvent).toList(growable: false);
  }

  Future<List<MatchEvent>> fetchFootballRecentMatches() async {
    final response = await api.get('/football/matches/recent');
    if (response is! List) {
      throw const FormatException('Invalid recent-football response.');
    }
    return response.map(parseApiMatchEvent).toList(growable: false);
  }

  Future<List<FootballTeamAsset>> searchFootballTeams(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const <FootballTeamAsset>[];
    final response = await api.get(
      '/football/teams/search',
      queryParams: {'q': normalized},
      requireAuth: true,
    );
    if (response is! List) {
      throw const FormatException('Invalid football-team search response.');
    }
    return response
        .map(parseApiFootballTeam)
        .where((team) => team.teamId.isNotEmpty && team.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> fetchFootballTeamPlayers(String teamId) async {
    final normalized = teamId.trim();
    if (!RegExp(r'^\d{3,20}$').hasMatch(normalized)) {
      return const <String>[];
    }
    final response = await api.get(
      '/football/teams/${Uri.encodeComponent(normalized)}/players',
      requireAuth: true,
    );
    if (response is! List) {
      throw const FormatException('Invalid football-player response.');
    }
    final names = <String>{};
    for (final raw in response.whereType<Map>()) {
      final player = Map<String, dynamic>.from(raw);
      final position = (player['position'] ?? '').toString().toLowerCase();
      final name = (player['name'] ?? player['player'] ?? '').toString().trim();
      if (name.isNotEmpty && !position.contains('goalkeeper')) {
        names.add(name);
      }
    }
    return names.toList(growable: false);
  }

  /// Loads normalized timeline, lineup, table and statistics through the
  /// self-hosted API. Keeping the football-provider key on the server also
  /// avoids direct-browser CORS failures on Flutter web.
  Future<MatchDetails> fetchMatchDetails(String matchId) async {
    final encodedId = Uri.encodeComponent(matchId);
    final response = await api.get('/matches/$encodedId/details');
    if (response is! Map) {
      throw const FormatException('Invalid match-details response.');
    }
    return MatchDetails.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<AbuChallenge>> fetchActiveChallenges() async {
    final res = await api.get('/challenges/active');
    if (res is List) {
      return res.map((c) => _parseChallenge(c)).toList(growable: false);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid challenge list.',
      details: res,
    );
  }

  Future<Map<String, dynamic>> submitChallengeAnswer({
    required String challengeId,
    required String answer,
  }) async {
    final res = await api.post(
      '/challenges/$challengeId/submit',
      body: {'answer': answer},
      requireAuth: true,
    );
    return res is Map<String, dynamic>
        ? res
        : {'correct': false, 'pointsAwarded': 0};
  }

  Future<void> submitPrediction({
    required String matchId,
    required int homeScore,
    required int awayScore,
    required String firstScorer,
    String? homeTeam,
    String? awayTeam,
    String? competition,
    DateTime? kickoffAt,
    String? homeLogoUrl,
    String? awayLogoUrl,
  }) async {
    await api.post(
      '/predictions',
      body: {
        'matchId': matchId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'firstScorer': firstScorer,
        if (homeTeam != null && homeTeam.isNotEmpty) 'homeTeam': homeTeam,
        if (awayTeam != null && awayTeam.isNotEmpty) 'awayTeam': awayTeam,
        if (competition != null && competition.isNotEmpty)
          'competition': competition,
        if (kickoffAt != null) 'kickoffAt': kickoffAt.toUtc().toIso8601String(),
        if (homeLogoUrl != null && homeLogoUrl.isNotEmpty)
          'homeLogoUrl': homeLogoUrl,
        if (awayLogoUrl != null && awayLogoUrl.isNotEmpty)
          'awayLogoUrl': awayLogoUrl,
      },
      requireAuth: true,
    );
  }

  Future<List<SavedPrediction>> fetchMyPredictions() async {
    final res = await api.get('/predictions/my', requireAuth: true);
    if (res is List) {
      return res.map((p) => _parsePrediction(p)).toList();
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid prediction history.',
      details: res,
    );
  }

  Future<Map<String, dynamic>> checkInDailyStreak() async {
    final res = await api.post('/streaks/check-in', requireAuth: true);
    if (res is Map<String, dynamic> &&
        res['streakCount'] is num &&
        res['pointsAwarded'] is num) {
      return res;
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not confirm the daily streak check-in.',
      details: res,
    );
  }

  Future<List<LeaderboardEntry>> fetchTopLeaderboard({
    String period = 'monthly',
  }) async {
    final res = await api.get('/leaderboards/$period');
    if (res is Map && res['leaderboard'] is List) {
      return (res['leaderboard'] as List)
          .map(
            (e) => LeaderboardEntry(
              uid: e['userId'] ?? '',
              username: e['username'] ?? '',
              displayName: e['displayName'] ?? '',
              avatarUrl: e['avatarUrl'] ?? '',
              supportedTeam: e['supportedTeam'] ?? '',
              monthlyPoints: (e['points'] ?? 0).toInt(),
              seasonPoints: (e['points'] ?? 0).toInt(),
              isMember: e['isYouTubeMember'] == true,
            ),
          )
          .toList(growable: false);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid leaderboard.',
      details: res,
    );
  }

  Future<void> updateSupportedTeam(String teamName, {String? teamLogo}) async {
    await api.put(
      '/profile/team',
      body: {'teamName': teamName, 'teamLogo': teamLogo},
      requireAuth: true,
    );
  }

  Future<AbuUserProfile?> fetchPublicProfile(String id) async {
    try {
      final res = await api.get('/profile/$id');
      if (res is Map) {
        return AbuUserProfile(
          uid: res['firebaseUid'] ?? res['id'] ?? id,
          email: '',
          displayName: res['displayName'] ?? 'Fan',
          username: res['username'] ?? '',
          avatarUrl: res['avatarUrl'] ?? '',
          supportedTeam: res['supportedTeam'] ?? 'Barcelona',
          supportedTeamLogo: res['supportedTeamLogo'] ?? '',
          country: res['country'] ?? '',
          countryCode: res['countryCode'] ?? '',
          role: res['role'] ?? 'user',
          membershipMultiplier: res['isYouTubeMember'] == true ? 2.0 : 1.0,
          suspended: false,
          totalPoints: (res['totalPoints'] ?? 0).toInt(),
          monthlyPoints: (res['monthlyPoints'] ?? 0).toInt(),
          seasonPoints: (res['seasonPoints'] ?? 0).toInt(),
          loyaltyPoints: (res['loyaltyPoints'] ?? 0).toInt(),
          currentStreak: (res['streakCount'] ?? 0).toInt(),
          longestStreak: (res['streakBest'] ?? 0).toInt(),
          level: (res['level'] ?? 1).toInt(),
          exactPredictions: (res['exactPredictionsCount'] ?? 0).toInt(),
          challengesCompleted: (res['challengesCompletedCount'] ?? 0).toInt(),
          playerCardsCollected: (res['playerCardsCollectedCount'] ?? 0).toInt(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? country,
    String? countryCode,
    String? avatarUrl,
    String? supportedTeam,
    String? supportedTeamLogo,
    bool? onboardingCompleted,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (username != null) body['username'] = username;
    if (country != null) body['country'] = country;
    if (countryCode != null) body['countryCode'] = countryCode;
    final normalizedAvatar = _absoluteHttpUrlOrNull(avatarUrl);
    if (normalizedAvatar != null) body['avatarUrl'] = normalizedAvatar;
    if (supportedTeam != null) body['supportedTeam'] = supportedTeam;
    if (onboardingCompleted == true) body['onboardingCompleted'] = true;
    final normalizedTeamLogo = _absoluteHttpUrlOrNull(supportedTeamLogo);
    if (normalizedTeamLogo != null) {
      body['supportedTeamLogo'] = normalizedTeamLogo;
    }

    await api.put('/profile/me', body: body, requireAuth: true);
  }

  String? _absoluteHttpUrlOrNull(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Future<String> uploadAvatar({
    required List<int> bytes,
    required String fileName,
  }) async {
    return _uploadImage('/uploads/avatar', bytes: bytes, fileName: fileName);
  }

  Future<String> uploadAdminImage({
    required String purpose,
    required List<int> bytes,
    required String fileName,
  }) async {
    const supportedPurposes = <String>{
      'announcement',
      'post',
      'challenge',
      'player_card',
    };
    if (!supportedPurposes.contains(purpose)) {
      throw ArgumentError('Unsupported image upload purpose: $purpose');
    }
    return _uploadImage(
      '/admin/uploads/$purpose',
      bytes: bytes,
      fileName: fileName,
    );
  }

  Future<String> _uploadImage(
    String path, {
    required List<int> bytes,
    required String fileName,
  }) async {
    final res = await api.postMultipart(
      path,
      bytes: bytes,
      fileName: fileName,
      requireAuth: true,
    );
    if (res is Map && res['url'] is String) {
      final url = (res['url'] as String).trim();
      if (url.isNotEmpty) return url;
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The media server did not return an image URL.',
      details: res,
    );
  }

  Future<void> verifyYouTubeMember({
    String? channelId,
    String? googleEmail,
  }) async {
    await api.post(
      '/profile/verify-yt-member',
      body: {'channelId': channelId, 'googleEmail': googleEmail},
      requireAuth: true,
    );
  }

  Future<List<PointLedgerEntry>> fetchPointHistory() async {
    final res = await api.get('/profile/point-history', requireAuth: true);
    if (res is List) {
      return res
          .map(
            (r) => PointLedgerEntry(
              id: r['id']?.toString() ?? '',
              sourceType: r['source_type'] ?? 'general',
              sourceId: r['source_id']?.toString() ?? r['id']?.toString() ?? '',
              basePoints: parseApiInt(r['base_points']),
              // PostgreSQL NUMERIC values are intentionally returned as
              // strings by node-postgres so precision is not lost. Accept
              // either representation instead of throwing on real devices.
              multiplier: parseApiDouble(r['multiplier'], 1),
              finalPoints: parseApiInt(r['final_points']),
              reason: r['description'] ?? 'Points awarded',
              createdAt:
                  DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
            ),
          )
          .toList();
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid points history.',
      details: res,
    );
  }

  Future<void> registerFcmToken(
    String fcmToken,
    String platform, {
    String? locale,
  }) async {
    await api.post(
      '/devices/register',
      body: {
        'fcmToken': fcmToken,
        'platform': platform,
        if (locale != null && locale.isNotEmpty) 'locale': locale,
      },
      requireAuth: true,
    );
  }

  Future<void> unregisterFcmToken(String fcmToken) async {
    await api.post(
      '/devices/unregister',
      body: {'fcmToken': fcmToken},
      requireAuth: true,
    );
  }

  Future<List<AbuUserProfile>> fetchAdminUsers({
    String search = '',
    String? role,
    String? status,
    int limit = 200,
  }) async {
    final response = await api.get(
      '/admin/users',
      queryParams: <String, String>{
        if (search.trim().isNotEmpty) 'q': search.trim(),
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit.clamp(1, 200).toString(),
      },
      requireAuth: true,
    );
    if (response is! Map || response['users'] is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid user directory.',
        details: response,
      );
    }
    return (response['users'] as List)
        .map(parseAdminUserProfile)
        .toList(growable: false);
  }

  Future<void> setAdminUserStatus({
    required String userId,
    required bool suspended,
  }) async {
    await api.post(
      '/admin/users/${Uri.encodeComponent(userId)}/status',
      body: <String, dynamic>{
        'status': suspended ? 'suspended' : 'active',
        'reason': suspended
            ? 'Suspended from the admin user directory.'
            : 'Reactivated from the admin user directory.',
      },
      requireAuth: true,
    );
  }

  Future<void> setAdminUserRole({
    required String userId,
    required String role,
  }) async {
    final apiRole = role == 'superAdmin' ? 'super_admin' : role;
    const supportedRoles = <String>{
      'fan',
      'member',
      'moderator',
      'admin',
      'super_admin',
    };
    if (!supportedRoles.contains(apiRole)) {
      throw ArgumentError('Unsupported role.');
    }
    await api.post(
      '/admin/users/${Uri.encodeComponent(userId)}/roles',
      body: <String, dynamic>{
        'roles': <String>{'fan', apiRole}.toList(growable: false),
        'reason': 'Role changed from the admin user directory.',
      },
      requireAuth: true,
    );
  }

  Future<AdminPointAdjustmentResult> adjustAdminUserPoints({
    required String userId,
    required int delta,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await api.post(
      '/admin/users/${Uri.encodeComponent(userId)}/points',
      body: <String, dynamic>{
        'amount': delta,
        'reason': reason,
        'idempotencyKey': idempotencyKey,
      },
      requireAuth: true,
    );
    if (response is! Map) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server did not confirm the point adjustment.',
        details: response,
      );
    }
    return AdminPointAdjustmentResult.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  Future<List<AdminPointAdjustment>> fetchAdminPointAdjustments() async {
    final response = await api.get(
      '/admin/point-adjustments',
      requireAuth: true,
    );
    if (response is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid point-adjustment history.',
        details: response,
      );
    }
    return response.map(parseAdminPointAdjustment).toList(growable: false);
  }

  Future<void> setAdminYouTubeMembership({
    required String userId,
    required bool isMember,
  }) async {
    await api.post(
      '/admin/users/${Uri.encodeComponent(userId)}/membership',
      body: <String, dynamic>{
        'isMember': isMember,
        'reason': isMember
            ? 'Gold membership granted from the admin user directory.'
            : 'Gold membership revoked from the admin user directory.',
      },
      requireAuth: true,
    );
  }

  Future<void> updateNotificationPreferences({
    required bool enabled,
    required bool matchEnabled,
    required bool challengeEnabled,
    required bool rewardEnabled,
    required bool newsEnabled,
  }) async {
    await api.put(
      '/notifications/preferences',
      body: {
        'enabled': enabled,
        'matchEnabled': matchEnabled,
        'challengeEnabled': challengeEnabled,
        'rewardEnabled': rewardEnabled,
        'newsEnabled': newsEnabled,
      },
      requireAuth: true,
    );
  }

  Future<Map<String, dynamic>> sendPushNotificationTest() async {
    final result = await api.post(
      '/notifications/test',
      body: const <String, dynamic>{},
      requireAuth: true,
    );
    return Map<String, dynamic>.from(result as Map);
  }

  AbuChallenge _parseChallenge(dynamic c) {
    return AbuChallenge(
      id: c['id'] ?? '',
      title: c['title'] ?? '',
      description: c['description'] ?? '',
      kind: c['kind'] ?? 'videoPhrase',
      status: c['status'] ?? 'open',
      rewardPoints: (c['reward_points'] ?? 10).toInt(),
      availableFrom: DateTime.tryParse(c['starts_at'] ?? '') ?? DateTime.now(),
      availableUntil: DateTime.tryParse(c['ends_at'] ?? '') ?? DateTime.now(),
      videoUrl: c['video_url'] ?? '',
      imageUrl: c['image_url'] ?? '',
      questions: const [],
      maximumAttempts: (c['maximum_attempts'] ?? 3).toInt(),
      memberOnly: c['member_only'] == true,
    );
  }

  SavedPrediction _parsePrediction(dynamic p) {
    return SavedPrediction(
      id: p['id']?.toString() ?? '',
      userId: p['user_id']?.toString() ?? '',
      matchId: p['match_id'] ?? '',
      homeScore: (p['home_score'] ?? 0).toInt(),
      awayScore: (p['away_score'] ?? 0).toInt(),
      firstScorer: p['first_scorer'] ?? '',
      submittedAt: DateTime.tryParse(p['submitted_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(p['updated_at'] ?? '') ?? DateTime.now(),
      rewarded: p['rewarded'] == true,
      pointsAwarded: (p['points_awarded'] ?? 0).toInt(),
      seenResult: p['seen_result'] == true,
      homeTeam: p['home_team'] ?? '',
      awayTeam: p['away_team'] ?? '',
    );
  }

  Future<List<ExclusiveVideo>> fetchExclusiveVideos() async {
    final res = await api.get('/videos/exclusive');
    if (res is List) {
      return res.map((v) => ExclusiveVideo.fromJson(v)).toList(growable: false);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid exclusive-video list.',
      details: res,
    );
  }

  Future<void> createExclusiveVideo({
    required String youtubeId,
    required String title,
    String? description,
    String? thumbnailUrl,
    DateTime? publishedAt,
    bool isUnlisted = true,
    bool memberOnly = false,
  }) async {
    await api.post(
      '/admin/videos',
      body: {
        'youtubeId': youtubeId,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
          'thumbnailUrl': thumbnailUrl,
        if (publishedAt != null)
          'publishedAt': publishedAt.toUtc().toIso8601String(),
        'isUnlisted': isUnlisted,
        'memberOnly': memberOnly,
      },
      requireAuth: true,
    );
  }

  Future<void> deleteExclusiveVideo(String id) async {
    await api.delete('/admin/videos/$id', requireAuth: true);
  }
}
