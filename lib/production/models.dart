import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
  String text =>
    DateTime.tryParse(text)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  _ => DateTime.fromMillisecondsSinceEpoch(0),
};

DateTime? _optionalDate(Object? value) => value == null ? null : _date(value);

String footballSeasonId(DateTime value) {
  final utc = value.toUtc();
  final startYear = utc.month >= DateTime.july ? utc.year : utc.year - 1;
  return '$startYear-${startYear + 1}';
}

class AbuUserProfile {
  const AbuUserProfile({
    required this.uid,
    required this.email,
    required this.username,
    required this.displayName,
    required this.country,
    required this.supportedTeam,
    required this.avatarUrl,
    required this.role,
    required this.membershipMultiplier,
    required this.totalPoints,
    required this.monthlyPoints,
    required this.seasonPoints,
    required this.suspended,
    this.supportedTeamLogo = '',
    this.countryCode = '',
    this.loyaltyPoints = 0,
    this.monthlyPeriod = '',
    this.seasonId = '',
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.level = 1,
    this.exactPredictions = 0,
    this.challengesCompleted = 0,
    this.playerCardsCollected = 0,
    this.lastCheckInDate = '',
    this.lastActivityAt,
    this.onboardingCompleted,
  });

  final String uid;
  final String email;
  final String username;
  final String displayName;
  final String country;
  final String countryCode;
  final String supportedTeam;
  final String supportedTeamLogo;
  final String avatarUrl;
  final String role;
  final double membershipMultiplier;
  final int totalPoints;
  final int monthlyPoints;
  final int seasonPoints;
  final int loyaltyPoints;
  final String monthlyPeriod;
  final String seasonId;
  final bool suspended;
  final int currentStreak;
  final int longestStreak;
  final int level;
  final int exactPredictions;
  final int challengesCompleted;
  final int playerCardsCollected;
  final String lastCheckInDate;
  final DateTime? lastActivityAt;

  /// Explicit PostgreSQL onboarding state. Legacy Firestore-only profiles do
  /// not have this field, so `null` deliberately falls back to field inference.
  final bool? onboardingCompleted;

  bool get isGuest => uid.isEmpty || uid == 'guest';
  bool get onboardingComplete =>
      isGuest ||
      (onboardingCompleted ??
          (username.isNotEmpty &&
              displayName.isNotEmpty &&
              country.isNotEmpty &&
              supportedTeam.isNotEmpty));
  bool get isAdmin => !isGuest && (role == 'admin' || role == 'superAdmin');
  bool get canManageContent =>
      isAdmin || role == 'editor' || role == 'contentManager';
  bool get canModerate => isAdmin || role == 'moderator';
  bool get canManageRoles => isAdmin;
  bool get isYouTubeMember => membershipMultiplier > 1;
  String get countryFlag {
    final c = countryCode.trim().isNotEmpty
        ? countryCode.trim().toLowerCase()
        : country.trim().toLowerCase();
    if (c.contains('saudi') || c == 'sa') return '🇸🇦';
    if (c.contains('egypt') || c == 'eg') return '🇪🇬';
    if (c.contains('emirates') || c.contains('uae') || c == 'ae') return '🇦🇪';
    if (c.contains('kuwait') || c == 'kw') return '🇰🇼';
    if (c.contains('qatar') || c == 'qa') return '🇶🇦';
    if (c.contains('jordan') || c == 'jo') return '🇯🇴';
    if (c.contains('iraq') || c == 'iq') return '🇮🇶';
    if (c.contains('morocco') || c == 'ma') return '🇲🇦';
    if (c.contains('algeria') || c == 'dz') return '🇩🇿';
    if (c.contains('tunisia') || c == 'tn') return '🇹🇳';
    if (c.contains('oman') || c == 'om') return '🇴🇲';
    if (c.contains('bahrain') || c == 'bh') return '🇧🇭';
    if (c.contains('lebanon') || c == 'lb') return '🇱🇧';
    if (c.contains('palestine') || c == 'ps') return '🇵🇸';
    if (c.contains('sudan') || c == 'sd') return '🇸🇩';
    if (c.contains('libya') || c == 'ly') return '🇱🇾';
    if (c.contains('yemen') || c == 'ye') return '🇾🇪';
    if (c.contains('syria') || c == 'sy') return '🇸🇾';
    if (c.contains('spain') || c == 'es') return '🇪🇸';
    if (c.contains('sweden') || c == 'se') return '🇸🇪';
    if (c.contains('united kingdom') || c.contains('uk') || c == 'gb') {
      return '🇬🇧';
    }
    if (c.contains('united states') || c.contains('usa') || c == 'us') {
      return '🇺🇸';
    }
    if (c.contains('germany') || c == 'de') return '🇩🇪';
    if (c.contains('france') || c == 'fr') return '🇫🇷';
    if (c.contains('italy') || c == 'it') return '🇮🇹';
    if (c.contains('brazil') || c == 'br') return '🇧🇷';
    if (c.contains('argentina') || c == 'ar') return '🇦🇷';
    if (c.contains('turkey') || c == 'tr') return '🇹🇷';
    return '🌍';
  }

  factory AbuUserProfile.guest() => const AbuUserProfile(
    uid: 'guest',
    email: '',
    username: 'guest',
    displayName: 'Guest Visitor',
    country: '',
    supportedTeam: 'Barcelona',
    avatarUrl: '',
    role: 'guest',
    membershipMultiplier: 1.0,
    totalPoints: 0,
    monthlyPoints: 0,
    seasonPoints: 0,
    loyaltyPoints: 0,
    suspended: false,
    currentStreak: 0,
    longestStreak: 0,
    lastCheckInDate: '',
  );

  AbuUserProfile copyWith({
    String? email,
    String? username,
    String? displayName,
    String? country,
    String? countryCode,
    String? supportedTeam,
    String? supportedTeamLogo,
    String? avatarUrl,
    String? role,
    int? totalPoints,
    int? monthlyPoints,
    int? seasonPoints,
    int? loyaltyPoints,
    double? membershipMultiplier,
    String? monthlyPeriod,
    String? seasonId,
    bool? suspended,
    int? currentStreak,
    int? longestStreak,
    int? level,
    int? exactPredictions,
    int? challengesCompleted,
    int? playerCardsCollected,
    String? lastCheckInDate,
    DateTime? lastActivityAt,
    bool? onboardingCompleted,
  }) => AbuUserProfile(
    uid: uid,
    email: email ?? this.email,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    country: country ?? this.country,
    countryCode: countryCode ?? this.countryCode,
    supportedTeam: supportedTeam ?? this.supportedTeam,
    supportedTeamLogo: supportedTeamLogo ?? this.supportedTeamLogo,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    role: role ?? this.role,
    membershipMultiplier: membershipMultiplier ?? this.membershipMultiplier,
    totalPoints: totalPoints ?? this.totalPoints,
    monthlyPoints: monthlyPoints ?? this.monthlyPoints,
    seasonPoints: seasonPoints ?? this.seasonPoints,
    loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
    monthlyPeriod: monthlyPeriod ?? this.monthlyPeriod,
    seasonId: seasonId ?? this.seasonId,
    suspended: suspended ?? this.suspended,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    level: level ?? this.level,
    exactPredictions: exactPredictions ?? this.exactPredictions,
    challengesCompleted: challengesCompleted ?? this.challengesCompleted,
    playerCardsCollected: playerCardsCollected ?? this.playerCardsCollected,
    lastCheckInDate: lastCheckInDate ?? this.lastCheckInDate,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
  );

  factory AbuUserProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuUserProfile(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      country: data['country'] as String? ?? '',
      countryCode: data['countryCode'] as String? ?? '',
      supportedTeam: data['supportedTeam'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      role: data['role'] as String? ?? 'user',
      membershipMultiplier: (data['membershipMultiplier'] as num? ?? 1)
          .toDouble(),
      totalPoints: (data['totalPoints'] as num? ?? 0).toInt(),
      monthlyPoints: (data['monthlyPoints'] as num? ?? 0).toInt(),
      seasonPoints: (data['seasonPoints'] as num? ?? 0).toInt(),
      loyaltyPoints:
          (data['loyaltyPoints'] as num? ?? data['seasonPoints'] as num? ?? 0)
              .toInt(),
      monthlyPeriod: data['monthlyPeriod'] as String? ?? '',
      seasonId: data['seasonId'] as String? ?? '',
      suspended: data['suspended'] as bool? ?? false,
      currentStreak: (data['currentStreak'] as num? ?? 0).toInt(),
      longestStreak: (data['longestStreak'] as num? ?? 0).toInt(),
      lastCheckInDate: data['lastCheckInDate'] as String? ?? '',
      lastActivityAt: _optionalDate(data['lastActivityAt']),
      onboardingCompleted: data['onboardingCompleted'] as bool?,
    );
  }
}

class AbuChallengeQuestion {
  const AbuChallengeQuestion({
    required this.id,
    required this.prompt,
    required this.type,
    this.options = const <String>[],
    this.correctAnswer = '',
    this.acceptedAnswers = const <String>[],
  });

  final String id;
  final String prompt;
  final String type;
  final List<String> options;

  /// Admin-only. Public challenge documents never contain answer keys.
  final String correctAnswer;
  final List<String> acceptedAnswers;

  factory AbuChallengeQuestion.fromMap(Map<String, dynamic> data) {
    final accepted = (data['acceptedAnswers'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return AbuChallengeQuestion(
      id: data['id'] as String? ?? 'main',
      prompt: data['prompt'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      options: (data['options'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      correctAnswer: data['correctAnswer'] as String? ?? '',
      acceptedAnswers: accepted,
    );
  }

  Map<String, dynamic> toPublicMap() => {
    'id': id,
    'prompt': prompt.trim(),
    'type': type,
    'options': options.map((value) => value.trim()).toList(),
  };

  Map<String, dynamic> toPrivateMap() => {
    'id': id,
    'type': type,
    'acceptedAnswers': <String>{
      ...acceptedAnswers,
      if (correctAnswer.trim().isNotEmpty) correctAnswer.trim(),
    }.toList(),
  };

  AbuChallengeQuestion copyWithPrivate(Map<String, dynamic> data) {
    final privateQuestion = AbuChallengeQuestion.fromMap(data);
    return AbuChallengeQuestion(
      id: id,
      prompt: prompt,
      type: type,
      options: options,
      correctAnswer: privateQuestion.acceptedAnswers.isNotEmpty
          ? privateQuestion.acceptedAnswers.first
          : privateQuestion.correctAnswer,
      acceptedAnswers: privateQuestion.acceptedAnswers,
    );
  }
}

class AbuChallenge {
  const AbuChallenge({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.rewardPoints,
    required this.status,
    required this.videoUrl,
    required this.availableFrom,
    required this.availableUntil,
    this.questions = const <AbuChallengeQuestion>[],
    this.maximumAttempts = 5,
    this.attemptsUsed = 0,
    this.memberOnly = false,
    this.notifyOnLive = false,
    this.imageUrl = '',
  });

  final String id;
  final String kind;
  final String title;
  final String description;
  final int rewardPoints;
  final String status;
  final String videoUrl;
  final DateTime availableFrom;
  final DateTime availableUntil;
  final List<AbuChallengeQuestion> questions;
  final int maximumAttempts;
  final int attemptsUsed;
  final bool memberOnly;
  final bool notifyOnLive;
  final String imageUrl;

  String get canonicalKind => switch (kind) {
    'videoQuestion' => 'videoPhrase',
    'quiz' => 'multiQuestion',
    _ => kind,
  };

  int get attemptsRemaining =>
      (maximumAttempts - attemptsUsed).clamp(0, maximumAttempts);

  bool get isOpen {
    final now = DateTime.now();
    return const ['open', 'live', 'scheduled'].contains(status) &&
        !now.isBefore(availableFrom) &&
        now.isBefore(availableUntil);
  }

  factory AbuChallenge.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String kind,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuChallenge(
      id: doc.id,
      kind: data['challengeType'] as String? ?? data['kind'] as String? ?? kind,
      title:
          data['title'] as String? ??
          (kind == 'playerCard' ? 'Find the Player Card' : 'Secret phrase'),
      description: data['description'] as String? ?? '',
      rewardPoints: (data['rewardPoints'] as num? ?? 0).toInt(),
      status: data['status'] as String? ?? 'draft',
      videoUrl: data['videoUrl'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      maximumAttempts: (data['maximumAttempts'] as num? ?? 5).toInt(),
      attemptsUsed: (data['attemptsUsed'] as num? ?? 0).toInt(),
      memberOnly: data['memberOnly'] as bool? ?? false,
      notifyOnLive: data['notifyOnLive'] as bool? ?? false,
      questions: (data['questions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                AbuChallengeQuestion.fromMap(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
      availableFrom: _date(data['availableFrom']),
      availableUntil: _date(data['availableUntil']),
    );
  }

  factory AbuChallenge.fromMap(Map<String, dynamic> data) {
    return AbuChallenge(
      id: (data['id'] ?? '').toString(),
      kind: (data['kind'] ?? 'videoPhrase').toString(),
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      rewardPoints:
          (data['rewardPoints'] as num? ?? data['reward_points'] as num? ?? 0)
              .toInt(),
      status: (data['status'] ?? 'draft').toString(),
      videoUrl: (data['videoUrl'] ?? data['video_url'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      maximumAttempts:
          (data['maximumAttempts'] as num? ??
                  data['maximum_attempts'] as num? ??
                  3)
              .toInt(),
      attemptsUsed:
          (data['attemptsUsed'] as num? ?? data['attempts_used'] as num? ?? 0)
              .toInt(),
      memberOnly:
          data['memberOnly'] as bool? ?? data['member_only'] as bool? ?? false,
      notifyOnLive:
          data['notifyOnLive'] as bool? ??
          data['notify_on_live'] as bool? ??
          false,
      questions: (data['questions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                AbuChallengeQuestion.fromMap(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
      availableFrom: _date(data['availableFrom'] ?? data['starts_at']),
      availableUntil: _date(data['availableUntil'] ?? data['ends_at']),
    );
  }

  AbuChallenge copyWith({
    List<AbuChallengeQuestion>? questions,
    int? attemptsUsed,
  }) => AbuChallenge(
    id: id,
    kind: kind,
    title: title,
    description: description,
    rewardPoints: rewardPoints,
    status: status,
    videoUrl: videoUrl,
    imageUrl: imageUrl,
    availableFrom: availableFrom,
    availableUntil: availableUntil,
    questions: questions ?? this.questions,
    maximumAttempts: maximumAttempts,
    attemptsUsed: attemptsUsed ?? this.attemptsUsed,
    memberOnly: memberOnly,
    notifyOnLive: notifyOnLive,
  );
}

class AbuPost {
  const AbuPost({
    required this.id,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.linkUrl,
    required this.authorName,
    required this.publishedAt,
    this.likeCount = 0,
    this.authorId = '',
  });

  final String id;
  final String title;
  final String body;
  final String imageUrl;
  final String linkUrl;
  final String authorName;
  final DateTime publishedAt;
  final int likeCount;
  final String authorId;

  factory AbuPost.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuPost(
      id: doc.id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      linkUrl: data['linkUrl'] as String? ?? '',
      authorName: data['authorName'] as String? ?? 'Abu 3meer',
      publishedAt: _date(data['publishedAt']),
      likeCount:
          (data['likeCount'] as num? ??
                  data['likes'] as num? ??
                  data['reactionsCount'] as num? ??
                  0)
              .toInt(),
      authorId:
          data['authorId'] as String? ?? data['createdBy'] as String? ?? '',
    );
  }

  AbuPost copyWith({
    String? id,
    String? title,
    String? body,
    String? imageUrl,
    String? linkUrl,
    String? authorName,
    DateTime? publishedAt,
    int? likeCount,
    String? authorId,
  }) => AbuPost(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    imageUrl: imageUrl ?? this.imageUrl,
    linkUrl: linkUrl ?? this.linkUrl,
    authorName: authorName ?? this.authorName,
    publishedAt: publishedAt ?? this.publishedAt,
    likeCount: likeCount ?? this.likeCount,
    authorId: authorId ?? this.authorId,
  );
}

class AbuComment {
  const AbuComment({
    required this.id,
    required this.userName,
    required this.body,
    required this.createdAt,
    this.userId = '',
  });

  final String id;
  final String userName;
  final String body;
  final DateTime createdAt;
  final String userId;

  factory AbuComment.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuComment(
      id: doc.id,
      userName: data['userName'] as String? ?? 'Fan',
      body: data['body'] as String? ?? '',
      createdAt: _date(data['createdAt']),
      userId: data['userId'] as String? ?? '',
    );
  }
}

class LaunchAnnouncement {
  const LaunchAnnouncement({
    required this.enabled,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.linkUrl,
    required this.buttonLabel,
    required this.revision,
    required this.frequency,
    required this.startsAt,
    required this.endsAt,
  });

  final bool enabled;
  final String title;
  final String body;
  final String imageUrl;
  final String linkUrl;
  final String buttonLabel;
  final int revision;
  final String frequency;
  final DateTime startsAt;
  final DateTime endsAt;

  bool get isActive {
    final now = DateTime.now();
    return enabled && !now.isBefore(startsAt) && now.isBefore(endsAt);
  }

  factory LaunchAnnouncement.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return LaunchAnnouncement(
      enabled: data['enabled'] as bool? ?? false,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      linkUrl: data['linkUrl'] as String? ?? '',
      buttonLabel: data['buttonLabel'] as String? ?? 'OPEN',
      revision: (data['revision'] as num? ?? 0).toInt(),
      frequency: data['frequency'] as String? ?? 'once',
      startsAt: data['startsAt'] == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : _date(data['startsAt']),
      endsAt: data['endsAt'] == null
          ? DateTime.now().add(const Duration(days: 3650))
          : _date(data['endsAt']),
    );
  }

  factory LaunchAnnouncement.fromMap(Map<String, dynamic> data) {
    return LaunchAnnouncement(
      enabled: data['enabled'] as bool? ?? false,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? data['image_url'] ?? '').toString(),
      linkUrl: (data['linkUrl'] ?? data['link_url'] ?? '').toString(),
      buttonLabel: (data['buttonLabel'] ?? data['button_label'] ?? 'OPEN')
          .toString(),
      revision: (data['revision'] as num? ?? 0).toInt(),
      frequency: (data['frequency'] ?? 'once').toString(),
      startsAt: _date(data['startsAt'] ?? data['starts_at']),
      endsAt: _date(data['endsAt'] ?? data['ends_at']),
    );
  }
}

class FanDuel {
  const FanDuel({
    required this.code,
    required this.hostUid,
    required this.hostName,
    required this.guestUid,
    required this.guestName,
    required this.status,
    required this.startAt,
  });

  final String code;
  final String hostUid;
  final String hostName;
  final String guestUid;
  final String guestName;
  final String status;
  final DateTime? startAt;

  factory FanDuel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawStart = data['startAt'];
    return FanDuel(
      code: doc.id,
      hostUid: data['hostUid'] as String? ?? '',
      hostName: data['hostName'] as String? ?? '',
      guestUid: data['guestUid'] as String? ?? '',
      guestName: data['guestName'] as String? ?? '',
      status: data['status'] as String? ?? 'waiting',
      startAt: rawStart == null ? null : _date(rawStart),
    );
  }
}

class MatchTimelineEvent {
  const MatchTimelineEvent({
    required this.minute,
    required this.type,
    required this.player,
    this.assist = '',
    this.detail = '',
    this.team = '',
    this.isHome = true,
  });

  final String minute;
  final String type;
  final String player;
  final String assist;
  final String detail;
  final String team;
  final bool isHome;

  factory MatchTimelineEvent.fromMap(Map<String, dynamic> map) =>
      MatchTimelineEvent(
        minute: map['minute']?.toString() ?? '',
        type: map['type']?.toString() ?? 'Goal',
        player: map['player']?.toString() ?? '',
        assist: map['assist']?.toString() ?? '',
        detail: (map['detail'] ?? map['comment'])?.toString() ?? '',
        team: map['team']?.toString() ?? '',
        isHome:
            map['isHome'] == true ||
            map['is_home'] == true ||
            map['isHome']?.toString().toLowerCase() == 'yes',
      );

  Map<String, dynamic> toMap() => {
    'minute': minute,
    'type': type,
    'player': player,
    'assist': assist,
    'detail': detail,
    'team': team,
    'isHome': isHome,
  };
}

class MatchLineupPlayer {
  const MatchLineupPlayer({
    required this.player,
    required this.team,
    required this.position,
    required this.isHome,
    required this.isSubstitute,
    this.squadNumber = '',
    this.playerImageUrl = '',
  });

  final String player;
  final String team;
  final String position;
  final bool isHome;
  final bool isSubstitute;
  final String squadNumber;
  final String playerImageUrl;

  factory MatchLineupPlayer.fromMap(
    Map<String, dynamic> map,
  ) => MatchLineupPlayer(
    player: map['player']?.toString() ?? '',
    team: map['team']?.toString() ?? '',
    position: map['position']?.toString() ?? '',
    isHome:
        map['isHome'] == true ||
        map['is_home'] == true ||
        map['isHome']?.toString().toLowerCase() == 'yes',
    isSubstitute:
        map['isSubstitute'] == true ||
        map['is_substitute'] == true ||
        map['isSubstitute']?.toString().toLowerCase() == 'yes',
    squadNumber: (map['squadNumber'] ?? map['squad_number'])?.toString() ?? '',
    playerImageUrl:
        (map['playerImageUrl'] ?? map['player_image_url'])?.toString() ?? '',
  );
}

class MatchStatistic {
  const MatchStatistic({
    required this.label,
    required this.homeValue,
    required this.awayValue,
  });

  final String label;
  final String homeValue;
  final String awayValue;

  factory MatchStatistic.fromMap(Map<String, dynamic> map) => MatchStatistic(
    label: (map['label'] ?? map['stat'])?.toString() ?? '',
    homeValue: (map['homeValue'] ?? map['home_value'])?.toString() ?? '',
    awayValue: (map['awayValue'] ?? map['away_value'])?.toString() ?? '',
  );

  double? get homeNumber =>
      double.tryParse(homeValue.replaceAll(RegExp(r'[^0-9.-]'), ''));
  double? get awayNumber =>
      double.tryParse(awayValue.replaceAll(RegExp(r'[^0-9.-]'), ''));
}

class MatchStanding {
  const MatchStanding({
    required this.rank,
    required this.team,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalDifference,
    required this.points,
    this.goalsFor,
    this.goalsAgainst,
    this.teamId = '',
    this.badgeUrl = '',
    this.form = '',
  });

  final int rank;
  final String team;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalDifference;
  final int points;
  final int? goalsFor;
  final int? goalsAgainst;
  final String teamId;
  final String badgeUrl;
  final String form;

  factory MatchStanding.fromMap(Map<String, dynamic> map) => MatchStanding(
    rank: int.tryParse(map['rank']?.toString() ?? '') ?? 0,
    team: map['team']?.toString() ?? '',
    played: int.tryParse(map['played']?.toString() ?? '') ?? 0,
    won: int.tryParse(map['won']?.toString() ?? '') ?? 0,
    drawn: int.tryParse(map['drawn']?.toString() ?? '') ?? 0,
    lost: int.tryParse(map['lost']?.toString() ?? '') ?? 0,
    goalDifference:
        int.tryParse(
          (map['goalDifference'] ?? map['goal_difference'])?.toString() ?? '',
        ) ??
        0,
    points: int.tryParse(map['points']?.toString() ?? '') ?? 0,
    goalsFor: int.tryParse(
      (map['goalsFor'] ?? map['goals_for'])?.toString() ?? '',
    ),
    goalsAgainst: int.tryParse(
      (map['goalsAgainst'] ?? map['goals_against'])?.toString() ?? '',
    ),
    teamId: (map['teamId'] ?? map['team_id'])?.toString() ?? '',
    badgeUrl: (map['badgeUrl'] ?? map['badge_url'])?.toString() ?? '',
    form: map['form']?.toString() ?? '',
  );
}

/// All provider-backed information shown inside the match facts screen.
///
/// Empty collections mean the provider has not published that section. They
/// must never be replaced by invented scorers, cards, players, or statistics.
class MatchDetails {
  const MatchDetails({
    this.timeline = const <MatchTimelineEvent>[],
    this.lineup = const <MatchLineupPlayer>[],
    this.statistics = const <MatchStatistic>[],
    this.standings = const <MatchStanding>[],
    this.venue = '',
    this.season = '',
    this.provider = '',
    this.isProviderLimited = false,
    this.status = '',
    this.homeScore,
    this.awayScore,
  });

  final List<MatchTimelineEvent> timeline;
  final List<MatchLineupPlayer> lineup;
  final List<MatchStatistic> statistics;
  final List<MatchStanding> standings;
  final String venue;
  final String season;
  final String provider;
  final String status;
  final int? homeScore;
  final int? awayScore;

  /// TheSportsDB's public key deliberately caps timeline, lineup, statistics,
  /// and league-table responses at five records.
  final bool isProviderLimited;

  bool get isEmpty =>
      timeline.isEmpty &&
      lineup.isEmpty &&
      statistics.isEmpty &&
      standings.isEmpty;

  MatchDetails copyWith({
    List<MatchTimelineEvent>? timeline,
    List<MatchLineupPlayer>? lineup,
    List<MatchStatistic>? statistics,
    List<MatchStanding>? standings,
    String? venue,
    String? season,
    String? provider,
    bool? isProviderLimited,
    String? status,
    int? homeScore,
    int? awayScore,
  }) => MatchDetails(
    timeline: timeline ?? this.timeline,
    lineup: lineup ?? this.lineup,
    statistics: statistics ?? this.statistics,
    standings: standings ?? this.standings,
    venue: venue ?? this.venue,
    season: season ?? this.season,
    provider: provider ?? this.provider,
    isProviderLimited: isProviderLimited ?? this.isProviderLimited,
    status: status ?? this.status,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
  );

  factory MatchDetails.fromMap(Map<String, dynamic> map) => MatchDetails(
    timeline: (map['timeline'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              MatchTimelineEvent.fromMap(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false),
    lineup: (map['lineup'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              MatchLineupPlayer.fromMap(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false),
    statistics: (map['statistics'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (value) => MatchStatistic.fromMap(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false),
    standings: (map['standings'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) => MatchStanding.fromMap(Map<String, dynamic>.from(value)))
        .toList(growable: false),
    venue: map['venue']?.toString() ?? '',
    season: map['season']?.toString() ?? '',
    provider: map['provider']?.toString() ?? '',
    status: map['status']?.toString() ?? '',
    homeScore: ((map['homeScore'] ?? map['home_score']) as num?)?.toInt(),
    awayScore: ((map['awayScore'] ?? map['away_score']) as num?)?.toInt(),
    isProviderLimited: map['isProviderLimited'] == true,
  );
}

class MatchEvent {
  const MatchEvent({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.kickoffAt,
    required this.predictionOpensAt,
    required this.predictionClosesAt,
    required this.status,
    this.providerMatchId = '',
    this.homeTeamId = '',
    this.awayTeamId = '',
    this.homeLogoUrl = '',
    this.awayLogoUrl = '',
    this.homeScore,
    this.awayScore,
    this.firstScorerOptions = const <String>[],
    this.firstScorer = '',
    this.timeline = const <MatchTimelineEvent>[],
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final DateTime kickoffAt;
  final DateTime predictionOpensAt;
  final DateTime predictionClosesAt;
  final String status;

  /// Fixture identity used by the shared football-data provider.
  ///
  /// A managed Abu 3meer match deliberately keeps its own [id] so saved
  /// predictions remain attached to the database row. When that row is
  /// merged with a provider fixture, this second identity lets the match
  /// centre load the provider's facts, lineup and league table.
  final String providerMatchId;
  final String homeTeamId;
  final String awayTeamId;
  final String homeLogoUrl;
  final String awayLogoUrl;
  final int? homeScore;
  final int? awayScore;
  final List<String> firstScorerOptions;
  final String firstScorer;
  final List<MatchTimelineEvent> timeline;

  factory MatchEvent.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MatchEvent(
      id: doc.id,
      homeTeam: data['homeTeam'] as String? ?? '',
      awayTeam: data['awayTeam'] as String? ?? '',
      competition: data['competition'] as String? ?? '',
      kickoffAt: _date(data['kickoffAt']),
      predictionOpensAt: _date(data['predictionOpensAt']),
      predictionClosesAt: _date(data['predictionClosesAt']),
      status: data['status'] as String? ?? 'draft',
      providerMatchId:
          (data['providerMatchId'] ?? data['provider_match_id'] ?? '')
              .toString(),
      homeTeamId: (data['homeTeamId'] ?? data['home_team_id'] ?? '').toString(),
      awayTeamId: (data['awayTeamId'] ?? data['away_team_id'] ?? '').toString(),
      homeLogoUrl: data['homeLogoUrl'] as String? ?? '',
      awayLogoUrl: data['awayLogoUrl'] as String? ?? '',
      homeScore: (data['homeScore'] as num?)?.toInt(),
      awayScore: (data['awayScore'] as num?)?.toInt(),
      firstScorerOptions:
          (data['firstScorerOptions'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
      firstScorer: data['firstScorer'] as String? ?? '',
      timeline: (data['timeline'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                MatchTimelineEvent.fromMap(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
    );
  }

  MatchEvent copyWith({
    String? id,
    String? homeTeam,
    String? awayTeam,
    String? competition,
    DateTime? kickoffAt,
    DateTime? predictionOpensAt,
    DateTime? predictionClosesAt,
    String? status,
    String? providerMatchId,
    String? homeTeamId,
    String? awayTeamId,
    String? homeLogoUrl,
    String? awayLogoUrl,
    int? homeScore,
    int? awayScore,
    List<String>? firstScorerOptions,
    String? firstScorer,
    List<MatchTimelineEvent>? timeline,
  }) => MatchEvent(
    id: id ?? this.id,
    homeTeam: homeTeam ?? this.homeTeam,
    awayTeam: awayTeam ?? this.awayTeam,
    competition: competition ?? this.competition,
    kickoffAt: kickoffAt ?? this.kickoffAt,
    predictionOpensAt: predictionOpensAt ?? this.predictionOpensAt,
    predictionClosesAt: predictionClosesAt ?? this.predictionClosesAt,
    status: status ?? this.status,
    providerMatchId: providerMatchId ?? this.providerMatchId,
    homeTeamId: homeTeamId ?? this.homeTeamId,
    awayTeamId: awayTeamId ?? this.awayTeamId,
    homeLogoUrl: homeLogoUrl ?? this.homeLogoUrl,
    awayLogoUrl: awayLogoUrl ?? this.awayLogoUrl,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
    firstScorerOptions: firstScorerOptions ?? this.firstScorerOptions,
    firstScorer: firstScorer ?? this.firstScorer,
    timeline: timeline ?? this.timeline,
  );
}

class SavedPrediction {
  const SavedPrediction({
    required this.id,
    required this.userId,
    required this.matchId,
    required this.homeScore,
    required this.awayScore,
    required this.firstScorer,
    required this.submittedAt,
    required this.updatedAt,
    required this.rewarded,
    this.pointsAwarded = 0,
    this.seenResult = false,
    this.exactMatchResult,
    this.firstScorerMatchResult,
    this.winnerMatchResult,
    this.homeTeam = '',
    this.awayTeam = '',
    this.match,
  });

  final String id;
  final String userId;
  final String matchId;
  final int homeScore;
  final int awayScore;
  final String firstScorer;
  final DateTime submittedAt;
  final DateTime updatedAt;
  final bool rewarded;
  final int pointsAwarded;
  final bool seenResult;
  final bool? exactMatchResult;
  final bool? firstScorerMatchResult;
  final bool? winnerMatchResult;
  final String homeTeam;
  final String awayTeam;
  final MatchEvent? match;

  /// Settlement is authoritative. A provider can publish a final score before
  /// the reward transaction has completed, so match status alone must never
  /// move a saved prediction out of the pending state.
  bool get isPending => !rewarded;
  bool get exactScoreCorrect =>
      exactMatchResult ??
      (!isPending &&
          match!.homeScore == homeScore &&
          match!.awayScore == awayScore);
  bool get firstScorerCorrect =>
      firstScorerMatchResult ??
      (!isPending &&
          match!.firstScorer.trim().toLowerCase() ==
              firstScorer.trim().toLowerCase());
  bool get winnerCorrect {
    if (winnerMatchResult case final persisted?) return persisted;
    if (isPending) return false;
    return homeScore.compareTo(awayScore) ==
        match!.homeScore!.compareTo(match!.awayScore!);
  }

  factory SavedPrediction.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    MatchEvent? match,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SavedPrediction(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      matchId: data['matchId'] as String? ?? '',
      homeScore: (data['homeScore'] as num? ?? 0).toInt(),
      awayScore: (data['awayScore'] as num? ?? 0).toInt(),
      firstScorer: data['firstScorer'] as String? ?? '',
      submittedAt: _date(data['submittedAt']),
      updatedAt: _date(data['updatedAt'] ?? data['submittedAt']),
      rewarded: data['rewarded'] as bool? ?? false,
      pointsAwarded: (data['pointsAwarded'] as num? ?? 0).toInt(),
      seenResult: data['seenResult'] as bool? ?? false,
      homeTeam: data['homeTeam'] as String? ?? '',
      awayTeam: data['awayTeam'] as String? ?? '',
      match: match,
    );
  }

  SavedPrediction copyWith({
    String? id,
    String? userId,
    String? matchId,
    int? homeScore,
    int? awayScore,
    String? firstScorer,
    DateTime? submittedAt,
    DateTime? updatedAt,
    bool? rewarded,
    int? pointsAwarded,
    bool? seenResult,
    bool? exactMatchResult,
    bool? firstScorerMatchResult,
    bool? winnerMatchResult,
    String? homeTeam,
    String? awayTeam,
    MatchEvent? match,
  }) => SavedPrediction(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    matchId: matchId ?? this.matchId,
    homeScore: homeScore ?? this.homeScore,
    awayScore: awayScore ?? this.awayScore,
    firstScorer: firstScorer ?? this.firstScorer,
    submittedAt: submittedAt ?? this.submittedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    rewarded: rewarded ?? this.rewarded,
    pointsAwarded: pointsAwarded ?? this.pointsAwarded,
    seenResult: seenResult ?? this.seenResult,
    exactMatchResult: exactMatchResult ?? this.exactMatchResult,
    firstScorerMatchResult:
        firstScorerMatchResult ?? this.firstScorerMatchResult,
    winnerMatchResult: winnerMatchResult ?? this.winnerMatchResult,
    homeTeam: homeTeam ?? this.homeTeam,
    awayTeam: awayTeam ?? this.awayTeam,
    match: match ?? this.match,
  );

  SavedPrediction withMatch(MatchEvent? value) => copyWith(match: value);
}

class PredictionOutcomeResult {
  const PredictionOutcomeResult({
    required this.event,
    required this.prediction,
    required this.exactMatch,
    required this.firstScorerMatch,
    required this.winnerMatch,
    required this.pointsEarned,
    required this.isPerfect,
    required this.hasSomeCorrect,
  });

  final MatchEvent event;
  final SavedPrediction prediction;
  final bool exactMatch;
  final bool firstScorerMatch;
  final bool winnerMatch;
  final int pointsEarned;
  final bool isPerfect;
  final bool hasSomeCorrect;
}

class PointLedgerEntry {
  const PointLedgerEntry({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.basePoints,
    required this.multiplier,
    required this.finalPoints,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String sourceType;
  final String sourceId;
  final int basePoints;
  final double multiplier;
  final int finalPoints;
  final String reason;
  final DateTime createdAt;

  factory PointLedgerEntry.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final points =
        (data['finalPoints'] as num? ??
                data['points'] as num? ??
                data['amount'] as num? ??
                data['pointsAwarded'] as num? ??
                data['basePoints'] as num? ??
                0)
            .toInt();
    final base =
        (data['basePoints'] as num? ??
                data['points'] as num? ??
                data['finalPoints'] as num? ??
                data['amount'] as num? ??
                0)
            .toInt();
    final type = data['sourceType'] as String? ?? data['type'] as String? ?? '';
    final desc =
        data['reason'] as String? ?? data['description'] as String? ?? '';
    return PointLedgerEntry(
      id: doc.id,
      sourceType: type,
      sourceId: data['sourceId'] as String? ?? '',
      basePoints: base,
      multiplier: (data['multiplier'] as num? ?? 1).toDouble(),
      finalPoints: points,
      reason: desc,
      createdAt: _date(data['createdAt']),
    );
  }
}

class AdminPointAdjustment {
  const AdminPointAdjustment({
    required this.id,
    required this.adminId,
    required this.adminDisplayName,
    required this.targetUserId,
    required this.targetDisplayName,
    required this.targetUsername,
    required this.delta,
    required this.reason,
    required this.totalBefore,
    required this.totalAfter,
    required this.monthlyBefore,
    required this.monthlyAfter,
    required this.seasonBefore,
    required this.seasonAfter,
    required this.periodFloorApplied,
    required this.monthlyRolledOver,
    required this.seasonRolledOver,
    required this.monthlyPeriod,
    required this.seasonId,
    required this.createdAt,
  });

  final String id;
  final String adminId;
  final String adminDisplayName;
  final String targetUserId;
  final String targetDisplayName;
  final String targetUsername;
  final int delta;
  final String reason;
  final int totalBefore;
  final int totalAfter;
  final int monthlyBefore;
  final int monthlyAfter;
  final int seasonBefore;
  final int seasonAfter;
  final bool periodFloorApplied;
  final bool monthlyRolledOver;
  final bool seasonRolledOver;
  final String monthlyPeriod;
  final String seasonId;
  final DateTime createdAt;

  factory AdminPointAdjustment.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AdminPointAdjustment(
      id: doc.id,
      adminId: data['adminId'] as String? ?? '',
      adminDisplayName: data['adminDisplayName'] as String? ?? '',
      targetUserId: data['targetUserId'] as String? ?? '',
      targetDisplayName: data['targetDisplayName'] as String? ?? '',
      targetUsername: data['targetUsername'] as String? ?? '',
      delta: (data['delta'] as num? ?? 0).toInt(),
      reason: data['reason'] as String? ?? '',
      totalBefore: (data['totalBefore'] as num? ?? 0).toInt(),
      totalAfter: (data['totalAfter'] as num? ?? 0).toInt(),
      monthlyBefore: (data['monthlyBefore'] as num? ?? 0).toInt(),
      monthlyAfter: (data['monthlyAfter'] as num? ?? 0).toInt(),
      seasonBefore: (data['seasonBefore'] as num? ?? 0).toInt(),
      seasonAfter: (data['seasonAfter'] as num? ?? 0).toInt(),
      periodFloorApplied: data['periodFloorApplied'] as bool? ?? false,
      monthlyRolledOver: data['monthlyRolledOver'] as bool? ?? false,
      seasonRolledOver: data['seasonRolledOver'] as bool? ?? false,
      monthlyPeriod: data['monthlyPeriod'] as String? ?? '',
      seasonId: data['seasonId'] as String? ?? '',
      createdAt: _date(data['createdAt']),
    );
  }
}

class AdminPointAdjustmentResult {
  const AdminPointAdjustmentResult({
    required this.adjustmentId,
    required this.targetUserId,
    required this.delta,
    required this.totalPoints,
    required this.monthlyPoints,
    required this.seasonPoints,
    required this.duplicate,
    required this.periodFloorApplied,
  });

  final String adjustmentId;
  final String targetUserId;
  final int delta;
  final int totalPoints;
  final int monthlyPoints;
  final int seasonPoints;
  final bool duplicate;
  final bool periodFloorApplied;

  factory AdminPointAdjustmentResult.fromMap(Map<String, dynamic> data) =>
      AdminPointAdjustmentResult(
        adjustmentId: data['adjustmentId'] as String? ?? '',
        targetUserId: data['targetUserId'] as String? ?? '',
        delta: (data['delta'] as num? ?? 0).toInt(),
        totalPoints: (data['totalPoints'] as num? ?? 0).toInt(),
        monthlyPoints: (data['monthlyPoints'] as num? ?? 0).toInt(),
        seasonPoints: (data['seasonPoints'] as num? ?? 0).toInt(),
        duplicate: data['duplicate'] as bool? ?? false,
        periodFloorApplied: data['periodFloorApplied'] as bool? ?? false,
      );
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.username,
    required this.avatarUrl,
    required this.supportedTeam,
    required this.monthlyPoints,
    required this.seasonPoints,
    required this.isMember,
    this.displayName = '',
    this.totalPoints = 0,
    this.monthlyPeriod = '',
    this.seasonId = '',
  });

  final String uid;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String supportedTeam;
  final int monthlyPoints;
  final int seasonPoints;
  final bool isMember;
  final int totalPoints;
  final String monthlyPeriod;
  final String seasonId;

  factory LeaderboardEntry.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final u = data['username'] as String? ?? '';
    return LeaderboardEntry(
      uid: doc.id,
      username: u,
      displayName: data['displayName'] as String? ?? u,
      avatarUrl: data['avatarUrl'] as String? ?? '',
      supportedTeam: data['supportedTeam'] as String? ?? '',
      monthlyPoints: (data['monthlyPoints'] as num? ?? 0).toInt(),
      seasonPoints: (data['seasonPoints'] as num? ?? 0).toInt(),
      isMember: data['isMember'] as bool? ?? false,
      totalPoints:
          (data['totalPoints'] as num? ?? data['seasonPoints'] as num? ?? 0)
              .toInt(),
      monthlyPeriod: data['monthlyPeriod'] as String? ?? '',
      seasonId: data['seasonId'] as String? ?? '',
    );
  }
}

enum LeaderboardPeriod { monthly, season, allTime }

class LeaderboardSeason {
  const LeaderboardSeason({
    required this.id,
    required this.displayName,
    this.startsAt,
    this.endsAt,
    this.active = false,
  });

  final String id;
  final String displayName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool active;

  factory LeaderboardSeason.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return LeaderboardSeason(
      id: doc.id,
      displayName: data['displayName'] as String? ?? doc.id,
      startsAt: _optionalDate(data['startsAt']),
      endsAt: _optionalDate(data['endsAt']),
      active: data['active'] as bool? ?? false,
    );
  }
}

class RankedLeaderboardEntry {
  const RankedLeaderboardEntry({
    required this.entry,
    required this.rank,
    required this.points,
  });

  final LeaderboardEntry entry;
  final int rank;
  final int points;
}

class LeaderboardSnapshot {
  const LeaderboardSnapshot({
    required this.entries,
    required this.currentUser,
    required this.totalPlayers,
    required this.seasons,
    required this.activeSeasonId,
  });

  final List<RankedLeaderboardEntry> entries;
  final RankedLeaderboardEntry? currentUser;
  final int totalPlayers;
  final List<LeaderboardSeason> seasons;
  final String? activeSeasonId;
}

class AbuAchievement {
  const AbuAchievement({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.description,
    required this.descriptionAr,
    required this.iconName,
    required this.category,
    required this.requirementType,
    required this.requirementTarget,
    required this.rewardPoints,
    required this.levelUnlock,
    required this.isSecret,
    required this.enabled,
    required this.sortOrder,
  });

  final String id;
  final String title;
  final String titleAr;
  final String description;
  final String descriptionAr;
  final String iconName;
  final String category;
  final String requirementType;
  final int requirementTarget;
  final int rewardPoints;
  final String levelUnlock;
  final bool isSecret;
  final bool enabled;
  final int sortOrder;

  AbuLevel? enabledUnlockLevel(Iterable<AbuLevel> levels) {
    final requiredLevelId = levelUnlock.trim();
    if (requiredLevelId.isEmpty) return null;
    for (final level in levels) {
      if (level.enabled && level.id == requiredLevelId) return level;
    }
    return null;
  }

  bool meetsLevelUnlock({
    required Iterable<AbuLevel> levels,
    required int totalPoints,
  }) {
    if (levelUnlock.trim().isEmpty) return true;
    final requiredLevel = enabledUnlockLevel(levels);
    return requiredLevel != null && totalPoints >= requiredLevel.minimumPoints;
  }

  factory AbuAchievement.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuAchievement(
      id: doc.id,
      title: data['title'] as String? ?? '',
      titleAr: data['titleAr'] as String? ?? '',
      description: data['description'] as String? ?? '',
      descriptionAr: data['descriptionAr'] as String? ?? '',
      iconName: data['iconName'] as String? ?? 'emoji_events',
      category: data['category'] as String? ?? 'points',
      requirementType: data['requirementType'] as String? ?? 'totalPoints',
      requirementTarget: (data['requirementTarget'] as num? ?? 0).toInt(),
      rewardPoints: (data['rewardPoints'] as num? ?? 0).toInt(),
      levelUnlock: data['levelUnlock'] as String? ?? '',
      isSecret: data['isSecret'] as bool? ?? false,
      enabled: data['enabled'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title.trim(),
    'titleAr': titleAr.trim(),
    'description': description.trim(),
    'descriptionAr': descriptionAr.trim(),
    'iconName': iconName,
    'category': category,
    'requirementType': requirementType,
    'requirementTarget': requirementTarget,
    'rewardPoints': rewardPoints,
    'levelUnlock': levelUnlock.trim(),
    'isSecret': isSecret,
    'enabled': enabled,
    'sortOrder': sortOrder,
  };
}

class AbuAchievementProgress {
  const AbuAchievementProgress({
    required this.achievement,
    required this.achievementId,
    required this.current,
    required this.target,
    required this.unlocked,
    this.unlockedAt,
  });

  final AbuAchievement achievement;
  final String achievementId;
  final int current;
  final int target;
  final bool unlocked;
  final DateTime? unlockedAt;

  double get fraction => target <= 0 ? 1 : (current / target).clamp(0, 1);
}

class AbuLevel {
  const AbuLevel({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.minimumPoints,
    this.maximumPoints,
    this.perks = const <String>[],
    this.perksAr = const <String>[],
    this.iconName = 'military_tech',
    this.color = 'C8FF38',
    this.enabled = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String nameAr;
  final int minimumPoints;
  final int? maximumPoints;
  final List<String> perks;
  final List<String> perksAr;
  final String iconName;
  final String color;
  final bool enabled;
  final int sortOrder;

  bool containsPoints(int points) =>
      points >= minimumPoints &&
      (maximumPoints == null || points <= maximumPoints!);

  factory AbuLevel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuLevel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      nameAr: data['nameAr'] as String? ?? '',
      minimumPoints: (data['minimumPoints'] as num? ?? 0).toInt(),
      maximumPoints: (data['maximumPoints'] as num?)?.toInt(),
      perks: (data['perks'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      perksAr: (data['perksAr'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      iconName: data['iconName'] as String? ?? 'military_tech',
      color: data['color'] as String? ?? 'C8FF38',
      enabled: data['enabled'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'nameAr': nameAr.trim(),
    'minimumPoints': minimumPoints,
    'maximumPoints': maximumPoints,
    'perks': perks
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(),
    'perksAr': perksAr
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(),
    'iconName': iconName,
    'color': color,
    'enabled': enabled,
    'sortOrder': sortOrder,
  };
}

class AbuLoyaltyReward {
  const AbuLoyaltyReward({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.description,
    required this.descriptionAr,
    required this.imageUrl,
    required this.category,
    required this.cost,
    required this.stock,
    required this.memberOnly,
    required this.enabled,
    required this.startsAt,
    required this.endsAt,
    required this.fulfilmentType,
    this.status = 'active',
    this.unlimitedStock = false,
    this.perUserLimit = 1,
  });

  final String id;
  final String title;
  final String titleAr;
  final String description;
  final String descriptionAr;
  final String imageUrl;
  final String category;
  final int cost;
  final int stock;
  final bool unlimitedStock;
  final int perUserLimit;
  final bool memberOnly;
  final bool enabled;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String fulfilmentType;
  final String status;

  bool get isAvailable {
    final now = DateTime.now();
    return enabled &&
        const {'active', 'live'}.contains(status) &&
        (startsAt == null || !now.isBefore(startsAt!)) &&
        (endsAt == null || now.isBefore(endsAt!)) &&
        (unlimitedStock || stock > 0);
  }

  factory AbuLoyaltyReward.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final status = data['status'] as String? ?? '';
    return AbuLoyaltyReward(
      id: doc.id,
      title: data['title'] as String? ?? '',
      titleAr: data['titleAr'] as String? ?? '',
      description: data['description'] as String? ?? '',
      descriptionAr: data['descriptionAr'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      category: data['category'] as String? ?? 'general',
      cost: (data['cost'] as num? ?? 0).toInt(),
      stock: (data['stock'] as num? ?? 0).toInt(),
      unlimitedStock: data['unlimitedStock'] as bool? ?? false,
      perUserLimit: (data['perUserLimit'] as num? ?? 1).toInt(),
      memberOnly: data['memberOnly'] as bool? ?? false,
      enabled:
          data['enabled'] as bool? ?? const ['active', 'live'].contains(status),
      startsAt: _optionalDate(data['availableFrom'] ?? data['startsAt']),
      endsAt: _optionalDate(data['availableUntil'] ?? data['endsAt']),
      fulfilmentType: data['fulfilmentType'] as String? ?? 'manual',
      status: status.isEmpty
          ? ((data['enabled'] as bool? ?? true) ? 'active' : 'disabled')
          : status,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title.trim(),
    'titleAr': titleAr.trim(),
    'description': description.trim(),
    'descriptionAr': descriptionAr.trim(),
    'imageUrl': imageUrl.trim(),
    'category': category,
    'cost': cost,
    'stock': stock,
    'unlimitedStock': unlimitedStock,
    'perUserLimit': perUserLimit,
    'memberOnly': memberOnly,
    'enabled': enabled,
    'status': enabled ? (status == 'live' ? 'live' : 'active') : 'disabled',
    'availableFrom': startsAt == null ? null : Timestamp.fromDate(startsAt!),
    'availableUntil': endsAt == null ? null : Timestamp.fromDate(endsAt!),
    'fulfilmentType': fulfilmentType,
  };
}

class AbuRewardRedemption {
  const AbuRewardRedemption({
    required this.id,
    required this.rewardId,
    required this.rewardTitle,
    required this.cost,
    required this.status,
    required this.createdAt,
    this.userId = '',
    this.userDisplayName = '',
    this.note = '',
    this.fulfilledAt,
    this.updatedAt,
  });

  final String id;
  final String rewardId;
  final String rewardTitle;
  final int cost;
  final String status;
  final DateTime createdAt;
  final String userId;
  final String userDisplayName;
  final String note;
  final DateTime? fulfilledAt;
  final DateTime? updatedAt;

  factory AbuRewardRedemption.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuRewardRedemption(
      id: doc.id,
      rewardId: data['rewardId'] as String? ?? '',
      rewardTitle: data['rewardTitle'] as String? ?? '',
      cost: (data['cost'] as num? ?? 0).toInt(),
      status: data['status'] as String? ?? 'pending',
      createdAt: _date(data['createdAt']),
      userId: data['userId'] as String? ?? '',
      userDisplayName:
          data['userDisplayName'] as String? ??
          data['username'] as String? ??
          '',
      note: data['statusNote'] as String? ?? data['note'] as String? ?? '',
      fulfilledAt: _optionalDate(data['fulfilledAt']),
      updatedAt: _optionalDate(data['updatedAt']),
    );
  }

  factory AbuRewardRedemption.fromMap(Map<String, dynamic> data) {
    return AbuRewardRedemption(
      id: (data['id'] ?? '').toString(),
      rewardId: (data['rewardId'] ?? data['reward_id'] ?? '').toString(),
      rewardTitle: (data['rewardTitle'] ?? data['reward_title'] ?? '')
          .toString(),
      cost: (data['cost'] as num? ?? 0).toInt(),
      status: (data['status'] ?? 'pending').toString(),
      createdAt: _date(data['createdAt'] ?? data['created_at']),
      userId: (data['userId'] ?? data['user_id'] ?? '').toString(),
      userDisplayName:
          (data['userDisplayName'] ?? data['user_display_name'] ?? '')
              .toString(),
      note: (data['note'] ?? data['adminNote'] ?? '').toString(),
      fulfilledAt: _optionalDate(data['fulfilledAt'] ?? data['fulfilled_at']),
      updatedAt: _optionalDate(data['updatedAt'] ?? data['updated_at']),
    );
  }
}

class AbuPlayerCard {
  const AbuPlayerCard({
    required this.id,
    required this.playerName,
    required this.playerNameAr,
    required this.imageUrl,
    required this.teamName,
    required this.teamLogoUrl,
    required this.position,
    required this.rating,
    required this.rarity,
    required this.stats,
    required this.description,
    required this.descriptionAr,
    required this.unlocked,
    required this.enabled,
    required this.sourceChallengeId,
    this.unlockedAt,
  });

  final String id;
  final String playerName;
  final String playerNameAr;
  final String imageUrl;
  final String teamName;
  final String teamLogoUrl;
  final String position;
  final int rating;
  final String rarity;
  final Map<String, int> stats;
  final String description;
  final String descriptionAr;
  final bool unlocked;
  final bool enabled;
  final DateTime? unlockedAt;
  final String sourceChallengeId;

  factory AbuPlayerCard.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool unlocked = false,
    DateTime? unlockedAt,
    String? sourceChallengeId,
  }) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawStats = data['stats'] as Map<String, dynamic>? ?? const {};
    return AbuPlayerCard(
      id: doc.id,
      playerName:
          data['playerName'] as String? ?? data['title'] as String? ?? '',
      playerNameAr: data['playerNameAr'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      teamName: data['teamName'] as String? ?? '',
      teamLogoUrl: data['teamLogoUrl'] as String? ?? '',
      position: data['position'] as String? ?? '',
      rating: (data['rating'] as num? ?? 0).toInt(),
      rarity: data['rarity'] as String? ?? 'common',
      stats: rawStats.map(
        (key, value) => MapEntry(key, (value as num? ?? 0).toInt()),
      ),
      description: data['description'] as String? ?? '',
      descriptionAr: data['descriptionAr'] as String? ?? '',
      unlocked: unlocked,
      enabled: data['enabled'] as bool? ?? true,
      unlockedAt: unlockedAt,
      sourceChallengeId:
          sourceChallengeId ?? data['sourceChallengeId'] as String? ?? '',
    );
  }

  factory AbuPlayerCard.fromMap(Map<String, dynamic> data) {
    final rawStats = data['stats'];
    final stats = rawStats is Map
        ? Map<String, dynamic>.from(rawStats).map(
            (key, value) => MapEntry(
              key,
              value is num ? value.toInt() : int.tryParse('$value') ?? 0,
            ),
          )
        : const <String, int>{};
    return AbuPlayerCard(
      id: (data['id'] ?? '').toString(),
      playerName: (data['playerName'] ?? data['player_name'] ?? '').toString(),
      playerNameAr: (data['playerNameAr'] ?? data['player_name_ar'] ?? '')
          .toString(),
      imageUrl: (data['imageUrl'] ?? data['card_image_url'] ?? '').toString(),
      teamName: (data['teamName'] ?? data['team'] ?? '').toString(),
      teamLogoUrl: (data['teamLogoUrl'] ?? data['team_logo_url'] ?? '')
          .toString(),
      position: (data['position'] ?? '').toString(),
      rating: (data['rating'] as num? ?? 0).toInt(),
      rarity: (data['rarity'] ?? data['card_tier'] ?? 'common').toString(),
      stats: stats,
      description: (data['description'] ?? '').toString(),
      descriptionAr: (data['descriptionAr'] ?? data['description_ar'] ?? '')
          .toString(),
      unlocked: data['unlocked'] as bool? ?? false,
      enabled: data['enabled'] as bool? ?? true,
      sourceChallengeId:
          (data['sourceChallengeId'] ?? data['source_challenge_id'] ?? '')
              .toString(),
      unlockedAt: _optionalDate(data['unlockedAt'] ?? data['unlocked_at']),
    );
  }

  Map<String, dynamic> toMap() => {
    'playerName': playerName.trim(),
    'playerNameAr': playerNameAr.trim(),
    'imageUrl': imageUrl.trim(),
    'teamName': teamName.trim(),
    'teamLogoUrl': teamLogoUrl.trim(),
    'position': position.trim(),
    'rating': rating,
    'rarity': rarity,
    'stats': stats,
    'description': description.trim(),
    'descriptionAr': descriptionAr.trim(),
    'enabled': enabled,
    'sourceChallengeId': sourceChallengeId.trim(),
  };
}

class ExclusiveVideo {
  const ExclusiveVideo({
    required this.id,
    required this.youtubeId,
    required this.title,
    this.description = '',
    required this.thumbnailUrl,
    required this.videoUrl,
    required this.publishedAt,
    this.isUnlisted = true,
    this.memberOnly = false,
    this.viewCount = 0,
  });

  final String id;
  final String youtubeId;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String videoUrl;
  final DateTime publishedAt;
  final bool isUnlisted;
  final bool memberOnly;
  final int viewCount;

  factory ExclusiveVideo.fromJson(Map<String, dynamic> json) {
    return ExclusiveVideo(
      id: json['id']?.toString() ?? '',
      youtubeId: json['youtube_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
      videoUrl: json['video_url']?.toString() ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.now(),
      isUnlisted: json['is_unlisted'] == true,
      memberOnly: json['member_only'] == true,
      viewCount: (json['view_count'] ?? 0).toInt(),
    );
  }
}
