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

enum YouTubeOAuthFlowState {
  pending,
  verified,
  notMember,
  connected,
  disconnected,
  expired,
  error,
}

enum YouTubeOAuthErrorCode {
  none,
  creatorMembersApiUnavailable,
  creatorMembershipsDisabled,
  creatorChannelMismatch,
  googleAccountMismatch,
  youtubeChannelAlreadyLinked,
  authorizationDenied,
  youtubeChannelMissing,
  youtubeChannelAmbiguous,
  googleAccountLinkRequired,
  creatorNotConnected,
  creatorReauthorizationRequired,
  creatorReusableAuthorizationMissing,
  youtubeScopeMissing,
  oauthFlowExpired,
  youtubeApiUnavailable,
  youtubeNotConfigured,
  unknown,
}

class YouTubeOAuthStart {
  const YouTubeOAuthStart({
    required this.flowId,
    required this.authorizationUrl,
  });

  final String flowId;
  final Uri authorizationUrl;
}

class YouTubeOAuthStatus {
  const YouTubeOAuthStatus({
    required this.state,
    this.isYouTubeMember = false,
    this.channelTitle = '',
    this.errorCode = YouTubeOAuthErrorCode.none,
  });

  final YouTubeOAuthFlowState state;
  final bool isYouTubeMember;
  final String channelTitle;
  final YouTubeOAuthErrorCode errorCode;

  bool get isPending => state == YouTubeOAuthFlowState.pending;
  bool get isSuccessful =>
      state == YouTubeOAuthFlowState.verified ||
      state == YouTubeOAuthFlowState.connected;
  bool get isTerminal => !isPending;
}

YouTubeOAuthErrorCode _parseYouTubeOAuthErrorCode(dynamic value) {
  final code = value?.toString().trim().toLowerCase() ?? '';
  return switch (code) {
    '' => YouTubeOAuthErrorCode.none,
    'creator_members_api_unavailable' =>
      YouTubeOAuthErrorCode.creatorMembersApiUnavailable,
    'creator_memberships_disabled' =>
      YouTubeOAuthErrorCode.creatorMembershipsDisabled,
    'creator_channel_mismatch' => YouTubeOAuthErrorCode.creatorChannelMismatch,
    'google_account_mismatch' ||
    'google_identity_invalid' => YouTubeOAuthErrorCode.googleAccountMismatch,
    'youtube_channel_already_linked' =>
      YouTubeOAuthErrorCode.youtubeChannelAlreadyLinked,
    'oauth_authorization_denied' => YouTubeOAuthErrorCode.authorizationDenied,
    'youtube_channel_missing' => YouTubeOAuthErrorCode.youtubeChannelMissing,
    'youtube_channel_ambiguous' =>
      YouTubeOAuthErrorCode.youtubeChannelAmbiguous,
    'google_account_link_required' =>
      YouTubeOAuthErrorCode.googleAccountLinkRequired,
    'creator_not_connected' => YouTubeOAuthErrorCode.creatorNotConnected,
    'creator_reauthorization_required' ||
    'creator_token_rejected' ||
    'creator_token_unavailable' ||
    'creator_token_incomplete' =>
      YouTubeOAuthErrorCode.creatorReauthorizationRequired,
    'creator_refresh_token_missing' =>
      YouTubeOAuthErrorCode.creatorReusableAuthorizationMissing,
    'youtube_scope_missing' => YouTubeOAuthErrorCode.youtubeScopeMissing,
    'oauth_flow_expired' ||
    'invalid_or_expired_oauth_state' ||
    'youtube_flow_not_found' => YouTubeOAuthErrorCode.oauthFlowExpired,
    'youtube_api_unavailable' ||
    'youtube_api_rejected' ||
    'youtube_verification_failed' =>
      YouTubeOAuthErrorCode.youtubeApiUnavailable,
    'youtube_not_configured' ||
    'youtube_invalid_encryption_key' ||
    'youtube_invalid_redirect_uri' ||
    'youtube_invalid_client_id' ||
    'youtube_invalid_creator_channel' ||
    'youtube_secret_encryption_failed' ||
    'youtube_secret_decryption_failed' =>
      YouTubeOAuthErrorCode.youtubeNotConfigured,
    _ => YouTubeOAuthErrorCode.unknown,
  };
}

@visibleForTesting
YouTubeOAuthStart parseYouTubeOAuthStart(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid YouTube connection response.');
  }
  final response = Map<String, dynamic>.from(value);
  final flowId = (response['flowId'] ?? response['flow_id'] ?? '')
      .toString()
      .trim();
  final authorizationUrl = Uri.tryParse(
    (response['authorizationUrl'] ?? response['authorization_url'] ?? '')
        .toString()
        .trim(),
  );
  final safeFlowId = RegExp(r'^[A-Za-z0-9_-]{8,200}$').hasMatch(flowId);
  // OAuth must open Google's own authorization host. Neither a creator token
  // nor a generic server-provided web destination is accepted by the client.
  final safeAuthorizationUrl =
      authorizationUrl != null &&
      authorizationUrl.scheme == 'https' &&
      authorizationUrl.host == 'accounts.google.com';
  if (!safeFlowId || !safeAuthorizationUrl) {
    throw const FormatException('Invalid YouTube connection response.');
  }
  return YouTubeOAuthStart(flowId: flowId, authorizationUrl: authorizationUrl);
}

@visibleForTesting
YouTubeOAuthStatus parseYouTubeOAuthStatus(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid YouTube connection status.');
  }
  final response = Map<String, dynamic>.from(value);
  var rawStatus = (response['status'] ?? '').toString().trim().toLowerCase();
  rawStatus = rawStatus.replaceAll('-', '_').replaceAll(' ', '_');
  if (rawStatus.isEmpty && response['connected'] == true) {
    rawStatus = 'connected';
  } else if (rawStatus.isEmpty && response['connected'] == false) {
    rawStatus = 'disconnected';
  }
  final state = switch (rawStatus) {
    'pending' || 'awaiting_authorization' => YouTubeOAuthFlowState.pending,
    'verified' || 'member' || 'active_member' => YouTubeOAuthFlowState.verified,
    'not_member' || 'notmember' => YouTubeOAuthFlowState.notMember,
    'connected' || 'authorized' => YouTubeOAuthFlowState.connected,
    'disconnected' || 'not_connected' => YouTubeOAuthFlowState.disconnected,
    'expired' || 'cancelled' || 'canceled' => YouTubeOAuthFlowState.expired,
    'error' || 'failed' || 'denied' => YouTubeOAuthFlowState.error,
    _ => throw const FormatException('Invalid YouTube connection status.'),
  };
  return YouTubeOAuthStatus(
    state: state,
    isYouTubeMember:
        response['isYouTubeMember'] == true || response['is_member'] == true,
    channelTitle: (response['channelTitle'] ?? response['channel_title'] ?? '')
        .toString()
        .trim(),
    // Only retain an allowlisted enum. Raw provider/server text is never
    // carried into UI state where it could disclose OAuth diagnostics.
    errorCode: _parseYouTubeOAuthErrorCode(
      response['errorCode'] ?? response['error_code'],
    ),
  );
}

class RewardRedemptionReceipt {
  const RewardRedemptionReceipt({
    required this.redemptionId,
    required this.remainingBalance,
    required this.claimCount,
    required this.duplicate,
    this.stockRemaining,
  });

  final String redemptionId;
  final int remainingBalance;
  final int? stockRemaining;
  final int claimCount;
  final bool duplicate;
}

@visibleForTesting
RewardRedemptionReceipt parseRewardRedemptionReceipt(dynamic value) {
  if (value is! Map || value['ok'] != true) {
    throw const FormatException('Invalid reward-redemption response.');
  }
  final response = Map<String, dynamic>.from(value);
  final redemptionId = (response['redemptionId'] ?? '').toString().trim();
  final remainingBalance = response['remainingBalance'];
  final claimCount = response['claimCount'];
  final stockRemaining = response['stockRemaining'];
  if (redemptionId.isEmpty ||
      remainingBalance is! num ||
      claimCount is! num ||
      (stockRemaining != null && stockRemaining is! num)) {
    throw const FormatException('Invalid reward-redemption response.');
  }
  return RewardRedemptionReceipt(
    redemptionId: redemptionId,
    remainingBalance: remainingBalance.toInt(),
    stockRemaining: (stockRemaining as num?)?.toInt(),
    claimCount: claimCount.toInt(),
    duplicate: response['duplicate'] == true,
  );
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
    status: switch ((match['status'] ?? 'upcoming').toString()) {
      'scheduled' => 'draft',
      'closed' => 'locked',
      'finished' => 'completed',
      'cancelled' || 'postponed' => 'disabled',
      _ => (match['status'] ?? 'upcoming').toString(),
    },
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
SavedPrediction parseApiSavedPrediction(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid prediction response.');
  }
  final prediction = Map<String, dynamic>.from(value);
  final matchStatus = (prediction['match_status'] ?? '').toString();
  final actualHomeScore = prediction['actual_home_score'];
  final actualAwayScore = prediction['actual_away_score'];
  final hasMatch =
      matchStatus.isNotEmpty ||
      actualHomeScore != null ||
      actualAwayScore != null;
  return SavedPrediction(
    id: prediction['id']?.toString() ?? '',
    userId: prediction['user_id']?.toString() ?? '',
    matchId: prediction['match_id']?.toString() ?? '',
    homeScore: parseApiInt(prediction['home_score']),
    awayScore: parseApiInt(prediction['away_score']),
    firstScorer: prediction['first_scorer']?.toString() ?? '',
    submittedAt:
        DateTime.tryParse(prediction['submitted_at']?.toString() ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(prediction['updated_at']?.toString() ?? '') ??
        DateTime.now(),
    rewarded: prediction['rewarded'] == true,
    pointsAwarded: parseApiInt(prediction['points_awarded']),
    seenResult: prediction['seen_result'] == true,
    exactMatchResult: prediction['is_exact_match'] is bool
        ? prediction['is_exact_match'] as bool
        : null,
    firstScorerMatchResult: prediction['is_first_scorer_match'] is bool
        ? prediction['is_first_scorer_match'] as bool
        : null,
    winnerMatchResult: prediction['is_winner_match'] is bool
        ? prediction['is_winner_match'] as bool
        : null,
    homeTeam: prediction['home_team']?.toString() ?? '',
    awayTeam: prediction['away_team']?.toString() ?? '',
    match: hasMatch
        ? parseApiMatchEvent(<String, dynamic>{
            'id': prediction['match_id'],
            'competition_name': prediction['competition_name'],
            'home_team': prediction['home_team'],
            'away_team': prediction['away_team'],
            'home_logo_url': prediction['home_logo_url'],
            'away_logo_url': prediction['away_logo_url'],
            'kickoff_at': prediction['kickoff_at'],
            'predictions_open_at': prediction['predictions_open_at'],
            'predictions_close_at': prediction['predictions_close_at'],
            'first_scorer_options': prediction['first_scorer_options'],
            'status': matchStatus,
            'home_score': actualHomeScore,
            'away_score': actualAwayScore,
            'first_scorer': prediction['actual_first_scorer'],
          })
        : null,
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
  DateTime? optionalTimestamp(String camelCase, String snakeCase) {
    final raw = user[camelCase] ?? user[snakeCase];
    if (raw == null || raw.toString().trim().isEmpty) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  final youtubeChannelId =
      (user['youtubeChannelId'] ?? user['youtube_channel_id'] ?? '')
          .toString()
          .trim();
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
    youtubeChannelLinked:
        user['youtubeChannelLinked'] == true || youtubeChannelId.isNotEmpty,
    youtubeMembershipLevelId:
        (user['youtubeMembershipLevelId'] ??
                user['youtube_membership_level_id'] ??
                '')
            .toString(),
    youtubeMembershipVerifiedAt: optionalTimestamp(
      'youtubeMembershipVerifiedAt',
      'youtube_membership_verified_at',
    ),
    youtubeMemberSince: optionalTimestamp(
      'youtubeMemberSince',
      'youtube_member_since',
    ),
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

@visibleForTesting
AbuChallenge parseApiChallenge(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid challenge response.');
  }
  return AbuChallenge.fromMap(Map<String, dynamic>.from(value));
}

@visibleForTesting
AbuPlayerCard parseApiPlayerCard(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid Player Card response.');
  }
  return AbuPlayerCard.fromMap(Map<String, dynamic>.from(value));
}

@visibleForTesting
LaunchAnnouncement? parseApiLaunchAnnouncement(dynamic value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const FormatException('Invalid launch-popup response.');
  }
  return LaunchAnnouncement.fromMap(Map<String, dynamic>.from(value));
}

@visibleForTesting
AbuRewardRedemption parseApiRedemption(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Invalid redemption response.');
  }
  return AbuRewardRedemption.fromMap(Map<String, dynamic>.from(value));
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
        totalPoints: (p['total_points'] ?? 0).toInt(),
        monthlyPoints: (p['monthly_points'] ?? 0).toInt(),
        seasonPoints: (p['season_points'] ?? 0).toInt(),
        loyaltyPoints: (p['loyalty_points'] ?? 0).toInt(),
        currentStreak: (p['streak_count'] ?? 0).toInt(),
        longestStreak: (p['streak_best'] ?? 0).toInt(),
        level: (p['level'] ?? 1).toInt(),
        exactPredictions: (p['exact_predictions_count'] ?? 0).toInt(),
        challengesCompleted: (p['challenges_completed_count'] ?? 0).toInt(),
        playerCardsCollected: (p['player_cards_collected_count'] ?? 0).toInt(),
        lastCheckInDate: p['streak_last_checkin'] != null
            ? p['streak_last_checkin'].toString().split('T').first
            : '',
        lastActivityAt: DateTime.tryParse(
          (p['streak_last_checkin'] ?? '').toString(),
        ),
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

  Future<List<MatchEvent>> fetchManagedMatches() async {
    final response = await api.get('/admin/matches', requireAuth: true);
    if (response is List) {
      return response.map(parseApiMatchEvent).toList(growable: false);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid managed-match list.',
      details: response,
    );
  }

  Future<MatchEvent> fetchMatch(String matchId) async {
    final response = await api.get('/matches/${Uri.encodeComponent(matchId)}');
    if (response is Map && response['match'] is Map) {
      return parseApiMatchEvent(response['match']);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid match.',
      details: response,
    );
  }

  Future<MatchEvent> createAdminMatch({
    required String id,
    required String homeTeam,
    required String awayTeam,
    required String competition,
    required DateTime kickoffAt,
    required DateTime predictionsOpenAt,
    required DateTime predictionsCloseAt,
    required List<String> firstScorerOptions,
    String? homeLogoUrl,
    String? awayLogoUrl,
  }) async {
    final response = await api.post(
      '/admin/matches',
      requireAuth: true,
      body: <String, dynamic>{
        'id': id,
        'competitionName': competition.trim(),
        'homeTeam': homeTeam.trim(),
        'awayTeam': awayTeam.trim(),
        'kickoffAt': kickoffAt.toUtc().toIso8601String(),
        'predictionsOpenAt': predictionsOpenAt.toUtc().toIso8601String(),
        'predictionsCloseAt': predictionsCloseAt.toUtc().toIso8601String(),
        'firstScorerOptions': firstScorerOptions,
        if (homeLogoUrl != null && homeLogoUrl.isNotEmpty)
          'homeLogoUrl': homeLogoUrl,
        if (awayLogoUrl != null && awayLogoUrl.isNotEmpty)
          'awayLogoUrl': awayLogoUrl,
      },
    );
    if (response is Map && response['match'] is Map) {
      return parseApiMatchEvent(response['match']);
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not confirm the match.',
      details: response,
    );
  }

  Future<void> setAdminMatchStatus({
    required String matchId,
    required String status,
  }) async {
    await api.put(
      '/admin/matches/${Uri.encodeComponent(matchId)}/status',
      requireAuth: true,
      body: {'status': status},
    );
  }

  Future<void> settleAdminMatch({
    required String matchId,
    required int homeScore,
    required int awayScore,
    required String firstScorer,
  }) async {
    await api.post(
      '/admin/matches/${Uri.encodeComponent(matchId)}/settle',
      requireAuth: true,
      body: <String, dynamic>{
        'homeScore': homeScore,
        'awayScore': awayScore,
        'firstScorer': firstScorer.trim(),
      },
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
  Future<MatchDetails> fetchMatchDetails(
    String matchId, {
    bool forceRefresh = false,
  }) async {
    final encodedId = Uri.encodeComponent(matchId);
    final response = await api.get(
      '/matches/$encodedId/details',
      bypassCache: forceRefresh,
    );
    if (response is! Map) {
      throw const FormatException('Invalid match-details response.');
    }
    return MatchDetails.fromMap(Map<String, dynamic>.from(response));
  }

  Future<List<AbuChallenge>> fetchActiveChallenges() async {
    final res = await api.get(
      '/challenges/active',
      requireAuth: true,
      bypassCache: true,
    );
    if (res is List) {
      return res.map(parseApiChallenge).toList(growable: false);
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

  Future<List<AbuChallenge>> fetchManagedChallenges() async {
    final response = await api.get('/admin/challenges', requireAuth: true);
    if (response is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid admin challenge list.',
        details: response,
      );
    }
    return response.map(parseApiChallenge).toList(growable: false);
  }

  Future<String> createAdminChallenge({
    required String kind,
    required String title,
    required String description,
    required String videoUrl,
    required String imageUrl,
    required int rewardPoints,
    required DateTime availableFrom,
    required DateTime availableUntil,
    required String status,
    required int maximumAttempts,
    required bool memberOnly,
    required bool notifyOnLive,
    required List<Map<String, dynamic>> questions,
    String playerCardId = '',
  }) async {
    final response = await api.post(
      '/admin/challenges',
      requireAuth: true,
      body: <String, dynamic>{
        'kind': kind,
        'title': title,
        'description': description,
        'videoUrl': videoUrl,
        'imageUrl': imageUrl,
        'rewardPoints': rewardPoints,
        'availableFrom': availableFrom.toUtc().toIso8601String(),
        'availableUntil': availableUntil.toUtc().toIso8601String(),
        'status': status,
        'maximumAttempts': maximumAttempts,
        'memberOnly': memberOnly,
        'notifyOnLive': notifyOnLive,
        if (playerCardId.trim().isNotEmpty) 'playerCardId': playerCardId.trim(),
        'questions': questions,
      },
    );
    if (response is Map && response['id'] != null) {
      return response['id'].toString();
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not confirm the new challenge.',
      details: response,
    );
  }

  Future<void> setAdminChallengeStatus({
    required String challengeId,
    required String status,
  }) async {
    await api.put(
      '/admin/challenges/${Uri.encodeComponent(challengeId)}/status',
      body: {'status': status},
      requireAuth: true,
    );
  }

  Future<void> deleteAdminChallenge(String challengeId) async {
    await api.delete(
      '/admin/challenges/${Uri.encodeComponent(challengeId)}',
      requireAuth: true,
    );
  }

  Future<List<AbuPlayerCard>> fetchPlayerCards({bool managed = false}) async {
    final response = await api.get(
      managed ? '/admin/player-cards' : '/player-cards',
      // The fan endpoint is personalized: locked cards have their private
      // identity fields redacted and unlock state comes from this user's
      // player_card_claims row.
      requireAuth: true,
    );
    if (response is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid Player Card list.',
        details: response,
      );
    }
    return response.map(parseApiPlayerCard).toList(growable: false);
  }

  Future<String> saveAdminPlayerCard(AbuPlayerCard card) async {
    final response = await api.post(
      '/admin/player-cards',
      requireAuth: true,
      body: <String, dynamic>{
        if (card.id.isNotEmpty) 'id': card.id,
        'playerName': card.playerName,
        'playerNameAr': card.playerNameAr,
        'imageUrl': card.imageUrl,
        'teamName': card.teamName,
        'teamLogoUrl': card.teamLogoUrl,
        'position': card.position,
        'rating': card.rating,
        'rarity': card.rarity,
        'stats': card.stats,
        'description': card.description,
        'descriptionAr': card.descriptionAr,
        'enabled': card.enabled,
      },
    );
    if (response is Map && response['id'] != null) {
      return response['id'].toString();
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not confirm the Player Card save.',
      details: response,
    );
  }

  Future<void> setAdminPlayerCardEnabled({
    required String cardId,
    required bool enabled,
  }) async {
    await api.put(
      '/admin/player-cards/${Uri.encodeComponent(cardId)}/status',
      body: {'enabled': enabled},
      requireAuth: true,
    );
  }

  Future<void> deleteAdminPlayerCard(String cardId) async {
    await api.delete(
      '/admin/player-cards/${Uri.encodeComponent(cardId)}',
      requireAuth: true,
    );
  }

  Future<LaunchAnnouncement?> fetchLaunchAnnouncement() async {
    // Launch popups are tiny mutable settings. Always revalidate so an admin
    // reset cannot be replayed from the native client's public GET cache.
    final response = await api.get(
      '/settings/launch-announcement',
      bypassCache: true,
    );
    return parseApiLaunchAnnouncement(response);
  }

  Future<LaunchAnnouncement> saveAdminLaunchAnnouncement({
    required bool enabled,
    required String title,
    required String body,
    required String imageUrl,
    required String linkUrl,
    required String buttonLabel,
    required String frequency,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final response = await api.put(
      '/admin/settings/launch-announcement',
      requireAuth: true,
      body: <String, dynamic>{
        'enabled': enabled,
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'linkUrl': linkUrl,
        'buttonLabel': buttonLabel,
        'frequency': frequency,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
      },
    );
    if (response is Map && response['announcement'] is Map) {
      return parseApiLaunchAnnouncement(response['announcement'])!;
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server did not confirm the launch popup.',
      details: response,
    );
  }

  Future<void> resetAdminLaunchAnnouncement() async {
    await api.delete('/admin/settings/launch-announcement', requireAuth: true);
  }

  Future<RewardRedemptionReceipt> redeemLoyaltyReward({
    required String rewardId,
    required String idempotencyKey,
  }) async {
    final response = await api.post(
      '/rewards/${Uri.encodeComponent(rewardId)}/redeem',
      requireAuth: true,
      body: {'idempotencyKey': idempotencyKey},
    );
    return parseRewardRedemptionReceipt(response);
  }

  Future<List<AbuRewardRedemption>> fetchAdminRedemptions() async {
    final response = await api.get('/admin/redemptions', requireAuth: true);
    if (response is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid redemption list.',
        details: response,
      );
    }
    return response.map(parseApiRedemption).toList(growable: false);
  }

  Future<void> updateAdminRedemptionStatus({
    required String redemptionId,
    required String status,
    String note = '',
  }) async {
    await api.put(
      '/admin/redemptions/${Uri.encodeComponent(redemptionId)}/status',
      requireAuth: true,
      body: {'status': status, 'note': note},
    );
  }

  Future<void> saveAdminAchievement(AbuAchievement achievement) async {
    await api.post(
      '/admin/achievements',
      requireAuth: true,
      body: <String, dynamic>{
        if (achievement.id.isNotEmpty) 'id': achievement.id,
        ...achievement.toMap(),
      },
    );
  }

  Future<void> setAdminAchievementEnabled({
    required String achievementId,
    required bool enabled,
  }) async {
    await api.put(
      '/admin/achievements/${Uri.encodeComponent(achievementId)}/status',
      requireAuth: true,
      body: {'enabled': enabled},
    );
  }

  Future<void> saveAdminLevel(AbuLevel level) async {
    await api.post(
      '/admin/levels',
      requireAuth: true,
      body: <String, dynamic>{
        if (level.id.isNotEmpty) 'id': level.id,
        ...level.toMap(),
      },
    );
  }

  Future<void> setAdminLevelEnabled({
    required String levelId,
    required bool enabled,
  }) async {
    await api.put(
      '/admin/levels/${Uri.encodeComponent(levelId)}/status',
      requireAuth: true,
      body: {'enabled': enabled},
    );
  }

  Future<void> saveAdminReward(AbuLoyaltyReward reward) async {
    await api.post(
      '/admin/rewards',
      requireAuth: true,
      body: <String, dynamic>{
        if (reward.id.isNotEmpty) 'id': reward.id,
        'title': reward.title.trim(),
        'titleAr': reward.titleAr.trim(),
        'description': reward.description.trim(),
        'descriptionAr': reward.descriptionAr.trim(),
        'imageUrl': reward.imageUrl.trim(),
        'category': reward.category,
        'cost': reward.cost,
        'stock': reward.stock,
        'unlimitedStock': reward.unlimitedStock,
        'perUserLimit': reward.perUserLimit,
        'memberOnly': reward.memberOnly,
        'enabled': reward.enabled,
        'startsAt': reward.startsAt?.toUtc().toIso8601String(),
        'endsAt': reward.endsAt?.toUtc().toIso8601String(),
        'fulfilmentType': reward.fulfilmentType,
      },
    );
  }

  Future<void> setAdminRewardEnabled({
    required String rewardId,
    required bool enabled,
  }) async {
    await api.put(
      '/admin/rewards/${Uri.encodeComponent(rewardId)}/status',
      requireAuth: true,
      body: {'enabled': enabled},
    );
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
      return res.map(parseApiSavedPrediction).toList();
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid prediction history.',
      details: res,
    );
  }

  Future<void> markPredictionResultSeen(String predictionId) async {
    await api.post(
      '/predictions/${Uri.encodeComponent(predictionId)}/seen',
      requireAuth: true,
      body: const <String, dynamic>{},
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

  LeaderboardEntry _leaderboardEntry(dynamic value) {
    final item = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final points = parseApiInt(item['points']);
    return LeaderboardEntry(
      uid: (item['publicId'] ?? item['userId'] ?? item['firebaseUid'] ?? '')
          .toString(),
      username: (item['username'] ?? '').toString(),
      displayName: (item['displayName'] ?? item['username'] ?? '').toString(),
      avatarUrl: (item['avatarUrl'] ?? '').toString(),
      supportedTeam: (item['supportedTeam'] ?? '').toString(),
      monthlyPoints: points,
      seasonPoints: points,
      totalPoints: points,
      isMember: item['isYouTubeMember'] == true,
    );
  }

  RankedLeaderboardEntry _rankedLeaderboardEntry(dynamic value, int fallback) {
    final item = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final entry = _leaderboardEntry(item);
    return RankedLeaderboardEntry(
      entry: entry,
      rank: parseApiInt(item['rank'], fallback),
      points: parseApiInt(item['points']),
    );
  }

  Future<LeaderboardSnapshot> fetchLeaderboardSnapshot({
    String period = 'monthly',
    String? seasonId,
  }) async {
    final res = await api.get(
      '/leaderboards/$period',
      queryParams: seasonId == null || seasonId.isEmpty
          ? null
          : <String, String>{'seasonId': seasonId},
    );
    if (res is Map && res['leaderboard'] is List) {
      final response = Map<String, dynamic>.from(res);
      final rawEntries = response['leaderboard'] as List;
      final entries = <RankedLeaderboardEntry>[
        for (var index = 0; index < rawEntries.length; index++)
          _rankedLeaderboardEntry(rawEntries[index], index + 1),
      ];
      final seasons = <LeaderboardSeason>[
        for (final season in (response['seasons'] as List? ?? const []))
          if (season is Map)
            LeaderboardSeason.fromMap(Map<String, dynamic>.from(season)),
      ];
      RankedLeaderboardEntry? currentUser;
      if (response['currentUser'] is Map) {
        currentUser = _rankedLeaderboardEntry(response['currentUser'], 0);
      } else {
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final uid = firebaseUser?.uid ?? '';
        currentUser = entries
            .where((item) => item.entry.uid == uid)
            .firstOrNull;
        if (currentUser == null && firebaseUser != null) {
          try {
            final rankResponse = await api.get(
              '/leaderboards/my-rank',
              queryParams: seasonId == null || seasonId.isEmpty
                  ? null
                  : <String, String>{'seasonId': seasonId},
              requireAuth: true,
              bypassCache: true,
            );
            if (rankResponse is Map) {
              final (rankKey, pointsKey) = switch (period) {
                'previous-month' => (
                  'previousMonthRank',
                  'previousMonthPoints',
                ),
                'season' => ('seasonRank', 'seasonPoints'),
                _ => ('monthlyRank', 'monthlyPoints'),
              };
              final rank = parseApiInt(rankResponse[rankKey]);
              final points = parseApiInt(rankResponse[pointsKey]);
              if (rank > 0) {
                currentUser = RankedLeaderboardEntry(
                  entry: LeaderboardEntry(
                    uid: (rankResponse['publicId'] ?? firebaseUser.uid)
                        .toString(),
                    username:
                        (rankResponse['publicId'] ??
                                firebaseUser.displayName ??
                                'Fan')
                            .toString(),
                    displayName: firebaseUser.displayName ?? 'Fan',
                    avatarUrl: firebaseUser.photoURL ?? '',
                    supportedTeam: '',
                    monthlyPoints: points,
                    seasonPoints: points,
                    totalPoints: points,
                    isMember: false,
                  ),
                  rank: rank,
                  points: points,
                );
              }
            }
          } catch (_) {
            // The public table remains useful if the authenticated personal
            // rank request is temporarily unavailable.
          }
        }
      }
      return LeaderboardSnapshot(
        entries: entries,
        currentUser: currentUser,
        totalPlayers: parseApiInt(response['totalPlayers'], entries.length),
        seasons: seasons,
        activeSeasonId:
            (response['activeSeasonId'] ?? response['activeSeason']?['id'])
                ?.toString(),
      );
    }
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid leaderboard.',
      details: res,
    );
  }

  Future<List<LeaderboardEntry>> fetchTopLeaderboard({
    String period = 'monthly',
  }) async =>
      (await fetchLeaderboardSnapshot(period: period)).entries
          .map((ranked) => ranked.entry)
          .toList(growable: false);

  Future<int> fetchMySeasonRank() async {
    final res = await api.get(
      '/leaderboards/my-rank',
      requireAuth: true,
      bypassCache: true,
    );
    if (res is Map) return parseApiInt(res['seasonRank']);
    throw AbuApiException(
      statusCode: 502,
      message: 'The server returned an invalid season rank.',
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
          uid: res['publicId'] ?? res['firebaseUid'] ?? res['id'] ?? id,
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

  Future<void> deleteAccount() async {
    await api.delete('/profile/me', requireAuth: true);
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

  Future<YouTubeOAuthStart> startYouTubeMembershipConnection() async {
    final response = await api.post(
      '/profile/youtube/connect/start',
      body: const <String, dynamic>{},
      requireAuth: true,
    );
    return parseYouTubeOAuthStart(response);
  }

  Future<YouTubeOAuthStatus> fetchYouTubeMembershipConnectionStatus(
    String flowId,
  ) async {
    final safeFlowId = Uri.encodeComponent(flowId.trim());
    final response = await api.get(
      '/profile/youtube/connect/$safeFlowId/status',
      requireAuth: true,
      bypassCache: true,
    );
    return parseYouTubeOAuthStatus(response);
  }

  Future<YouTubeOAuthStatus> fetchYouTubeCreatorConnectionStatus() async {
    final response = await api.get(
      '/admin/youtube/creator/status',
      requireAuth: true,
      bypassCache: true,
    );
    return parseYouTubeOAuthStatus(response);
  }

  Future<YouTubeOAuthStart> startYouTubeCreatorConnection() async {
    final response = await api.post(
      '/admin/youtube/creator/connect/start',
      body: const <String, dynamic>{},
      requireAuth: true,
    );
    return parseYouTubeOAuthStart(response);
  }

  Future<YouTubeOAuthStatus> fetchYouTubeCreatorFlowStatus(
    String flowId,
  ) async {
    final safeFlowId = Uri.encodeComponent(flowId.trim());
    final response = await api.get(
      '/admin/youtube/creator/connect/$safeFlowId/status',
      requireAuth: true,
      bypassCache: true,
    );
    return parseYouTubeOAuthStatus(response);
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
    required String installationId,
    String? locale,
  }) async {
    await api.post(
      '/devices/register',
      body: {
        'fcmToken': fcmToken,
        'installationId': installationId,
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

  Future<void> revokeFcmInstallation({
    required String fcmToken,
    required String installationId,
  }) async {
    await api.post(
      '/devices/revoke',
      body: {'fcmToken': fcmToken, 'installationId': installationId},
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

  Future<List<LeaderboardSeason>> fetchAdminLeaderboardSeasons() async {
    final response = await api.get(
      '/admin/leaderboard-seasons',
      requireAuth: true,
      bypassCache: true,
    );
    if (response is! Map || response['seasons'] is! List) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server returned an invalid season directory.',
        details: response,
      );
    }
    return (response['seasons'] as List)
        .whereType<Map>()
        .map(
          (season) =>
              LeaderboardSeason.fromMap(Map<String, dynamic>.from(season)),
        )
        .toList(growable: false);
  }

  Future<LeaderboardSeason> saveAdminLeaderboardSeason({
    required String id,
    required String displayName,
    required DateTime startsAt,
    required DateTime endsAt,
    required String reason,
    required bool create,
  }) async {
    final encodedId = Uri.encodeComponent(id.trim());
    final body = <String, dynamic>{
      if (create) 'id': id.trim(),
      'displayName': displayName.trim(),
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt.toUtc().toIso8601String(),
      'reason': reason.trim(),
    };
    final response = create
        ? await api.post(
            '/admin/leaderboard-seasons',
            body: body,
            requireAuth: true,
          )
        : await api.put(
            '/admin/leaderboard-seasons/$encodedId',
            body: body,
            requireAuth: true,
          );
    if (response is! Map || response['season'] is! Map) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server did not confirm the season update.',
        details: response,
      );
    }
    return LeaderboardSeason.fromMap(
      Map<String, dynamic>.from(response['season'] as Map),
    );
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

  Future<Map<String, dynamic>> createNotificationBroadcast({
    required String title,
    required String body,
    required String idempotencyKey,
    String? imageUrl,
    DateTime? scheduledAt,
  }) async {
    final result = await api.post(
      '/admin/notifications/broadcast',
      body: <String, dynamic>{
        'title': title.trim(),
        'body': body.trim(),
        'idempotencyKey': idempotencyKey,
        'category': 'general',
        'targetAudience': 'all',
        'data': const <String, String>{'route': '/home'},
        if (imageUrl != null && imageUrl.trim().isNotEmpty)
          'imageUrl': imageUrl.trim(),
        if (scheduledAt != null)
          'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      },
      requireAuth: true,
    );
    if (result is! Map) {
      throw AbuApiException(
        statusCode: 502,
        message: 'The server did not confirm the notification campaign.',
        details: result,
      );
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<ExclusiveVideo>> fetchExclusiveVideos({
    bool managed = false,
    bool forceRefresh = false,
  }) async {
    final res = await api.get(
      managed ? '/admin/videos' : '/videos/exclusive',
      // The fan feed is account-specific because Gold-only links are redacted
      // by the server for non-members.
      requireAuth: true,
      bypassCache: forceRefresh,
    );
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
