// Central app state management using ChangeNotifier.
// All demo state lives here — no backend, all in-memory with optional persistence.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../models/match.dart';
import '../models/challenge.dart';
import '../data/mock_users.dart';
import '../data/mock_matches.dart';
import '../data/mock_challenges.dart';
import '../data/mock_achievements.dart';
import '../data/mock_rewards_notifications.dart';

/// Events for XP/rank animations (UI can listen and animate).
class XpGainEvent {
  final int amount;
  final String source;
  final String? referenceId;
  final int newTotalXp;
  final int newLevel;
  final int rankChange;
  final int previousRank;
  final int newRank;

  const XpGainEvent({
    required this.amount,
    required this.source,
    this.referenceId,
    required this.newTotalXp,
    required this.newLevel,
    this.rankChange = 0,
    this.previousRank = 0,
    this.newRank = 0,
  });
}

class LoyaltyGainEvent {
  final int amount;
  final String source;
  final String? referenceId;
  final int newBalance;

  const LoyaltyGainEvent({
    required this.amount,
    required this.source,
    this.referenceId,
    required this.newBalance,
  });
}

class AchievementUnlockEvent {
  final String achievementId;
  final String name;
  final int xpReward;
  final int loyaltyReward;

  const AchievementUnlockEvent({
    required this.achievementId,
    required this.name,
    required this.xpReward,
    required this.loyaltyReward,
  });
}

class StreakUpdateEvent {
  final int newStreak;
  final bool isMilestone;
  final int? milestoneValue;

  const StreakUpdateEvent({
    required this.newStreak,
    this.isMilestone = false,
    this.milestoneValue,
  });
}

/// Main app state — ChangeNotifier for reactive UI.
class AppState extends ChangeNotifier {
  // ─── Auth / Current User ──────────────────────────────────────
  User? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _authError;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get authError => _authError;

  // ─── Demo Data Repositories (in-memory) ───────────────────────
  final List<User> _allUsers = List.from(_mockUsers);
  final List<Match> _allMatches = List.from(mockMatches);
  final List<Challenge> _allChallenges = List.from(mockChallenges);
  final List<Achievement> _allAchievements = List.from(mockAchievements);
  final List<LoyaltyReward> _allRewards = List.from(mockRewards);
  final List<Notification> _allNotifications = List.from(mockNotifications);
  final List<Transaction> _allTransactions = List.from(mockActivity);
  final List<SuspiciousActivity> _suspiciousActivities = List.from(
    mockSuspiciousActivity,
  );
  final List<AdminAction> _adminActions = List.from(mockAdminActions);

  // User-specific maps (keyed by userId)
  final Map<String, Map<PredictionType, dynamic>> _userPredictions = {};
  final Map<String, UserMatchPredictions> _userMatchPredictions = {};
  final Map<String, UserChallengeProgress> _userChallengeProgress = {};
  final Map<String, UserAchievement> _userAchievements = {};
  final List<RewardRedemption> _userRedemptions = List.from(
    demoUserRedemptions,
  );

  // ─── UI State ─────────────────────────────────────────────────
  int _selectedNavIndex = 0;
  int _selectedAdminNavIndex = 0;
  bool _showDemoMode = false;
  DemoScenario _activeDemoScenario = DemoScenario.none;
  ThemeMode _themeMode = ThemeMode.dark;
  String _language = 'en';

  int get selectedNavIndex => _selectedNavIndex;
  int get selectedAdminNavIndex => _selectedAdminNavIndex;
  bool get showDemoMode => _showDemoMode;
  DemoScenario get activeDemoScenario => _activeDemoScenario;
  ThemeMode get themeMode => _themeMode;
  String get language => _language;

  // ─── Event Streams (for animations) ───────────────────────────
  final List<ValueChanged<XpGainEvent>> _xpListeners = [];
  final List<ValueChanged<LoyaltyGainEvent>> _loyaltyListeners = [];
  final List<ValueChanged<AchievementUnlockEvent>> _achievementListeners = [];
  final List<ValueChanged<StreakUpdateEvent>> _streakListeners = [];

  // ─── Init / Persistence ───────────────────────────────────────
  static const String _prefsUserId = 'demo_current_user_id';
  static const String _prefsDemoScenario = 'demo_active_scenario';

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Restore demo user if any
      final savedUserId = prefs.getString(_prefsUserId);
      if (savedUserId != null) {
        final user = _allUsers.firstWhere(
          (u) => u.id == savedUserId,
          orElse: () => _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10'),
        );
        _currentUser = user;
        _isAuthenticated = true;
      }

      // Restore demo scenario
      final savedScenario = prefs.getInt(_prefsDemoScenario) ?? 0;
      _activeDemoScenario = DemoScenario.values[savedScenario];
      if (_activeDemoScenario != DemoScenario.none) {
        _applyDemoScenario(_activeDemoScenario);
      }

      // Load user-specific data
      if (_currentUser != null) {
        _loadUserData(_currentUser!.id);
      }
    } catch (e) {
      debugPrint('AppState init error: $e');
      // Fallback to demo user
      _currentUser = _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10');
      _isAuthenticated = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  void _loadUserData(String userId) {
    // Load predictions
    _userMatchPredictions[userId] = UserMatchPredictions(
      userId: userId,
      matchId: getCurrentClasico()?.id ?? '',
      predictions: [],
      isLocked: false,
    );

    // Load challenge progress
    for (final c in _allChallenges) {
      final key = '${c.id}_$userId';
      if (demoUserChallengeProgress.containsKey(key)) {
        _userChallengeProgress[key] = demoUserChallengeProgress[key]!;
      } else if (demoUserChallengeProgress.containsKey(c.id)) {
        _userChallengeProgress[key] = demoUserChallengeProgress[c.id]!;
      }
    }

    // Load achievements
    for (final a in _allAchievements) {
      final key = '${a.id}_$userId';
      if (demoUserAchievements.containsKey(key)) {
        _userAchievements[key] = demoUserAchievements[key]!;
      } else if (demoUserAchievements.containsKey(a.id)) {
        _userAchievements[key] = demoUserAchievements[a.id]!;
      }
    }
  }

  void _applyDemoScenario(DemoScenario scenario) {
    switch (scenario) {
      case DemoScenario.newUser:
        _currentUser = null;
        _isAuthenticated = false;
        break;
      case DemoScenario.activeFan:
        _currentUser = _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10');
        _isAuthenticated = true;
        break;
      case DemoScenario.matchday:
        _currentUser = _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10');
        _isAuthenticated = true;
        // Ensure El Clásico is open
        final clasico = _allMatches.firstWhere(
          (m) => m.id == 'mtc_clasico_2024_08_24',
        );
        final idx = _allMatches.indexOf(clasico);
        _allMatches[idx] = clasico.copyWith(
          status: MatchStatus.predictionsOpen,
        );
        break;
      case DemoScenario.results:
        _currentUser = _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10');
        _isAuthenticated = true;
        break;
      case DemoScenario.admin:
        final adminUser = _mockUsers
            .firstWhere((u) => u.id == 'usr_mohammed_legend')
            .copyWith(isAdmin: true);
        _currentUser = adminUser;
        _isAuthenticated = true;
        break;
      case DemoScenario.none:
        break;
    }
  }

  Future<void> _persistUserId(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) {
      await prefs.setString(_prefsUserId, userId);
    } else {
      await prefs.remove(_prefsUserId);
    }
  }

  Future<void> _persistDemoScenario(DemoScenario scenario) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDemoScenario, scenario.index);
  }

  // ─── Auth Actions ─────────────────────────────────────────────
  Future<bool> login(
    String email,
    String password, {
    bool rememberMe = false,
  }) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final user = _allUsers.firstWhere(
        (u) => u.email.toLowerCase() == email.toLowerCase(),
        orElse: () => throw Exception('User not found'),
      );

      // Demo: any password works if user exists
      if (password.length >= 4) {
        _currentUser = user;
        _isAuthenticated = true;
        _loadUserData(user.id);
        await _persistUserId(user.id);
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        throw Exception('Invalid password');
      }
    } catch (e) {
      _authError = 'Invalid email or password';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 600));
    _currentUser = _mockUsers.firstWhere((u) => u.id == 'usr_ahmed10');
    _isAuthenticated = true;
    _loadUserData(_currentUser!.id);
    await _persistUserId(_currentUser!.id);
    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<bool> loginWithApple() async {
    return loginWithGoogle(); // Same demo behavior
  }

  Future<bool> register(RegistrationData data) async {
    _isLoading = true;
    _authError = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1000));

    try {
      if (!data.isValid) {
        throw Exception('Please check all fields');
      }

      // Check username/email uniqueness
      if (_allUsers.any(
        (u) => u.username.toLowerCase() == data.username.toLowerCase(),
      )) {
        throw Exception('Username already taken');
      }
      if (_allUsers.any(
        (u) => u.email.toLowerCase() == data.email.toLowerCase(),
      )) {
        throw Exception('Email already registered');
      }

      final newUser = User(
        id: 'usr_${data.username.toLowerCase()}',
        username: data.username,
        email: data.email,
        displayName: data.displayName,
        avatarUrl: data.avatarUrl,
        countryCode: data.countryCode,
        team: data.team,
        joinedAt: DateTime.now(),
        xp: 0,
        loyaltyPoints: 0,
        level: 1,
      );

      _allUsers.add(newUser);
      _currentUser = newUser;
      _isAuthenticated = true;
      _loadUserData(newUser.id);
      await _persistUserId(newUser.id);

      // Grant first prediction achievement immediately on first prediction (handled elsewhere)
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void logout() {
    _currentUser = null;
    _isAuthenticated = false;
    _selectedNavIndex = 0;
    _persistUserId(null);
    notifyListeners();
  }

  // ─── User Profile Updates ─────────────────────────────────────
  void updateProfile({
    String? displayName,
    String? countryCode,
    String? avatarUrl,
    Team? team,
  }) {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      displayName: displayName,
      countryCode: countryCode,
      avatarUrl: avatarUrl,
      team: team,
    );
    // Update in all users list
    final idx = _allUsers.indexWhere((u) => u.id == _currentUser!.id);
    if (idx >= 0) _allUsers[idx] = _currentUser!;
    notifyListeners();
  }

  // ─── XP / Progression ─────────────────────────────────────────
  void addXp(
    int amount, {
    required String source,
    String? referenceId,
    int rankChange = 0,
    int previousRank = 0,
    int newRank = 0,
  }) {
    if (_currentUser == null) return;

    final oldLevel = _currentUser!.level;
    final oldXp = _currentUser!.xp;
    final newXp = oldXp + amount;
    final newLevel = _calculateLevel(newXp);

    _currentUser = _currentUser!.copyWith(
      xp: newXp,
      level: newLevel,
      seasonRank: newRank > 0 ? newRank : _currentUser!.seasonRank,
    );

    // Update in all users list
    final idx = _allUsers.indexWhere((u) => u.id == _currentUser!.id);
    if (idx >= 0) _allUsers[idx] = _currentUser!;

    // Notify listeners for animation
    final event = XpGainEvent(
      amount: amount,
      source: source,
      referenceId: referenceId,
      newTotalXp: newXp,
      newLevel: newLevel,
      rankChange: rankChange,
      previousRank: previousRank,
      newRank: newRank,
    );
    for (final listener in _xpListeners) {
      listener(event);
    }

    // Check level up achievements
    if (newLevel > oldLevel) {
      _checkLevelAchievements(newLevel);
    }

    notifyListeners();
  }

  int _calculateLevel(int xp) {
    // Level formula: XP required = 1000 * level^1.5 roughly
    for (int lvl = 50; lvl >= 1; lvl--) {
      final required = (1000 * lvl * lvl * 0.8).round();
      if (xp >= required) return lvl;
    }
    return 1;
  }

  void _checkLevelAchievements(int newLevel) {
    for (final ach in _allAchievements.where(
      (a) => a.requirementType == 'level',
    )) {
      if (newLevel >= ach.requirement) {
        unlockAchievement(ach.id);
      }
    }
  }

  void addLoyalty(int amount, {required String source, String? referenceId}) {
    if (_currentUser == null) return;

    final newBalance = _currentUser!.loyaltyPoints + amount;
    _currentUser = _currentUser!.copyWith(loyaltyPoints: newBalance);

    final idx = _allUsers.indexWhere((u) => u.id == _currentUser!.id);
    if (idx >= 0) _allUsers[idx] = _currentUser!;

    final event = LoyaltyGainEvent(
      amount: amount,
      source: source,
      referenceId: referenceId,
      newBalance: newBalance,
    );
    for (final listener in _loyaltyListeners) {
      listener(event);
    }

    notifyListeners();
  }

  // ─── Streak ───────────────────────────────────────────────────
  void updateStreak(int newStreak) {
    if (_currentUser == null) return;
    final oldStreak = _currentUser!.currentStreak;
    _currentUser = _currentUser!.copyWith(
      currentStreak: newStreak,
      longestStreak: newStreak > _currentUser!.longestStreak
          ? newStreak
          : _currentUser!.longestStreak,
    );

    final idx = _allUsers.indexWhere((u) => u.id == _currentUser!.id);
    if (idx >= 0) _allUsers[idx] = _currentUser!;

    final isMilestone = [3, 7, 10, 20, 30].contains(newStreak);
    final event = StreakUpdateEvent(
      newStreak: newStreak,
      isMilestone: isMilestone,
      milestoneValue: isMilestone ? newStreak : null,
    );
    for (final listener in _streakListeners) {
      listener(event);
    }

    // Check streak achievements
    for (final ach in _allAchievements.where(
      (a) => a.requirementType == 'streak',
    )) {
      if (newStreak >= ach.requirement) {
        unlockAchievement(ach.id);
      }
    }

    notifyListeners();
  }

  // ─── Predictions ──────────────────────────────────────────────
  void setPrediction(String matchId, PredictionType type, dynamic value) {
    if (_currentUser == null) return;

    final key = '${_currentUser!.id}_$matchId';
    var preds = _userMatchPredictions[key];

    if (preds == null) {
      preds = UserMatchPredictions(
        userId: _currentUser!.id,
        matchId: matchId,
        predictions: [],
      );
    }

    final existingIndex = preds.predictions.indexWhere((p) => p.type == type);
    final config = getPredictionConfig(matchId);
    final xpReward = config?.xpRewards[type] ?? 0;

    final prediction = Prediction(
      id: 'pred_${_currentUser!.id}_$matchId_${type.name}',
      userId: _currentUser!.id,
      matchId: matchId,
      type: type,
      value: value,
      xpReward: xpReward,
      createdAt: DateTime.now(),
    );

    List<Prediction> updatedPredictions;
    if (existingIndex >= 0) {
      updatedPredictions = List.from(preds.predictions);
      updatedPredictions[existingIndex] = prediction;
    } else {
      updatedPredictions = [...preds.predictions, prediction];
    }

    final totalPotentialXp = updatedPredictions.fold(
      0,
      (a, p) => a + p.xpReward,
    );

    _userMatchPredictions[key] = preds.copyWith(
      predictions: updatedPredictions,
      totalPotentialXp: totalPotentialXp,
    );

    notifyListeners();
  }

  void lockPredictions(String matchId) {
    if (_currentUser == null) return;

    final key = '${_currentUser!.id}_$matchId';
    final preds = _userMatchPredictions[key];
    if (preds != null) {
      _userMatchPredictions[key] = preds.copyWith(
        isLocked: true,
        lockedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void unlockPredictionsForDemo(String matchId) {
    if (_currentUser == null) return;
    final key = '${_currentUser!.id}_$matchId';
    _userMatchPredictions.remove(key);
    notifyListeners();
  }

  UserMatchPredictions? getUserPredictions(String matchId) {
    if (_currentUser == null) return null;
    return _userMatchPredictions['${_currentUser!.id}_$matchId'];
  }

  // ─── Challenge Actions ────────────────────────────────────────
  bool attemptChallenge(String challengeId, String answer) {
    if (_currentUser == null) return false;

    final challenge = _allChallenges.firstWhere((c) => c.id == challengeId);
    final key = '${challengeId}_${_currentUser!.id}';
    var progress = _userChallengeProgress[key];

    if (progress == null) {
      progress = UserChallengeProgress(
        challengeId: challengeId,
        userId: _currentUser!.id,
      );
    }

    if (progress.completed) return false; // Already done
    if (progress.attemptsUsed >= challenge.maxAttempts) return false;

    final isCorrect = _checkChallengeAnswer(challenge, answer);
    final newAttemptsUsed = progress.attemptsUsed + 1;
    final isLastAttempt = newAttemptsUsed >= challenge.maxAttempts;
    final completed = isCorrect || isLastAttempt;

    int xpAwarded = 0;
    int loyaltyAwarded = 0;

    if (isCorrect) {
      xpAwarded = challenge.xpReward;
      loyaltyAwarded =
          (challenge.loyaltyReward * _currentUser!.loyaltyMultiplier).round();
      addXp(xpAwarded, source: 'challenge', referenceId: challengeId);
      addLoyalty(loyaltyAwarded, source: 'challenge', referenceId: challengeId);
    }

    final attempt = ChallengeAttempt(
      id: 'att_${DateTime.now().millisecondsSinceEpoch}',
      challengeId: challengeId,
      userId: _currentUser!.id,
      answer: answer,
      isCorrect: isCorrect,
      xpAwarded: xpAwarded,
      loyaltyAwarded: loyaltyAwarded,
      attemptedAt: DateTime.now(),
      attemptNumber: newAttemptsUsed,
    );

    _userChallengeProgress[key] = progress.copyWith(
      attemptsUsed: newAttemptsUsed,
      completed: completed,
      rewarded: isCorrect,
      completedAt: isCorrect ? DateTime.now() : null,
      attempts: [...progress.attempts, attempt],
    );

    notifyListeners();
    return isCorrect;
  }

  bool _checkChallengeAnswer(Challenge challenge, String answer) {
    switch (challenge.type) {
      case ChallengeType.secretPhrase:
      case ChallengeType.multipleChoice:
      case ChallengeType.knowledge:
      case ChallengeType.videoQuiz:
        return answer.trim().toLowerCase() ==
            challenge.correctAnswer.trim().toLowerCase();
      case ChallengeType.matchChallenge:
      case ChallengeType.prediction:
      case ChallengeType.streak:
        return answer.trim().toLowerCase() ==
            challenge.correctAnswer.trim().toLowerCase();
    }
  }

  UserChallengeProgress? getChallengeProgress(String challengeId) {
    if (_currentUser == null) return null;
    return _userChallengeProgress['${challengeId}_${_currentUser!.id}'];
  }

  // ─── Achievements ─────────────────────────────────────────────
  void unlockAchievement(String achievementId) {
    if (_currentUser == null) return;

    final key = '${achievementId}_${_currentUser!.id}';
    var ua = _userAchievements[key];

    if (ua == null) {
      ua = UserAchievement(
        achievementId: achievementId,
        userId: _currentUser!.id,
      );
    }

    if (ua.unlocked) return; // Already unlocked

    final achievement = _allAchievements.firstWhere(
      (a) => a.id == achievementId,
    );
    ua = ua.copyWith(
      currentProgress: achievement.requirement,
      unlocked: true,
      unlockedAt: DateTime.now(),
      notified: false,
    );

    _userAchievements[key] = ua;

    // Award XP and Loyalty
    addXp(
      achievement.xpReward,
      source: 'achievement',
      referenceId: achievementId,
    );
    addLoyalty(
      (achievement.loyaltyReward * _currentUser!.loyaltyMultiplier).round(),
      source: 'achievement',
      referenceId: achievementId,
    );

    // Notify for animation
    final event = AchievementUnlockEvent(
      achievementId: achievementId,
      name: achievement.name,
      xpReward: achievement.xpReward,
      loyaltyReward: achievement.loyaltyReward,
    );
    for (final listener in _achievementListeners) {
      listener(event);
    }

    notifyListeners();
  }

  void updateAchievementProgress(String achievementId, int progress) {
    if (_currentUser == null) return;
    final key = '${achievementId}_${_currentUser!.id}';
    var ua = _userAchievements[key];
    if (ua == null) {
      ua = UserAchievement(
        achievementId: achievementId,
        userId: _currentUser!.id,
      );
    }
    final achievement = _allAchievements.firstWhere(
      (a) => a.id == achievementId,
    );
    ua = ua.copyWith(
      currentProgress: progress.clamp(0, achievement.requirement),
    );
    _userAchievements[key] = ua;

    if (progress >= achievement.requirement && !ua.unlocked) {
      unlockAchievement(achievementId);
    }

    notifyListeners();
  }

  UserAchievement? getUserAchievement(String achievementId) {
    if (_currentUser == null) return null;
    return _userAchievements['${achievementId}_${_currentUser!.id}'];
  }

  List<UserAchievement> getAllUserAchievements() {
    if (_currentUser == null) return [];
    return _allAchievements.map((a) {
      return _userAchievements['${a.id}_${_currentUser!.id}'] ??
          UserAchievement(achievementId: a.id, userId: _currentUser!.id);
    }).toList();
  }

  // ─── Rewards / Loyalty Store ──────────────────────────────────
  bool redeemReward(String rewardId) {
    if (_currentUser == null) return false;

    final reward = _allRewards.firstWhere((r) => r.id == rewardId);
    if (!reward.canRedeem) return false;
    if (_currentUser!.loyaltyPoints < reward.loyaltyCost) return false;

    _currentUser = _currentUser!.copyWith(
      loyaltyPoints: _currentUser!.loyaltyPoints - reward.loyaltyCost,
    );

    final idx = _allUsers.indexWhere((u) => u.id == _currentUser!.id);
    if (idx >= 0) _allUsers[idx] = _currentUser!;

    // Update reward stock
    final rewardIdx = _allRewards.indexWhere((r) => r.id == rewardId);
    if (rewardIdx >= 0 && _allRewards[rewardIdx].stock > 0) {
      _allRewards[rewardIdx] = _allRewards[rewardIdx].copyWith(
        stock: _allRewards[rewardIdx].stock - 1,
        timesRedeemed: _allRewards[rewardIdx].timesRedeemed + 1,
      );
    }

    // Record redemption
    _userRedemptions.add(
      RewardRedemption(
        id: 'red_${DateTime.now().millisecondsSinceEpoch}',
        userId: _currentUser!.id,
        rewardId: rewardId,
        loyaltySpent: reward.loyaltyCost,
        redeemedAt: DateTime.now(),
        status: RedemptionStatus.pending,
      ),
    );

    addLoyalty(
      -reward.loyaltyCost,
      source: 'redemption',
      referenceId: rewardId,
    );
    notifyListeners();
    return true;
  }

  // ─── Notifications ────────────────────────────────────────────
  void markNotificationRead(String notificationId) {
    final idx = _allNotifications.indexWhere((n) => n.id == notificationId);
    if (idx >= 0) {
      _allNotifications[idx] = _allNotifications[idx].copyWith(read: true);
      notifyListeners();
    }
  }

  void markAllNotificationsRead() {
    for (int i = 0; i < _allNotifications.length; i++) {
      if (_allNotifications[i].userId == _currentUser?.id) {
        _allNotifications[i] = _allNotifications[i].copyWith(read: true);
      }
    }
    notifyListeners();
  }

  List<Notification> getUserNotifications() {
    if (_currentUser == null) return [];
    return _allNotifications.where((n) => n.userId == _currentUser!.id).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  int getUnreadCount() {
    if (_currentUser == null) return 0;
    return _allNotifications
        .where((n) => n.userId == _currentUser!.id && !n.read)
        .length;
  }

  // ─── Activity History ─────────────────────────────────────────
  List<Transaction> getUserActivity({TransactionType? filter}) {
    if (_currentUser == null) return [];
    var txns =
        _allTransactions.where((t) => t.userId == _currentUser!.id).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (filter != null) {
      txns = txns.where((t) => t.type == filter).toList();
    }
    return txns;
  }

  // ─── Navigation ───────────────────────────────────────────────
  void setNavIndex(int index) {
    _selectedNavIndex = index;
    notifyListeners();
  }

  void setAdminNavIndex(int index) {
    _selectedAdminNavIndex = index;
    notifyListeners();
  }

  // ─── Demo Mode ────────────────────────────────────────────────
  void setDemoScenario(DemoScenario scenario) {
    _activeDemoScenario = scenario;
    _showDemoMode = scenario != DemoScenario.none;
    _applyDemoScenario(scenario);
    _persistDemoScenario(scenario);
    notifyListeners();
  }

  void resetDemo() {
    _activeDemoScenario = DemoScenario.none;
    _showDemoMode = false;
    _persistDemoScenario(DemoScenario.none);
    logout();
    notifyListeners();
  }

  // ─── Admin Actions (simulated) ────────────────────────────────
  void adminAdjustXp(String userId, int amount) {
    final idx = _allUsers.indexWhere((u) => u.id == userId);
    if (idx >= 0) {
      final user = _allUsers[idx];
      _allUsers[idx] = user.copyWith(xp: (user.xp + amount).clamp(0, 9999999));
      if (_currentUser?.id == userId) {
        _currentUser = _allUsers[idx];
      }
      _recordAdminAction('adjustXp', userId, 'Adjusted XP by $amount', {
        'amount': amount,
      });
      notifyListeners();
    }
  }

  void adminAdjustLoyalty(String userId, int amount) {
    final idx = _allUsers.indexWhere((u) => u.id == userId);
    if (idx >= 0) {
      final user = _allUsers[idx];
      _allUsers[idx] = user.copyWith(
        loyaltyPoints: (user.loyaltyPoints + amount).clamp(0, 9999999),
      );
      if (_currentUser?.id == userId) {
        _currentUser = _allUsers[idx];
      }
      _recordAdminAction(
        'adjustLoyalty',
        userId,
        'Adjusted Loyalty by $amount',
        {'amount': amount},
      );
      notifyListeners();
    }
  }

  void adminCreateMatch(Match match) {
    _allMatches.add(match);
    _recordAdminAction(
      'createMatch',
      'system',
      'Created match ${match.homeTeamName} vs ${match.awayTeamName}',
      {'matchId': match.id},
    );
    notifyListeners();
  }

  void adminUpdateMatch(Match match) {
    final idx = _allMatches.indexWhere((m) => m.id == match.id);
    if (idx >= 0) {
      _allMatches[idx] = match;
      _recordAdminAction('updateMatch', 'system', 'Updated match ${match.id}', {
        'matchId': match.id,
      });
      notifyListeners();
    }
  }

  void adminClosePredictions(String matchId) {
    final idx = _allMatches.indexWhere((m) => m.id == matchId);
    if (idx >= 0) {
      _allMatches[idx] = _allMatches[idx].copyWith(
        status: MatchStatus.predictionsLocked,
      );
      _recordAdminAction(
        'closePredictions',
        'system',
        'Closed predictions for $matchId',
        {'matchId': matchId},
      );
      notifyListeners();
    }
  }

  void adminEnterResult(
    String matchId,
    int homeScore,
    int awayScore, {
    String? firstScorerId,
    String? manOfMatchId,
  }) {
    final idx = _allMatches.indexWhere((m) => m.id == matchId);
    if (idx >= 0) {
      _allMatches[idx] = _allMatches[idx].copyWith(
        status: MatchStatus.finished,
        homeScore: homeScore,
        awayScore: awayScore,
        firstScorerId: firstScorerId,
        manOfMatchId: manOfMatchId,
        bothTeamsScored: homeScore > 0 && awayScore > 0,
      );
      _recordAdminAction(
        'enterResult',
        'system',
        'Entered result for $matchId',
        {'matchId': matchId, 'homeScore': homeScore, 'awayScore': awayScore},
      );
      notifyListeners();
    }
  }

  void adminCreateChallenge(Challenge challenge) {
    _allChallenges.add(challenge);
    _recordAdminAction(
      'createChallenge',
      'system',
      'Created challenge: ${challenge.title}',
      {'challengeId': challenge.id},
    );
    notifyListeners();
  }

  void adminUpdateChallenge(Challenge challenge) {
    final idx = _allChallenges.indexWhere((c) => c.id == challenge.id);
    if (idx >= 0) {
      _allChallenges[idx] = challenge;
      _recordAdminAction(
        'updateChallenge',
        'system',
        'Updated challenge: ${challenge.title}',
        {'challengeId': challenge.id},
      );
      notifyListeners();
    }
  }

  void adminCreateReward(LoyaltyReward reward) {
    _allRewards.add(reward);
    _recordAdminAction(
      'createReward',
      'system',
      'Created reward: ${reward.name}',
      {'rewardId': reward.id},
    );
    notifyListeners();
  }

  void adminUpdateReward(LoyaltyReward reward) {
    final idx = _allRewards.indexWhere((r) => r.id == reward.id);
    if (idx >= 0) {
      _allRewards[idx] = reward;
      _recordAdminAction(
        'updateReward',
        'system',
        'Updated reward: ${reward.name}',
        {'rewardId': reward.id},
      );
      notifyListeners();
    }
  }

  void adminCreateAchievement(Achievement achievement) {
    _allAchievements.add(achievement);
    _recordAdminAction(
      'createAchievement',
      'system',
      'Created achievement: ${achievement.name}',
      {'achievementId': achievement.id},
    );
    notifyListeners();
  }

  void adminUpdateAchievement(Achievement achievement) {
    final idx = _allAchievements.indexWhere((a) => a.id == achievement.id);
    if (idx >= 0) {
      _allAchievements[idx] = achievement;
      _recordAdminAction(
        'updateAchievement',
        'system',
        'Updated achievement: ${achievement.name}',
        {'achievementId': achievement.id},
      );
      notifyListeners();
    }
  }

  void adminWarnUser(String userId) {
    final idx = _allUsers.indexWhere((u) => u.id == userId);
    if (idx >= 0) {
      _allUsers[idx] = _allUsers[idx].copyWith(status: UserStatus.warned);
      _recordAdminAction('warnUser', userId, 'Warned user', {});
      notifyListeners();
    }
  }

  void adminSuspendUser(String userId) {
    final idx = _allUsers.indexWhere((u) => u.id == userId);
    if (idx >= 0) {
      _allUsers[idx] = _allUsers[idx].copyWith(status: UserStatus.suspended);
      _recordAdminAction('suspendUser', userId, 'Suspended user', {});
      notifyListeners();
    }
  }

  void adminBanUser(String userId) {
    final idx = _allUsers.indexWhere((u) => u.id == userId);
    if (idx >= 0) {
      _allUsers[idx] = _allUsers[idx].copyWith(status: UserStatus.banned);
      _recordAdminAction('banUser', userId, 'Banned user', {});
      notifyListeners();
    }
  }

  void adminReviewSuspicious(
    String activityId,
    SuspiciousStatus status, {
    String? notes,
  }) {
    final idx = _suspiciousActivities.indexWhere((a) => a.id == activityId);
    if (idx >= 0) {
      final adminId = _currentUser?.id ?? 'admin_creator';
      _suspiciousActivities[idx] = _suspiciousActivities[idx].copyWith(
        status: status,
        reviewedBy: adminId,
        reviewedAt: DateTime.now(),
        resolutionNotes: notes,
      );
      _recordAdminAction(
        'reviewSuspicious',
        'system',
        'Reviewed suspicious activity $activityId',
        {'activityId': activityId, 'status': status.name},
      );
      notifyListeners();
    }
  }

  void _recordAdminAction(
    AdminActionType type,
    String targetUserId,
    String description,
    Map<String, dynamic> changes,
  ) {
    _adminActions.add(
      AdminAction(
        id: 'adm_${DateTime.now().millisecondsSinceEpoch}',
        adminId: _currentUser?.id ?? 'admin_creator',
        type: type,
        targetUserId: targetUserId,
        description: description,
        changes: changes,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ─── Getters for Admin / Data ─────────────────────────────────
  List<User> get allUsers => List.unmodifiable(_allUsers);
  List<Match> get allMatches => List.unmodifiable(_allMatches);
  List<Challenge> get allChallenges => List.unmodifiable(_allChallenges);
  List<Achievement> get allAchievements => List.unmodifiable(_allAchievements);
  List<LoyaltyReward> get allRewards => List.unmodifiable(_allRewards);
  List<Notification> get allNotifications =>
      List.unmodifiable(_allNotifications);
  List<Transaction> get allTransactions => List.unmodifiable(_allTransactions);
  List<SuspiciousActivity> get suspiciousActivities =>
      List.unmodifiable(_suspiciousActivities);
  List<AdminAction> get adminActions => List.unmodifiable(_adminActions);
  List<RewardRedemption> get userRedemptions =>
      List.unmodifiable(_userRedemptions);

  Match? getMatchById(String id) {
    try {
      return _allMatches.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  Challenge? getChallengeById(String id) {
    try {
      return _allChallenges.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  User? getUserById(String id) {
    try {
      return _allUsers.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  // ─── Event Listener Registration ──────────────────────────────
  void addXpListener(ValueChanged<XpGainEvent> listener) =>
      _xpListeners.add(listener);
  void removeXpListener(ValueChanged<XpGainEvent> listener) =>
      _xpListeners.remove(listener);
  void addLoyaltyListener(ValueChanged<LoyaltyGainEvent> listener) =>
      _loyaltyListeners.add(listener);
  void removeLoyaltyListener(ValueChanged<LoyaltyGainEvent> listener) =>
      _loyaltyListeners.remove(listener);
  void addAchievementListener(ValueChanged<AchievementUnlockEvent> listener) =>
      _achievementListeners.add(listener);
  void removeAchievementListener(
    ValueChanged<AchievementUnlockEvent> listener,
  ) => _achievementListeners.remove(listener);
  void addStreakListener(ValueChanged<StreakUpdateEvent> listener) =>
      _streakListeners.add(listener);
  void removeStreakListener(ValueChanged<StreakUpdateEvent> listener) =>
      _streakListeners.remove(listener);
}

enum DemoScenario { none, newUser, activeFan, matchday, results, admin }
