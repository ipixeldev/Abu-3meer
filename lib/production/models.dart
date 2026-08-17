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
  bool get isYouTubeMember => membershipMultiplier > 1;

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
