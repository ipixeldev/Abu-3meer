import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  int milliseconds => DateTime.fromMillisecondsSinceEpoch(milliseconds),
  _ => DateTime.fromMillisecondsSinceEpoch(0),
};

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
  });

  final String uid;
  final String email;
  final String username;
  final String displayName;
  final String country;
  final String supportedTeam;
  final String avatarUrl;
  final String role;
  final double membershipMultiplier;
  final int totalPoints;
  final int monthlyPoints;
  final int seasonPoints;
  final bool suspended;

  bool get onboardingComplete =>
      username.isNotEmpty && displayName.isNotEmpty && supportedTeam.isNotEmpty;
  bool get isAdmin => role == 'admin' || role == 'superAdmin';
  bool get canManageContent =>
      isAdmin || role == 'editor' || role == 'contentManager';
  bool get canModerate => isAdmin || role == 'moderator';
  bool get canManageRoles => isAdmin;
  bool get isYouTubeMember => membershipMultiplier > 1;

  AbuUserProfile copyWith({
    int? totalPoints,
    int? monthlyPoints,
    int? seasonPoints,
    double? membershipMultiplier,
  }) => AbuUserProfile(
    uid: uid,
    email: email,
    username: username,
    displayName: displayName,
    country: country,
    supportedTeam: supportedTeam,
    avatarUrl: avatarUrl,
    role: role,
    membershipMultiplier: membershipMultiplier ?? this.membershipMultiplier,
    totalPoints: totalPoints ?? this.totalPoints,
    monthlyPoints: monthlyPoints ?? this.monthlyPoints,
    seasonPoints: seasonPoints ?? this.seasonPoints,
    suspended: suspended,
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
      supportedTeam: data['supportedTeam'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      role: data['role'] as String? ?? 'user',
      membershipMultiplier: (data['membershipMultiplier'] as num? ?? 1)
          .toDouble(),
      totalPoints: (data['totalPoints'] as num? ?? 0).toInt(),
      monthlyPoints: (data['monthlyPoints'] as num? ?? 0).toInt(),
      seasonPoints: (data['seasonPoints'] as num? ?? 0).toInt(),
      suspended: data['suspended'] as bool? ?? false,
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
      kind: kind,
      title:
          data['title'] as String? ??
          (kind == 'playerCard' ? 'Find the Player Card' : 'Secret phrase'),
      description: data['description'] as String? ?? '',
      rewardPoints: (data['rewardPoints'] as num? ?? 0).toInt(),
      status: data['status'] as String? ?? 'draft',
      videoUrl: data['videoUrl'] as String? ?? '',
      availableFrom: _date(data['availableFrom']),
      availableUntil: _date(data['availableUntil']),
    );
  }
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
  });

  final String id;
  final String title;
  final String body;
  final String imageUrl;
  final String linkUrl;
  final String authorName;
  final DateTime publishedAt;

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
    );
  }
}

class AbuComment {
  const AbuComment({
    required this.id,
    required this.userName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String userName;
  final String body;
  final DateTime createdAt;

  factory AbuComment.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AbuComment(
      id: doc.id,
      userName: data['userName'] as String? ?? 'Fan',
      body: data['body'] as String? ?? '',
      createdAt: _date(data['createdAt']),
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
    this.homeLogoUrl = '',
    this.awayLogoUrl = '',
    this.homeScore,
    this.awayScore,
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final DateTime kickoffAt;
  final DateTime predictionOpensAt;
  final DateTime predictionClosesAt;
  final String status;
  final String homeLogoUrl;
  final String awayLogoUrl;
  final int? homeScore;
  final int? awayScore;

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
      homeLogoUrl: data['homeLogoUrl'] as String? ?? '',
      awayLogoUrl: data['awayLogoUrl'] as String? ?? '',
      homeScore: (data['homeScore'] as num?)?.toInt(),
      awayScore: (data['awayScore'] as num?)?.toInt(),
    );
  }
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
    return PointLedgerEntry(
      id: doc.id,
      sourceType: data['sourceType'] as String? ?? '',
      sourceId: data['sourceId'] as String? ?? '',
      basePoints: (data['basePoints'] as num? ?? 0).toInt(),
      multiplier: (data['multiplier'] as num? ?? 1).toDouble(),
      finalPoints: (data['finalPoints'] as num? ?? 0).toInt(),
      reason: data['reason'] as String? ?? '',
      createdAt: _date(data['createdAt']),
    );
  }
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
  });

  final String uid;
  final String username;
  final String avatarUrl;
  final String supportedTeam;
  final int monthlyPoints;
  final int seasonPoints;
  final bool isMember;

  factory LeaderboardEntry.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return LeaderboardEntry(
      uid: doc.id,
      username: data['username'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
      supportedTeam: data['supportedTeam'] as String? ?? '',
      monthlyPoints: (data['monthlyPoints'] as num? ?? 0).toInt(),
      seasonPoints: (data['seasonPoints'] as num? ?? 0).toInt(),
      isMember: data['isMember'] as bool? ?? false,
    );
  }
}
