// Challenge, achievement, reward, and loyalty models.

import 'package:flutter/material.dart';

import 'user.dart';

enum ChallengeType {
  secretPhrase,
  multipleChoice,
  matchChallenge,
  videoQuiz,
  knowledge,
  streak,
  prediction,
}

enum ChallengeStatus { draft, scheduled, live, ended, archived }

enum ChallengeCategory { video, match, general, special }

/// Challenge model.
class Challenge {
  final String id;
  final String title;
  final String description;
  final ChallengeType type;
  final ChallengeCategory category;
  final ChallengeStatus status;
  final String? videoUrl; // YouTube video ID or URL placeholder
  final String correctAnswer; // For secret phrase / multiple choice
  final List<String> options; // For multiple choice
  final int xpReward;
  final int loyaltyReward;
  final bool memberOnly;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime createdAt;
  final String createdBy; // Admin user ID
  final int maxAttempts;
  final int? matchId; // Link to match for match challenges

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.category,
    this.status = ChallengeStatus.draft,
    this.videoUrl,
    required this.correctAnswer,
    this.options = const [],
    required this.xpReward,
    required this.loyaltyReward,
    this.memberOnly = false,
    required this.startAt,
    required this.endAt,
    required this.createdAt,
    required this.createdBy,
    this.maxAttempts = 3,
    this.matchId,
  });

  Challenge copyWith({
    String? id,
    String? title,
    String? description,
    ChallengeType? type,
    ChallengeCategory? category,
    ChallengeStatus? status,
    String? videoUrl,
    String? correctAnswer,
    List<String>? options,
    int? xpReward,
    int? loyaltyReward,
    bool? memberOnly,
    DateTime? startAt,
    DateTime? endAt,
    DateTime? createdAt,
    String? createdBy,
    int? maxAttempts,
    int? matchId,
  }) => Challenge(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    type: type ?? this.type,
    category: category ?? this.category,
    status: status ?? this.status,
    videoUrl: videoUrl ?? this.videoUrl,
    correctAnswer: correctAnswer ?? this.correctAnswer,
    options: options ?? this.options,
    xpReward: xpReward ?? this.xpReward,
    loyaltyReward: loyaltyReward ?? this.loyaltyReward,
    memberOnly: memberOnly ?? this.memberOnly,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    createdAt: createdAt ?? this.createdAt,
    createdBy: createdBy ?? this.createdBy,
    maxAttempts: maxAttempts ?? this.maxAttempts,
    matchId: matchId ?? this.matchId,
  );

  bool get isLiveNow {
    final now = DateTime.now();
    return status == ChallengeStatus.live &&
        now.isAfter(startAt) &&
        now.isBefore(endAt);
  }

  bool get isUpcoming =>
      status == ChallengeStatus.scheduled && DateTime.now().isBefore(startAt);
  bool get isEnded =>
      status == ChallengeStatus.ended || DateTime.now().isAfter(endAt);

  String get typeLabel {
    switch (type) {
      case ChallengeType.secretPhrase:
        return 'Secret Phrase';
      case ChallengeType.multipleChoice:
        return 'Multiple Choice';
      case ChallengeType.matchChallenge:
        return 'Match Challenge';
      case ChallengeType.videoQuiz:
        return 'Video Quiz';
      case ChallengeType.knowledge:
        return 'Knowledge';
      case ChallengeType.streak:
        return 'Streak';
      case ChallengeType.prediction:
        return 'Prediction';
    }
  }

  String get categoryLabel {
    switch (category) {
      case ChallengeCategory.video:
        return 'Video';
      case ChallengeCategory.match:
        return 'Match';
      case ChallengeCategory.general:
        return 'General';
      case ChallengeCategory.special:
        return 'Special';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case ChallengeCategory.video:
        return Icons.play_circle_outline;
      case ChallengeCategory.match:
        return Icons.sports_soccer;
      case ChallengeCategory.general:
        return Icons.quiz_outlined;
      case ChallengeCategory.special:
        return Icons.star_outline;
    }
  }
}

/// User's attempt at a challenge.
class ChallengeAttempt {
  final String id;
  final String challengeId;
  final String userId;
  final String answer;
  final bool isCorrect;
  final int xpAwarded;
  final int loyaltyAwarded;
  final DateTime attemptedAt;
  final int attemptNumber;

  const ChallengeAttempt({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.answer,
    required this.isCorrect,
    required this.xpAwarded,
    required this.loyaltyAwarded,
    required this.attemptedAt,
    required this.attemptNumber,
  });
}

/// User's challenge progress.
class UserChallengeProgress {
  final String challengeId;
  final String userId;
  final int attemptsUsed;
  final bool completed;
  final bool rewarded;
  final DateTime? completedAt;
  final List<ChallengeAttempt> attempts;

  const UserChallengeProgress({
    required this.challengeId,
    required this.userId,
    this.attemptsUsed = 0,
    this.completed = false,
    this.rewarded = false,
    this.completedAt,
    this.attempts = const [],
  });

  UserChallengeProgress copyWith({
    String? challengeId,
    String? userId,
    int? attemptsUsed,
    bool? completed,
    bool? rewarded,
    DateTime? completedAt,
    List<ChallengeAttempt>? attempts,
  }) => UserChallengeProgress(
    challengeId: challengeId ?? this.challengeId,
    userId: userId ?? this.userId,
    attemptsUsed: attemptsUsed ?? this.attemptsUsed,
    completed: completed ?? this.completed,
    rewarded: rewarded ?? this.rewarded,
    completedAt: completedAt ?? this.completedAt,
    attempts: attempts ?? this.attempts,
  );
}

/// Achievement model.
class Achievement {
  final String id;
  final String name;
  final String description;
  final String iconName; // Maps to icon asset or generated
  final AchievementCategory category;
  final int requirement; // Target value
  final String
  requirementType; // e.g., 'correct_predictions', 'streak', 'el_clasico_wins'
  final int xpReward;
  final int loyaltyReward;
  final bool isSecret; // Hidden until unlocked
  final int sortOrder;
  final DateTime createdAt;

  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.category,
    required this.requirement,
    required this.requirementType,
    this.xpReward = 0,
    this.loyaltyReward = 0,
    this.isSecret = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  String get categoryLabel {
    switch (category) {
      case AchievementCategory.predictions:
        return 'Predictions';
      case AchievementCategory.streaks:
        return 'Streaks';
      case AchievementCategory.special:
        return 'Special';
      case AchievementCategory.team:
        return 'Team';
      case AchievementCategory.loyalty:
        return 'Loyalty';
      case AchievementCategory.social:
        return 'Social';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case AchievementCategory.predictions:
        return Icons.target_outlined;
      case AchievementCategory.streaks:
        return Icons.local_fire_department_outlined;
      case AchievementCategory.special:
        return Icons.emoji_events_outlined;
      case AchievementCategory.team:
        return Icons.flag_outlined;
      case AchievementCategory.loyalty:
        return Icons.card_giftcard_outlined;
      case AchievementCategory.social:
        return Icons.people_outline;
    }
  }
}

enum AchievementCategory {
  predictions,
  streaks,
  special,
  team,
  loyalty,
  social,
}

/// User's achievement progress.
class UserAchievement {
  final String achievementId;
  final String userId;
  final int currentProgress;
  final bool unlocked;
  final DateTime? unlockedAt;
  final bool notified;

  const UserAchievement({
    required this.achievementId,
    required this.userId,
    this.currentProgress = 0,
    this.unlocked = false,
    this.unlockedAt,
    this.notified = false,
  });

  UserAchievement copyWith({
    String? achievementId,
    String? userId,
    int? currentProgress,
    bool? unlocked,
    DateTime? unlockedAt,
    bool? notified,
  }) => UserAchievement(
    achievementId: achievementId ?? this.achievementId,
    userId: userId ?? this.userId,
    currentProgress: currentProgress ?? this.currentProgress,
    unlocked: unlocked ?? this.unlocked,
    unlockedAt: unlockedAt ?? this.unlockedAt,
    notified: notified ?? this.notified,
  );
}

/// Loyalty reward in the store.
class LoyaltyReward {
  final String id;
  final String name;
  final String description;
  final String imageUrl; // Placeholder
  final int loyaltyCost;
  final int stock; // -1 for unlimited
  final bool active;
  final RewardCategory category;
  final int sortOrder;
  final DateTime createdAt;
  final int timesRedeemed;

  const LoyaltyReward({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.loyaltyCost,
    this.stock = -1,
    this.active = true,
    required this.category,
    this.sortOrder = 0,
    required this.createdAt,
    this.timesRedeemed = 0,
  });

  bool get inStock => stock == -1 || stock > 0;
  bool get canRedeem => active && inStock;

  String get categoryLabel {
    switch (category) {
      case RewardCategory.merchandise:
        return 'Merchandise';
      case RewardCategory.credit:
        return 'Store Credit';
      case RewardCategory.exclusive:
        return 'Exclusive';
      case RewardCategory.digital:
        return 'Digital';
      case RewardCategory.experience:
        return 'Experience';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case RewardCategory.merchandise:
        return Icons.shopping_bag_outlined;
      case RewardCategory.credit:
        return Icons.credit_card_outlined;
      case RewardCategory.exclusive:
        return Icons.diamond_outlined;
      case RewardCategory.digital:
        return Icons.download_outlined;
      case RewardCategory.experience:
        return Icons.event_outlined;
    }
  }
}

enum RewardCategory { merchandise, credit, exclusive, digital, experience }

/// User's reward redemption.
class RewardRedemption {
  final String id;
  final String userId;
  final String rewardId;
  final int loyaltySpent;
  final DateTime redeemedAt;
  final RedemptionStatus status;

  const RewardRedemption({
    required this.id,
    required this.userId,
    required this.rewardId,
    required this.loyaltySpent,
    required this.redeemedAt,
    this.status = RedemptionStatus.pending,
  });
}

enum RedemptionStatus { pending, fulfilled, cancelled, shipped }

/// Notification model.
class Notification {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String message;
  final String? actionUrl; // Deep link
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const Notification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.actionUrl,
    this.read = false,
    required this.createdAt,
    this.metadata,
  });

  Notification copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? message,
    String? actionUrl,
    bool? read,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) => Notification(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    title: title ?? this.title,
    message: message ?? this.message,
    actionUrl: actionUrl ?? this.actionUrl,
    read: read ?? this.read,
    createdAt: createdAt ?? this.createdAt,
    metadata: metadata ?? this.metadata,
  );

  IconData get icon {
    switch (type) {
      case NotificationType.predictionsOpen:
        return Icons.sports_soccer;
      case NotificationType.predictionsClosing:
        return Icons.schedule;
      case NotificationType.achievementUnlocked:
        return Icons.emoji_events;
      case NotificationType.rankUp:
        return Icons.trending_up;
      case NotificationType.newChallenge:
        return Icons.quiz_outlined;
      case NotificationType.streakRisk:
        return Icons.local_fire_department;
      case NotificationType.matchResult:
        return Icons.flag;
      case NotificationType.rewardRedeemed:
        return Icons.card_giftcard;
      case NotificationType.system:
        return Icons.info_outline;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.predictionsOpen:
      case NotificationType.newChallenge:
        return AppColors.accentPrimary;
      case NotificationType.predictionsClosing:
      case NotificationType.streakRisk:
        return AppColors.error;
      case NotificationType.achievementUnlocked:
      case NotificationType.rankUp:
        return AppColors.success;
      case NotificationType.matchResult:
        return AppColors.accentSecondary;
      case NotificationType.rewardRedeemed:
        return AppColors.accentPrimary;
      case NotificationType.system:
        return AppColors.textMuted;
    }
  }
}

enum NotificationType {
  predictionsOpen,
  predictionsClosing,
  achievementUnlocked,
  rankUp,
  newChallenge,
  streakRisk,
  matchResult,
  rewardRedeemed,
  system,
}

/// XP / Loyalty transaction history.
class Transaction {
  final String id;
  final String userId;
  final TransactionType type;
  final int amount; // Positive for credit, negative for debit
  final int balanceAfter;
  final String description;
  final String? referenceId; // Match ID, Challenge ID, etc.
  final DateTime createdAt;
  final TransactionSource source;

  const Transaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.referenceId,
    required this.createdAt,
    required this.source,
  });

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;

  Color get color => isCredit ? AppColors.success : AppColors.error;
  IconData get icon {
    switch (source) {
      case TransactionSource.prediction:
        return Icons.sports_soccer;
      case TransactionSource.challenge:
        return Icons.quiz_outlined;
      case TransactionSource.achievement:
        return Icons.emoji_events;
      case TransactionSource.streak:
        return Icons.local_fire_department;
      case TransactionSource.redemption:
        return Icons.card_giftcard;
      case TransactionSource.admin:
        return Icons.admin_panel_settings;
      case TransactionSource.membership:
        return Icons.workspace_premium;
      case TransactionSource.daily:
        return Icons.calendar_today;
    }
  }
}

enum TransactionType { xp, loyalty }

enum TransactionSource {
  prediction,
  challenge,
  achievement,
  streak,
  redemption,
  admin,
  membership,
  daily,
}

/// Fan War aggregate stats.
class FanWarStats {
  final int barcaTotalXp;
  final int madridTotalXp;
  final int barcaActiveFans;
  final int madridActiveFans;
  final double barcaAvgXp;
  final double madridAvgXp;
  final int barcaWeeklyXp;
  final int madridWeeklyXp;
  final String? barcaTopContributorId;
  final String? madridTopContributorId;
  final int barcaTopContributorXp;
  final int madridTopContributorXp;
  final DateTime lastUpdated;

  const FanWarStats({
    required this.barcaTotalXp,
    required this.madridTotalXp,
    required this.barcaActiveFans,
    required this.madridActiveFans,
    required this.barcaAvgXp,
    required this.madridAvgXp,
    required this.barcaWeeklyXp,
    required this.madridWeeklyXp,
    this.barcaTopContributorId,
    this.madridTopContributorId,
    required this.barcaTopContributorXp,
    required this.madridTopContributorXp,
    required this.lastUpdated,
  });

  int get totalXp => barcaTotalXp + madridTotalXp;
  double get barcaPercentage => totalXp > 0 ? barcaTotalXp / totalXp : 0.5;
  double get madridPercentage => 1 - barcaPercentage;
  int get lead => (barcaTotalXp - madridTotalXp).abs();
  Team get leader =>
      barcaTotalXp > madridTotalXp ? Team.barcelona : Team.realMadrid;
  String get leadText {
    final leaderName = leader == Team.barcelona ? 'Barcelona' : 'Real Madrid';
    return '$leaderName leads by ${_format(lead)} XP';
  }

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Admin analytics snapshot.
class AdminAnalytics {
  final int totalUsers;
  final int activeToday;
  final int activeThisWeek;
  final int activeThisMonth;
  final int newUsersToday;
  final int newUsersThisWeek;
  final int newUsersThisMonth;
  final int predictionsToday;
  final int predictionsThisWeek;
  final int challengeEntriesToday;
  final int challengeEntriesThisWeek;
  final int youtubeMembers;
  final int totalXpDistributed;
  final int totalLoyaltyDistributed;
  final FanWarStats fanWarStats;
  final List<DailyMetric> dailyActiveUsers;
  final List<DailyMetric> newRegistrations;
  final List<DailyMetric> predictionParticipation;
  final List<DailyMetric> challengeParticipation;
  final List<DailyMetric> xpDistributed;
  final DateTime generatedAt;

  const AdminAnalytics({
    required this.totalUsers,
    required this.activeToday,
    required this.activeThisWeek,
    required this.activeThisMonth,
    required this.newUsersToday,
    required this.newUsersThisWeek,
    required this.newUsersThisMonth,
    required this.predictionsToday,
    required this.predictionsThisWeek,
    required this.challengeEntriesToday,
    required this.challengeEntriesThisWeek,
    required this.youtubeMembers,
    required this.totalXpDistributed,
    required this.totalLoyaltyDistributed,
    required this.fanWarStats,
    required this.dailyActiveUsers,
    required this.newRegistrations,
    required this.predictionParticipation,
    required this.challengeParticipation,
    required this.xpDistributed,
    required this.generatedAt,
  });
}

class DailyMetric {
  final DateTime date;
  final int value;

  const DailyMetric({required this.date, required this.value});
}

/// Suspicious activity flag for admin review.
class SuspiciousActivity {
  final String id;
  final String userId;
  final SuspiciousType type;
  final String description;
  final SuspiciousRisk risk;
  final DateTime detectedAt;
  final Map<String, dynamic> evidence;
  final SuspiciousStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? resolutionNotes;

  const SuspiciousActivity({
    required this.id,
    required this.userId,
    required this.type,
    required this.description,
    required this.risk,
    required this.detectedAt,
    required this.evidence,
    this.status = SuspiciousStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.resolutionNotes,
  });

  SuspiciousActivity copyWith({
    String? id,
    String? userId,
    SuspiciousType? type,
    String? description,
    SuspiciousRisk? risk,
    DateTime? detectedAt,
    Map<String, dynamic>? evidence,
    SuspiciousStatus? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? resolutionNotes,
  }) => SuspiciousActivity(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    type: type ?? this.type,
    description: description ?? this.description,
    risk: risk ?? this.risk,
    detectedAt: detectedAt ?? this.detectedAt,
    evidence: evidence ?? this.evidence,
    status: status ?? this.status,
    reviewedBy: reviewedBy ?? this.reviewedBy,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    resolutionNotes: resolutionNotes ?? this.resolutionNotes,
  );
}

enum SuspiciousType {
  multipleAttempts,
  unusualXpGain,
  repeatedRequests,
  impossibleStreak,
  botBehavior,
  accountSharing,
}

enum SuspiciousRisk { low, medium, high, critical }

enum SuspiciousStatus { pending, underReview, ignored, resolved, escalated }

/// Admin action log.
class AdminAction {
  final String id;
  final String adminId;
  final AdminActionType type;
  final String targetUserId;
  final String description;
  final Map<String, dynamic> changes;
  final DateTime createdAt;

  const AdminAction({
    required this.id,
    required this.adminId,
    required this.type,
    required this.targetUserId,
    required this.description,
    required this.changes,
    required this.createdAt,
  });
}

enum AdminActionType {
  adjustXp,
  adjustLoyalty,
  warnUser,
  suspendUser,
  banUser,
  unbanUser,
  createMatch,
  updateMatch,
  closePredictions,
  enterResult,
  createChallenge,
  updateChallenge,
  createReward,
  updateReward,
  createAchievement,
  updateAchievement,
  reviewSuspicious,
}
