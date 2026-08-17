// User, profile, and authentication models.

import 'package:flutter/material.dart';

enum Team { barcelona, realMadrid }

enum MembershipTier { none, member, ultraMember }

enum UserStatus { active, warned, suspended, banned }

/// Core user model.
class User {
  final String id;
  final String username;
  final String email;
  final String displayName;
  final String? avatarUrl;
  final String countryCode; // ISO 3166-1 alpha-2
  final Team team;
  final MembershipTier membershipTier;
  final UserStatus status;
  final DateTime joinedAt;
  final DateTime? lastActiveAt;

  // Progression
  final int xp;
  final int loyaltyPoints;
  final int level;
  final int currentStreak;
  final int longestStreak;
  final int correctPredictions;
  final int totalPredictions;
  final int achievementsUnlocked;
  final int seasonRank;
  final int monthlyRank;
  final int allTimeRank;

  // Admin
  final bool isAdmin;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    this.avatarUrl,
    required this.countryCode,
    required this.team,
    this.membershipTier = MembershipTier.none,
    this.status = UserStatus.active,
    required this.joinedAt,
    this.lastActiveAt,
    this.xp = 0,
    this.loyaltyPoints = 0,
    this.level = 1,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.correctPredictions = 0,
    this.totalPredictions = 0,
    this.achievementsUnlocked = 0,
    this.seasonRank = 0,
    this.monthlyRank = 0,
    this.allTimeRank = 0,
    this.isAdmin = false,
  });

  /// Copy with for immutable updates.
  User copyWith({
    String? id,
    String? username,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? countryCode,
    Team? team,
    MembershipTier? membershipTier,
    UserStatus? status,
    DateTime? joinedAt,
    DateTime? lastActiveAt,
    int? xp,
    int? loyaltyPoints,
    int? level,
    int? currentStreak,
    int? longestStreak,
    int? correctPredictions,
    int? totalPredictions,
    int? achievementsUnlocked,
    int? seasonRank,
    int? monthlyRank,
    int? allTimeRank,
    bool? isAdmin,
  }) => User(
    id: id ?? this.id,
    username: username ?? this.username,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    countryCode: countryCode ?? this.countryCode,
    team: team ?? this.team,
    membershipTier: membershipTier ?? this.membershipTier,
    status: status ?? this.status,
    joinedAt: joinedAt ?? this.joinedAt,
    lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    xp: xp ?? this.xp,
    loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
    level: level ?? this.level,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    correctPredictions: correctPredictions ?? this.correctPredictions,
    totalPredictions: totalPredictions ?? this.totalPredictions,
    achievementsUnlocked: achievementsUnlocked ?? this.achievementsUnlocked,
    seasonRank: seasonRank ?? this.seasonRank,
    monthlyRank: monthlyRank ?? this.monthlyRank,
    allTimeRank: allTimeRank ?? this.allTimeRank,
    isAdmin: isAdmin ?? this.isAdmin,
  );

  double get predictionAccuracy =>
      totalPredictions > 0 ? correctPredictions / totalPredictions : 0.0;

  String get countryFlag => _countryFlag(countryCode);

  static String _countryFlag(String code) {
    if (code.length != 2) return '🏳️';
    final offset = 0x1F1E6 - 0x41; // Regional indicator symbols
    return String.fromCharCodes(
      code.toUpperCase().codeUnits.map((c) => c + offset),
    );
  }

  /// Team display name.
  String get teamName => team == Team.barcelona ? 'Barcelona' : 'Real Madrid';

  /// Team short code.
  String get teamCode => team == Team.barcelona ? 'BAR' : 'RMA';

  /// Membership display name.
  String get membershipLabel {
    switch (membershipTier) {
      case MembershipTier.none:
        return 'Free';
      case MembershipTier.member:
        return 'Member';
      case MembershipTier.ultraMember:
        return 'Ultra Member';
    }
  }

  /// Level name from level number.
  String get levelName {
    const names = ['Rookie', 'Fan', 'Ultra', 'Legend', 'GOAT'];
    final idx = (level - 1).clamp(0, names.length - 1);
    return names[idx];
  }

  /// XP required for next level.
  int get xpForNextLevel {
    // Exponential curve: 1000 * level^1.5 roughly
    return (1000 * (level + 1) * (level + 1) * 0.8).round();
  }

  /// XP progress within current level (0.0 - 1.0).
  double get levelProgress {
    final currentLevelXp = (1000 * level * level * 0.8).round();
    final nextLevelXp = xpForNextLevel;
    final progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
    return progress.clamp(0.0, 1.0);
  }

  /// Loyalty multiplier from membership (NOT applied to XP — product rule).
  double get loyaltyMultiplier {
    switch (membershipTier) {
      case MembershipTier.none:
        return 1.0;
      case MembershipTier.member:
        return 1.5;
      case MembershipTier.ultraMember:
        return 2.0;
    }
  }
}

/// Public profile (subset of user shown to other fans).
class PublicProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String countryCode;
  final Team team;
  final MembershipTier membershipTier;
  final int xp;
  final int level;
  final int seasonRank;
  final int currentStreak;
  final int correctPredictions;
  final int totalPredictions;
  final int achievementsUnlocked;
  final List<String> recentAchievementIds;
  final DateTime joinedAt;

  const PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.countryCode,
    required this.team,
    required this.membershipTier,
    required this.xp,
    required this.level,
    required this.seasonRank,
    required this.currentStreak,
    required this.correctPredictions,
    required this.totalPredictions,
    required this.achievementsUnlocked,
    required this.recentAchievementIds,
    required this.joinedAt,
  });

  factory PublicProfile.fromUser(User user) => PublicProfile(
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    countryCode: user.countryCode,
    team: user.team,
    membershipTier: user.membershipTier,
    xp: user.xp,
    level: user.level,
    seasonRank: user.seasonRank,
    currentStreak: user.currentStreak,
    correctPredictions: user.correctPredictions,
    totalPredictions: user.totalPredictions,
    achievementsUnlocked: user.achievementsUnlocked,
    recentAchievementIds: [], // Filled separately
    joinedAt: user.joinedAt,
  );

  double get predictionAccuracy =>
      totalPredictions > 0 ? correctPredictions / totalPredictions : 0.0;

  String get countryFlag => User._countryFlag(countryCode);
  String get teamName => team == Team.barcelona ? 'Barcelona' : 'Real Madrid';
  String get levelName {
    const names = ['Rookie', 'Fan', 'Ultra', 'Legend', 'GOAT'];
    final idx = (level - 1).clamp(0, names.length - 1);
    return names[idx];
  }
}

/// Simple credentials for demo login.
class Credentials {
  final String email;
  final String password;
  final bool rememberMe;

  const Credentials({
    required this.email,
    required this.password,
    this.rememberMe = false,
  });
}

/// Registration form data.
class RegistrationData {
  // Account
  final String username;
  final String email;
  final String password;
  final String confirmPassword;

  // Profile
  final String displayName;
  final String countryCode;
  final String? avatarUrl;

  // Team
  final Team team;

  const RegistrationData({
    required this.username,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.displayName,
    required this.countryCode,
    this.avatarUrl,
    required this.team,
  });

  bool get passwordsMatch => password == confirmPassword;
  bool get isValid =>
      username.length >= 3 &&
      email.contains('@') &&
      password.length >= 8 &&
      passwordsMatch &&
      displayName.isNotEmpty &&
      countryCode.length == 2;
}
